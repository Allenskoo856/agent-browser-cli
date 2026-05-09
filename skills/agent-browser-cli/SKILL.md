---
name: agent-browser-cli
description: 使用 agent-browser-cli 进行浏览器感知与控制。适用于标签页扫描/切换、页面 JS 执行、Cookie、CDP、contentSettings、截图、文件上传、下拉框点击、tmwd_cdp_bridge 初始化和 Web 工具排障。
---

# agent-browser-cli

使用 `agent-browser-cli`、`web_scan`、`web_execute_js` 进行浏览器控制。底层通过 `TMWebDriver.py` 和 Chrome 扩展接管用户浏览器，保留登录态和 Cookie；不是 Selenium/Playwright。

## 项目路径

在仓库根目录创建并使用虚拟环境：

```bash
.venv/bin/python
```

缺包时只安装到当前项目虚拟环境，不要装到系统 Python：

```bash
.venv/bin/python -m pip install beautifulsoup4 requests simple-websocket-server bottle
```

扩展目录：

```text
assets/tmwd_cdp_bridge
```

扩展配置必须存在：

```js
const TID = '__agent_browser_cli_bridge_26c9f1';
```

对应文件：

```text
assets/tmwd_cdp_bridge/config.js
```

## 最小自检

Chrome 必须已打开，且至少有一个正常网页标签页，不能只停留在 `about:blank`、`chrome://` 等内部页。

优先用常驻会话 CLI 自检。它会自动启动 `agent_browser_server.py`，复用同一个 `ga.driver`，默认空闲 300 秒自动退出；每次请求都会续期。

```bash
.venv/bin/python agent_browser_cli.py tabs
```

服务状态、停止和重载：

```bash
.venv/bin/python agent_browser_cli.py status
.venv/bin/python agent_browser_cli.py stop
.venv/bin/python agent_browser_cli.py restart
```

常驻服务端口：
- `18765`：底层 `TMWebDriver` WebSocket，Chrome 扩展连接使用。
- `18766`：底层 `TMWebDriver` HTTP `/link`，用于内部 master/remote 协议。
- `18767`：外层 `agent-browser-cli` HTTP 服务，供 CLI 复用会话。

底层直接 Python 自检只用于排障或开发：

```bash
.venv/bin/python - <<'PY'
import ga
print(ga.web_scan(tabs_only=True))
PY
```

成功标志：
- 返回 `status=success`
- 能看到 `tabs_count`
- 首次运行会拉起本地 WS 服务 `ws://127.0.0.1:18765`

## 推荐 CLI 调用

日常操作优先使用 `agent_browser_cli.py`，避免每次都新起 Python 进程并重新初始化浏览器标签会话。

```bash
cd /path/to/agent-browser-cli
.venv/bin/python agent_browser_cli.py status
.venv/bin/python agent_browser_cli.py tabs
.venv/bin/python agent_browser_cli.py scan --tabs-only
.venv/bin/python agent_browser_cli.py scan --tab 303987837 --text-only
.venv/bin/python agent_browser_cli.py open https://www.baidu.com
.venv/bin/python agent_browser_cli.py exec --tab 303987837 'return document.title'
.venv/bin/python agent_browser_cli.py exec --tab 303987837 '{"cmd":"tabs"}'
.venv/bin/python agent_browser_cli.py restart
.venv/bin/python agent_browser_cli.py stop
```

执行较复杂 JS 时，把脚本写入文件再调用：

```bash
.venv/bin/python agent_browser_cli.py exec --tab 303987837 --file /tmp/script.js
```

`exec` 默认只执行 JS，不做执行前后 DOM 扫描。需要页面变化摘要时显式加 `--monitor`。

```bash
.venv/bin/python agent_browser_cli.py exec --tab 303987837 --monitor 'return document.title'
```

需要等待页面变化时，不要在脚本里固定 `setTimeout`。优先用 `--wait-js` 做条件等待，条件满足会立即返回；普通页面 JS 会把主脚本和等待条件合并到同一次浏览器执行里，减少往返：

```bash
.venv/bin/python agent_browser_cli.py exec --tab 303987837 'document.querySelector("button").click()' --wait-js 'return document.body.innerText.includes("完成")' --wait-timeout 3
```

## 基础调用

`web_scan` 负责感知，`web_execute_js` 负责精确操作。能精确操作时，不做全量扫描。下面是底层 Python 直接调用方式，主要用于排障或在脚本内集成；日常命令行操作优先用上面的常驻 CLI。

```python
import ga

print(ga.web_scan(tabs_only=True))
print(ga.web_scan())
print(ga.web_scan(text_only=True))
print(ga.web_scan(switch_tab_id="303987837"))
```

普通页面 JS：

```python
import ga

print(ga.web_execute_js("return document.title"))
print(ga.web_execute_js("""
return {
  title: document.title,
  url: location.href
}
"""))
```

`web_execute_js` 内使用 `await` 时必须显式 `return`，否则结果可能是 `null`。

`web_scan` 只读取当前页，不负责导航。切换网站用 `web_execute_js` 执行：

```python
import ga
print(ga.web_execute_js("location.href='https://example.com'; return location.href"))
```

新开标签页优先使用原生 `open` 命令，不要用 `window.open` 加 `--monitor`。`open` 底层走扩展 `chrome.tabs.create`，不会触发 CDP debugger attach。

```bash
.venv/bin/python agent_browser_cli.py open www.baidu.com
.venv/bin/python agent_browser_cli.py new-tab https://example.com --background
```

JS 事件的 `isTrusted=false`，敏感操作可能被页面拦截。JS 点击按钮打不开新 tab 时，优先改用 CDP 点击。

## 扩展 JSON 指令

跨标签页、Cookie、CDP、扩展管理、浏览器内容权限时，优先用 JSON 字符串直传，不要自己拼 DOM 节点。

```python
import ga

print(ga.web_execute_js('{"cmd":"tabs"}'))
print(ga.web_execute_js('{"cmd":"cookies"}'))
print(ga.web_execute_js('{"cmd":"cdp","tabId":303987837,"method":"Page.captureScreenshot","params":{"format":"png"}}'))
print(ga.web_execute_js('{"cmd":"batch","tabId":303987837,"commands":[{"cmd":"tabs"},{"cmd":"cookies"}]}'))
```

常用命令：
- `{"cmd":"tabs"}`：读取或切换标签页。
- `{"cmd":"openTab","url":"https://example.com","active":true}`：原生创建标签页。
- `{"cmd":"cookies"}`：读取当前页 Cookie。
- `{"cmd":"cdp","tabId":N,"method":"...","params":{}}`：执行单个 CDP 命令。
- `{"cmd":"batch","tabId":N,"commands":[...]}`：同一链路内批量执行，支持 `$N.path` 引用前序结果。
- `{"cmd":"management","method":"list|reload|disable|enable","extId":"..."}`：管理扩展。
- `{"cmd":"contentSettings","type":"automaticDownloads","pattern":"https://*/*","setting":"allow"}`：设置内容权限。

`contentSettings` 用于绕过 Chrome “下载多个文件”对话框，该对话框会阻塞浏览器 JS 执行。可选 `type` 包括 `automaticDownloads`、`popups`、`notifications` 等；`setting` 包括 `allow`、`block`、`ask`。CDP 的 `Browser.setDownloadBehavior` 在当前扩展环境不可用，因为 `chrome.debugger` 是 tab 级权限。

`batch` 前序命令失败时，后续 `$N.path` 引用会静默变成 `undefined`，必须检查 `results` 数组中每项的 `ok` 状态。同一条 CDP 链路内保持 `nodeId` 来源一致，不要混用 `querySelector` 路径和 `performSearch` 路径。

CDP 默认使用当前注入页的 `sender.tab.id`，跨 tab 操作必须显式传 `tabId`，或先在 `batch` 里通过 `tabs` 查询目标标签。

## CDP 操作要点

通用点击使用三事件序列：

```text
mouseMoved -> mousePressed -> mouseReleased
```

省略 `mouseMoved` 可能导致 MUI Tooltip、Ant Design Dropdown 等 hover 依赖组件失效。稳定状态下 CDP 坐标等于 `getBoundingClientRect()` 坐标，不需要修正。

首次 CDP attach 会触发 Chrome infobar，页面内容可能下移约 20px。首次操作前先发无害 `mouseMoved(0,0)` 预热，再测量元素坐标。

Vue3 自定义 Select/Dropdown 优先走 vnode 实例调用；CDP 坐标点击适合选项少且可见的场景。CDP 下拉框流程是先点击 select 打开下拉，再测量动态 option，再点击 option。

某些 SPA 后台标签不会加载数据，需要先用 CDP `Page.bringToFront` 切到前台。跨标签页操作时显式传 `tabId`，不依赖当前页。

页面存在 `transform: scale` 或 CSS `zoom` 时，坐标需要按页面缩放修正：

```js
const scale = window.visualViewport ? window.visualViewport.scale : 1;
const zoom = parseFloat(getComputedStyle(document.documentElement).zoom) || 1;
const realX = x * zoom;
const realY = y * zoom;
return { scale, zoom, realX, realY };
```

需要转物理坐标时：`physX = (screenX + rect中心x) * dpr`，`physY = (screenY + chromeH + rect中心y) * dpr`，其中 `chromeH = outerHeight - innerHeight`。

CDP 文本输入：`Input.insertText` 快但没有完整 key 事件，受控组件需要补发 `input` 事件；需要完整键盘模拟时用 `Input.dispatchKeyEvent` 逐键派发。

## 文件上传

文件上传优先用 DataTransfer API，纯 JS、无 CDP 依赖：

```js
const input = document.querySelector('input[type=file]');
const file = new File(['content'], 'demo.txt', { type: 'text/plain' });
const dt = new DataTransfer();
dt.items.add(file);
input.files = dt.files;
input.dispatchEvent(new Event('input', { bubbles: true }));
input.dispatchEvent(new Event('change', { bubbles: true }));
return input.files.length;
```

不优先使用 CDP `DOM.setFileInputFiles`，因为在 tmwd 桥环境里 `nodeId` 跨调用容易失效。若必须用 CDP，尽量在同一个 `batch` 内完成 `getDocument -> querySelector -> setFileInputFiles`，不要混用不同来源的 `nodeId`。

上传前检查 `input.accept`。页面有多个文件 input 时，用 `accept`、父容器文案、相邻 label 区分目标 input。上传后前端框架可能不感知，必要时补发 `input` / `change` 事件。

瞬态 input 的核心是缩短“发现 input -> set files”的时间窗：优先同 batch 完成；再不行用 DOM 事件监听；猴子补丁只作兜底思路。

## 下载与图片搜索

PDF 链接在浏览器内预览而非下载时，用页面 JS 触发 Blob 下载。该方式要求同源或 CORS 允许；跨域时先导航到目标域再执行。

```js
return fetch('PDF_URL').then(r => r.blob()).then(b => {
  const a = document.createElement('a');
  a.href = URL.createObjectURL(b);
  a.download = 'filename.pdf';
  a.click();
  return true;
});
```

Google 图搜场景不要硬编码混淆 class。点击结果优先找 `[role=button]` 容器；`web_scan` 可能过滤边栏，弹出后用 JS 读 `document.body.innerText`；大图遍历 `img` 按 `naturalWidth` 最大取 `src`；“访问”链接遍历 `a` 找 `textContent.includes('访问')` 的 `href`；缩略图直接提取 `img[src^="data:image"]`。

## iframe、Shadow DOM 与截图

同源 iframe 会被 `web_scan` 自动穿透。跨域 iframe 优先走 CDP：`Page.getFrameTree` 找 `frameId`，再 `Page.createIsolatedWorld` 获取 `contextId`，最后用 `Runtime.evaluate` 在 iframe 上下文执行。

iframe 内元素做 CDP 点击时，坐标需要合成：`finalX = iframeRect.x + elRect.x`，`finalY = iframeRect.y + elRect.y`。`Target.getTargets` / `Target.attachToTarget` 在当前 CDP 桥里通常会返回 `Not allowed`，不要优先走这条路。postMessage 中继只在 content script 已注入 iframe 时可靠，第三方支付 iframe 通常不可用。

closed Shadow DOM 使用 `DOM.getDocument({depth:-1,pierce:true})`，再逐级 `DOM.querySelector`。`nodeId` 在 DOM 变更后会失效，必要时重新 `getDocument`。

`DOM.getBoxModel` 返回 content 四点坐标，中心点用四点平均，不要简化成对角线平均；元素存在 rotate/skew 时四点不一定是矩形。`DOM.querySelector` 不能跨 Shadow 边界写组合选择器，要先找 host，再在 shadow 内找子元素。

截图优先 CDP：

```python
import ga
print(ga.web_execute_js('{"cmd":"cdp","method":"Page.captureScreenshot","params":{"format":"png"}}'))
```

验证码 canvas/img 优先用 JS `canvas.toDataURL()` 或直接读取图片 `src`。

## Autofill 与登录

`web_scan` 输出的 input 若带 `data-autofilled="true"`，value 可能显示为受保护提示，不是真实值。Chrome 只在前台 tab 释放 autofill 保护值，所以必须先 CDP `Page.bringToFront`。

一键释放流程：`Page.bringToFront` -> `mousePressed` 点任一字段，通常不需要 `mouseReleased` -> 等 500ms -> 补发 `input/change` 事件 -> 点登录。

## 调试

`simphtml` 调试必须注入 JS 到真实浏览器，Python 端无法模拟 DOM。

```python
from TMWebDriver import TMWebDriver
import simphtml

d = TMWebDriver()
d.set_session('url_pattern')
print(d.execute_js('return document.title'))
```

`simphtml.optimize_html_for_tokens(html)` 返回 BeautifulSoup Tag，展示前用 `str(...)`。

## 排障顺序

1. 先跑最小自检，确认是不是当前项目 `.venv` 缺包。
2. 若报 `BeautifulSoup4`、`requests`、`simple_websocket_server`、`bottle` 相关错误，安装到 `.venv`。
3. 若提示无法加载 `config.js` 或清单，检查 `assets/tmwd_cdp_bridge/config.js`。
4. 若 `web_scan` 提示没有可用标签页，先打开正常网页，不要只开内部页。
5. 若本机 `18766` 端口没监听，后台持续运行 `from TMWebDriver import TMWebDriver; TMWebDriver()` 起 master。
6. 若扩展没装，加载 `assets/tmwd_cdp_bridge`。
7. 仍失败时继续看 `memory/web_setup_sop.md` 和 `memory/tmwebdriver_sop.md`。
