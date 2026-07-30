# Playwright 隔离运行时

面向开发、测试和 Agent 使用者的完整操作流程、测试案例生成方式、CI 示例及真实
Chrome 登录态排障方法，见
[自动化测试与真实会话排障手册](./AUTOMATION-TESTING-GUIDE.md)。

## 定位

`agent-browser-cli` 提供两个互补的浏览器引擎：

- 默认 Chrome 引擎通过扩展连接用户真实 Chrome，复用现有标签页、Cookie 和登录态。
- `pw` 引擎通过 `playwright-core` 启动独立 Chromium，不读取用户浏览器状态，适合
  内网功能测试、CI 和离线部署。

Playwright 引擎不是为了测试 `agent-browser-cli` 本身。它是提供给 Agent 的通用
Web/UI/API 功能测试运行时，可用于测试其他前端、后台和微服务。

## 架构

```text
Agent / Skill
  -> agent-browser-cli
  -> Rust daemon / policy / artifact control
  -> stdin/stdout JSON-RPC v1
  -> Node Playwright runtime
       -> one isolated Chromium process per session
       -> APIRequestContext
       -> @playwright/test child process
```

Rust daemon 在第一次 `pw` 调用时懒启动 Node Runtime。Runtime 关闭或传输失败时，
Rust 会回收子进程；daemon 停止时会关闭全部 Playwright Session。

## 安装

源码开发：

```bash
npm ci
npm run playwright:check
npm run playwright:install
cargo build
./target/debug/agent-browser-cli pw doctor
```

`pw doctor` 会返回：

- JSON-RPC 协议版本
- Node、Playwright Runtime 和 Playwright 版本
- Chromium 可执行文件及安装状态
- 状态和制品目录
- 当前 Session 数量

## Session

```bash
agent-browser-cli pw session create \
  --name admin-smoke \
  --base-url https://admin.test.intranet \
  --allow-host admin.test.intranet \
  --allow-host auth.test.intranet \
  --locale zh-CN \
  --timezone Asia/Shanghai \
  --viewport-width 1440 \
  --viewport-height 900 \
  --trace
```

默认行为：

- headless Chromium
- 每个 Session 独立浏览器进程
- 每个 Session 独立临时 user data 目录
- Session 关闭后删除 Cookie、缓存和临时 profile
- artifacts 单独保留，便于审计和排障

需要观察浏览器时显式使用 `--headed`。代理配置使用 `--proxy-server` 和
`--proxy-bypass`。企业 CA 应通过运行环境的 `NODE_EXTRA_CA_CERTS` 配置；
`--ignore-https-errors` 只用于明确接受风险的测试环境。

## 页面操作

```bash
agent-browser-cli pw open /login --session admin-smoke
agent-browser-cli pw scan --session admin-smoke
agent-browser-cli pw snapshot --session admin-smoke
agent-browser-cli pw fill @e1 tester --session admin-smoke
agent-browser-cli pw press Enter --target @e1 --session admin-smoke
agent-browser-cli pw click @e3 --session admin-smoke
agent-browser-cli pw screenshot --session admin-smoke --full-page
agent-browser-cli pw pdf --session admin-smoke
```

`snapshot` 生成的 `@e` 引用只属于当前 Session 最近一次快照。页面结构或内容变化后
重新执行 `snapshot`。

本地 HTML Fixture 可以直接装载，不产生网络请求：

```bash
agent-browser-cli pw content tests/fixtures/p1.html --session admin-smoke
```

原始 JavaScript 默认禁止，需要逐次显式授权：

```bash
agent-browser-cli pw exec 'document.title' \
  --session admin-smoke \
  --allow-raw-javascript
```

## API 功能测试

不依赖浏览器 Cookie：

```bash
agent-browser-cli pw request https://api.test.intranet/health \
  --allow-host api.test.intranet \
  --method GET
```

与浏览器 Session 共享 Cookie：

```bash
agent-browser-cli pw request /api/me \
  --session admin-smoke \
  --method GET
```

使用独立 Cookie 容器：

```bash
agent-browser-cli pw request /api/me \
  --session admin-smoke \
  --isolated-cookies
```

Header 使用 `KEY=VALUE`：

```bash
agent-browser-cli pw request https://api.test.intranet/orders \
  --allow-host api.test.intranet \
  --method POST \
  --header Content-Type=application/json \
  --data '{"sku":"A-100","quantity":1}'
```

该能力用于 HTTP 功能测试，不用于性能或压力测试。

## 标准 Playwright Test

Agent 探索并确认流程后，应生成标准 Playwright Test，而不是把临时 CLI 操作当作
长期测试用例：

```bash
agent-browser-cli pw test tests/e2e \
  --cwd . \
  --config playwright.config.ts \
  --report-dir artifacts/e2e
```

失败时 CLI 返回非零退出码，适合作为 CI 门禁。测试项目自己的
`@playwright/test` 优先于 Runtime 内置副本，避免不同版本的 Test Runner 同时加载。

## 网络安全

通过交互式 CLI 发起的顶层页面导航或 API 请求必须配置 `allowedHosts`：

- Session 使用一个或多个 `--allow-host`
- 无 Session 的 API 请求也必须使用 `--allow-host`
- `*.example.intranet` 只匹配子域，不匹配裸域
- `169.254.169.254`、metadata hostname、IPv4/IPv6 link-local 地址始终禁止
- allowlist hostname 如果解析到 link-local 地址也会被拒绝

`allowedHosts` 是 CLI 调用层的目标校验，不是完整的出站防火墙，不能保证拦截页面
加载的每个子资源、页面脚本请求或所有重定向链路。生产和内网部署必须额外在容器、
主机防火墙或受控代理层限制出站网络。

## Runtime 环境变量

```text
AGENT_BROWSER_PLAYWRIGHT_RUNTIME
  Node Runtime 脚本路径。源码开发或自定义安装时使用。

AGENT_BROWSER_PLAYWRIGHT_NODE
  Node 可执行文件路径。未设置时优先使用随包 Node，最后回退 PATH 中的 node。

AGENT_BROWSER_PLAYWRIGHT_EXECUTABLE_PATH
  Chromium 可执行文件。用于企业维护的固定浏览器或离线浏览器目录。

PLAYWRIGHT_BROWSERS_PATH
  Playwright 浏览器目录。

NODE_EXTRA_CA_CERTS
  企业根证书 PEM 文件。

AGENT_BROWSER_PLAYWRIGHT_DEBUG=1
  在 JSON-RPC 错误中包含 Runtime stack，仅用于排障。
```

## 离线交付

流水线交付的是容器化离线安装器，而不是要求用户手工 `docker load` 的裸镜像包。
介质结构：

```text
agent-browser-cli-playwright-v<version>-linux-x64-offline-installer/
  install.sh
  launcher.sh
  uninstall.sh
  README-OFFLINE.md
  BUILD_INFO.txt
  SHA256SUMS
  payload/
    agent-browser-cli-playwright-<version>-linux-x64-image.tar.gz
```

目标主机要求 Linux x86_64，并已经安装 Docker 或 Podman。安装不访问公网：

```bash
sha256sum -c \
  agent-browser-cli-playwright-v<version>-linux-x64-offline-installer.tar.gz.sha256
tar -xzf \
  agent-browser-cli-playwright-v<version>-linux-x64-offline-installer.tar.gz
cd agent-browser-cli-playwright-v<version>-linux-x64-offline-installer
./install.sh
agent-browser-playwright doctor
```

安装器会校验介质、导入镜像、在断网容器中启动 Chromium、自检并安装
`agent-browser-playwright`。该命令直接映射 `agent-browser-cli pw` 的子命令：

```bash
agent-browser-playwright session create \
  --name demo \
  --allow-host app.test.intranet
agent-browser-playwright open https://app.test.intranet --session demo
agent-browser-playwright session close demo
```

现有 Debian 10/UOS 1050 Rust 二进制通过，并不代表 Playwright Chromium 可以在
该系统原生运行。当前安装器明确使用容器固定 Node、Playwright、Chromium、字体及
动态库；如果目标环境不能运行容器，需要单独设计并验证原生离线包，不能复用本介质
的兼容性结论。
