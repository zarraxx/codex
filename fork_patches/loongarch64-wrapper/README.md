# LoongArch64 Codex wrapper

This Node.js launcher installs and updates the LoongArch64 Codex builds
published by `zarraxx/codex`.

It keeps the launcher at `~/.local/bin/codex` and the native bundle at
`~/opt/codex`. On the first interactive launch each day, it compares the
installed version with compatible GitHub Releases and asks before upgrading.

Updates are downloaded to a staging directory, checked against the published
SHA-256 file, test-launched, and atomically moved into place. The previous
native bundle is retained at `~/opt/codex.previous`.

## Install

Node.js 20 or newer is required. On a LoongArch64 Linux system:

```bash
curl -fsSL https://github.com/zarraxx/codex/releases/download/loongarch64-wrapper-v1.0.0/install.sh | bash
```

The installer adds `~/.local/bin` to the front of PATH in the available shell
startup files. Open a new terminal after installation.

## Commands

```bash
codex --wrapper-status
codex --wrapper-update
```

`--wrapper-update` asks before installing a newer native build. The installer
uses `codex --wrapper-update --yes` for unattended initial setup.

Set `CODEX_WRAPPER_SKIP_UPDATE=1` to skip the daily check for one invocation.
