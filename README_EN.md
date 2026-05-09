<div align="center">

# agent-browser-cli

A browser perception and control CLI for agents, turning a real Chrome session into reusable tab scanning, page JavaScript, Cookie, CDP, and screenshot capabilities.

Browser perception · Page control · Chrome session reuse · CDP · Conditional wait · Agent Skill integration

<p>
  <a href="https://github.com/sleepinginsummer/agent-browser-cli"><img src="https://img.shields.io/badge/CLI-agentbrowsercli-2ea44f" alt="CLI agentbrowsercli"></a>
  <a href="https://github.com/sleepinginsummer/agent-browser-cli/blob/main/LICENSE"><img src="https://img.shields.io/badge/License-MIT-green" alt="License MIT"></a>
  <a href="https://www.python.org/"><img src="https://img.shields.io/badge/Python-%3E%3D3.10-3776AB?logo=python&logoColor=white" alt="Python >=3.10"></a>
  <a href="https://github.com/sleepinginsummer/agent-browser-cli"><img src="https://img.shields.io/badge/Windows-MacOS-0078D6?labelColor=0078D6&color=C0C0C0" alt="Windows/MacOS"></a>
  <a href="https://github.com/sleepinginsummer/agent-browser-cli/releases"><img src="https://img.shields.io/badge/release-v0.1.0-blue" alt="release v0.1.0"></a>
  <a href="https://github.com/sleepinginsummer/agent-browser-cli/pulls"><img src="https://img.shields.io/badge/PRs-welcome-brightgreen" alt="PRs welcome"></a>
</p>

[AI One-Line Install](#ai-one-line-install) · [Manual Installation](#manual-installation) · [Chrome Extension](#chrome-extension) · [Update](#update) · [Uninstall](#uninstall) · [Friendly Links](#friendly-links)

[中文](README.md) | English

</div>

`agent-browser-cli` is a browser perception and control tool for agents. It connects to the user's real Chrome browser through a Chrome extension, preserving login state and cookies while providing tab scanning, page JavaScript execution, cookie reading, CDP control, screenshots, file uploads, dropdown clicks, and related capabilities.

This project is not Selenium or Playwright. It is better suited for helping agents read pages accurately and perform actions inside an existing browser session.

## Project Info

- Current version: `0.1.0`
- Supported platforms: Windows, macOS
- Python: `3.10+` recommended
- Browser: Chrome / Chromium, with `assets/tmwd_cdp_bridge` loaded

## Acknowledgements

The browser control capability in this project was extracted and adapted from the Web toolchain in [GenericAgent](https://github.com/lsdefine/GenericAgent), including ideas and implementation around `TMWebDriver`, `simphtml`, and the `tmwd_cdp_bridge` extension.

Thanks to the GenericAgent project for the browser bridge, page simplification, CDP control, and practical SOPs. This repository reorganizes and enhances that work for standalone usage and CLI invocation.

## AI One-Line Install

```text
Please read https://github.com/sleepinginsummer/agent-browser-cli/blob/main/AI_INSTALL.md, follow the instructions to install the CLI, load the Chrome extension, and add `skills/agent-browser-cli/SKILL.md`.
```

## Improvements

- Extracted browser control capability from GenericAgent and exposed it as a CLI for Codex, Claude Code, and OpenCode. The GenericAgent browser extension can be reused and does not need to be reinstalled.
- Avoids reinitializing the browser connection for every command.
- Adds a startup lock to avoid repeated low-level port binding when multiple CLI commands start concurrently.
- Adds the skill `skills/agent-browser-cli/SKILL.md` for AI usage reference.
- Includes several optimizations to reduce command execution time.

## Layout

```text
.
├── agent_browser_cli.py          # CLI entry
├── agent_browser_server.py       # Long-lived HTTP service
├── ga.py                         # web_scan / web_execute_js entry
├── TMWebDriver.py                # Browser extension WebSocket / HTTP bridge
├── simphtml.py                   # Page simplification and DOM diff
├── assets/tmwd_cdp_bridge/       # Chrome MV3 extension
├── memory/                       # Browser tool SOPs
└── skills/agent-browser-cli/     # skill
```

## Manual Installation

```bash
cd /path/to/agent-browser-cli
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
```

## Chrome Extension

Load this extension directory:

```text
assets/tmwd_cdp_bridge
```

Chrome needs at least one normal web page tab open. Do not leave it only on `about:blank` or `chrome://` pages.

## Quick Check

```bash
.venv/bin/python agent_browser_cli.py tabs
.venv/bin/python agent_browser_cli.py open https://www.baidu.com
```

On success, it returns:

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

## Common Commands

The README only keeps the quick entry point. For the full command list and browser operation SOP, see [skills/agent-browser-cli/SKILL.md](./skills/agent-browser-cli/SKILL.md).

```bash
.venv/bin/python agent_browser_cli.py tabs
```

## Update

```bash
git pull
.venv/bin/python -m pip install -r requirements.txt
.venv/bin/python agent_browser_cli.py restart
```

If the Chrome extension has updates, reload the `assets/tmwd_cdp_bridge` extension in `chrome://extensions`.

Current extension bridge identifier:

```js
const TID = '__agent_browser_cli_bridge_26c9f1';
```

If you installed the skill into a global Codex/Agent directory, copy it again after updating:

```bash
mkdir -p ~/.agents/skills/agent-browser-cli
cp skills/agent-browser-cli/SKILL.md ~/.agents/skills/agent-browser-cli/SKILL.md
```

## Uninstall

Stop the long-lived service first:

```bash
.venv/bin/python agent_browser_cli.py stop
```

Then clean up as needed:

```bash
rm -rf .venv
rm -f .agent-browser-cli.log .agent-browser-cli.lock
rm -rf ~/.agents/skills/agent-browser-cli
```

Finally, remove the `TMWD CDP Bridge` extension from Chrome's extension management page, or remove the loaded `assets/tmwd_cdp_bridge` extension configuration.

## Ports

- `18765`: underlying `TMWebDriver` WebSocket, used by the Chrome extension.
- `18766`: underlying `TMWebDriver` HTTP `/link`, used by the internal master/remote protocol.
- `18767`: outer `agent-browser-cli` HTTP service, used by the CLI to reuse the session.

## Friendly Links

- [LINUX DO - A New Ideal Community](https://linux.do/)

## License

MIT License. See [LICENSE](./LICENSE).
