#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/lib/flutter-workspace-common.sh"
PROFILE_FILE="${VITYO_ANDROID_PROFILE_FILE:-$ROOT/toolchain/android-sdk-profiles.csv}"
ANDROID_SDK_ROOT="${VITYO_ANDROID_SDK_ROOT:-$HOME/Android/Sdk}"
FLUTTER_HOME="${VITYO_FLUTTER_HOME:-$HOME/develop/flutter}"
FLUTTER_BIN="${VITYO_FLUTTER_BIN:-$FLUTTER_HOME/bin/flutter}"
FLUTTER_DIR_DEFAULT="$ROOT/frontend/vityo_app"
OUT_DIR_DEFAULT="$ROOT/build/android-profile-artifacts"
WORK_DIR_DEFAULT="$ROOT/build/android-profile-workspaces"
ANDROID_PROFILES_DEFAULT="${VITYO_ANDROID_PROFILES:-all}"

declare -A PROFILE_PLATFORM=()
declare -A PROFILE_COMPILE_SDK=()
declare -A PROFILE_TARGET_SDK=()
declare -A PROFILE_MIN_SDK=()
declare -A PROFILE_BUILD_TOOLS=()
declare -A PROFILE_NDK_VERSION=()
declare -a PROFILE_ORDER=()
DEFAULT_PROFILE=""

usage() {
  cat <<'EOF'
Usage: android-sdk-profile.sh <command> [options]

Manage standardized Android SDK profiles for Vityo on Linux/macOS hosts
and containers, and run Android builds against one or more pinned SDK profiles.

Commands:
  list
      Show the supported Android SDK profiles.
  install [--sdk-root <dir>] [--profiles <csv>]
      Install one or more Android SDK profiles into an existing SDK root.
      Profiles default to all entries in toolchain/android-sdk-profiles.csv.
  env [<profile>]
      Print shell exports for the selected profile. Use with:
      eval "$(./scripts/android-sdk-profile.sh env android-35)"
  run [<profile>] -- <command...>
      Run an arbitrary command with the selected profile's Android build env.
  build [options] [-- <extra flutter args>]
      Build the Flutter Android shell against one or more profiles using
      isolated per-profile workspaces so multiple SDK versions can build
      concurrently on the same Linux machine.

Build options:
  --profiles <csv>         Comma-separated profile list or "all"
  --artifact <apk|appbundle>
                           Android artifact type (default: apk)
  --mode <debug|profile|release>
                           Flutter build mode (default: debug)
  --parallel               Build the selected profiles concurrently
  --flutter-dir <dir>      Flutter app directory
  --out-dir <dir>          Artifact output root
  --work-dir <dir>         Isolated workspace root
  --target-platform <csv>  Pass through Flutter --target-platform

Environment:
  VITYO_ANDROID_PROFILE_FILE  Profile csv location
  VITYO_ANDROID_SDK_ROOT      Android SDK root
  VITYO_FLUTTER_HOME          Flutter checkout root
  VITYO_FLUTTER_BIN           Flutter binary override
EOF
}

log() {
  printf '[android-sdk-profile] %s\n' "$*"
}

fail() {
  printf '[android-sdk-profile] %s\n' "$*" >&2
  exit 1
}

load_profiles() {
  local line name platform compile_sdk target_sdk min_sdk build_tools ndk_version default_flag

  [[ -r "$PROFILE_FILE" ]] || fail "Android profile file is missing: $PROFILE_FILE"
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="$(vityo_trim "$line")"
    [[ -n "$line" ]] || continue
    [[ "$line" == \#* ]] && continue
    [[ "$line" == name,* ]] && continue

    IFS=, read -r name platform compile_sdk target_sdk min_sdk build_tools ndk_version default_flag <<<"$line"
    name="$(vityo_trim "$name")"
    platform="$(vityo_trim "$platform")"
    compile_sdk="$(vityo_trim "$compile_sdk")"
    target_sdk="$(vityo_trim "$target_sdk")"
    min_sdk="$(vityo_trim "$min_sdk")"
    build_tools="$(vityo_trim "$build_tools")"
    ndk_version="$(vityo_trim "$ndk_version")"
    default_flag="$(vityo_trim "$default_flag")"

    [[ -n "$name" ]] || continue
    PROFILE_ORDER+=("$name")
    PROFILE_PLATFORM["$name"]="$platform"
    PROFILE_COMPILE_SDK["$name"]="$compile_sdk"
    PROFILE_TARGET_SDK["$name"]="$target_sdk"
    PROFILE_MIN_SDK["$name"]="$min_sdk"
    PROFILE_BUILD_TOOLS["$name"]="$build_tools"
    PROFILE_NDK_VERSION["$name"]="$ndk_version"
    if [[ "$default_flag" == "yes" || "$default_flag" == "true" ]]; then
      DEFAULT_PROFILE="$name"
    fi
  done <"$PROFILE_FILE"

  [[ ${#PROFILE_ORDER[@]} -gt 0 ]] || fail "no Android profiles found in $PROFILE_FILE"
  [[ -n "$DEFAULT_PROFILE" ]] || DEFAULT_PROFILE="${PROFILE_ORDER[-1]}"
}

require_profile() {
  local profile="$1"
  [[ -n "${PROFILE_PLATFORM[$profile]:-}" ]] || fail "unknown Android profile: $profile"
}

profiles_from_csv() {
  local csv="${1:-$ANDROID_PROFILES_DEFAULT}"
  local raw token
  local -a result=()

  if [[ -z "$csv" || "$csv" == "all" ]]; then
    printf '%s\n' "${PROFILE_ORDER[@]}"
    return
  fi

  IFS=, read -r -a raw <<<"$csv"
  for token in "${raw[@]}"; do
    token="$(vityo_trim "$token")"
    [[ -n "$token" ]] || continue
    require_profile "$token"
    result+=("$token")
  done

  [[ ${#result[@]} -gt 0 ]] || fail "no valid Android profiles selected"
  printf '%s\n' "${result[@]}"
}

export_profile_env() {
  local profile="$1"
  require_profile "$profile"

  export VITYO_ANDROID_PROFILE="$profile"
  export VITYO_ANDROID_PLATFORM="${PROFILE_PLATFORM[$profile]}"
  export VITYO_ANDROID_COMPILE_SDK="${PROFILE_COMPILE_SDK[$profile]}"
  export VITYO_ANDROID_TARGET_SDK="${PROFILE_TARGET_SDK[$profile]}"
  export VITYO_ANDROID_MIN_SDK="${PROFILE_MIN_SDK[$profile]}"
  export VITYO_ANDROID_BUILD_TOOLS="${PROFILE_BUILD_TOOLS[$profile]}"
  export VITYO_ANDROID_NDK_VERSION="${PROFILE_NDK_VERSION[$profile]}"
  export ANDROID_SDK_ROOT="$ANDROID_SDK_ROOT"
  export ANDROID_HOME="$ANDROID_SDK_ROOT"
  local java_home
  java_home="$(vityo_default_java_home)"
  if [[ -n "$java_home" ]]; then
    export JAVA_HOME="$java_home"
  fi
  export PATH="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools:$ANDROID_SDK_ROOT/build-tools/${PROFILE_BUILD_TOOLS[$profile]}:$PATH"

  export ORG_GRADLE_PROJECT_vityoAndroidCompileSdk="${PROFILE_COMPILE_SDK[$profile]}"
  export ORG_GRADLE_PROJECT_vityoAndroidTargetSdk="${PROFILE_TARGET_SDK[$profile]}"
  export ORG_GRADLE_PROJECT_vityoAndroidMinSdk="${PROFILE_MIN_SDK[$profile]}"
  export ORG_GRADLE_PROJECT_vityoAndroidBuildToolsVersion="${PROFILE_BUILD_TOOLS[$profile]}"
  export ORG_GRADLE_PROJECT_vityoAndroidNdkVersion="${PROFILE_NDK_VERSION[$profile]}"
  export ORG_GRADLE_PROJECT_vityoAndroidBuildRoot="../../build/${profile}"
}

print_env() {
  local profile="${1:-$DEFAULT_PROFILE}"
  require_profile "$profile"

  cat <<EOF
export VITYO_ANDROID_PROFILE="$profile"
export ANDROID_SDK_ROOT="$ANDROID_SDK_ROOT"
export ANDROID_HOME="\$ANDROID_SDK_ROOT"
export VITYO_ANDROID_PLATFORM="${PROFILE_PLATFORM[$profile]}"
export VITYO_ANDROID_COMPILE_SDK="${PROFILE_COMPILE_SDK[$profile]}"
export VITYO_ANDROID_TARGET_SDK="${PROFILE_TARGET_SDK[$profile]}"
export VITYO_ANDROID_MIN_SDK="${PROFILE_MIN_SDK[$profile]}"
export VITYO_ANDROID_BUILD_TOOLS="${PROFILE_BUILD_TOOLS[$profile]}"
export VITYO_ANDROID_NDK_VERSION="${PROFILE_NDK_VERSION[$profile]}"
export PATH="\$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:\$ANDROID_SDK_ROOT/platform-tools:\$ANDROID_SDK_ROOT/build-tools/${PROFILE_BUILD_TOOLS[$profile]}:\$PATH"
export ORG_GRADLE_PROJECT_vityoAndroidCompileSdk="${PROFILE_COMPILE_SDK[$profile]}"
export ORG_GRADLE_PROJECT_vityoAndroidTargetSdk="${PROFILE_TARGET_SDK[$profile]}"
export ORG_GRADLE_PROJECT_vityoAndroidMinSdk="${PROFILE_MIN_SDK[$profile]}"
export ORG_GRADLE_PROJECT_vityoAndroidBuildToolsVersion="${PROFILE_BUILD_TOOLS[$profile]}"
export ORG_GRADLE_PROJECT_vityoAndroidNdkVersion="${PROFILE_NDK_VERSION[$profile]}"
export ORG_GRADLE_PROJECT_vityoAndroidBuildRoot="../../build/${profile}"
EOF

  local java_home
  java_home="$(vityo_default_java_home)"
  if [[ -n "$java_home" ]]; then
    printf 'export JAVA_HOME="%s"\n' "$java_home"
  fi
}

list_profiles() {
  printf '%-12s %-12s %-12s %-10s %-8s %-12s %s\n' "profile" "platform" "compileSdk" "targetSdk" "minSdk" "buildTools" "default"
  for profile in "${PROFILE_ORDER[@]}"; do
    printf '%-12s %-12s %-12s %-10s %-8s %-12s %s\n' \
      "$profile" \
      "${PROFILE_PLATFORM[$profile]}" \
      "${PROFILE_COMPILE_SDK[$profile]}" \
      "${PROFILE_TARGET_SDK[$profile]}" \
      "${PROFILE_MIN_SDK[$profile]}" \
      "${PROFILE_BUILD_TOOLS[$profile]}" \
      "$([[ "$profile" == "$DEFAULT_PROFILE" ]] && printf 'yes' || printf 'no')"
  done
}

require_sdkmanager() {
  local sdkmanager="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager"
  [[ -x "$sdkmanager" ]] || fail "sdkmanager is missing under $ANDROID_SDK_ROOT. Run ./scripts/bootstrap-dev-env.sh --with-android first."
}

install_profiles() {
  local sdkmanager profile
  local -a profiles=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --sdk-root)
        ANDROID_SDK_ROOT="$2"
        shift 2
        ;;
      --profiles)
        mapfile -t profiles < <(profiles_from_csv "$2")
        shift 2
        ;;
      *)
        require_profile "$1"
        profiles+=("$1")
        shift
        ;;
    esac
  done

  if [[ ${#profiles[@]} -eq 0 ]]; then
    mapfile -t profiles < <(profiles_from_csv "all")
  fi

  require_sdkmanager
  sdkmanager="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager"

  log "accepting Android SDK licenses"
  yes | "$sdkmanager" --sdk_root="$ANDROID_SDK_ROOT" --licenses >/dev/null

  log "installing shared Android SDK packages"
  yes | "$sdkmanager" --sdk_root="$ANDROID_SDK_ROOT" "platform-tools" >/dev/null

  for profile in "${profiles[@]}"; do
    log "installing Android SDK profile $profile"
    yes | "$sdkmanager" --sdk_root="$ANDROID_SDK_ROOT" \
      "platforms;${PROFILE_PLATFORM[$profile]}" \
      "build-tools;${PROFILE_BUILD_TOOLS[$profile]}" \
      "ndk;${PROFILE_NDK_VERSION[$profile]}" >/dev/null
  done
}

run_with_profile() {
  local profile="${1:-$DEFAULT_PROFILE}"
  shift || true
  [[ $# -gt 0 && "$1" == "--" ]] && shift
  [[ $# -gt 0 ]] || fail "run requires a command after --"

  export_profile_env "$profile"
  exec "$@"
}

build_for_profile() {
  local profile="$1"
  local artifact="$2"
  local mode="$3"
  local flutter_dir="$4"
  local out_dir="$5"
  local work_dir="$6"
  local target_platform="$7"
  shift 7
  local -a extra_args=("$@")
  local workspace_root="$work_dir/$profile"
  local app_dir="$workspace_root/$(basename "$flutter_dir")"
  local outputs_root="$out_dir/$profile"
  local cache_dir=".gradle-$profile"
  local -a cmd=()

  require_profile "$profile"
  FLUTTER_BIN="$(vityo_resolve_flutter_bin "$FLUTTER_BIN" "$FLUTTER_HOME")" \
    || fail "flutter is not installed. Set VITYO_FLUTTER_BIN or VITYO_FLUTTER_HOME."
  vityo_copy_flutter_project \
    "$flutter_dir" \
    "$workspace_root" \
    ".gradle" \
    "android/.gradle"

  cmd=("$FLUTTER_BIN" "build" "$artifact" "--$mode" "--android-project-cache-dir" "$cache_dir")
  cmd+=("--android-project-arg" "vityoAndroidProfile=$profile")
  cmd+=("--android-project-arg" "vityoAndroidCompileSdk=${PROFILE_COMPILE_SDK[$profile]}")
  cmd+=("--android-project-arg" "vityoAndroidTargetSdk=${PROFILE_TARGET_SDK[$profile]}")
  cmd+=("--android-project-arg" "vityoAndroidMinSdk=${PROFILE_MIN_SDK[$profile]}")
  cmd+=("--android-project-arg" "vityoAndroidBuildToolsVersion=${PROFILE_BUILD_TOOLS[$profile]}")
  cmd+=("--android-project-arg" "vityoAndroidNdkVersion=${PROFILE_NDK_VERSION[$profile]}")
  cmd+=("--android-project-arg" "vityoAndroidBuildRoot=../../build/${profile}")
  if [[ -n "$target_platform" ]]; then
    cmd+=("--target-platform" "$target_platform")
  fi
  if [[ ${#extra_args[@]} -gt 0 ]]; then
    cmd+=("${extra_args[@]}")
  fi

  log "building $artifact ($mode) for Android profile $profile"
  (
    export_profile_env "$profile"
    cd "$app_dir"
    "${cmd[@]}"
  )

  mkdir -p "$outputs_root"
  rm -rf "$outputs_root/outputs"
  if [[ -d "$app_dir/build/app/outputs" ]]; then
    cp -a "$app_dir/build/app/outputs" "$outputs_root/outputs"
  fi
  cat >"$outputs_root/profile.env" <<EOF
VITYO_ANDROID_PROFILE=$profile
VITYO_ANDROID_PLATFORM=${PROFILE_PLATFORM[$profile]}
VITYO_ANDROID_COMPILE_SDK=${PROFILE_COMPILE_SDK[$profile]}
VITYO_ANDROID_TARGET_SDK=${PROFILE_TARGET_SDK[$profile]}
VITYO_ANDROID_MIN_SDK=${PROFILE_MIN_SDK[$profile]}
VITYO_ANDROID_BUILD_TOOLS=${PROFILE_BUILD_TOOLS[$profile]}
VITYO_ANDROID_NDK_VERSION=${PROFILE_NDK_VERSION[$profile]}
EOF
}

build_profiles() {
  local profiles_csv="$DEFAULT_PROFILE"
  local artifact="apk"
  local mode="debug"
  local parallel=0
  local flutter_dir="$FLUTTER_DIR_DEFAULT"
  local out_dir="$OUT_DIR_DEFAULT"
  local work_dir="$WORK_DIR_DEFAULT"
  local target_platform=""
  local -a extra_args=()
  local -a profiles=()
  local -a pids=()
  local -a pid_profiles=()
  local profile pid i status=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --profiles)
        profiles_csv="$2"
        shift 2
        ;;
      --artifact)
        artifact="$2"
        shift 2
        ;;
      --mode)
        mode="$2"
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
      --target-platform)
        target_platform="$2"
        shift 2
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

  [[ "$artifact" == "apk" || "$artifact" == "appbundle" ]] || fail "unsupported artifact type: $artifact"
  [[ "$mode" == "debug" || "$mode" == "profile" || "$mode" == "release" ]] || fail "unsupported build mode: $mode"
  [[ -d "$flutter_dir" ]] || fail "Flutter directory is missing: $flutter_dir"

  mapfile -t profiles < <(profiles_from_csv "$profiles_csv")
  mkdir -p "$out_dir" "$work_dir"

  if [[ $parallel -eq 0 || ${#profiles[@]} -eq 1 ]]; then
    for profile in "${profiles[@]}"; do
      build_for_profile "$profile" "$artifact" "$mode" "$flutter_dir" "$out_dir" "$work_dir" "$target_platform" "${extra_args[@]}"
    done
    return
  fi

  for profile in "${profiles[@]}"; do
    local logfile="$out_dir/$profile/build.log"
    mkdir -p "$out_dir/$profile"
    (
      build_for_profile "$profile" "$artifact" "$mode" "$flutter_dir" "$out_dir" "$work_dir" "$target_platform" "${extra_args[@]}"
    ) >"$logfile" 2>&1 &
    pid="$!"
    pids+=("$pid")
    pid_profiles+=("$profile")
  done

  for i in "${!pids[@]}"; do
    if ! wait "${pids[$i]}"; then
      printf '[android-sdk-profile] parallel build failed for %s; see %s\n' \
        "${pid_profiles[$i]}" "$out_dir/${pid_profiles[$i]}/build.log" >&2
      status=1
    else
      printf '[android-sdk-profile] parallel build completed for %s; log: %s\n' \
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
    install)
      install_profiles "$@"
      ;;
    env)
      print_env "${1:-$DEFAULT_PROFILE}"
      ;;
    run)
      if [[ $# -gt 0 && "$1" != "--" ]]; then
        run_with_profile "$1" "${@:2}"
      else
        run_with_profile "$DEFAULT_PROFILE" "$@"
      fi
      ;;
    build)
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
