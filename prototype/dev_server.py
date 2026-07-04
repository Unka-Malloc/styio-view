#!/usr/bin/env python3
from __future__ import annotations

import json
import hmac
import os
import secrets
import shutil
from http import HTTPStatus
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, unquote, urlparse, urlsplit


ROOT = Path(__file__).resolve().parent
DEFAULT_WORKSPACE = ROOT / "workspace"
WORKSPACE_CONFIG = ROOT / ".workspace-root"
HOST = os.environ.get("STYIO_DEV_SERVER_HOST", "127.0.0.1")
PORT = int(os.environ.get("STYIO_DEV_SERVER_PORT", "4180"))
SESSION_COOKIE_NAME = "styio_dev_server_session"
SESSION_TOKEN_HEADER = "X-Styio-Dev-Server-Token"
SESSION_TOKEN_ENV = "STYIO_DEV_SERVER_TOKEN"
ENABLE_MUTATION_ENV = "STYIO_DEV_SERVER_ENABLE_MUTATION"
SESSION_TOKEN = os.environ.get(SESSION_TOKEN_ENV) or secrets.token_urlsafe(32)
LOCAL_HOSTNAMES = {"127.0.0.1", "localhost", "::1"}
TRUTHY_ENV_VALUES = {"1", "true", "yes", "y", "on"}
IGNORED_NAMES = {
    ".DS_Store",
    ".git",
    ".idea",
    ".vscode",
    "__pycache__",
    "build",
    "dist",
    "node_modules",
}


def mutation_enabled() -> bool:
    return os.environ.get(ENABLE_MUTATION_ENV, "").strip().casefold() in TRUTHY_ENV_VALUES


def split_host_port(raw_host: str | None) -> tuple[str, int | None] | None:
    if raw_host is None or not raw_host.strip():
        return None

    try:
        parsed = urlsplit(f"//{raw_host.strip()}")
        hostname = parsed.hostname
        port = parsed.port
    except ValueError:
        return None

    if hostname is None:
        return None

    return hostname.rstrip(".").casefold(), port


def is_allowed_local_netloc(raw_host: str | None, *, expected_port: int) -> bool:
    parsed = split_host_port(raw_host)
    if parsed is None:
        return False

    hostname, port = parsed
    if hostname not in LOCAL_HOSTNAMES:
        return False

    return port == expected_port


def parse_cookie_header(raw_cookie: str | None) -> dict[str, str]:
    cookies: dict[str, str] = {}
    if not raw_cookie:
        return cookies

    for segment in raw_cookie.split(";"):
        if "=" not in segment:
            continue
        name, value = segment.split("=", 1)
        cookies[name.strip()] = value.strip()

    return cookies


def token_matches(candidate: str | None) -> bool:
    if candidate is None:
        return False

    try:
        candidate_bytes = candidate.encode("utf-8")
        session_bytes = SESSION_TOKEN.encode("utf-8")
    except UnicodeEncodeError:
        return False

    return hmac.compare_digest(candidate_bytes, session_bytes)


def load_workspace_root() -> Path:
    if WORKSPACE_CONFIG.exists():
        raw = WORKSPACE_CONFIG.read_text(encoding="utf-8").strip()
        if raw:
            candidate = Path(raw).expanduser()
            if not candidate.is_absolute():
                candidate = (ROOT / candidate).resolve()
            else:
                candidate = candidate.resolve()
            if candidate.is_dir():
                return candidate

    DEFAULT_WORKSPACE.mkdir(parents=True, exist_ok=True)
    return DEFAULT_WORKSPACE.resolve()


WORKSPACE_ROOT = load_workspace_root()


def current_workspace() -> Path:
    return WORKSPACE_ROOT


def persist_workspace_root(path: Path) -> None:
    WORKSPACE_CONFIG.write_text(str(path), encoding="utf-8")


def set_workspace_root(raw_path: str) -> Path:
    global WORKSPACE_ROOT

    candidate = resolve_existing_path_case_sensitive(raw_path, base=ROOT)
    if not candidate.is_dir():
        raise ValueError("workspace path must point to an existing directory")

    selected = candidate.resolve()
    WORKSPACE_ROOT = selected
    persist_workspace_root(selected)
    return selected


def is_ignored(path: Path) -> bool:
    return path.name in IGNORED_NAMES or path.name.startswith(".")


def iter_clean_parts(raw_path: str) -> list[str]:
    parts: list[str] = []
    for part in Path(raw_path).parts:
        if part in ("", "."):
            continue
        if part == "..":
            raise ValueError("path escapes workspace root")
        parts.append(part)
    return parts


def lookup_case_sensitive_child(parent: Path, name: str) -> Path | None:
    if not parent.exists() or not parent.is_dir():
        return None

    children = {child.name: child for child in parent.iterdir()}
    if name in children:
        return children[name]

    conflicting = next((child_name for child_name in children if child_name.casefold() == name.casefold()), None)
    if conflicting is not None:
        raise ValueError(f"path casing must match existing entry: {conflicting}")

    return None


def resolve_existing_path_case_sensitive(raw_path: str, *, base: Path | None = None) -> Path:
    candidate = Path(raw_path.strip()).expanduser()
    if os.name == "nt" and candidate.is_absolute() and candidate.exists():
        return candidate.resolve()

    if candidate.is_absolute():
        current = Path(candidate.anchor)
        parts = list(candidate.parts[1:])
    else:
        current = (base or ROOT).resolve()
        parts = iter_clean_parts(str(candidate))

    for part in parts:
        match = lookup_case_sensitive_child(current, part)
        if match is None:
            raise ValueError("path must point to an existing directory")
        current = match

    return current


def resolve_workspace_path(relative_path: str, *, require_exists: bool = False) -> Path:
    root = current_workspace().resolve()
    parts = iter_clean_parts(relative_path)
    if not parts:
        raise ValueError("path must be a non-empty string")

    current = root
    for index, part in enumerate(parts):
        is_last = index == len(parts) - 1
        match = lookup_case_sensitive_child(current, part)
        if match is not None:
            current = match
            continue

        if require_exists or not is_last:
            raise ValueError("path not found")

        current = current / part

    current = current.resolve()
    if root not in current.parents and current != root:
        raise ValueError("path escapes workspace root")

    return current


def scan_workspace_directory(path: Path, root: Path) -> list[dict]:
    entries: list[dict] = []

    for child in sorted(
        path.iterdir(),
        key=lambda item: (item.is_file(), item.name),
    ):
        if is_ignored(child):
            continue

        relative_path = child.relative_to(root).as_posix()
        if child.is_dir():
            entries.append(
                {
                    "type": "directory",
                    "name": child.name,
                    "path": relative_path,
                    "children": scan_workspace_directory(child, root),
                }
            )
            continue

        entries.append(
            {
                "type": "file",
                "name": child.name,
                "path": relative_path,
                "size": child.stat().st_size,
            }
        )

    return entries


def flatten_file_paths(entries: list[dict]) -> list[str]:
    files: list[str] = []

    for entry in entries:
        if entry["type"] == "file":
            files.append(entry["path"])
            continue
        files.extend(flatten_file_paths(entry["children"]))

    return files


def workspace_snapshot() -> dict:
    root = current_workspace().resolve()
    entries = scan_workspace_directory(root, root)
    return {
        "rootPath": str(root),
        "workspaceName": root.name,
        "entries": entries,
        "files": flatten_file_paths(entries),
    }


def resolve_browser_path(raw_path: str | None) -> Path:
    if raw_path and raw_path.strip():
        candidate = resolve_existing_path_case_sensitive(raw_path, base=ROOT)
    else:
        candidate = current_workspace().resolve()

    if not candidate.exists():
        raise ValueError("browser path must point to an existing file or directory")

    return candidate.resolve()


def path_is_within_root(path: Path, root: Path) -> bool:
    try:
        path.resolve().relative_to(root.resolve())
    except ValueError:
        return False
    return True


def browser_entry_snapshot(raw_path: str | None, *, include_files: bool = False) -> dict:
    target = resolve_browser_path(raw_path)
    selected_file = target if target.is_file() else None
    current = target.parent if selected_file else target
    parent = current.parent if current.parent != current else None
    breadcrumbs = []

    if current.anchor:
        anchor = Path(current.anchor)
        breadcrumbs.append({"name": current.anchor, "path": str(anchor)})

    cursor = current
    segments = list(current.parts)
    if current.anchor:
        segments = segments[1:]
        cursor = Path(current.anchor)
    else:
        cursor = Path(".")

    for segment in segments:
        cursor = (cursor / segment).resolve()
        breadcrumbs.append({"name": segment, "path": str(cursor)})

    directories = []
    files = []
    for child in sorted(current.iterdir(), key=lambda item: item.name):
        if is_ignored(child):
            continue
        if child.is_dir():
            directories.append({"name": child.name, "path": str(child.resolve())})
            continue
        if include_files and child.is_file():
            files.append({"name": child.name, "path": str(child.resolve())})

    return {
        "currentPath": str(current),
        "parentPath": str(parent) if parent else None,
        "breadcrumbs": breadcrumbs,
        "directories": directories,
        "files": files,
        "selectedFilePath": str(selected_file) if selected_file else None,
    }


class PrototypeHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)

    def end_headers(self) -> None:
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        if getattr(self, "_issue_session_cookie", False):
            self.send_header(
                "Set-Cookie",
                f"{SESSION_COOKIE_NAME}={SESSION_TOKEN}; Path=/; HttpOnly; SameSite=Strict",
            )
        super().end_headers()

    def end_json(self, payload: dict, status: int = HTTPStatus.OK) -> None:
        encoded = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def read_json_body(self) -> dict:
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError as error:
            raise ValueError("invalid content length") from error

        body = self.rfile.read(length)

        try:
            payload = json.loads(body.decode("utf-8")) if body else {}
        except json.JSONDecodeError as error:
            raise ValueError("invalid json") from error

        if not isinstance(payload, dict):
            raise ValueError("json body must be an object")

        return payload

    def is_api_request(self) -> bool:
        return urlparse(self.path).path.startswith("/api/")

    def api_forbidden(self, message: str, status: int = HTTPStatus.FORBIDDEN) -> None:
        self.end_json({"error": message}, status)

    def reject_request(self, message: str, status: int = HTTPStatus.FORBIDDEN) -> None:
        if self.is_api_request():
            self.api_forbidden(message, status)
            return

        self.send_error(status, message)

    def host_is_allowed(self) -> bool:
        return is_allowed_local_netloc(self.headers.get("Host"), expected_port=self.server.server_port)

    def origin_is_allowed(self) -> bool:
        origin = self.headers.get("Origin")
        if origin is None:
            return False

        parsed = urlparse(origin)
        if parsed.scheme != "http":
            return False

        return is_allowed_local_netloc(parsed.netloc, expected_port=self.server.server_port)

    def has_valid_session_credential(self) -> bool:
        if token_matches(self.headers.get(SESSION_TOKEN_HEADER)):
            return True

        authorization = self.headers.get("Authorization", "")
        bearer_prefix = "Bearer "
        if authorization.startswith(bearer_prefix):
            bearer_token = authorization[len(bearer_prefix) :].strip()
            if token_matches(bearer_token):
                return True

        cookies = parse_cookie_header(self.headers.get("Cookie"))
        return token_matches(cookies.get(SESSION_COOKIE_NAME))

    def enforce_host_boundary(self) -> bool:
        if self.host_is_allowed():
            return True

        self.reject_request("host must be localhost, 127.0.0.1, or ::1 on the dev server port")
        return False

    def enforce_api_boundary(self, *, require_origin: bool = False, require_mutation: bool = False) -> bool:
        fetch_site = self.headers.get("Sec-Fetch-Site", "").strip().casefold()
        if fetch_site == "cross-site":
            self.api_forbidden("cross-site requests are not allowed")
            return False

        origin = self.headers.get("Origin")
        if origin is not None and not self.origin_is_allowed():
            self.api_forbidden("origin is not allowed")
            return False

        if require_origin and not self.origin_is_allowed():
            self.api_forbidden("same-origin request origin is required")
            return False

        if not self.has_valid_session_credential():
            self.api_forbidden("missing or invalid dev server session credential")
            return False

        if require_mutation and not mutation_enabled():
            self.api_forbidden(f"mutation APIs are disabled; set {ENABLE_MUTATION_ENV}=1 to enable local writes")
            return False

        return True

    def do_HEAD(self) -> None:
        if not self.enforce_host_boundary():
            return

        parsed = urlparse(self.path)
        self._issue_session_cookie = not self.is_api_request()
        if parsed.path == "/":
            self.redirect_to_editor()
            return
        if parsed.path in ("/index", "/index.html"):
            self.reject_removed_entrypoint()
            return
        if parsed.path in ("/app.js", "/styles.css"):
            self.reject_removed_entrypoint()
            return
        if parsed.path in ("/editor", "/editor/"):
            self.path = "/editor.html"
        super().do_HEAD()

    def do_GET(self) -> None:
        if not self.enforce_host_boundary():
            return

        parsed = urlparse(self.path)
        if parsed.path.startswith("/api/") and not self.enforce_api_boundary():
            return

        self._issue_session_cookie = not parsed.path.startswith("/api/")
        if parsed.path == "/":
            self.redirect_to_editor()
            return

        if parsed.path in ("/index", "/index.html"):
            self.reject_removed_entrypoint()
            return

        if parsed.path in ("/app.js", "/styles.css"):
            self.reject_removed_entrypoint()
            return

        if parsed.path in ("/editor", "/editor/"):
            self.path = "/editor.html"
            super().do_GET()
            return

        if parsed.path == "/api/workspace":
            self.end_json(workspace_snapshot())
            return

        if parsed.path == "/api/browser/entries":
            query = parse_qs(parsed.query)
            raw_path = query.get("path", [None])[0]
            include_files = query.get("includeFiles", ["0"])[0] == "1"
            try:
                self.end_json(browser_entry_snapshot(raw_path, include_files=include_files))
            except ValueError as error:
                self.end_json({"error": str(error)}, HTTPStatus.BAD_REQUEST)
            return

        if parsed.path == "/api/browser/file":
            query = parse_qs(parsed.query)
            raw_path = query.get("path", [None])[0]
            if not isinstance(raw_path, str) or not raw_path.strip():
                self.end_json({"error": "path must be a non-empty string"}, HTTPStatus.BAD_REQUEST)
                return

            try:
                target = resolve_browser_path(raw_path)
                if not target.is_file():
                    raise ValueError("path must point to a file")
                if not path_is_within_root(target, current_workspace()):
                    self.end_json({"error": "file reads are limited to the current workspace"}, HTTPStatus.FORBIDDEN)
                    return
                content = target.read_text(encoding="utf-8")
            except UnicodeDecodeError:
                self.end_json({"error": "file is not utf-8 text"}, HTTPStatus.UNSUPPORTED_MEDIA_TYPE)
                return
            except ValueError as error:
                self.end_json({"error": str(error)}, HTTPStatus.BAD_REQUEST)
                return
            except FileNotFoundError:
                self.end_json({"error": "file not found"}, HTTPStatus.NOT_FOUND)
                return

            self.end_json({"ok": True, "path": str(target), "content": content})
            return

        if parsed.path.startswith("/api/workspace/file/"):
            relative_path = unquote(parsed.path.removeprefix("/api/workspace/file/")).strip()
            try:
                target = resolve_workspace_path(relative_path, require_exists=True)
                content = target.read_text(encoding="utf-8")
            except UnicodeDecodeError:
                self.end_json({"error": "file is not utf-8 text"}, HTTPStatus.UNSUPPORTED_MEDIA_TYPE)
                return
            except ValueError as error:
                self.end_json({"error": str(error)}, HTTPStatus.BAD_REQUEST)
                return
            except FileNotFoundError:
                self.end_json({"error": "file not found"}, HTTPStatus.NOT_FOUND)
                return

            self.end_json(
                {
                    "ok": True,
                    "file": relative_path,
                    "path": str(target),
                    "content": content,
                }
            )
            return

        super().do_GET()

    def redirect_to_editor(self) -> None:
        self.send_response(HTTPStatus.FOUND)
        self.send_header("Location", "/editor")
        self.send_header("Content-Length", "0")
        self.end_headers()

    def reject_removed_entrypoint(self) -> None:
        self.send_error(HTTPStatus.NOT_FOUND, "Not found")

    def do_POST(self) -> None:
        if not self.enforce_host_boundary():
            return

        parsed = urlparse(self.path)
        if parsed.path.startswith("/api/") and not self.enforce_api_boundary(
            require_origin=True,
            require_mutation=True,
        ):
            return

        try:
            payload = self.read_json_body()
        except ValueError as error:
            self.end_json({"error": str(error)}, HTTPStatus.BAD_REQUEST)
            return

        if parsed.path == "/api/workspace/root":
            raw_path = payload.get("path")
            if not isinstance(raw_path, str) or not raw_path.strip():
                self.end_json({"error": "path must be a non-empty string"}, HTTPStatus.BAD_REQUEST)
                return

            try:
                root = set_workspace_root(raw_path)
            except ValueError as error:
                self.end_json({"error": str(error)}, HTTPStatus.BAD_REQUEST)
                return

            self.end_json({"ok": True, "rootPath": str(root), "workspaceName": root.name})
            return

        if parsed.path == "/api/workspace/create-file":
            relative_path = payload.get("path")
            content = payload.get("content", "")

            if not isinstance(relative_path, str) or not relative_path.strip():
                self.end_json({"error": "path must be a non-empty string"}, HTTPStatus.BAD_REQUEST)
                return
            if not isinstance(content, str):
                self.end_json({"error": "content must be a string"}, HTTPStatus.BAD_REQUEST)
                return

            try:
                target = resolve_workspace_path(relative_path.strip())
            except ValueError as error:
                self.end_json({"error": str(error)}, HTTPStatus.BAD_REQUEST)
                return

            target.parent.mkdir(parents=True, exist_ok=True)
            if not target.exists():
                target.touch()
            target.write_text(content, encoding="utf-8")
            self.end_json(
                {
                    "ok": True,
                    "file": target.relative_to(current_workspace()).as_posix(),
                    "path": str(target),
                },
                HTTPStatus.CREATED,
            )
            return

        if parsed.path == "/api/workspace/create-folder":
            relative_path = payload.get("path")
            if not isinstance(relative_path, str) or not relative_path.strip():
                self.end_json({"error": "path must be a non-empty string"}, HTTPStatus.BAD_REQUEST)
                return

            try:
                target = resolve_workspace_path(relative_path.strip())
            except ValueError as error:
                self.end_json({"error": str(error)}, HTTPStatus.BAD_REQUEST)
                return

            target.mkdir(parents=True, exist_ok=True)
            self.end_json(
                {
                    "ok": True,
                    "folder": target.relative_to(current_workspace()).as_posix(),
                    "path": str(target),
                },
                HTTPStatus.CREATED,
            )
            return

        if parsed.path == "/api/workspace/delete-file":
            relative_path = payload.get("path")
            if not isinstance(relative_path, str) or not relative_path.strip():
                self.end_json({"error": "path must be a non-empty string"}, HTTPStatus.BAD_REQUEST)
                return

            try:
                target = resolve_workspace_path(relative_path.strip(), require_exists=True)
            except ValueError as error:
                self.end_json({"error": str(error)}, HTTPStatus.BAD_REQUEST)
                return

            if not target.exists():
                self.end_json({"error": "file not found"}, HTTPStatus.NOT_FOUND)
                return
            if not target.is_file():
                self.end_json({"error": "path must point to a file"}, HTTPStatus.BAD_REQUEST)
                return

            target.unlink()
            self.end_json(
                {
                    "ok": True,
                    "file": relative_path.strip(),
                }
            )
            return

        if parsed.path == "/api/workspace/delete-paths":
            raw_paths = payload.get("paths")
            if not isinstance(raw_paths, list) or not raw_paths:
                self.end_json({"error": "paths must be a non-empty array"}, HTTPStatus.BAD_REQUEST)
                return

            deleted: list[str] = []
            seen: set[str] = set()
            normalized_paths: list[str] = []

            for raw_path in raw_paths:
                if not isinstance(raw_path, str) or not raw_path.strip():
                    self.end_json({"error": "every path must be a non-empty string"}, HTTPStatus.BAD_REQUEST)
                    return

                relative_path = raw_path.strip()
                if relative_path in seen:
                    continue
                normalized_paths.append(relative_path)
                seen.add(relative_path)

            normalized_paths.sort()
            pruned_paths: list[str] = []

            for candidate in normalized_paths:
                if any(candidate.startswith(f"{other}/") for other in pruned_paths):
                    continue
                pruned_paths.append(candidate)

            for relative_path in pruned_paths:
                try:
                    target = resolve_workspace_path(relative_path, require_exists=True)
                except ValueError as error:
                    self.end_json({"error": str(error)}, HTTPStatus.BAD_REQUEST)
                    return

                if target == current_workspace():
                    self.end_json({"error": "cannot delete workspace root"}, HTTPStatus.BAD_REQUEST)
                    return

                if not target.exists():
                    self.end_json({"error": f"path not found: {relative_path}"}, HTTPStatus.NOT_FOUND)
                    return

                if target.is_dir():
                    shutil.rmtree(target)
                else:
                    target.unlink()

                deleted.append(relative_path)

            self.end_json({"ok": True, "deleted": deleted})
            return

        if parsed.path == "/api/workspace/rename-file":
            relative_path = payload.get("path")
            next_relative_path = payload.get("nextPath")
            if not isinstance(relative_path, str) or not relative_path.strip():
                self.end_json({"error": "path must be a non-empty string"}, HTTPStatus.BAD_REQUEST)
                return
            if not isinstance(next_relative_path, str) or not next_relative_path.strip():
                self.end_json({"error": "nextPath must be a non-empty string"}, HTTPStatus.BAD_REQUEST)
                return

            try:
                source = resolve_workspace_path(relative_path.strip(), require_exists=True)
                target = resolve_workspace_path(next_relative_path.strip())
            except ValueError as error:
                self.end_json({"error": str(error)}, HTTPStatus.BAD_REQUEST)
                return

            if not source.exists():
                self.end_json({"error": "file not found"}, HTTPStatus.NOT_FOUND)
                return
            if not source.is_file():
                self.end_json({"error": "path must point to a file"}, HTTPStatus.BAD_REQUEST)
                return
            if target.exists():
                self.end_json({"error": "target path already exists"}, HTTPStatus.CONFLICT)
                return

            target.parent.mkdir(parents=True, exist_ok=True)
            source.rename(target)
            self.end_json(
                {
                    "ok": True,
                    "file": relative_path.strip(),
                    "nextFile": target.relative_to(current_workspace()).as_posix(),
                    "path": str(target),
                }
            )
            return

        if parsed.path.startswith("/api/workspace/file/"):
            relative_path = unquote(parsed.path.removeprefix("/api/workspace/file/")).strip()
            content = payload.get("content")
            if not isinstance(content, str):
                self.end_json({"error": "content must be a string"}, HTTPStatus.BAD_REQUEST)
                return

            try:
                target = resolve_workspace_path(relative_path, require_exists=True)
            except ValueError as error:
                self.end_json({"error": str(error)}, HTTPStatus.BAD_REQUEST)
                return
            target.write_text(content, encoding="utf-8")
            self.end_json(
                {
                    "ok": True,
                    "file": relative_path,
                    "bytes": len(content.encode("utf-8")),
                    "path": str(target),
                }
            )
            return

        self.end_json({"error": "unknown endpoint"}, HTTPStatus.NOT_FOUND)


def main() -> None:
    current_workspace().mkdir(parents=True, exist_ok=True)
    server = ThreadingHTTPServer((HOST, PORT), PrototypeHandler)
    print(f"Vityo dev server listening on http://{HOST}:{PORT}", flush=True)
    if mutation_enabled():
        print("workspace mutation APIs enabled for this local dev session", flush=True)
    else:
        print(f"workspace mutation APIs disabled; set {ENABLE_MUTATION_ENV}=1 to enable local writes", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
