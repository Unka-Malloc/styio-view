#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/delivery-gate.sh [options]

Run the common Styio delivery floor by composing repository hygiene, the docs
gate, external audit, and checkpoint health into one entrypoint.

Options:
  --mode <checkpoint|push>  Delivery mode (default: checkpoint)
  --base <ref>              Base ref for team-docs-gate branch checks
  --range <rev-range>       Explicit revision range for repo-hygiene push mode
  --skip-health             Skip checkpoint-health (docs/process-only deliveries)
  --skip-audit              Skip external styio-audit gate
  --skip-ecosystem          Skip ecosystem CLI doc consistency check in docs-gate
  --audit-bin <path>        Explicit styio-audit executable
  -h, --help                Show this help
USAGE
}

log() {
  echo "[delivery-gate] $*"
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

MODE="checkpoint"
BASE_REF=""
REV_RANGE=""
RUN_HEALTH=1
RUN_AUDIT=1
SKIP_ECOSYSTEM=0
AUDIT_BIN="${STYIO_AUDIT_BIN:-}"

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
    --range)
      REV_RANGE="$2"
      shift 2
      ;;
    --skip-health)
      RUN_HEALTH=0
      shift
      ;;
    --skip-audit)
      RUN_AUDIT=0
      shift
      ;;
    --skip-ecosystem)
      SKIP_ECOSYSTEM=1
      shift
      ;;
    --audit-bin)
      AUDIT_BIN="$2"
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

REPO_CMD=(python3 scripts/repo-hygiene-gate.py)
DOCS_GATE_CMD=(./scripts/docs-gate.sh)
HEALTH_CMD=(./scripts/checkpoint-health.sh)

case "$MODE" in
  checkpoint)
    REPO_CMD+=(--mode staged)
    DOCS_GATE_CMD+=(--mode staged)
    ;;
  push)
    REPO_CMD+=(--mode push)
    if [[ -n "$REV_RANGE" ]]; then
      REPO_CMD+=(--range "$REV_RANGE")
    fi
    if [[ -z "$BASE_REF" ]]; then
      BASE_REF="$(default_upstream_base)"
    fi
    if [[ -z "$BASE_REF" ]]; then
      echo "push mode requires --base <ref> or a configured upstream branch" >&2
      exit 2
    fi
    DOCS_GATE_CMD+=(--mode push --base "$BASE_REF")
    ;;
  *)
    echo "Unsupported mode: $MODE" >&2
    usage >&2
    exit 2
    ;;
esac

if [[ "$SKIP_ECOSYSTEM" -eq 1 ]]; then
  DOCS_GATE_CMD+=(--skip-ecosystem)
fi

run_cmd "${REPO_CMD[@]}"
run_cmd "${DOCS_GATE_CMD[@]}"

if [[ "$RUN_AUDIT" -eq 1 ]]; then
  if [[ -z "$AUDIT_BIN" ]]; then
    if [[ -x "$ROOT/../styio-audit/bin/styio-audit" ]]; then
      AUDIT_BIN="$ROOT/../styio-audit/bin/styio-audit"
    elif [[ -x "$ROOT/../../eBioRing/styio-audit/bin/styio-audit" ]]; then
      AUDIT_BIN="$ROOT/../../eBioRing/styio-audit/bin/styio-audit"
    elif [[ -x "/home/unka/styio-audit/bin/styio-audit" ]]; then
      AUDIT_BIN="/home/unka/styio-audit/bin/styio-audit"
    elif command -v styio-audit >/dev/null 2>&1; then
      AUDIT_BIN="$(command -v styio-audit)"
    fi
  fi
  if [[ -z "$AUDIT_BIN" || ! -x "$AUDIT_BIN" ]]; then
    log "styio-audit executable not found; running local security audit fallback"
    run_cmd python3 scripts/check_security_baseline.py
    run_cmd python3 scripts/check_license_policy.py
    run_cmd python3 scripts/check_architecture_boundaries.py
    run_cmd python3 scripts/check_compat_facades.py
    run_cmd python3 scripts/import-boundary-gate.py
  else
    AUDIT_ROOT="$(cd "$(dirname "$AUDIT_BIN")/.." && pwd)"
    if git -C "$AUDIT_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      log "styio-audit commit: $(git -C "$AUDIT_ROOT" rev-parse HEAD)"
    fi
    run_cmd "$AUDIT_BIN" gate --repo "$ROOT" --project Vityo
  fi
else
  log "styio-audit skipped"
fi

if [[ "$RUN_HEALTH" -eq 1 ]]; then
  run_cmd "${HEALTH_CMD[@]}"
else
  log "checkpoint-health skipped"
fi

log "all checks passed"
