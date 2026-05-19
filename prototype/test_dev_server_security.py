#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import os
import threading
import unittest
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer
from pathlib import Path
from tempfile import TemporaryDirectory
from urllib.parse import quote


MODULE_PATH = Path(__file__).with_name("dev_server.py")
SPEC = importlib.util.spec_from_file_location("dev_server", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
dev_server = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(dev_server)


class DevServerSecurityBoundaryTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = TemporaryDirectory()
        self.addCleanup(self.temp_dir.cleanup)

        self.previous_workspace = dev_server.WORKSPACE_ROOT
        self.previous_mutation_env = os.environ.get(dev_server.ENABLE_MUTATION_ENV)
        os.environ.pop(dev_server.ENABLE_MUTATION_ENV, None)

        workspace = Path(self.temp_dir.name) / "workspace"
        workspace.mkdir()
        (workspace / "main.styio").write_text("module Main {}\n", encoding="utf-8")
        dev_server.WORKSPACE_ROOT = workspace.resolve()

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), dev_server.PrototypeHandler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.base_url = f"http://127.0.0.1:{self.server.server_port}"
        self.origin = self.base_url
        self.session_cookie = self.load_session_cookie()

    def tearDown(self) -> None:
        self.server.shutdown()
        self.thread.join(timeout=5)
        self.server.server_close()
        dev_server.WORKSPACE_ROOT = self.previous_workspace

        if self.previous_mutation_env is None:
            os.environ.pop(dev_server.ENABLE_MUTATION_ENV, None)
        else:
            os.environ[dev_server.ENABLE_MUTATION_ENV] = self.previous_mutation_env

    def request(
        self,
        method: str,
        path: str,
        *,
        body: dict | None = None,
        headers: dict[str, str] | None = None,
        follow_redirects: bool = True,
    ) -> tuple[int, dict[str, str], bytes]:
        request_headers = headers.copy() if headers else {}
        data = None
        if body is not None:
            data = json.dumps(body).encode("utf-8")
            request_headers.setdefault("Content-Type", "application/json")

        request = urllib.request.Request(
            f"{self.base_url}{path}",
            data=data,
            headers=request_headers,
            method=method,
        )
        opener = urllib.request.build_opener()
        if not follow_redirects:
            opener = urllib.request.build_opener(_NoRedirectHandler)

        try:
            with opener.open(request, timeout=5) as response:
                return response.status, dict(response.headers), response.read()
        except urllib.error.HTTPError as error:
            return error.code, dict(error.headers), error.read()

    def load_session_cookie(self) -> str:
        status, headers, _ = self.request("GET", "/editor")
        self.assertEqual(status, 200)

        set_cookie = headers.get("Set-Cookie")
        self.assertIsNotNone(set_cookie)
        assert set_cookie is not None
        self.assertIn("HttpOnly", set_cookie)
        self.assertIn("SameSite=Strict", set_cookie)
        return set_cookie.split(";", 1)[0]

    def header_value(self, headers: dict[str, str], name: str) -> str:
        for header_name, value in headers.items():
            if header_name.casefold() == name.casefold():
                return value
        return ""

    def test_root_redirects_to_canonical_editor_route(self) -> None:
        status, headers, body = self.request(
            "GET",
            "/",
            follow_redirects=False,
        )

        self.assertEqual(status, 302)
        self.assertEqual(headers.get("Location"), "/editor")
        self.assertEqual(body, b"")

    def test_editor_route_serves_focused_editor_page(self) -> None:
        status, headers, body = self.request("GET", "/editor")

        self.assertEqual(status, 200)
        self.assertIn("text/html", self.header_value(headers, "Content-Type"))
        self.assertIn(b'id="editorInput"', body)
        self.assertIn(b'./editor.js', body)
        self.assertNotIn(b"Design Repository", body)

    def test_removed_legacy_entrypoint_is_not_served(self) -> None:
        for route in ("/index", "/index.html"):
            with self.subTest(route=route):
                status, _, body = self.request(
                    "GET",
                    route,
                    follow_redirects=False,
                )

                self.assertEqual(status, 404)
                self.assertNotIn(b"Design Repository", body)

    def test_removed_legacy_entrypoint_assets_are_not_served(self) -> None:
        for route in ("/app.js", "/styles.css"):
            with self.subTest(route=route):
                status, _, _ = self.request(
                    "GET",
                    route,
                    follow_redirects=False,
                )

                self.assertEqual(status, 404)

    def authenticated_headers(self, *, origin: str | None = None) -> dict[str, str]:
        headers = {"Cookie": self.session_cookie}
        if origin is not None:
            headers["Origin"] = origin
        return headers

    def test_api_read_routes_reject_missing_session_cookie(self) -> None:
        status, _, body = self.request("GET", "/api/workspace")

        self.assertEqual(status, 403)
        self.assertIn(b"missing or invalid dev server session credential", body)

    def test_api_read_routes_accept_same_origin_session_cookie(self) -> None:
        status, _, body = self.request("GET", "/api/workspace", headers=self.authenticated_headers())

        self.assertEqual(status, 200)
        payload = json.loads(body.decode("utf-8"))
        self.assertEqual(payload["workspaceName"], "workspace")
        self.assertEqual(payload["files"], ["main.styio"])

    def test_api_read_routes_accept_explicit_token_header(self) -> None:
        status, _, body = self.request(
            "GET",
            "/api/workspace",
            headers={dev_server.SESSION_TOKEN_HEADER: dev_server.SESSION_TOKEN},
        )

        self.assertEqual(status, 200)
        payload = json.loads(body.decode("utf-8"))
        self.assertEqual(payload["files"], ["main.styio"])

    def test_browser_file_reads_are_limited_to_current_workspace(self) -> None:
        outside_file = Path(self.temp_dir.name) / "outside.txt"
        outside_file.write_text("outside secret\n", encoding="utf-8")

        status, _, body = self.request(
            "GET",
            f"/api/browser/file?path={quote(str(outside_file))}",
            headers=self.authenticated_headers(),
        )

        self.assertEqual(status, 403)
        self.assertIn(b"limited to the current workspace", body)
        self.assertNotIn(b"outside secret", body)

    def test_rejects_non_local_host_header(self) -> None:
        status, _, body = self.request(
            "GET",
            "/api/workspace",
            headers={"Host": f"attacker.test:{self.server.server_port}", "Cookie": self.session_cookie},
        )

        self.assertEqual(status, 403)
        self.assertIn(b"host must be localhost", body)

    def test_mutation_requires_same_origin(self) -> None:
        status, _, body = self.request(
            "POST",
            "/api/workspace/create-file",
            body={"path": "created.styio", "content": "x"},
            headers=self.authenticated_headers(),
        )

        self.assertEqual(status, 403)
        self.assertIn(b"same-origin request origin is required", body)
        self.assertFalse((dev_server.WORKSPACE_ROOT / "created.styio").exists())

    def test_mutation_is_disabled_without_explicit_opt_in(self) -> None:
        status, _, body = self.request(
            "POST",
            "/api/workspace/create-file",
            body={"path": "created.styio", "content": "x"},
            headers=self.authenticated_headers(origin=self.origin),
        )

        self.assertEqual(status, 403)
        self.assertIn(dev_server.ENABLE_MUTATION_ENV.encode("utf-8"), body)
        self.assertFalse((dev_server.WORKSPACE_ROOT / "created.styio").exists())

    def test_mutation_can_be_enabled_for_local_dev_session(self) -> None:
        os.environ[dev_server.ENABLE_MUTATION_ENV] = "1"

        status, _, body = self.request(
            "POST",
            "/api/workspace/create-file",
            body={"path": "created.styio", "content": "x"},
            headers=self.authenticated_headers(origin=self.origin),
        )

        self.assertEqual(status, 201, body.decode("utf-8"))
        self.assertEqual((dev_server.WORKSPACE_ROOT / "created.styio").read_text(encoding="utf-8"), "x")

    def test_mutation_rejects_untrusted_origin_even_when_enabled(self) -> None:
        os.environ[dev_server.ENABLE_MUTATION_ENV] = "1"

        status, _, body = self.request(
            "POST",
            "/api/workspace/create-file",
            body={"path": "created.styio", "content": "x"},
            headers=self.authenticated_headers(origin="http://attacker.test"),
        )

        self.assertEqual(status, 403)
        self.assertIn(b"origin is not allowed", body)
        self.assertFalse((dev_server.WORKSPACE_ROOT / "created.styio").exists())


class _NoRedirectHandler(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


if __name__ == "__main__":
    unittest.main()
