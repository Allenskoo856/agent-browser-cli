#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
version="$(node -p "require('${repo_root}/package.json').version")"
output_dir="${1:-${repo_root}/dist/playwright-offline}"
image="agent-browser-cli-playwright:${version}"
archive="${output_dir}/agent-browser-cli-playwright-${version}-linux-x64.tar.gz"

mkdir -p "${output_dir}"
docker build \
  --platform linux/amd64 \
  --file "${repo_root}/packaging/playwright/Dockerfile" \
  --tag "${image}" \
  "${repo_root}"
docker save "${image}" | gzip -9 >"${archive}"

if command -v sha256sum >/dev/null 2>&1; then
  sha256sum "${archive}" >"${archive}.sha256"
else
  shasum -a 256 "${archive}" >"${archive}.sha256"
fi

echo "${archive}"
