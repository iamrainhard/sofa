import json
from pathlib import Path
import struct
import sys
import unittest
from unittest.mock import Mock, patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'Resources'))
from bridge import Bridge, credentials, packet, extract, host_address, utf8, MAX_PACKET

class FramingTests(unittest.TestCase):
    def test_fragmentation_and_coalescing(self):
        for length in (0, 1, 127, 128, 16384, 50000):
            data = b'x' * length
            encoded = packet(0x30, data)
            for cut in (0, 1, len(encoded) // 2, len(encoded) - 1):
                self.assertIsNone(extract(encoded[:cut]))
            self.assertEqual(extract(encoded + b'next'), (0x30, data, b'next'))
    def test_rejects_malformed_and_oversized(self):
        with self.assertRaises(ValueError): extract(b'\x30\x80\x80\x80\x80')
        with self.assertRaises(ValueError): packet(0x30, b'x' * (MAX_PACKET + 1))
        with self.assertRaises(ValueError): extract(b'\x30\xff\xff\x7f')
    def test_credentials_known_vector(self):
        self.assertEqual(credentials('56:b8:88:4e:f7:19', 1766974704), (
            '56:b8:88:4e:f7:19$his$256DBF_vidaacommon_001',
            'his$6239759786168176024', 'C3BA44782E18ABF4892AC44D79A622D2'))
    def test_host_is_local_ip_only(self):
        self.assertEqual(host_address('192.168.1.100'), '192.168.1.100')
        for host in ('example.com', '8.8.8.8', '127.0.0.1', '0.0.0.0', '224.0.0.1', '::1', '192.168.1.1:80', '1;rm'):
            with self.assertRaises(ValueError): host_address(host)

class StateTests(unittest.TestCase):
    def setUp(self):
        self.events = []
        self.bridge = Bridge(self.events.append)
        self.bridge.sock = Mock()
        self.bridge.client = 'test-client'
        self.bridge.username = 'test-user'
        self.bridge.acknowledged = True
    def test_retained_power_state_and_live_updates_are_delivered(self):
        topic = '/remoteapp/mobile/broadcast/ui_service/state'
        body = utf8(topic) + json.dumps({'statetype': 'fake_sleep_0'}).encode()
        self.bridge.receive(0x31, body)
        self.assertEqual(self.events[-1]['value']['statetype'], 'fake_sleep_0')
        self.bridge.receive(0x30, body)
        self.assertEqual(self.events[-1]['value']['statetype'], 'fake_sleep_0')

    def test_power_poll_is_authenticated_and_rate_limited(self):
        self.bridge.sock.pending.return_value = False
        self.bridge.last_received = self.bridge.last_ping = 100
        with patch('bridge.select.select', return_value=([], [], [])), patch('bridge.time.monotonic', return_value=100):
            self.bridge.tick()
            self.bridge.sock.sendall.assert_not_called()
            self.bridge.authenticated = True
            self.bridge.tick()
            self.bridge.sock.sendall.assert_called_once()
            self.assertIn(b'actions/gettvstate', self.bridge.sock.sendall.call_args.args[0])
            self.bridge.tick()
            self.bridge.sock.sendall.assert_called_once()

    def test_broker_connection_is_not_authorization(self):
        self.bridge.receive(0x20, b'\x00\x00')
        self.assertFalse(self.bridge.authenticated)
        self.bridge.receive(0x90, b'\x00\x01' + b'\x80' * 5 + b'\x00' * 3)
        self.assertFalse(self.bridge.authenticated)
        self.assertEqual(self.events[-1], {'event': 'status', 'value': 'pairing'})
    def test_remote_commands_require_authorization(self):
        with self.assertRaises(ValueError): self.bridge.command({'action': 'key', 'key': 'HOME'})
        self.bridge.sock.sendall.assert_not_called()
    def test_remote_key_payload_matches_vidaa_wire_protocol(self):
        self.bridge.authenticated = True
        for key, wire_value in [('UP', b'KEY_UP'), ('HOME', b'KEY_HOME'), ('OK', b'KEY_OK'), ('RETURNS', b'KEY_RETURNS'), ('PAUSE', b'KEY_PAUSE')]:
            self.bridge.command({'action': 'key', 'key': key})
            frame = self.bridge.sock.sendall.call_args[0][0]
            _, body, _ = extract(frame)
            topic_length = struct.unpack('!H', body[:2])[0]
            self.assertEqual(body[2 + topic_length:], wire_value)
    def test_catalog_indices_cannot_wrap_or_overrun(self):
        self.bridge.authenticated = True
        self.bridge.apps = [{'name': 'Example', 'appId': '1'}]
        self.bridge.sources = [{'sourceid': '1'}]
        for action in ('app', 'source'):
            for index in (-1, 1, 999):
                with self.assertRaises(ValueError): self.bridge.command({'action': action, 'index': index})
        self.bridge.sock.sendall.assert_not_called()

    def test_pin_validation_no_publish(self):
        for pin in ('', 'abcd', '１２３４', '123456789', '-1234'):
            with self.assertRaises(ValueError): self.bridge.command({'action': 'pin', 'pin': pin})
        self.bridge.sock.sendall.assert_not_called()
    def test_auth_success_and_token(self):
        self.bridge.message('/authentication', {'result': 1})
        self.assertTrue(self.bridge.authenticated)
        self.bridge.message('/tokenissuance', {'accesstoken': 'test-secret', 'refreshtoken': 'test-refresh'})
        value = [e for e in self.events if e['event'] == 'credentials'][0]['value']
        self.assertEqual(value['mqtt_username'], 'test-user')
        self.assertEqual(value['client_id'], 'test-client')
    def test_volume_does_not_invent_authentication(self):
        self.bridge.message('/volumechange', {'volume_type': 0, 'volume_value': 12})
        self.assertFalse(self.bridge.authenticated)
        self.assertEqual(self.events[-1]['value'], 12)
        self.bridge.message('/volumechange', {'volume_type': 2, 'volume_value': 1})
        self.assertTrue(self.events[-1]['value'])
    def test_qos1_ack_and_truncation(self):
        body = utf8('/volume') + b'\x00\x12' + json.dumps({'volume_value': 8}).encode()
        self.bridge.receive(0x32, body)
        self.bridge.sock.sendall.assert_called_with(b'\x40\x02\x00\x12')
        self.assertEqual(self.events[-1]['value'], 8)
        with self.assertRaises(ValueError): self.bridge.receive(0x30, b'\x00\x20short')
    def test_failed_auth_does_not_become_ready(self):
        self.bridge.pin_pending = True
        self.bridge.message('/authentication', {'result': 0})
        self.assertFalse(self.bridge.authenticated)
        self.assertEqual(self.events[-1]['event'], 'error')
    def test_volume_requires_pairing_and_reads_actual_value(self):
        with self.assertRaises(ValueError): self.bridge.command({'action': 'volume', 'value': 9})
        self.bridge.authenticated = True
        self.bridge.soap = Mock()
        self.bridge.read_volume = Mock()
        self.bridge.command({'action': 'volume', 'value': 9})
        self.bridge.soap.assert_called_once_with('SetVolume', {'InstanceID': 0, 'Channel': 'Master', 'DesiredVolume': 9})
        self.bridge.read_volume.assert_called_once()
        self.assertEqual(self.events, [])  # Never invent a confirmed volume from the requested value.
    def test_volume_completion_uses_readback_and_request_identity(self):
        self.bridge.authenticated = True
        self.bridge.soap = Mock()
        self.bridge.read_volume = Mock(return_value=14)
        self.bridge.command({'action': 'volume', 'value': 15, 'request': 42})
        self.assertEqual(self.events[-1], {'event': 'volume_result', 'request': 42, 'value': 14})

    def test_volume_failure_releases_in_flight_request(self):
        self.bridge.authenticated = True
        self.bridge.soap = Mock(side_effect=OSError('TV unavailable'))
        with self.assertRaises(OSError):
            self.bridge.command({'action': 'volume', 'value': 15, 'request': 43})
        self.assertEqual(self.events[-1], {'event': 'volume_result', 'request': 43, 'value': None})

    def test_changed_certificate_blocks_credentials_before_mqtt(self):
        raw, tls, context = Mock(), Mock(), Mock()
        tls.getpeercert.return_value = b'changed-server-certificate'
        context.wrap_socket.return_value = tls
        with patch('bridge.socket.create_connection', return_value=raw), patch('bridge.ssl.SSLContext', return_value=context):
            self.bridge.connect({'host':'192.168.1.100', 'device':'02:00:00:00:00:01', 'fingerprint':'old-pin'})
        tls.sendall.assert_not_called()
        self.assertEqual(self.events[-1]['event'], 'trust')
        self.assertTrue(self.events[-1]['changed'])
        self.assertIsNone(self.bridge.sock)
    def test_returned_catalog_preserves_index(self):
        self.bridge.message('/applist', [{'name': 'Netflix', 'appId': '1'}])
        self.bridge.command({'action': 'app', 'index': 0})
        sent = self.bridge.sock.sendall.call_args[0][0]
        self.assertIn(b'"appId":"1"', sent)
        self.assertTrue(self.bridge.authenticated)

if __name__ == '__main__': unittest.main()
