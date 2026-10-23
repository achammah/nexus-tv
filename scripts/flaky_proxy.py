"""A local stand-in for the provider's stream server, for the network-cut test.

The app is launched with -NXStreamBase http://127.0.0.1:18888, so its stream URLs point here; this process
forwards each request to the real server (first line of the file named by NXTV_ACCOUNT_FILE), follows redirects itself,
and rewrites HLS playlists so every segment comes back through here too. Stopping this process cuts the
stream like a lost network. It logs nothing (stream URLs carry the login), only a request count in
build/proxy-requests.txt. Usage: python3 -I scripts/flaky_proxy.py [port]
"""
import os
import sys
import threading
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

KEY = [l.strip() for l in open(os.path.expanduser(os.environ['NXTV_ACCOUNT_FILE'])).read().splitlines() if l.strip()]
BASE = KEY[0].rstrip('/')
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 18888
ME = 'http://127.0.0.1:%d' % PORT
COUNT = [0]
LOCK = threading.Lock()


def wrap(url):
    return ME + '/__abs__/' + urllib.parse.quote(url, safe='')


class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def log_message(self, *a):        # silent: paths carry the login
        pass

    def do_GET(self):
        with LOCK:
            COUNT[0] += 1
            try:
                with open('build/proxy-requests.txt', 'w') as f:
                    f.write(str(COUNT[0]))
            except OSError:
                pass
        target = urllib.parse.unquote(self.path[len('/__abs__/'):]) if self.path.startswith('/__abs__/') else BASE + self.path
        req = urllib.request.Request(target, headers={'User-Agent': self.headers.get('User-Agent', 'Mozilla/5.0')})
        if self.headers.get('Range'):
            req.add_header('Range', self.headers['Range'])
        try:
            r = urllib.request.urlopen(req, timeout=20)
        except urllib.error.HTTPError as e:
            r = e
        except OSError:
            self.send_error(502)
            return
        ctype = r.headers.get('Content-Type', '')
        final = r.geturl() if hasattr(r, 'geturl') else target
        if 'mpegurl' in ctype.lower() or urllib.parse.urlsplit(final).path.endswith('.m3u8'):
            body = r.read().decode('utf-8', 'replace')
            out = []
            for line in body.splitlines():
                if line and not line.startswith('#'):
                    line = wrap(urllib.parse.urljoin(final, line))
                out.append(line)
            data = ('\n'.join(out) + '\n').encode()
            self.send_response(r.status if hasattr(r, 'status') else 200)
            self.send_header('Content-Type', ctype or 'application/vnd.apple.mpegurl')
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        self.send_response(getattr(r, 'status', 200))
        for h in ('Content-Type', 'Content-Length', 'Content-Range', 'Accept-Ranges'):
            if r.headers.get(h):
                self.send_header(h, r.headers[h])
        self.end_headers()
        try:
            while True:
                chunk = r.read(65536)
                if not chunk:
                    break
                self.wfile.write(chunk)
        except OSError:
            pass


if __name__ == '__main__':
    ThreadingHTTPServer.daemon_threads = True
    ThreadingHTTPServer(('127.0.0.1', PORT), Handler).serve_forever()
