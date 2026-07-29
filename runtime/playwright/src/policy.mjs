import dns from "node:dns/promises";
import net from "node:net";

const BLOCKED_HOSTS = new Set([
  "169.254.169.254",
  "metadata.google.internal",
  "metadata.google",
]);

export function normalizeAllowedHosts(hosts = []) {
  return [...new Set(
    hosts
      .map((host) => String(host).trim().toLowerCase())
      .filter(Boolean),
  )];
}

export function matchesAllowedHost(hostname, allowedHosts) {
  const normalized = hostname.toLowerCase();
  return allowedHosts.some((entry) => {
    if (entry.startsWith("*.")) {
      const suffix = entry.slice(1);
      return normalized.endsWith(suffix) && normalized.length > suffix.length;
    }
    return normalized === entry;
  });
}

function isBlockedAddress(address) {
  if (BLOCKED_HOSTS.has(address)) return true;
  if (net.isIP(address) === 4) {
    const parts = address.split(".").map(Number);
    return parts[0] === 169 && parts[1] === 254;
  }
  return address.toLowerCase().startsWith("fe80:");
}

export async function assertTargetAllowed(rawTarget, baseUrl, allowedHosts = []) {
  const url = new URL(rawTarget, baseUrl || undefined);
  if (!["http:", "https:"].includes(url.protocol)) {
    throw new Error(`Only http/https targets are allowed: ${url.protocol}`);
  }

  const hostname = url.hostname.toLowerCase();
  if (BLOCKED_HOSTS.has(hostname) || isBlockedAddress(hostname)) {
    throw new Error(`Blocked metadata or link-local target: ${hostname}`);
  }

  const normalizedAllowedHosts = normalizeAllowedHosts(allowedHosts);
  if (normalizedAllowedHosts.length === 0) {
    throw new Error("allowedHosts is required for network targets");
  }
  if (!matchesAllowedHost(hostname, normalizedAllowedHosts)) {
    throw new Error(`Target host is not in allowedHosts: ${hostname}`);
  }

  // Literal hostnames are checked above. DNS resolution adds protection against
  // a hostname allowlist entry being rebound to link-local metadata services.
  if (net.isIP(hostname) === 0) {
    const records = await dns.lookup(hostname, { all: true }).catch(() => []);
    if (records.some((record) => isBlockedAddress(record.address))) {
      throw new Error(`Target resolves to a blocked link-local address: ${hostname}`);
    }
  }

  return url;
}
