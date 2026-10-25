#!/usr/bin/env python3
"""Exercise a real HTTP server using only Python's standard library."""
import concurrent.futures
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request


def main():
    binary = Path(__file__).resolve().parent / ".build/debug/LiquidServer"
    if not binary.exists():
        raise SystemExit("First run: swift build --package-path Examples/ServerRender")
    with socket.socket() as reservation:
        reservation.bind(("127.0.0.1", 0))
        port = reservation.getsockname()[1]
    base = f"http://127.0.0.1:{port}"
    # Local smoke tests must not send loopback traffic through a session proxy.
    client = urllib.request.build_opener(urllib.request.ProxyHandler({}))

    def get(path):
        with client.open(base + path, timeout=10) as response:
            return response.headers, response.read().decode("utf-8")

    with tempfile.TemporaryFile(mode="w+") as logs:
        server = subprocess.Popen(
            [str(binary)],
            env={**os.environ, "HOST": "127.0.0.1", "PORT": str(port)},
            stdout=logs,
            stderr=subprocess.STDOUT,
        )
        try:
            deadline = time.monotonic() + 20
            while True:
                try:
                    assert get("/health")[1] == "ok"
                    break
                except (urllib.error.URLError, TimeoutError):
                    if server.poll() is not None or time.monotonic() > deadline:
                        raise RuntimeError("Server did not become healthy")
                    time.sleep(0.1)

            headers, html = get("/")
            assert headers.get_content_type() == "text/html"
            assert headers.get_content_charset() == "utf-8"
            assert headers["Cache-Control"] == "no-store"
            assert "Hello, Swift friend." in html
            assert html.count('data-product="') == 3
            assert "Sold out" in html and "Jasmine Tea" in html

            _, html = get("/?category=tea&name=Ada")
            assert "Hello, Ada." in html and "Tea time" in html
            assert html.count('data-product="') == 1
            assert "Ceramic Cup" not in html
            _, html = get("/?empty=1")
            assert "No products in this collection." in html
            assert 'data-product="' not in html

            attack = '<script>alert("hello")</script>'
            _, html = get("/?" + urllib.parse.urlencode({"name": attack, "empty": "1"}))
            assert attack not in html
            assert "&lt;script&gt;alert(&quot;hello&quot;)&lt;/script&gt;" in html
            assert urllib.parse.quote_plus(attack) in html
            assert "Hello, Swift friend." in get("/")[1]
            assert get("/?category=unknown")[1].count('data-product="') == 3

            def check_visitor(index):
                name = f"Visitor-{index}-🦉"
                _, page = get("/?" + urllib.parse.urlencode({"name": name}))
                assert f"Hello, {name}." in page
                assert page.count('data-product="') == 3

            with concurrent.futures.ThreadPoolExecutor(max_workers=4) as workers:
                list(workers.map(check_visitor, range(8)))
            try:
                get("/missing")
                raise AssertionError("Unknown routes must return 404")
            except urllib.error.HTTPError as error:
                assert error.code == 404
            print("SSR smoke checks passed: HTTP, HTML, filters, empty state, escaping, concurrent requests, 404.")
        except BaseException:
            logs.seek(0)
            print(logs.read())
            raise
        finally:
            server.terminate()
            try:
                server.wait(timeout=10)
            except subprocess.TimeoutExpired:
                server.kill()
                server.wait(timeout=5)


if __name__ == "__main__":
    main()
