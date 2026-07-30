#!/usr/bin/env bash

set -Eeuo pipefail

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

media_dir="${1:-dist/playwright-offline}"
media_dir="$(CDPATH= cd -- "${media_dir}" && pwd -P)"
archive_path="$(
  find "${media_dir}" -maxdepth 1 -type f \
    -name 'agent-browser-cli-playwright-*-offline-installer.tar.gz' \
    -print -quit
)"
[[ -n "${archive_path}" ]] || fail "offline installer archive was not found"

archive_name="$(basename -- "${archive_path}")"
[[ -f "${archive_path}.sha256" ]] ||
  fail "outer checksum is missing: ${archive_name}.sha256"

printf 'Verifying outer archive checksum...\n'
(
  cd "${media_dir}"
  sha256sum --check --quiet --strict "${archive_name}.sha256"
)

work_dir="$(mktemp -d)"
cleanup() {
  rm -rf -- "${work_dir}"
}
trap cleanup EXIT

tar -xzf "${archive_path}" -C "${work_dir}"
package_dir="$(
  find "${work_dir}" -mindepth 1 -maxdepth 1 -type d \
    -name 'agent-browser-cli-playwright-*-offline-installer' \
    -print -quit
)"
[[ -n "${package_dir}" ]] || fail "installer directory was not found after extraction"

printf 'Verifying installer payload checksums...\n'
(
  cd "${package_dir}"
  sha256sum --check --quiet --strict SHA256SUMS
)

install_root="${work_dir}/installed"
bin_dir="${work_dir}/bin"
test_home="${work_dir}/home"
fixture_dir="${work_dir}/fixture"
mkdir -p "${test_home}" "${fixture_dir}"

printf 'Installing from the medium without registry access...\n'
HOME="${test_home}" "${package_dir}/install.sh" \
  --prefix "${install_root}" \
  --bin-dir "${bin_dir}" \
  --engine docker \
  --yes

launcher="${bin_dir}/agent-browser-playwright"
[[ -x "${launcher}" ]] || fail "installed launcher is missing"

cat >"${fixture_dir}/fixture.html" <<'EOF'
<!doctype html>
<html lang="zh-CN">
  <head>
    <meta charset="utf-8">
    <title>offline installer smoke</title>
  </head>
  <body>
    <label>用户名 <input aria-label="用户名"></label>
    <button type="button">提交</button>
    <p id="result">离线运行成功</p>
  </body>
</html>
EOF

cat >"${fixture_dir}/offline-smoke.spec.mjs" <<'EOF'
import { test, expect } from "@playwright/test";

test("runs bundled Playwright without network", async ({ page }) => {
  await page.setContent(`
    <main>
      <h1>offline Playwright smoke</h1>
      <button type="button">提交</button>
    </main>
  `);
  await expect(
    page.getByRole("heading", { name: "offline Playwright smoke" }),
  ).toBeVisible();
  await expect(page.getByRole("button", { name: "提交" })).toBeEnabled();
});
EOF

printf 'Running persistent Session smoke test with container network disabled...\n'
(
  cd "${fixture_dir}"
  export HOME="${test_home}"
  export AGENT_BROWSER_PLAYWRIGHT_HOME="${test_home}/runtime-data"
  export AGENT_BROWSER_PLAYWRIGHT_NETWORK=none

  "${launcher}" doctor |
    grep -Eq '"chromiumInstalled"[[:space:]]*:[[:space:]]*true'
  "${launcher}" session create \
    --name offline-installer-smoke \
    --allow-host 127.0.0.1 \
    --trace
  "${launcher}" content fixture.html --session offline-installer-smoke
  "${launcher}" snapshot --session offline-installer-smoke |
    grep -q '离线运行成功'
  "${launcher}" session close offline-installer-smoke

  printf 'Running standard Playwright Test from the bundled node_modules...\n'
  "${launcher}" test offline-smoke.spec.mjs \
    --cwd /workspace/project \
    --report-dir /workspace/project/artifacts |
    grep -q '1 passed'

  "${launcher}" --container-stop
)

printf 'Verifying uninstall...\n'
"${install_root}/uninstall.sh" \
  --remove-image \
  --remove-node-modules-volume \
  --yes
[[ ! -e "${install_root}" ]] || fail "installation root still exists after uninstall"
[[ ! -e "${launcher}" ]] || fail "launcher still exists after uninstall"

printf 'Offline installer smoke test passed.\n'
