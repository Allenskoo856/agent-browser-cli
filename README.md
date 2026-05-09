<div align="center">

# agent-browser-cli

面向 Agent 的浏览器感知与控制 CLI，把真实 Chrome 会话变成可复用的标签页扫描、页面 JS、Cookie、CDP 和截图能力。

浏览器感知 · 页面控制 · Chrome 登录态复用 · CDP · 条件等待 · Agent Skill 集成

<p>
  <a href="https://github.com/sleepinginsummer/agent-browser-cli"><img src="https://img.shields.io/badge/CLI-agentbrowsercli-2ea44f" alt="CLI agentbrowsercli"></a>
  <a href="https://github.com/sleepinginsummer/agent-browser-cli/blob/main/LICENSE"><img src="https://img.shields.io/badge/License-MIT-green" alt="License MIT"></a>
  <a href="https://www.python.org/"><img src="https://img.shields.io/badge/Python-%3E%3D3.10-3776AB?logo=python&logoColor=white" alt="Python >=3.10"></a>
  <a href="https://github.com/sleepinginsummer/agent-browser-cli"><img src="https://img.shields.io/badge/Windows-MacOS-0078D6?labelColor=0078D6&color=C0C0C0" alt="Windows/MacOS"></a>
  <a href="https://github.com/sleepinginsummer/agent-browser-cli/releases"><img src="https://img.shields.io/badge/release-v0.1.0-blue" alt="release v0.1.0"></a>
  <a href="https://github.com/sleepinginsummer/agent-browser-cli/pulls"><img src="https://img.shields.io/badge/PRs-welcome-brightgreen" alt="PRs welcome"></a>
</p>

[AI 一句话安装](#ai-一句话安装) · [手动安装](#手动安装) · [Chrome 扩展](#chrome-扩展) · [更新](#更新) · [卸载](#卸载) · [友情链接](#友情链接)

中文 | [English](README_EN.md)

</div>

`agent-browser-cli` 是一个面向 Agent 的浏览器感知与控制工具。它通过 Chrome 扩展连接用户真实浏览器，保留登录态和 Cookie，提供标签页扫描、页面 JS 执行、Cookie 读取、CDP 控制、截图、文件上传、下拉框点击等能力。

本项目不是 Selenium / Playwright。它更适合在已有浏览器会话中辅助 Agent 精确读取页面和执行操作。

## 项目信息

- 当前版本：`0.1.0`
- 支持平台：Windows、macOS
- Python：建议 `3.10+`
- 浏览器：Chrome / Chromium，需加载 `assets/tmwd_cdp_bridge`

## 致谢

本项目的浏览器控制能力提取并改造自 [GenericAgent](https://github.com/lsdefine/GenericAgent) 项目中的 Web 工具链，包括 `TMWebDriver`、`simphtml` 和 `tmwd_cdp_bridge` 扩展相关思路与实现。

感谢 GenericAgent 项目提供的浏览器桥接、页面简化、CDP 控制和实践 SOP。本仓库在此基础上做了面向独立使用和 CLI 调用的整理与增强。

## AI 一句话安装

```text
请阅读 https://github.com/sleepinginsummer/agent-browser-cli/blob/main/AI_INSTALL.md，按说明安装 CLI、加载 Chrome 扩展，并添加 `skills/agent-browser-cli/SKILL.md`。
```

## 改进内容

- 从 GenericAgent 中拆出浏览器控制能力，使用cli 提供给codex、claude code、opencode使用。GenericAgent浏览器插件不需要重新安装，可以共用同一个插件
- 避免每次命令都重新初始化浏览器连接。
- 新增启动锁，避免多个 CLI 并发启动时重复绑定底层端口。
- 增加skill：`skills/agent-browser-cli/SKILL.md`，提供ai参考使用。
- 若干优化，缩短命令执行时间

## 目录结构

```text
.
├── agent_browser_cli.py          # 命令行入口
├── agent_browser_server.py       # 常驻 HTTP 服务
├── ga.py                         # web_scan / web_execute_js 入口
├── TMWebDriver.py                # 浏览器扩展 WebSocket / HTTP 桥
├── simphtml.py                   # 页面简化和 DOM diff
├── assets/tmwd_cdp_bridge/       # Chrome MV3 扩展
├── memory/                       # 浏览器工具 SOP
└── skills/agent-browser-cli/     #  skill
```

## 手动安装

```bash
cd /path/to/agent-browser-cli
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
```

## Chrome 扩展

加载扩展目录：

```text
assets/tmwd_cdp_bridge
```

Chrome 需要至少打开一个正常网页标签页，不要只停留在 `about:blank` 或 `chrome://` 页面。

## 快速自检

```bash
.venv/bin/python agent_browser_cli.py tabs
.venv/bin/python agent_browser_cli.py open https://www.baidu.com
```

成功时会返回：

```json
{
  "ok": true,
  "result": {
    "status": "success",
    "metadata": {
      "tabs_count": 1
    }
  }
}
```

## 常用命令

README 只保留快速入口；完整命令和浏览器操作 SOP 见 [skills/agent-browser-cli/SKILL.md](./skills/agent-browser-cli/SKILL.md)。

```bash
.venv/bin/python agent_browser_cli.py tabs
```

## 更新

```bash
git pull
.venv/bin/python -m pip install -r requirements.txt
.venv/bin/python agent_browser_cli.py restart
```

如果 Chrome 扩展有更新，在 `chrome://extensions` 中重新加载 `assets/tmwd_cdp_bridge` 扩展。

当前扩展配置标识为：

```js
const TID = '__agent_browser_cli_bridge_26c9f1';
```

如果你把 skill 安装到了 Codex/Agent 的全局目录，更新后同步复制：

```bash
mkdir -p ~/.agents/skills/agent-browser-cli
cp skills/agent-browser-cli/SKILL.md ~/.agents/skills/agent-browser-cli/SKILL.md
```

## 卸载

先停止常驻服务：

```bash
.venv/bin/python agent_browser_cli.py stop
```

然后按需清理：

```bash
rm -rf .venv
rm -f .agent-browser-cli.log .agent-browser-cli.lock
rm -rf ~/.agents/skills/agent-browser-cli
```

最后在 Chrome 扩展管理页中移除 `TMWD CDP Bridge` 扩展，或删除已加载的 `assets/tmwd_cdp_bridge` 扩展配置。

## 端口

- `18765`：底层 `TMWebDriver` WebSocket，Chrome 扩展连接使用。
- `18766`：底层 `TMWebDriver` HTTP `/link`，用于内部 master/remote 协议。
- `18767`：外层 `agent-browser-cli` HTTP 服务，供 CLI 复用会话。

## 友情链接

- [LINUX DO - 新的理想型社区](https://linux.do/)

## 许可证

MIT License. See [LICENSE](./LICENSE).
