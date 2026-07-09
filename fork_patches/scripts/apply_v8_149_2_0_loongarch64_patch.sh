#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd)
CODEX_RS_DIR=${CODEX_RS_DIR:-"$REPO_ROOT/codex-rs"}
CARGO_HOME_DIR=${CARGO_HOME:-"$HOME/.cargo"}
PATCH_FILE=${PATCH_FILE:-"$REPO_ROOT/fork_patches/v8-149.2.0-loongarch64-writeflags.patch"}

if [[ ! -f "$PATCH_FILE" ]]; then
  echo "patch file not found: $PATCH_FILE" >&2
  exit 1
fi

cargo fetch --locked --manifest-path "$CODEX_RS_DIR/Cargo.toml" >/dev/null

V8_SRC_DIR=$(find "$CARGO_HOME_DIR/registry/src" -type d -path '*/v8-149.2.0' | head -n 1)
if [[ -z "$V8_SRC_DIR" ]]; then
  echo "could not locate cached v8-149.2.0 source under $CARGO_HOME_DIR/registry/src" >&2
  exit 1
fi

TARGET_FILE="$V8_SRC_DIR/src/string.rs"
if grep -q 'crate::binding::WriteFlags_kNullTerminate' "$TARGET_FILE"; then
  echo "v8-149.2.0 LoongArch64 WriteFlags patch already applied"
  exit 0
fi

patch -d "$V8_SRC_DIR" -N -p1 < "$PATCH_FILE"
echo "applied patch to $V8_SRC_DIR"
