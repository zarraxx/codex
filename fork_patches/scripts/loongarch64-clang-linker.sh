#!/usr/bin/env bash
set -euo pipefail

clang_driver=${REAL_CLANG_DRIVER:-}
if [[ -z "$clang_driver" ]]; then
  echo "REAL_CLANG_DRIVER is not set" >&2
  exit 1
fi
llvm_runtime_dir=${LLVM_RUNTIME_DIR:-}

filtered_args=()
for arg in "$@"; do
  case "$arg" in
    -lgcc|-lgcc_s)
      ;;
    *)
      filtered_args+=("$arg")
      ;;
  esac
done

extra_args=(-rtlib=compiler-rt -unwindlib=libunwind)
if [[ -n "$llvm_runtime_dir" ]]; then
  extra_args+=(
    "-L$llvm_runtime_dir"
    "-Wl,-rpath-link,$llvm_runtime_dir"
    "-lc++"
    "-lc++abi"
    "-lunwind"
  )
fi

exec "$clang_driver" "${extra_args[@]}" "${filtered_args[@]}"
