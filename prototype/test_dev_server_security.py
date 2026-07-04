#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import os
import subprocess
import threading
import time
import unittest
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer
from pathlib import Path
from tempfile import TemporaryDirectory
from urllib.parse import quote
from unittest import mock


MODULE_PATH = Path(__file__).with_name("dev_server.py")
SPEC = importlib.util.spec_from_file_location("dev_server", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
dev_server = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(dev_server)


class DevServerPathUtilityTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = TemporaryDirectory()
        self.addCleanup(self.temp_dir.cleanup)
        self.previous_workspace = dev_server.WORKSPACE_ROOT
        self.previous_root = dev_server.ROOT
        self.previous_workspace_config = dev_server.WORKSPACE_CONFIG
        self.previous_default_workspace = dev_server.DEFAULT_WORKSPACE
        self.previous_mutation_env = os.environ.get(dev_server.ENABLE_MUTATION_ENV)
        os.environ.pop(dev_server.ENABLE_MUTATION_ENV, None)

        self.root = Path(self.temp_dir.name)
        self.workspace = self.root / "workspace"
        self.workspace.mkdir()
        (self.workspace / "main.styio").write_text("module Main {}\n", encoding="utf-8")
        (self.workspace / "src").mkdir()
        (self.workspace / "src" / "lib.styio").write_text("module Lib {}\n", encoding="utf-8")
        (self.workspace / ".hidden").write_text("ignored\n", encoding="utf-8")
        (self.workspace / "node_modules").mkdir()
        dev_server.ROOT = self.root
        dev_server.DEFAULT_WORKSPACE = self.root / "default-workspace"
        dev_server.WORKSPACE_CONFIG = self.root / ".workspace-root"
        dev_server.WORKSPACE_ROOT = self.workspace.resolve()

    def tearDown(self) -> None:
        dev_server.WORKSPACE_ROOT = self.previous_workspace
        dev_server.ROOT = self.previous_root
        dev_server.WORKSPACE_CONFIG = self.previous_workspace_config
        dev_server.DEFAULT_WORKSPACE = self.previous_default_workspace
        if self.previous_mutation_env is None:
            os.environ.pop(dev_server.ENABLE_MUTATION_ENV, None)
        else:
            os.environ[dev_server.ENABLE_MUTATION_ENV] = self.previous_mutation_env

    def test_host_cookie_token_and_mutation_helpers_cover_edge_cases(self) -> None:
        self.assertIsNone(dev_server.split_host_port(None))
        self.assertIsNone(dev_server.split_host_port(""))
        self.assertIsNone(dev_server.split_host_port("localhost:bad"))
        self.assertIsNone(dev_server.split_host_port(":4180"))
        self.assertEqual(dev_server.split_host_port("LOCALHOST.:4180"), ("localhost", 4180))
        self.assertTrue(dev_server.is_allowed_local_netloc("127.0.0.1:4180", expected_port=4180))
        self.assertFalse(dev_server.is_allowed_local_netloc("127.0.0.1:4181", expected_port=4180))
        self.assertFalse(dev_server.is_allowed_local_netloc("example.test:4180", expected_port=4180))
        self.assertFalse(dev_server.is_allowed_local_netloc(None, expected_port=4180))

        cookies = dev_server.parse_cookie_header("a=1; missing; b = two ; styio_dev_server_session=token")
        self.assertEqual(cookies["a"], "1")
        self.assertEqual(cookies["b"], "two")
        self.assertEqual(cookies[dev_server.SESSION_COOKIE_NAME], "token")
        self.assertEqual(dev_server.parse_cookie_header(None), {})

        self.assertFalse(dev_server.token_matches(None))
        self.assertFalse(dev_server.token_matches("\udcff"))
        self.assertTrue(dev_server.token_matches(dev_server.SESSION_TOKEN))

        os.environ[dev_server.ENABLE_MUTATION_ENV] = " YES "
        self.assertTrue(dev_server.mutation_enabled())
        os.environ[dev_server.ENABLE_MUTATION_ENV] = "off"
        self.assertFalse(dev_server.mutation_enabled())

    def test_workspace_loading_setting_and_path_resolution(self) -> None:
        relative_workspace = self.root / "relative"
        relative_workspace.mkdir()
        dev_server.WORKSPACE_CONFIG.write_text("relative\n", encoding="utf-8")
        self.assertEqual(dev_server.load_workspace_root(), relative_workspace.resolve())

        absolute_workspace = self.root / "absolute"
        absolute_workspace.mkdir()
        dev_server.WORKSPACE_CONFIG.write_text(str(absolute_workspace), encoding="utf-8")
        self.assertEqual(dev_server.load_workspace_root(), absolute_workspace.resolve())

        dev_server.WORKSPACE_CONFIG.write_text(str(self.root / "missing"), encoding="utf-8")
        self.assertEqual(dev_server.load_workspace_root(), dev_server.DEFAULT_WORKSPACE.resolve())
        self.assertTrue(dev_server.DEFAULT_WORKSPACE.is_dir())

        selected = dev_server.set_workspace_root(str(self.workspace))
        self.assertEqual(selected, self.workspace.resolve())
        self.assertEqual(dev_server.WORKSPACE_CONFIG.read_text(encoding="utf-8"), str(self.workspace.resolve()))
        with self.assertRaisesRegex(ValueError, "workspace path must point to an existing directory"):
            dev_server.set_workspace_root(str(self.workspace / "main.styio"))

        self.assertTrue(dev_server.is_ignored(self.workspace / ".hidden"))
        self.assertTrue(dev_server.is_ignored(self.workspace / "node_modules"))
        self.assertEqual(dev_server.iter_clean_parts("./src/lib.styio"), ["src", "lib.styio"])
        with self.assertRaisesRegex(ValueError, "path escapes workspace root"):
            dev_server.iter_clean_parts("../outside")
        with self.assertRaisesRegex(ValueError, "path casing must match existing entry"):
            dev_server.lookup_case_sensitive_child(self.workspace, "MAIN.STYIO")
        self.assertIsNone(dev_server.lookup_case_sensitive_child(self.workspace / "missing", "x"))
        self.assertEqual(
            dev_server.resolve_existing_path_case_sensitive("workspace", base=self.root),
            self.workspace.resolve(),
        )
        self.assertEqual(
            dev_server.resolve_workspace_path("src/lib.styio", require_exists=True),
            (self.workspace / "src" / "lib.styio").resolve(),
        )
        self.assertEqual(dev_server.resolve_workspace_path("new.styio"), self.workspace.resolve() / "new.styio")
        with self.assertRaisesRegex(ValueError, "path must be a non-empty string"):
            dev_server.resolve_workspace_path("")
        with self.assertRaisesRegex(ValueError, "path not found"):
            dev_server.resolve_workspace_path("missing/file.styio")
        outside = self.root / "outside"
        outside.mkdir()
        link = self.workspace / "outside-link"
        self._create_directory_link(link, outside)
        with self.assertRaisesRegex(ValueError, "path escapes workspace root"):
            dev_server.resolve_workspace_path("outside-link", require_exists=True)
        broken = self.root / "broken-link"
        try:
            broken.symlink_to(self.root / "missing-target")
        except OSError:
            pass
        else:
            with self.assertRaisesRegex(ValueError, "browser path must point to an existing file or directory"):
                dev_server.resolve_browser_path(str(broken))

    def _create_directory_link(self, link: Path, target: Path) -> None:
        try:
            link.symlink_to(target, target_is_directory=True)
            return
        except OSError:
            if os.name != "nt":
                raise

        result = subprocess.run(
            ["cmd", "/c", "mklink", "/J", str(link), str(target)],
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            self.skipTest(f"directory links are unavailable: {result.stderr or result.stdout}")

    def test_workspace_and_browser_snapshots_filter_entries_and_select_files(self) -> None:
        snapshot = dev_server.workspace_snapshot()
        self.assertEqual(snapshot["workspaceName"], "workspace")
        self.assertEqual(snapshot["files"], ["src/lib.styio", "main.styio"])
        self.assertTrue(any(entry["type"] == "directory" and entry["name"] == "src" for entry in snapshot["entries"]))

        browser = dev_server.browser_entry_snapshot(str(self.workspace / "main.styio"), include_files=True)
        self.assertEqual(browser["selectedFilePath"], str((self.workspace / "main.styio").resolve()))
        self.assertTrue(any(file["name"] == "main.styio" for file in browser["files"]))
        self.assertTrue(any(directory["name"] == "src" for directory in browser["directories"]))
        self.assertFalse(any(file["name"] == ".hidden" for file in browser["files"]))

        workspace_browser = dev_server.browser_entry_snapshot(None)
        self.assertEqual(workspace_browser["currentPath"], str(self.workspace.resolve()))
        self.assertTrue(dev_server.path_is_within_root(self.workspace / "src", self.workspace))
        self.assertFalse(dev_server.path_is_within_root(self.root, self.workspace))
        with self.assertRaisesRegex(ValueError, "path must point to an existing directory"):
            dev_server.resolve_browser_path(str(self.workspace / "missing"))

    def test_main_starts_server_and_closes_on_keyboard_interrupt(self) -> None:
        events: list[str] = []

        class FakeServer:
            def __init__(self, *args, **kwargs):
                events.append(f"init:{args[0]}")

            def serve_forever(self) -> None:
                events.append("serve")
                raise KeyboardInterrupt

            def server_close(self) -> None:
                events.append("close")

        with mock.patch.object(dev_server, "ThreadingHTTPServer", FakeServer):
            os.environ[dev_server.ENABLE_MUTATION_ENV] = "1"
            dev_server.main()

        self.assertEqual(events, ["init:('127.0.0.1', 4180)", "serve", "close"])


class DevServerSecurityBoundaryTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = TemporaryDirectory()
        self.addCleanup(self.temp_dir.cleanup)

        self.previous_workspace = dev_server.WORKSPACE_ROOT
        self.previous_workspace_config = dev_server.WORKSPACE_CONFIG
        self.previous_mutation_env = os.environ.get(dev_server.ENABLE_MUTATION_ENV)
        os.environ.pop(dev_server.ENABLE_MUTATION_ENV, None)

        workspace = Path(self.temp_dir.name) / "workspace"
        workspace.mkdir()
        (workspace / "main.styio").write_text("module Main {}\n", encoding="utf-8")
        dev_server.WORKSPACE_ROOT = workspace.resolve()
        dev_server.WORKSPACE_CONFIG = Path(self.temp_dir.name) / ".workspace-root"

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
        dev_server.WORKSPACE_CONFIG = self.previous_workspace_config

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
        retry_on_disconnect: bool = False,
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

        for attempt in range(2 if retry_on_disconnect else 1):
            try:
                with opener.open(request, timeout=5) as response:
                    return response.status, dict(response.headers), response.read()
            except urllib.error.HTTPError as error:
                return error.code, dict(error.headers), error.read()
            except (ConnectionAbortedError, ConnectionResetError):
                if attempt == 0 and retry_on_disconnect:
                    time.sleep(0.05)
                    continue
                raise
        raise AssertionError("request retry loop exited unexpectedly")

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

    def authenticated_post_headers(self, *, origin: str | None = None) -> dict[str, str]:
        headers = self.authenticated_headers(origin=origin)
        headers["Content-Type"] = "application/json"
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

    def test_api_read_routes_accept_bearer_token_and_reject_cross_site_fetch(self) -> None:
        status, _, body = self.request(
            "GET",
            "/api/workspace",
            headers={"Authorization": f"Bearer {dev_server.SESSION_TOKEN}"},
        )
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(body.decode("utf-8"))["files"], ["main.styio"])

        status, _, body = self.request(
            "GET",
            "/api/workspace",
            headers={
                "Cookie": self.session_cookie,
                "Sec-Fetch-Site": "cross-site",
            },
        )
        self.assertEqual(status, 403)
        self.assertIn(b"cross-site requests are not allowed", body)

    def test_head_issues_cookie_for_document_but_not_api(self) -> None:
        status, headers, _ = self.request("HEAD", "/editor.html")
        self.assertEqual(status, 200)
        self.assertIn("Set-Cookie", headers)

        status, headers, _ = self.request("HEAD", "/api/workspace", headers=self.authenticated_headers())
        self.assertEqual(status, 404)
        self.assertNotIn("Set-Cookie", headers)

        status, _, body = self.request(
            "HEAD",
            "/editor.html",
            headers={"Host": f"attacker.test:{self.server.server_port}"},
        )
        self.assertEqual(status, 403)
        self.assertEqual(body, b"")

    def test_browser_entries_and_file_read_routes_cover_success_and_bad_inputs(self) -> None:
        status, _, body = self.request(
            "GET",
            f"/api/browser/entries?path={quote(str(dev_server.WORKSPACE_ROOT))}&includeFiles=1",
            headers=self.authenticated_headers(),
        )
        self.assertEqual(status, 200)
        payload = json.loads(body.decode("utf-8"))
        self.assertTrue(any(file["name"] == "main.styio" for file in payload["files"]))

        status, _, body = self.request(
            "GET",
            "/api/browser/entries?path=/missing/path",
            headers=self.authenticated_headers(),
        )
        self.assertEqual(status, 400)
        self.assertIn(b"path must point to an existing directory", body)

        status, _, body = self.request(
            "GET",
            "/api/browser/file",
            headers=self.authenticated_headers(),
        )
        self.assertEqual(status, 400)
        self.assertIn(b"path must be a non-empty string", body)

        status, _, body = self.request(
            "GET",
            f"/api/browser/file?path={quote(str(dev_server.WORKSPACE_ROOT))}",
            headers=self.authenticated_headers(),
        )
        self.assertEqual(status, 400)
        self.assertIn(b"path must point to a file", body)

        status, _, body = self.request(
            "GET",
            f"/api/browser/file?path={quote(str(dev_server.WORKSPACE_ROOT / 'main.styio'))}",
            headers=self.authenticated_headers(),
        )
        self.assertEqual(status, 200)
        self.assertIn(b"module Main", body)

        binary = dev_server.WORKSPACE_ROOT / "binary.txt"
        binary.write_bytes(b"\xff")
        status, _, body = self.request(
            "GET",
            f"/api/browser/file?path={quote(str(binary))}",
            headers=self.authenticated_headers(),
        )
        self.assertEqual(status, 415)
        self.assertIn(b"file is not utf-8 text", body)

        missing_after_resolution = mock.Mock()
        missing_after_resolution.is_file.return_value = True
        missing_after_resolution.read_text.side_effect = FileNotFoundError
        with mock.patch.object(dev_server, "resolve_browser_path", return_value=missing_after_resolution):
            with mock.patch.object(dev_server, "path_is_within_root", return_value=True):
                status, _, body = self.request(
                    "GET",
                    "/api/browser/file?path=/tmp/disappeared.txt",
                    headers=self.authenticated_headers(),
                )
        self.assertEqual(status, 404)
        self.assertIn(b"file not found", body)

    def test_workspace_file_routes_cover_read_write_and_bad_inputs(self) -> None:
        status, _, body = self.request(
            "GET",
            "/api/workspace/file/main.styio",
            headers=self.authenticated_headers(),
        )
        self.assertEqual(status, 200)
        self.assertIn(b"module Main", body)

        status, _, body = self.request(
            "GET",
            "/api/workspace/file/missing.styio",
            headers=self.authenticated_headers(),
        )
        self.assertEqual(status, 400)
        self.assertIn(b"path not found", body)

        binary = dev_server.WORKSPACE_ROOT / "binary.styio"
        binary.write_bytes(b"\xff")
        status, _, body = self.request(
            "GET",
            "/api/workspace/file/binary.styio",
            headers=self.authenticated_headers(),
        )
        self.assertEqual(status, 415)
        self.assertIn(b"file is not utf-8 text", body)

        missing_after_resolution = mock.Mock()
        missing_after_resolution.read_text.side_effect = FileNotFoundError
        with mock.patch.object(dev_server, "resolve_workspace_path", return_value=missing_after_resolution):
            status, _, body = self.request(
                "GET",
                "/api/workspace/file/disappeared.styio",
                headers=self.authenticated_headers(),
            )
        self.assertEqual(status, 404)
        self.assertIn(b"file not found", body)

        os.environ[dev_server.ENABLE_MUTATION_ENV] = "1"
        status, _, body = self.request(
            "POST",
            "/api/workspace/file/main.styio",
            body={"content": "module Changed {}\n"},
            headers=self.authenticated_post_headers(origin=self.origin),
        )
        self.assertEqual(status, 200, body.decode("utf-8"))
        self.assertEqual(json.loads(body.decode("utf-8"))["bytes"], len("module Changed {}\n".encode("utf-8")))
        self.assertEqual((dev_server.WORKSPACE_ROOT / "main.styio").read_text(encoding="utf-8"), "module Changed {}\n")

        status, _, body = self.request(
            "POST",
            "/api/workspace/file/main.styio",
            body={"content": 42},
            headers=self.authenticated_post_headers(origin=self.origin),
        )
        self.assertEqual(status, 400)
        self.assertIn(b"content must be a string", body)

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

        status, _, body = self.request(
            "GET",
            "/editor.html",
            headers={"Host": f"attacker.test:{self.server.server_port}"},
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
            retry_on_disconnect=True,
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

    def test_mutation_routes_cover_create_folder_delete_rename_root_and_unknown_endpoint(self) -> None:
        os.environ[dev_server.ENABLE_MUTATION_ENV] = "1"

        status, _, body = self.request(
            "POST",
            "/api/workspace/create-file",
            body={"path": "bad.styio", "content": 7},
            headers=self.authenticated_post_headers(origin=self.origin),
        )
        self.assertEqual(status, 400)
        self.assertIn(b"content must be a string", body)

        status, _, body = self.request(
            "POST",
            "/api/workspace/create-folder",
            body={"path": "nested"},
            headers=self.authenticated_post_headers(origin=self.origin),
        )
        self.assertEqual(status, 201, body.decode("utf-8"))
        self.assertTrue((dev_server.WORKSPACE_ROOT / "nested").is_dir())

        status, _, body = self.request(
            "POST",
            "/api/workspace/create-folder",
            body={"path": ""},
            headers=self.authenticated_post_headers(origin=self.origin),
        )
        self.assertEqual(status, 400)
        self.assertIn(b"path must be a non-empty string", body)

        status, _, body = self.request(
            "POST",
            "/api/workspace/rename-file",
            body={"path": "main.styio", "nextPath": "renamed.styio"},
            headers=self.authenticated_post_headers(origin=self.origin),
        )
        self.assertEqual(status, 200, body.decode("utf-8"))
        self.assertTrue((dev_server.WORKSPACE_ROOT / "renamed.styio").is_file())

        status, _, body = self.request(
            "POST",
            "/api/workspace/rename-file",
            body={"path": "renamed.styio", "nextPath": "renamed.styio"},
            headers=self.authenticated_post_headers(origin=self.origin),
        )
        self.assertEqual(status, 409)
        self.assertIn(b"target path already exists", body)

        status, _, body = self.request(
            "POST",
            "/api/workspace/delete-file",
            body={"path": "renamed.styio"},
            headers=self.authenticated_post_headers(origin=self.origin),
        )
        self.assertEqual(status, 200, body.decode("utf-8"))
        self.assertFalse((dev_server.WORKSPACE_ROOT / "renamed.styio").exists())

        status, _, body = self.request(
            "POST",
            "/api/workspace/delete-file",
            body={"path": "nested"},
            headers=self.authenticated_post_headers(origin=self.origin),
        )
        self.assertEqual(status, 400)
        self.assertIn(b"path must point to a file", body)

        (dev_server.WORKSPACE_ROOT / "delete-me").mkdir()
        (dev_server.WORKSPACE_ROOT / "delete-me" / "child.styio").write_text("child\n", encoding="utf-8")
        (dev_server.WORKSPACE_ROOT / "loose.styio").write_text("loose\n", encoding="utf-8")
        status, _, body = self.request(
            "POST",
            "/api/workspace/delete-paths",
            body={"paths": ["delete-me", "delete-me/child.styio", "loose.styio", "loose.styio"]},
            headers=self.authenticated_post_headers(origin=self.origin),
        )
        self.assertEqual(status, 200, body.decode("utf-8"))
        self.assertEqual(json.loads(body.decode("utf-8"))["deleted"], ["delete-me", "loose.styio"])
        self.assertFalse((dev_server.WORKSPACE_ROOT / "delete-me").exists())

        status, _, body = self.request(
            "POST",
            "/api/workspace/delete-paths",
            body={"paths": []},
            headers=self.authenticated_post_headers(origin=self.origin),
        )
        self.assertEqual(status, 400)
        self.assertIn(b"paths must be a non-empty array", body)

        status, _, body = self.request(
            "POST",
            "/api/workspace/delete-paths",
            body={"paths": [""]},
            headers=self.authenticated_post_headers(origin=self.origin),
        )
        self.assertEqual(status, 400)
        self.assertIn(b"every path must be a non-empty string", body)

        status, _, body = self.request(
            "POST",
            "/api/workspace/delete-paths",
            body={"paths": ["missing.styio"]},
            headers=self.authenticated_post_headers(origin=self.origin),
        )
        self.assertEqual(status, 400)
        self.assertIn(b"path not found", body)

        next_workspace = Path(self.temp_dir.name) / "next-workspace"
        next_workspace.mkdir()
        status, _, body = self.request(
            "POST",
            "/api/workspace/root",
            body={"path": str(next_workspace)},
            headers=self.authenticated_post_headers(origin=self.origin),
        )
        self.assertEqual(status, 200, body.decode("utf-8"))
        self.assertEqual(dev_server.WORKSPACE_ROOT, next_workspace.resolve())

        status, _, body = self.request(
            "POST",
            "/api/workspace/root",
            body={"path": ""},
            headers=self.authenticated_post_headers(origin=self.origin),
        )
        self.assertEqual(status, 400)
        self.assertIn(b"path must be a non-empty string", body)

        status, _, body = self.request(
            "POST",
            "/api/workspace/root",
            body={"path": str(next_workspace / "not-a-directory.styio")},
            headers=self.authenticated_post_headers(origin=self.origin),
        )
        self.assertEqual(status, 400)
        self.assertIn(b"path must point to an existing directory", body)

        status, _, body = self.request(
            "POST",
            "/api/unknown",
            body={},
            headers=self.authenticated_post_headers(origin=self.origin),
        )
        self.assertEqual(status, 404)
        self.assertIn(b"unknown endpoint", body)

    def test_mutation_rejects_invalid_json_and_bad_content_length(self) -> None:
        os.environ[dev_server.ENABLE_MUTATION_ENV] = "1"

        request = urllib.request.Request(
            f"{self.base_url}/api/workspace/create-file",
            data=b"{bad",
            headers=self.authenticated_post_headers(origin=self.origin),
            method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=5) as response:
                status = response.status
                body = response.read()
        except urllib.error.HTTPError as error:
            status = error.code
            body = error.read()
        self.assertEqual(status, 400)
        self.assertIn(b"invalid json", body)

        request = urllib.request.Request(
            f"{self.base_url}/api/workspace/create-file",
            data=b"[]",
            headers=self.authenticated_post_headers(origin=self.origin),
            method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=5) as response:
                status = response.status
                body = response.read()
        except urllib.error.HTTPError as error:
            status = error.code
            body = error.read()
        self.assertEqual(status, 400)
        self.assertIn(b"json body must be an object", body)

        request = urllib.request.Request(
            f"{self.base_url}/api/workspace/create-file",
            data=b"{}",
            headers=self.authenticated_post_headers(origin=self.origin)
            | {"Content-Length": "invalid"},
            method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=5) as response:
                status = response.status
                body = response.read()
        except urllib.error.HTTPError as error:
            status = error.code
            body = error.read()
        self.assertEqual(status, 400)
        self.assertIn(b"invalid content length", body)

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

        status, _, body = self.request(
            "POST",
            "/api/workspace/create-file",
            body={"path": "created.styio", "content": "x"},
            headers=self.authenticated_headers(origin=f"https://127.0.0.1:{self.server.server_port}"),
        )
        self.assertEqual(status, 403)
        self.assertIn(b"origin is not allowed", body)

    def test_mutation_rejects_non_local_host_before_body_handling(self) -> None:
        os.environ[dev_server.ENABLE_MUTATION_ENV] = "1"

        status, _, body = self.request(
            "POST",
            "/api/workspace/create-file",
            body={"path": "created.styio", "content": "x"},
            headers=self.authenticated_post_headers(origin=self.origin)
            | {"Host": f"attacker.test:{self.server.server_port}"},
        )

        self.assertEqual(status, 403)
        self.assertIn(b"host must be localhost", body)

    def test_mutation_routes_cover_remaining_bad_path_branches(self) -> None:
        os.environ[dev_server.ENABLE_MUTATION_ENV] = "1"

        cases = [
            ("/api/workspace/create-file", {"path": "", "content": ""}, b"path must be a non-empty string"),
            ("/api/workspace/create-file", {"path": "missing/child.styio", "content": ""}, b"path not found"),
            ("/api/workspace/create-folder", {"path": "missing/child"}, b"path not found"),
            ("/api/workspace/delete-file", {"path": ""}, b"path must be a non-empty string"),
            ("/api/workspace/delete-file", {"path": "missing.styio"}, b"path not found"),
            ("/api/workspace/rename-file", {"path": "", "nextPath": "next.styio"}, b"path must be a non-empty string"),
            ("/api/workspace/rename-file", {"path": "main.styio", "nextPath": ""}, b"nextPath must be a non-empty string"),
            ("/api/workspace/rename-file", {"path": "missing/source.styio", "nextPath": "next.styio"}, b"path not found"),
            ("/api/workspace/file/missing.styio", {"content": ""}, b"path not found"),
        ]
        for endpoint, payload, expected in cases:
            with self.subTest(endpoint=endpoint, payload=payload):
                status, _, body = self.request(
                    "POST",
                    endpoint,
                    body=payload,
                    headers=self.authenticated_post_headers(origin=self.origin),
                )
                self.assertEqual(status, 400)
                self.assertIn(expected, body)

        status, _, body = self.request(
            "POST",
            "/api/workspace/rename-file",
            body={"path": "folder", "nextPath": "folder-renamed"},
            headers=self.authenticated_post_headers(origin=self.origin),
        )
        self.assertEqual(status, 400)
        self.assertIn(b"path not found", body)

        (dev_server.WORKSPACE_ROOT / "folder").mkdir()
        status, _, body = self.request(
            "POST",
            "/api/workspace/rename-file",
            body={"path": "folder", "nextPath": "folder-renamed"},
            headers=self.authenticated_post_headers(origin=self.origin),
        )
        self.assertEqual(status, 400)
        self.assertIn(b"path must point to a file", body)

    def test_mutation_routes_handle_paths_that_disappear_after_resolution(self) -> None:
        os.environ[dev_server.ENABLE_MUTATION_ENV] = "1"

        vanished = mock.Mock()
        vanished.exists.return_value = False
        vanished.is_file.return_value = True
        with mock.patch.object(dev_server, "resolve_workspace_path", return_value=vanished):
            status, _, body = self.request(
                "POST",
                "/api/workspace/delete-file",
                body={"path": "vanished.styio"},
                headers=self.authenticated_post_headers(origin=self.origin),
            )
        self.assertEqual(status, 404)
        self.assertIn(b"file not found", body)

        source = mock.Mock()
        source.exists.return_value = False
        target = mock.Mock()
        with mock.patch.object(dev_server, "resolve_workspace_path", side_effect=[source, target]):
            status, _, body = self.request(
                "POST",
                "/api/workspace/rename-file",
                body={"path": "vanished.styio", "nextPath": "next.styio"},
                headers=self.authenticated_post_headers(origin=self.origin),
            )
        self.assertEqual(status, 404)
        self.assertIn(b"file not found", body)

        with mock.patch.object(dev_server, "resolve_workspace_path", return_value=dev_server.current_workspace()):
            status, _, body = self.request(
                "POST",
                "/api/workspace/delete-paths",
                body={"paths": ["root"]},
                headers=self.authenticated_post_headers(origin=self.origin),
            )
        self.assertEqual(status, 400)
        self.assertIn(b"cannot delete workspace root", body)

        vanished_path = mock.MagicMock()
        vanished_path.exists.return_value = False
        vanished_path.__eq__.return_value = False
        with mock.patch.object(dev_server, "resolve_workspace_path", return_value=vanished_path):
            status, _, body = self.request(
                "POST",
                "/api/workspace/delete-paths",
                body={"paths": ["vanished.styio"]},
                headers=self.authenticated_post_headers(origin=self.origin),
            )
        self.assertEqual(status, 404)
        self.assertIn(b"path not found: vanished.styio", body)


class _NoRedirectHandler(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


if __name__ == "__main__":
    unittest.main()
