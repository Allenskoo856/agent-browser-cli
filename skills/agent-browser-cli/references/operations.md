# agent-browser-cli 运维排障

## 基本顺序

正常浏览器任务不要从本文件开始，也不要先查状态。先执行目标命令，让 CLI 按需自动启动 daemon：

```bash
agent-browser-cli tabs
agent-browser-cli open https://example.com
agent-browser-cli scan --text-only
agent-browser-cli exec --tab <tabId> 'return document.title'
```

只有目标命令失败、输出明确提示连接异常，或用户明确要求排障时，才看轻量状态：

```bash
agent-browser-cli status
```

再按需做完整自检：

```bash
agent-browser-cli doctor
agent-browser-cli logs --tail 100
```

`status` 的 `ok=true` 只表示命令执行成功；是否可用看 `healthy` 和 `summary`。
`daemon_not_running` / `running=false` 只表示当前未常驻；在尚未执行目标命令前，这通常是正常状态，不应阻塞任务。

## daemon 未运行

典型状态：

```json
{ "summary": "daemon_not_running", "running": false }
```

处理：

```bash
agent-browser-cli restart
agent-browser-cli status
```

浏览器任务中优先执行 `tabs/open/exec/scan` 自动启动 daemon；只有自动启动失败或需要排障时再 `restart`。`doctor` 不会自动启动 daemon。

## 扩展未连接

典型状态：

```json
{ "summary": "extension_not_connected", "connection": { "extension_connected": false } }
```

处理：

1. 确认 Chrome 已打开。
2. 确认已加载 `assets/tmwd_cdp_bridge` 扩展。
3. 确认扩展 popup 中的端口等于 `doctor` 输出的 `configured_port`。
4. 在 `chrome://extensions` 点击扩展“重新加载”。
5. 执行：

```bash
agent-browser-cli status
```

## 没有可用标签页

典型状态：

```json
{ "summary": "no_active_tabs", "connection": { "active_tabs": 0 } }
```

处理：打开一个普通 `http/https` 页面。不要只停留在 `about:blank`、`chrome://` 或扩展页。

## 端口不一致

典型状态：

```json
{ "summary": "port_mismatch" }
```

处理：

```bash
agent-browser-cli restart
agent-browser-cli doctor
```

如果需要修改扩展端口，必须先说明影响并取得用户确认：该命令会写入 `~/.agent-browser-cli/config.json`，运行中的 daemon 会重启。

```bash
agent-browser-cli set-extension-port <port>
```

## 查看日志

日志固定在：

```text
~/.agent-browser-cli/logs/daemon.log
```

查看最近 100 行：

```bash
agent-browser-cli logs
```

查看最近 N 行：

```bash
agent-browser-cli logs --tail 200
```

`logs` 只输出纯文本日志，不输出 JSON，也不支持 `--follow`。

## 重启和停止

```bash
agent-browser-cli restart
agent-browser-cli stop
```

`restart` 会重新读取配置并启动 daemon；`stop` 只停止 daemon。

## 重新安装 skill

安装命令会写用户目录并创建软链接。必须先 dry-run 展示真实计划：

```bash
agent-browser-cli install-skill --dry-run
```

用户确认后执行：

```bash
agent-browser-cli install-skill
```

脚本化场景可用：

```bash
agent-browser-cli install-skill --yes
```

默认实体安装目录：

```text
~/.agents/skills/agent-browser-cli
```

Codex、Claude、Kimi CLI、Cursor、Gemini 等已存在的 skill 父目录只创建软链接，不复制多份实体文件。已存在且不是软链接的目标不会被覆盖，`--yes` 也不会覆盖。
