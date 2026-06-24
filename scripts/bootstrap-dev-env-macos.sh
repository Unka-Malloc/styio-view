#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_HOME="${HOME}"
PYTHON_STANDARD_VERSION="${STYIO_TOOLCHAIN_PYTHON_STANDARD_VERSION:-$(tr -d '[:space:]' < "$ROOT/.python-version")}"
NODE_STANDARD_VERSION="${STYIO_TOOLCHAIN_NODE_STANDARD_VERSION:-$(tr -d '[:space:]' < "$ROOT/.nvmrc")}"
FLUTTER_STANDARD_VERSION="${STYIO_TOOLCHAIN_FLUTTER_STANDARD_VERSION:-$(tr -d '[:space:]' < "$ROOT/.flutter-version")}"
DART_STANDARD_VERSION="${STYIO_TOOLCHAIN_DART_STANDARD_VERSION:-3.11.5}"
CHROMIUM_STANDARD_VERSION="${STYIO_TOOLCHAIN_CHROMIUM_STANDARD_VERSION:-$(tr -d '[:space:]' < "$ROOT/.chromium-version")}"
CMAKE_STANDARD_VERSION="${STYIO_TOOLCHAIN_CMAKE_STANDARD_VERSION:-3.31.6}"
ANDROID_CMDLINE_TOOLS_VERSION="${VITYO_ANDROID_CMDLINE_TOOLS_VERSION:-14742923}"
ANDROID_PROFILE_FILE="${VITYO_ANDROID_PROFILE_FILE:-$ROOT/toolchain/android-sdk-profiles.csv}"
ANDROID_PROFILES="${VITYO_ANDROID_PROFILES:-android-35,android-36}"
ANDROID_DEFAULT_PROFILE="${VITYO_ANDROID_DEFAULT_PROFILE:-android-36}"
APPLE_PROFILE_FILE="${VITYO_APPLE_PROFILE_FILE:-$ROOT/toolchain/apple-platform-profiles.csv}"
FLUTTER_HOME="${VITYO_FLUTTER_HOME:-$TARGET_HOME/develop/flutter}"
ANDROID_SDK_ROOT="${VITYO_ANDROID_SDK_ROOT:-$TARGET_HOME/Library/Android/sdk}"
NODE_INSTALL_ROOT="${VITYO_NODE_INSTALL_ROOT:-$TARGET_HOME/.local/Vityo/nodejs}"
BROWSER_HOME="${VITYO_BROWSER_HOME:-$TARGET_HOME/Library/Application Support/Vityo/browser}"
TOOL_VENV="${VITYO_TOOL_VENV:-$TARGET_HOME/.local/venvs/Vityo-tools}"
WITH_ANDROID=0
WITH_IOS=0
SKIP_WORKSPACE_BOOTSTRAP=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Install the Vityo macOS developer environment. Base profile is macOS
desktop + web. Optional mobile combos can be added with flags.

Options:
  --with-ios                Install the macOS + iOS combo prerequisites
  --with-android            Install the macOS + Android combo prerequisites
  --android-profiles <csv>  Android SDK profiles to install (default: $ANDROID_PROFILES)
  --android-default-profile <name>
                            Default Android profile for shell snippets (default: $ANDROID_DEFAULT_PROFILE)
  --skip-workspace-bootstrap
                            Skip repo-local npm/flutter restore and runner bootstrap
  -h, --help                Show this help
EOF
}

log() {
  printf '[Vityo macOS env] %s\n' "$*"
}

fail() {
  printf '[Vityo macOS env] %s\n' "$*" >&2
  exit 1
}

ensure_macos() {
  [[ "$(uname -s)" == "Darwin" ]] || fail "this script only supports macOS"
}

ensure_homebrew() {
  if command -v brew >/dev/null 2>&1; then
    return
  fi

  log "installing Homebrew"
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
}

eval_brew_shellenv() {
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  else
    fail "brew was not found after installation"
  fi
}

mac_arch() {
  case "$(uname -m)" in
    arm64)
      echo "arm64"
      ;;
    x86_64)
      echo "x64"
      ;;
    *)
      fail "unsupported macOS architecture: $(uname -m)"
      ;;
  esac
}

install_python() {
  local current version workdir archive url
  current="$(python3 --version 2>/dev/null | awk '{print $2}' || true)"
  if [[ "$current" == "$PYTHON_STANDARD_VERSION" ]]; then
    log "Python already matches standardized version $current"
    return
  fi

  workdir="$(mktemp -d)"
  trap 'rm -rf "$workdir"' RETURN
  archive="python-${PYTHON_STANDARD_VERSION}-macos11.pkg"
  url="https://www.python.org/ftp/python/${PYTHON_STANDARD_VERSION}/${archive}"
  log "installing Python $PYTHON_STANDARD_VERSION"
  curl -fsSL "$url" -o "$workdir/$archive"
  sudo installer -pkg "$workdir/$archive" -target /
}

install_tooling_venv() {
  log "installing standardized CMake/CTest into $TOOL_VENV"
  python3 -m venv "$TOOL_VENV"
  "$TOOL_VENV/bin/python" -m pip install --upgrade pip
  "$TOOL_VENV/bin/python" -m pip install "cmake==$CMAKE_STANDARD_VERSION"
}

install_brew_packages() {
  local packages=(git llvm@18 openjdk@21)
  if [[ $WITH_IOS -eq 1 ]]; then
    packages+=(cocoapods mas)
  fi
  log "installing Homebrew packages: ${packages[*]}"
  brew install "${packages[@]}"
}

install_node() {
  local arch archive url workdir node_root
  arch="$(mac_arch)"
  node_root="$NODE_INSTALL_ROOT/node-v${NODE_STANDARD_VERSION}-darwin-${arch}"
  if [[ -x "$node_root/bin/node" ]] && [[ "$("$node_root/bin/node" --version)" == "v$NODE_STANDARD_VERSION" ]]; then
    log "Node.js already matches standardized version v$NODE_STANDARD_VERSION"
    return
  fi

  workdir="$(mktemp -d)"
  trap 'rm -rf "$workdir"' RETURN
  archive="node-v${NODE_STANDARD_VERSION}-darwin-${arch}.tar.gz"
  url="https://nodejs.org/dist/v${NODE_STANDARD_VERSION}/${archive}"
  log "installing official Node.js v$NODE_STANDARD_VERSION"
  mkdir -p "$NODE_INSTALL_ROOT"
  curl -fsSL "$url" -o "$workdir/$archive"
  tar -xzf "$workdir/$archive" -C "$NODE_INSTALL_ROOT"
}

flutter_archive_name() {
  case "$(mac_arch)" in
    arm64)
      echo "flutter_macos_arm64_${FLUTTER_STANDARD_VERSION}-stable.zip"
      ;;
    x64)
      echo "flutter_macos_${FLUTTER_STANDARD_VERSION}-stable.zip"
      ;;
  esac
}

install_flutter() {
  local current archive url workdir
  current="$(tr -d '[:space:]' < "$FLUTTER_HOME/version" 2>/dev/null || true)"
  if [[ "$current" == "$FLUTTER_STANDARD_VERSION" ]]; then
    log "Flutter already matches standardized version $FLUTTER_STANDARD_VERSION"
    return
  fi

  archive="$(flutter_archive_name)"
  url="https://storage.googleapis.com/flutter_infra_release/releases/stable/macos/${archive}"
  workdir="$(mktemp -d)"
  trap 'rm -rf "$workdir"' RETURN

  log "installing Flutter $FLUTTER_STANDARD_VERSION"
  mkdir -p "$(dirname "$FLUTTER_HOME")"
  rm -rf "$FLUTTER_HOME"
  curl -fsSL "$url" -o "$workdir/$archive"
  unzip -q "$workdir/$archive" -d "$workdir"
  mv "$workdir/flutter" "$FLUTTER_HOME"
}

browser_archive_name() {
  case "$(mac_arch)" in
    arm64)
      echo "chrome-mac-arm64.zip"
      ;;
    x64)
      echo "chrome-mac-x64.zip"
      ;;
  esac
}

browser_binary_path() {
  case "$(mac_arch)" in
    arm64)
      printf '%s\n' "$BROWSER_HOME/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing"
      ;;
    x64)
      printf '%s\n' "$BROWSER_HOME/chrome-mac-x64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing"
      ;;
  esac
}

install_managed_browser() {
  local browser_bin archive url workdir
  browser_bin="$(browser_binary_path)"
  if [[ -x "$browser_bin" ]] && "$browser_bin" --version | grep -F "$CHROMIUM_STANDARD_VERSION" >/dev/null 2>&1; then
    log "managed browser already matches standardized version $CHROMIUM_STANDARD_VERSION"
    return
  fi

  archive="$(browser_archive_name)"
  url="https://storage.googleapis.com/chrome-for-testing-public/${CHROMIUM_STANDARD_VERSION}/$( [[ $(mac_arch) == arm64 ]] && printf 'mac-arm64' || printf 'mac-x64' )/${archive}"
  workdir="$(mktemp -d)"
  trap 'rm -rf "$workdir"' RETURN

  log "installing managed browser runtime $CHROMIUM_STANDARD_VERSION"
  mkdir -p "$BROWSER_HOME"
  rm -rf "$BROWSER_HOME/chrome-mac-arm64" "$BROWSER_HOME/chrome-mac-x64"
  curl -fsSL "$url" -o "$workdir/$archive"
  unzip -q "$workdir/$archive" -d "$BROWSER_HOME"
}

android_archive_name() {
  echo "commandlinetools-mac-${ANDROID_CMDLINE_TOOLS_VERSION}_latest.zip"
}

install_android_sdk() {
  local archive url workdir java_home
  archive="$(android_archive_name)"
  java_home="$(brew --prefix openjdk@21)/libexec/openjdk.jdk/Contents/Home"

  if [[ ! -x "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" ]]; then
    log "installing Android command-line tools"
    workdir="$(mktemp -d)"
    trap 'rm -rf "$workdir"' RETURN
    url="https://dl.google.com/android/repository/${archive}"
    mkdir -p "$ANDROID_SDK_ROOT"
    curl -fsSL "$url" -o "$workdir/$archive"
    unzip -q "$workdir/$archive" -d "$workdir"
    rm -rf "$ANDROID_SDK_ROOT/cmdline-tools/latest"
    mkdir -p "$ANDROID_SDK_ROOT/cmdline-tools"
    mv "$workdir/cmdline-tools" "$ANDROID_SDK_ROOT/cmdline-tools/latest"
  fi

  export JAVA_HOME="$java_home"
  export ANDROID_HOME="$ANDROID_SDK_ROOT"
  export PATH="$TOOL_VENV/bin:$NODE_INSTALL_ROOT/node-v${NODE_STANDARD_VERSION}-darwin-$(mac_arch)/bin:$FLUTTER_HOME/bin:$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools:$PATH"

  log "configuring Flutter Android support"
  "$FLUTTER_HOME/bin/flutter" config --android-sdk "$ANDROID_SDK_ROOT" --enable-web --enable-macos-desktop --enable-ios --enable-android

  log "installing Android SDK profiles: $ANDROID_PROFILES"
  VITYO_ANDROID_PROFILE_FILE="$ANDROID_PROFILE_FILE" \
  VITYO_ANDROID_SDK_ROOT="$ANDROID_SDK_ROOT" \
    "$ROOT/scripts/android-sdk-profile.sh" install --profiles "$ANDROID_PROFILES"
}

ensure_ios_toolchain() {
  local developer_dir="/Applications/Xcode.app/Contents/Developer"

  if ! xcode-select -p >/dev/null 2>&1; then
    log "requesting Xcode command line tools"
    xcode-select --install || true
    fail "Xcode command line tools are not ready yet. Complete the installation, then rerun with --with-ios."
  fi

  if [[ ! -d "$developer_dir" ]]; then
    if [[ "${VITYO_AUTO_INSTALL_XCODE:-0}" == "1" ]] && command -v mas >/dev/null 2>&1; then
      log "attempting Xcode installation via App Store"
      mas install 497799835
    fi
  fi

  [[ -d "$developer_dir" ]] || fail "iOS support requires /Applications/Xcode.app. Install Xcode, then rerun with --with-ios."

  sudo xcode-select -s "$developer_dir" || true
  sudo xcodebuild -license accept || true
  "$FLUTTER_HOME/bin/flutter" config --enable-ios --enable-macos-desktop >/dev/null
}

bootstrap_workspace() {
  local platforms="web,macos"
  [[ $WITH_IOS -eq 1 ]] && platforms="$platforms,ios"
  [[ $WITH_ANDROID -eq 1 ]] && platforms="$platforms,android"
  VITYO_FLUTTER_HOME="$FLUTTER_HOME" "$ROOT/scripts/bootstrap-workspace.sh" --platforms "$platforms"
}

print_summary() {
  local browser_bin node_bin java_home platforms
  browser_bin="$(browser_binary_path)"
  node_bin="$NODE_INSTALL_ROOT/node-v${NODE_STANDARD_VERSION}-darwin-$(mac_arch)/bin"
  java_home="$(brew --prefix openjdk@21)/libexec/openjdk.jdk/Contents/Home"
  platforms="web,macos"
  [[ $WITH_IOS -eq 1 ]] && platforms="$platforms,ios"
  [[ $WITH_ANDROID -eq 1 ]] && platforms="$platforms,android"

  cat <<EOF

Vityo macOS bootstrap complete.

Profile:
  Host combo:     macos$( [[ $WITH_IOS -eq 1 ]] && printf '+ios' )$( [[ $WITH_ANDROID -eq 1 ]] && printf '+android' )
  Python:         $PYTHON_STANDARD_VERSION
  Node.js:        v$NODE_STANDARD_VERSION
  Flutter/Dart:   $FLUTTER_STANDARD_VERSION / $DART_STANDARD_VERSION
  Browser runtime:$CHROMIUM_STANDARD_VERSION
  Android SDKs:   $( [[ $WITH_ANDROID -eq 1 ]] && printf '%s (default: %s)' "$ANDROID_PROFILES" "$ANDROID_DEFAULT_PROFILE" || printf 'not installed' )
  Apple profiles: $APPLE_PROFILE_FILE

Suggested shell exports:
  export FLUTTER_HOME="$FLUTTER_HOME"
  export STYIO_CHROME_PATH="$browser_bin"
  export CHROME_EXECUTABLE="\$STYIO_CHROME_PATH"
  export ANDROID_SDK_ROOT="$ANDROID_SDK_ROOT"
  export ANDROID_HOME="\$ANDROID_SDK_ROOT"
  export JAVA_HOME="$java_home"
  export PATH="$TOOL_VENV/bin:$node_bin:\$FLUTTER_HOME/bin:\$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:\$ANDROID_SDK_ROOT/platform-tools:\$PATH"

Typical next steps:
  ./scripts/bootstrap-workspace.sh --platforms $platforms
  ./scripts/android-sdk-profile.sh list
  ./scripts/apple-platform-profile.sh list
  eval "\$(./scripts/android-sdk-profile.sh env $ANDROID_DEFAULT_PROFILE)"
  eval "\$(./scripts/apple-platform-profile.sh env ios-13)"
  ./scripts/android-sdk-profile.sh build --profiles $ANDROID_PROFILES --parallel --artifact apk --mode debug
  ./scripts/apple-platform-profile.sh build --profiles ios-13,ios-15 --parallel --mode debug --simulator --no-codesign
  ./scripts/apple-platform-profile.sh build --profiles macos-10.15,macos-12 --parallel --mode debug
  cd "$ROOT/frontend/vityo_app" && "\$FLUTTER_HOME/bin/flutter" analyze
  cd "$ROOT/frontend/vityo_app" && "\$FLUTTER_HOME/bin/flutter" test
  cd "$ROOT/prototype" && STYIO_CHROME_PATH="$browser_bin" STYIO_EDITOR_URL=http://127.0.0.1:4180/editor npm run selftest:editor
EOF
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --with-ios)
        WITH_IOS=1
        shift
        ;;
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

  ensure_macos
  ensure_homebrew
  eval_brew_shellenv
  install_python
  install_tooling_venv
  install_brew_packages
  install_node
  install_flutter
  install_managed_browser

  if [[ $WITH_IOS -eq 1 ]]; then
    ensure_ios_toolchain
  else
    "$FLUTTER_HOME/bin/flutter" config --enable-web --enable-macos-desktop >/dev/null
  fi

  if [[ $WITH_ANDROID -eq 1 ]]; then
    install_android_sdk
  fi

  if [[ $SKIP_WORKSPACE_BOOTSTRAP -eq 0 ]]; then
    bootstrap_workspace
  fi

  print_summary
}

main "$@"
