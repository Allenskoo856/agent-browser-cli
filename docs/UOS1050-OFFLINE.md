# UOS 1050 Offline Install (agent-browser-cli)

This repository includes a GitHub Actions workflow that builds **linux-x64** binaries inside **Debian 10 (glibc 2.28)** for **UOS 1050**.

- Workflow: `.github/workflows/build-uos-1050.yml`
- Build script: `scripts/build-uos-1050.sh`
- Trigger: Actions → `build-uos-1050` → Run workflow

Successful artifacts are named like:

- `agent-browser-cli-uos-1050-linux-x64`

## Download media from GitHub Actions

1. Open the latest successful `build-uos-1050` run
2. Download the artifact zip
3. Also download Node.js offline runtime (recommended):

```bash
curl -LO https://nodejs.org/dist/v20.19.3/node-v20.19.3-linux-x64.tar.xz
```

## Install on UOS 1050 (x86_64)

### A. Fast path with standalone binary

```bash
# from extracted artifact
sudo cp ./agent-browser-cli /usr/local/bin/agent-browser-cli
sudo chmod +x /usr/local/bin/agent-browser-cli
agent-browser-cli --help
```

### B. npm offline install

```bash
# install Node >= required version first
export PATH=/opt/node/bin:$PATH
npm install -g ./npm/*agent-browser-cli*.tgz + npm/*linux-x64*.tgz
agent-browser-cli --help
```

### C. Config

```bash
mkdir -p $(dirname ~/.agent-browser-cli/config.json)
# edit real connection settings
vi ~/.agent-browser-cli/config.json
```

Node requirement: **>= 18 (kit uses Node 20)**

## Project notes

- Command: `agent-browser-cli`
- Config: `~/.agent-browser-cli/config.json`
- Requires Chrome/Chromium extension: `extension/tmwd_cdp_bridge`
- Default ports: extension WS `18765`, CLI HTTP `18767`
- Skill: `agent-browser-cli install-skill --yes` or copy offline kit skill
- OpenCode skill path: `~/.config/opencode/skills/agent-browser-cli/SKILL.md`


## OpenCode configuration

```bash
# install skill into common agents directory
mkdir -p ~/.agents/skills ~/.config/opencode/skills

# copy skill from offline kit / repo skill files
# then link for OpenCode
ln -sfn ~/.agents/skills/agent-browser-cli ~/.config/opencode/skills/agent-browser-cli

# ensure CLI is on PATH
export PATH=/opt/node/bin:/usr/local/bin:$PATH

# OpenCode config
mkdir -p ~/.config/opencode
cat > ~/.config/opencode/opencode.json <<'EOF'
{
  "$schema": "https://opencode.ai/config.json",
  "permission": {
    "bash": "allow"
  }
}
EOF
```

Restart OpenCode after installing skills.

## Full offline kit guide

If you have the combined offline kit (`offline-media` / `uos1050-offline-kit.tar.gz`), use:

- `README-UOS1050-OFFLINE.md`
- `install-all.sh`

That kit installs all three CLIs + Node + OpenCode skills together.

## Compatibility check

Artifact `BUILD_INFO.txt` should contain:

- `build_image=debian:10`
- `intended_os=UOS 1050 / Debian 10 (glibc 2.28)`
- GLIBC symbols up to `GLIBC_2.28` only

---

# Full Combined Offline Guide

# UOS 1050 内网离线部署完整指南

适用系统：统信 UOS 1050 / Debian 10 系（glibc 2.28）x86_64  
适用项目：

- agent-ssh-cli `0.3.9`
- agent-database-cli `0.2.24`
- agent-browser-cli `0.3.6`

本介质内的 Linux 二进制已在 **Debian 10（glibc 2.28）** 下重新编译，兼容 UOS 1050。

---

## 0. 介质包结构

建议把整个 `offline-media` 目录拷到 U 盘，结构如下：

```text
offline-media/
├── README-UOS1050-OFFLINE.md          # 本指南
├── runtime/
│   └── node-v20.19.3-linux-x64.tar.xz # Node.js 运行时（离线）
├── agent-ssh-cli/
│   ├── agentsshcli-native
│   ├── npm/
│   │   ├── agent-ssh-cli-0.3.9.tgz
│   │   └── agent-ssh-cli-linux-x64-0.3.9.tgz
│   ├── BUILD_INFO.txt
│   └── INSTALL_UOS1050.md
├── agent-database-cli/
│   ├── agent-database-cli
│   ├── npm/
│   │   ├── agent-database-cli-0.2.24.tgz
│   │   └── agent-database-cli-linux-x64-0.2.24.tgz
│   ├── BUILD_INFO.txt
│   └── INSTALL_UOS1050.md
├── agent-browser-cli/
│   ├── agent-browser-cli
│   ├── npm/
│   │   ├── sleepinsummer-agent-browser-cli-0.3.6.tgz
│   │   └── sleepinsummer-agent-browser-cli-linux-x64-0.3.6.tgz
│   ├── extension/
│   │   ├── chrome-extensions.zip
│   │   └── tmwd_cdp_bridge/
│   ├── BUILD_INFO.txt
│   └── INSTALL_UOS1050.md
├── skills/
│   ├── agent-ssh-cli/SKILL.md
│   ├── agent-database-cli/SKILL.md
│   └── agent-browser-cli/SKILL.md
└── config-examples/
    ├── agent-ssh-cli.config.json
    ├── agent-database-cli.config.example.json
    └── agent-browser-cli.config.json
```

---

## 1. 外网电脑：介质从哪里下载

### 1.1 推荐：直接使用本仓库已整理好的 offline-media

如果你手上已经有本目录：

```text
/Users/allen/Documents/微服务日志/uos-builds/offline-media
```

直接整包拷贝到 U 盘即可。

### 1.2 外网重新下载（GitHub Actions Artifact）

成功构建页：

1. agent-ssh-cli  
   https://github.com/Allenskoo856/agent-ssh-cli/actions/runs/29679196876
2. agent-database-cli  
   https://github.com/Allenskoo856/agent-database-cli/actions/runs/29679197859
3. agent-browser-cli  
   https://github.com/Allenskoo856/agent-browser-cli/actions/runs/29679198921

在每个页面底部 `Artifacts` 下载：

- `agent-ssh-cli-uos-1050-linux-x64`
- `agent-database-cli-uos-1050-linux-x64`
- `agent-browser-cli-uos-1050-linux-x64`

仓库主页：

- https://github.com/Allenskoo856/agent-ssh-cli
- https://github.com/Allenskoo856/agent-database-cli
- https://github.com/Allenskoo856/agent-browser-cli

分支：`main` 或 `codex/uos-1050-build`  
Workflow：`build-uos-1050`

### 1.3 外网额外下载 Node 运行时

```bash
# 推荐 Node 20，三个项目都能覆盖（database 要求 >=20）
curl -LO https://nodejs.org/dist/v20.19.3/node-v20.19.3-linux-x64.tar.xz
```

### 1.4 可选：Skill 与示例配置

若你没有 offline-media 整包，可从 fork 仓库下载：

```bash
# skill
# agent-ssh-cli/SKILL.md
# agent-database-cli/skills/agent-database-cli/SKILL.md
# agent-browser-cli/skills/agent-browser-cli/**

# 示例配置
# agent-ssh-cli/example.config.json
# agent-database-cli/config/docker-test.json
```

### 1.5 打成 U 盘包

```bash
# 外网电脑
mkdir -p uos1050-offline-kit/{runtime,skills,config-examples}
# 放入 node tar.xz
# 解压三个 artifact zip 到 agent-ssh-cli / agent-database-cli / agent-browser-cli
# 放入 skills 与 config-examples
tar -czf uos1050-offline-kit.tar.gz uos1050-offline-kit
```

---

## 2. 内网 UOS 1050 安装前检查

```bash
uname -m
# 必须 x86_64

ldd --version | head -n1
# 期望 glibc 2.28 左右

# 磁盘建议预留 >= 500MB
df -h ~
```

架构说明：

- 本介质只支持 **x86_64**
- 不支持 龙芯 / 申威 / arm64

---

## 3. 内网：安装 Node.js（离线）

```bash
# 假设 U 盘挂载到 /media/usb，或你把包拷到 ~/uos1050-offline-kit
cd ~/uos1050-offline-kit   # 或 offline-media 实际路径

sudo mkdir -p /opt/node
sudo tar -xJf runtime/node-v20.19.3-linux-x64.tar.xz -C /opt/node --strip-components=1

# 系统级 PATH
echo 'export PATH=/opt/node/bin:$PATH' | sudo tee /etc/profile.d/node.sh
source /etc/profile.d/node.sh

# 或用户级
# echo 'export PATH=/opt/node/bin:$PATH' >> ~/.bashrc
# source ~/.bashrc

node -v   # v20.19.3
npm -v    # 10.x
```

---

## 4. 安装三个 CLI（推荐 npm 离线安装）

### 4.1 agent-ssh-cli

```bash
cd ~/uos1050-offline-kit/agent-ssh-cli

npm install -g ./npm/agent-ssh-cli-0.3.9.tgz ./npm/agent-ssh-cli-linux-x64-0.3.9.tgz
agentsshcli --help
```

无 npm 时也可：

```bash
sudo cp ./agentsshcli-native /usr/local/bin/agentsshcli
sudo chmod +x /usr/local/bin/agentsshcli
agentsshcli --help
```

配置：

```bash
mkdir -p ~/.agent-ssh-cli
cp ../config-examples/agent-ssh-cli.config.json ~/.agent-ssh-cli/config.json
vi ~/.agent-ssh-cli/config.json
```

最小配置示例：

```json
[
  {
    "name": "内网服务器",
    "host": "10.0.0.10",
    "port": 22,
    "username": "root",
    "password": "你的密码"
  }
]
```

验证：

```bash
agentsshcli list
agentsshcli exec --no-cache 内网服务器 "pwd"
```

### 4.2 agent-database-cli

```bash
cd ~/uos1050-offline-kit/agent-database-cli

npm install -g ./npm/agent-database-cli-0.2.24.tgz ./npm/agent-database-cli-linux-x64-0.2.24.tgz
agent-database-cli --help
```

或：

```bash
sudo cp ./agent-database-cli /usr/local/bin/agent-database-cli
sudo chmod +x /usr/local/bin/agent-database-cli
```

配置：

```bash
mkdir -p ~/.agent-database-cli
cp ../config-examples/agent-database-cli.config.example.json ~/.agent-database-cli/config.json
vi ~/.agent-database-cli/config.json
```

最小配置示例：

```json
{
  "databases": {
    "local-mysql": {
      "type": "mysql",
      "url": "mysql://user:password@10.0.0.20:3306/app",
      "readonly": true,
      "blacklist": ["drop", "truncate", "delete"],
      "keepAliveSeconds": 180
    }
  }
}
```

验证：

```bash
agent-database-cli list
agent-database-cli test --db local-mysql
```

注意：

- MySQL / PostgreSQL / Redis / MongoDB：无需额外客户端
- Oracle 默认 SQLcl：需额外准备 SQLcl + Java 21
- Oracle 原生驱动：需 Oracle Instant Client

### 4.3 agent-browser-cli

```bash
cd ~/uos1050-offline-kit/agent-browser-cli

npm install -g \
  ./npm/sleepinsummer-agent-browser-cli-0.3.6.tgz \
  ./npm/sleepinsummer-agent-browser-cli-linux-x64-0.3.6.tgz

agent-browser-cli --help
```

或：

```bash
sudo cp ./agent-browser-cli /usr/local/bin/agent-browser-cli
sudo chmod +x /usr/local/bin/agent-browser-cli
```

配置：

```bash
mkdir -p ~/.agent-browser-cli
cp ../config-examples/agent-browser-cli.config.json ~/.agent-browser-cli/config.json
```

加载 Chrome 扩展（必须）：

1. 打开 Chrome：`chrome://extensions`
2. 打开“开发者模式”
3. “加载已解压的扩展程序”
4. 选择：

```text
~/uos1050-offline-kit/agent-browser-cli/extension/tmwd_cdp_bridge
```

5. 至少打开一个普通网页标签（不要只停在 `chrome://` / `about:blank`）

验证：

```bash
agent-browser-cli status
agent-browser-cli doctor
agent-browser-cli tabs
agent-browser-cli open https://www.baidu.com
```

默认端口：

- 扩展 WebSocket：`18765`
- CLI HTTP：`18767`

改端口：

```bash
agent-browser-cli set-extension-port 18766
```

---

## 5. 一键安装脚本（内网）

把下面保存为 `install-all.sh`，放在 offline-media 根目录执行：

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
export PATH="/opt/node/bin:${PATH}"

if ! command -v node >/dev/null 2>&1; then
  echo "[1/5] 安装 Node.js 20..."
  sudo mkdir -p /opt/node
  sudo tar -xJf "$ROOT/runtime/node-v20.19.3-linux-x64.tar.xz" -C /opt/node --strip-components=1
  echo 'export PATH=/opt/node/bin:$PATH' | sudo tee /etc/profile.d/node.sh >/dev/null
  export PATH="/opt/node/bin:$PATH"
fi

echo "Node: $(node -v)  npm: $(npm -v)"

echo "[2/5] 安装 agent-ssh-cli..."
npm install -g \
  "$ROOT/agent-ssh-cli/npm/agent-ssh-cli-0.3.9.tgz" \
  "$ROOT/agent-ssh-cli/npm/agent-ssh-cli-linux-x64-0.3.9.tgz"

echo "[3/5] 安装 agent-database-cli..."
npm install -g \
  "$ROOT/agent-database-cli/npm/agent-database-cli-0.2.24.tgz" \
  "$ROOT/agent-database-cli/npm/agent-database-cli-linux-x64-0.2.24.tgz"

echo "[4/5] 安装 agent-browser-cli..."
npm install -g \
  "$ROOT/agent-browser-cli/npm/sleepinsummer-agent-browser-cli-0.3.6.tgz" \
  "$ROOT/agent-browser-cli/npm/sleepinsummer-agent-browser-cli-linux-x64-0.3.6.tgz"

echo "[5/5] 初始化配置与 skill..."
mkdir -p ~/.agent-ssh-cli ~/.agent-database-cli ~/.agent-browser-cli
mkdir -p ~/.agents/skills ~/.config/opencode/skills

[[ -f ~/.agent-ssh-cli/config.json ]] || \
  cp "$ROOT/config-examples/agent-ssh-cli.config.json" ~/.agent-ssh-cli/config.json
[[ -f ~/.agent-database-cli/config.json ]] || \
  cp "$ROOT/config-examples/agent-database-cli.config.example.json" ~/.agent-database-cli/config.json
[[ -f ~/.agent-browser-cli/config.json ]] || \
  cp "$ROOT/config-examples/agent-browser-cli.config.json" ~/.agent-browser-cli/config.json

# skill 实体目录
cp -a "$ROOT/skills/agent-ssh-cli" ~/.agents/skills/
cp -a "$ROOT/skills/agent-database-cli" ~/.agents/skills/
cp -a "$ROOT/skills/agent-browser-cli" ~/.agents/skills/

# OpenCode skill 软链
ln -sfn ~/.agents/skills/agent-ssh-cli ~/.config/opencode/skills/agent-ssh-cli
ln -sfn ~/.agents/skills/agent-database-cli ~/.config/opencode/skills/agent-database-cli
ln -sfn ~/.agents/skills/agent-browser-cli ~/.config/opencode/skills/agent-browser-cli

# 兼容 codex/claude 等
mkdir -p ~/.codex/skills ~/.claude/skills
ln -sfn ~/.agents/skills/agent-ssh-cli ~/.codex/skills/agent-ssh-cli
ln -sfn ~/.agents/skills/agent-database-cli ~/.codex/skills/agent-database-cli
ln -sfn ~/.agents/skills/agent-browser-cli ~/.codex/skills/agent-browser-cli
ln -sfn ~/.agents/skills/agent-ssh-cli ~/.claude/skills/agent-ssh-cli
ln -sfn ~/.agents/skills/agent-database-cli ~/.claude/skills/agent-database-cli
ln -sfn ~/.agents/skills/agent-browser-cli ~/.claude/skills/agent-browser-cli

echo "验证 CLI..."
agentsshcli --help >/dev/null
agent-database-cli --help >/dev/null
agent-browser-cli --help >/dev/null

echo "安装完成。"
echo "请编辑："
echo "  ~/.agent-ssh-cli/config.json"
echo "  ~/.agent-database-cli/config.json"
echo "  ~/.agent-browser-cli/config.json"
echo "browser 还需手动加载扩展目录："
echo "  $ROOT/agent-browser-cli/extension/tmwd_cdp_bridge"
```

执行：

```bash
chmod +x install-all.sh
./install-all.sh
```

---

## 6. OpenCode 配置（内网）

OpenCode 读取 skill 的常用路径是：

```text
~/.config/opencode/skills/<skill-name>/SKILL.md
```

同时兼容社区通用目录：

```text
~/.agents/skills/<skill-name>/SKILL.md
```

### 6.1 安装 skill（离线）

```bash
ROOT=~/uos1050-offline-kit

mkdir -p ~/.agents/skills ~/.config/opencode/skills

cp -a "$ROOT/skills/agent-ssh-cli" ~/.agents/skills/
cp -a "$ROOT/skills/agent-database-cli" ~/.agents/skills/
cp -a "$ROOT/skills/agent-browser-cli" ~/.agents/skills/

ln -sfn ~/.agents/skills/agent-ssh-cli ~/.config/opencode/skills/agent-ssh-cli
ln -sfn ~/.agents/skills/agent-database-cli ~/.config/opencode/skills/agent-database-cli
ln -sfn ~/.agents/skills/agent-browser-cli ~/.config/opencode/skills/agent-browser-cli
```

确认：

```bash
ls -la ~/.config/opencode/skills
ls -la ~/.agents/skills
test -f ~/.config/opencode/skills/agent-ssh-cli/SKILL.md && echo ok-ssh
test -f ~/.config/opencode/skills/agent-database-cli/SKILL.md && echo ok-db
test -f ~/.config/opencode/skills/agent-browser-cli/SKILL.md && echo ok-browser
```

### 6.2 OpenCode 配置文件

编辑：

```text
~/.config/opencode/opencode.json
```

最小可用示例：

```json
{
  "$schema": "https://opencode.ai/config.json",
  "permission": {
    "bash": "allow"
  }
}
```

如果你已有 plugin 配置，保留即可。skill 目录软链成功后，OpenCode 启动时会自动发现 `~/.config/opencode/skills/*`。

### 6.3 让 OpenCode 能找到命令

确保 PATH 含：

```bash
export PATH=/opt/node/bin:/usr/local/bin:$PATH
```

验证：

```bash
which agentsshcli
which agent-database-cli
which agent-browser-cli
```

### 6.4 给 OpenCode 的使用提示词示例

SSH：

```text
使用 agent-ssh-cli skill。先 agentsshcli list，再对“内网服务器”执行 pwd 和 df -h。
```

Database：

```text
使用 agent-database-cli skill。先 list 数据库连接，再对 local-mysql 做只读查询，不要执行写操作。
```

Browser：

```text
使用 agent-browser-cli skill。先 status/doctor/tabs，确认扩展已连接，再打开目标页面并截图。
```

### 6.5 也可用官方 install-skill（若 CLI 已装）

```bash
agent-database-cli install-skill --yes
agent-browser-cli install-skill --yes
# agent-ssh-cli 没有 install-skill，手动拷 skill 即可
```

注意：`install-skill` 默认写到 `~/.agents/skills`，并给 codex/claude/cursor 建软链；  
OpenCode 建议额外建：

```bash
ln -sfn ~/.agents/skills/agent-database-cli ~/.config/opencode/skills/agent-database-cli
ln -sfn ~/.agents/skills/agent-browser-cli ~/.config/opencode/skills/agent-browser-cli
```

---

## 7. 验收清单

```bash
# 运行时
node -v
npm -v

# CLI
agentsshcli --help
agent-database-cli --help
agent-browser-cli --help

# 配置
test -f ~/.agent-ssh-cli/config.json
test -f ~/.agent-database-cli/config.json
test -f ~/.agent-browser-cli/config.json

# skill
test -f ~/.config/opencode/skills/agent-ssh-cli/SKILL.md
test -f ~/.config/opencode/skills/agent-database-cli/SKILL.md
test -f ~/.config/opencode/skills/agent-browser-cli/SKILL.md

# 业务验证
agentsshcli list
agent-database-cli list
agent-browser-cli status
```

`BUILD_INFO.txt` 中应看到：

- `build_image=debian:10`
- `intended_os=UOS 1050 / Debian 10 (glibc 2.28)`
- GLIBC 最高 `2.28`

---

## 8. 常见问题

### 8.1 GLIBC_2.xx not found
你装到了官方 npm 高 glibc 预编译包。请改用本介质中的 UOS 1050 产物。

### 8.2 agentsshcli 提示找不到原生二进制
平台包没装上。重新执行：

```bash
npm install -g ./npm/agent-ssh-cli-0.3.9.tgz ./npm/agent-ssh-cli-linux-x64-0.3.9.tgz
```

或直接复制 `agentsshcli-native`。

### 8.3 browser status 不健康
- Chrome 扩展未加载
- 扩展端口与 CLI 不一致
- 没打开普通网页标签
- 本机 18765/18767 被占用

处理：

```bash
agent-browser-cli doctor
agent-browser-cli restart
```

### 8.4 OpenCode 看不到 skill
检查：

```bash
ls -la ~/.config/opencode/skills
# 重启 OpenCode
```

### 8.5 database 连接失败
- 先确认网络可达目标库
- PostgreSQL 云库常需 `?sslmode=require`
- 默认 `readonly: true`，写操作会被拒绝

---

## 9. 卸载

```bash
npm uninstall -g agent-ssh-cli agent-database-cli @sleepinsummer/agent-browser-cli

rm -rf ~/.agent-ssh-cli ~/.agent-database-cli ~/.agent-browser-cli
rm -rf ~/.agents/skills/agent-ssh-cli \
       ~/.agents/skills/agent-database-cli \
       ~/.agents/skills/agent-browser-cli
rm -rf ~/.config/opencode/skills/agent-ssh-cli \
       ~/.config/opencode/skills/agent-database-cli \
       ~/.config/opencode/skills/agent-browser-cli
```

Chrome 中手动移除 `TMWD CDP Bridge` 扩展。

---

## 10. 介质来源与版本锁定

| 组件 | 版本 | 来源 |
|---|---|---|
| agent-ssh-cli | 0.3.9 | Allenskoo856 fork + UOS1050 Actions 产物 |
| agent-database-cli | 0.2.24 | 同上 |
| agent-browser-cli | 0.3.6 | 同上 |
| Node.js | 20.19.3 | https://nodejs.org/dist/v20.19.3/ |
| 构建镜像 | debian:10 | glibc 2.28 |
| 目标系统 | UOS 1050 x86_64 | |

成功构建记录：

- https://github.com/Allenskoo856/agent-ssh-cli/actions/runs/29679196876
- https://github.com/Allenskoo856/agent-database-cli/actions/runs/29679197859
- https://github.com/Allenskoo856/agent-browser-cli/actions/runs/29679198921
