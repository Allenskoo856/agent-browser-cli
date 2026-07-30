#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
version="$(node -p "require('${repo_root}/package.json').version")"
output_dir="${1:-${repo_root}/dist/playwright-offline}"
image="agent-browser-cli-playwright:${version}"
media_name="agent-browser-cli-playwright-v${version}-linux-x64-offline-installer"
archive_name="${media_name}.tar.gz"
build_root="$(mktemp -d)"
media_dir="${build_root}/${media_name}"
image_archive_name="agent-browser-cli-playwright-${version}-linux-x64-image.tar.gz"
image_archive="${media_dir}/payload/${image_archive_name}"

case "${output_dir}" in
  ""|"/"|"${repo_root}")
    echo "refusing unsafe output directory: ${output_dir}" >&2
    exit 1
    ;;
  "${repo_root}"/*)
    ;;
  *)
    echo "output directory must be inside the repository: ${output_dir}" >&2
    exit 1
    ;;
esac

cleanup() {
  rm -rf -- "${build_root}"
}
trap cleanup EXIT

rm -rf -- "${output_dir}"
mkdir -p "${output_dir}" "${media_dir}/payload"

docker build \
  --platform linux/amd64 \
  --file "${repo_root}/packaging/playwright/Dockerfile" \
  --tag "${image}" \
  "${repo_root}"

docker save "${image}" | gzip -6 >"${image_archive}"

install -m 0755 \
  "${repo_root}/packaging/playwright/offline/install.sh" \
  "${media_dir}/install.sh"
install -m 0755 \
  "${repo_root}/packaging/playwright/offline/launcher.sh" \
  "${media_dir}/launcher.sh"
install -m 0755 \
  "${repo_root}/packaging/playwright/offline/uninstall.sh" \
  "${media_dir}/uninstall.sh"
install -m 0644 \
  "${repo_root}/packaging/playwright/offline/README-OFFLINE.md" \
  "${media_dir}/README-OFFLINE.md"

build_time="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
commit_sha="${GITHUB_SHA:-unknown}"
image_id="$(docker image inspect --format '{{.Id}}' "${image}")"
cat >"${media_dir}/BUILD_INFO.txt" <<EOF
project=agent-browser-cli
project_version=${version}
media_format=container-offline-installer-v1
target_os=Linux with Docker or Podman
target_arch=linux-x64
image=${image}
image_id=${image_id}
image_archive=payload/${image_archive_name}
commit=${commit_sha}
built_at=${build_time}
EOF

(
  cd "${media_dir}"
  find . -type f ! -name SHA256SUMS -print0 |
    sort -z |
    xargs -0 sha256sum >SHA256SUMS
)

tar \
  --sort=name \
  --owner=0 \
  --group=0 \
  --numeric-owner \
  -cf - \
  -C "${build_root}" \
  "${media_name}" |
  gzip -1 >"${output_dir}/${archive_name}"

(
  cd "${output_dir}"
  sha256sum "${archive_name}" >"${archive_name}.sha256"
)
cp -a -- "${media_dir}/BUILD_INFO.txt" "${output_dir}/BUILD_INFO.txt"

cat >"${output_dir}/README-FIRST.txt" <<EOF
agent-browser-cli Playwright offline installer ${version}

1. Verify:
   sha256sum -c ${archive_name}.sha256
2. Extract:
   tar -xzf ${archive_name}
3. Install without network access:
   cd ${media_name}
   ./install.sh
4. Verify:
   agent-browser-playwright doctor

Requirements: Linux x86_64 and Docker or Podman.
The installer imports the bundled image; it does not pull from a registry.
EOF

printf 'Offline installer created:\n'
find "${output_dir}" -maxdepth 1 -type f -printf '  %f (%s bytes)\n' | sort
