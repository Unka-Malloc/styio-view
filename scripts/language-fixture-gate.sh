#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/language-fixture-gate.sh [options]

Run the Vityo Styio language fixture confidence gate through the configured
Styio executable.

Options:
  --flutter-dir <dir>    Flutter shell directory (default: frontend/vityo_app)
  --fixture-root <dir>   Fixture root inside the Flutter directory (can repeat).
                         Defaults to parser-backed CI fixture roots:
                         test/fixtures/language_service and
                         test/fixtures/styio_language/syntax_contract
  --styio-bin <path>     Explicit Styio executable path
  -h, --help             Show this help

Resolution order for Styio:
  1. --styio-bin
  2. STYIO environment variable
  3. ../styio-nightly/build/default/bin/styio
  4. ../styio-nightly/build/bin/styio
  5. /usr/local/bin/styio
  6. styio found on PATH
USAGE
}

log() {
  echo "[language-fixture-gate] $*"
}

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

FLUTTER_DIR="frontend/vityo_app"
DEFAULT_FIXTURE_ROOTS=(
  "test/fixtures/language_service"
  "test/fixtures/styio_language/syntax_contract"
)
FIXTURE_ROOTS=()
STYIO_BIN="${STYIO:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --flutter-dir)
      FLUTTER_DIR="$2"
      shift 2
      ;;
    --fixture-root)
      FIXTURE_ROOTS+=("$2")
      shift 2
      ;;
    --styio-bin)
      STYIO_BIN="$2"
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

resolve_styio() {
  if [[ -n "$STYIO_BIN" ]]; then
    printf '%s\n' "$STYIO_BIN"
    return
  fi
  for candidate in \
    "$ROOT/../styio-nightly/build/default/bin/styio" \
    "$ROOT/../styio-nightly/build/bin/styio" \
    "/usr/local/bin/styio"; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return
    fi
  done
  command -v styio 2>/dev/null || true
}

STYIO_BIN="$(resolve_styio)"
if [[ -z "$STYIO_BIN" || ! -x "$STYIO_BIN" ]]; then
  # Machine-readable JSON for parser-unavailable (requirement: parser unavailable reason)
  echo '{"gatePassed":false,"blocked":true,"reason":"Parser unavailable: Styio executable not found. Pass --styio-bin or set STYIO.","summary":{"total":0,"passed":0,"failed":0,"truePositive":0,"trueNegative":0,"falsePositive":0,"falseNegative":0,"unlabeled":0}}'
  echo "Language fixture gate: blocked (parser unavailable — Styio executable not found)" >&2
  exit 2
fi

if [[ "${#FIXTURE_ROOTS[@]}" -eq 0 ]]; then
  FIXTURE_ROOTS=("${DEFAULT_FIXTURE_ROOTS[@]}")
fi

log "styio: $STYIO_BIN"
for fixture_root in "${FIXTURE_ROOTS[@]}"; do
  log "fixture root: $FLUTTER_DIR/$fixture_root"
done

(
  cd "$FLUTTER_DIR"
  LANGUAGE_FIXTURE_ARGS=(dart run tool/language_fixture_gate.dart --styio "$STYIO_BIN")
  for fixture_root in "${FIXTURE_ROOTS[@]}"; do
    LANGUAGE_FIXTURE_ARGS+=(--root "$fixture_root")
  done
  "${LANGUAGE_FIXTURE_ARGS[@]}"
)
