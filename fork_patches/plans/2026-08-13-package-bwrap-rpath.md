# Package bwrap RPATH Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the packaged LoongArch64 `codex-resources/bwrap` resolve the LLVM runtime libraries bundled in the archive.

**Architecture:** Keep the existing archive layout. Finalize `bwrap` with `$ORIGIN/../lib` before calculating the digest compiled into Codex, then copy that exact file into `codex-resources/bwrap` during packaging.

**Tech Stack:** Bash, patchelf, GitHub Actions

---

### Task 1: Cover bwrap RUNPATH finalization

**Files:**
- Create: `fork_patches/scripts/tests/build_codex_cli_loongarch64_test.sh`
- Modify: `fork_patches/scripts/build_codex_cli_loongarch64.sh`

- [ ] Add a shell regression test with temporary fake build, sysroot, and LLVM toolchain trees.
- [ ] Run the test and verify that it fails because `bwrap` is not passed to `patchelf` before hashing.
- [ ] Finalize `bwrap` with `$ORIGIN/../lib` after stripping and before calculating `CODEX_BWRAP_SHA256`.
- [ ] Run the regression test and shell syntax checks.
- [ ] Package the downloaded CI artifact with the corrected script and verify `bwrap` reports `RUNPATH=$ORIGIN/../lib`.

### Task 2: Publish and run CI

**Files:**
- Modify: `fork_patches/scripts/build_codex_cli_loongarch64.sh`
- Create: `fork_patches/scripts/tests/build_codex_cli_loongarch64_test.sh`

- [ ] Review the focused diff and commit it.
- [ ] Push `main` to the fork.
- [ ] Dispatch `loongarch64-release.yml` for `rust-v0.147.0` with release publishing enabled.
- [ ] Monitor the workflow through build, smoke test, and publication.
