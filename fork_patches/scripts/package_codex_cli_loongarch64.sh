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
BINARIES=${BINARIES:-"codex codex-code-mode-host codex-responses-api-proxy bwrap"}
LLVM_RUNTIME_DIR=${LLVM_RUNTIME_DIR:-"$LLVM_TOOLCHAIN_ROOT/lib/$TARGET"}
ARCHIVE_PATH=${ARCHIVE_PATH:-"$REPO_ROOT/fork_patches/dist/codex-$TARGET-$PROFILE.tar.xz"}
STRIP_MODE=${STRIP_MODE:-auto}
STRIP_BIN=${STRIP_BIN:-"$LLVM_TOOLCHAIN_ROOT/bin/$TARGET-strip"}

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

strip_binary() {
  local binary_path=$1
  local strip_mode=$2

  case "$strip_mode" in
    none)
      return 0
      ;;
    debug)
      "$STRIP_BIN" --strip-debug "$binary_path"
      ;;
    unneeded)
      "$STRIP_BIN" --strip-unneeded "$binary_path"
      ;;
    *)
      echo "unsupported STRIP_MODE: $strip_mode" >&2
      exit 1
      ;;
  esac
}

if [[ -n "${BIN_NAME:-}" && -n "${TARGET_BIN:-}" && "$BINARIES" == "$BIN_NAME" ]]; then
  binaries=("$BIN_NAME")
else
  read -r -a binaries <<< "$BINARIES"
fi
for binary in "${binaries[@]}"; do
  target_bin="$CODEX_RS_DIR/target/$TARGET/$PROFILE/$binary"
  if [[ ! -x "$target_bin" ]]; then
    echo "missing target binary: $target_bin" >&2
    exit 1
  fi
done
if [[ ! -d "$LLVM_RUNTIME_DIR" ]]; then
  echo "missing LLVM runtime dir: $LLVM_RUNTIME_DIR" >&2
  exit 1
fi
if ! command -v "$PATCHELF_BIN" >/dev/null 2>&1; then
  echo "missing patchelf: $PATCHELF_BIN" >&2
  exit 1
fi
if [[ "$STRIP_MODE" == "auto" ]]; then
  if [[ "$PROFILE" == "release" ]]; then
    STRIP_MODE=unneeded
  else
    STRIP_MODE=none
  fi
fi
if [[ "$STRIP_MODE" != "none" && ! -x "$STRIP_BIN" ]]; then
  echo "missing strip tool: $STRIP_BIN" >&2
  exit 1
fi

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR/bin" "$DIST_DIR/codex-resources" "$DIST_DIR/lib"

for binary in "${binaries[@]}"; do
  target_bin="$CODEX_RS_DIR/target/$TARGET/$PROFILE/$binary"
  if [[ "$binary" == "bwrap" ]]; then
    install -m 755 "$target_bin" "$DIST_DIR/codex-resources/bwrap"
  else
    install -m 755 "$target_bin" "$DIST_DIR/bin/$binary"
    strip_binary "$DIST_DIR/bin/$binary" "$STRIP_MODE"
  fi
done
copy_runtime_libs \
  "$LLVM_RUNTIME_DIR" \
  "$DIST_DIR/lib" \
  'libc++.so*' \
  'libc++abi.so*' \
  'libunwind.so*'

for binary in "${binaries[@]}"; do
  if [[ "$binary" == "bwrap" ]]; then
    continue
  fi
  "$PATCHELF_BIN" \
    --set-rpath '$ORIGIN/../lib' \
    "$DIST_DIR/bin/$binary"
done

mkdir -p "$(dirname -- "$ARCHIVE_PATH")"
tar -C "$(dirname -- "$DIST_DIR")" -cJf "$ARCHIVE_PATH" "$(basename -- "$DIST_DIR")"

for binary in "${binaries[@]}"; do
  if [[ "$binary" == "bwrap" ]]; then
    echo "packaged binary: $DIST_DIR/codex-resources/bwrap"
  else
    echo "packaged binary: $DIST_DIR/bin/$binary"
  fi
done
echo "strip mode: $STRIP_MODE"
echo "runtime libs dir: $DIST_DIR/lib"
echo "archive: $ARCHIVE_PATH"
