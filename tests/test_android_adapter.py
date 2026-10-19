"""Real local TLS/protobuf fixture, not hardware certification.

Exercises the actual pinned dependency, six-hex PIN challenge and remote wire
messages. Fixture servers bind loopback only; production IP validation is patched
only inside these tests.
"""
import asyncio
import hashlib
from pathlib import Path
import ssl
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'Resources'))
from android_adapter import AndroidAdapter, KEYS, valid_pin
from androidtvremote2.certificate_generator import generate_selfsigned_cert
from androidtvremote2.polo_pb2 import OuterMessage
from androidtvremote2.remotemessage_pb2 import RemoteMessage, RemoteKeyCode
from cryptography import x509


async def read_message(reader, cls):
    length = 0
    for i in range(5):
        byte = (await reader.readexactly(1))[0]
        length |= (byte & 127) << (7 * i)
        if not byte & 128:
            if length > 1048576:
                raise ValueError('Fixture frame too large')
            msg = cls()
            msg.ParseFromString(await reader.readexactly(length))
            return msg
    raise ValueError('Bad frame')


async def write_message(writer, msg):
    body = msg.SerializeToString()
    length, prefix = len(body), bytearray()
    while True:
        prefix.append((length & 127) | (128 if length > 127 else 0))
        length >>= 7
        if not length:
            break
    # Deliberately fragment length/body across transport writes.
    writer.write(prefix)
    await writer.drain()
    await asyncio.sleep(0)
    writer.write(body)
    await writer.drain()


class AndroidTLSFixtureTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.events, self.received, self.writers, self.adapters = [], [], [], []
        self.fixture_volume = 7
        self.temp = tempfile.TemporaryDirectory()
        self.server_cert, self.server_key = generate_selfsigned_cert('FixtureTV')
        root = Path(self.temp.name)
        (root / 'cert.pem').write_bytes(self.server_cert)
        (root / 'key.pem').write_bytes(self.server_key)
        self.pair_context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        self.pair_context.load_cert_chain(root / 'cert.pem', root / 'key.pem')
        self.remote_context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        self.remote_context.load_cert_chain(root / 'cert.pem', root / 'key.pem')
        self.remote_context.verify_mode = ssl.CERT_REQUIRED
        self.remote_context.verify_flags |= ssl.VERIFY_X509_PARTIAL_CHAIN
        self.pair_server = await asyncio.start_server(self.pair_client, '127.0.0.1', 0, ssl=self.pair_context)
        self.remote_server = await asyncio.start_server(self.remote_client, '127.0.0.1', 0, ssl=self.remote_context)
        self.pair_port = self.pair_server.sockets[0].getsockname()[1]
        self.api_port = self.remote_server.sockets[0].getsockname()[1]
        self.address_patch = patch('android_adapter.host_address', return_value='127.0.0.1')
        self.address_patch.start()
        self.fingerprint = hashlib.sha256(ssl.PEM_cert_to_DER_cert(self.server_cert.decode())).hexdigest().upper()

    async def asyncTearDown(self):
        for adapter in self.adapters:
            await asyncio.to_thread(adapter.close)
        for writer in self.writers:
            writer.close()
        for writer in self.writers:
            try:
                await writer.wait_closed()
            except (OSError, ConnectionError):
                pass
        for server in (self.pair_server, self.remote_server):
            server.close()
            await server.wait_closed()
        self.address_patch.stop()
        self.temp.cleanup()

    def make_adapter(self):
        adapter = AndroidAdapter(self.events.append, api_port=self.api_port, pair_port=self.pair_port)
        self.adapters.append(adapter)
        self.adapter = adapter
        return adapter

    async def wait_event(self, predicate, timeout=5):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            for event in self.events:
                if predicate(event):
                    return event
            await asyncio.sleep(0.02)
        self.fail('Expected fixture event not received: ' + str([e['event'] for e in self.events]))

    def code_and_secret(self):
        h = hashlib.sha256()
        for pem in (self.adapter.certificate.encode(), self.server_cert):
            numbers = x509.load_pem_x509_certificate(pem).public_key().public_numbers()
            h.update(bytes.fromhex(f'{numbers.n:X}'))
            h.update(bytes.fromhex(f'0{numbers.e:X}'))
        h.update(bytes.fromhex('AB12'))
        secret = h.digest()
        return f'{secret[0]:02X}AB12', secret

    async def pair_client(self, reader, writer):
        self.writers.append(writer)
        try:
            while True:
                request = await read_message(reader, OuterMessage)
                response = OuterMessage(protocol_version=2, status=200)
                if request.HasField('pairing_request'):
                    response.pairing_request_ack.server_name = 'FixtureTV'
                elif request.HasField('options'):
                    response.options.preferred_role = 2
                    encoding = response.options.output_encodings.add()
                    encoding.type = 3
                    encoding.symbol_length = 6
                elif request.HasField('configuration'):
                    response.configuration_ack.SetInParent()
                elif request.HasField('secret'):
                    _, expected = self.code_and_secret()
                    if request.secret.secret != expected:
                        response.status = 402
                    else:
                        self.remote_context.load_verify_locations(cadata=self.adapter.certificate)
                        response.secret_ack.secret = expected
                await write_message(writer, response)
        except (asyncio.IncompleteReadError, ConnectionError):
            pass
        finally:
            writer.close()

    async def remote_client(self, reader, writer):
        self.writers.append(writer)
        try:
            msg = RemoteMessage()
            msg.remote_configure.code1 = 1 | 2 | 4 | 32 | 64 | 512
            msg.remote_configure.device_info.model = 'Test Google TV'
            msg.remote_configure.device_info.vendor = 'Fixture Brand'
            await write_message(writer, msg)
            await read_message(reader, RemoteMessage)
            msg = RemoteMessage()
            msg.remote_set_active.active = 1 | 2 | 4 | 32 | 64 | 512
            await write_message(writer, msg)
            await read_message(reader, RemoteMessage)
            msg = RemoteMessage()
            msg.remote_start.started = True
            await write_message(writer, msg)
            msg = RemoteMessage()
            msg.remote_set_volume_level.volume_level = 7
            msg.remote_set_volume_level.volume_max = 20
            msg.remote_set_volume_level.volume_muted = False
            await write_message(writer, msg)
            msg = RemoteMessage()
            msg.remote_ime_key_inject.app_info.app_package = 'com.google.android.youtube.tv'
            await write_message(writer, msg)
            while True:
                request = await read_message(reader, RemoteMessage)
                self.received.append(request)
                if request.HasField('remote_key_inject') and request.remote_key_inject.key_code in (24, 25):
                    self.fixture_volume = max(0, min(20, self.fixture_volume + (1 if request.remote_key_inject.key_code == 24 else -1)))
                    feedback = RemoteMessage()
                    feedback.remote_set_volume_level.volume_level = self.fixture_volume
                    feedback.remote_set_volume_level.volume_max = 20
                    feedback.remote_set_volume_level.volume_muted = False
                    await write_message(writer, feedback)
        except (asyncio.IncompleteReadError, ConnectionError):
            pass
        finally:
            writer.close()

    async def paired(self):
        adapter = self.make_adapter()
        adapter.command(dict(action='connect', host='192.168.1.10', fingerprint=self.fingerprint))
        await self.wait_event(lambda e: e.get('value') == 'pairing')
        code, _ = self.code_and_secret()
        adapter.command(dict(action='pin', pin=code))
        credentials = await self.wait_event(lambda e: e['event'] == 'credentials')
        await self.wait_event(lambda e: e.get('value') == 'ready')
        return adapter, credentials['value']

    async def test_pair_wire_controls_state_and_saved_reconnect(self):
        adapter, saved = await self.paired()
        await self.wait_event(lambda e: e['event'] == 'volume' and e['value'] == 35)
        await self.wait_event(lambda e: e['event'] == 'state' and e['value'].get('appname') == 'YouTube')
        for key in ('HOME', 'UP', 'OK', 'RETURNS', 'VOLUMEUP', 'INPUT'):
            adapter.command(dict(action='key', key=key))
        adapter.command(dict(action='app', index=0))
        deadline = time.monotonic() + 3
        while len(self.received) < 7 and time.monotonic() < deadline:
            await asyncio.sleep(0.02)
        self.assertEqual([m.remote_key_inject.key_code for m in self.received[:6]],
                         [RemoteKeyCode.Value('KEYCODE_' + KEYS[k]) for k in ('HOME', 'UP', 'OK', 'RETURNS', 'VOLUMEUP', 'INPUT')])
        self.assertEqual(self.received[6].remote_app_link_launch_request.app_link, 'https://www.youtube.com')
        directory = adapter.storage.name
        self.assertFalse((Path(directory) / 'key.pem').exists())
        await asyncio.to_thread(adapter.close)
        self.assertFalse(Path(directory).exists())
        self.events.clear()
        new = self.make_adapter()
        new.command(dict(action='connect', host='192.168.1.10', fingerprint=self.fingerprint, saved=saved))
        await self.wait_event(lambda e: e.get('value') == 'ready')
        self.assertFalse(any(e.get('value') == 'pairing' for e in self.events))

    async def test_slider_moves_through_actual_protocol_feedback(self):
        adapter, _ = await self.paired()
        await self.wait_event(lambda e: e['event'] == 'volume')
        adapter.command(dict(action='volume', value=53, request=1))
        result = await self.wait_event(lambda e: e['event'] == 'volume_result' and e['request'] == 1)
        self.assertEqual(result['value'], 55)
        self.assertEqual(len(self.received), 4)
        self.assertTrue(all(m.remote_key_inject.key_code == 24 for m in self.received))

    async def test_changed_certificate_requires_trust_before_pairing(self):
        adapter = self.make_adapter()
        adapter.command(dict(action='connect', host='192.168.1.10', fingerprint='different'))
        event = await self.wait_event(lambda e: e['event'] == 'trust')
        self.assertTrue(event['changed'])
        self.assertFalse(any(e['event'] == 'credentials' or e.get('value') == 'ready' for e in self.events))
        self.assertIsNone(adapter.remote)

    async def test_wrong_code_redaction_and_cancel(self):
        adapter = self.make_adapter()
        adapter.command(dict(action='connect', host='192.168.1.10', fingerprint=self.fingerprint))
        await self.wait_event(lambda e: e.get('value') == 'pairing')
        good, _ = self.code_and_secret()
        bad = ('FF' if not good.startswith('FF') else '00') + good[2:]
        adapter.command(dict(action='pin', pin=bad))
        error = await self.wait_event(lambda e: e['event'] == 'error')
        self.assertNotIn(bad, error['message'])
        self.assertFalse(any(e['event'] == 'credentials' for e in self.events))
        await asyncio.to_thread(adapter.close)
        count = len(self.events)
        adapter.command(dict(action='pin', pin=good))
        await asyncio.sleep(0.05)
        self.assertEqual(len(self.events), count)
        self.assertFalse(adapter.thread.is_alive())

    async def test_wrong_code_can_be_retried_without_new_pairing(self):
        adapter = self.make_adapter()
        adapter.command(dict(action='connect', host='192.168.1.10', fingerprint=self.fingerprint))
        await self.wait_event(lambda e: e.get('value') == 'pairing')
        code, _ = self.code_and_secret()
        bad = ('FF' if not code.startswith('FF') else '00') + code[2:]
        adapter.command(dict(action='pin', pin=bad))
        await self.wait_event(lambda e: e['event'] == 'error')
        adapter.command(dict(action='pin', pin=code))
        await self.wait_event(lambda e: e.get('value') == 'ready')

    async def test_control_connection_cannot_use_another_server_certificate(self):
        adapter, saved = await self.paired()
        await asyncio.to_thread(adapter.close)
        self.events.clear()
        other_cert, other_key = generate_selfsigned_cert('DifferentTV')
        certfile, keyfile = Path(self.temp.name) / 'other-cert', Path(self.temp.name) / 'other-key'
        certfile.write_bytes(other_cert); keyfile.write_bytes(other_key)
        self.remote_context.load_cert_chain(certfile, keyfile)
        new = self.make_adapter()
        new.command(dict(action='connect', host='192.168.1.10', fingerprint=self.fingerprint, saved=saved))
        # Pairing endpoint still has the approved cert. The control endpoint's
        # changed cert must fail verification rather than report ready.
        await self.wait_event(lambda e: e.get('value') == 'pairing' or e['event'] == 'error')
        self.assertFalse(any(e.get('value') == 'ready' for e in self.events))


class AndroidInputTests(unittest.TestCase):
    def test_pin_and_all_mapped_keys_exist(self):
        self.assertTrue(valid_pin('Ab12cD'))
        for pin in ('1234', '1234567', 'GG1234', '１２３４５６', ''):
            self.assertFalse(valid_pin(pin))
        for name in KEYS.values():
            RemoteKeyCode.Value('KEYCODE_' + name)
