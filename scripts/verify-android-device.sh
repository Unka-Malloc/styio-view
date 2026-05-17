#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLUTTER_DIR_DEFAULT="$ROOT/frontend/vityo_app"
OUT_DIR_DEFAULT="$ROOT/build/android-device-verification"
WORK_DIR_DEFAULT="$ROOT/build/android-device-workspaces"
PACKAGE_NAME_DEFAULT="io.vityo.app"

PROFILE=""
DEVICE_ID=""
MODE="debug"
FLUTTER_DIR="$FLUTTER_DIR_DEFAULT"
OUT_DIR="$OUT_DIR_DEFAULT"
WORK_DIR="$WORK_DIR_DEFAULT"
PACKAGE_NAME="$PACKAGE_NAME_DEFAULT"
TARGET_PLATFORM=""
BUILD_ONLY=0
NO_LAUNCH=0
LIST_DEVICES=0
declare -a EXTRA_ARGS=()

usage() {
  cat <<'EOF'
Usage: verify-android-device.sh [options] [-- <extra flutter build args>]

Build, install, and optionally launch Vityo on a real Android device using
one of the standardized Android SDK profiles.

Options:
  --profile <name>         Android profile from toolchain/android-sdk-profiles.csv
  --device-id <id>         adb device id; when omitted, a single connected device is auto-selected
  --mode <debug|profile|release>
                           Flutter build mode (default: debug)
  --flutter-dir <dir>      Flutter app directory
  --out-dir <dir>          Artifact output root
  --work-dir <dir>         Isolated workspace root
  --package-name <name>    Android application id (default: io.vityo.app)
  --target-platform <csv>  Pass through Flutter --target-platform
  --build-only             Build the APK but skip adb install/launch
  --no-launch              Install the APK but skip app launch
  --list-devices           Print adb devices and exit
  -h, --help               Show this help
EOF
}

log() {
  printf '[verify-android-device] %s\n' "$*"
}

fail() {
  printf '[verify-android-device] %s\n' "$*" >&2
  exit 1
}

require_adb() {
  command -v adb >/dev/null 2>&1 || fail "adb is required"
}

list_devices() {
  require_adb
  adb devices -l
}

select_device() {
  local -a devices=()
  local line serial state

  while IFS= read -r line; do
    [[ "$line" == List\ of\ devices* ]] && continue
    [[ -n "$line" ]] || continue
    serial="$(printf '%s\n' "$line" | awk '{print $1}')"
    state="$(printf '%s\n' "$line" | awk '{print $2}')"
    [[ "$state" == "device" ]] || continue
    devices+=("$serial")
  done < <(adb devices)

  if [[ ${#devices[@]} -eq 1 ]]; then
    printf '%s\n' "${devices[0]}"
    return
  fi

  if [[ ${#devices[@]} -eq 0 ]]; then
    fail "no authorized Android devices are connected"
  fi

  fail "multiple Android devices are connected; pass --device-id explicitly"
}

find_apk() {
  local profile="$1"
  local mode="$2"
  local artifact_root="$OUT_DIR/$profile/outputs/flutter-apk"
  local apk_name="app-${mode}.apk"

  if [[ -f "$artifact_root/$apk_name" ]]; then
    printf '%s\n' "$artifact_root/$apk_name"
    return
  fi

  find "$artifact_root" -maxdepth 1 -type f -name '*.apk' | sort | head -n 1
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
      --out-dir)
        OUT_DIR="$2"
        shift 2
        ;;
      --work-dir)
        WORK_DIR="$2"
        shift 2
        ;;
      --package-name)
        PACKAGE_NAME="$2"
        shift 2
        ;;
      --target-platform)
        TARGET_PLATFORM="$2"
        shift 2
        ;;
      --build-only)
        BUILD_ONLY=1
        shift
        ;;
      --no-launch)
        NO_LAUNCH=1
        shift
        ;;
      --list-devices)
        LIST_DEVICES=1
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

  if [[ $LIST_DEVICES -eq 1 ]]; then
    list_devices
    exit 0
  fi

  [[ -n "$PROFILE" ]] || fail "--profile is required"
  require_adb
  if [[ -z "$DEVICE_ID" ]]; then
    DEVICE_ID="$(select_device)"
  fi

  local -a build_cmd=(
    "$ROOT/scripts/android-sdk-profile.sh"
    build
    --profiles "$PROFILE"
    --artifact apk
    --mode "$MODE"
    --flutter-dir "$FLUTTER_DIR"
    --out-dir "$OUT_DIR"
    --work-dir "$WORK_DIR"
  )
  if [[ -n "$TARGET_PLATFORM" ]]; then
    build_cmd+=(--target-platform "$TARGET_PLATFORM")
  fi
  if [[ ${#EXTRA_ARGS[@]} -gt 0 ]]; then
    build_cmd+=(-- "${EXTRA_ARGS[@]}")
  fi

  log "building APK for profile $PROFILE"
  "${build_cmd[@]}"

  local apk_path
  apk_path="$(find_apk "$PROFILE" "$MODE")"
  [[ -n "$apk_path" && -f "$apk_path" ]] || fail "unable to locate built APK for profile $PROFILE"

  if [[ $BUILD_ONLY -eq 1 ]]; then
    log "build complete: $apk_path"
    exit 0
  fi

  log "installing APK on device $DEVICE_ID"
  adb -s "$DEVICE_ID" install -r "$apk_path"

  if [[ $NO_LAUNCH -eq 0 ]]; then
    log "launching package $PACKAGE_NAME on device $DEVICE_ID"
    adb -s "$DEVICE_ID" shell monkey -p "$PACKAGE_NAME" -c android.intent.category.LAUNCHER 1 >/dev/null
  fi

  log "Android device verification deploy complete"
}

main "$@"
