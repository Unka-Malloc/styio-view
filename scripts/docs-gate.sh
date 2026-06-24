#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/docs-gate.sh [options]

Run the common docs/process gate by composing team-runbook maintenance,
docs audit, and ecosystem CLI contract consistency into one entrypoint.

Options:
  --mode <worktree|staged|push>  Change source for team-docs-gate (default: worktree)
  --base <ref>                   Base ref for push-mode team-docs-gate
  --skip-ecosystem               Skip the ecosystem CLI doc consistency check
  -h, --help                     Show this help
USAGE
}

log() {
  echo "[docs-gate] $*"
}

run_cmd() {
  log "$*"
  "$@"
}

default_upstream_base() {
  git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true
}

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

MODE="worktree"
BASE_REF=""
SKIP_ECOSYSTEM=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="$2"
      shift 2
      ;;
    --base)
      BASE_REF="$2"
      shift 2
      ;;
    --skip-ecosystem)
      SKIP_ECOSYSTEM=1
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

TEAM_CMD=(python3 scripts/team-docs-gate.py)
case "$MODE" in
  worktree)
    ;;
  staged)
    TEAM_CMD+=(--mode staged)
    ;;
  push)
    if [[ -z "$BASE_REF" ]]; then
      BASE_REF="$(default_upstream_base)"
    fi
    if [[ -z "$BASE_REF" ]]; then
      echo "push mode requires --base <ref> or a configured upstream branch" >&2
      exit 2
    fi
    TEAM_CMD+=(--base "$BASE_REF")
    ;;
  *)
    echo "Unsupported mode: $MODE" >&2
    usage >&2
    exit 2
    ;;
esac

run_cmd "${TEAM_CMD[@]}"
run_cmd env STYIO_SKIP_TEAM_DOC_GATE=1 python3 scripts/docs-audit.py
if [[ "$SKIP_ECOSYSTEM" -eq 1 ]]; then
  log "ecosystem CLI doc consistency check skipped"
else
  run_cmd python3 scripts/ecosystem-cli-doc-gate.py --non-blocking
fi
log "all checks passed"
