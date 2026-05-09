#!/usr/bin/env python3
"""agent-browser-cli 常驻会话客户端。

默认复用同一个 Python 进程中的 ga.driver，避免每次命令都重新等待浏览器扩展上报标签页。
服务空闲 300 秒自动退出；每次请求都会续期。
"""

from __future__ import annotations

import argparse
import contextlib
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request


HOST = "127.0.0.1"
PORT = int(os.environ.get("AGENT_BROWSER_CLI_PORT", "18767"))
BASE_URL = f"http://{HOST}:{PORT}"
PROJECT_DIR = os.path.dirname(os.path.abspath(__file__))
LOCK_PATH = os.path.join(PROJECT_DIR, ".agent-browser-cli.lock")


def _request(path: str, payload: dict | None = None, timeout: float = 30) -> dict:
    data = None if payload is None else json.dumps(payload, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(
        BASE_URL + path,
        data=data,
        headers={"Content-Type": "application/json"},
        method="GET" if payload is None else "POST",
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8"))


def _is_server_alive() -> bool:
    try:
        result = _request("/health", timeout=1)
        return result.get("ok") is True
    except Exception:
        return False


def _start_server() -> None:
    log_path = os.path.join(PROJECT_DIR, ".agent-browser-cli.log")
    cmd = [sys.executable, os.path.join(PROJECT_DIR, "agent_browser_server.py")]
    with open(log_path, "ab") as log:
        subprocess.Popen(
            cmd,
            cwd=PROJECT_DIR,
            stdout=log,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )


@contextlib.contextmanager
def _startup_lock():
    lock_file = open(LOCK_PATH, "a+", encoding="utf-8")
    try:
        if os.name == "posix":
            import fcntl

            fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
        yield
    finally:
        if os.name == "posix":
            import fcntl

            fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
        lock_file.close()


def ensure_server() -> None:
    if _is_server_alive():
        return
    with _startup_lock():
        if _is_server_alive():
            return
        _start_server()
        deadline = time.time() + 15
        while time.time() < deadline:
            if _is_server_alive():
                return
            time.sleep(0.2)
        raise RuntimeError("agent-browser-cli server 启动超时，查看 .agent-browser-cli.log")


def print_json(data: dict) -> None:
    print(json.dumps(data, ensure_ascii=False, indent=2))


def cmd_tabs(_: argparse.Namespace) -> None:
    ensure_server()
    print_json(_request("/tabs"))


def cmd_scan(args: argparse.Namespace) -> None:
    ensure_server()
    print_json(
        _request(
            "/scan",
            {
                "tabs_only": args.tabs_only,
                "text_only": args.text_only,
                "switch_tab_id": args.tab,
            },
            timeout=args.timeout,
        )
    )


def cmd_exec(args: argparse.Namespace) -> None:
    ensure_server()
    script = args.script
    if args.file:
        with open(args.file, "r", encoding="utf-8") as f:
            script = f.read()
    no_monitor = not args.monitor
    print_json(
        _request(
            "/exec",
            {
                "script": script,
                "switch_tab_id": args.tab,
                "no_monitor": no_monitor,
                "wait_js": args.wait_js,
                "wait_timeout": args.wait_timeout,
                "wait_interval": args.wait_interval,
            },
            timeout=args.timeout,
        )
    )


def cmd_open(args: argparse.Namespace) -> None:
    ensure_server()
    print_json(
        _request(
            "/open",
            {
                "url": args.url,
                "active": not args.background,
                "switch_tab_id": args.tab,
            },
            timeout=args.timeout,
        )
    )


def cmd_stop(_: argparse.Namespace) -> None:
    if not _is_server_alive():
        print_json({"ok": True, "status": "not_running"})
        return
    print_json(_request("/shutdown", {}, timeout=3))


def wait_server_stopped(timeout: float = 5) -> bool:
    deadline = time.time() + timeout
    while time.time() < deadline:
        if not _is_server_alive():
            return True
        time.sleep(0.1)
    return not _is_server_alive()


def cmd_restart(_: argparse.Namespace) -> None:
    stopped = True
    if _is_server_alive():
        try:
            _request("/shutdown", {}, timeout=3)
        except Exception:
            pass
        stopped = wait_server_stopped()
    if not stopped:
        print_json({"ok": False, "error": "server 停止超时"})
        return
    ensure_server()
    print_json(_request("/health"))


def cmd_status(_: argparse.Namespace) -> None:
    if not _is_server_alive():
        print_json({"ok": True, "running": False})
        return
    print_json(_request("/health"))


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="agent-browser-cli")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("tabs", help="列出浏览器标签页")
    p.set_defaults(func=cmd_tabs)

    p = sub.add_parser("scan", help="调用 ga.web_scan")
    p.add_argument("--tab", help="切换到指定 tab id 后扫描")
    p.add_argument("--tabs-only", action="store_true", help="只读取标签页")
    p.add_argument("--text-only", action="store_true", help="只读取文本")
    p.add_argument("--timeout", type=float, default=60)
    p.set_defaults(func=cmd_scan)

    p = sub.add_parser("exec", help="调用 ga.web_execute_js")
    p.add_argument("script", nargs="?", default="", help="要执行的 JS 或扩展 JSON 指令")
    p.add_argument("--file", help="从文件读取 JS")
    p.add_argument("--tab", help="目标 tab id")
    p.add_argument("--monitor", action="store_true", help="执行前后扫描 DOM 并返回页面变化摘要")
    p.add_argument("--wait-js", help="执行后轮询该 JS 表达式，返回真值时立即结束")
    p.add_argument("--wait-timeout", type=float, default=3, help="wait-js 最大等待秒数")
    p.add_argument("--wait-interval", type=float, default=0.1, help="wait-js 轮询间隔秒数")
    p.add_argument("--timeout", type=float, default=60)
    p.set_defaults(func=cmd_exec)

    p = sub.add_parser("open", aliases=["new-tab"], help="原生新开标签页访问 URL")
    p.add_argument("url", help="要打开的 URL，省略协议时默认补 https://")
    p.add_argument("--background", action="store_true", help="后台打开，不激活新标签页")
    p.add_argument("--tab", help="通过指定现有 tab 注入扩展指令")
    p.add_argument("--timeout", type=float, default=30)
    p.set_defaults(func=cmd_open)

    p = sub.add_parser("status", help="查看常驻服务状态")
    p.set_defaults(func=cmd_status)

    p = sub.add_parser("stop", help="停止常驻服务")
    p.set_defaults(func=cmd_stop)

    p = sub.add_parser("restart", help="重启常驻服务并加载最新代码")
    p.set_defaults(func=cmd_restart)
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    try:
        args.func(args)
        return 0
    except urllib.error.URLError as e:
        print_json({"ok": False, "error": str(e)})
        return 1
    except Exception as e:
        print_json({"ok": False, "error": str(e)})
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
