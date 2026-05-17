#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/lib/flutter-workspace-common.sh"
PROFILE_FILE="${VITYO_APPLE_PROFILE_FILE:-$ROOT/toolchain/apple-platform-profiles.csv}"
FLUTTER_HOME="${VITYO_FLUTTER_HOME:-$HOME/develop/flutter}"
FLUTTER_BIN="${VITYO_FLUTTER_BIN:-$FLUTTER_HOME/bin/flutter}"
FLUTTER_DIR_DEFAULT="$ROOT/frontend/vityo_app"
OUT_DIR_DEFAULT="$ROOT/build/apple-profile-artifacts"
WORK_DIR_DEFAULT="$ROOT/build/apple-profile-workspaces"

declare -A PROFILE_FAMILY=()
declare -A PROFILE_IOS_TARGET=()
declare -A PROFILE_MACOS_TARGET=()
declare -A PROFILE_DEVELOPER_DIR=()
declare -A DEFAULT_BY_FAMILY=()
declare -a PROFILE_ORDER=()

usage() {
  cat <<'EOF'
Usage: apple-platform-profile.sh <command> [options]

Manage standardized Apple build profiles for Vityo on macOS, including
selectable iOS deployment targets, macOS deployment targets, and Xcode roots.

Commands:
  list
      Show the supported Apple build profiles.
  env [<profile>]
      Print shell exports for the selected Apple profile.
  run [<profile>] -- <command...>
      Run an arbitrary command with the selected profile's Apple build env.
  build [options] [-- <extra flutter args>]
      Build one or more Apple profiles using isolated per-profile workspaces.

Build options:
  --profiles <csv>         Comma-separated profile list
  --parallel               Build the selected profiles concurrently
  --flutter-dir <dir>      Flutter app directory
  --out-dir <dir>          Artifact output root
  --work-dir <dir>         Isolated workspace root
  --mode <debug|profile|release>
                           Flutter build mode (default: debug)
  --simulator              Pass --simulator to iOS builds
  --no-codesign            Pass --no-codesign to iOS builds

Environment:
  VITYO_APPLE_PROFILE_FILE  Profile csv location
  VITYO_FLUTTER_HOME        Flutter checkout root
  VITYO_FLUTTER_BIN         Flutter binary override
EOF
}

log() {
  printf '[apple-platform-profile] %s\n' "$*"
}

fail() {
  printf '[apple-platform-profile] %s\n' "$*" >&2
  exit 1
}

ensure_macos() {
  [[ "$(uname -s)" == "Darwin" ]] || fail "Apple build profiles require macOS"
}

ensure_flutter_bin() {
  FLUTTER_BIN="$(vityo_resolve_flutter_bin "$FLUTTER_BIN" "$FLUTTER_HOME")" \
    || fail "flutter is not installed. Set VITYO_FLUTTER_BIN or VITYO_FLUTTER_HOME."
}

load_profiles() {
  local line name family ios_target macos_target developer_dir default_flag

  [[ -r "$PROFILE_FILE" ]] || fail "Apple profile file is missing: $PROFILE_FILE"
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="$(vityo_trim "$line")"
    [[ -n "$line" ]] || continue
    [[ "$line" == \#* ]] && continue
    [[ "$line" == name,* ]] && continue

    IFS=, read -r name family ios_target macos_target developer_dir default_flag <<<"$line"
    name="$(vityo_trim "$name")"
    family="$(vityo_trim "$family")"
    ios_target="$(vityo_trim "$ios_target")"
    macos_target="$(vityo_trim "$macos_target")"
    developer_dir="$(vityo_trim "$developer_dir")"
    default_flag="$(vityo_trim "$default_flag")"

    [[ -n "$name" ]] || continue
    PROFILE_ORDER+=("$name")
    PROFILE_FAMILY["$name"]="$family"
    PROFILE_IOS_TARGET["$name"]="$ios_target"
    PROFILE_MACOS_TARGET["$name"]="$macos_target"
    PROFILE_DEVELOPER_DIR["$name"]="$developer_dir"
    if [[ "$default_flag" == "yes" || "$default_flag" == "true" ]]; then
      DEFAULT_BY_FAMILY["$family"]="$name"
    fi
  done <"$PROFILE_FILE"

  [[ ${#PROFILE_ORDER[@]} -gt 0 ]] || fail "no Apple profiles found in $PROFILE_FILE"
}

require_profile() {
  local profile="$1"
  [[ -n "${PROFILE_FAMILY[$profile]:-}" ]] || fail "unknown Apple profile: $profile"
}

profiles_from_csv() {
  local csv="$1"
  local raw token
  local -a result=()

  [[ -n "$csv" ]] || fail "profile list is required"
  IFS=, read -r -a raw <<<"$csv"
  for token in "${raw[@]}"; do
    token="$(vityo_trim "$token")"
    [[ -n "$token" ]] || continue
    require_profile "$token"
    result+=("$token")
  done

  [[ ${#result[@]} -gt 0 ]] || fail "no valid Apple profiles selected"
  printf '%s\n' "${result[@]}"
}

default_profile_for_family() {
  local family="$1"
  local profile="${DEFAULT_BY_FAMILY[$family]:-}"
  [[ -n "$profile" ]] || fail "no default Apple profile configured for family: $family"
  printf '%s\n' "$profile"
}

export_profile_env() {
  local profile="$1"
  require_profile "$profile"

  local family="${PROFILE_FAMILY[$profile]}"
  local developer_dir="${PROFILE_DEVELOPER_DIR[$profile]}"

  export VITYO_APPLE_PROFILE="$profile"
  export VITYO_APPLE_PROFILE_FAMILY="$family"
  export COCOAPODS_DISABLE_STATS=true
  if [[ -n "$developer_dir" ]]; then
    export DEVELOPER_DIR="$developer_dir"
  fi

  case "$family" in
    ios)
      export VITYO_IOS_DEPLOYMENT_TARGET="${PROFILE_IOS_TARGET[$profile]}"
      unset VITYO_MACOS_DEPLOYMENT_TARGET || true
      ;;
    macos)
      export VITYO_MACOS_DEPLOYMENT_TARGET="${PROFILE_MACOS_TARGET[$profile]}"
      unset VITYO_IOS_DEPLOYMENT_TARGET || true
      ;;
    *)
      fail "unsupported Apple profile family: $family"
      ;;
  esac
}

print_env() {
  local profile="${1:-$(default_profile_for_family ios)}"
  local family developer_dir

  require_profile "$profile"
  family="${PROFILE_FAMILY[$profile]}"
  developer_dir="${PROFILE_DEVELOPER_DIR[$profile]}"

  cat <<EOF
export VITYO_APPLE_PROFILE="$profile"
export VITYO_APPLE_PROFILE_FAMILY="$family"
export COCOAPODS_DISABLE_STATS=true
EOF

  if [[ -n "$developer_dir" ]]; then
    printf 'export DEVELOPER_DIR="%s"\n' "$developer_dir"
  fi

  case "$family" in
    ios)
      printf 'export VITYO_IOS_DEPLOYMENT_TARGET="%s"\n' "${PROFILE_IOS_TARGET[$profile]}"
      ;;
    macos)
      printf 'export VITYO_MACOS_DEPLOYMENT_TARGET="%s"\n' "${PROFILE_MACOS_TARGET[$profile]}"
      ;;
  esac
}

list_profiles() {
  printf '%-14s %-8s %-10s %-12s %s\n' "profile" "family" "iosTarget" "macosTarget" "developerDir"
  for profile in "${PROFILE_ORDER[@]}"; do
    printf '%-14s %-8s %-10s %-12s %s\n' \
      "$profile" \
      "${PROFILE_FAMILY[$profile]}" \
      "${PROFILE_IOS_TARGET[$profile]:--}" \
      "${PROFILE_MACOS_TARGET[$profile]:--}" \
      "${PROFILE_DEVELOPER_DIR[$profile]}"
  done
}

run_with_profile() {
  local profile="${1:-}"
  [[ -n "$profile" ]] || fail "run requires a profile"
  shift || true
  [[ $# -gt 0 && "$1" == "--" ]] && shift
  [[ $# -gt 0 ]] || fail "run requires a command after --"

  export_profile_env "$profile"
  exec "$@"
}

build_for_profile() {
  local profile="$1"
  local flutter_dir="$2"
  local out_dir="$3"
  local work_dir="$4"
  local mode="$5"
  local simulator="$6"
  local no_codesign="$7"
  shift 7
  local -a extra_args=("$@")
  local family workspace_root app_dir outputs_root cache_dir
  local -a cmd=()

  require_profile "$profile"
  ensure_flutter_bin
  family="${PROFILE_FAMILY[$profile]}"
  workspace_root="$work_dir/$profile"
  app_dir="$workspace_root/$(basename "$flutter_dir")"
  outputs_root="$out_dir/$profile"
  cache_dir=".dart_tool-$profile"

  vityo_copy_flutter_project "$flutter_dir" "$workspace_root"

  case "$family" in
    ios)
      cmd=("$FLUTTER_BIN" "build" "ios" "--$mode")
      [[ "$simulator" == "1" ]] && cmd+=("--simulator")
      [[ "$no_codesign" == "1" ]] && cmd+=("--no-codesign")
      ;;
    macos)
      cmd=("$FLUTTER_BIN" "build" "macos" "--$mode")
      ;;
    *)
      fail "unsupported Apple profile family: $family"
      ;;
  esac

  if [[ ${#extra_args[@]} -gt 0 ]]; then
    cmd+=("${extra_args[@]}")
  fi

  log "building $family ($mode) for Apple profile $profile"
  (
    export_profile_env "$profile"
    cd "$app_dir"
    FLUTTER_BUILD_DIR="build-$profile" "${cmd[@]}"
  )

  mkdir -p "$outputs_root"
  if [[ -d "$app_dir/build-$profile" ]]; then
    rm -rf "$outputs_root/build"
    cp -a "$app_dir/build-$profile" "$outputs_root/build"
  fi
  cat >"$outputs_root/profile.env" <<EOF
VITYO_APPLE_PROFILE=$profile
VITYO_APPLE_PROFILE_FAMILY=$family
DEVELOPER_DIR=${PROFILE_DEVELOPER_DIR[$profile]}
VITYO_IOS_DEPLOYMENT_TARGET=${PROFILE_IOS_TARGET[$profile]}
VITYO_MACOS_DEPLOYMENT_TARGET=${PROFILE_MACOS_TARGET[$profile]}
EOF
}

build_profiles() {
  local profiles_csv=""
  local parallel=0
  local flutter_dir="$FLUTTER_DIR_DEFAULT"
  local out_dir="$OUT_DIR_DEFAULT"
  local work_dir="$WORK_DIR_DEFAULT"
  local mode="debug"
  local simulator=0
  local no_codesign=0
  local -a extra_args=()
  local -a profiles=()
  local -a pids=()
  local -a pid_profiles=()
  local profile i status=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --profiles)
        profiles_csv="$2"
        shift 2
        ;;
      --parallel)
        parallel=1
        shift
        ;;
      --flutter-dir)
        flutter_dir="$2"
        shift 2
        ;;
      --out-dir)
        out_dir="$2"
        shift 2
        ;;
      --work-dir)
        work_dir="$2"
        shift 2
        ;;
      --mode)
        mode="$2"
        shift 2
        ;;
      --simulator)
        simulator=1
        shift
        ;;
      --no-codesign)
        no_codesign=1
        shift
        ;;
      --)
        shift
        extra_args=("$@")
        break
        ;;
      *)
        fail "unknown build option: $1"
        ;;
    esac
  done

  [[ "$mode" == "debug" || "$mode" == "profile" || "$mode" == "release" ]] || fail "unsupported build mode: $mode"
  [[ -d "$flutter_dir" ]] || fail "Flutter directory is missing: $flutter_dir"
  [[ -n "$profiles_csv" ]] || fail "--profiles is required for Apple builds"

  mapfile -t profiles < <(profiles_from_csv "$profiles_csv")
  mkdir -p "$out_dir" "$work_dir"

  if [[ $parallel -eq 0 || ${#profiles[@]} -eq 1 ]]; then
    for profile in "${profiles[@]}"; do
      build_for_profile "$profile" "$flutter_dir" "$out_dir" "$work_dir" "$mode" "$simulator" "$no_codesign" "${extra_args[@]}"
    done
    return
  fi

  for profile in "${profiles[@]}"; do
    local logfile="$out_dir/$profile/build.log"
    mkdir -p "$out_dir/$profile"
    (
      build_for_profile "$profile" "$flutter_dir" "$out_dir" "$work_dir" "$mode" "$simulator" "$no_codesign" "${extra_args[@]}"
    ) >"$logfile" 2>&1 &
    pids+=("$!")
    pid_profiles+=("$profile")
  done

  for i in "${!pids[@]}"; do
    if ! wait "${pids[$i]}"; then
      printf '[apple-platform-profile] parallel build failed for %s; see %s\n' \
        "${pid_profiles[$i]}" "$out_dir/${pid_profiles[$i]}/build.log" >&2
      status=1
    else
      printf '[apple-platform-profile] parallel build completed for %s; log: %s\n' \
        "${pid_profiles[$i]}" "$out_dir/${pid_profiles[$i]}/build.log"
    fi
  done

  [[ $status -eq 0 ]] || exit "$status"
}

main() {
  local command="${1:-}"
  shift || true

  load_profiles

  case "$command" in
    list)
      list_profiles
      ;;
    env)
      print_env "${1:-$(default_profile_for_family ios)}"
      ;;
    run)
      ensure_macos
      [[ $# -gt 0 ]] || fail "run requires a profile"
      run_with_profile "$@"
      ;;
    build)
      ensure_macos
      build_profiles "$@"
      ;;
    -h|--help|help|"")
      usage
      ;;
    *)
      fail "unknown command: $command"
      ;;
  esac
}

main "$@"
