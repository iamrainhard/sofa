#!/usr/bin/env python3
"""Local JSON-lines bridge. No third-party Python runtime packages. No telemetry."""
import hashlib
import ipaddress
import json
import os
import queue
import select
import socket
import ssl
import struct
import sys
import threading
import time
import urllib.request
import xml.etree.ElementTree as ET
from urllib.parse import urljoin, urlparse

MAX_PACKET = 1048576

def host_address(value):
    ip = ipaddress.ip_address(value)
    if ip.version != 4 or not ip.is_private or ip.is_unspecified or ip.is_multicast or ip.is_loopback:
        raise ValueError('Enter the TV’s private IPv4 address, for example 192.168.1.100.')
    return str(ip)

def discover_devices(timeout=3.0):
    """Bounded SSDP discovery. Only follow a reply back to its private sender."""
    query = ("M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\n"
             'MAN: "ssdp:discover"\r\nMX: 2\r\n'
             "ST: urn:schemas-upnp-org:device:MediaRenderer:1\r\n\r\n").encode()
    addresses = set()
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.settimeout(0.3)
        sock.sendto(query, ('239.255.255.250', 1900))
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline and len(addresses) < 12:
            try:
                data, sender = sock.recvfrom(8192)
                host = host_address(sender[0])
                headers = dict(line.split(':', 1) for line in data.decode(errors='replace').split('\r\n')[1:] if ':' in line)
                location = next((v.strip() for k, v in headers.items() if k.lower() == 'location'), '')
                parsed = urlparse(location)
                if parsed.scheme == 'http' and parsed.hostname == host and parsed.port == 18400:
                    addresses.add(host)
            except (socket.timeout, ValueError, OSError):
                continue
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, req, fp, code, msg, headers, newurl):
            return None
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
    found = []
    for host in sorted(addresses):
        try:
            with opener.open('http://' + host + ':18400/MediaServer/rendererdevicedesc.xml', timeout=1.5) as response:
                root = ET.fromstring(response.read(262144))
            found.append({'host': host, 'name': root.findtext('.//{*}friendlyName', 'VIDAA TV'),
                          'model': root.findtext('.//{*}modelName', '')})
        except (OSError, ValueError, ET.ParseError):
            continue
    return found


def credentials(device, timestamp=None):
    timestamp = int(time.time()) if timestamp is None else timestamp
    md5 = lambda s: hashlib.md5(s.encode()).hexdigest().upper()
    race = md5('38D65DC30F45109A369A86FCE866A85B$' + device)[:6]
    client = device + '$his$' + race + '_vidaacommon_001'
    username = 'his$' + str(timestamp ^ 0x569814772b03a968)
    n = sum(int(d) for d in str(timestamp)) % 10
    inner = md5('his' + str(n) + 'h!i@s#$v%i^d&a*a')[:6]
    return client, username, md5(str(timestamp) + '$' + inner)

def utf8(value):
    data = value.encode()
    if len(data) > 65535:
        raise ValueError('MQTT field too long')
    return struct.pack('!H', len(data)) + data

def packet(kind, body=b''):
    if len(body) > MAX_PACKET:
        raise ValueError('MQTT packet too large')
    length, encoded = len(body), bytearray([kind])
    while True:
        digit = length % 128
        length //= 128
        encoded.append(digit | (128 if length else 0))
        if not length:
            break
    return bytes(encoded) + body

def extract(buffer):
    if len(buffer) < 2:
        return None
    length, multiplier = 0, 1
    for i in range(1, min(len(buffer), 5)):
        digit = buffer[i]
        length += (digit & 127) * multiplier
        if length > MAX_PACKET:
            raise ValueError('TV response exceeds packet limit')
        if not digit & 128:
            end = i + 1 + length
            if len(buffer) < end:
                return None
            return buffer[0], bytes(buffer[i + 1:end]), bytes(buffer[end:])
        multiplier *= 128
    if len(buffer) >= 5:
        raise ValueError('Invalid MQTT remaining length')
    return None

class Bridge:
    def __init__(self, emit=None):
        self.event_lock = threading.Lock()
        self.emit = emit or (lambda value: print(json.dumps(value), flush=True))
        self.sock = None
        self.host = None
        self.client = None
        self.username = None
        self.buffer = b''
        self.authenticated = False
        self.acknowledged = False
        self.pending = None
        self.control_url = None
        self.last_ping = 0
        self.last_state_request = 0
        self.last_received = 0
        self.apps = []
        self.sources = []
        self.muted = None
        self.saved = {}
        self.pin_pending = False
        self.subscription_id = 0

    def event(self, kind, **values):
        with self.event_lock:
            self.emit(dict(event=kind, **values))

    def close(self):
        if self.sock:
            try:
                self.sock.close()
            except OSError:
                pass
        self.sock = None
        self.authenticated = False
        self.acknowledged = False
        self.buffer = b''

    def probe(self, host):
        self.host = host_address(host)
        self.control_url = None
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        url = 'http://' + self.host + ':18400/MediaServer/rendererdevicedesc.xml'
        with opener.open(url, timeout=4) as response:
            root = ET.fromstring(response.read(262144))
        def find(name):
            node = root.find('.//{*}' + name)
            return node.text if node is not None else ''
        for service in root.findall('.//{*}service'):
            if service.findtext('{*}serviceType', '').endswith(':RenderingControl:1'):
                candidate = urljoin(url, service.findtext('{*}controlURL', ''))
                parsed = urlparse(candidate)
                if parsed.hostname == self.host and parsed.port == 18400:
                    self.control_url = candidate
        self.event('device', name=find('friendlyName'), model=find('modelName'))
        if self.control_url:
            self.read_volume()

    def soap(self, action, values):
        if not self.control_url:
            raise ValueError('TV volume service is unavailable. Refresh the connection.')
        service = 'urn:schemas-upnp-org:service:RenderingControl:1'
        fields = ''.join('<{0}>{1}</{0}>'.format(k, v) for k, v in values.items())
        xml = ('<?xml version="1.0"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
               's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body><u:' + action +
               ' xmlns:u="' + service + '">' + fields + '</u:' + action + '></s:Body></s:Envelope>')
        request = urllib.request.Request(self.control_url, xml.encode(), {
            'Content-Type': 'text/xml; charset="utf-8"', 'SOAPACTION': '"' + service + '#' + action + '"'})
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        with opener.open(request, timeout=3) as response:
            return ET.fromstring(response.read(65536))

    def read_volume(self):
        values = {'InstanceID': 0, 'Channel': 'Master'}
        root = self.soap('GetVolume', values)
        volume = int(root.findtext('.//{*}CurrentVolume', '-1'))
        root = self.soap('GetMute', values)
        muted = root.findtext('.//{*}CurrentMute', '0') in ('1', 'true')
        if 0 <= volume <= 100:
            self.muted = muted
            self.event('volume', value=volume, muted=muted, source='readback')
            return volume

    def connect(self, command):
        self.close()
        self.host = host_address(command['host'])
        self.saved = command.get('saved') or {}
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
        context.check_hostname = False
        context.verify_mode = ssl.CERT_NONE  # Pinned before MQTT credentials are transmitted.
        base = os.path.join(os.path.dirname(__file__), 'certs')
        context.load_cert_chain(os.path.join(base, 'vidaa_client.pem'), os.path.join(base, 'vidaa_client.key'))
        raw = socket.create_connection((self.host, 36669), timeout=5)
        try:
            self.sock = context.wrap_socket(raw, server_hostname=self.host)
            fingerprint = hashlib.sha256(self.sock.getpeercert(binary_form=True)).hexdigest()
            trusted = command.get('fingerprint', '')
            if fingerprint != trusted:
                self.close()
                self.event('trust', fingerprint=fingerprint, changed=bool(trusted))
                return
            self.client, self.username, password = credentials(command['device'])
            if self.saved.get('accesstoken'):
                self.client = self.saved['client_id']
                self.username = self.saved['mqtt_username']
                elapsed = time.time() - self.saved.get('issued_at', 0)
                expiry = self.saved.get('accesstoken_duration_day', 7) * 86400
                if elapsed >= expiry and self.saved.get('refreshtoken'):
                    password = self.saved['refreshtoken']
                    self.pending = 'refresh_token'
                else:
                    password = self.saved['accesstoken']
                    self.pending = None
            else:
                self.pending = None
            body = utf8('MQTT') + bytes([4, 0xC2]) + struct.pack('!H', 30)
            body += utf8(self.client) + utf8(self.username) + utf8(password)
            self.sock.sendall(packet(0x10, body))
            self.sock.settimeout(1)
            self.last_ping = self.last_received = time.monotonic()
            self.event('status', value='connecting')
        except Exception:
            raw.close()
            self.close()
            raise

    def publish(self, service, path, value=''):
        if not self.sock or not self.acknowledged:
            raise ValueError('Connect to the TV first.')
        topic = '/remoteapp/tv/' + service + '/' + self.client + '/' + path
        payload = json.dumps(value, separators=(',', ':')) if isinstance(value, (dict, list)) else str(value)
        self.sock.sendall(packet(0x30, utf8(topic) + payload.encode()))

    def refresh(self):
        for service, path in [('ui_service', 'actions/gettvstate'), ('platform_service', 'actions/getvolume'),
                              ('ui_service', 'actions/sourcelist'), ('ui_service', 'actions/applist')]:
            self.publish(service, path)

    def subscribe(self):
        prefix = '/remoteapp/mobile/' + self.client
        topics = ['/remoteapp/mobile/broadcast/ui_service/state',
                  '/remoteapp/mobile/broadcast/ui_service/volume',
                  '/remoteapp/mobile/broadcast/platform_service/actions/volumechange']
        topics += [prefix + '/' + tail for tail in [
            'ui_service/data/sourcelist', 'ui_service/data/applist', 'ui_service/data/authentication',
            'ui_service/data/authenticationcode', 'platform_service/data/tokenissuance']]
        self.subscription_id = self.subscription_id % 65535 + 1
        self.sock.sendall(packet(0x82, struct.pack('!H', self.subscription_id) + b''.join(utf8(t) + b'\x00' for t in topics)))

    def receive(self, kind, body):
        if kind >> 4 == 2:
            if len(body) != 2 or body[1] != 0:
                self.close()
                self.event('error', message='TV rejected the connection. Re-pair this Mac in Connection settings.')
                return
            self.acknowledged = True
            self.subscribe()
        elif kind >> 4 == 9:
            # VIDAA deliberately refuses state/catalog subscriptions until PIN pairing.
            # Authentication and token channels must be available before we offer pairing.
            codes = list(body[2:])
            if len(codes) != 8 or any(codes[i] == 128 for i in (5, 6, 7)):
                self.event('error', message='TV refused the pairing response channel. Reconnect to try again.')
                self.close()
                self.event('status', value='offline')
                return
            self.event('status', value='ready' if self.authenticated else 'pairing')
            if self.pending == 'refresh_token':
                self.pending = None
                self.publish('platform_service', 'data/gettoken', {'refreshtoken': self.saved['refreshtoken']})
            if self.authenticated or self.saved.get('accesstoken'):
                self.refresh()
        elif kind >> 4 == 3:
            if len(body) < 2:
                raise ValueError('Truncated MQTT publish')
            length = struct.unpack('!H', body[:2])[0]
            if len(body) < 2 + length:
                raise ValueError('Truncated MQTT topic')
            topic = body[2:2 + length].decode()
            offset = 2 + length
            qos = (kind >> 1) & 3
            if qos:
                if len(body) < offset + 2:
                    raise ValueError('Missing MQTT packet identifier')
                identity = body[offset:offset + 2]
                offset += 2
                if qos != 1:
                    raise ValueError('Unsupported MQTT QoS')
                self.sock.sendall(packet(0x40, identity))
            try:
                payload = json.loads(body[offset:].decode())
            except (ValueError, UnicodeDecodeError):
                return
            self.message(topic, payload)

    def mark_ready(self):
        if not self.authenticated:
            self.authenticated = True
            self.event('status', value='ready')

    def message(self, topic, value):
        if topic.endswith('/tokenissuance') and isinstance(value, dict):
            if value.get('accesstoken'):
                saved = {k: value[k] for k in ('accesstoken', 'refreshtoken', 'accesstoken_duration_day',
                                             'refreshtoken_duration_day') if k in value}
                saved.update(client_id=self.client, mqtt_username=self.username, issued_at=time.time())
                self.saved = saved
                self.event('credentials', value=saved)
                self.mark_ready()
                self.subscribe()
        elif 'authentication' in topic and isinstance(value, dict):
            if value.get('result') == 1:
                self.mark_ready()
                self.pin_pending = False
                self.subscribe()
                self.publish('platform_service', 'data/gettoken', {'refreshtoken': ''})
                self.publish('ui_service', 'actions/authenticationcodeclose')
                self.refresh()
            elif self.pin_pending and 'result' in value:
                self.pin_pending = False
                self.event('error', message='The TV did not accept that code. Check the code shown on its screen.')
            else:
                self.event('status', value='pairing')
        elif topic.endswith('/applist'):
            items = value if isinstance(value, list) else value.get('list', value.get('apps', value.get('app_list', []))) if isinstance(value, dict) else []
            if isinstance(items, list):
                self.apps = [item for item in items if isinstance(item, dict)]
                self.event('apps', value=self.apps)
                if items:
                    self.mark_ready()
        elif topic.endswith('/sourcelist'):
            items = value if isinstance(value, list) else value.get('list', value.get('sources', value.get('source_list', []))) if isinstance(value, dict) else []
            if isinstance(items, list):
                self.sources = [item for item in items if isinstance(item, dict)]
                self.event('sources', value=self.sources)
                if items:
                    self.mark_ready()
        elif 'volume' in topic and isinstance(value, dict):
            if value.get('volume_type', 0) == 2:
                self.muted = value.get('volume_value') == 1
                self.event('mute', value=self.muted)
            else:
                volume = value.get('volume_value', value.get('volume', value.get('value')))
                try:
                    volume = int(volume)
                    if 0 <= volume <= 100:
                        self.event('volume', value=volume, muted=self.muted)
                except (ValueError, TypeError):
                    pass
        elif isinstance(value, dict) and topic.endswith('/state'):
            if value.get('statetype') in ('authentication', 'authenticationcode'):
                self.authenticated = False
                self.event('status', value='pairing')
            else:
                self.event('state', value=value)

    def command(self, command):
        action = command.get('action')
        if action == 'discover':
            def discover():
                try:
                    self.event('discovery', devices=discover_devices())
                except OSError:
                    self.event('discovery', devices=[], message='No TVs found. Check Local Network permission or enter the address manually.')
            threading.Thread(target=discover, daemon=True).start()
        elif action == 'probe':
            self.probe(command['host'])
        elif action == 'connect':
            self.connect(command)
        elif action == 'disconnect':
            self.close()
            self.event('status', value='offline')
        elif action == 'pair':
            self.publish('ui_service', 'actions/vidaa_app_connect', {'app_version': 2, 'connect_result': 0, 'device_type': 'Mobile App'})
            self.event('status', value='pairing')
        elif action == 'pin':
            pin = command.get('pin', '')
            if not pin.isascii() or not pin.isdigit() or not 4 <= len(pin) <= 8:
                raise ValueError('Enter the numeric pairing code shown on the TV.')
            self.pin_pending = True
            self.publish('ui_service', 'actions/authenticationcode', {'authNum': int(pin)})
        elif action == 'refresh':
            if self.control_url:
                self.read_volume()
            if self.acknowledged:
                self.refresh()
        elif action == 'read_volume':
            self.read_volume()
        elif action == 'volume':
            volume = int(command['value'])
            if not 0 <= volume <= 100:
                raise ValueError('Volume must be between 0 and 100.')
            if not self.authenticated:
                raise ValueError('Pair this Mac to change volume.')
            try:
                self.soap('SetVolume', {'InstanceID': 0, 'Channel': 'Master', 'DesiredVolume': volume})
                actual = self.read_volume()
                if 'request' in command:
                    self.event('volume_result', request=command['request'], value=actual)
            except Exception:
                if 'request' in command:
                    self.event('volume_result', request=command['request'], value=None)
                raise
        elif action == 'mute':
            if not self.authenticated:
                raise ValueError('Pair this Mac to change mute.')
            mute = bool(command['value'])
            self.soap('SetMute', {'InstanceID': 0, 'Channel': 'Master', 'DesiredMute': int(mute)})
            self.read_volume()
        elif action in ('key', 'source', 'app'):
            if not self.authenticated:
                raise ValueError('Pair this Mac before using remote controls.')
            if action == 'key':
                key = command.get('key', '')
                allowed = {'UP', 'DOWN', 'LEFT', 'RIGHT', 'OK', 'RETURNS', 'MENU', 'HOME', 'EXIT',
                           'VOLUMEUP', 'VOLUMEDOWN', 'MUTE', 'PLAY', 'PAUSE', 'STOP', 'FORWARDS', 'BACK',
                           'CHANNELUP', 'CHANNELDOWN', 'POWER', 'RED', 'GREEN', 'YELLOW', 'BLUE', 'SUBTITLE'} | set('0123456789')
                if key not in allowed:
                    raise ValueError('Unsupported key')
                self.publish('remote_service', 'actions/sendkey', 'KEY_' + key)
            elif action == 'source':
                index = int(command['index'])
                if not 0 <= index < len(self.sources):
                    raise ValueError('The input catalog changed. Refresh and try again.')
                item = self.sources[index]
                sourceid = item.get('sourceid', item.get('sourceId', item.get('id')))
                if sourceid is None:
                    raise ValueError('The TV did not provide an input identifier.')
                self.publish('ui_service', 'actions/changesource', {'sourceid': str(sourceid)})
            elif action == 'app':
                index = int(command['index'])
                if not 0 <= index < len(self.apps):
                    raise ValueError('The app catalog changed. Refresh and try again.')
                self.publish('ui_service', 'actions/launchapp', self.apps[index])
            self.event('sent', label=command.get('label', 'Command sent'))
        else:
            raise ValueError('Unknown bridge command')

    def tick(self):
        if not self.sock:
            return
        if select.select([self.sock], [], [], 0)[0] or self.sock.pending():
            data = self.sock.recv(65536)
            if not data:
                self.close()
                self.event('status', value='offline')
                return
            self.last_received = time.monotonic()
            self.buffer += data
            while True:
                result = extract(self.buffer)
                if result is None:
                    break
                kind, body, self.buffer = result
                self.receive(kind, body)
                if not self.sock:
                    break
        # Keep panel power fresh even when the TV remains network-connected in standby.
        if self.sock and self.authenticated and time.monotonic() - self.last_state_request > 10:
            self.publish('ui_service', 'actions/gettvstate')
            self.last_state_request = time.monotonic()
        if self.sock and time.monotonic() - self.last_ping > 15:
            self.sock.sendall(packet(0xC0))
            self.last_ping = time.monotonic()
        if self.sock and time.monotonic() - self.last_received > 45:
            self.close()
            self.event('error', message='TV stopped responding. Reconnect when the TV is awake.', disconnected=True)


def main():
    commands = queue.Queue()
    def reader():
        for line in sys.stdin:
            try:
                commands.put(json.loads(line))
            except ValueError:
                commands.put({'action': 'invalid'})
        commands.put(None)
    threading.Thread(target=reader, daemon=True).start()
    bridge = Bridge()
    while True:
        try:
            command = commands.get(timeout=0.05)
            if command is None:
                break
            try:
                bridge.command(command)
            except Exception as error:
                if command.get('action') == 'connect':
                    bridge.close()
                bridge.event('error', message=str(error))
        except queue.Empty:
            pass
        try:
            bridge.tick()
        except Exception as error:
            bridge.close()
            bridge.event('error', message='Connection interrupted: ' + str(error), disconnected=True)
    bridge.close()

if __name__ == '__main__':
    main()
