"""Bounded, same-device Samsung discovery and optional UPnP volume support."""
import concurrent.futures
import socket
import time
import urllib.request
import xml.etree.ElementTree as ET
from urllib.parse import urljoin, urlsplit
from xml.sax.saxutils import escape

from bridge import host_address

LIMIT = 262144
SERVICE = 'urn:schemas-upnp-org:service:RenderingControl:1'


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def local_url(url, host):
    p = urlsplit(url)
    if (p.scheme != 'http' or p.hostname != host_address(host) or p.username or
            p.password or p.fragment or not 1 <= (p.port or 80) <= 65535):
        raise ValueError('Device URL must stay on the selected TV')
    return url


def fetch(url, host, data=None, headers=None):
    request = urllib.request.Request(local_url(url, host), data, headers or {})
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
    with opener.open(request, timeout=1.5) as response:
        result = response.read(LIMIT + 1)
    if len(result) > LIMIT:
        raise ValueError('TV response too large')
    return result


def xml(data):
    if b'<!DOCTYPE' in data.upper() or b'<!ENTITY' in data.upper():
        raise ValueError('Unsupported XML declaration')
    return ET.fromstring(data)


def locations(timeout=2, target=None):
    query = ('M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\n'
             'MAN: "ssdp:discover"\r\nMX: 1\r\n'
             'ST: urn:schemas-upnp-org:device:MediaRenderer:1\r\n\r\n').encode()
    found = set()
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.settimeout(0.15)
        sock.sendto(query, ('239.255.255.250', 1900))
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline and len(found) < 8:
            try:
                data, sender = sock.recvfrom(8192)
                host = host_address(sender[0])
                if target and host != target:
                    continue
                headers = {k.strip().lower(): v.strip() for line in data.decode(errors='replace').split('\r\n')[1:]
                           if ':' in line for k, v in [line.split(':', 1)]}
                url = local_url(headers.get('location', ''), host)
                found.add((host, url))
            except (OSError, ValueError):
                continue
    return sorted(found)


def description(host, url):
    root = xml(fetch(url, host))
    if 'samsung' not in root.findtext('.//{*}manufacturer', '').lower():
        raise ValueError('Not a Samsung TV')
    return root


def discover_devices():
    def inspect(item):
        host, url = item
        try:
            root = description(host, url)
            return dict(host=host, name=root.findtext('.//{*}friendlyName', 'Samsung TV'),
                        model=root.findtext('.//{*}modelName', ''), platform='samsung')
        except Exception:
            return None
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        return [item for item in pool.map(inspect, locations()) if item]


class VolumeService:
    """Only enable the slider after SCPD confirms actions and GetVolume succeeds."""
    def __init__(self, host, control, actions):
        self.host, self.control, self.actions = host, local_url(control, host), actions

    @classmethod
    def discover(cls, host):
        for _, url in locations(target=host):
            try:
                root = description(host, url)
                for service in root.findall('.//{*}service'):
                    if service.findtext('{*}serviceType') != SERVICE:
                        continue
                    scpd = xml(fetch(urljoin(url, service.findtext('{*}SCPDURL', '')), host))
                    actions = {n.text for n in scpd.findall('.//{*}action/{*}name')}
                    if not {'GetVolume', 'SetVolume'} <= actions:
                        continue
                    # Keep Sofa's 0–100 scale honest; defer unusual ranges.
                    ranges = [v for v in scpd.findall('.//{*}stateVariable') if v.findtext('{*}name') == 'Volume']
                    if ranges:
                        v = ranges[0]
                        if (v.findtext('.//{*}minimum', '0'), v.findtext('.//{*}maximum', '100'), v.findtext('.//{*}step', '1')) != ('0', '100', '1'):
                            continue
                    obj = cls(host, urljoin(url, service.findtext('{*}controlURL', '')), actions)
                    obj.read()
                    return obj
            except Exception:
                continue
        return None

    def soap(self, action, **values):
        if action not in self.actions:
            raise ValueError('Unsupported volume action')
        fields = ''.join(f'<{k}>{escape(str(v))}</{k}>' for k, v in dict(InstanceID=0, Channel='Master', **values).items())
        body = (f'<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
                f's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body>'
                f'<u:{action} xmlns:u="{SERVICE}">{fields}</u:{action}></s:Body></s:Envelope>').encode()
        result = xml(fetch(self.control, self.host, body, {'Content-Type': 'text/xml; charset="utf-8"',
                     'SOAPACTION': f'"{SERVICE}#{action}"'}))
        if result.find('.//{*}Fault') is not None:
            raise ValueError('TV rejected volume request')
        return result

    def read(self):
        value = int(self.soap('GetVolume').findtext('.//{*}CurrentVolume', '-1'))
        if not 0 <= value <= 100:
            raise ValueError('Invalid volume readback')
        result = dict(value=value, source='readback')
        if 'GetMute' in self.actions:
            try:
                mute = self.soap('GetMute').findtext('.//{*}CurrentMute')
                if mute in ('0', '1', 'true', 'false'):
                    result['muted'] = mute in ('1', 'true')
            except Exception:
                pass  # Missing mute feedback must not disable valid volume feedback.
        return result

    def set(self, value):
        if type(value) is not int or not 0 <= value <= 100:
            raise ValueError('Invalid volume')
        self.soap('SetVolume', DesiredVolume=value)
        return self.read()
