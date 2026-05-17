#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/lib/flutter-workspace-common.sh"
FLUTTER_DIR_DEFAULT="$ROOT/frontend/vityo_app"
WORK_DIR_DEFAULT="$ROOT/build/apple-device-workspaces"

PROFILE=""
DEVICE_ID=""
MODE="debug"
FLUTTER_DIR="$FLUTTER_DIR_DEFAULT"
WORK_DIR="$WORK_DIR_DEFAULT"
LIST_DEVICES=0
SIMULATOR=0
NO_CODESIGN=0
declare -a EXTRA_ARGS=()

usage() {
  cat <<'EOF'
Usage: verify-apple-device.sh [options] [-- <extra flutter run args>]

Run Vityo against a real Apple target using one of the standardized Apple
profiles. iOS profiles target physical devices or simulators. macOS profiles
target the local Mac host via `flutter run -d macos`.

Options:
  --profile <name>         Apple profile from toolchain/apple-platform-profiles.csv
  --device-id <id>         Flutter device id; required for iOS physical devices
  --mode <debug|profile|release>
                           Flutter run mode (default: debug)
  --flutter-dir <dir>      Flutter app directory
  --work-dir <dir>         Isolated workspace root
  --list-devices           Print `flutter devices` and exit
  --simulator              Pass --simulator for iOS validation
  --no-codesign            Pass --no-codesign for iOS validation
  -h, --help               Show this help
EOF
}

log() {
  printf '[verify-apple-device] %s\n' "$*"
}

fail() {
  printf '[verify-apple-device] %s\n' "$*" >&2
  exit 1
}

ensure_macos() {
  [[ "$(uname -s)" == "Darwin" ]] || fail "Apple device verification requires macOS"
}

ensure_flutter_bin() {
  local flutter_home="${VITYO_FLUTTER_HOME:-$HOME/develop/flutter}"
  local flutter_bin="${VITYO_FLUTTER_BIN:-$flutter_home/bin/flutter}"
  vityo_resolve_flutter_bin "$flutter_bin" "$flutter_home" \
    || fail "flutter is not installed"
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --profile)
        PROFILE="$2"
        shift 2
        ;;
      --device-id)
        DEVICE_ID="$2"
        shift 2
        ;;
      --mode)
        MODE="$2"
        shift 2
        ;;
      --flutter-dir)
        FLUTTER_DIR="$2"
        shift 2
        ;;
      --work-dir)
        WORK_DIR="$2"
        shift 2
        ;;
      --list-devices)
        LIST_DEVICES=1
        shift
        ;;
      --simulator)
        SIMULATOR=1
        shift
        ;;
      --no-codesign)
        NO_CODESIGN=1
        shift
        ;;
      --)
        shift
        EXTRA_ARGS=("$@")
        break
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

  ensure_macos
  local flutter_bin
  flutter_bin="$(ensure_flutter_bin)"

  if [[ $LIST_DEVICES -eq 1 ]]; then
    "$flutter_bin" devices
    exit 0
  fi

  [[ -n "$PROFILE" ]] || fail "--profile is required"
  local family
  family="$(VITYO_APPLE_PROFILE_FILE="${VITYO_APPLE_PROFILE_FILE:-$ROOT/toolchain/apple-platform-profiles.csv}" "$ROOT/scripts/apple-platform-profile.sh" env "$PROFILE" | awk -F= '/VITYO_APPLE_PROFILE_FAMILY/ {gsub(/"/,"",$2); print $2}')"
  [[ -n "$family" ]] || fail "unable to resolve Apple profile family for $PROFILE"

  local workspace_root="$WORK_DIR/$PROFILE"
  local app_dir="$workspace_root/$(basename "$FLUTTER_DIR")"
  vityo_copy_flutter_project "$FLUTTER_DIR" "$workspace_root"

  local -a cmd=()
  case "$family" in
    ios)
      [[ -n "$DEVICE_ID" || $SIMULATOR -eq 1 ]] || fail "iOS verification requires --device-id or --simulator"
      cmd=("$flutter_bin" "run" "--$MODE")
      if [[ $SIMULATOR -eq 1 ]]; then
        cmd+=("--simulator")
      else
        cmd+=("-d" "$DEVICE_ID")
      fi
      if [[ $NO_CODESIGN -eq 1 ]]; then
        cmd+=("--no-codesign")
      fi
      ;;
    macos)
      cmd=("$flutter_bin" "run" "--$MODE" "-d" "${DEVICE_ID:-macos}")
      ;;
    *)
      fail "unsupported Apple profile family: $family"
      ;;
  esac

  if [[ ${#EXTRA_ARGS[@]} -gt 0 ]]; then
    cmd+=("${EXTRA_ARGS[@]}")
  fi

  log "starting Apple verification run for profile $PROFILE"
  (
    eval "$("$ROOT/scripts/apple-platform-profile.sh" env "$PROFILE")"
    cd "$app_dir"
    FLUTTER_BUILD_DIR="build-$PROFILE" "${cmd[@]}"
  )
}

main "$@"
