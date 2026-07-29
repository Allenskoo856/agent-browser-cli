use crate::config;
use anyhow::{anyhow, Context, Result};
use serde_json::{json, Value};
use std::env;
use std::path::{Path, PathBuf};
use std::process::Stdio;
use std::sync::atomic::{AtomicU64, Ordering};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::process::{Child, ChildStdin, ChildStdout, Command};
use tokio::sync::Mutex;

struct RuntimeProcess {
    child: Child,
    stdin: ChildStdin,
    stdout: BufReader<ChildStdout>,
}

pub struct PlaywrightRuntime {
    process: Mutex<Option<RuntimeProcess>>,
    next_id: AtomicU64,
}

impl Default for PlaywrightRuntime {
    fn default() -> Self {
        Self {
            process: Mutex::new(None),
            next_id: AtomicU64::new(1),
        }
    }
}

impl PlaywrightRuntime {
    pub async fn call(&self, method: &str, params: Value) -> Result<Value> {
        let mut guard = self.process.lock().await;
        if guard.is_none() {
            *guard = Some(start_runtime().await?);
        }

        let id = self.next_id.fetch_add(1, Ordering::Relaxed).to_string();
        let request = json!({
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params
        });
        let process = guard
            .as_mut()
            .ok_or_else(|| anyhow!("Playwright runtime 未启动"))?;

        let transport_result: Result<Value> = async {
            process
                .stdin
                .write_all(request.to_string().as_bytes())
                .await?;
            process.stdin.write_all(b"\n").await?;
            process.stdin.flush().await?;

            let mut line = String::new();
            let bytes = process.stdout.read_line(&mut line).await?;
            if bytes == 0 {
                return Err(anyhow!("Playwright runtime 已退出且未返回响应"));
            }
            serde_json::from_str(line.trim()).context("Playwright runtime 返回了无效 JSON")
        }
        .await;

        let response = match transport_result {
            Ok(response) => response,
            Err(err) => {
                let _ = process.child.kill().await;
                *guard = None;
                return Err(err);
            }
        };
        if response.get("id").and_then(Value::as_str) != Some(id.as_str()) {
            let _ = process.child.kill().await;
            *guard = None;
            return Err(anyhow!("Playwright runtime 响应 ID 不匹配"));
        }
        if let Some(error) = response.get("error") {
            let message = error
                .get("message")
                .and_then(Value::as_str)
                .unwrap_or("Playwright runtime 调用失败");
            return Err(anyhow!(message.to_string()));
        }
        response
            .get("result")
            .cloned()
            .ok_or_else(|| anyhow!("Playwright runtime 响应缺少 result"))
    }

    pub async fn shutdown(&self) -> Value {
        let mut guard = self.process.lock().await;
        let Some(process) = guard.as_mut() else {
            return json!({ "running": false, "closed": true });
        };

        let id = self.next_id.fetch_add(1, Ordering::Relaxed).to_string();
        let request = json!({
            "jsonrpc": "2.0",
            "id": id,
            "method": "runtime.shutdown",
            "params": {}
        });
        let sent = process
            .stdin
            .write_all(format!("{request}\n").as_bytes())
            .await
            .is_ok();
        if sent {
            let _ = process.stdin.flush().await;
        }
        let exited = tokio::time::timeout(std::time::Duration::from_secs(5), process.child.wait())
            .await
            .is_ok();
        if !exited {
            let _ = process.child.kill().await;
        }
        *guard = None;
        json!({ "running": true, "closed": true, "graceful": exited })
    }
}

async fn start_runtime() -> Result<RuntimeProcess> {
    let runtime_script = resolve_runtime_script()?;
    let node = resolve_node_binary(&runtime_script);
    let state_dir = config::user_config_dir()?.join("playwright");
    let artifacts_dir = state_dir.join("artifacts");
    std::fs::create_dir_all(&state_dir)
        .with_context(|| format!("创建 Playwright 状态目录失败: {}", state_dir.display()))?;
    std::fs::create_dir_all(&artifacts_dir).with_context(|| {
        format!(
            "创建 Playwright artifacts 目录失败: {}",
            artifacts_dir.display()
        )
    })?;

    let mut command = Command::new(&node);
    command
        .arg(&runtime_script)
        .env("AGENT_BROWSER_PLAYWRIGHT_STATE_DIR", &state_dir)
        .env("AGENT_BROWSER_PLAYWRIGHT_ARTIFACTS_DIR", &artifacts_dir)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .kill_on_drop(true);

    if let Some(browser_path) = env::var_os("AGENT_BROWSER_PLAYWRIGHT_EXECUTABLE_PATH") {
        command.env("AGENT_BROWSER_PLAYWRIGHT_EXECUTABLE_PATH", browser_path);
    }
    if let Some(browser_path) = env::var_os("PLAYWRIGHT_BROWSERS_PATH") {
        command.env("PLAYWRIGHT_BROWSERS_PATH", browser_path);
    }

    let mut child = command.spawn().with_context(|| {
        format!(
            "启动 Playwright runtime 失败: {} {}",
            PathBuf::from(&node).display(),
            runtime_script.display()
        )
    })?;
    let stdin = child
        .stdin
        .take()
        .ok_or_else(|| anyhow!("无法打开 Playwright runtime stdin"))?;
    let stdout = child
        .stdout
        .take()
        .ok_or_else(|| anyhow!("无法打开 Playwright runtime stdout"))?;

    Ok(RuntimeProcess {
        child,
        stdin,
        stdout: BufReader::new(stdout),
    })
}

fn resolve_node_binary(runtime_script: &Path) -> PathBuf {
    if let Some(node) = env::var_os("AGENT_BROWSER_PLAYWRIGHT_NODE") {
        return PathBuf::from(node);
    }
    let runtime_root = runtime_script
        .parent()
        .and_then(Path::parent)
        .unwrap_or_else(|| Path::new("."));
    let bundled = if cfg!(windows) {
        runtime_root.join("node/node.exe")
    } else {
        runtime_root.join("node/bin/node")
    };
    if bundled.is_file() {
        bundled
    } else {
        PathBuf::from("node")
    }
}

fn resolve_runtime_script() -> Result<PathBuf> {
    if let Some(script) = env::var_os("AGENT_BROWSER_PLAYWRIGHT_RUNTIME") {
        let script = PathBuf::from(script);
        if script.is_file() {
            return Ok(script);
        }
        return Err(anyhow!(
            "AGENT_BROWSER_PLAYWRIGHT_RUNTIME 指向的文件不存在: {}",
            script.display()
        ));
    }

    let mut candidates = Vec::new();
    if let Some(package_dir) = env::var_os("AGENT_BROWSER_CLI_PACKAGE_DIR") {
        let package_dir = PathBuf::from(package_dir);
        candidates.push(package_dir.join("runtime/playwright/src/runtime.mjs"));
        if let Some(parent) = package_dir.parent() {
            candidates.push(parent.join("runtime/playwright/src/runtime.mjs"));
        }
    }
    if let Ok(cwd) = env::current_dir() {
        candidates.push(cwd.join("runtime/playwright/src/runtime.mjs"));
    }
    if let Ok(exe) = env::current_exe() {
        for ancestor in exe.ancestors().take(8) {
            candidates.push(ancestor.join("runtime/playwright/src/runtime.mjs"));
        }
    }

    candidates
        .into_iter()
        .find(|candidate| candidate.is_file())
        .ok_or_else(|| {
            anyhow!(
                "找不到 Playwright runtime；设置 AGENT_BROWSER_PLAYWRIGHT_RUNTIME 或安装包含 runtime/playwright 的完整包"
            )
        })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn explicit_missing_runtime_is_reported() {
        let old = env::var_os("AGENT_BROWSER_PLAYWRIGHT_RUNTIME");
        env::set_var(
            "AGENT_BROWSER_PLAYWRIGHT_RUNTIME",
            "/definitely/missing/runtime.mjs",
        );
        let error = resolve_runtime_script().unwrap_err().to_string();
        if let Some(old) = old {
            env::set_var("AGENT_BROWSER_PLAYWRIGHT_RUNTIME", old);
        } else {
            env::remove_var("AGENT_BROWSER_PLAYWRIGHT_RUNTIME");
        }
        assert!(error.contains("指向的文件不存在"));
    }
}
