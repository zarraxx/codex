#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
BUILD_SCRIPT=$(cd -- "$SCRIPT_DIR/.." && pwd)/build_codex_cli_loongarch64.sh
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

target=loongarch64-unknown-linux-gnu
profile=release
toolchain_root="$TEST_ROOT/llvm"
sysroot="$TEST_ROOT/sysroot"
codex_rs_dir="$TEST_ROOT/codex-rs"
mkdir -p \
  "$toolchain_root/bin" \
  "$toolchain_root/lib/$target" \
  "$sysroot/usr/include/openssl" \
  "$sysroot/usr/include/loongarch64-linux-gnu/openssl" \
  "$sysroot/usr/lib/loongarch64-linux-gnu" \
  "$codex_rs_dir"
: > "$codex_rs_dir/rust-toolchain.toml"
: > "$sysroot/usr/include/openssl/ssl.h"
: > "$sysroot/usr/lib/loongarch64-linux-gnu/libssl.so"
: > "$sysroot/usr/lib/loongarch64-linux-gnu/libcrypto.so"

for tool in \
  loongarch64-unknown-linux-gnu-clang-gcc \
  loongarch64-unknown-linux-gnu-clang-g++ \
  loongarch64-unknown-linux-gnu-ar; do
  printf '#!/bin/sh\nexit 0\n' > "$toolchain_root/bin/$tool"
  chmod +x "$toolchain_root/bin/$tool"
done

cat > "$toolchain_root/bin/loongarch64-unknown-linux-gnu-strip" <<'EOF'
#!/bin/sh
printf 'strip %s\n' "$*" >> "$TEST_EVENT_LOG"
EOF
cat > "$toolchain_root/bin/patchelf" <<'EOF'
#!/bin/sh
printf 'patchelf %s\n' "$*" >> "$TEST_EVENT_LOG"
printf 'rpath=%s\n' "$2" >> "$3"
EOF
cat > "$toolchain_root/bin/rustc" <<'EOF'
#!/bin/sh
printf 'host: x86_64-unknown-linux-gnu\n'
EOF
cat > "$toolchain_root/bin/cargo" <<'EOF'
#!/bin/sh
printf 'cargo %s\n' "$*" >> "$TEST_EVENT_LOG"
case " $* " in
  *' --bin bwrap '*)
    bwrap_path="$CODEX_RS_DIR/target/$TARGET/$PROFILE/bwrap"
    mkdir -p "$(dirname -- "$bwrap_path")"
    printf '#!/bin/sh\nexit 0\n' > "$bwrap_path"
    chmod +x "$bwrap_path"
    ;;
  *)
    printf '%s\n' "$CODEX_BWRAP_SHA256" > "$TEST_RECORDED_DIGEST"
    ;;
esac
EOF
chmod +x "$toolchain_root/bin/"*

TEST_EVENT_LOG="$TEST_ROOT/events.log" \
TEST_RECORDED_DIGEST="$TEST_ROOT/recorded-digest" \
CODEX_RS_DIR="$codex_rs_dir" \
TARGET="$target" \
PROFILE="$profile" \
LLVM_TOOLCHAIN_ROOT="$toolchain_root" \
SYSROOT="$sysroot" \
OPENSSL_SYSROOT="$sysroot" \
PATCHELF_BIN="$toolchain_root/bin/patchelf" \
BINARIES="codex bwrap" \
BUILD_LOG="$TEST_ROOT/build.log" \
  "$BUILD_SCRIPT" >/dev/null

bwrap_path="$codex_rs_dir/target/$target/$profile/bwrap"
expected_patchelf="patchelf --set-rpath \$ORIGIN/../lib $bwrap_path"
grep -Fx -- "$expected_patchelf" "$TEST_ROOT/events.log" >/dev/null || {
  echo "bwrap was not assigned the bundled-library RUNPATH before hashing" >&2
  exit 1
}

expected_digest=$(sha256sum "$bwrap_path" | awk '{print $1}')
recorded_digest=$(cat "$TEST_ROOT/recorded-digest")
if [[ "$recorded_digest" != "$expected_digest" ]]; then
  echo "Codex build did not receive the final patched bwrap digest" >&2
  exit 1
fi
