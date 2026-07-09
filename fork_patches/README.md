This directory contains fork-specific files used to build and maintain
LoongArch64 support without directly modifying upstream repository files.

Current contents:

- `v8-149.2.0-loongarch64-writeflags.patch`
  Fixes the `v8` crate's `WriteFlags` constant names for the generated
  LoongArch64 binding.
- `scripts/apply_v8_149_2_0_loongarch64_patch.sh`
  Applies the patch to the cached `v8-149.2.0` crate source in `CARGO_HOME`.
- `scripts/build_codex_cli_loongarch64.sh`
  Cross-builds `codex-cli` for `loongarch64-unknown-linux-gnu` using the
  fork's current LLVM/sysroot flow.
- `scripts/loongarch64-clang-linker.sh`
  Wraps the LoongArch64 Clang C++ driver so final links use
  `compiler-rt`, `libunwind`, `libc++`, and `libc++abi` instead of `libgcc`.
- `scripts/package_codex_cli_loongarch64.sh`
  Stages the built `codex` binary with its LLVM runtime libraries,
  applies an `rpath` with `patchelf`, strips release binaries by default, and
  emits a `.tar.xz` bundle.
- `scripts/smoke_test_codex_cli_loongarch64_container.sh`
  Launches the packaged `codex` bundle inside
  `ghcr.io/zarraxx/debian:trixie` under LoongArch64 emulation and verifies
  that `codex --version` starts successfully after installing runtime
  packages.
- `scripts/prepare_debian13_loongarch64_sysroot.sh`
  Builds a Debian 13 LoongArch64 sysroot directly from the Loong13 APT
  repositories for use by the cross-build workflow.

The build script assumes:

- a LoongArch64 LLVM toolchain is installed locally
- a Debian 13 `loong64` sysroot is available locally
- the LoongArch64 `rusty_v8` release assets are available via
  `RUSTY_V8_MIRROR`

Override paths with environment variables when needed.

Default local paths:

- `LLVM_TOOLCHAIN_ROOT=$HOME/opt/clang-22.1.8-x86_64-unknown-linux-gnu`
- `SYSROOT=$HOME/opt/debian13-loong64-sysroot`

Examples:

- Debug build:
  `fork_patches/scripts/build_codex_cli_loongarch64.sh`
- Release build:
  `PROFILE=release fork_patches/scripts/build_codex_cli_loongarch64.sh`
- Package a release build:
  `PROFILE=release PATCHELF_BIN=/path/to/patchelf fork_patches/scripts/package_codex_cli_loongarch64.sh`
- Override stripping behavior when packaging:
  `STRIP_MODE=none|debug|unneeded fork_patches/scripts/package_codex_cli_loongarch64.sh`
- Smoke-test a packaged release bundle in the Debian 13 container:
  `ARCHIVE_PATH=/path/to/codex-loongarch64-unknown-linux-gnu-release.tar.xz fork_patches/scripts/smoke_test_codex_cli_loongarch64_container.sh`

Runtime expectation on Debian 13:

- The package bundles `libc++.so.1`, `libc++abi.so.1`, and `libunwind.so.1`
  from LLVM 22.1.8.
- OpenSSL is expected from the target system. On minimal Debian 13 systems,
  install it with:
  `sudo apt update && sudo apt install -y ca-certificates libssl3t64`

Workflow release lane:

- The standalone LoongArch64 GitHub Actions workflow publishes from tags in the
  form `rust-loongarch64-vX.Y.Z`.
- Before publishing, the workflow downloads the packaged archive and boots it
  under QEMU in `ghcr.io/zarraxx/debian:trixie`.
