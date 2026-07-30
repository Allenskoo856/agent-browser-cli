#!/usr/bin/env bash

set -Eeuo pipefail

usage() {
  cat <<'EOF'
Install the containerized agent-browser-cli Playwright runtime without network access.

Usage:
  ./install.sh [--prefix <path>] [--bin-dir <path>] [--engine <command>]
               [--yes] [--skip-smoke]

Options:
  --prefix <path>   Installation metadata directory.
                    root default: /opt/agent-browser-cli-playwright
                    user default: ~/.local/share/agent-browser-cli-playwright
  --bin-dir <path>  Directory for the agent-browser-playwright command.
                    root default: /usr/local/bin
                    user default: ~/.local/bin
  --engine <cmd>    Container engine: auto, docker, podman, or an executable path.
                    Default: auto
  --yes             Skip the confirmation prompt.
  --skip-smoke      Skip offline Chromium launch checks.
  -h, --help        Show this help.

The installer never pulls from a registry. Docker or Podman must already exist.
EOF
}

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

if [[ "${EUID}" -eq 0 ]]; then
  prefix="/opt/agent-browser-cli-playwright"
  bin_dir="/usr/local/bin"
else
  prefix="${HOME}/.local/share/agent-browser-cli-playwright"
  bin_dir="${HOME}/.local/bin"
fi

engine_arg="auto"
assume_yes=false
skip_smoke=false

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --prefix)
      [[ "$#" -ge 2 ]] || fail "--prefix requires a path"
      prefix="$2"
      shift 2
      ;;
    --bin-dir)
      [[ "$#" -ge 2 ]] || fail "--bin-dir requires a path"
      bin_dir="$2"
      shift 2
      ;;
    --engine)
      [[ "$#" -ge 2 ]] || fail "--engine requires a command"
      engine_arg="$2"
      shift 2
      ;;
    --yes)
      assume_yes=true
      shift
      ;;
    --skip-smoke)
      skip_smoke=true
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

[[ "$(uname -s)" == "Linux" ]] || fail "this medium only supports Linux"
case "$(uname -m)" in
  x86_64|amd64) ;;
  *) fail "this medium only supports Linux x86_64" ;;
esac

[[ "${prefix}" = /* ]] || fail "--prefix must be an absolute path"
[[ "${bin_dir}" = /* ]] || fail "--bin-dir must be an absolute path"
case "${prefix}" in
  /|/usr|/usr/local|/opt|/home|/root)
    fail "refusing unsafe installation prefix: ${prefix}"
    ;;
esac

for command_name in \
  awk cp dirname find grep gzip id install ln mkdir mktemp mv readlink rm \
  sha256sum tee touch tr uname
do
  command -v "${command_name}" >/dev/null 2>&1 ||
    fail "required command is missing: ${command_name}"
done

resolve_engine() {
  local requested="$1"
  local candidate
  if [[ "${requested}" == "auto" ]]; then
    for candidate in docker podman; do
      if command -v "${candidate}" >/dev/null 2>&1; then
        command -v "${candidate}"
        return 0
      fi
    done
    return 1
  fi
  if [[ "${requested}" == */* ]]; then
    [[ -x "${requested}" ]] || return 1
    readlink -f -- "${requested}"
  else
    command -v "${requested}"
  fi
}

engine="$(resolve_engine "${engine_arg}")" ||
  fail "Docker or Podman was not found; install a container engine before using this medium"
"${engine}" info >/dev/null 2>&1 ||
  fail "container engine is installed but unavailable: ${engine}"

media_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
[[ -f "${media_dir}/SHA256SUMS" ]] || fail "SHA256SUMS is missing"
[[ -f "${media_dir}/BUILD_INFO.txt" ]] || fail "BUILD_INFO.txt is missing"
[[ -f "${media_dir}/launcher.sh" ]] || fail "launcher.sh is missing"
[[ -f "${media_dir}/uninstall.sh" ]] || fail "uninstall.sh is missing"

image="$(awk -F= '$1 == "image" { print substr($0, index($0, "=") + 1); exit }' \
  "${media_dir}/BUILD_INFO.txt")"
image_archive_rel="$(awk -F= '$1 == "image_archive" { print substr($0, index($0, "=") + 1); exit }' \
  "${media_dir}/BUILD_INFO.txt")"
version="$(awk -F= '$1 == "project_version" { print substr($0, index($0, "=") + 1); exit }' \
  "${media_dir}/BUILD_INFO.txt")"
[[ -n "${image}" ]] || fail "BUILD_INFO.txt does not define image"
[[ -n "${image_archive_rel}" ]] || fail "BUILD_INFO.txt does not define image_archive"
[[ -n "${version}" ]] || fail "BUILD_INFO.txt does not define project_version"
image_archive="${media_dir}/${image_archive_rel}"
[[ -f "${image_archive}" ]] || fail "bundled image archive is missing: ${image_archive_rel}"

printf 'Verifying offline medium checksums...\n'
(
  cd "${media_dir}"
  sha256sum --check --quiet --strict SHA256SUMS
)

command_path="${bin_dir}/agent-browser-playwright"
[[ ! -e "${prefix}" && ! -L "${prefix}" ]] ||
  fail "installation prefix already exists: ${prefix}; uninstall it before reinstalling"
[[ ! -e "${command_path}" && ! -L "${command_path}" ]] ||
  fail "command path already exists: ${command_path}"

printf '\nInstallation plan:\n'
printf '  runtime:     %s\n' "${prefix}"
printf '  command:     %s\n' "${command_path}"
printf '  engine:      %s\n' "${engine}"
printf '  image:       %s\n' "${image}"
printf '  network:     not used during installation\n'

if [[ "${assume_yes}" != true ]]; then
  if [[ ! -t 0 ]]; then
    fail "non-interactive installation requires --yes"
  fi
  read -r -p "Continue? [y/N] " answer
  case "${answer}" in
    y|Y|yes|YES) ;;
    *) printf 'Installation cancelled.\n'; exit 1 ;;
  esac
fi

printf '\nImporting bundled image without registry access...\n'
gzip -dc -- "${image_archive}" | "${engine}" load
"${engine}" image inspect "${image}" >/dev/null

if [[ "${skip_smoke}" != true ]]; then
  smoke_output="$(mktemp)"
  smoke_session="installer-smoke-$$"
  cleanup_smoke() {
    rm -f -- "${smoke_output}"
  }
  trap cleanup_smoke EXIT

  printf 'Checking embedded runtime with network disabled...\n'
  "${engine}" run --rm \
    --network none \
    --shm-size=1g \
    "${image}" \
    pw doctor | tee "${smoke_output}"
  grep -Eq '"chromiumInstalled"[[:space:]]*:[[:space:]]*true' "${smoke_output}" ||
    fail "pw doctor did not confirm the bundled Chromium"

  printf 'Launching headless Chromium with network disabled...\n'
  "${engine}" run --rm \
    --network none \
    --shm-size=1g \
    "${image}" \
    pw session create \
    --name "${smoke_session}" \
    --allow-host 127.0.0.1 >/dev/null

  cleanup_smoke
  trap - EXIT
fi

parent_dir="$(dirname -- "${prefix}")"
stage_dir="${parent_dir}/.agent-browser-cli-playwright.install.$$"
install_id="$(printf '%s' "${prefix}" | sha256sum | awk '{ print substr($1, 1, 16) }')"
volume_version="$(printf '%s' "${version}" | tr -c 'a-zA-Z0-9_.-' '-')"
node_modules_volume="agent-browser-playwright-node-modules-${volume_version}"

cleanup_stage() {
  if [[ -d "${stage_dir}" ]]; then
    rm -rf -- "${stage_dir}"
  fi
}
trap cleanup_stage EXIT

mkdir -p -- "${parent_dir}" "${bin_dir}" "${stage_dir}/bin"
install -m 0755 -- "${media_dir}/launcher.sh" \
  "${stage_dir}/bin/agent-browser-playwright"
install -m 0755 -- "${media_dir}/uninstall.sh" "${stage_dir}/uninstall.sh"
install -m 0644 -- "${media_dir}/README-OFFLINE.md" \
  "${stage_dir}/README-OFFLINE.md"
install -m 0644 -- "${media_dir}/BUILD_INFO.txt" "${stage_dir}/BUILD_INFO.txt"
touch "${stage_dir}/.agent-browser-playwright-install"

{
  printf 'CONTAINER_ENGINE=%q\n' "${engine}"
  printf 'IMAGE=%q\n' "${image}"
  printf 'PROJECT_VERSION=%q\n' "${version}"
  printf 'COMMAND_PATH=%q\n' "${command_path}"
  printf 'INSTALL_ID=%q\n' "${install_id}"
  printf 'NODE_MODULES_VOLUME=%q\n' "${node_modules_volume}"
} >"${stage_dir}/config.env"
chmod 0644 "${stage_dir}/config.env"

mv -- "${stage_dir}" "${prefix}"
ln -s -- "${prefix}/bin/agent-browser-playwright" "${command_path}"
trap - EXIT

printf '\nInstalled successfully.\n'
"${command_path}" doctor
"${command_path}" --container-stop >/dev/null

printf '\nNext steps:\n'
printf '  Run: %s doctor\n' "${command_path}"
printf '  Read: %s/README-OFFLINE.md\n' "${prefix}"
if [[ ":${PATH}:" != *":${bin_dir}:"* ]]; then
  printf '  Add %s to PATH.\n' "${bin_dir}"
fi
