import functools
import http.client
import threading
import unittest
from http.server import ThreadingHTTPServer

from serve import Handler, ROOT


class ServerBoundaryTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(Handler, directory=str(ROOT)))
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join()

    def request(self, path, method='GET'):
        connection = http.client.HTTPConnection('127.0.0.1', self.server.server_port)
        connection.request(method, path)
        response = connection.getresponse()
        result = response.status, dict(response.getheaders()), response.read()
        connection.close()
        return result

    def test_loopback_static_content_and_no_external_script_policy(self):
        status, headers, body = self.request('/')
        self.assertEqual(status, 200)
        self.assertIn(b'60', body)
        self.assertIn("connect-src 'self'", headers['Content-Security-Policy'])
        status, headers, _ = self.request('/app.mjs')
        self.assertEqual(status, 200)
        self.assertIn('javascript', headers['Content-type'])

    def test_no_repository_escape_directory_listing_or_write_endpoint(self):
        for path in ['/../AGENTS.md', '/%2e%2e/%2e%2e/AGENTS.md', '/data/', '/serve.py', '/C:/Windows/win.ini']:
            self.assertEqual(self.request(path)[0], 404, path)
        self.assertEqual(self.request('/data/layout.json', 'POST')[0], 501)


if __name__ == '__main__':
    unittest.main()
