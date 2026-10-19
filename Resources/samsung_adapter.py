"""Experimental Tizen remote: pinned TLS WebSocket + optional UPnP volume.

No SmartThings account, developer mode, token files, or upstream token logging.
Only port 8002 is supported; never downgrade saved credentials to plaintext.
"""
import base64
import hashlib
import json
import queue
import socket
import ssl
import threading
import time
from urllib.parse import urlencode

import websocket
from bridge import host_address
from samsung_network import VolumeService, fetch

KEYS = {
    'UP': 'KEY_UP', 'DOWN': 'KEY_DOWN', 'LEFT': 'KEY_LEFT', 'RIGHT': 'KEY_RIGHT',
    'OK': 'KEY_ENTER', 'RETURNS': 'KEY_RETURN', 'HOME': 'KEY_HOME', 'MENU': 'KEY_MENU',
    'EXIT': 'KEY_EXIT', 'POWER': 'KEY_POWER', 'VOLUMEUP': 'KEY_VOLUP', 'VOLUMEDOWN': 'KEY_VOLDOWN',
    'MUTE': 'KEY_MUTE', 'PLAY': 'KEY_PLAY', 'PAUSE': 'KEY_PAUSE', 'STOP': 'KEY_STOP',
    'FORWARDS': 'KEY_FF', 'BACK': 'KEY_REWIND', 'CHANNELUP': 'KEY_CHUP', 'CHANNELDOWN': 'KEY_CHDOWN',
    'SUBTITLE': 'KEY_SUB_TITLE', 'RED': 'KEY_RED', 'GREEN': 'KEY_GREEN', 'YELLOW': 'KEY_YELLOW',
    'BLUE': 'KEY_BLUE', 'INPUT': 'KEY_SOURCE', **{str(i): f'KEY_{i}' for i in range(10)},
}


def tls_socket(host, port):
    raw = socket.create_connection((host, port), timeout=4)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE  # Fingerprint checked on THIS socket before HTTP/token bytes.
    try:
        return context.wrap_socket(raw, server_hostname=host)
    except Exception:
        raw.close()
        raise


class SamsungAdapter:
    def __init__(self, emit, socket_factory=tls_socket, ws_factory=websocket.create_connection,
                 volume_factory=VolumeService.discover, port=8002, approval_timeout=60):
        self.emit = emit
        self.socket_factory, self.ws_factory = socket_factory, ws_factory
        self.volume_factory, self.port = volume_factory, port
        self.approval_timeout = approval_timeout
        self.commands = queue.Queue(maxsize=128)
        self.closed = threading.Event()
        self.ws = self.transport = None
        self.ready = False
        self.host = None
        self.saved = {}
        self.apps = []
        self.volume_service = None
        self.probing = False
        self.generation = 0
        self.deadline = self.next_volume = self.last_key = self.next_ping = 0
        self.thread = threading.Thread(target=self._run, daemon=True)
        self.thread.start()

    def event(self, kind, **values):
        if not self.closed.is_set():
            self.emit(dict(event=kind, **values))

    def command(self, command):
        if not self.closed.is_set():
            self.commands.put_nowait(command)

    def tick(self):
        pass

    def _drop(self):
        self.ready = False
        self.generation += 1
        self.probing = False
        ws, self.ws = self.ws, None
        transport, self.transport = self.transport, None
        if ws:
            try:
                ws.abort()  # No blocking close handshake during cancellation.
            except OSError:
                pass
        if transport:
            try:
                transport.close()
            except OSError:
                pass

    def close(self):
        self.closed.set()
        self._drop()
        if threading.current_thread() is not self.thread:
            self.thread.join(timeout=0.3)

    def _run(self):
        try:
            while not self.closed.is_set():
                try:
                    command = self.commands.get_nowait()
                except queue.Empty:
                    command = None
                if command:
                    try:
                        self._command(command)
                    except Exception:
                        if command.get('action') == 'connect':
                            self._drop()
                            self.event('error', message='Samsung did not connect. Keep the TV awake on the same network and enable external device connections. This beta requires Tizen’s secure remote service.', disconnected=True)
                        else:
                            self.event('error', message='Samsung did not accept that command. Try again or reconnect.')
                if self.closed.is_set():
                    break
                if self.ws:
                    try:
                        data = self.ws.recv()
                        if not data or len(data) > 262144:
                            raise ValueError('Remote closed or oversized message')
                        self._message(json.loads(data))
                    except websocket.WebSocketTimeoutException:
                        pass
                    except Exception:
                        self._drop()
                        self.event('error', message='Samsung disconnected. Reconnect when the TV is awake.', disconnected=True)
                    if self.ws and not self.ready and time.monotonic() >= self.deadline:
                        self._drop()
                        self.event('status', value='pairing')
                        self.event('approval', waiting=False)
                        self.event('error', message='Approval timed out. Choose Try again, then select Allow on your TV. Check Device Connection Manager if Sofa was blocked.')
                    if self.ws and time.monotonic() >= self.next_ping:
                        try:
                            self.ws.ping()
                            self.next_ping = time.monotonic() + 20
                        except Exception:
                            self._drop()
                            self.event('error', message='Samsung disconnected. Reconnect when the TV is awake.', disconnected=True)
                    if self.ready and self.volume_service and time.monotonic() >= self.next_volume:
                        self._read_volume()
                else:
                    self.closed.wait(0.05)
        finally:
            self._drop()

    def _connect(self, command):
        self._drop()
        self.host = host_address(command['host'])
        self.saved = command.get('saved') or {}
        self.apps = []; self.volume_service = None
        transport = self.socket_factory(self.host, self.port)
        self.transport = transport
        fingerprint = hashlib.sha256(transport.getpeercert(binary_form=True)).hexdigest()
        trusted = str(command.get('fingerprint', '')).lower()
        if fingerprint != trusted:
            self._drop()
            self.event('trust', fingerprint=fingerprint, changed=bool(trusted))
            return
        if self.closed.is_set():
            self._drop(); return
        params = {'name': base64.b64encode(b'Sofa').decode()}
        token = self.saved.get('token')
        if isinstance(token, str) and 0 < len(token) <= 4096:
            params['token'] = token
        self.event('status', value='pairing')
        self.event('approval', waiting=True)
        self.deadline = time.monotonic() + self.approval_timeout
        # Supply the already-verified TLS socket; redirects are explicitly disabled.
        self.ws = self.ws_factory(f'wss://{self.host}:{self.port}/api/v2/channels/samsung.remote.control?{urlencode(params)}',
                                  socket=transport, timeout=4, suppress_origin=True, redirect_limit=0)
        self.ws.settimeout(0.1)
        self.next_ping = time.monotonic() + 20

    def _message(self, message):
        if not isinstance(message, dict):
            return
        event, data = message.get('event'), message.get('data', {})
        if event in ('ms.channel.unauthorized', 'ms.channel.timeOut'):
            self._drop()
            # Invalidate only this platform's saved token, not VIDAA/Android credentials.
            self.event('credentials', value={})
            self.event('status', value='pairing')
            self.event('approval', waiting=False)
            self.event('error', message='TV approval was denied or expired. Remove Sofa from the TV’s blocked devices if needed, then try again and choose Allow.')
        elif event == 'ms.channel.connect' and not self.ready:
            token = data.get('token') if isinstance(data, dict) else None
            if not token and isinstance(data, dict):
                # Some firmware returns the token on the matching client entry.
                for client in data.get('clients', []):
                    if isinstance(client, dict) and client.get('id') == data.get('id'):
                        token = client.get('attributes', {}).get('token')
            if isinstance(token, (str, int)) and 0 < len(str(token)) <= 4096:
                self.event('credentials', value={'token': str(token)})
            self.ready = True
            self.event('approval', waiting=False)
            self.event('status', value='ready')
            self.event('device', name='Samsung TV', model='Samsung · Tizen (experimental)')
            self.event('capabilities', absolute_volume=False, installed_apps=False)
            self._send({'method': 'ms.channel.emit', 'params': {'event': 'ed.installedApp.get', 'to': 'host'}})
            # Optional metadata/services cannot block successful pairing.
            self._probe_optional()
        elif event == 'ed.installedApp.get' and self.ready:
            items = data.get('data', []) if isinstance(data, dict) else []
            if isinstance(items, list):
                self.apps = [dict(name=str(i['name'])[:100], appId=str(i['appId'])[:256],
                                  app_type=i.get('app_type')) for i in items[:256]
                             if isinstance(i, dict) and i.get('name') and i.get('appId')]
                self.event('apps', value=self.apps)
                self.event('capabilities', installed_apps=bool(self.apps))

    def _probe_optional(self):
        if self.probing or self.closed.is_set():
            return
        self.probing = True
        host, generation = self.host, self.generation
        def probe():
            # Remote keys remain responsive during SSDP/HTTP timeouts.
            info = self._device_info(host)
            service = None
            try:
                service = self.volume_factory(host)
            except Exception:
                pass
            if not self.closed.is_set():
                try:
                    self.commands.put_nowait(dict(action='_probe_result', generation=generation, info=info, service=service))
                except queue.Full:
                    self.probing = False
        threading.Thread(target=probe, daemon=True).start()

    def _device_info(self, host):
        try:
            info = json.loads(fetch(f'http://{host}:8001/api/v2/', host))
            device = info.get('device', {})
            return device if isinstance(device, dict) else {}
        except Exception:
            return {}

    def _metadata(self, device):
        if isinstance(device, dict):
            if device.get('name'):
                self.event('device', name=str(device['name'])[:100], model='Samsung · ' + str(device.get('modelName', 'Tizen'))[:100])
            power = device.get('PowerState')
            if power in ('on', 'standby'):
                self.event('state', value={'statetype': 'samsung_state', 'power': power == 'on'})

    def _send(self, payload):
        if self.closed.is_set() or not self.ws:
            return
        self.ws.send(json.dumps(payload))

    def _read_volume(self, request=None, value=None):
        self.next_volume = time.monotonic() + 5
        try:
            if not self.volume_service:
                raise ValueError('No volume service')
            result = self.volume_service.read() if value is None else self.volume_service.set(value)
            self.event('volume', mute_known='muted' in result, **result)
            self.event('capabilities', absolute_volume=True)
            if request is not None:
                self.event('volume_result', request=request, value=result['value'])
        except Exception:
            self.volume_service = None
            self.event('capabilities', absolute_volume=False)
            self.event('volume_control_unavailable')
            if request is not None:
                self.event('volume_result', request=request)

    def _command(self, command):
        action = command.get('action')
        if action == 'connect':
            self._connect(command); return
        if not self.ready:
            return  # Never send remote commands before on-TV approval.
        if action == '_probe_result':
            if command.get('generation') == self.generation:
                self.probing = False
                self._metadata(command.get('info'))
                if command.get('service') is not None:
                    self.volume_service = command['service']
                if self.volume_service:
                    self._read_volume()
            return
        if action in ('refresh', 'read_volume'):
            if action == 'refresh':
                self._probe_optional()
                self._send({'method': 'ms.channel.emit', 'params': {'event': 'ed.installedApp.get', 'to': 'host'}})
            if self.volume_service:
                self._read_volume()
        elif action == 'volume':
            self._read_volume(command.get('request'), command.get('value'))
        elif action in ('key', 'mute'):
            key = 'MUTE' if action == 'mute' else command.get('key')
            if key not in KEYS:
                raise ValueError('Unsupported key')
            self.closed.wait(max(0, 0.08 - (time.monotonic() - self.last_key)))
            self._send({'method': 'ms.remote.control', 'params': {'Cmd': 'Click', 'DataOfCmd': KEYS[key], 'Option': 'false', 'TypeOfRemote': 'SendRemoteKey'}})
            self.last_key = time.monotonic()
            self.next_volume = self.last_key + 0.3
            self.event('sent', label=command.get('label', 'Command sent'))
        elif action == 'app':
            index = command.get('index')
            if type(index) is not int or not 0 <= index < len(self.apps):
                raise ValueError('App is no longer listed')
            app = self.apps[index]
            self._send({'method': 'ms.channel.emit', 'params': {'event': 'ed.apps.launch', 'to': 'host',
                        'data': {'appId': app['appId'], 'metaTag': '', 'action_type': 'DEEP_LINK' if app['app_type'] == 2 else 'NATIVE_LAUNCH'}}})
            self.event('sent', label='App launch requested · confirmation unavailable')
