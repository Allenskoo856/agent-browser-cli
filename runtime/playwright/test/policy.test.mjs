import assert from "node:assert/strict";
import test from "node:test";
import {
  assertTargetAllowed,
  matchesAllowedHost,
  normalizeAllowedHosts,
} from "../src/policy.mjs";

test("normalizes and deduplicates allowed hosts", () => {
  assert.deepEqual(
    normalizeAllowedHosts([" APP.EXAMPLE.COM ", "*.example.com", "app.example.com"]),
    ["app.example.com", "*.example.com"],
  );
});

test("matches exact and wildcard hosts without matching the bare suffix", () => {
  assert.equal(matchesAllowedHost("app.example.com", ["*.example.com"]), true);
  assert.equal(matchesAllowedHost("example.com", ["*.example.com"]), false);
  assert.equal(matchesAllowedHost("notexample.com", ["*.example.com"]), false);
});

test("blocks cloud metadata and link-local targets", async () => {
  await assert.rejects(
    assertTargetAllowed("http://169.254.169.254/latest", null, []),
    /Blocked metadata or link-local target/,
  );
  await assert.rejects(
    assertTargetAllowed("http://metadata.google.internal/", null, []),
    /Blocked metadata or link-local target/,
  );
});

test("enforces allowed hosts", async () => {
  const url = await assertTargetAllowed(
    "http://127.0.0.1:8080/health",
    null,
    ["127.0.0.1"],
  );
  assert.equal(url.pathname, "/health");
  await assert.rejects(
    assertTargetAllowed("https://example.com/", null, ["internal.example"]),
    /not in allowedHosts/,
  );
  await assert.rejects(
    assertTargetAllowed("https://example.com/", null, []),
    /allowedHosts is required/,
  );
});
