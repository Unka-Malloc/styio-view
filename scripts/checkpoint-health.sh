#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/checkpoint-health.sh [options]

Run the repository-wide checkpoint health gate for styio-view.

Options:
  --flutter-dir <dir>    Flutter shell directory (default: frontend/styio_view_app)
  --prototype-dir <dir>  Handwritten prototype directory (default: prototype)
  --editor-url <url>     Focused editor URL for prototype selftest (default: http://127.0.0.1:4180/editor.html)
  -h, --help             Show this help
USAGE
}

log() {
  echo "[checkpoint-health] $*"
}

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

FLUTTER_DIR="frontend/styio_view_app"
PROTOTYPE_DIR="prototype"
EDITOR_URL="http://127.0.0.1:4180/editor.html"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --flutter-dir)
      FLUTTER_DIR="$2"
      shift 2
      ;;
    --prototype-dir)
      PROTOTYPE_DIR="$2"
      shift 2
      ;;
    --editor-url)
      EDITOR_URL="$2"
      shift 2
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

log "flutter analyze"
(cd "$FLUTTER_DIR" && flutter analyze)

log "flutter test"
(cd "$FLUTTER_DIR" && flutter test)

log "prototype governance"
(cd "$PROTOTYPE_DIR" && npm run governance)

log "prototype selftest"
(cd "$PROTOTYPE_DIR" && STYIO_EDITOR_URL="$EDITOR_URL" npm run selftest:editor)

log "all checks passed"
