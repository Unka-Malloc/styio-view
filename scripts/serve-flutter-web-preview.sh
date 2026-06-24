#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOST="${VITYO_WEB_PREVIEW_HOST:-127.0.0.1}"
PORT="${VITYO_WEB_PREVIEW_PORT:-8080}"
BUILD_MODE="${VITYO_WEB_PREVIEW_BUILD_MODE:-debug}"
SKIP_BUILD=0
STRICT_PORT=0

usage() {
  cat <<'EOF'
Usage: ./scripts/serve-flutter-web-preview.sh [options]

Serve the canonical Vityo focused editor at /editor.

Options:
  --host HOST       Bind host. Default: 127.0.0.1
  --port PORT       Preferred port. Default: 8080
  --debug           Accepted for compatibility; no Flutter build is run.
  --release         Accepted for compatibility; no Flutter build is run.
  --skip-build      Accepted for compatibility; no Flutter build is run.
  -h, --help        Show this help.

Environment:
  VITYO_WEB_PREVIEW_HOST
  VITYO_WEB_PREVIEW_PORT
  STYIO_DEV_SERVER_ENABLE_MUTATION

EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)
      HOST="${2:?missing host}"
      shift 2
      ;;
    --port)
      PORT="${2:?missing port}"
      STRICT_PORT=1
      shift 2
      ;;
    --debug)
      BUILD_MODE="debug"
      shift
      ;;
    --release)
      BUILD_MODE="release"
      shift
      ;;
    --skip-build)
      SKIP_BUILD=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "$BUILD_MODE" != "debug" && "$BUILD_MODE" != "release" ]]; then
  echo "Unsupported build mode: $BUILD_MODE" >&2
  exit 2
fi

port_is_free() {
  python3 - "$HOST" "$1" <<'PY'
import socket
import sys

host = sys.argv[1]
port = int(sys.argv[2])
with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        sock.bind((host, port))
    except OSError:
        sys.exit(1)
PY
}

select_port() {
  local candidate="$PORT"
  if port_is_free "$candidate"; then
    echo "$candidate"
    return
  fi

  if [[ "$STRICT_PORT" -eq 1 ]]; then
    echo "Port $candidate is already in use on $HOST." >&2
    exit 1
  fi

  for candidate in $(seq "$((PORT + 1))" "$((PORT + 50))"); do
    if port_is_free "$candidate"; then
      echo "$candidate"
      return
    fi
  done

  echo "No free port found in ${PORT}..$((PORT + 50)) on $HOST." >&2
  exit 1
}

check_host="$HOST"
if [[ "$check_host" == "0.0.0.0" ]]; then
  check_host="127.0.0.1"
fi

selected_port="$(select_port)"
export STYIO_DEV_SERVER_HOST="$HOST"
export STYIO_DEV_SERVER_PORT="$selected_port"

python3 "$ROOT_DIR/prototype/dev_server.py" &
server_pid="$!"

cleanup() {
  if kill -0 "$server_pid" 2>/dev/null; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
}
trap cleanup INT TERM EXIT

base_url="http://${check_host}:${selected_port}"

for _ in $(seq 1 60); do
  if curl -fsS "$base_url/editor" >/dev/null 2>&1; then
    break
  fi
  if ! kill -0 "$server_pid" 2>/dev/null; then
    echo "Preview server exited before becoming ready." >&2
    wait "$server_pid"
    exit 1
  fi
  sleep 0.25
done

curl -fsSI "$base_url/editor" >/dev/null

cat <<EOF
Vityo focused editor preview is ready.

URL:
  $base_url/editor

Root:
  $base_url/ redirects to /editor

Mode:
  canonical focused editor

Note:
  This route serves prototype/editor.html, the product-facing editor surface.
  The Flutter integration shell is not used as the default preview page.

Press Ctrl-C to stop the server.
EOF

wait "$server_pid"
