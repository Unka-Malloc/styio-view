#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/frontend/vityo_app"
HOST="${VITYO_WEB_PREVIEW_HOST:-127.0.0.1}"
PORT="${VITYO_WEB_PREVIEW_PORT:-8080}"
BUILD_MODE="${VITYO_WEB_PREVIEW_BUILD_MODE:-debug}"
SKIP_BUILD=0
STRICT_PORT=0

usage() {
  cat <<'EOF'
Usage: ./scripts/serve-flutter-web-preview.sh [options]

Build and serve the Vityo Flutter Web shell with the local hosted-control
plane preview API required for browser startup.

Options:
  --host HOST       Bind host. Default: 127.0.0.1
  --port PORT       Preferred port. Default: 8080
  --debug           Build debug web output. Default.
  --release         Build release web output.
  --skip-build      Serve existing build/web output.
  -h, --help        Show this help.

Environment:
  VITYO_WEB_PREVIEW_HOST
  VITYO_WEB_PREVIEW_PORT
  VITYO_WEB_PREVIEW_BUILD_MODE

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

cd "$APP_DIR"

if [[ "$SKIP_BUILD" -eq 0 ]]; then
  flutter pub get
  flutter build web "--$BUILD_MODE"
fi

if [[ ! -f "$APP_DIR/build/web/flutter_bootstrap.js" ]]; then
  echo "Missing build/web/flutter_bootstrap.js. Run without --skip-build once." >&2
  exit 1
fi

selected_port="$(select_port)"
export VITYO_WEB_PREVIEW_HOST="$HOST"
export VITYO_WEB_PREVIEW_PORT="$selected_port"

python3 scripts/serve_web_preview.py &
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
  if curl -fsS "$base_url/" >/dev/null 2>&1; then
    break
  fi
  if ! kill -0 "$server_pid" 2>/dev/null; then
    echo "Preview server exited before becoming ready." >&2
    wait "$server_pid"
    exit 1
  fi
  sleep 0.25
done

curl -fsSI "$base_url/flutter_bootstrap.js" >/dev/null
curl -fsSI "$base_url/main.dart.js" >/dev/null
curl -fsS \
  -H 'Content-Type: application/json' \
  -X POST \
  "$base_url/api/styio-hosted/v1/workspaces/open" \
  -d '{"platform":"web"}' >/dev/null

cat <<EOF
Vityo Flutter Web preview is ready.

URL:
  $base_url/

Mode:
  build: $BUILD_MODE
  hosted control-plane: local preview mock

Note:
  The preview mock lets the Web shell boot for UI and language-service checks.
  It does not prove real Styio compile/run/package workflows are complete.

Press Ctrl-C to stop the server.
EOF

wait "$server_pid"
