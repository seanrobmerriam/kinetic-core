#!/usr/bin/env node
"use strict";

/**
 * Security regression checks (initial scaffold for TASK-097).
 *
 * Focus:
 * - A01 Broken Access Control
 * - A03 Injection (invalid JSON handling)
 * - A07 Identification and Authentication Failures
 *
 * Usage:
 *   node test/security-regression.js
 *
 * Environment:
 *   API_URL                  default: http://localhost:18081
 *   DASHBOARD_AUTH_EMAIL     default: admin@example.com
 *   DASHBOARD_AUTH_PASSWORD  default: secret-pass
 */

const http = require("http");
const https = require("https");

const API_BASE = (process.env.API_URL || "http://localhost:18081").replace(/\/$/, "");
const ADMIN_EMAIL = process.env.DASHBOARD_AUTH_EMAIL || "admin@example.com";
const ADMIN_PASSWORD = process.env.DASHBOARD_AUTH_PASSWORD || "secret-pass";

function assert(cond, msg) {
  if (!cond) throw new Error(msg);
}

function request(method, path, body, token, rawJsonBody = false) {
  return new Promise((resolve, reject) => {
    const url = new URL(`${API_BASE}${path}`);
    const bodyStr = body === undefined ? undefined : (rawJsonBody ? body : JSON.stringify(body));

    const headers = { "Content-Type": "application/json" };
    if (token) headers.Authorization = `Bearer ${token}`;
    if (bodyStr) headers["Content-Length"] = Buffer.byteLength(bodyStr);

    const lib = url.protocol === "https:" ? https : http;
    const req = lib.request(
      {
        hostname: url.hostname,
        port: url.port || (url.protocol === "https:" ? 443 : 80),
        path: url.pathname + url.search,
        method,
        headers,
      },
      (res) => {
        let data = "";
        res.on("data", (chunk) => {
          data += chunk;
        });
        res.on("end", () => {
          let parsed = null;
          try {
            parsed = JSON.parse(data);
          } catch {
            // Keep parsed as null for non-JSON responses.
          }
          resolve({ status: res.statusCode, headers: res.headers, body: data, parsed });
        });
      }
    );

    req.on("error", reject);
    if (bodyStr) req.write(bodyStr);
    req.end();
  });
}

async function loginAsAdmin() {
  const resp = await request("POST", "/api/v1/auth/login", {
    email: ADMIN_EMAIL,
    password: ADMIN_PASSWORD,
  });
  assert(resp.status === 200, `admin login failed: HTTP ${resp.status}`);
  assert(resp.parsed && resp.parsed.session_id, "admin login response missing session_id");
  return resp.parsed.session_id;
}

async function createApiKey(sessionToken, role) {
  const now = Date.now();
  const payload = {
    label: `security-${role}-${now}`,
    partner_id: `security-partner-${now}`,
    role,
    rate_limit_per_min: 300,
  };
  const resp = await request("POST", "/api/v1/api-keys", payload, sessionToken);
  assert(resp.status === 201, `create API key (${role}) failed: HTTP ${resp.status}`);
  assert(resp.parsed && resp.parsed.key_secret, "API key create response missing key_secret");
  return resp.parsed.key_secret;
}

async function run() {
  const tests = [];

  function add(name, fn) {
    tests.push({ name, fn });
  }

  add("A07 unauthenticated access blocked", async () => {
    const resp = await request("GET", "/api/v1/accounts", undefined, undefined);
    assert(resp.status === 401, `expected 401, got ${resp.status}`);
    assert(resp.parsed && resp.parsed.error === "unauthorized", "expected unauthorized error payload");
  });

  add("A07 invalid bearer token denied", async () => {
    const resp = await request("GET", "/api/v1/accounts", undefined, "invalid-token");
    assert(resp.status === 401, `expected 401, got ${resp.status}`);
  });

  add("A03 malformed JSON rejected", async () => {
    const admin = await loginAsAdmin();
    const resp = await request(
      "POST",
      "/api/v1/transactions/deposit",
      "{ bad json",
      admin,
      true
    );
    assert(resp.status === 400, `expected 400, got ${resp.status}`);
    assert(resp.parsed && resp.parsed.error === "invalid_json", "expected invalid_json error payload");
  });

  add("A01 operations token blocked from admin boundary", async () => {
    const admin = await loginAsAdmin();
    const opsKey = await createApiKey(admin, "operations");
    const resp = await request("GET", "/api/v1/api-keys", undefined, opsKey);
    assert(resp.status === 403, `expected 403, got ${resp.status}`);
    assert(resp.parsed && resp.parsed.error === "forbidden", "expected forbidden error payload");
  });

  add("A01 read_only token blocked from write operation", async () => {
    const admin = await loginAsAdmin();
    const roKey = await createApiKey(admin, "read_only");
    const resp = await request(
      "POST",
      "/api/v1/transactions/deposit",
      { any: "payload" },
      roKey
    );
    assert(resp.status === 403, `expected 403, got ${resp.status}`);
  });

  add("A01 admin token allowed on admin boundary", async () => {
    const admin = await loginAsAdmin();
    const adminKey = await createApiKey(admin, "admin");
    const resp = await request("GET", "/api/v1/api-keys", undefined, adminKey);
    assert(resp.status === 200, `expected 200, got ${resp.status}`);
    assert(resp.parsed && Array.isArray(resp.parsed.items), "expected list API keys response shape");
  });

  let passed = 0;
  let failed = 0;

  console.log("\n=== Security Regression (API) ===\n");
  for (const t of tests) {
    process.stdout.write(`- ${t.name} ... `);
    try {
      await t.fn();
      passed += 1;
      console.log("PASS");
    } catch (err) {
      failed += 1;
      console.log("FAIL");
      console.log(`  ${err.message}`);
    }
  }

  console.log("\nSummary");
  console.log(`Passed: ${passed}`);
  console.log(`Failed: ${failed}`);

  if (failed > 0) {
    process.exit(1);
  }
}

run().catch((err) => {
  console.error("Fatal error:", err);
  process.exit(1);
});
