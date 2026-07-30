# agent-browser-cli Playwright 离线安装器

该介质面向 Linux x86_64，要求目标主机已经安装并启动 Docker 或 Podman。
安装过程不访问镜像仓库或 npm；Chromium、Node、Playwright 和 Rust CLI 均在内置
OCI 镜像中。

这不是 UOS/Debian 原生二进制包。使用容器封装是为了固定 Chromium 及其系统依赖，
避免目标主机的 glibc、字体和浏览器动态库差异破坏可重复性。

## 安装

```bash
sha256sum --check agent-browser-cli-playwright-*-offline-installer.tar.gz.sha256
tar -xzf agent-browser-cli-playwright-*-offline-installer.tar.gz
cd agent-browser-cli-playwright-*-offline-installer
./install.sh
```

无人值守：

```bash
./install.sh --yes
```

指定 Podman：

```bash
./install.sh --engine podman
```

普通用户默认安装到：

```text
~/.local/share/agent-browser-cli-playwright
~/.local/bin/agent-browser-cli
```

root 默认安装到：

```text
/opt/agent-browser-cli-playwright
/usr/local/bin/agent-browser-cli
```

## 使用

离线安装与普通安装使用统一的 `agent-browser-cli pw` 命令入口：

```bash
agent-browser-cli pw doctor

agent-browser-cli pw session create \
  --name order-smoke \
  --base-url https://order.test.intranet \
  --allow-host order.test.intranet \
  --trace

agent-browser-cli pw open /login --session order-smoke
agent-browser-cli pw snapshot --session order-smoke
agent-browser-cli pw screenshot --session order-smoke --full-page
agent-browser-cli pw session close order-smoke
```

命令会为当前工作目录维护一个后台 Runtime 容器，因此多次命令之间可以复用同一个
隔离 Session。项目目录挂载到容器 `/workspace/project`。

执行标准测试：

```bash
export E2E_BASE_URL=https://order.test.intranet
export E2E_USER=agent-e2e
export E2E_PASSWORD='通过安全介质注入'

agent-browser-cli pw test tests/e2e \
  --cwd /workspace/project \
  --config playwright.config.mjs \
  --report-dir /workspace/project/artifacts/e2e
```

`E2E_*` 环境变量自动转发。其他环境变量通过逗号分隔的名称显式允许：

```bash
export AGENT_BROWSER_PLAYWRIGHT_FORWARD_ENV=HTTPS_PROXY,NO_PROXY
```

## 内网网络

默认使用容器 `bridge` 网络。使用已经创建的受控网络：

```bash
agent-browser-cli pw runtime stop
export AGENT_BROWSER_PLAYWRIGHT_NETWORK=intranet-e2e
agent-browser-cli pw doctor
```

Linux 主机需要访问宿主机服务时，可明确使用：

```bash
export AGENT_BROWSER_PLAYWRIGHT_NETWORK=host
```

修改网络、共享内存或额外容器参数前，先执行
`agent-browser-cli pw runtime stop`，修改后运行下一条命令即可创建新的 Runtime。

额外的容器创建参数可以逐行写入文件：

```text
--add-host=auth.test.intranet:10.10.8.20
--volume=/etc/pki/internal-root-ca.pem:/etc/pki/internal-root-ca.pem:ro
--env=NODE_EXTRA_CA_CERTS=/etc/pki/internal-root-ca.pem
```

然后：

```bash
export AGENT_BROWSER_PLAYWRIGHT_RUN_ARGS_FILE=/etc/agent-browser-playwright/run-args
```

## Runtime 管理

```bash
agent-browser-cli pw runtime status
agent-browser-cli pw runtime container
agent-browser-cli pw runtime stop
```

状态和测试制品默认保存在：

```text
~/.local/share/agent-browser-playwright/data
```

可以通过 `AGENT_BROWSER_PLAYWRIGHT_HOME` 修改。

## 卸载

进入安装目录执行：

```bash
./uninstall.sh
```

同时移除镜像和依赖卷：

```bash
./uninstall.sh --remove-image --remove-node-modules-volume
```

默认保留用户测试数据，防止误删截图、Trace 和报告。

## 安全说明

- 安装器会先校验介质内全部 SHA-256；
- 安装和自检均不访问网络；
- 测试 Session 不读取用户真实 Chrome Cookie；
- 当前目录会挂载到 Runtime 容器 `/workspace/project`，不要从敏感目录启动命令；
- `--allow-host` 不能代替容器网络、防火墙或受控代理；
- 不要把密码、Cookie 或 Token 写进测试源码和日志。
