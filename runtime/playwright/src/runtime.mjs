#!/usr/bin/env node

import { spawn } from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import readline from "node:readline";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
import { chromium, request as playwrightRequest } from "playwright-core";
import { assertTargetAllowed, normalizeAllowedHosts } from "./policy.mjs";
import { createSnapshot } from "./snapshot.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const runtimeRoot = path.resolve(__dirname, "..");
const require = createRequire(import.meta.url);
const runtimePackage = JSON.parse(
  fs.readFileSync(path.join(runtimeRoot, "package.json"), "utf8"),
);
const playwrightCorePackage = JSON.parse(
  fs.readFileSync(require.resolve("playwright-core/package.json"), "utf8"),
);
const stateRoot = path.resolve(
  process.env.AGENT_BROWSER_PLAYWRIGHT_STATE_DIR
    || path.join(os.tmpdir(), "agent-browser-playwright"),
);
const artifactsRoot = path.resolve(
  process.env.AGENT_BROWSER_PLAYWRIGHT_ARTIFACTS_DIR
    || path.join(stateRoot, "artifacts"),
);
const sessions = new Map();

fs.mkdirSync(stateRoot, { recursive: true });
fs.mkdirSync(artifactsRoot, { recursive: true });

function jsonResult(id, result) {
  process.stdout.write(`${JSON.stringify({ jsonrpc: "2.0", id, result })}\n`);
}

function jsonError(id, error) {
  process.stdout.write(`${JSON.stringify({
    jsonrpc: "2.0",
    id,
    error: {
      code: -32000,
      message: error?.message || String(error),
      data: process.env.AGENT_BROWSER_PLAYWRIGHT_DEBUG === "1"
        ? { stack: error?.stack || null }
        : undefined,
    },
  })}\n`);
}

function sessionInfo(session) {
  return {
    name: session.name,
    createdAt: session.createdAt,
    headless: session.headless,
    baseUrl: session.baseUrl || null,
    allowedHosts: session.allowedHosts,
    pages: session.context.pages().map((page, index) => ({
      index,
      url: page.url(),
    })),
    artifactDir: session.artifactDir,
  };
}

function requireSession(params) {
  const name = String(params.session || params.name || "").trim();
  if (!name) throw new Error("session is required");
  const session = sessions.get(name);
  if (!session) throw new Error(`Playwright session not found: ${name}`);
  return session;
}

function currentPage(session) {
  const pages = session.context.pages();
  if (pages.length === 0) throw new Error(`Session has no open page: ${session.name}`);
  const index = session.activePageIndex ?? pages.length - 1;
  return pages[Math.max(0, Math.min(index, pages.length - 1))];
}

function resolveTarget(session, rawTarget) {
  const target = String(rawTarget || "").trim();
  if (!target) throw new Error("target is required");
  if (target.startsWith("@e")) {
    const selector = session.refs.get(target);
    if (!selector) {
      throw new Error(`Unknown element ref ${target}; run pw snapshot again`);
    }
    return selector;
  }
  return target;
}

async function closeSession(name) {
  const session = sessions.get(name);
  if (!session) return false;
  sessions.delete(name);
  try {
    if (session.tracing) {
      await session.context.tracing.stop().catch(() => {});
    }
    await session.context.close();
  } finally {
    fs.rmSync(session.userDataDir, { recursive: true, force: true });
  }
  return true;
}

async function createSession(params) {
  const name = String(params.name || "").trim();
  if (!/^[a-zA-Z0-9._-]{1,64}$/.test(name)) {
    throw new Error("name must match [a-zA-Z0-9._-] and be at most 64 characters");
  }
  if (sessions.has(name)) throw new Error(`Session already exists: ${name}`);

  const headless = params.headless !== false;
  const userDataDir = fs.mkdtempSync(path.join(stateRoot, `${name}-`));
  const artifactDir = path.join(
    artifactsRoot,
    `${new Date().toISOString().replaceAll(":", "-")}-${name}-${crypto.randomUUID()}`,
  );
  fs.mkdirSync(artifactDir, { recursive: true });

  let context;
  try {
    context = await chromium.launchPersistentContext(userDataDir, {
      headless,
      executablePath: process.env.AGENT_BROWSER_PLAYWRIGHT_EXECUTABLE_PATH || undefined,
      ignoreHTTPSErrors: Boolean(params.ignoreHTTPSErrors),
      locale: params.locale || "zh-CN",
      timezoneId: params.timezone || "Asia/Shanghai",
      viewport: {
        width: Number(params.viewportWidth || 1440),
        height: Number(params.viewportHeight || 900),
      },
      acceptDownloads: params.allowDownloads !== false,
      proxy: params.proxyServer ? {
        server: params.proxyServer,
        bypass: params.proxyBypass || undefined,
      } : undefined,
    });

    const pages = context.pages();
    const page = pages[0] || await context.newPage();
    const session = {
      name,
      context,
      page,
      activePageIndex: 0,
      createdAt: new Date().toISOString(),
      headless,
      baseUrl: params.baseUrl || null,
      allowedHosts: normalizeAllowedHosts(params.allowedHosts || []),
      userDataDir,
      artifactDir,
      refs: new Map(),
      tracing: false,
    };

    if (params.trace) {
      await context.tracing.start({ screenshots: true, snapshots: true, sources: true });
      session.tracing = true;
    }

    sessions.set(name, session);
    return sessionInfo(session);
  } catch (error) {
    await context?.close().catch(() => {});
    fs.rmSync(userDataDir, { recursive: true, force: true });
    throw error;
  }
}

async function openPage(params) {
  const session = requireSession(params);
  const url = await assertTargetAllowed(
    params.url || params.target,
    session.baseUrl,
    session.allowedHosts,
  );
  const page = params.newPage ? await session.context.newPage() : currentPage(session);
  await page.goto(url.href, {
    waitUntil: params.waitUntil || "domcontentloaded",
    timeout: Number(params.timeoutMs || 30000),
  });
  session.activePageIndex = session.context.pages().indexOf(page);
  session.refs.clear();
  return { url: page.url(), title: await page.title(), pageIndex: session.activePageIndex };
}

async function setPageContent(params) {
  const session = requireSession(params);
  const page = currentPage(session);
  await page.setContent(String(params.html || ""), {
    waitUntil: params.waitUntil || "load",
    timeout: Number(params.timeoutMs || 30000),
  });
  session.refs.clear();
  return { url: page.url(), title: await page.title() };
}

async function snapshotPage(params) {
  const session = requireSession(params);
  const page = currentPage(session);
  const snapshot = await createSnapshot(page, Number(params.limit || 200));
  session.refs = new Map(snapshot.elements.map((element) => [element.ref, element.selector]));
  return snapshot;
}

async function scanPage(params) {
  const session = requireSession(params);
  const page = currentPage(session);
  return {
    title: await page.title(),
    url: page.url(),
    text: (await page.locator("body").innerText()).slice(0, Number(params.limit || 50000)),
  };
}

async function clickPage(params) {
  const session = requireSession(params);
  const page = currentPage(session);
  const target = resolveTarget(session, params.target);
  await page.locator(target).click({ timeout: Number(params.timeoutMs || 15000) });
  session.refs.clear();
  return { clicked: params.target, url: page.url() };
}

async function fillPage(params) {
  const session = requireSession(params);
  const page = currentPage(session);
  const target = resolveTarget(session, params.target);
  const locator = page.locator(target);
  const value = String(params.value ?? "");
  if (params.append) {
    await locator.pressSequentially(value, { timeout: Number(params.timeoutMs || 15000) });
  } else {
    await locator.fill(value, { timeout: Number(params.timeoutMs || 15000) });
  }
  session.refs.clear();
  return { filled: params.target, length: value.length };
}

async function pressPage(params) {
  const session = requireSession(params);
  const page = currentPage(session);
  if (params.target) {
    const target = resolveTarget(session, params.target);
    await page.locator(target).press(String(params.keys), {
      timeout: Number(params.timeoutMs || 15000),
    });
  } else {
    await page.keyboard.press(String(params.keys));
  }
  session.refs.clear();
  return { pressed: params.keys };
}

async function evaluatePage(params) {
  const session = requireSession(params);
  if (!params.allowRawJavascript) {
    throw new Error("Raw JavaScript is disabled; pass allowRawJavascript=true explicitly");
  }
  const page = currentPage(session);
  const result = await page.evaluate(String(params.script || ""));
  return { value: result };
}

async function screenshotPage(params) {
  const session = requireSession(params);
  const page = currentPage(session);
  const filename = path.basename(params.filename || `screenshot-${Date.now()}.png`);
  const output = path.join(session.artifactDir, filename);
  await page.screenshot({ path: output, fullPage: Boolean(params.fullPage) });
  return { path: output, bytes: fs.statSync(output).size };
}

async function pdfPage(params) {
  const session = requireSession(params);
  const page = currentPage(session);
  const filename = path.basename(params.filename || `page-${Date.now()}.pdf`);
  const output = path.join(session.artifactDir, filename);
  await page.pdf({
    path: output,
    format: params.paper || "A4",
    landscape: Boolean(params.landscape),
    printBackground: params.printBackground !== false,
  });
  return { path: output, bytes: fs.statSync(output).size };
}

async function traceStart(params) {
  const session = requireSession(params);
  if (session.tracing) throw new Error("Tracing is already active");
  await session.context.tracing.start({ screenshots: true, snapshots: true, sources: true });
  session.tracing = true;
  return { tracing: true };
}

async function traceStop(params) {
  const session = requireSession(params);
  if (!session.tracing) throw new Error("Tracing is not active");
  const filename = path.basename(params.filename || `trace-${Date.now()}.zip`);
  const output = path.join(session.artifactDir, filename);
  await session.context.tracing.stop({ path: output });
  session.tracing = false;
  return { tracing: false, path: output, bytes: fs.statSync(output).size };
}

async function requestFetch(params) {
  const session = params.session ? requireSession(params) : null;
  const baseUrl = session?.baseUrl || params.baseUrl || null;
  const allowedHosts = session?.allowedHosts || normalizeAllowedHosts(params.allowedHosts || []);
  const url = await assertTargetAllowed(params.url || params.target, baseUrl, allowedHosts);
  const isolated = !session || params.shareBrowserCookies === false;
  const api = isolated
    ? await playwrightRequest.newContext({
      ignoreHTTPSErrors: Boolean(params.ignoreHTTPSErrors),
      extraHTTPHeaders: params.headers || {},
    })
    : session.context.request;
  try {
    const response = await api.fetch(url.href, {
      method: String(params.method || "GET").toUpperCase(),
      headers: params.headers || {},
      data: params.data,
      failOnStatusCode: false,
      timeout: Number(params.timeoutMs || 30000),
      maxRedirects: Number(params.maxRedirects ?? 10),
    });
    const body = await response.text();
    const bodyLimit = Math.max(0, Math.min(Number(params.bodyLimit || 1024 * 1024), 5 * 1024 * 1024));
    let json = null;
    try {
      json = JSON.parse(body);
    } catch {
      // Keep the original text response.
    }
    return {
      url: response.url(),
      status: response.status(),
      ok: response.ok(),
      headers: response.headers(),
      body: body.slice(0, bodyLimit),
      json,
      truncated: body.length > bodyLimit,
    };
  } finally {
    if (isolated) await api.dispose();
  }
}

async function runTests(params) {
  const cwd = path.resolve(params.cwd || process.cwd());
  let cliPath;
  try {
    const projectRequire = createRequire(path.join(cwd, "package.json"));
    cliPath = projectRequire.resolve("@playwright/test/cli");
  } catch {
    try {
      cliPath = require.resolve("@playwright/test/cli");
    } catch {
      throw new Error("@playwright/test is not installed in the project or Playwright runtime");
    }
  }
  const reportDir = path.resolve(params.reportDir || path.join(artifactsRoot, `test-${Date.now()}`));
  fs.mkdirSync(reportDir, { recursive: true });

  const args = [cliPath, "test"];
  if (params.path) args.push(String(params.path));
  if (params.config) args.push("--config", String(params.config));
  if (params.project) args.push("--project", String(params.project));
  if (params.grep) args.push("--grep", String(params.grep));
  args.push("--reporter", params.reporter || "line");
  const env = {
    ...process.env,
    ...Object.fromEntries(
      Object.entries(params.env || {}).map(([key, value]) => [key, String(value)]),
    ),
    AGENT_BROWSER_REPORT_DIR: reportDir,
  };

  const result = await new Promise((resolve, reject) => {
    const child = spawn(process.execPath, args, {
      cwd,
      env,
      stdio: ["ignore", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk) => {
      stdout = (stdout + chunk).slice(-200000);
    });
    child.stderr.on("data", (chunk) => {
      stderr = (stderr + chunk).slice(-200000);
    });
    child.on("error", reject);
    child.on("exit", (code, signal) => resolve({ code, signal, stdout, stderr }));
  });

  return {
    ok: result.code === 0,
    exitCode: result.code,
    signal: result.signal,
    stdout: result.stdout,
    stderr: result.stderr,
    reportDir,
  };
}

async function handle(method, params = {}) {
  switch (method) {
    case "runtime.health":
      return {
        ok: true,
        protocolVersion: 1,
        runtimeVersion: runtimePackage.version,
        nodeVersion: process.version,
        playwrightVersion: playwrightCorePackage.version,
        chromiumExecutable: chromium.executablePath(),
        chromiumInstalled: fs.existsSync(
          process.env.AGENT_BROWSER_PLAYWRIGHT_EXECUTABLE_PATH || chromium.executablePath(),
        ),
        stateRoot,
        artifactsRoot,
        sessions: sessions.size,
      };
    case "session.create": return createSession(params);
    case "session.list": return [...sessions.values()].map(sessionInfo);
    case "session.close":
      return { name: params.name || params.session, closed: await closeSession(params.name || params.session) };
    case "session.closeAll": {
      const names = [...sessions.keys()];
      for (const name of names) await closeSession(name);
      return { closed: names };
    }
    case "page.open": return openPage(params);
    case "page.setContent": return setPageContent(params);
    case "page.scan": return scanPage(params);
    case "page.snapshot": return snapshotPage(params);
    case "page.click": return clickPage(params);
    case "page.fill": return fillPage(params);
    case "page.press": return pressPage(params);
    case "page.evaluate": return evaluatePage(params);
    case "page.screenshot": return screenshotPage(params);
    case "page.pdf": return pdfPage(params);
    case "trace.start": return traceStart(params);
    case "trace.stop": return traceStop(params);
    case "request.fetch": return requestFetch(params);
    case "test.run": return runTests(params);
    case "runtime.shutdown":
      await shutdown();
      return { ok: true };
    default:
      throw new Error(`Unknown runtime method: ${method}`);
  }
}

let shuttingDown = false;
async function shutdown() {
  if (shuttingDown) return;
  shuttingDown = true;
  for (const name of [...sessions.keys()]) {
    await closeSession(name).catch(() => {});
  }
}

const input = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
input.on("line", async (line) => {
  let request;
  try {
    request = JSON.parse(line);
    if (request.jsonrpc !== "2.0" || request.id === undefined || !request.method) {
      throw new Error("Invalid JSON-RPC request");
    }
    const result = await handle(request.method, request.params || {});
    jsonResult(request.id, result);
    if (request.method === "runtime.shutdown") process.exit(0);
  } catch (error) {
    jsonError(request?.id ?? null, error);
  }
});

input.on("close", async () => {
  await shutdown();
  process.exit(0);
});

for (const signal of ["SIGTERM", "SIGINT"]) {
  process.on(signal, async () => {
    await shutdown();
    process.exit(0);
  });
}
