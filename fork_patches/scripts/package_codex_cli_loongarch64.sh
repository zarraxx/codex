#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd)
CODEX_RS_DIR=${CODEX_RS_DIR:-"$REPO_ROOT/codex-rs"}
TARGET=${TARGET:-loongarch64-unknown-linux-gnu}
PROFILE=${PROFILE:-release}
LLVM_TOOLCHAIN_ROOT=${LLVM_TOOLCHAIN_ROOT:-"$HOME/opt/clang-22.1.8-x86_64-unknown-linux-gnu"}
DIST_DIR=${DIST_DIR:-"$REPO_ROOT/fork_patches/dist/codex-$TARGET-$PROFILE"}
PATCHELF_BIN=${PATCHELF_BIN:-patchelf}
BIN_NAME=${BIN_NAME:-codex}
TARGET_BIN=${TARGET_BIN:-"$CODEX_RS_DIR/target/$TARGET/$PROFILE/$BIN_NAME"}
LLVM_RUNTIME_DIR=${LLVM_RUNTIME_DIR:-"$LLVM_TOOLCHAIN_ROOT/lib/$TARGET"}
ARCHIVE_PATH=${ARCHIVE_PATH:-"$REPO_ROOT/fork_patches/dist/codex-$TARGET-$PROFILE.tar.xz"}

copy_runtime_libs() {
  local source_dir=$1
  local dest_dir=$2
  shift 2

  mkdir -p "$dest_dir"
  for pattern in "$@"; do
    find "$dest_dir" -maxdepth 1 -name "$pattern" -exec rm -f {} +
    find "$source_dir" -maxdepth 1 -name "$pattern" -exec cp -aP {} "$dest_dir/" \;
  done
}

if [[ ! -x "$TARGET_BIN" ]]; then
  echo "missing target binary: $TARGET_BIN" >&2
  exit 1
fi
if [[ ! -d "$LLVM_RUNTIME_DIR" ]]; then
  echo "missing LLVM runtime dir: $LLVM_RUNTIME_DIR" >&2
  exit 1
fi
if ! command -v "$PATCHELF_BIN" >/dev/null 2>&1; then
  echo "missing patchelf: $PATCHELF_BIN" >&2
  exit 1
fi

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR/bin" "$DIST_DIR/lib"

install -m 755 "$TARGET_BIN" "$DIST_DIR/bin/$BIN_NAME"
copy_runtime_libs \
  "$LLVM_RUNTIME_DIR" \
  "$DIST_DIR/lib" \
  'libc++.so*' \
  'libc++abi.so*' \
  'libunwind.so*'

"$PATCHELF_BIN" \
  --set-rpath '$ORIGIN/../lib' \
  "$DIST_DIR/bin/$BIN_NAME"

mkdir -p "$(dirname -- "$ARCHIVE_PATH")"
tar -C "$(dirname -- "$DIST_DIR")" -cJf "$ARCHIVE_PATH" "$(basename -- "$DIST_DIR")"

echo "packaged binary: $DIST_DIR/bin/$BIN_NAME"
echo "runtime libs dir: $DIST_DIR/lib"
echo "archive: $ARCHIVE_PATH"
