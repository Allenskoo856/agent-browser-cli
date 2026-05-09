# AI 安装说明

把下面这段话发给 AI，让 AI 在你的本机环境里完成安装、配置 skill 和验证。

```text
请帮我安装 agent-browser-cli：https://github.com/sleepinginsummer/agent-browser-cli

要求：
1. 先问我项目是否已经下载；如果没下载，问我要下载到哪个目录。
2. 校验 Python 版本，要求 Python >= 3.10。
3. 在项目目录创建 .venv 虚拟环境，并安装 requirements.txt。
4. 指导我在 Chrome 中加载 assets/tmwd_cdp_bridge 解压扩展。
5. 如果之前已经加载过扩展，必须在 chrome://extensions 里重新加载 `assets/tmwd_cdp_bridge`，确保最新 `config.js` 和 `background.js` 生效。
6. 将 skills/agent-browser-cli/SKILL.md 安装到当前 AI 可识别的 skills 目录。
7. 执行 agent_browser_cli.py tabs、open 和 status 验证可用。
8. 如果已经安装过旧版 GenericAgent 的 tmwd_cdp_bridge 扩展，不要直接复用旧扩展；必须确认扩展目录来自当前项目并已重新加载。
```

## 1. 确认项目目录

先确认用户是否已经下载项目。

如果已经下载，进入现有项目目录：

```bash
cd /path/to/agent-browser-cli
```

如果还没有下载，先询问用户希望下载到哪个父目录，例如：

```text
项目还没下载。你希望下载到哪个目录？例如 ~/projects 或 /Volumes/data/project
```

用户确认后再执行：

```bash
git clone https://github.com/sleepinginsummer/agent-browser-cli.git
cd agent-browser-cli
```

如果目标目录已存在，不要覆盖，先确认是否复用现有目录。

## 2. 校验 Python 版本

```bash
python3 --version
```

要求 Python `>= 3.10`。如果版本过低，先停止安装并提示用户升级 Python。

## 3. 创建虚拟环境并安装依赖

```bash
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
.venv/bin/python agent_browser_cli.py --help
```

如果虚拟环境创建失败，先检查：

```bash
python3 -m venv --help
```

## 4. 加载 Chrome 扩展

在 Chrome 打开：

```text
chrome://extensions
```

开启“开发者模式”，加载已解压扩展目录：

```text
assets/tmwd_cdp_bridge
```

如果之前已经安装过旧版 GenericAgent 的 `tmwd_cdp_bridge` 扩展，不要直接复用旧扩展。当前项目需要加载 `assets/tmwd_cdp_bridge`，并在每次扩展代码更新后点击“重新加载”。

当前扩展配置应包含：

```js
const TID = '__agent_browser_cli_bridge_26c9f1';
```

Chrome 至少需要打开一个正常网页标签页，不要只停留在 `about:blank` 或 `chrome://` 页面。

## 5. 安装 skill

将仓库中的 `skills/agent-browser-cli/SKILL.md` 安装到 AI 使用的 skills 目录。

通用目录示例：

```bash
mkdir -p ~/.agents/skills/agent-browser-cli
cp skills/agent-browser-cli/SKILL.md ~/.agents/skills/agent-browser-cli/SKILL.md
```

Codex 默认目录示例：

```bash
mkdir -p ~/.codex/skills/agent-browser-cli
cp skills/agent-browser-cli/SKILL.md ~/.codex/skills/agent-browser-cli/SKILL.md
```

如果 AI 使用其它 skills 目录，将 `SKILL.md` 复制到对应的 `agent-browser-cli/SKILL.md`。

## 6. 验证

```bash
.venv/bin/python agent_browser_cli.py tabs
.venv/bin/python agent_browser_cli.py open https://www.baidu.com
.venv/bin/python agent_browser_cli.py status
```

成功时，`tabs` 会返回 `ok: true`，并包含当前 Chrome 标签页数量。
`open` 应能原生新开标签页，不应使用 `exec --monitor` 或 `window.open` 代替。

如果常驻服务需要重载最新代码：

```bash
.venv/bin/python agent_browser_cli.py restart
```

## 7. 使用入口

拿到标签页 ID 后，可以执行：

```bash
.venv/bin/python agent_browser_cli.py scan --tab <tabId> --text-only
.venv/bin/python agent_browser_cli.py exec --tab <tabId> 'return document.title'
```

完整命令和浏览器操作 SOP 见：

```text
skills/agent-browser-cli/SKILL.md
```
