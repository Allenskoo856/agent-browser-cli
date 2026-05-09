#!/usr/bin/env python3
"""agent-browser-cli 常驻服务。

职责：
- 复用同一个 ga.driver 和浏览器扩展连接。
- 每次请求刷新 last_activity，默认空闲 300 秒自动退出。
- 对外提供轻量 HTTP API 给 CLI 调用。
"""

from __future__ import annotations

import json
import os
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any

import ga


HOST = "127.0.0.1"
PORT = int(os.environ.get("AGENT_BROWSER_CLI_PORT", "18767"))
IDLE_TTL = int(os.environ.get("AGENT_BROWSER_CLI_TTL", "300"))
STARTED_AT = time.time()
last_activity = time.time()
shutdown_requested = False
driver_ready = False


def _touch() -> None:
    global last_activity
    last_activity = time.time()


def _json_default(obj: Any) -> str:
    return str(obj)


def _response(ok: bool, **kwargs: Any) -> dict[str, Any]:
    data = {"ok": ok}
    data.update(kwargs)
    return data


def _wait_for_js(
    wait_js: str,
    switch_tab_id: str | None,
    timeout: float,
    interval: float,
) -> dict[str, Any]:
    """按条件轮询页面状态，条件满足立刻返回，避免固定 sleep。"""
    deadline = time.time() + max(timeout, 0)
    interval = max(interval, 0.02)
    last_result: Any = None
    last_error: Any = None
    while True:
        try:
            result = ga.web_execute_js(wait_js, switch_tab_id=switch_tab_id, no_monitor=True)
            last_result = result
            last_error = None
            if result.get("status") == "success" and bool(result.get("js_return")):
                return _response(True, matched=True, result=result)
        except Exception as e:
            last_error = str(e)
        if time.time() >= deadline:
            return _response(False, matched=False, result=last_result, error=last_error)
        time.sleep(interval)


def _is_extension_json(script: str) -> bool:
    stripped = script.strip()
    if not stripped.startswith("{"):
        return False
    try:
        data = json.loads(stripped)
    except json.JSONDecodeError:
        return False
    return isinstance(data, dict) and "cmd" in data


def _wrap_script_with_wait(script: str, wait_js: str, timeout: float, interval: float) -> str:
    """把主脚本和等待条件合并为一次页面 JS 执行，减少浏览器往返。"""
    timeout_ms = max(int(timeout * 1000), 0)
    interval_ms = max(int(interval * 1000), 20)
    return f"""
const __agentBrowserMain = {json.dumps(script, ensure_ascii=False)};
const __agentBrowserWait = {json.dumps(wait_js, ensure_ascii=False)};
const __agentBrowserTimeoutMs = {timeout_ms};
const __agentBrowserIntervalMs = {interval_ms};
const AsyncFunction = Object.getPrototypeOf(async function(){{}}).constructor;
const __runUser = async (code) => {{
  const trimmed = String(code || '').trim();
  if (!trimmed) return undefined;
  if (/^return\\b/.test(trimmed)) return await (new AsyncFunction(trimmed))();
  try {{
    const value = eval(trimmed);
    return value instanceof Promise ? await value : value;
  }} catch (e) {{
    if (e instanceof SyntaxError && (/return/i.test(e.message) || /await/i.test(e.message))) {{
      return await (new AsyncFunction(trimmed))();
    }}
    throw e;
  }}
}};
const __mainResult = await __runUser(__agentBrowserMain);
let __matched = false;
let __waitValue = undefined;
let __waitError = null;
const __deadline = Date.now() + __agentBrowserTimeoutMs;
while (true) {{
  try {{
    __waitValue = await __runUser(__agentBrowserWait);
    __waitError = null;
    if (__waitValue) {{
      __matched = true;
      break;
    }}
  }} catch (e) {{
    __waitError = e.message || String(e);
  }}
  if (Date.now() >= __deadline) break;
  await new Promise(resolve => setTimeout(resolve, __agentBrowserIntervalMs));
}}
return {{
  result: __mainResult,
  wait: {{
    ok: __matched,
    matched: __matched,
    value: __waitValue,
    error: __waitError
  }}
}};
"""


class Handler(BaseHTTPRequestHandler):
    server_version = "AgentBrowserCli/1.0"

    def log_message(self, fmt: str, *args: Any) -> None:
        return

    def _read_json(self) -> dict[str, Any]:
        length = int(self.headers.get("Content-Length", "0") or "0")
        if length <= 0:
            return {}
        raw = self.rfile.read(length).decode("utf-8")
        return json.loads(raw) if raw else {}

    def _send(self, data: dict[str, Any], status: int = 200) -> None:
        body = json.dumps(data, ensure_ascii=False, default=_json_default).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:
        _touch()
        try:
            if self.path == "/health":
                self._send(
                    _response(
                        driver_ready,
                        running=True,
                        ready=driver_ready,
                        pid=os.getpid(),
                        uptime=round(time.time() - STARTED_AT, 3),
                        idle_seconds=round(time.time() - last_activity, 3),
                        ttl=IDLE_TTL,
                    )
                )
                return
            if self.path == "/tabs":
                self._send(_response(True, result=ga.web_scan(tabs_only=True)))
                return
            self._send(_response(False, error="not found"), status=404)
        except Exception as e:
            self._send(_response(False, error=str(e)), status=500)

    def do_POST(self) -> None:
        global shutdown_requested
        _touch()
        try:
            payload = self._read_json()
            if self.path == "/scan":
                result = ga.web_scan(
                    tabs_only=bool(payload.get("tabs_only", False)),
                    switch_tab_id=payload.get("switch_tab_id"),
                    text_only=bool(payload.get("text_only", False)),
                )
                self._send(_response(True, result=result))
                return
            if self.path == "/exec":
                script = payload.get("script", "")
                switch_tab_id = payload.get("switch_tab_id")
                wait_js = payload.get("wait_js")
                if wait_js and not _is_extension_json(script):
                    wrapped_script = _wrap_script_with_wait(
                        script=script,
                        wait_js=wait_js,
                        timeout=float(payload.get("wait_timeout", 3)),
                        interval=float(payload.get("wait_interval", 0.1)),
                    )
                    result = ga.web_execute_js(
                        wrapped_script,
                        switch_tab_id=switch_tab_id,
                        no_monitor=bool(payload.get("no_monitor", False)),
                    )
                    self._send(_response(True, result=result, combined_wait=True))
                    return
                result = ga.web_execute_js(
                    script,
                    switch_tab_id=switch_tab_id,
                    no_monitor=bool(payload.get("no_monitor", False)),
                )
                if wait_js:
                    wait_result = _wait_for_js(
                        wait_js=wait_js,
                        switch_tab_id=switch_tab_id,
                        timeout=float(payload.get("wait_timeout", 3)),
                        interval=float(payload.get("wait_interval", 0.1)),
                    )
                    self._send(_response(True, result=result, wait=wait_result))
                    return
                self._send(_response(True, result=result))
                return
            if self.path == "/open":
                result = ga.web_open_tab(
                    payload.get("url", ""),
                    active=bool(payload.get("active", True)),
                    switch_tab_id=payload.get("switch_tab_id"),
                )
                self._send(_response(True, result=result))
                return
            if self.path == "/shutdown":
                shutdown_requested = True
                self._send(_response(True, status="shutdown_requested"))
                threading.Thread(target=self.server.shutdown, daemon=True).start()
                return
            self._send(_response(False, error="not found"), status=404)
        except Exception as e:
            self._send(_response(False, error=str(e)), status=500)


def idle_watchdog(server: ThreadingHTTPServer) -> None:
    while not shutdown_requested:
        time.sleep(1)
        if time.time() - last_activity > IDLE_TTL:
            server.shutdown()
            return


def main() -> int:
    global driver_ready
    # 启动阶段先初始化底层 TMWebDriver，避免 /health 过早返回可用导致并发请求重复绑定 18765。
    ga.web_scan(tabs_only=True)
    driver_ready = True
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    threading.Thread(target=idle_watchdog, args=(server,), daemon=True).start()
    print(f"agent-browser-cli server listening on http://{HOST}:{PORT}, ttl={IDLE_TTL}s", flush=True)
    try:
        server.serve_forever()
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
