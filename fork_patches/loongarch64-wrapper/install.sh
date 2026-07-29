#!/usr/bin/env bash
set -euo pipefail

repository="zarraxx/codex"
wrapper_release_tag="loongarch64-wrapper-v1.0.0"
wrapper_asset="codex-wrapper.js"
wrapper_checksum_asset="${wrapper_asset}.sha256"
release_base_url="https://github.com/${repository}/releases/download/${wrapper_release_tag}"
wrapper_bin_dir="${HOME}/.local/bin"
wrapper_path="${wrapper_bin_dir}/codex"
wrapper_backup_path="${wrapper_bin_dir}/codex.previous-wrapper"
wrapper_stage_path="${wrapper_bin_dir}/.codex-wrapper.new.$$"

fail() {
  printf 'codex wrapper install: %s\n' "$*" >&2
  exit 1
}

for command_name in curl install node sha256sum tar; do
  command -v "${command_name}" >/dev/null 2>&1 || fail "missing required command: ${command_name}"
done

case "$(uname -s)" in
  Linux) ;;
  *) fail "only Linux is supported" ;;
esac

case "$(uname -m)" in
  loongarch64|loong64) ;;
  *) fail "only LoongArch64 is supported" ;;
esac

node_arch="$(node -p 'process.arch')"
node_major="$(node -p 'Number(process.versions.node.split(".")[0])')"
[[ "${node_arch}" == "loong64" ]] || fail "the installed Node.js does not target LoongArch64"
(( node_major >= 20 )) || fail "Node.js 20 or newer is required"

install_tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/codex-wrapper-install.XXXXXXXX")"
cleanup() {
  rm -rf -- "${install_tmp_dir}"
  rm -f -- "${wrapper_stage_path}"
}
trap cleanup EXIT

printf 'Downloading Codex wrapper %s...\n' "${wrapper_release_tag}"
curl -fL --retry 3 --connect-timeout 10 \
  "${release_base_url}/${wrapper_asset}" \
  -o "${install_tmp_dir}/${wrapper_asset}"
curl -fL --retry 3 --connect-timeout 10 \
  "${release_base_url}/${wrapper_checksum_asset}" \
  -o "${install_tmp_dir}/${wrapper_checksum_asset}"

(
  cd "${install_tmp_dir}"
  sha256sum --check "${wrapper_checksum_asset}"
)
node --check "${install_tmp_dir}/${wrapper_asset}"

mkdir -p "${wrapper_bin_dir}"
if [[ -e "${wrapper_path}" || -L "${wrapper_path}" ]]; then
  cp -p -- "${wrapper_path}" "${wrapper_backup_path}"
fi
install -m 0755 "${install_tmp_dir}/${wrapper_asset}" "${wrapper_stage_path}"
mv -f -- "${wrapper_stage_path}" "${wrapper_path}"

path_marker="# >>> zarraxx codex wrapper >>>"
ensure_path_config() {
  local config_path="$1"
  [[ -f "${config_path}" ]] || touch "${config_path}"
  if grep -Fq "${path_marker}" "${config_path}"; then
    return
  fi
  cat >> "${config_path}" <<'EOF'

# >>> zarraxx codex wrapper >>>
if [ -d "$HOME/.local/bin" ] ; then
    case "$PATH" in
        "$HOME/.local/bin"|"$HOME/.local/bin":*) ;;
        *) PATH="$HOME/.local/bin:$PATH" ;;
    esac
fi
export PATH
# <<< zarraxx codex wrapper <<<
EOF
}

ensure_path_config "${HOME}/.profile"
if [[ "${SHELL:-}" == */bash || -f "${HOME}/.bashrc" ]]; then
  ensure_path_config "${HOME}/.bashrc"
fi
if [[ "${SHELL:-}" == */zsh || -f "${HOME}/.zshrc" ]]; then
  ensure_path_config "${HOME}/.zshrc"
fi

printf 'Installing or updating the LoongArch64 Codex binary...\n'
"${wrapper_path}" --wrapper-update --yes

printf '\nInstalled: %s\n' "${wrapper_path}"
printf 'Open a new terminal, or run:\n'
printf '  export PATH="%s:$PATH"\n' "${wrapper_bin_dir}"
printf '  hash -r\n'
printf '\nCheck status with: codex --wrapper-status\n'
