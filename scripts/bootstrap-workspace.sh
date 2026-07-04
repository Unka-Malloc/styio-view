#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLUTTER_HOME="${VITYO_FLUTTER_HOME:-$HOME/develop/flutter}"
FLUTTER_BIN="${VITYO_FLUTTER_BIN:-$FLUTTER_HOME/bin/flutter}"
PLATFORMS="${VITYO_FLUTTER_PLATFORMS:-}"
SKIP_PLATFORM_BOOTSTRAP=0
SKIP_NPM=0
SKIP_FLUTTER_PUB=0

usage() {
  cat <<'EOF'
Usage: bootstrap-workspace.sh [options]

Restore repo-local dependencies and generate Flutter runners for the selected
desktop/mobile platform combination.

Options:
  --platforms <csv>         Explicit Flutter platform list
  --with-android            Add Android runner support
  --with-ios                Add iOS runner support (macOS only)
  --skip-platform-bootstrap Skip flutter create --platforms
  --skip-npm                Skip prototype npm ci
  --skip-flutter-pub        Skip flutter pub get
  -h, --help                Show this help
EOF
}

log() {
  printf '[Vityo workspace] %s\n' "$*"
}

fail() {
  printf '[Vityo workspace] %s\n' "$*" >&2
  exit 1
}

host_desktop_platform() {
  case "$(uname -s)" in
    Linux)
      echo "linux"
      ;;
    Darwin)
      echo "macos"
      ;;
    *)
      fail "unsupported host for bootstrap-workspace.sh: $(uname -s)"
      ;;
  esac
}

ensure_platform() {
  local name="$1"
  if [[ ",$PLATFORMS," != *",$name,"* ]]; then
    if [[ -n "$PLATFORMS" ]]; then
      PLATFORMS="$PLATFORMS,$name"
    else
      PLATFORMS="$name"
    fi
  fi
}

ensure_defaults() {
  if [[ -z "$PLATFORMS" ]]; then
    PLATFORMS="web,$(host_desktop_platform)"
  fi
}

verify_platforms() {
  case "$(uname -s)" in
    Linux)
      [[ ",$PLATFORMS," != *",ios,"* ]] || fail "iOS runners require macOS"
      ;;
    Darwin)
      ;;
    *)
      fail "unsupported host for platform validation: $(uname -s)"
      ;;
  esac
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --platforms)
        PLATFORMS="$2"
        shift 2
        ;;
      --with-android)
        ensure_platform "android"
        shift
        ;;
      --with-ios)
        ensure_platform "ios"
        shift
        ;;
      --skip-platform-bootstrap)
        SKIP_PLATFORM_BOOTSTRAP=1
        shift
        ;;
      --skip-npm)
        SKIP_NPM=1
        shift
        ;;
      --skip-flutter-pub)
        SKIP_FLUTTER_PUB=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        fail "unknown option: $1"
        ;;
    esac
  done

  ensure_defaults
  verify_platforms

  if [[ ! -x "$FLUTTER_BIN" ]] && ! command -v flutter >/dev/null 2>&1; then
    fail "flutter is not installed. Set VITYO_FLUTTER_HOME or VITYO_FLUTTER_BIN."
  fi

  if [[ ! -x "$FLUTTER_BIN" ]]; then
    FLUTTER_BIN="$(command -v flutter)"
  fi

  if [[ $SKIP_PLATFORM_BOOTSTRAP -eq 0 ]]; then
    log "generating Flutter runners for platforms: $PLATFORMS"
    app_root="$ROOT/frontend/vityo_app"
    default_widget_test="$app_root/test/widget_test.dart"
    had_default_widget_test=0
    if [[ -e "$default_widget_test" ]]; then
      had_default_widget_test=1
    fi
    (
      cd "$app_root"
      "$FLUTTER_BIN" create \
        --platforms="$PLATFORMS" \
        --project-name=vityo_app \
        --org=io.vityo \
        .
    )
    if [[ $had_default_widget_test -eq 0 && -e "$default_widget_test" ]]; then
      rm -f "$default_widget_test"
    fi
  fi

  if [[ $SKIP_NPM -eq 0 ]]; then
    log "installing prototype npm dependencies"
    (cd "$ROOT/prototype" && npm ci)
  fi

  if [[ $SKIP_FLUTTER_PUB -eq 0 ]]; then
    log "installing Flutter package dependencies"
    (
      cd "$ROOT/frontend/vityo_app"
      "$FLUTTER_BIN" pub get
    )
  fi

  log "workspace bootstrap complete"
}

main "$@"
