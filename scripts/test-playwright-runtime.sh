#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cli="${AGENT_BROWSER_CLI_BIN:-${repo_root}/target/debug/agent-browser-cli}"
session="runtime-smoke-$$"
temp_dir="$(mktemp -d)"

cleanup() {
  "${cli}" pw session close "${session}" >/dev/null 2>&1 || true
  rm -rf "${temp_dir}"
}
trap cleanup EXIT

"${cli}" pw doctor
"${cli}" pw session create \
  --name "${session}" \
  --allow-host 127.0.0.1 \
  --trace
"${cli}" pw content "${repo_root}/tests/fixtures/p1.html" --session "${session}"
"${cli}" pw snapshot --session "${session}" >"${temp_dir}/snapshot.json"
grep -q '"ref": "@e1"' "${temp_dir}/snapshot.json"

"${cli}" pw fill @e1 runtime-user --session "${session}"
"${cli}" pw snapshot --session "${session}" >"${temp_dir}/snapshot-after-fill.json"
"${cli}" pw click @e4 --session "${session}"
"${cli}" pw exec \
  'document.querySelector("#username").value + ":" + document.querySelector("#result").textContent' \
  --session "${session}" \
  --allow-raw-javascript >"${temp_dir}/exec.json"
grep -q 'runtime-user:提交完成' "${temp_dir}/exec.json"

"${cli}" pw screenshot \
  --session "${session}" \
  --filename runtime-smoke.png \
  --full-page >"${temp_dir}/screenshot.json"
grep -q '"bytes":' "${temp_dir}/screenshot.json"

if "${cli}" pw open https://example.com --session "${session}" >"${temp_dir}/blocked.json" 2>&1; then
  echo "expected disallowed target to fail" >&2
  exit 1
fi
"${cli}" pw session list >"${temp_dir}/sessions.json"
grep -q "\"name\": \"${session}\"" "${temp_dir}/sessions.json"

"${cli}" pw trace stop \
  --session "${session}" \
  --filename runtime-smoke-trace.zip >"${temp_dir}/trace.json"
grep -q '"bytes":' "${temp_dir}/trace.json"
"${cli}" pw session close "${session}"
