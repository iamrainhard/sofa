"""Actual TLS/WebSocket wire fixture. This is not Samsung hardware certification."""
import asyncio
import base64
import hashlib
import json
from pathlib import Path
import ssl
import struct
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch
from urllib.parse import parse_qs, urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'Resources'))
from samsung_adapter import SamsungAdapter
from androidtvremote2.certificate_generator import generate_selfsigned_cert


class VolumeFixture:
    def __init__(self):
        self.value = 31
        self.fail = False

    def read(self):
        if self.fail:
            raise OSError('Fixture volume unavailable')
        return dict(value=self.value, muted=False, source='readback')

    def set(self, value):
        self.value = value
        return self.read()


async def frame(writer, payload, opcode=1):
    body = json.dumps(payload).encode() if opcode == 1 else payload
    length = len(body)
    prefix = bytes([0x80 | opcode, length]) if length < 126 else bytes([0x80 | opcode, 126]) + struct.pack('!H', length)
    writer.write(prefix + body)
    await writer.drain()


class SamsungTLSFixtureTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.events, self.received, self.requests, self.writers, self.adapters = [], [], [], [], []
        self.approve = asyncio.Event()
        self.response = dict(event='ms.channel.connect', data={'token': 'fixture-token'})
        self.volume = VolumeFixture()
        self.temp = tempfile.TemporaryDirectory()
        root = Path(self.temp.name)
        cert, key = generate_selfsigned_cert('FixtureSamsung')
        (root / 'cert.pem').write_bytes(cert)
        (root / 'key.pem').write_bytes(key)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(root / 'cert.pem', root / 'key.pem')
        self.server = await asyncio.start_server(self.client, '127.0.0.1', 0, ssl=context)
        self.port = self.server.sockets[0].getsockname()[1]
        self.fingerprint = hashlib.sha256(ssl.PEM_cert_to_DER_cert(cert.decode())).hexdigest()
        self.patches = [patch('samsung_adapter.host_address', return_value='127.0.0.1'),
                        patch.object(SamsungAdapter, '_device_info')]
        for p in self.patches:
            p.start()

    async def asyncTearDown(self):
        for adapter in self.adapters:
            await asyncio.to_thread(adapter.close)
        self.approve.set()
        for writer in self.writers:
            writer.close()
        for writer in self.writers:
            try:
                await writer.wait_closed()
            except (OSError, ConnectionError):
                pass
        self.server.close()
        await self.server.wait_closed()
        for p in self.patches:
            p.stop()
        self.temp.cleanup()

    def connect(self, fingerprint=None, saved=None, **options):
        factory = options.pop('volume_factory', lambda host: self.volume)
        self.adapter = SamsungAdapter(self.events.append, port=self.port, volume_factory=factory, **options)
        self.adapters.append(self.adapter)
        self.adapter.command(dict(action='connect', host='127.0.0.1',
                                  fingerprint=self.fingerprint if fingerprint is None else fingerprint, saved=saved or {}))
        return self.adapter

    async def until(self, predicate, timeout=5):
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            if predicate():
                return
            await asyncio.sleep(0.01)
        self.fail('Fixture timeout; events: ' + repr(self.events))

    def has(self, kind, **values):
        return any(e.get('event') == kind and all(e.get(k) == v for k, v in values.items()) for e in self.events)

    async def ready(self, **options):
        adapter = self.connect(**options)
        self.approve.set()
        await self.until(lambda: self.has('status', value='ready'))
        return adapter

    async def client(self, reader, writer):
        self.writers.append(writer)
        try:
            raw = await reader.readuntil(b'\r\n\r\n')
            lines = raw.decode().split('\r\n')
            self.requests.append(lines[0].split(' ')[1])
            headers = dict(line.split(': ', 1) for line in lines[1:] if ': ' in line)
            accept = base64.b64encode(hashlib.sha1((headers['Sec-WebSocket-Key'] + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').encode()).digest()).decode()
            writer.write(('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ' + accept + '\r\n\r\n').encode())
            await writer.drain()
            await self.approve.wait()
            if writer.is_closing():
                return
            await frame(writer, self.response)
            while True:
                first, second = await reader.readexactly(2)
                length = second & 127
                if length == 126:
                    length = struct.unpack('!H', await reader.readexactly(2))[0]
                elif length == 127:
                    length = struct.unpack('!Q', await reader.readexactly(8))[0]
                if length > 262144:
                    raise ValueError('Fixture frame too large')
                mask = await reader.readexactly(4) if second & 128 else b'\0' * 4
                body = await reader.readexactly(length)
                body = bytes(b ^ mask[i % 4] for i, b in enumerate(body))
                if first & 15 == 9:
                    await frame(writer, body, 10)
                elif first & 15 == 1:
                    message = json.loads(body)
                    self.received.append(message)
                    if message.get('params', {}).get('event') == 'ed.installedApp.get':
                        await frame(writer, dict(event='ed.installedApp.get', data={'data': [
                            {'name': 'YouTube', 'appId': 'fixture.youtube', 'app_type': 2},
                            {'name': 'Netflix', 'appId': 'fixture.netflix', 'app_type': 4}]}))
        except (asyncio.IncompleteReadError, ConnectionError, OSError):
            pass
        finally:
            writer.close()

    async def test_certificate_must_be_approved_before_token_or_http(self):
        for fingerprint in ('', '00' * 32):
            adapter = self.connect(fingerprint=fingerprint, saved={'token': 'must-not-leak'})
            await self.until(lambda: self.has('trust', changed=bool(fingerprint)))
            self.assertEqual(self.requests, [])
            self.assertFalse(adapter.ready)
            await asyncio.to_thread(adapter.close)

    async def test_approval_gates_keys_and_persists_token(self):
        adapter = self.connect()
        await self.until(lambda: self.has('approval', waiting=True))
        adapter.command(dict(action='key', key='POWER'))
        await asyncio.sleep(0.2)
        self.assertEqual(self.received, [])
        self.approve.set()
        await self.until(lambda: self.has('volume', value=31))
        self.assertTrue(self.has('credentials', value={'token': 'fixture-token'}))
        self.assertTrue(self.has('capabilities', absolute_volume=True))
        for key in ('UP', 'LEFT', 'RIGHT', 'OK', 'INPUT', 'VOLUMEDOWN', 'MUTE', 'BACK', 'FORWARDS'):
            adapter.command(dict(action='key', key=key))
        await self.until(lambda: len([m for m in self.received if m['method'] == 'ms.remote.control']) == 9)
        commands = [m['params']['DataOfCmd'] for m in self.received if m['method'] == 'ms.remote.control']
        self.assertEqual(commands, ['KEY_UP', 'KEY_LEFT', 'KEY_RIGHT', 'KEY_ENTER', 'KEY_SOURCE', 'KEY_VOLDOWN', 'KEY_MUTE', 'KEY_REWIND', 'KEY_FF'])
        self.assertNotIn('KEY_POWER', commands)
        self.assertTrue(all(m['params']['Cmd'] == 'Click' for m in self.received if m['method'] == 'ms.remote.control'))

    async def test_reconnect_uses_saved_token_on_verified_socket(self):
        await self.ready(saved={'token': 'saved-token'}, fingerprint=self.fingerprint.upper())
        query = parse_qs(urlsplit(self.requests[0]).query)
        self.assertEqual(query['token'], ['saved-token'])
        self.assertEqual(base64.b64decode(query['name'][0]), b'Sofa')
        self.assertNotIn('saved-token', repr(self.events))

    async def test_denial_invalidates_only_samsung_credentials_and_allows_retry(self):
        self.response = dict(event='ms.channel.unauthorized')
        adapter = self.connect(saved={'token': 'blocked'})
        self.approve.set()
        await self.until(lambda: self.has('approval', waiting=False))
        self.assertTrue(self.has('credentials', value={}))
        self.assertTrue(self.has('status', value='pairing'))
        self.assertFalse(adapter.ready)
        self.assertFalse(self.has('status', value='ready'))

    async def test_approval_timeout_and_closed_adapter_cannot_emit(self):
        adapter = self.connect(approval_timeout=0.15)
        await self.until(lambda: self.has('approval', waiting=False))
        self.assertFalse(adapter.ready)
        await asyncio.to_thread(adapter.close)
        count = len(self.events)
        adapter.event('credentials', value={'token': 'late'})
        self.assertEqual(len(self.events), count)

    async def test_installed_apps_launch_actual_catalog_id(self):
        adapter = await self.ready()
        await self.until(lambda: self.has('capabilities', installed_apps=True))
        adapter.command(dict(action='app', index=0))
        adapter.command(dict(action='app', index=1))
        await self.until(lambda: len([m for m in self.received if m['params'].get('event') == 'ed.apps.launch']) == 2)
        launches = [m['params']['data'] for m in self.received if m['params'].get('event') == 'ed.apps.launch']
        self.assertEqual(launches, [dict(appId='fixture.youtube', action_type='DEEP_LINK', metaTag=''), dict(appId='fixture.netflix', action_type='NATIVE_LAUNCH', metaTag='')])
        adapter.command(dict(action='app', index=900))
        await self.until(lambda: self.has('error'))
        self.assertFalse(self.has('state'), 'Launch is not proof of active app or power')

    async def test_volume_readback_failure_falls_back_without_losing_remote(self):
        adapter = await self.ready()
        await self.until(lambda: self.has('capabilities', absolute_volume=True))
        adapter.command(dict(action='volume', value=48, request=42))
        await self.until(lambda: self.has('volume_result', request=42, value=48))
        self.volume.fail = True
        adapter.command(dict(action='volume', value=52, request=43))
        await self.until(lambda: self.has('volume_control_unavailable'))
        self.assertTrue(adapter.ready)
        self.assertTrue(self.has('volume_result', request=43))
        self.assertFalse(self.has('volume_result', request=43, value=52))
        adapter.command(dict(action='key', key='VOLUMEUP'))
        await self.until(lambda: any(m['params'].get('DataOfCmd') == 'KEY_VOLUP' for m in self.received))

    async def test_missing_or_failed_optional_volume_does_not_break_pairing(self):
        def fail(host):
            raise OSError('No UPnP')
        adapter = await self.ready(volume_factory=fail)
        await self.until(lambda: self.has('capabilities', installed_apps=True))
        self.assertTrue(adapter.ready)
        self.assertFalse(self.has('capabilities', absolute_volume=True))
        adapter.command(dict(action='key', key='HOME'))
        await self.until(lambda: any(m['params'].get('DataOfCmd') == 'KEY_HOME' for m in self.received))

    async def test_slow_optional_discovery_does_not_delay_remote_keys(self):
        release = threading.Event()
        def slow(host):
            release.wait(2)
            return self.volume
        try:
            adapter = await self.ready(volume_factory=slow)
            adapter.command(dict(action='key', key='HOME'))
            await self.until(lambda: any(m['params'].get('DataOfCmd') == 'KEY_HOME' for m in self.received), timeout=1)
            self.assertFalse(self.has('capabilities', absolute_volume=True))
            release.set()
            await self.until(lambda: self.has('capabilities', absolute_volume=True))
        finally:
            release.set()

    async def test_stale_optional_probe_cannot_replace_current_state(self):
        adapter = await self.ready()
        await self.until(lambda: self.has('capabilities', absolute_volume=True))
        adapter.command(dict(action='_probe_result', generation=adapter.generation - 1, info={'name': 'Wrong TV'}, service=None))
        adapter.command(dict(action='key', key='HOME'))
        await self.until(lambda: any(m['params'].get('DataOfCmd') == 'KEY_HOME' for m in self.received))
        self.assertIsNotNone(adapter.volume_service)
        self.assertFalse(self.has('device', name='Wrong TV'))

    async def test_refresh_keeps_valid_volume_if_multicast_discovery_is_quiet(self):
        adapter = await self.ready()
        await self.until(lambda: self.has('capabilities', absolute_volume=True))
        adapter.volume_factory = lambda host: None
        adapter.command(dict(action='refresh'))
        adapter.command(dict(action='volume', request=90, value=61))
        await self.until(lambda: self.has('volume_result', request=90, value=61))
        await self.until(lambda: not adapter.probing)
        self.assertIs(adapter.volume_service, self.volume)
        self.assertFalse(self.has('volume_control_unavailable'))
