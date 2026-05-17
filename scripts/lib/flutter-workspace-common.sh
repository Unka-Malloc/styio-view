#!/usr/bin/env bash

vityo_trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

vityo_default_java_home() {
  if [[ -n "${JAVA_HOME:-}" ]]; then
    printf '%s\n' "$JAVA_HOME"
    return
  fi

  case "$(uname -s)" in
    Darwin)
      if [[ -x /usr/libexec/java_home ]]; then
        /usr/libexec/java_home 2>/dev/null || true
      fi
      ;;
    Linux)
      if [[ -d /usr/lib/jvm/default-java ]]; then
        printf '%s\n' "/usr/lib/jvm/default-java"
      fi
      ;;
  esac
}

vityo_resolve_flutter_bin() {
  local flutter_bin="${1:-}"
  local flutter_home="${2:-$HOME/develop/flutter}"

  if [[ -n "$flutter_bin" && -x "$flutter_bin" ]]; then
    printf '%s\n' "$flutter_bin"
    return
  fi

  if command -v flutter >/dev/null 2>&1; then
    command -v flutter
    return
  fi

  local derived_bin="$flutter_home/bin/flutter"
  if [[ -x "$derived_bin" ]]; then
    printf '%s\n' "$derived_bin"
    return
  fi

  return 1
}

vityo_copy_flutter_project() {
  local source_dir="$1"
  local dest_root="$2"
  shift 2
  local parent_name project_name
  local -a extra_excludes=("$@")
  local -a tar_args=()

  parent_name="$(dirname "$source_dir")"
  project_name="$(basename "$source_dir")"
  rm -rf "$dest_root"
  mkdir -p "$dest_root"

  tar_args=(
    --exclude="$project_name/build"
    --exclude="$project_name/.dart_tool"
    --exclude="$project_name/ios/Pods"
    --exclude="$project_name/macos/Pods"
    --exclude="$project_name/ios/.symlinks"
    --exclude="$project_name/macos/.symlinks"
  )
  for exclude_path in "${extra_excludes[@]}"; do
    tar_args+=(--exclude="$project_name/$exclude_path")
  done

  (
    cd "$parent_name"
    tar "${tar_args[@]}" -cf - "$project_name"
  ) | (
    cd "$dest_root"
    tar -xf -
  )
}
