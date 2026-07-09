#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: smoke_test_codex_cli_loongarch64_container.sh

Environment overrides:
  CONTAINER_ENGINE          docker or podman; auto-detected when unset
  IMAGE                     Container image to use
  TARGET_ARCH               Container architecture for podman
  TARGET_PLATFORM           Container platform for docker
  BUNDLE_DIR                Extracted codex bundle directory
  ARCHIVE_PATH              .tar.xz bundle path to extract when BUNDLE_DIR is unset
  EXTRACT_ROOT              Temporary extraction parent
  APT_PACKAGES              Debian packages to install in the container
  CODEX_ARGS                Arguments passed to bin/codex
EOF
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
  usage
  exit 0
fi

IMAGE=${IMAGE:-ghcr.io/zarraxx/debian:trixie}
TARGET_ARCH=${TARGET_ARCH:-loong64}
TARGET_PLATFORM=${TARGET_PLATFORM:-linux/loong64}
BUNDLE_DIR=${BUNDLE_DIR:-}
ARCHIVE_PATH=${ARCHIVE_PATH:-}
EXTRACT_ROOT=${EXTRACT_ROOT:-}
APT_PACKAGES=${APT_PACKAGES:-ca-certificates libssl3t64}
CODEX_ARGS=${CODEX_ARGS:---version}

if [[ -z "${CONTAINER_ENGINE:-}" ]]; then
  if command -v docker >/dev/null 2>&1; then
    CONTAINER_ENGINE=docker
  elif command -v podman >/dev/null 2>&1; then
    CONTAINER_ENGINE=podman
  else
    echo "missing container engine: need docker or podman" >&2
    exit 1
  fi
fi

if [[ -z "$BUNDLE_DIR" ]]; then
  if [[ -z "$ARCHIVE_PATH" ]]; then
    echo "missing bundle input: set BUNDLE_DIR or ARCHIVE_PATH" >&2
    exit 1
  fi
  if [[ ! -f "$ARCHIVE_PATH" ]]; then
    echo "missing archive: $ARCHIVE_PATH" >&2
    exit 1
  fi

  if [[ -z "$EXTRACT_ROOT" ]]; then
    EXTRACT_ROOT=$(mktemp -d)
    trap 'rm -rf "$EXTRACT_ROOT"' EXIT
  else
    rm -rf "$EXTRACT_ROOT"
    mkdir -p "$EXTRACT_ROOT"
  fi

  tar -C "$EXTRACT_ROOT" -xf "$ARCHIVE_PATH"
  BUNDLE_DIR=$(find "$EXTRACT_ROOT" -mindepth 1 -maxdepth 1 -type d | head -n 1)
fi

if [[ ! -x "$BUNDLE_DIR/bin/codex" ]]; then
  echo "missing codex binary: $BUNDLE_DIR/bin/codex" >&2
  exit 1
fi

container_cmd='apt-get update >/tmp/apt-update.log 2>&1 && apt-get install -y '"$APT_PACKAGES"' >/tmp/apt-install.log 2>&1 && /work/bin/codex '"$CODEX_ARGS"

case "$CONTAINER_ENGINE" in
  docker)
    docker run --rm \
      --platform "$TARGET_PLATFORM" \
      -v "$BUNDLE_DIR:/work:ro" \
      "$IMAGE" \
      sh -lc "$container_cmd"
    ;;
  podman)
    podman run --rm \
      --arch "$TARGET_ARCH" \
      -v "$BUNDLE_DIR:/work:Z,ro" \
      "$IMAGE" \
      sh -lc "$container_cmd"
    ;;
  *)
    echo "unsupported container engine: $CONTAINER_ENGINE" >&2
    exit 1
    ;;
esac
