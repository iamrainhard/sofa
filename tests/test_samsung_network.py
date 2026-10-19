"""Local HTTP/SOAP fixture validates volume discovery and same-device boundaries."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import sys
import threading
import unittest
from unittest.mock import patch
from urllib.error import HTTPError

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'Resources'))
from samsung_network import VolumeService, description, fetch, local_url, xml, LIMIT, SERVICE


class SamsungNetworkTests(unittest.TestCase):
    def test_url_and_xml_boundaries(self):
        host = '192.168.1.23'
        self.assertEqual(local_url(f'http://{host}:9197/dmr/control', host), f'http://{host}:9197/dmr/control')
        for url in ('https://192.168.1.23/a', 'http://8.8.8.8/a', 'http://192.168.1.24/a',
                    'http://name.local/a', 'http://user:secret@192.168.1.23/a', 'http://192.168.1.23/a#b', 'file:///etc/passwd'):
            with self.assertRaises(ValueError):
                local_url(url, host)
        for data in (b'<!DOCTYPE x><x/>', b'<!ENTITY x "y"><x/>'):
            with self.assertRaises(ValueError):
                xml(data)

    def setUp(self):
        self.value, self.muted, self.fail, self.actions, self.maximum, self.brand = 27, True, False, ['GetVolume', 'SetVolume', 'GetMute'], 100, 'Samsung Electronics'
        self.posts = []
        fixture = self
        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass
            def do_GET(self):
                if self.path == '/redirect':
                    self.send_response(302); self.send_header('Location', '/root.xml'); self.end_headers(); return
                if self.path == '/large':
                    body = b'x' * (LIMIT + 1)
                elif self.path == '/root.xml':
                    body = f'<root><device><manufacturer>{fixture.brand}</manufacturer><serviceList><service><serviceType>{SERVICE}</serviceType><SCPDURL>/scpd.xml</SCPDURL><controlURL>/control</controlURL></service></serviceList></device></root>'.encode()
                else:
                    actions = ''.join(f'<action><name>{a}</name></action>' for a in fixture.actions)
                    body = f'<scpd><actionList>{actions}</actionList><serviceStateTable><stateVariable><name>Volume</name><allowedValueRange><minimum>0</minimum><maximum>{fixture.maximum}</maximum><step>1</step></allowedValueRange></stateVariable></serviceStateTable></scpd>'.encode()
                self.send_response(200); self.end_headers(); self.wfile.write(body)
            def do_POST(self):
                body = self.rfile.read(int(self.headers['Content-Length']))
                fixture.posts.append((self.headers['SOAPACTION'], body))
                action = self.headers['SOAPACTION'].split('#')[-1].strip('"')
                if fixture.fail:
                    response = b'<Envelope><Body><Fault/></Body></Envelope>'
                else:
                    root = xml(body)
                    assert root.findtext('.//InstanceID') == '0'
                    assert root.findtext('.//Channel') == 'Master'
                    if action == 'SetVolume':
                        fixture.value = int(root.findtext('.//DesiredVolume'))
                    value = f'<CurrentMute>{int(fixture.muted)}</CurrentMute>' if action == 'GetMute' else f'<CurrentVolume>{fixture.value}</CurrentVolume>' if action == 'GetVolume' else ''
                    response = f'<Envelope><Body><{action}Response>{value}</{action}Response></Body></Envelope>'.encode()
                self.send_response(200); self.end_headers(); self.wfile.write(response)
        self.server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.url = f'http://127.0.0.1:{self.server.server_port}'
        self.patches = [patch('samsung_network.host_address', side_effect=lambda h: h),
                        patch('samsung_network.locations', return_value=[('127.0.0.1', self.url + '/root.xml')])]
        for p in self.patches:
            p.start()

    def tearDown(self):
        self.server.shutdown(); self.server.server_close(); self.thread.join()
        for p in self.patches:
            p.stop()

    def test_real_discovery_read_set_and_mute(self):
        service = VolumeService.discover('127.0.0.1')
        self.assertIsNotNone(service)
        self.assertEqual(service.read(), dict(value=27, muted=True, source='readback'))
        self.assertEqual(service.set(64), dict(value=64, muted=True, source='readback'))
        self.assertTrue(any('#SetVolume' in action for action, _ in self.posts))
        for value in (-1, 101, True, '50'):
            with self.assertRaises(ValueError):
                service.set(value)
        self.fail = True
        with self.assertRaises(ValueError):
            service.read()

    def test_unavailable_or_nonstandard_volume_is_not_advertised(self):
        self.actions = ['GetVolume']
        self.assertIsNone(VolumeService.discover('127.0.0.1'))
        self.actions = ['GetVolume', 'SetVolume']
        self.maximum = 20
        self.assertIsNone(VolumeService.discover('127.0.0.1'))
        self.maximum = 100; self.value = 900
        self.assertIsNone(VolumeService.discover('127.0.0.1'))
        self.value = 27; self.brand = 'Other manufacturer'
        with self.assertRaises(ValueError):
            description('127.0.0.1', self.url + '/root.xml')
        self.assertIsNone(VolumeService.discover('127.0.0.1'))

    def test_http_rejects_redirects_and_large_responses(self):
        with self.assertRaises(HTTPError):
            fetch(self.url + '/redirect', '127.0.0.1')
        with self.assertRaises(ValueError):
            fetch(self.url + '/large', '127.0.0.1')
