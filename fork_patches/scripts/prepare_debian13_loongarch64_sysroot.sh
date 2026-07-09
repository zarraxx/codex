#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: prepare_debian13_loongarch64_sysroot.sh [output-dir]

Environment overrides:
  SYSROOT                     Destination directory
  MMDEBSTRAP_BIN             mmdebstrap binary to use
  DEBIAN_SUITE               Debian suite (default: trixie)
  DEBIAN_ARCH                Debian architecture (default: loong64)
  DEBIAN_MAIN_REPO           Main Loong13 APT repository
  DEBIAN_COMPONENTS          APT components list
  DEBIAN_INCLUDE_PACKAGES    Comma-separated packages to install in sysroot
EOF
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
  usage
  exit 0
fi

SYSROOT=${SYSROOT:-${1:-}}
MMDEBSTRAP_BIN=${MMDEBSTRAP_BIN:-mmdebstrap}
DEBIAN_SUITE=${DEBIAN_SUITE:-trixie}
DEBIAN_ARCH=${DEBIAN_ARCH:-loong64}
DEBIAN_MAIN_REPO=${DEBIAN_MAIN_REPO:-https://loong13.debian.net/debian-loong64/}
DEBIAN_COMPONENTS=${DEBIAN_COMPONENTS:-main contrib non-free non-free-firmware}
DEBIAN_INCLUDE_PACKAGES=${DEBIAN_INCLUDE_PACKAGES:-ca-certificates,libc6,libc6-dev,linux-libc-dev,libssl-dev,libssl3t64,zlib1g,zlib1g-dev}

if [[ -z "$SYSROOT" ]]; then
  echo "missing sysroot output directory" >&2
  usage >&2
  exit 1
fi
if ! command -v "$MMDEBSTRAP_BIN" >/dev/null 2>&1; then
  echo "missing mmdebstrap: $MMDEBSTRAP_BIN" >&2
  exit 1
fi

rm -rf "$SYSROOT"
mkdir -p "$SYSROOT"

main_repo="deb [trusted=yes] $DEBIAN_MAIN_REPO $DEBIAN_SUITE $DEBIAN_COMPONENTS"

"$MMDEBSTRAP_BIN" \
  --architectures="$DEBIAN_ARCH" \
  --variant=extract \
  --include="$DEBIAN_INCLUDE_PACKAGES" \
  --aptopt='Acquire::AllowInsecureRepositories "true"' \
  --aptopt='APT::Get::AllowUnauthenticated "true"' \
  "$DEBIAN_SUITE" \
  "$SYSROOT" \
  "$main_repo"

echo "prepared sysroot: $SYSROOT"
