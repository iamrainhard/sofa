import sys
import pathlib
import threading
import unittest
from unittest.mock import patch, Mock
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / 'Resources'))
import tv_discovery as d

XML = b'<root><device><friendlyName>Living Room</friendlyName><manufacturer>Hisense</manufacturer><modelName>A4K</modelName><UDN>uuid:device-one</UDN></device></root>'
PIN = 'a' * 64

class DiscoveryTests(unittest.TestCase):
    def test_same_origin_only(self):
        for url in ['http://8.8.8.8/a', 'http://192.168.1.3/a', 'file:///etc/passwd', 'http://user:pass@192.168.1.2/a', 'http://192.168.1.2/a#fragment', 'https://192.168.1.2/a']:
            with self.assertRaises(ValueError):
                d.announcement(('HTTP/1.1 200 OK\r\nLOCATION: '+url+'\r\n\r\n').encode(), '192.168.1.2')
        with self.assertRaises(ValueError): d.announcement(b'garbage', '192.168.1.2')

    @patch('tv_discovery.certificate', return_value=PIN)
    @patch('tv_discovery.fetch', return_value=XML)
    def test_vidaa_netflix_announcement_finds_remote(self, fetch, cert):
        item = d.announcement(b'HTTP/1.1 200 OK\r\nlocation: http://192.168.1.2:9080\r\nusn: uuid:HISETVN123::urn:mdx-netflix-com:service:target:3\r\n\r\n', '192.168.1.2')
        tv = d.inspect_announcement(item)
        self.assertEqual(tv['platform'], 'vidaa')
        self.assertEqual(tv['identity'], 'upnp:uuid:device-one')
        self.assertEqual(tv['fingerprint'], PIN)
        fetch.assert_called_once_with('http://192.168.1.2:18400/MediaServer/rendererdevicedesc.xml', '192.168.1.2')

    @patch('tv_discovery.certificate', return_value=PIN)
    @patch('tv_discovery.fetch', return_value=XML)
    def test_vidaa_identity_survives_address_change(self, fetch, cert):
        one = d.inspect_candidate('192.168.1.33', 'vidaa')
        two = d.inspect_candidate('192.168.1.2', 'vidaa')
        self.assertEqual(one['identity'], two['identity'])
        self.assertNotEqual(one['host'], two['host'])

    @patch('tv_discovery.certificate', return_value=PIN)
    @patch('tv_discovery.fetch', return_value=b'{"device":{"id":"uuid:Samsung-one","name":"Bedroom","modelName":"Tizen"}}')
    def test_samsung_stable_id_and_secure_port(self, fetch, cert):
        tv = d.inspect_candidate('192.168.1.2', 'samsung')
        self.assertEqual(tv['identity'], 'samsung:uuid:samsung-one')
        cert.assert_called_once_with('192.168.1.2', 'samsung')

    @patch('tv_discovery.certificate', return_value=PIN)
    def test_android_bonjour_and_cast_require_remote(self, cert):
        for identity in ['bonjour:TV._androidtvremote2._tcp.local.', 'cast:device-id']:
            self.assertEqual(d.inspect_candidate('192.168.1.2', 'androidtv', identity)['identity'], identity)
        self.assertEqual(d.inspect_candidate('192.168.1.2', 'androidtv', 'Friendly name')['identity'], '')
        cert.side_effect = OSError('Remote Service absent')
        with self.assertRaises(OSError): d.inspect_candidate('192.168.1.2', 'androidtv', 'cast:device-id')

    @patch('tv_discovery.certificate', return_value=PIN)
    @patch('tv_discovery.fetch', return_value=b'<root><device><friendlyName>Generic</friendlyName></device></root>')
    def test_missing_identity_does_not_invent_one(self, fetch, cert):
        self.assertEqual(d.inspect_candidate('192.168.1.2', 'vidaa')['identity'], '')

    def test_cancelled_scan_does_not_emit(self):
        stop = threading.Event(); stop.set(); emit = Mock()
        d.discover([], emit, stop, duration=.01)
        emit.assert_not_called()

    @patch('tv_discovery.fetch', return_value=b'<!DOCTYPE root [<!ENTITY x "bad">]><root/>')
    def test_entity_rejected(self, fetch):
        with patch('tv_discovery.certificate', return_value=PIN):
            self.assertEqual(d.inspect_candidate('192.168.1.2', 'vidaa')['identity'], '')

if __name__ == '__main__': unittest.main()

class InterfaceDiscoveryTests(unittest.TestCase):
    def test_retry_and_failure_of_one_interface(self):
        bad, good = Mock(), Mock()
        bad.bind.side_effect = OSError('Interface went away')
        now = [0.0]
        def clock(): now[0] += .1; return now[0]
        with patch('tv_discovery.socket.socket', side_effect=[bad, good]), patch('tv_discovery.select.select', return_value=([], [], [])), patch('tv_discovery.time.monotonic', side_effect=clock):
            d.discover(['192.168.1.4', '192.168.2.4'], duration=4)
        bad.close.assert_called_once()
        self.assertEqual(good.sendto.call_count, 4, 'Both targets are retried on the working interface')
        good.close.assert_called_once()

class OptionalMetadataTests(unittest.TestCase):
    @patch('tv_discovery.certificate', return_value=PIN)
    @patch('tv_discovery.fetch', side_effect=OSError('DLNA disabled'))
    def test_vidaa_remote_survives_missing_dlna(self, fetch, cert):
        tv = d.inspect_candidate('192.168.1.2', 'vidaa', 'airplay:device-id', 'TV')
        self.assertEqual(tv['identity'], 'airplay:device-id')
        self.assertEqual(tv['fingerprint'], PIN)

    @patch('tv_discovery.certificate', return_value=PIN)
    def test_samsung_optional_api_does_not_hide_upnp_tv(self, cert):
        description = XML.replace(b'Hisense', b'Samsung')
        with patch('tv_discovery.fetch', side_effect=[description, OSError('No API'), description]):
            tv = d.inspect_announcement(('192.168.1.2', 'http://192.168.1.2:9197/desc.xml', 'uuid:one'))
        self.assertEqual(tv['platform'], 'samsung')
        self.assertEqual(tv['identity'], 'upnp:uuid:device-one')
