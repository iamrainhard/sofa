"""Bounded LAN discovery. Announcements are hints, never authentication.
No subnet sweep, redirects, proxies, credentials or remote commands. The adapter
rechecks the approved certificate on the socket used to transmit credentials.
"""
import concurrent.futures
import hashlib
import json
import select
import socket
import ssl
import threading
import time
from urllib.parse import urlsplit
from bridge import host_address
from samsung_network import fetch, xml, local_url

PORTS = {'vidaa': 36669, 'androidtv': 6467, 'samsung': 8002}


def certificate(host, platform):
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE  # Observation only, never authentication.
    with socket.create_connection((host_address(host), PORTS[platform]), timeout=1.5) as raw:
        with context.wrap_socket(raw, server_hostname=host) as secure:
            return hashlib.sha256(secure.getpeercert(binary_form=True)).hexdigest()


def inspect_candidate(host, platform, identity='', name='', location=''):
    host = host_address(host)
    if platform not in PORTS:
        raise ValueError('Unsupported platform')
    result = dict(host=host, platform=platform, name=name[:160], model='', identity='')
    if platform == 'vidaa':
        try:
            root = xml(fetch(f'http://{host}:18400/MediaServer/rendererdevicedesc.xml', host))
            udn = root.findtext('.//{*}UDN', '').strip().lower()
            result.update(name=root.findtext('.//{*}friendlyName', 'VIDAA TV')[:160],
                          model=root.findtext('.//{*}modelName', '')[:160], identity='upnp:' + udn if udn else '')
        except (OSError, ValueError):
            # A disabled DLNA service must not hide a reachable remote. Only a
            # device-id TXT hint can supply identity; a friendly name cannot.
            if identity.startswith('airplay:') and len(identity) <= 512:
                result['identity'] = identity
        result['name'] = result['name'] or 'VIDAA TV'
    elif platform == 'samsung':
        try:
            info = json.loads(fetch(f'http://{host}:8001/api/v2/', host))
            device = info.get('device', {})
            identifier = device.get('id') or device.get('udn')
            result.update(name=str(device.get('name') or info.get('name') or 'Samsung TV')[:160],
                          model=str(device.get('modelName') or '')[:160],
                          identity='samsung:' + str(identifier).lower() if identifier else '')
        except (OSError, ValueError, AttributeError):
            if location:
                root = xml(fetch(location, host))
                if 'samsung' not in root.findtext('.//{*}manufacturer', '').lower():
                    raise ValueError('Not a Samsung TV')
                udn = root.findtext('.//{*}UDN', '').strip().lower()
                result.update(name=root.findtext('.//{*}friendlyName', 'Samsung TV')[:160],
                              model=root.findtext('.//{*}modelName', '')[:160], identity='upnp:' + udn if udn else '')
        result['name'] = result['name'] or 'Samsung TV'
    else:
        if identity.startswith(('bonjour:', 'cast:')) and len(identity) <= 512:
            result['identity'] = identity
        result['name'] = result['name'] or 'Google / Android TV'
        result['model'] = 'Google / Android TV'
    result['fingerprint'] = certificate(host, platform)
    return result


def announcement(data, sender):
    host = host_address(sender)
    lines = data.decode(errors='replace').split('\r\n')
    if not lines[0].upper().startswith('HTTP/1.1 200'):
        raise ValueError('Not an SSDP response')
    headers = {k.strip().lower(): v.strip() for line in lines[1:] if ':' in line
               for k, v in [line.split(':', 1)]}
    return host, local_url(headers.get('location', ''), host), headers.get('usn', '')[:512]


def inspect_announcement(item):
    host, location, usn = item
    port = urlsplit(location).port or 80
    if port == 18400 or (port == 9080 and 'hisetv' in usn.lower()):
        return inspect_candidate(host, 'vidaa')
    root = xml(fetch(location, host))
    manufacturer = root.findtext('.//{*}manufacturer', '').lower()
    if 'samsung' in manufacturer:
        return inspect_candidate(host, 'samsung', location=location)
    if 'hisense' in manufacturer or 'vidaa' in manufacturer:
        return inspect_candidate(host, 'vidaa')
    return None


def discover(interfaces=(), emit=lambda value: None, cancelled=None, duration=4.0):
    cancelled = cancelled or threading.Event()
    sockets, seen, pending = [], set(), set()
    host_locations = {}
    pool = concurrent.futures.ThreadPoolExecutor(max_workers=8)
    for interface in list(dict.fromkeys(interfaces))[:8] or ['']:
        sock = None
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 2)
            if interface:
                address = socket.inet_aton(host_address(interface))
                sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_IF, address)
                sock.bind((interface, 0))
            sock.setblocking(False)
            sockets.append(sock)
        except (OSError, ValueError):
            if sock: sock.close()
    started, sent = time.monotonic(), 0
    try:
        while sockets and not cancelled.is_set() and time.monotonic() - started < duration:
            if sent < 2 and time.monotonic() - started >= sent * 1.5:
                for sock in sockets:
                    for target in ('ssdp:all', 'urn:schemas-upnp-org:device:MediaRenderer:1'):
                        query = ('M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\n'
                                 'MAN: "ssdp:discover"\r\nMX: 1\r\nST: ' + target + '\r\n\r\n').encode()
                        try: sock.sendto(query, ('239.255.255.250', 1900))
                        except OSError: pass
                sent += 1
            readable, _, _ = select.select(sockets, [], [], .1)
            for sock in readable:
                try:
                    data, sender = sock.recvfrom(8192)
                    item = announcement(data, sender[0])
                    if (item[0], item[1]) not in seen and (item[0] in host_locations or len(host_locations) < 32) and host_locations.get(item[0], 0) < 2:
                        seen.add((item[0], item[1])); host_locations[item[0]] = host_locations.get(item[0], 0) + 1
                        pending.add(pool.submit(inspect_announcement, item))
                except (OSError, ValueError): pass
            for future in list(pending):
                if future.done():
                    pending.remove(future)
                    try:
                        value = future.result()
                        if value and not cancelled.is_set(): emit(value)
                    except Exception: pass
        deadline = time.monotonic() + 5
        while pending and not cancelled.is_set() and time.monotonic() < deadline:
            done, pending = concurrent.futures.wait(pending, timeout=.1, return_when=concurrent.futures.FIRST_COMPLETED)
            for future in done:
                try:
                    value = future.result()
                    if value and not cancelled.is_set(): emit(value)
                except Exception: pass
    finally:
        for sock in sockets: sock.close()
        pool.shutdown(wait=False, cancel_futures=True)
