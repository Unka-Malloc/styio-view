#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/checkpoint-health.sh [options]

Run the repository-wide checkpoint health gate for Vityo.

Options:
  --flutter-dir <dir>    Flutter shell directory (default: frontend/vityo_app)
  --prototype-dir <dir>  Handwritten prototype directory (default: prototype)
  --editor-url <url>     Focused editor URL for prototype selftest (default: http://127.0.0.1:4180/editor)
  --styio-bin <path>     Explicit Styio executable for language fixture gate
  --skip-language-fixtures
                          Skip Styio language fixture confidence gate
  -h, --help             Show this help
USAGE
}

log() {
  echo "[checkpoint-health] $*"
}

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

FLUTTER_DIR="frontend/vityo_app"
PROTOTYPE_DIR="prototype"
EDITOR_URL="http://127.0.0.1:4180/editor"
STYIO_BIN="${STYIO:-}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
RUN_LANGUAGE_FIXTURES=1

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
    --styio-bin)
      STYIO_BIN="$2"
      shift 2
      ;;
    --skip-language-fixtures)
      RUN_LANGUAGE_FIXTURES=0
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

log "flutter analyze"
(cd "$FLUTTER_DIR" && flutter analyze)

log "repo hygiene policy tests"
"$PYTHON_BIN" -m unittest tests.test_repo_hygiene_gate

log "project coverage gate"
"$PYTHON_BIN" scripts/project-coverage-gate.py --python-fail-under 95 --flutter-fail-under 85 --flutter-dir "$FLUTTER_DIR"

log "release readiness static gate"
"$PYTHON_BIN" scripts/release-readiness-gate.py --flutter-dir "$FLUTTER_DIR" --skip-build

if [[ "$RUN_LANGUAGE_FIXTURES" -eq 1 ]]; then
  log "language fixture confidence gate"
  LANGUAGE_FIXTURE_CMD=(./scripts/language-fixture-gate.sh --flutter-dir "$FLUTTER_DIR")
  if [[ -n "$STYIO_BIN" ]]; then
    LANGUAGE_FIXTURE_CMD+=(--styio-bin "$STYIO_BIN")
  fi
  "${LANGUAGE_FIXTURE_CMD[@]}"
else
  log "language fixture confidence gate skipped"
fi

log "prototype governance"
(cd "$PROTOTYPE_DIR" && npm run governance)

log "prototype selftest"
(cd "$PROTOTYPE_DIR" && STYIO_EDITOR_URL="$EDITOR_URL" npm run selftest:editor)

log "all checks passed"
