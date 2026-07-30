#!/usr/bin/env bash

set -Eeuo pipefail

usage() {
  cat <<'EOF'
Uninstall the containerized agent-browser-cli Playwright runtime.

Usage:
  ./uninstall.sh [--remove-image] [--remove-node-modules-volume] [--yes]

Options:
  --remove-image                Also remove the imported OCI image.
  --remove-node-modules-volume  Also remove the cached Playwright node_modules volume.
  --yes                         Skip the confirmation prompt.
  -h, --help                    Show this help.

Per-user test data under ~/.local/share/agent-browser-playwright is preserved.
EOF
}

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

remove_image=false
remove_volume=false
assume_yes=false

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --remove-image)
      remove_image=true
      shift
      ;;
    --remove-node-modules-volume)
      remove_volume=true
      shift
      ;;
    --yes)
      assume_yes=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

script_path="$(readlink -f -- "${BASH_SOURCE[0]}")"
install_root="$(CDPATH= cd -- "$(dirname -- "${script_path}")" && pwd)"
[[ -f "${install_root}/.agent-browser-playwright-install" ]] ||
  fail "refusing to remove an unrecognized directory: ${install_root}"
# shellcheck disable=SC1091
source "${install_root}/config.env"

case "${install_root}" in
  /|/usr|/usr/local|/opt|/home|/root)
    fail "refusing unsafe installation root: ${install_root}"
    ;;
esac

printf 'Uninstall plan:\n'
printf '  runtime metadata: %s\n' "${install_root}"
printf '  command:          %s\n' "${COMMAND_PATH}"
printf '  remove image:     %s\n' "${remove_image}"
printf '  remove volume:    %s\n' "${remove_volume}"
printf '  user test data:   preserved\n'

if [[ "${assume_yes}" != true ]]; then
  if [[ ! -t 0 ]]; then
    fail "non-interactive uninstall requires --yes"
  fi
  read -r -p "Continue? [y/N] " answer
  case "${answer}" in
    y|Y|yes|YES) ;;
    *) printf 'Uninstall cancelled.\n'; exit 1 ;;
  esac
fi

if [[ -x "${CONTAINER_ENGINE}" ]] && "${CONTAINER_ENGINE}" info >/dev/null 2>&1; then
  containers=()
  while IFS= read -r container_id; do
    [[ -n "${container_id}" ]] && containers+=("${container_id}")
  done < <(
    "${CONTAINER_ENGINE}" ps --all --quiet \
      --filter "label=com.agent-browser-cli.playwright.install=${INSTALL_ID}"
  )
  if [[ "${#containers[@]}" -gt 0 ]]; then
    "${CONTAINER_ENGINE}" rm --force "${containers[@]}" >/dev/null
  fi
  if [[ "${remove_volume}" == true ]]; then
    "${CONTAINER_ENGINE}" volume rm "${NODE_MODULES_VOLUME}" >/dev/null 2>&1 || true
  fi
  if [[ "${remove_image}" == true ]]; then
    "${CONTAINER_ENGINE}" image rm "${IMAGE}" >/dev/null 2>&1 || true
  fi
fi

if [[ -L "${COMMAND_PATH}" ]]; then
  command_target="$(readlink -f -- "${COMMAND_PATH}")"
  expected_target="${install_root}/bin/agent-browser-cli"
  if [[ "${command_target}" == "${expected_target}" ]]; then
    rm -- "${COMMAND_PATH}"
  else
    fail "command symlink does not point into this installation: ${COMMAND_PATH}"
  fi
elif [[ -e "${COMMAND_PATH}" ]]; then
  fail "command path is not this installer's symlink: ${COMMAND_PATH}"
fi

rm -rf -- "${install_root}"
printf 'Uninstalled successfully. User test data was preserved.\n'
