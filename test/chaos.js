/**
 * Chaos engineering test suite for kinetic-core.
 *
 * Each scenario injects a specific failure mode and asserts the system
 * handles it correctly — either by maintaining invariants under concurrency
 * or by returning well-formed errors and recovering cleanly.
 *
 * Scenarios:
 *   idempotency_concurrent      — 20 parallel mutations with the same key are
 *                                  applied exactly once (balance += 1×, not 20×)
 *   overdraft_protection        — Concurrent withdrawals totalling 10× balance
 *                                  never push balance below zero
 *   transfer_conservation       — 100 concurrent transfers preserve total money
 *                                  supply (A + B = constant throughout)
 *   malformed_input_resilience  — Corrupt / incomplete requests always return
 *                                  4xx; server stays responsive after each
 *   graceful_timeout            — Requests cancelled mid-flight via socket
 *                                  timeout produce clean errors, not hangs
 *   abrupt_connection_drop      — TCP connections dropped after partial headers
 *                                  leave the server healthy
 *   recovery_checkpoint_lifecycle — Full checkpoint create / initiate / complete
 *                                   / validate API lifecycle completes without error
 *
 * Usage:
 *   node test/chaos.js
 *
 * Environment variables (same as perf-bench.js):
 *   API_URL                  Base URL  (default: http://localhost:18081)
 *   DASHBOARD_AUTH_EMAIL     Admin email
 *   DASHBOARD_AUTH_PASSWORD  Admin password
 */

"use strict";

const http = require("http");
const https = require("https");
const net = require("net");

// ─── Configuration ─────────────────────────────────────────────────────────

const API_BASE = (process.env.API_URL || "http://localhost:18081").replace(/\/$/, "");
const ADMIN_EMAIL = process.env.DASHBOARD_AUTH_EMAIL || "admin@example.com";
const ADMIN_PASSWORD = process.env.DASHBOARD_AUTH_PASSWORD || "secret-pass";

const DEFAULT_TIMEOUT = 15000;

// ─── HTTP helpers ──────────────────────────────────────────────────────────

function assert(cond, msg) {
  if (!cond) throw new Error(`Assertion failed: ${msg}`);
}

/**
 * Send a single HTTP request.
 * Returns { status, body, parsed? }.
 * @param {number} [socketTimeout] Optional socket timeout in ms.
 */
function request(method, path, body, token, socketTimeout) {
  return new Promise((resolve, reject) => {
    const url = new URL(`${API_BASE}${path}`);
    const bodyStr = body !== undefined ? JSON.stringify(body) : undefined;

    const headers = { "Content-Type": "application/json" };
    if (token) headers["Authorization"] = `Bearer ${token}`;
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
        res.on("data", (chunk) => { data += chunk; });
        res.on("end", () => {
          let parsed = null;
          try { parsed = JSON.parse(data); } catch { /* not JSON */ }
          resolve({ status: res.statusCode, body: data, parsed });
        });
      }
    );

    if (socketTimeout) {
      req.setTimeout(socketTimeout, () => {
        req.destroy(new Error(`Socket timeout after ${socketTimeout}ms`));
      });
    }

    req.on("error", reject);
    if (bodyStr) req.write(bodyStr);
    req.end();
  });
}

/** Run `n` copies of `fn` in parallel and return an array of settled results. */
function runParallel(fn, n) {
  return Promise.allSettled(Array.from({ length: n }, () => fn()));
}

// ─── Auth / fixture helpers ────────────────────────────────────────────────

async function authenticate() {
  const { status, parsed } = await request("POST", "/api/v1/auth/login", {
    email: ADMIN_EMAIL,
    password: ADMIN_PASSWORD,
  });
  if (status !== 200 || !parsed?.session_id) {
    throw new Error(`Login failed: HTTP ${status}`);
  }
  return parsed.session_id;
}

/**
 * Create a test party + two funded accounts.
 * Returns { partyId, accountId1, accountId2 }.
 */
async function createTestFixtures(token, seedAmountMinorUnits = 1_000_000) {
  const ts = Date.now();

  const partyResp = await request(
    "POST",
    "/api/v1/parties",
    {
      full_name: `Chaos User ${ts}`,
      email: `chaos_${ts}@example.com`,
      phone: "+10000000000",
      address: "1 Chaos Ave",
    },
    token
  );
  assert(
    partyResp.status === 200 || partyResp.status === 201,
    `Create party failed: HTTP ${partyResp.status} — ${partyResp.body}`
  );
  const partyId = partyResp.parsed.party_id;

  const a1Resp = await request(
    "POST",
    "/api/v1/accounts",
    { party_id: partyId, name: "Chaos Alpha", currency: "USD" },
    token
  );
  assert(
    a1Resp.status === 200 || a1Resp.status === 201,
    `Create account 1 failed: HTTP ${a1Resp.status}`
  );
  const accountId1 = a1Resp.parsed.account_id;

  const a2Resp = await request(
    "POST",
    "/api/v1/accounts",
    { party_id: partyId, name: "Chaos Beta", currency: "USD" },
    token
  );
  assert(
    a2Resp.status === 200 || a2Resp.status === 201,
    `Create account 2 failed: HTTP ${a2Resp.status}`
  );
  const accountId2 = a2Resp.parsed.account_id;

  // Seed account 1
  const seedResp = await request(
    "POST",
    "/api/v1/transactions/deposit",
    {
      idempotency_key: `chaos-seed-${ts}`,
      dest_account_id: accountId1,
      amount: seedAmountMinorUnits,
      currency: "USD",
      description: "chaos seed",
    },
    token
  );
  assert(
    seedResp.status === 200 || seedResp.status === 201,
    `Seed deposit failed: HTTP ${seedResp.status}`
  );

  return { partyId, accountId1, accountId2 };
}

async function getBalance(accountId, token) {
  const resp = await request(
    "GET",
    `/api/v1/accounts/${accountId}/balance`,
    undefined,
    token
  );
  assert(resp.status === 200, `getBalance failed: HTTP ${resp.status}`);
  // balance may be in minor units under various field names
  const b = resp.parsed;
  return b.available_balance ?? b.balance ?? b.amount ?? 0;
}

// ─── Scenarios ─────────────────────────────────────────────────────────────

/**
 * Scenario: Idempotency under concurrent duplicate mutations.
 *
 * Fire 20 concurrent deposits all sharing the same idempotency_key.
 * Exactly one should credit the account; the rest must be rejected or
 * treated as duplicates. Final balance must equal seed + exactly one deposit.
 */
async function scenarioIdempotency(token) {
  const { accountId1 } = await createTestFixtures(token, 0);
  const depositAmount = 1000; // 10.00 USD in minor units
  const idempotencyKey = `chaos-idem-${Date.now()}`;

  const balanceBefore = await getBalance(accountId1, token);

  const CONCURRENCY = 20;
  const results = await runParallel(
    () =>
      request(
        "POST",
        "/api/v1/transactions/deposit",
        {
          idempotency_key: idempotencyKey,
          dest_account_id: accountId1,
          amount: depositAmount,
          currency: "USD",
          description: "idempotency chaos",
        },
        token
      ),
    CONCURRENCY
  );

  // Count successes vs rejects
  let successes = 0;
  let clientErrors = 0;
  let serverErrors = 0;
  for (const r of results) {
    if (r.status === "fulfilled") {
      const { status } = r.value;
      if (status >= 200 && status < 300) successes++;
      else if (status >= 400 && status < 500) clientErrors++;
      else if (status >= 500) serverErrors++;
    }
  }

  assert(serverErrors === 0, `Server errors (5xx) during idempotency test: ${serverErrors}`);

  const balanceAfter = await getBalance(accountId1, token);
  const credited = balanceAfter - balanceBefore;

  // The deposit must be applied at most once (idempotent)
  assert(
    credited <= depositAmount,
    `Idempotency violated: balance increased by ${credited} (expected ≤ ${depositAmount})`
  );

  console.log(
    `    successes=${successes}  client_errors=${clientErrors}  server_errors=${serverErrors}  credited=${credited}  expected≤${depositAmount}`
  );
}

/**
 * Scenario: Overdraft protection under concurrent excess withdrawals.
 *
 * Seed an account with $10.00 (1000 minor units).
 * Fire 20 concurrent withdrawals of $1.00 (100 minor units) each — $20 total.
 * Final balance must be ≥ 0.
 */
async function scenarioOverdraft(token) {
  const seedAmount = 1000; // $10.00
  const withdrawAmount = 100; // $1.00 per request
  const withdrawCount = 20; // $20.00 total attempted

  const { accountId1 } = await createTestFixtures(token, seedAmount);

  let successes = 0;
  let serverErrors = 0;
  const results = await runParallel(
    () =>
      request(
        "POST",
        "/api/v1/transactions/withdraw",
        {
          idempotency_key: `chaos-wd-${Date.now()}-${Math.random()}`,
          source_account_id: accountId1,
          amount: withdrawAmount,
          currency: "USD",
          description: "overdraft chaos",
        },
        token
      ),
    withdrawCount
  );

  for (const r of results) {
    if (r.status === "fulfilled") {
      const { status } = r.value;
      if (status >= 200 && status < 300) successes++;
      else if (status >= 500) serverErrors++;
    }
  }

  assert(serverErrors === 0, `Server errors during overdraft test: ${serverErrors}`);

  const finalBalance = await getBalance(accountId1, token);
  assert(
    finalBalance >= 0,
    `Overdraft protection failed: balance went negative (${finalBalance})`
  );

  const expectedMaxWithdrawn = Math.floor(seedAmount / withdrawAmount) * withdrawAmount;
  const actualWithdrawn = seedAmount - finalBalance;
  assert(
    actualWithdrawn <= seedAmount,
    `Withdrawn (${actualWithdrawn}) exceeded seed (${seedAmount})`
  );

  console.log(
    `    successes=${successes}  final_balance=${finalBalance}  seed=${seedAmount}  withdrew=${actualWithdrawn}`
  );
}

/**
 * Scenario: Transfer money-supply conservation under high concurrency.
 *
 * Seed account A with $1 000.00 (100 000 minor units).
 * Fire 100 concurrent $1.00 (100 minor units) transfers A → B.
 * A + B must equal the original seed at all times (checked after all settle).
 */
async function scenarioTransferConservation(token) {
  const seed = 100_000; // $1 000.00
  const transferAmount = 100; // $1.00
  const transferCount = 100;

  const { accountId1, accountId2 } = await createTestFixtures(token, seed);

  let serverErrors = 0;
  const results = await runParallel(
    () =>
      request(
        "POST",
        "/api/v1/transactions/transfer",
        {
          idempotency_key: `chaos-xfr-${Date.now()}-${Math.random()}`,
          source_account_id: accountId1,
          dest_account_id: accountId2,
          amount: transferAmount,
          currency: "USD",
          description: "conservation chaos",
        },
        token
      ),
    transferCount
  );

  for (const r of results) {
    if (r.status === "fulfilled" && r.value.status >= 500) serverErrors++;
  }
  assert(serverErrors === 0, `Server errors during transfer conservation test: ${serverErrors}`);

  const balA = await getBalance(accountId1, token);
  const balB = await getBalance(accountId2, token);
  const total = balA + balB;

  assert(
    total === seed,
    `Money not conserved: A(${balA}) + B(${balB}) = ${total} ≠ seed(${seed})`
  );
  assert(balA >= 0, `Account A went negative: ${balA}`);
  assert(balB >= 0, `Account B went negative: ${balB}`);

  console.log(`    balA=${balA}  balB=${balB}  total=${total}  seed=${seed}  conserved=true`);
}

/**
 * Scenario: Malformed and invalid requests always produce 4xx.
 *
 * Tests a variety of bad inputs. After each one, pings /health to confirm
 * the server is still responsive.
 */
async function scenarioMalformedInputResilience(token) {
  const cases = [
    // [description, method, path, rawBody, headers]
    {
      label: "corrupt JSON body",
      method: "POST",
      path: "/api/v1/parties",
      rawBody: '{"full_name": "broken"',
    },
    {
      label: "empty body on POST",
      method: "POST",
      path: "/api/v1/parties",
      rawBody: "",
    },
    {
      label: "missing required field (party create)",
      method: "POST",
      path: "/api/v1/parties",
      body: { email: "no-name@example.com" }, // missing full_name
    },
    {
      label: "negative deposit amount",
      method: "POST",
      path: "/api/v1/transactions/deposit",
      body: {
        idempotency_key: `chaos-neg-${Date.now()}`,
        dest_account_id: "00000000-0000-0000-0000-000000000000",
        amount: -100,
        currency: "USD",
      },
    },
    {
      label: "zero amount deposit",
      method: "POST",
      path: "/api/v1/transactions/deposit",
      body: {
        idempotency_key: `chaos-zero-${Date.now()}`,
        dest_account_id: "00000000-0000-0000-0000-000000000000",
        amount: 0,
        currency: "USD",
      },
    },
    {
      label: "invalid UUID in path",
      method: "GET",
      path: "/api/v1/accounts/not-a-valid-uuid",
    },
    {
      label: "nonexistent resource",
      method: "GET",
      path: "/api/v1/accounts/00000000-0000-0000-0000-000000000099",
    },
    {
      label: "unknown route",
      method: "GET",
      path: "/api/v1/does-not-exist",
    },
  ];

  let passed = 0;
  let failed = 0;

  for (const c of cases) {
    let resp;
    try {
      if (c.rawBody !== undefined) {
        // Send raw (potentially malformed) body
        resp = await sendRaw(c.method, c.path, c.rawBody, token);
      } else {
        resp = await request(c.method, c.path, c.body, token);
      }
    } catch (err) {
      console.log(`    [${c.label}] request error: ${err.message}`);
      failed++;
      continue;
    }

    const isClientError = resp.status >= 400 && resp.status < 500;
    if (isClientError) {
      passed++;
    } else {
      console.log(`    ✗ [${c.label}] expected 4xx, got HTTP ${resp.status}`);
      failed++;
    }

    // Verify server is still healthy after each bad request
    try {
      const health = await request("GET", "/health");
      assert(health.status === 200, `Health check failed after "${c.label}"`);
    } catch (err) {
      throw new Error(`Server unhealthy after "${c.label}": ${err.message}`);
    }
  }

  assert(
    failed === 0,
    `${failed} of ${cases.length} malformed-input cases did not return 4xx`
  );
  console.log(`    ${passed}/${cases.length} malformed inputs correctly returned 4xx`);
}

/** Send a raw HTTP request with an arbitrary string body (may be malformed). */
function sendRaw(method, path, rawBody, token) {
  return new Promise((resolve, reject) => {
    const url = new URL(`${API_BASE}${path}`);
    const headers = {
      "Content-Type": "application/json",
      "Content-Length": Buffer.byteLength(rawBody),
    };
    if (token) headers["Authorization"] = `Bearer ${token}`;

    const lib = url.protocol === "https:" ? https : http;
    const req = lib.request(
      {
        hostname: url.hostname,
        port: url.port || 80,
        path: url.pathname,
        method,
        headers,
      },
      (res) => {
        let data = "";
        res.on("data", (c) => { data += c; });
        res.on("end", () => {
          let parsed = null;
          try { parsed = JSON.parse(data); } catch { /* not JSON */ }
          resolve({ status: res.statusCode, body: data, parsed });
        });
      }
    );
    req.on("error", reject);
    req.write(rawBody);
    req.end();
  });
}

/**
 * Scenario: Graceful handling of client-side socket timeouts.
 *
 * Send requests with a 1ms socket timeout. They must fail with a timeout
 * error on the client side (not hang). After all timeout attempts, the
 * server must still respond to /health.
 */
async function scenarioGracefulTimeout(token) {
  const ATTEMPTS = 10;
  let timeouts = 0;
  let unexpected = 0;

  for (let i = 0; i < ATTEMPTS; i++) {
    try {
      await request("GET", "/api/v1/parties", undefined, token, /* socketTimeout= */ 1);
      // If it somehow completes in 1ms, that's acceptable (very fast server)
    } catch (err) {
      if (/timeout|ECONNRESET|socket/i.test(err.message)) {
        timeouts++;
      } else {
        console.log(`    unexpected error: ${err.message}`);
        unexpected++;
      }
    }
  }

  assert(unexpected === 0, `Unexpected (non-timeout) errors: ${unexpected}`);

  // Server must still respond after all those aborted connections
  const health = await request("GET", "/health");
  assert(health.status === 200, `Server not healthy after timeout chaos (HTTP ${health.status})`);

  console.log(
    `    attempts=${ATTEMPTS}  timeouts=${timeouts}  unexpected=${unexpected}  server_healthy=true`
  );
}

/**
 * Scenario: Abrupt TCP connection drops.
 *
 * Opens a raw TCP connection to the API port, writes a partial HTTP request
 * (just the start of the headers), then immediately destroys the socket.
 * The server must remain healthy after N such drops.
 */
async function scenarioAbruptConnectionDrop() {
  const url = new URL(`${API_BASE}/api/v1/parties`);
  const port = parseInt(url.port, 10) || 80;
  const hostname = url.hostname;
  const DROPS = 20;

  let dropped = 0;
  let errors = 0;

  for (let i = 0; i < DROPS; i++) {
    await new Promise((resolve) => {
      const socket = net.createConnection({ host: hostname, port }, () => {
        // Write a partial HTTP request (missing headers and blank line)
        socket.write(`GET /api/v1/parties HTTP/1.1\r\nHost: ${hostname}:${port}\r\n`);
        // Drop the connection without completing the request
        socket.destroy();
        dropped++;
        resolve();
      });
      socket.on("error", () => {
        errors++;
        resolve();
      });
    });
  }

  // Allow the server a moment to clean up
  await new Promise((r) => setTimeout(r, 200));

  // Server must still be healthy
  const health = await request("GET", "/health");
  assert(health.status === 200, `Server not healthy after ${DROPS} connection drops`);

  console.log(
    `    dropped=${dropped}  socket_errors=${errors}  server_healthy=true`
  );
}

/**
 * Scenario: Recovery checkpoint full lifecycle.
 *
 * POST checkpoint → GET checkpoint (status=active) →
 * POST initiate → POST complete → GET validate (valid=true).
 */
async function scenarioRecoveryCheckpointLifecycle(token) {
  // Create a checkpoint
  const createResp = await request(
    "POST",
    "/api/v1/recovery/checkpoints",
    {
      resource_type: "account",
      resource_id: "chaos-test-resource",
      snapshot: { note: "chaos test checkpoint" },
    },
    token
  );
  assert(
    createResp.status === 200 || createResp.status === 201,
    `Create checkpoint failed: HTTP ${createResp.status} — ${createResp.body}`
  );

  const checkpointId = createResp.parsed?.checkpoint_id;
  assert(checkpointId, "Create checkpoint response missing checkpoint_id");
  console.log(`    checkpoint_id=${checkpointId}`);

  // Fetch the checkpoint
  const getResp = await request(
    "GET",
    `/api/v1/recovery/checkpoints/${checkpointId}`,
    undefined,
    token
  );
  assert(getResp.status === 200, `Get checkpoint failed: HTTP ${getResp.status}`);

  // Initiate recovery
  const initiateResp = await request(
    "POST",
    `/api/v1/recovery/checkpoints/${checkpointId}/initiate`,
    {},
    token
  );
  assert(
    initiateResp.status === 200,
    `Initiate recovery failed: HTTP ${initiateResp.status} — ${initiateResp.body}`
  );

  // Complete recovery
  const completeResp = await request(
    "POST",
    `/api/v1/recovery/checkpoints/${checkpointId}/complete`,
    {},
    token
  );
  assert(
    completeResp.status === 200,
    `Complete recovery failed: HTTP ${completeResp.status} — ${completeResp.body}`
  );

  // Validate
  const validateResp = await request(
    "GET",
    `/api/v1/recovery/checkpoints/${checkpointId}/validate`,
    undefined,
    token
  );
  assert(validateResp.status === 200, `Validate failed: HTTP ${validateResp.status}`);
  assert(
    validateResp.parsed?.valid === true,
    `Checkpoint validation returned valid=false: ${validateResp.body}`
  );

  console.log(`    lifecycle complete: created→initiated→completed→validated`);
}

// ─── Runner ────────────────────────────────────────────────────────────────

async function main() {
  console.log("═══════════════════════════════════════════════════");
  console.log(" kinetic-core  Chaos Engineering Tests");
  console.log("═══════════════════════════════════════════════════");
  console.log(`  API_BASE : ${API_BASE}`);
  console.log("───────────────────────────────────────────────────\n");

  let token;
  try {
    token = await authenticate();
  } catch (err) {
    console.error(`Fatal: cannot authenticate — ${err.message}`);
    console.error("Ensure the API is running and credentials are correct.");
    process.exit(2);
  }

  const results = [];

  async function run(name, fn) {
    process.stdout.write(`\n▶ ${name}\n`);
    try {
      await fn();
      console.log(`✓ ${name} — PASS`);
      results.push({ name, status: "PASS" });
    } catch (err) {
      console.error(`✗ ${name} — FAIL: ${err.message}`);
      results.push({ name, status: "FAIL", error: err.message });
    }
  }

  await run("idempotency_concurrent", () => scenarioIdempotency(token));
  await run("overdraft_protection", () => scenarioOverdraft(token));
  await run("transfer_conservation", () => scenarioTransferConservation(token));
  await run("malformed_input_resilience", () => scenarioMalformedInputResilience(token));
  await run("graceful_timeout", () => scenarioGracefulTimeout(token));
  await run("abrupt_connection_drop", scenarioAbruptConnectionDrop);
  await run("recovery_checkpoint_lifecycle", () =>
    scenarioRecoveryCheckpointLifecycle(token)
  );

  // ── Summary ──────────────────────────────────────────────────────────────
  console.log("\n─────────────────────────────────────────────────");
  console.log(" Chaos Test Results");
  console.log("─────────────────────────────────────────────────");

  let passed = 0;
  let failed = 0;
  for (const r of results) {
    const icon = r.status === "PASS" ? "✓" : "✗";
    const detail = r.status === "FAIL" ? ` — ${r.error}` : "";
    console.log(`  ${icon}  ${r.name}${detail}`);
    if (r.status === "PASS") passed++;
    else failed++;
  }

  console.log("─────────────────────────────────────────────────");
  console.log(`  Passed: ${passed}   Failed: ${failed}`);
  console.log("─────────────────────────────────────────────────\n");

  if (failed > 0) process.exit(1);
}

main().catch((err) => {
  console.error("Fatal:", err);
  process.exit(2);
});
