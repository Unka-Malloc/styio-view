#!/usr/bin/env python3
from __future__ import annotations

import json
import os
from http import HTTPStatus
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse


APP_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = APP_ROOT.parents[1]
WEB_ROOT = REPO_ROOT / "prototype"
HOST = os.environ.get("VITYO_WEB_PREVIEW_HOST", "127.0.0.1")
PORT = int(os.environ.get("VITYO_WEB_PREVIEW_PORT", "8080"))
WORKSPACE_ID = "demo-workspace"


class PreviewHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(WEB_ROOT), **kwargs)

    def end_headers(self) -> None:
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path == "/":
            self._redirect("/editor")
            return
        if parsed.path in ("/index", "/index.html"):
            self._reject_removed_entrypoint()
            return
        if parsed.path in ("/editor", "/editor/"):
            self.path = "/editor.html"
            super().do_GET()
            return
        if parsed.path.startswith("/api/styio-hosted/v1/"):
            self._handle_api("GET", parsed.path)
            return
        super().do_GET()

    def do_POST(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path.startswith("/api/styio-hosted/v1/"):
            body = self._read_json_body()
            self._handle_api("POST", parsed.path, body)
            return
        self.send_error(HTTPStatus.NOT_FOUND, "Not found")

    def do_OPTIONS(self) -> None:
        self.send_response(HTTPStatus.NO_CONTENT)
        self.send_header("Access-Control-Allow-Origin", self.headers.get("Origin", "*"))
        self.send_header("Access-Control-Allow-Headers", "content-type,authorization")
        self.send_header("Access-Control-Allow-Methods", "GET,POST,OPTIONS")
        self.end_headers()

    def _read_json_body(self) -> dict:
        length = int(self.headers.get("content-length") or "0")
        if length <= 0:
            return {}
        try:
            return json.loads(self.rfile.read(length).decode("utf-8"))
        except json.JSONDecodeError:
            return {}

    def _handle_api(self, method: str, path: str, body: dict | None = None) -> None:
        key = f"{method} {path}"
        if key == "POST /api/styio-hosted/v1/workspaces/open":
            self._send_json(_open_workspace_response())
            return
        if key == f"GET /api/styio-hosted/v1/workspaces/{WORKSPACE_ID}/project-graph":
            self._send_json(_project_graph_response())
            return
        if key == f"POST /api/styio-hosted/v1/workspaces/{WORKSPACE_ID}/documents/load":
            self._send_json(_document_load_response(body or {}))
            return
        if key == f"POST /api/styio-hosted/v1/workspaces/{WORKSPACE_ID}/documents/save":
            self._send_json(_document_save_response(body or {}))
            return

        response = _command_response_for(key)
        if response is not None:
            self._send_json(response)
            return

        self._send_json(
            {
                "returncode": 1,
                "message": "Preview hosted route is not implemented.",
                "stdout": "",
                "stderr": key,
                "error_payload": {
                    "code": "preview.unimplemented_route",
                    "details": {"route": key},
                    "retryable": False,
                },
            },
            status=HTTPStatus.NOT_FOUND,
        )

    def _send_json(self, payload: dict, *, status: HTTPStatus = HTTPStatus.OK) -> None:
        body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", self.headers.get("Origin", "*"))
        self.end_headers()
        self.wfile.write(body)

    def _redirect(self, location: str) -> None:
        self.send_response(HTTPStatus.FOUND)
        self.send_header("Location", location)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def _reject_removed_entrypoint(self) -> None:
        self.send_error(HTTPStatus.NOT_FOUND, "Not found")


def _open_workspace_response() -> dict:
    return {
        "returncode": 0,
        "message": "opened local preview hosted workspace",
        "stdout": "",
        "stderr": "",
        "payload": _project_graph_payload(),
        "workspace": _hosted_workspace_record(),
    }


def _project_graph_response() -> dict:
    return {
        "returncode": 0,
        "message": "refreshed local preview hosted project graph",
        "stdout": "",
        "stderr": "",
        "payload": _project_graph_payload(),
        "workspace": _hosted_workspace_record(),
    }


def _document_load_response(body: dict) -> dict:
    path = _body_string(body, "path") or "/workspace/demo/src/main.styio"
    return {
        "returncode": 0,
        "message": "loaded preview hosted document",
        "stdout": "",
        "stderr": "",
        "payload": {
            "document_id": path,
            "path": path,
            "document_text": _document_text_for(path),
            "revision": 1,
        },
    }


def _document_save_response(body: dict) -> dict:
    path = _body_string(body, "path") or "/workspace/demo/src/main.styio"
    revision = _body_int(body, "revision") or 0
    return {
        "returncode": 0,
        "message": "saved preview hosted document",
        "stdout": "",
        "stderr": "",
        "payload": {
            "path": path,
            "revision": revision + 1,
            "saved": True,
        },
    }


def _document_text_for(path: str) -> str:
    documents = {
        "/workspace/demo/src/main.styio": "value = 1\nvalue\n",
        "/workspace/demo/src/lib.styio": "value = 1\n",
        "/workspace/demo/tests/render_test.styio": "value = 1\nvalue\n",
    }
    return documents.get(path, "value = 1\n")


def _body_string(body: dict, key: str) -> str | None:
    value = body.get(key)
    if isinstance(value, str) and value:
        return value
    return None


def _body_int(body: dict, key: str) -> int | None:
    value = body.get(key)
    if isinstance(value, int):
        return value
    if isinstance(value, str):
        try:
            return int(value)
        except ValueError:
            return None
    return None


def _command_response_for(key: str) -> dict | None:
    command_routes = {
        f"POST /api/styio-hosted/v1/workspaces/{WORKSPACE_ID}/tool/install": (
            "installed preview managed compiler",
            {
                "compiler_version": "0.0.1-preview",
                "channel": "preview",
                "install_root": "/workspace/demo/.pafio/tools/styio/0.0.1-preview",
                "install_binary_path": "/workspace/demo/.pafio/tools/styio/0.0.1-preview/bin/styio",
            },
        ),
        f"POST /api/styio-hosted/v1/workspaces/{WORKSPACE_ID}/tool/use": (
            "activated preview managed compiler",
            {"compiler_version": "0.0.1-preview", "channel": "preview"},
        ),
        f"POST /api/styio-hosted/v1/workspaces/{WORKSPACE_ID}/tool/pin": (
            "pinned preview managed compiler",
            {
                "compiler_version": "0.0.1-preview",
                "channel": "preview",
                "pin_path": "/workspace/demo/pafio-toolchain.toml",
            },
        ),
        f"POST /api/styio-hosted/v1/workspaces/{WORKSPACE_ID}/tool/clear-pin": (
            "cleared preview managed compiler pin",
            {"pin_cleared": True},
        ),
        f"POST /api/styio-hosted/v1/workspaces/{WORKSPACE_ID}/dependencies/fetch": (
            "preview dependency fetch completed",
            {"packages": 3, "registry_packages": 1, "path_packages": 0},
        ),
        f"POST /api/styio-hosted/v1/workspaces/{WORKSPACE_ID}/dependencies/vendor": (
            "preview dependency vendor completed",
            {"packages": 3, "output_path": "/workspace/demo/.pafio/vendor"},
        ),
        f"POST /api/styio-hosted/v1/workspaces/{WORKSPACE_ID}/deployment/pack": (
            "preview package archive prepared",
            {"package": "demo/app", "archive_path": "/workspace/demo/dist/demo-app.tar"},
        ),
        f"POST /api/styio-hosted/v1/workspaces/{WORKSPACE_ID}/deployment/preflight": (
            "preview publish preflight completed",
            {"package": "demo/app", "mode": "dry-run"},
        ),
        f"POST /api/styio-hosted/v1/workspaces/{WORKSPACE_ID}/deployment/publish": (
            "preview publish simulated",
            {"package": "demo/app", "registry_root": "/registry/local", "mode": "preview"},
        ),
    }
    if key in command_routes:
        message, payload = command_routes[key]
        return _hosted_command_response(message=message, payload=payload)

    if key == f"POST /api/styio-hosted/v1/workspaces/{WORKSPACE_ID}/execution/run":
        return _execution_response(
            message="Preview run completed without invoking the Styio compiler.",
            session_id="preview-run-session",
            event_kind="runtime.stdout",
            payload={"stdout": "preview run ok\n"},
        )
    if key == f"POST /api/styio-hosted/v1/workspaces/{WORKSPACE_ID}/execution/build":
        return _execution_response(
            message="Preview build completed without invoking the Styio compiler.",
            session_id="preview-build-session",
            event_kind="compile.finished",
            payload={"stdout": "preview build ok\n"},
        )
    if key == f"POST /api/styio-hosted/v1/workspaces/{WORKSPACE_ID}/execution/test":
        return _execution_response(
            message="Preview test completed without invoking the Styio compiler.",
            session_id="preview-test-session",
            event_kind="test.finished",
            payload={"stdout": "preview tests ok\n"},
        )
    return None


def _hosted_command_response(*, message: str, payload: dict) -> dict:
    return {
        "returncode": 0,
        "message": message,
        "stdout": "",
        "stderr": "",
        "payload": payload,
    }


def _execution_response(
    *, message: str, session_id: str, event_kind: str, payload: dict
) -> dict:
    stdout = payload.get("stdout", "")
    return {
        "returncode": 0,
        "message": message,
        "stdout": stdout,
        "stderr": "",
        "payload": {
            "session_id": session_id,
            "stdout": stdout,
            "runtime_events": [
                {
                    "schema_version": 1,
                    "session_id": session_id,
                    "sequence": 1,
                    "timestamp": "2026-05-10T00:00:00Z",
                    "eventKind": event_kind,
                    "origin": "Vityo.preview",
                    "payload": {"line": stdout.strip()},
                }
            ],
        },
    }


def _hosted_workspace_record() -> dict:
    return {
        "workspaceId": WORKSPACE_ID,
        "schemaVersion": "1",
        "ownerRef": "Vityo-local-preview",
        "status": "active",
        "entryUrl": f"http://{HOST}:{PORT}/",
        "createdAt": "2026-05-10T00:00:00Z",
        "lastActiveAt": "2026-05-10T00:00:00Z",
        "retentionDays": 1,
        "exportState": "not_requested",
    }


def _project_graph_payload() -> dict:
    return {
        "id": "/workspace/demo/pafio.toml",
        "title": "demo/app",
        "kind": "hosted",
        "workspace_root": "/workspace/demo",
        "workspace_members": [],
        "manifest_path": "/workspace/demo/pafio.toml",
        "lockfile_path": "/workspace/demo/pafio.lock",
        "toolchain_pin_path": "/workspace/demo/pafio-toolchain.toml",
        "styio_config_path": "/workspace/demo/styio.toml",
        "vendor_root": "/workspace/demo/.pafio/vendor",
        "build_root": "/workspace/demo/.pafio/build",
        "packages": [
            {
                "package_name": "demo/app",
                "version": "0.1.0",
                "root_path": "/workspace/demo",
                "manifest_path": "/workspace/demo/pafio.toml",
                "targets": _targets(),
                "dependencies": _dependencies(),
                "is_workspace_member": False,
                "publish_enabled": True,
            }
        ],
        "dependencies": _dependencies(),
        "targets": _targets(),
        "editor_files": [
            "/workspace/demo/src/main.styio",
            "/workspace/demo/src/lib.styio",
            "/workspace/demo/tests/render_test.styio",
        ],
        "toolchain": {
            "source": "managed-current",
            "detail": "Local preview server exposes a mock hosted route; compiler execution is not real.",
            "pin_path": "/workspace/demo/pafio-toolchain.toml",
            "channel": "preview",
            "version": "0.0.1-preview",
        },
        "lock_state": "fresh",
        "vendor_state": "present",
        "active_compiler": {
            "binary_path": "/workspace/demo/.pafio/tools/styio/current/bin/styio",
            "tool": "styio",
            "compiler_version": "0.0.1-preview",
            "channel": "preview",
            "variant": "preview",
            "capabilities": ["machine_info_json", "compile_plan"],
            "supported_contract_versions": {
                "compile_plan": [1],
                "runtime_events": [1],
            },
            "integration_phase": "local-preview",
            "supported_adapter_modes": ["cloud"],
            "feature_flags": {"runtime_events": True},
        },
        "managed_toolchains": {
            "pafio_home": "/workspace/demo/.pafio",
            "current_binary": "/workspace/demo/.pafio/tools/styio/current/bin/styio",
            "current_metadata_path": "/workspace/demo/.pafio/tools/styio/current/metadata.json",
            "installed": [
                {
                    "channel": "preview",
                    "compiler_version": "0.0.1-preview",
                    "install_root": "/workspace/demo/.pafio/tools/styio/0.0.1-preview",
                    "install_binary_path": "/workspace/demo/.pafio/tools/styio/0.0.1-preview/bin/styio",
                    "install_metadata_path": "/workspace/demo/.pafio/tools/styio/0.0.1-preview/metadata.json",
                }
            ],
        },
        "package_distribution": {
            "schema_version": 1,
            "packages": [
                {
                    "package_name": "demo/app",
                    "manifest_path": "/workspace/demo/pafio.toml",
                    "publish_enabled": True,
                    "publish_ready": True,
                    "blocking_reasons": [],
                    "runtime_registry_dependencies": 1,
                    "runtime_path_dependencies": 0,
                    "runtime_git_dependencies": 0,
                    "dev_registry_dependencies": 0,
                    "dev_path_dependencies": 0,
                    "dev_git_dependencies": 0,
                }
            ],
            "registry_sources": [
                {
                    "registry_root": "https://packages.example.test",
                    "transport": "https",
                    "dependency_refs": 1,
                    "packages": ["palette"],
                }
            ],
            "publishable_packages": 1,
            "blocked_packages": 0,
        },
        "source_state": {
            "schema_version": 1,
            "pafio_home": "/workspace/demo/.pafio",
            "declared_git_dependencies": 0,
            "declared_registry_dependencies": 1,
            "git_cache": {
                "repos_root": "/workspace/demo/.pafio/git/repos",
                "checkouts_root": "/workspace/demo/.pafio/git/checkouts",
                "repos_present": True,
                "checkouts_present": True,
            },
            "registry_cache": {
                "cache_root": "/workspace/demo/.pafio/registry",
                "index_root": "/workspace/demo/.pafio/registry/index",
                "blob_root": "/workspace/demo/.pafio/registry/blobs",
                "checkout_root": "/workspace/demo/.pafio/registry/checkouts",
                "index_present": True,
                "blobs_present": True,
                "checkouts_present": True,
            },
            "vendor": {
                "vendor_root": "/workspace/demo/.pafio/vendor",
                "metadata_path": "/workspace/demo/.pafio/vendor/vendor.json",
                "vendor_present": True,
                "metadata_present": True,
                "git_snapshots": 0,
            },
        },
        "notes": [
            "Local preview route is intentionally mocked so the Flutter shell can boot without the hosted control plane.",
            "Syntax highlighting, diagnostics, completion, hover, and editor UI can be evaluated here; compiler execution remains a backend handoff.",
        ],
    }


def _targets() -> list[dict]:
    return [
        {
            "id": "demo/app:bin:demo",
            "package_name": "demo/app",
            "kind": "bin",
            "name": "demo",
            "file_path": "/workspace/demo/src/main.styio",
        },
        {
            "id": "demo/app:lib",
            "package_name": "demo/app",
            "kind": "lib",
            "name": "demo",
            "file_path": "/workspace/demo/src/lib.styio",
        },
        {
            "id": "demo/app:test:render",
            "package_name": "demo/app",
            "kind": "test",
            "name": "render",
            "file_path": "/workspace/demo/tests/render_test.styio",
        },
    ]


def _dependencies() -> list[dict]:
    return [
        {
            "source_package_name": "demo/app",
            "dependency_name": "palette",
            "kind": "runtime",
            "requirement": "registry:https://packages.example.test@1.0.0",
            "source_kind": "registry",
            "registry": "https://packages.example.test",
            "package": "palette",
            "version": "1.0.0",
            "publish_blocking": False,
        }
    ]


def main() -> None:
    if not WEB_ROOT.exists():
        raise SystemExit(
            f"{WEB_ROOT} does not exist. Run `flutter build web --debug` first."
        )
    if not (WEB_ROOT / "flutter_bootstrap.js").exists():
        raise SystemExit(
            f"{WEB_ROOT} is missing flutter_bootstrap.js. Rebuild the web target."
        )

    server = ThreadingHTTPServer((HOST, PORT), PreviewHandler)
    print(f"Vityo Flutter web preview listening on http://{HOST}:{PORT}")
    print("hosted control-plane routes are mocked for local UI validation")
    server.serve_forever()


if __name__ == "__main__":
    main()
