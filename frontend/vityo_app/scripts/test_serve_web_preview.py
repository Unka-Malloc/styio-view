#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import threading
import unittest
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer
from pathlib import Path
from tempfile import TemporaryDirectory


MODULE_PATH = Path(__file__).with_name("serve_web_preview.py")
SPEC = importlib.util.spec_from_file_location("serve_web_preview", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
serve_web_preview = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(serve_web_preview)


class PreviewHostedDocumentRouteTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = TemporaryDirectory()
        self.addCleanup(self.temp_dir.cleanup)

        self.previous_web_root = serve_web_preview.WEB_ROOT
        web_root = Path(self.temp_dir.name)
        (web_root / "index.html").write_text(
            '<html><body>Legacy entrypoint page</body></html>',
            encoding="utf-8",
        )
        (web_root / "editor.html").write_text(
            '<html><textarea id="editorInput"></textarea><script src="./editor.js"></script></html>',
            encoding="utf-8",
        )
        (web_root / "editor.js").write_text("console.log('editor');", encoding="utf-8")
        serve_web_preview.WEB_ROOT = web_root

        self.server = ThreadingHTTPServer(
            ("127.0.0.1", 0),
            serve_web_preview.PreviewHandler,
        )
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.base_url = f"http://127.0.0.1:{self.server.server_port}"

    def tearDown(self) -> None:
        self.server.shutdown()
        self.thread.join(timeout=5)
        self.server.server_close()
        serve_web_preview.WEB_ROOT = self.previous_web_root

    def raw_request(
        self,
        method: str,
        path: str,
        body: dict | None = None,
    ) -> tuple[int, dict[str, str], bytes]:
        data = None
        headers = {}
        if body is not None:
            data = json.dumps(body).encode("utf-8")
            headers["Content-Type"] = "application/json"

        request = urllib.request.Request(
            f"{self.base_url}{path}",
            data=data,
            headers=headers,
            method=method,
        )
        opener = urllib.request.build_opener(_NoRedirectHandler)

        try:
            with opener.open(request, timeout=5) as response:
                return response.status, dict(response.headers), response.read()
        except urllib.error.HTTPError as error:
            return error.code, dict(error.headers), error.read()

    def request(self, path: str, body: dict) -> tuple[int, dict]:
        status, _, response_body = self.raw_request("POST", path, body)
        return status, json.loads(response_body.decode("utf-8"))

    def test_root_redirects_to_editor(self) -> None:
        status, headers, body = self.raw_request("GET", "/")

        self.assertEqual(status, 302)
        self.assertEqual(headers["Location"], "/editor")
        self.assertEqual(body, b"")

    def test_editor_route_serves_focused_editor_page(self) -> None:
        status, headers, body = self.raw_request("GET", "/editor")

        self.assertEqual(status, 200)
        self.assertIn("text/html", _header_value(headers, "Content-Type"))
        self.assertIn(b'id="editorInput"', body)
        self.assertIn(b"./editor.js", body)
        self.assertNotIn(b"Legacy entrypoint page", body)

    def test_removed_legacy_entrypoint_is_not_served(self) -> None:
        for route in ("/index", "/index.html"):
            with self.subTest(route=route):
                status, _, body = self.raw_request("GET", route)

                self.assertEqual(status, 404)
                self.assertNotIn(b"Legacy entrypoint page", body)

    def test_document_load_returns_editor_payload(self) -> None:
        status, payload = self.request(
            "/api/styio-hosted/v1/workspaces/demo-workspace/documents/load",
            {"path": "/workspace/demo/src/main.styio"},
        )

        self.assertEqual(status, 200)
        self.assertEqual(payload["returncode"], 0)
        self.assertEqual(payload["payload"]["path"], "/workspace/demo/src/main.styio")
        self.assertEqual(payload["payload"]["document_text"], "value = 1\nvalue\n")
        self.assertEqual(payload["payload"]["revision"], 1)

    def test_document_save_acknowledges_next_revision(self) -> None:
        status, payload = self.request(
            "/api/styio-hosted/v1/workspaces/demo-workspace/documents/save",
            {
                "path": "/workspace/demo/src/main.styio",
                "document_text": "value = 1\n",
                "revision": 7,
            },
        )

        self.assertEqual(status, 200)
        self.assertEqual(payload["returncode"], 0)
        self.assertEqual(payload["payload"]["path"], "/workspace/demo/src/main.styio")
        self.assertEqual(payload["payload"]["revision"], 8)
        self.assertTrue(payload["payload"]["saved"])


class _NoRedirectHandler(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def _header_value(headers: dict[str, str], name: str) -> str:
    for key, value in headers.items():
        if key.lower() == name.lower():
            return value
    raise KeyError(name)


if __name__ == "__main__":
    unittest.main()
