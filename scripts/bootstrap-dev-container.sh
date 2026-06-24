#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_NAME="${VITYO_DOCKER_IMAGE:-vityo-nightly/dev-env}"
CONTAINER_NAME="${VITYO_DOCKER_CONTAINER:-vityo-nightly-dev}"
ANDROID_PROFILES="${VITYO_ANDROID_PROFILES:-android-35,android-36}"
ANDROID_DEFAULT_PROFILE="${VITYO_ANDROID_DEFAULT_PROFILE:-android-36}"
WITH_ANDROID=0
REBUILD=0
NO_RUN=0
SKIP_WORKSPACE_BOOTSTRAP=0

usage() {
  cat <<'EOF'
Usage: bootstrap-dev-container.sh [options]

Build and launch the standardized Vityo development container.

Options:
  --with-android            Build the Linux + Android combo image
  --android-profiles <csv>  Android SDK profiles to bake into the image
                            Default: android-35,android-36
  --android-default-profile <name>
                            Default Android profile inside the container
                            Default: android-36
  --rebuild                 Force a fresh docker build
  --no-run                  Build the image but do not launch a shell
  --skip-workspace-bootstrap
                            Launch without running bootstrap-workspace.sh
  --image-name <name>       Override docker image name
  --container-name <name>   Override docker container name
  -h, --help                Show this help
EOF
}

log() {
  printf '[Vityo container] %s\n' "$*"
}

fail() {
  printf '[Vityo container] %s\n' "$*" >&2
  exit 1
}

require_docker() {
  command -v docker >/dev/null 2>&1 || fail "docker is required"
}

build_image() {
  local build_args=()
  if [[ $WITH_ANDROID -eq 1 ]]; then
    build_args+=(--build-arg INCLUDE_ANDROID=1)
    build_args+=(--build-arg "ANDROID_PROFILES=$ANDROID_PROFILES")
    build_args+=(--build-arg "ANDROID_DEFAULT_PROFILE=$ANDROID_DEFAULT_PROFILE")
  else
    build_args+=(--build-arg INCLUDE_ANDROID=0)
  fi
  if [[ $REBUILD -eq 1 ]]; then
    build_args+=(--no-cache)
  fi

  log "building image $IMAGE_NAME"
  docker build "${build_args[@]}" -f "$ROOT/docker/dev-env.Dockerfile" -t "$IMAGE_NAME" "$ROOT"
}

run_container() {
  local platforms="web,linux"
  local startup="./scripts/bootstrap-workspace.sh --platforms ${platforms}"
  if [[ $WITH_ANDROID -eq 1 ]]; then
    platforms="web,linux,android"
    startup="./scripts/bootstrap-workspace.sh --platforms ${platforms}"
  fi
  if [[ $SKIP_WORKSPACE_BOOTSTRAP -eq 1 ]]; then
    startup="true"
  fi

  log "launching container $CONTAINER_NAME"
  docker run --rm -it \
    --name "$CONTAINER_NAME" \
    -u "$(id -u):$(id -g)" \
    -e HOME=/tmp/styio-home \
    -e STYIO_EDITOR_URL=http://127.0.0.1:4180/editor \
    -e VITYO_ANDROID_PROFILES="$ANDROID_PROFILES" \
    -e VITYO_ANDROID_DEFAULT_PROFILE="$ANDROID_DEFAULT_PROFILE" \
    -v "$ROOT:/workspace/vityo-nightly" \
    -w /workspace/vityo-nightly \
    -p 4180:4180 \
    "$IMAGE_NAME" \
    bash -lc "mkdir -p \"\$HOME\" && ${startup} && exec bash"
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
      --rebuild)
        REBUILD=1
        shift
        ;;
      --no-run)
        NO_RUN=1
        shift
        ;;
      --skip-workspace-bootstrap)
        SKIP_WORKSPACE_BOOTSTRAP=1
        shift
        ;;
      --image-name)
        IMAGE_NAME="$2"
        shift 2
        ;;
      --container-name)
        CONTAINER_NAME="$2"
        shift 2
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

  require_docker
  build_image
  if [[ $NO_RUN -eq 0 ]]; then
    run_container
  fi
}

main "$@"
