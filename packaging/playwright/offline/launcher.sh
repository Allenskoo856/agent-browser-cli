#!/usr/bin/env bash

set -Eeuo pipefail

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Run the installed containerized Playwright runtime.

Usage:
  agent-browser-playwright <pw-command> [arguments]
  agent-browser-playwright --container-status
  agent-browser-playwright --container-stop
  agent-browser-playwright --print-container

Examples:
  agent-browser-playwright doctor
  agent-browser-playwright session create --name demo --allow-host app.test.intranet
  agent-browser-playwright open https://app.test.intranet --session demo
  agent-browser-playwright test tests/e2e --cwd /workspace/project

Environment:
  AGENT_BROWSER_PLAYWRIGHT_HOME         Persistent state directory.
  AGENT_BROWSER_PLAYWRIGHT_WORKDIR      Host project directory; default: current directory.
  AGENT_BROWSER_PLAYWRIGHT_NETWORK      Container network; default: bridge.
  AGENT_BROWSER_PLAYWRIGHT_SHM_SIZE     Shared memory size; default: 1g.
  AGENT_BROWSER_PLAYWRIGHT_RUN_ARGS_FILE
                                        Extra container-create arguments, one per line.
  AGENT_BROWSER_PLAYWRIGHT_FORWARD_ENV  Additional env names, comma separated.

E2E_* environment variables are forwarded automatically. A runtime container is
kept per workdir so interactive Playwright sessions survive between commands.
EOF
}

script_path="$(readlink -f -- "${BASH_SOURCE[0]}")"
install_root="$(CDPATH= cd -- "$(dirname -- "${script_path}")/.." && pwd)"
[[ -f "${install_root}/.agent-browser-playwright-install" ]] ||
  fail "installation marker is missing: ${install_root}"
[[ -f "${install_root}/config.env" ]] ||
  fail "installation config is missing: ${install_root}/config.env"
# shellcheck disable=SC1091
source "${install_root}/config.env"

for required_value in CONTAINER_ENGINE IMAGE INSTALL_ID NODE_MODULES_VOLUME; do
  [[ -n "${!required_value:-}" ]] || fail "missing config value: ${required_value}"
done
[[ -x "${CONTAINER_ENGINE}" ]] || fail "container engine is unavailable: ${CONTAINER_ENGINE}"
"${CONTAINER_ENGINE}" info >/dev/null 2>&1 ||
  fail "container engine is not running: ${CONTAINER_ENGINE}"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

host_workdir="${AGENT_BROWSER_PLAYWRIGHT_WORKDIR:-${PWD}}"
[[ -d "${host_workdir}" ]] || fail "workdir does not exist: ${host_workdir}"
host_workdir="$(CDPATH= cd -- "${host_workdir}" && pwd -P)"
data_dir="${AGENT_BROWSER_PLAYWRIGHT_HOME:-${HOME}/.local/share/agent-browser-playwright/data}"
mkdir -p -- "${data_dir}"
data_dir="$(CDPATH= cd -- "${data_dir}" && pwd -P)"

network="${AGENT_BROWSER_PLAYWRIGHT_NETWORK:-bridge}"
shm_size="${AGENT_BROWSER_PLAYWRIGHT_SHM_SIZE:-1g}"
runtime_key="$(
  printf '%s\n%s\n%s\n%s\n' "${IMAGE}" "${host_workdir}" "$(id -u)" "${network}" |
    sha256sum |
    awk '{ print substr($1, 1, 16) }'
)"
container_name="agent-browser-playwright-${runtime_key}"

container_exists() {
  "${CONTAINER_ENGINE}" container inspect "${container_name}" >/dev/null 2>&1
}

container_running() {
  [[ "$("${CONTAINER_ENGINE}" container inspect \
    --format '{{.State.Running}}' "${container_name}" 2>/dev/null)" == "true" ]]
}

stop_container() {
  if container_exists; then
    if container_running; then
      "${CONTAINER_ENGINE}" exec "${container_name}" \
        /usr/bin/node \
        /opt/agent-browser-cli/npm/bin/agent-browser-cli.js \
        stop >/dev/null 2>&1 || true
    fi
    "${CONTAINER_ENGINE}" rm --force "${container_name}" >/dev/null
  fi
}

case "${1:-}" in
  --print-container)
    printf '%s\n' "${container_name}"
    exit 0
    ;;
  --container-status)
    if container_exists; then
      "${CONTAINER_ENGINE}" container inspect \
        --format 'name={{.Name}} status={{.State.Status}} image={{.Config.Image}}' \
        "${container_name}"
    else
      printf 'name=%s status=not-created image=%s\n' "${container_name}" "${IMAGE}"
    fi
    exit 0
    ;;
  --container-stop)
    stop_container
    printf 'Stopped %s\n' "${container_name}"
    exit 0
    ;;
esac

if ! "${CONTAINER_ENGINE}" volume inspect "${NODE_MODULES_VOLUME}" >/dev/null 2>&1; then
  "${CONTAINER_ENGINE}" volume create \
    --label "com.agent-browser-cli.playwright.install=${INSTALL_ID}" \
    "${NODE_MODULES_VOLUME}" >/dev/null
  if ! "${CONTAINER_ENGINE}" run --rm \
    --user 0:0 \
    --volume "${NODE_MODULES_VOLUME}:/target" \
    --entrypoint /bin/sh \
    "${IMAGE}" \
    -c 'cp -a /opt/agent-browser-cli/node_modules/. /target/ && touch /target/.agent-browser-playwright-ready'
  then
    "${CONTAINER_ENGINE}" volume rm "${NODE_MODULES_VOLUME}" >/dev/null 2>&1 || true
    fail "failed to initialize the offline node_modules volume"
  fi
fi

if ! container_exists; then
  run_args=(
    run
    --detach
    --name "${container_name}"
    --init
    --shm-size "${shm_size}"
    --network "${network}"
    --user "$(id -u):$(id -g)"
    --env HOME=/data/home
    --label "com.agent-browser-cli.playwright.install=${INSTALL_ID}"
    --label "com.agent-browser-cli.playwright.workdir=${runtime_key}"
    --volume "${data_dir}:/data/home"
    --volume "${host_workdir}:/workspace/project"
    --volume "${NODE_MODULES_VOLUME}:/workspace/node_modules"
    --workdir /workspace/project
  )

  run_args_file="${AGENT_BROWSER_PLAYWRIGHT_RUN_ARGS_FILE:-}"
  if [[ -n "${run_args_file}" ]]; then
    [[ -f "${run_args_file}" ]] || fail "run args file does not exist: ${run_args_file}"
    while IFS= read -r extra_arg || [[ -n "${extra_arg}" ]]; do
      [[ -n "${extra_arg}" ]] || continue
      run_args+=("${extra_arg}")
    done <"${run_args_file}"
  fi

  "${CONTAINER_ENGINE}" "${run_args[@]}" \
    --entrypoint /bin/sh \
    "${IMAGE}" \
    -c 'trap "exit 0" TERM INT; while :; do sleep 3600 & wait $!; done' \
    >/dev/null
elif ! container_running; then
  "${CONTAINER_ENGINE}" start "${container_name}" >/dev/null
fi

exec_args=(exec --workdir /workspace/project)
while IFS= read -r env_name; do
  case "${env_name}" in
    E2E_*) exec_args+=(--env "${env_name}") ;;
  esac
done < <(compgen -e)

if [[ -n "${AGENT_BROWSER_PLAYWRIGHT_FORWARD_ENV:-}" ]]; then
  IFS=',' read -r -a extra_env_names <<<"${AGENT_BROWSER_PLAYWRIGHT_FORWARD_ENV}"
  for env_name in "${extra_env_names[@]}"; do
    [[ "${env_name}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] ||
      fail "invalid forwarded environment variable name: ${env_name}"
    printenv "${env_name}" >/dev/null ||
      fail "forwarded environment variable is not set: ${env_name}"
    exec_args+=(--env "${env_name}")
  done
fi

if [[ "$#" -eq 0 ]]; then
  set -- doctor
fi

"${CONTAINER_ENGINE}" "${exec_args[@]}" "${container_name}" \
  /usr/bin/node \
  /opt/agent-browser-cli/npm/bin/agent-browser-cli.js \
  pw "$@"
