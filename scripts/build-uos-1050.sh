#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

echo "[uos-1050] Installing build dependencies on Debian 10..."

# Debian 10 (buster) is archived; use archive.debian.org
cat > /etc/apt/sources.list <<'EOF'
deb http://archive.debian.org/debian buster main contrib non-free
deb http://archive.debian.org/debian-security buster/updates main contrib non-free
deb http://archive.debian.org/debian buster-updates main contrib non-free
EOF
echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99no-check-valid-until
apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates curl build-essential pkg-config git python3 file binutils xz-utils unzip zip
rm -rf /var/lib/apt/lists/*

echo "[uos-1050] Installing Node.js ${NODE_VERSION}..."
curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz" -o /tmp/node.tar.xz
mkdir -p /usr/local/lib/nodejs
tar -xJf /tmp/node.tar.xz -C /usr/local/lib/nodejs
export PATH="/usr/local/lib/nodejs/node-v${NODE_VERSION}-linux-x64/bin:${PATH}"
node -v
npm -v

echo "[uos-1050] Installing Rust ${RUST_VERSION}..."
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain "${RUST_VERSION}" --profile minimal
export PATH="${HOME}/.cargo/bin:${PATH}"
rustc --version
cargo --version
ldd --version | head -n1

echo "[uos-1050] Building agent-browser-cli native binary..."
cargo build --release --bin agent-browser-cli
BIN="target/release/agent-browser-cli"
test -x "${BIN}"

VERSION="$(node -p "require('./package.json').version")"
OUT_DIR="dist/uos-1050"
mkdir -p "${OUT_DIR}/npm" "${OUT_DIR}/extension"

cp "${BIN}" "${OUT_DIR}/agent-browser-cli"
chmod +x "${OUT_DIR}/agent-browser-cli"

if [ -f scripts/package-platform.mjs ]; then
  node scripts/package-platform.mjs linux-x64 "${BIN}"
  npm pack --pack-destination "${OUT_DIR}/npm" npm/platform/linux-x64
else
  PKG_DIR="npm/platform/linux-x64"
  mkdir -p "${PKG_DIR}/bin"
  cp "${BIN}" "${PKG_DIR}/bin/agent-browser-cli"
  chmod +x "${PKG_DIR}/bin/agent-browser-cli"
  node <<'NODE'
const fs = require('fs');
const root = JSON.parse(fs.readFileSync('package.json', 'utf8'));
const pkg = {
  name: `${root.name}-linux-x64`,
  version: root.version,
  description: `${root.description} (linux-x64, Debian 10 / UOS 1050)`,
  license: root.license,
  repository: root.repository,
  publishConfig: { access: 'public' },
  os: ['linux'],
  cpu: ['x64'],
  files: ['bin']
};
fs.writeFileSync('npm/platform/linux-x64/package.json', JSON.stringify(pkg, null, 2) + '\n');
NODE
  npm pack --pack-destination "${OUT_DIR}/npm" npm/platform/linux-x64
fi

npm pack --pack-destination "${OUT_DIR}/npm" .

if [ -d assets/tmwd_cdp_bridge ]; then
  (cd assets/tmwd_cdp_bridge && zip -r "../../${OUT_DIR}/extension/chrome-extensions.zip" .)
  mkdir -p "${OUT_DIR}/extension/tmwd_cdp_bridge"
  cp -a assets/tmwd_cdp_bridge/. "${OUT_DIR}/extension/tmwd_cdp_bridge/"
fi

{
  echo "project=agent-browser-cli"
  echo "version=${VERSION}"
  echo "git_sha=${GITHUB_SHA:-unknown}"
  echo "target=x86_64-unknown-linux-gnu"
  echo "build_image=debian:10"
  echo "intended_os=UOS 1050 / Debian 10 (glibc 2.28)"
  echo "rustc=$(rustc --version)"
  echo "node=$(node -v)"
  ldd --version | head -n1
  file "${OUT_DIR}/agent-browser-cli"
  echo "GLIBC symbols:"
  strings "${OUT_DIR}/agent-browser-cli" | grep -o 'GLIBC_[0-9.]*' | sort -u || true
} > "${OUT_DIR}/BUILD_INFO.txt"

cat > "${OUT_DIR}/INSTALL_UOS1050.md" <<'EOF'
# UOS 1050 offline install (agent-browser-cli)

Built in debian:10 (glibc 2.28) for UOS 1050.

## Files
- agent-browser-cli
- npm/*agent-browser-cli*.tgz
- npm/*linux-x64*.tgz
- extension/chrome-extensions.zip
- extension/tmwd_cdp_bridge/
- BUILD_INFO.txt

## Install
```bash
# Need Node.js >= 18 first
npm install -g ./npm/*agent-browser-cli*.tgz ./npm/*linux-x64*.tgz
agent-browser-cli --help
```

Standalone:
```bash
sudo cp ./agent-browser-cli /usr/local/bin/agent-browser-cli
sudo chmod +x /usr/local/bin/agent-browser-cli
```

## Chrome extension
1. chrome://extensions
2. enable developer mode
3. load unpacked: extension/tmwd_cdp_bridge
4. open a normal webpage tab
5. agent-browser-cli status && agent-browser-cli doctor && agent-browser-cli tabs

Config: ~/.agent-browser-cli/config.json
Default extension port: 18765
EOF

echo "[uos-1050] Artifacts:"
find "${OUT_DIR}" -type f | sort
cat "${OUT_DIR}/BUILD_INFO.txt"
