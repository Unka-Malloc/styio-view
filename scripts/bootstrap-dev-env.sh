#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
DEBIAN_STANDARD_VERSION="${STYIO_TOOLCHAIN_DEBIAN_STANDARD_VERSION:-13}"
LLVM_STANDARD_SERIES="${STYIO_TOOLCHAIN_LLVM_STANDARD_SERIES:-18.1.x}"
CMAKE_STANDARD_VERSION="${STYIO_TOOLCHAIN_CMAKE_STANDARD_VERSION:-3.31.6}"
PYTHON_STANDARD_VERSION="${STYIO_TOOLCHAIN_PYTHON_STANDARD_VERSION:-$(tr -d '[:space:]' < "$ROOT/.python-version")}"
NODE_STANDARD_VERSION="${STYIO_TOOLCHAIN_NODE_STANDARD_VERSION:-$(tr -d '[:space:]' < "$ROOT/.nvmrc")}"
FLUTTER_STANDARD_VERSION="${STYIO_TOOLCHAIN_FLUTTER_STANDARD_VERSION:-$(tr -d '[:space:]' < "$ROOT/.flutter-version")}"
DART_STANDARD_VERSION="${STYIO_TOOLCHAIN_DART_STANDARD_VERSION:-3.11.5}"
CHROMIUM_STANDARD_VERSION="${STYIO_TOOLCHAIN_CHROMIUM_STANDARD_VERSION:-$(tr -d '[:space:]' < "$ROOT/.chromium-version")}"
ANDROID_CMDLINE_TOOLS_VERSION="${VITYO_ANDROID_CMDLINE_TOOLS_VERSION:-14742923}"
ANDROID_PROFILE_FILE="${VITYO_ANDROID_PROFILE_FILE:-$ROOT/toolchain/android-sdk-profiles.csv}"
ANDROID_PROFILES="${VITYO_ANDROID_PROFILES:-android-35,android-36}"
ANDROID_DEFAULT_PROFILE="${VITYO_ANDROID_DEFAULT_PROFILE:-android-36}"
FLUTTER_HOME="${VITYO_FLUTTER_HOME:-$TARGET_HOME/develop/flutter}"
ANDROID_SDK_ROOT="${VITYO_ANDROID_SDK_ROOT:-$TARGET_HOME/Android/Sdk}"
NODE_INSTALL_ROOT="${VITYO_NODE_INSTALL_ROOT:-/usr/local/lib/nodejs}"
WITH_ANDROID=0
SKIP_WORKSPACE_BOOTSTRAP=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Install the Debian/Ubuntu packages and SDKs required to build, test, and run
Vityo on a fresh Linux host, container, or VM.

Options:
  --with-android            Install the Linux + Android combo toolchain
  --android-profiles <csv>  Android SDK profiles to install (default: $ANDROID_PROFILES)
  --android-default-profile <name>
                            Default Android profile for shell snippets (default: $ANDROID_DEFAULT_PROFILE)
  --skip-workspace-bootstrap
                            Skip repo-local npm/flutter restore and runner bootstrap
  -h, --help                Show this help

Optional environment:
  VITYO_FLUTTER_HOME        Flutter checkout location
                                 Default: $FLUTTER_HOME
  VITYO_ANDROID_SDK_ROOT    Android SDK root
                                 Default: $ANDROID_SDK_ROOT
  VITYO_ANDROID_PROFILE_FILE Android SDK profile csv
                                 Default: $ANDROID_PROFILE_FILE
  VITYO_ANDROID_PROFILES    Android SDK profile set
                                 Default: $ANDROID_PROFILES
  VITYO_ANDROID_DEFAULT_PROFILE
                                 Default profile for shell exports
                                 Default: $ANDROID_DEFAULT_PROFILE

Standardized baseline:
  Debian                  $DEBIAN_STANDARD_VERSION (trixie)
  LLVM / Clang            $LLVM_STANDARD_SERIES via clang-18
  CMake / CTest           $CMAKE_STANDARD_VERSION
  Python                  $PYTHON_STANDARD_VERSION
  Node.js                 v$NODE_STANDARD_VERSION LTS
  Flutter / Dart          $FLUTTER_STANDARD_VERSION / $DART_STANDARD_VERSION
  Chromium                $CHROMIUM_STANDARD_VERSION
EOF
}

log() {
  printf '[Vityo linux env] %s\n' "$*"
}

fail() {
  printf '[Vityo linux env] %s\n' "$*" >&2
  exit 1
}

as_root() {
  if [[ $EUID -eq 0 ]]; then
    "$@"
    return
  fi

  if command -v sudo >/dev/null 2>&1; then
    sudo "$@"
    return
  fi

  fail "sudo is required to install system packages"
}

report_standard_baseline() {
  # shellcheck disable=SC1091
  . /etc/os-release
  if [[ "${ID:-}" == "debian" && "${VERSION_ID:-}" == "$DEBIAN_STANDARD_VERSION" ]]; then
    log "host matches the standardized dev baseline: Debian $DEBIAN_STANDARD_VERSION"
    return
  fi

  log "host is ${PRETTY_NAME:-unknown}; standardized dev baseline is Debian $DEBIAN_STANDARD_VERSION (trixie). Continuing with the compatible Debian/Ubuntu bootstrap path."
}

ensure_debian_like() {
  if [[ ! -r /etc/os-release ]]; then
    fail "/etc/os-release is missing; only Debian/Ubuntu hosts are supported"
  fi

  # shellcheck disable=SC1091
  . /etc/os-release

  local family="${ID_LIKE:-}"
  if [[ "${ID:-}" != "debian" && "${ID:-}" != "ubuntu" && "${family}" != *debian* && "${family}" != *ubuntu* ]]; then
    fail "unsupported distribution: ${PRETTY_NAME:-unknown}. Expected Debian/Ubuntu."
  fi
}

install_system_packages() {
  local packages=(
    build-essential
    ca-certificates
    chromium
    clang-18
    cmake
    curl
    git
    libblkid-dev
    libgtk-3-dev
    liblzma-dev
    mesa-utils
    ninja-build
    pkg-config
    python3
    python3-pip
    python3-venv
    unzip
    wget
    xz-utils
    zip
  )

  if [[ $WITH_ANDROID -eq 1 ]]; then
    packages+=(default-jdk)
  fi

  log "installing system packages"
  as_root apt-get update
  as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${packages[@]}"
}

node_arch() {
  case "$(uname -m)" in
    x86_64|amd64)
      echo "x64"
      ;;
    aarch64|arm64)
      echo "arm64"
      ;;
    *)
      fail "unsupported architecture for official Node.js binaries: $(uname -m)"
      ;;
  esac
}

install_node() {
  local arch version archive url workdir

  if command -v node >/dev/null 2>&1; then
    version="$(node --version 2>/dev/null || true)"
    if [[ "$version" == "v$NODE_STANDARD_VERSION" ]]; then
      log "Node.js already matches standardized version $version"
      return
    fi
  fi

  arch="$(node_arch)"
  archive="node-v${NODE_STANDARD_VERSION}-linux-${arch}.tar.xz"
  url="https://nodejs.org/dist/v${NODE_STANDARD_VERSION}/${archive}"
  workdir="$(mktemp -d)"
  trap 'rm -rf "$workdir"' RETURN

  log "installing official Node.js v$NODE_STANDARD_VERSION into $NODE_INSTALL_ROOT"
  wget -qO "$workdir/$archive" "$url"
  as_root mkdir -p "$NODE_INSTALL_ROOT"
  as_root rm -rf "$NODE_INSTALL_ROOT/node-v${NODE_STANDARD_VERSION}-linux-${arch}"
  as_root tar -xJf "$workdir/$archive" -C "$NODE_INSTALL_ROOT"
  as_root ln -sf "$NODE_INSTALL_ROOT/node-v${NODE_STANDARD_VERSION}-linux-${arch}/bin/node" /usr/local/bin/node
  as_root ln -sf "$NODE_INSTALL_ROOT/node-v${NODE_STANDARD_VERSION}-linux-${arch}/bin/npm" /usr/local/bin/npm
  as_root ln -sf "$NODE_INSTALL_ROOT/node-v${NODE_STANDARD_VERSION}-linux-${arch}/bin/npx" /usr/local/bin/npx
  as_root ln -sf "$NODE_INSTALL_ROOT/node-v${NODE_STANDARD_VERSION}-linux-${arch}/bin/corepack" /usr/local/bin/corepack
}

install_flutter() {
  local current_version=""
  local archive="flutter_linux_${FLUTTER_STANDARD_VERSION}-stable.tar.xz"
  local url="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/${archive}"
  local workdir

  if [[ -r "$FLUTTER_HOME/version" ]]; then
    current_version="$(tr -d '[:space:]' < "$FLUTTER_HOME/version")"
  fi

  if [[ "$current_version" == "$FLUTTER_STANDARD_VERSION" ]]; then
    log "Flutter already matches standardized version $FLUTTER_STANDARD_VERSION"
    return
  fi

  workdir="$(mktemp -d)"
  trap 'rm -rf "$workdir"' RETURN

  log "installing Flutter $FLUTTER_STANDARD_VERSION into $FLUTTER_HOME"
  mkdir -p "$(dirname "$FLUTTER_HOME")"
  rm -rf "$FLUTTER_HOME"
  wget -qO "$workdir/$archive" "$url"
  tar -xJf "$workdir/$archive" -C "$workdir"
  mv "$workdir/flutter" "$FLUTTER_HOME"
  if [[ $EUID -eq 0 && "$TARGET_USER" != "root" ]]; then
    chown -R "$TARGET_USER":"$TARGET_USER" "$FLUTTER_HOME"
  fi
}

android_cmdline_tools_archive() {
  echo "commandlinetools-linux-${ANDROID_CMDLINE_TOOLS_VERSION}_latest.zip"
}

install_android_cmdline_tools() {
  local archive_name
  archive_name="$(android_cmdline_tools_archive)"

  if [[ -x "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" ]]; then
    log "using existing Android command-line tools at $ANDROID_SDK_ROOT"
    return
  fi

  log "installing Android command-line tools into $ANDROID_SDK_ROOT"
  mkdir -p "$ANDROID_SDK_ROOT"

  local workdir
  workdir="$(mktemp -d)"
  trap 'rm -rf "$workdir"' RETURN

  wget -qO "$workdir/$archive_name" "https://dl.google.com/android/repository/$archive_name"
  unzip -q "$workdir/$archive_name" -d "$workdir"

  rm -rf "$ANDROID_SDK_ROOT/cmdline-tools/latest"
  mkdir -p "$ANDROID_SDK_ROOT/cmdline-tools"
  mv "$workdir/cmdline-tools" "$ANDROID_SDK_ROOT/cmdline-tools/latest"
  if [[ $EUID -eq 0 && "$TARGET_USER" != "root" ]]; then
    chown -R "$TARGET_USER":"$TARGET_USER" "$ANDROID_SDK_ROOT"
  fi
}

configure_android_sdk() {
  local flutter_bin="$FLUTTER_HOME/bin/flutter"

  export JAVA_HOME="/usr/lib/jvm/default-java"
  export ANDROID_HOME="$ANDROID_SDK_ROOT"
  export PATH="$FLUTTER_HOME/bin:$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools:$PATH"

  log "configuring Flutter toolchains for Android"
  "$flutter_bin" config --android-sdk "$ANDROID_SDK_ROOT" --enable-web --enable-linux-desktop --enable-android

  log "installing Android SDK profiles: $ANDROID_PROFILES"
  VITYO_ANDROID_PROFILE_FILE="$ANDROID_PROFILE_FILE" \
  VITYO_ANDROID_SDK_ROOT="$ANDROID_SDK_ROOT" \
    "$ROOT/scripts/android-sdk-profile.sh" install --profiles "$ANDROID_PROFILES"

  VITYO_ANDROID_PROFILE_FILE="$ANDROID_PROFILE_FILE" \
  VITYO_ANDROID_SDK_ROOT="$ANDROID_SDK_ROOT" \
    "$ROOT/scripts/android-sdk-profile.sh" env "$ANDROID_DEFAULT_PROFILE" >/dev/null
}

bootstrap_workspace() {
  local workspace_cmd=("$ROOT/scripts/bootstrap-workspace.sh")
  if [[ $WITH_ANDROID -eq 1 ]]; then
    workspace_cmd+=(--platforms "web,linux,android")
  else
    workspace_cmd+=(--platforms "web,linux")
  fi
  log "bootstrapping repo workspace"
  "${workspace_cmd[@]}"
}

verify_tool_versions() {
  local node_version chromium_version flutter_version

  node_version="$(node --version 2>/dev/null || true)"
  chromium_version="$(chromium --product-version 2>/dev/null || true)"
  flutter_version="$("$FLUTTER_HOME/bin/flutter" --version --machine 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["frameworkVersion"])' 2>/dev/null || true)"

  [[ "$node_version" == "v$NODE_STANDARD_VERSION" ]] || fail "Node.js version mismatch: expected v$NODE_STANDARD_VERSION, got ${node_version:-missing}"
  [[ "$chromium_version" == "$CHROMIUM_STANDARD_VERSION" ]] || fail "Chromium version mismatch: expected $CHROMIUM_STANDARD_VERSION, got ${chromium_version:-missing}"
  [[ "$flutter_version" == "$FLUTTER_STANDARD_VERSION" ]] || fail "Flutter version mismatch: expected $FLUTTER_STANDARD_VERSION, got ${flutter_version:-missing}"
}

print_summary() {
  local chrome_bin
  chrome_bin="$(command -v chromium || true)"

  cat <<EOF

Vityo Linux bootstrap complete.

Profile:
  Host combo:     linux$( [[ $WITH_ANDROID -eq 1 ]] && printf '+android' )
  Debian:         $DEBIAN_STANDARD_VERSION (trixie)
  LLVM series:    $LLVM_STANDARD_SERIES
  CMake/CTest:    $CMAKE_STANDARD_VERSION
  Python:         $PYTHON_STANDARD_VERSION
  Node.js:        v$NODE_STANDARD_VERSION
  Flutter/Dart:   $FLUTTER_STANDARD_VERSION / $DART_STANDARD_VERSION
  Chromium:       $CHROMIUM_STANDARD_VERSION
  Android SDKs:   $( [[ $WITH_ANDROID -eq 1 ]] && printf '%s (default: %s)' "$ANDROID_PROFILES" "$ANDROID_DEFAULT_PROFILE" || printf 'not installed' )

Suggested shell exports:
  export FLUTTER_HOME="$FLUTTER_HOME"
  export ANDROID_SDK_ROOT="$ANDROID_SDK_ROOT"
  export ANDROID_HOME="\$ANDROID_SDK_ROOT"
  export JAVA_HOME=/usr/lib/jvm/default-java
  export STYIO_CHROME_PATH="${chrome_bin:-/usr/bin/chromium}"
  export CHROME_EXECUTABLE="\$STYIO_CHROME_PATH"
  export PATH="\$FLUTTER_HOME/bin:\$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:\$ANDROID_SDK_ROOT/platform-tools:\$PATH"

Typical next steps:
  ./scripts/bootstrap-workspace.sh --platforms web,linux$( [[ $WITH_ANDROID -eq 1 ]] && printf ',android' )
  ./scripts/android-sdk-profile.sh list
  eval "\$(./scripts/android-sdk-profile.sh env $ANDROID_DEFAULT_PROFILE)"
  ./scripts/android-sdk-profile.sh build --profiles $ANDROID_PROFILES --parallel --artifact apk --mode debug
  cd "$ROOT/frontend/vityo_app" && "\$FLUTTER_HOME/bin/flutter" analyze
  cd "$ROOT/frontend/vityo_app" && "\$FLUTTER_HOME/bin/flutter" test
  cd "$ROOT/prototype" && STYIO_EDITOR_URL=http://127.0.0.1:4180/editor npm run selftest:editor
EOF
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --with-android)
        WITH_ANDROID=1
        shift
        ;;
      --android-profiles)
        ANDROID_PROFILES="$2"
        shift 2
        ;;
      --android-default-profile)
        ANDROID_DEFAULT_PROFILE="$2"
        shift 2
        ;;
      --skip-workspace-bootstrap)
        SKIP_WORKSPACE_BOOTSTRAP=1
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

  ensure_debian_like
  report_standard_baseline
  install_system_packages
  install_node
  install_flutter
  if [[ $WITH_ANDROID -eq 1 ]]; then
    install_android_cmdline_tools
    configure_android_sdk
  else
    "$FLUTTER_HOME/bin/flutter" config --enable-web --enable-linux-desktop >/dev/null
  fi
  if [[ $SKIP_WORKSPACE_BOOTSTRAP -eq 0 ]]; then
    bootstrap_workspace
  fi
  verify_tool_versions
  print_summary
}

main "$@"
