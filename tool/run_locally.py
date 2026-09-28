"""Run the real SafeNest phone app in a browser on this machine.

WHY A PROXY AND NOT JUST A FILE SERVER. The app is a Flutter web build, so it
makes its API calls with the browser's fetch — and a browser refuses a call to
a different origin unless that origin says otherwise. The live API sets a CORS
allowlist and a CSP, neither of which mentions a page served off localhost, and
changing them means editing and restarting SafeNest's server, which is not
something to do so a UI can be looked at.

So this serves the app AND forwards /api to the real server from the same
origin. The browser sees one host and never asks the CORS question at all.

    python run_app.py [port] [--api https://app.safenesthub.in]

Then open http://127.0.0.1:<port>/ and sign in with that same address as the
server URL.
"""
from __future__ import annotations

import argparse
import mimetypes
import posixpath
import ssl
import sys
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "build" / "webapp"
API = "https://app.safenesthub.in"

# Hop-by-hop headers are about one connection and must not be relayed.
DROP = {
    "connection",
    "keep-alive",
    "proxy-authenticate",
    "proxy-authorization",
    "te",
    "trailers",
    "transfer-encoding",
    "upgrade",
    "host",
    "content-length",
    # The upstream's own CORS answer is for its own origin. Same-origin here
    # means the browser never looks, and a stale header only confuses it.
    "access-control-allow-origin",
    "access-control-allow-credentials",
    "content-security-policy",
    "content-encoding",
}


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "safenest-local"

    def log_message(self, fmt, *args):  # quieter; failures still print below
        pass

    # ---- the app itself -------------------------------------------------
    def _serve_file(self):
        path = posixpath.normpath(self.path.split("?", 1)[0]).lstrip("/")
        target = ROOT / path if path else ROOT / "index.html"
        if target.is_dir():
            target = target / "index.html"
        # A Flutter web app owns its routes, so anything unknown is the app.
        if not target.is_file():
            target = ROOT / "index.html"
        body = target.read_bytes()
        ctype = mimetypes.guess_type(target.name)[0] or "application/octet-stream"
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        # The whole point of running this is to see a build that was just made.
        self.send_header("Cache-Control", "no-store, must-revalidate")
        self.end_headers()
        self.wfile.write(body)

    # ---- everything the app asks the server ------------------------------
    def _proxy(self):
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else None
        req = urllib.request.Request(API + self.path, data=body, method=self.command)
        for k, v in self.headers.items():
            if k.lower() not in DROP:
                req.add_header(k, v)
        ctx = ssl.create_default_context()
        try:
            with urllib.request.urlopen(req, timeout=120, context=ctx) as r:
                data = r.read()
                status, headers = r.status, r.headers
        except urllib.error.HTTPError as e:
            # A 401 or a 422 is an ANSWER, not a failure — the app needs to see
            # it to say "wrong password" rather than "something went wrong".
            data = e.read()
            status, headers = e.code, e.headers
        except Exception as e:  # network, DNS, TLS
            msg = f'{{"detail":"local proxy could not reach {API}: {e}"}}'.encode()
            self.send_response(502)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(msg)))
            self.end_headers()
            self.wfile.write(msg)
            print(f"  !! {self.command} {self.path} -> {e}", flush=True)
            return

        self.send_response(status)
        for k, v in headers.items():
            if k.lower() not in DROP:
                self.send_header(k, v)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _route(self):
        try:
            if self.path.startswith(("/api/", "/openapi.json", "/media/", "/static/")):
                self._proxy()
            else:
                self._serve_file()
        except (BrokenPipeError, ConnectionResetError):
            pass  # the browser gave up on an image; normal while scrolling

    do_GET = do_POST = do_PUT = do_PATCH = do_DELETE = do_HEAD = _route

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Content-Length", "0")
        self.end_headers()


def main():
    global API, ROOT
    ap = argparse.ArgumentParser()
    ap.add_argument("port", nargs="?", type=int, default=5601)
    ap.add_argument("--api", default=API)
    ap.add_argument("--root", default=str(ROOT))
    a = ap.parse_args()

    API = a.api.rstrip("/")
    ROOT = Path(a.root)
    if not (ROOT / "index.html").is_file():
        sys.exit(f"no build at {ROOT} — run: flutter build web -t lib/web_main.dart")

    print(f"SafeNest, running locally")
    print(f"  app : http://127.0.0.1:{a.port}/")
    print(f"  api : {API}  (proxied, same origin — no CORS)")
    print(f"  sign in with the server address: http://127.0.0.1:{a.port}")
    ThreadingHTTPServer(("127.0.0.1", a.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
