#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd)
CODEX_RS_DIR=${CODEX_RS_DIR:-"$REPO_ROOT/codex-rs"}
TARGET=${TARGET:-loongarch64-unknown-linux-gnu}
PROFILE=${PROFILE:-debug}
TOOLCHAIN_KIND=${TOOLCHAIN_KIND:-llvm}
LLVM_TOOLCHAIN_ROOT=${LLVM_TOOLCHAIN_ROOT:-"$HOME/opt/clang-22.1.8-x86_64-unknown-linux-gnu"}
GCC_TOOLCHAIN_ROOT=${GCC_TOOLCHAIN_ROOT:-"$HOME/opt/loongarch64-unknown-linux-gnu-gcc15.2.0"}
SYSROOT=${SYSROOT:-"$HOME/opt/debian13-loong64-sysroot"}
OPENSSL_SYSROOT=${OPENSSL_SYSROOT:-"$SYSROOT"}
OPENSSL_STAGE_DIR=${OPENSSL_STAGE_DIR:-"$CODEX_RS_DIR/target/fork-support/$TARGET/openssl"}
RUSTY_V8_MIRROR=${RUSTY_V8_MIRROR:-https://github.com/zarraxx/rusty_v8/releases/download}
BUILD_LOG=${BUILD_LOG:-"/tmp/codex-loongarch64-cargo-build-$(date -u +%Y%m%dT%H%M%SZ).log"}

LLVM_LINKER_WRAPPER="$REPO_ROOT/fork_patches/scripts/loongarch64-clang-linker.sh"
if [[ "$TOOLCHAIN_KIND" == "llvm" ]]; then
  TOOLCHAIN_ROOT="$LLVM_TOOLCHAIN_ROOT"
  LINKER_BIN="$TOOLCHAIN_ROOT/bin/loongarch64-unknown-linux-gnu-clang-gcc"
  CXX_BIN="$TOOLCHAIN_ROOT/bin/loongarch64-unknown-linux-gnu-clang-g++"
  AR_BIN="$TOOLCHAIN_ROOT/bin/loongarch64-unknown-linux-gnu-ar"
else
  TOOLCHAIN_ROOT="$GCC_TOOLCHAIN_ROOT"
  LINKER_BIN="$TOOLCHAIN_ROOT/bin/loongarch64-unknown-linux-gnu-gcc"
  CXX_BIN="$TOOLCHAIN_ROOT/bin/loongarch64-unknown-linux-gnu-g++"
  AR_BIN="$TOOLCHAIN_ROOT/bin/loongarch64-unknown-linux-gnu-ar"
fi

ACTIVE_SYSROOT=$SYSROOT

if [[ ! -x "$LINKER_BIN" ]]; then
  echo "missing linker: $LINKER_BIN" >&2
  exit 1
fi
if [[ ! -x "$CXX_BIN" ]]; then
  echo "missing C++ compiler: $CXX_BIN" >&2
  exit 1
fi
if [[ ! -x "$AR_BIN" ]]; then
  echo "missing archiver: $AR_BIN" >&2
  exit 1
fi
if [[ ! -d "$ACTIVE_SYSROOT" ]]; then
  echo "missing sysroot: $ACTIVE_SYSROOT" >&2
  exit 1
fi
if [[ ! -d "$OPENSSL_SYSROOT" ]]; then
  echo "missing OpenSSL sysroot: $OPENSSL_SYSROOT" >&2
  exit 1
fi
if [[ "$TOOLCHAIN_KIND" == "llvm" && ! -x "$LLVM_LINKER_WRAPPER" ]]; then
  echo "missing llvm linker wrapper: $LLVM_LINKER_WRAPPER" >&2
  exit 1
fi

mkdir -p "$ACTIVE_SYSROOT/usr/include"
mkdir -p "$OPENSSL_SYSROOT/usr/include/openssl"

if [[ "$TOOLCHAIN_KIND" == "gcc" ]]; then
  mkdir -p "$SYSROOT/usr/include/openssl"
  mkdir -p "$SYSROOT/lib"

  # Debian loong64 packages place the runtime loader and glibc objects under
  # /usr, while the linker scripts in libc.so reference the conventional /lib
  # and /lib64 prefixes. Mirror those prefixes inside the sysroot so cross-link
  # steps can resolve them once --sysroot is enabled.
  ln -sfn ../usr/lib/loongarch64-linux-gnu "$SYSROOT/lib/loongarch64-linux-gnu"
  ln -sfn usr/lib64 "$SYSROOT/lib64"
  ln -sfn loongarch64-linux-gnu/asm "$SYSROOT/usr/include/asm"
  ln -sfn loongarch64-linux-gnu/bits "$SYSROOT/usr/include/bits"
  ln -sfn loongarch64-linux-gnu/gnu "$SYSROOT/usr/include/gnu"
  ln -sfn loongarch64-linux-gnu/sys "$SYSROOT/usr/include/sys"
  ln -sfn ../lib/loongarch64-linux-gnu/Scrt1.o "$SYSROOT/usr/lib64/Scrt1.o"
  ln -sfn ../lib/loongarch64-linux-gnu/crt1.o "$SYSROOT/usr/lib64/crt1.o"
  ln -sfn ../lib/loongarch64-linux-gnu/crti.o "$SYSROOT/usr/lib64/crti.o"
  ln -sfn ../lib/loongarch64-linux-gnu/crtn.o "$SYSROOT/usr/lib64/crtn.o"
fi

if [[ "$TOOLCHAIN_KIND" == "llvm" ]]; then
  mkdir -p "$TOOLCHAIN_ROOT/sysroot"
  mkdir -p "$ACTIVE_SYSROOT/lib" "$ACTIVE_SYSROOT/usr/lib"
  ln -sfn "$ACTIVE_SYSROOT" "$TOOLCHAIN_ROOT/sysroot/$TARGET"
  if [[ ! -e "$ACTIVE_SYSROOT/lib64" ]]; then
    ln -sfn usr/lib64 "$ACTIVE_SYSROOT/lib64"
  fi
  if [[ ! -e "$ACTIVE_SYSROOT/lib/loongarch64-linux-gnu" ]]; then
    ln -sfn ../usr/lib/loongarch64-linux-gnu "$ACTIVE_SYSROOT/lib/loongarch64-linux-gnu"
  fi
  if [[ ! -e "$ACTIVE_SYSROOT/usr/lib/loongarch64-linux-gnu" ]]; then
    ln -sfn ../lib64 "$ACTIVE_SYSROOT/usr/lib/loongarch64-linux-gnu"
  fi
fi

if [[ ! -f "$OPENSSL_SYSROOT/usr/lib/loongarch64-linux-gnu/libssl.so" ]]; then
  echo "missing libssl in OpenSSL sysroot: $OPENSSL_SYSROOT/usr/lib/loongarch64-linux-gnu/libssl.so" >&2
  exit 1
fi
if [[ ! -f "$OPENSSL_SYSROOT/usr/include/openssl/ssl.h" ]]; then
  echo "missing OpenSSL headers in OpenSSL sysroot: $OPENSSL_SYSROOT/usr/include/openssl/ssl.h" >&2
  exit 1
fi

mkdir -p "$OPENSSL_STAGE_DIR/include" "$OPENSSL_STAGE_DIR/lib"
rm -rf "$OPENSSL_STAGE_DIR/include/openssl"
rm -rf "$OPENSSL_STAGE_DIR/include/loongarch64-linux-gnu"
cp -a "$OPENSSL_SYSROOT/usr/include/openssl" "$OPENSSL_STAGE_DIR/include/"
mkdir -p "$OPENSSL_STAGE_DIR/include/loongarch64-linux-gnu"
cp -a "$OPENSSL_SYSROOT/usr/include/loongarch64-linux-gnu/openssl" \
  "$OPENSSL_STAGE_DIR/include/loongarch64-linux-gnu/"
find "$OPENSSL_STAGE_DIR/lib" -maxdepth 1 \
  \( -name 'libcrypto.so*' -o -name 'libssl.so*' \) \
  -exec rm -f {} +
find "$OPENSSL_SYSROOT/usr/lib/loongarch64-linux-gnu" -maxdepth 1 \
  \( -name 'libcrypto.so*' -o -name 'libssl.so*' \) \
  -exec cp -aP {} "$OPENSSL_STAGE_DIR/lib/" \;

HOST_TRIPLE=$(rustc -vV | sed -n 's/^host: //p')
TOOLCHAIN_CHANNEL=$(sed -n 's/^channel = "\(.*\)"/\1/p' "$CODEX_RS_DIR/rust-toolchain.toml" | head -n 1)
if [[ -n "$TOOLCHAIN_CHANNEL" && -n "$HOST_TRIPLE" ]]; then
  rustup target add "$TARGET" --toolchain "${TOOLCHAIN_CHANNEL}-${HOST_TRIPLE}"
fi

export PATH="$TOOLCHAIN_ROOT/bin:$PATH"
if [[ "$TOOLCHAIN_KIND" == "llvm" ]]; then
  export CARGO_TARGET_LOONGARCH64_UNKNOWN_LINUX_GNU_LINKER="$LLVM_LINKER_WRAPPER"
  export REAL_CLANG_DRIVER="$CXX_BIN"
  export LLVM_RUNTIME_DIR="$TOOLCHAIN_ROOT/lib/$TARGET"
  export CC_loongarch64_unknown_linux_gnu=loongarch64-unknown-linux-gnu-clang-gcc
  export CXX_loongarch64_unknown_linux_gnu=loongarch64-unknown-linux-gnu-clang-g++
  export AR_loongarch64_unknown_linux_gnu=loongarch64-unknown-linux-gnu-ar
  export CARGO_TARGET_LOONGARCH64_UNKNOWN_LINUX_GNU_RUSTFLAGS="${CARGO_TARGET_LOONGARCH64_UNKNOWN_LINUX_GNU_RUSTFLAGS:-} -C link-arg=--sysroot=$ACTIVE_SYSROOT -C link-arg=-fuse-ld=lld"
  export CFLAGS_loongarch64_unknown_linux_gnu="${CFLAGS_loongarch64_unknown_linux_gnu:-} --sysroot=$ACTIVE_SYSROOT"
  export CXXFLAGS_loongarch64_unknown_linux_gnu="${CXXFLAGS_loongarch64_unknown_linux_gnu:-} --sysroot=$ACTIVE_SYSROOT"
  export LDFLAGS_loongarch64_unknown_linux_gnu="${LDFLAGS_loongarch64_unknown_linux_gnu:-} --sysroot=$ACTIVE_SYSROOT -fuse-ld=lld"
else
  export CARGO_TARGET_LOONGARCH64_UNKNOWN_LINUX_GNU_LINKER=loongarch64-unknown-linux-gnu-gcc
  export CC_loongarch64_unknown_linux_gnu=loongarch64-unknown-linux-gnu-gcc
  export CXX_loongarch64_unknown_linux_gnu=loongarch64-unknown-linux-gnu-g++
  export AR_loongarch64_unknown_linux_gnu=loongarch64-unknown-linux-gnu-ar
  export CARGO_TARGET_LOONGARCH64_UNKNOWN_LINUX_GNU_RUSTFLAGS="${CARGO_TARGET_LOONGARCH64_UNKNOWN_LINUX_GNU_RUSTFLAGS:-} -C link-arg=--sysroot=$ACTIVE_SYSROOT"
  export CFLAGS_loongarch64_unknown_linux_gnu="${CFLAGS_loongarch64_unknown_linux_gnu:-} --sysroot=$ACTIVE_SYSROOT -I$ACTIVE_SYSROOT/usr/include/loongarch64-linux-gnu"
  export CXXFLAGS_loongarch64_unknown_linux_gnu="${CXXFLAGS_loongarch64_unknown_linux_gnu:-} --sysroot=$ACTIVE_SYSROOT -I$ACTIVE_SYSROOT/usr/include/loongarch64-linux-gnu"
  export LDFLAGS_loongarch64_unknown_linux_gnu="${LDFLAGS_loongarch64_unknown_linux_gnu:-} --sysroot=$ACTIVE_SYSROOT"
fi
export PKG_CONFIG_ALLOW_CROSS=1
export PKG_CONFIG_SYSROOT_DIR="$OPENSSL_SYSROOT"
export PKG_CONFIG_LIBDIR="$OPENSSL_SYSROOT/usr/lib/loongarch64-linux-gnu/pkgconfig:$OPENSSL_SYSROOT/usr/lib/pkgconfig:$OPENSSL_SYSROOT/usr/share/pkgconfig"
export OPENSSL_NO_PKG_CONFIG=1
export RUSTY_V8_MIRROR
export LOONGARCH64_UNKNOWN_LINUX_GNU_OPENSSL_DIR="$OPENSSL_STAGE_DIR"
export LOONGARCH64_UNKNOWN_LINUX_GNU_OPENSSL_LIB_DIR="$OPENSSL_STAGE_DIR/lib"
export LOONGARCH64_UNKNOWN_LINUX_GNU_OPENSSL_INCLUDE_DIR="$OPENSSL_STAGE_DIR/include"

cd "$CODEX_RS_DIR"
cargo_args=(build -p codex-cli --target "$TARGET" -vv)
if [[ "$PROFILE" == "release" ]]; then
  cargo_args+=(--release)
elif [[ "$PROFILE" != "debug" ]]; then
  cargo_args+=(--profile "$PROFILE")
fi

cargo "${cargo_args[@]}" 2>&1 | tee "$BUILD_LOG"

echo "build log: $BUILD_LOG"
echo "expected binary: $CODEX_RS_DIR/target/$TARGET/$PROFILE/codex"
