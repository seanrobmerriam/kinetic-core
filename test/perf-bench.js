/**
 * Performance benchmarking suite for the kinetic-core backend API.
 *
 * Measures p50/p95/p99 latency and throughput (req/s) for critical endpoints.
 * Reports threshold violations. Exits 1 when any p99 or rps threshold is
 * breached and BENCH_STRICT=1.
 *
 * Setup phase creates isolated test fixtures (one party + two accounts) that
 * are used by mutation benchmarks so they can run against real data without
 * cross-contaminating production state.
 *
 * Usage:
 *   node test/perf-bench.js
 *
 * Environment variables:
 *   API_URL                  Base URL for the API (default: http://localhost:18081)
 *   DASHBOARD_AUTH_EMAIL     Admin email  (default: admin@example.com)
 *   DASHBOARD_AUTH_PASSWORD  Admin password (default: secret-pass)
 *   BENCH_CONCURRENCY        Parallel request workers (default: 10)
 *   BENCH_ITERATIONS         Requests per benchmark (default: 100)
 *   BENCH_WARMUP             Warmup requests before measurement (default: 10)
 *   BENCH_STRICT             Exit 1 on threshold breach when set to "1"
 *   T_HEALTH_P99             p99 threshold (ms) for /health (default: 50)
 *   T_READ_P99               p99 threshold (ms) for list reads (default: 200)
 *   T_WRITE_P99              p99 threshold (ms) for mutations (default: 500)
 *   T_LEDGER_P99             p99 threshold (ms) for ledger queries (default: 1000)
 *   T_HEALTH_RPS             min req/s for /health (default: 200)
 *   T_READ_RPS               min req/s for list reads (default: 50)
 *   T_WRITE_RPS              min req/s for mutations (default: 20)
 *   T_LEDGER_RPS             min req/s for ledger queries (default: 10)
 */

"use strict";

const http = require("http");
const https = require("https");

// ─── Configuration ─────────────────────────────────────────────────────────

const API_BASE = (process.env.API_URL || "http://localhost:18081").replace(/\/$/, "");
const ADMIN_EMAIL = process.env.DASHBOARD_AUTH_EMAIL || "admin@example.com";
const ADMIN_PASSWORD = process.env.DASHBOARD_AUTH_PASSWORD || "secret-pass";
const CONCURRENCY = Math.max(1, parseInt(process.env.BENCH_CONCURRENCY || "10", 10));
const ITERATIONS = Math.max(1, parseInt(process.env.BENCH_ITERATIONS || "100", 10));
const WARMUP_COUNT = Math.max(0, parseInt(process.env.BENCH_WARMUP || "10", 10));
const STRICT = process.env.BENCH_STRICT === "1";

// Thresholds: p99_ms (max allowed p99 latency) and rps (minimum throughput)
const T = {
  health: {
    p99_ms: parseInt(process.env.T_HEALTH_P99 || "50", 10),
    rps: parseFloat(process.env.T_HEALTH_RPS || "200"),
  },
  read: {
    p99_ms: parseInt(process.env.T_READ_P99 || "200", 10),
    rps: parseFloat(process.env.T_READ_RPS || "50"),
  },
  write: {
    p99_ms: parseInt(process.env.T_WRITE_P99 || "500", 10),
    rps: parseFloat(process.env.T_WRITE_RPS || "20"),
  },
  ledger: {
    p99_ms: parseInt(process.env.T_LEDGER_P99 || "1000", 10),
    rps: parseFloat(process.env.T_LEDGER_RPS || "10"),
  },
};

// ─── HTTP helpers ──────────────────────────────────────────────────────────

/**
 * Send a single HTTP request.
 * Returns { latency_ms, status, body }.
 */
function request(method, path, body, token) {
  return new Promise((resolve, reject) => {
    const url = new URL(`${API_BASE}${path}`);
    const bodyStr = body !== undefined ? JSON.stringify(body) : undefined;

    const headers = { "Content-Type": "application/json" };
    if (token) headers["Authorization"] = `Bearer ${token}`;
    if (bodyStr) headers["Content-Length"] = Buffer.byteLength(bodyStr);

    const lib = url.protocol === "https:" ? https : http;
    const start = process.hrtime.bigint();

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
          const latency_ms = Number(process.hrtime.bigint() - start) / 1e6;
          resolve({ latency_ms, status: res.statusCode, body: data });
        });
      }
    );

    req.on("error", reject);
    if (bodyStr) req.write(bodyStr);
    req.end();
  });
}

/**
 * Run `total` invocations of `fn` with `concurrency` parallel workers.
 * Returns { latencies, completed, errors }.
 */
async function runBatch(fn, total, concurrency) {
  const latencies = [];
  let errors = 0;
  let remaining = total;

  // Split into batches of `concurrency`
  while (remaining > 0) {
    const batchSize = Math.min(remaining, concurrency);
    const results = await Promise.allSettled(
      Array.from({ length: batchSize }, () => fn())
    );
    for (const r of results) {
      if (r.status === "fulfilled") {
        latencies.push(r.value.latency_ms);
      } else {
        errors++;
      }
    }
    remaining -= batchSize;
  }

  return { latencies, completed: latencies.length, errors };
}

// ─── Statistics ────────────────────────────────────────────────────────────

function percentile(sorted, p) {
  if (sorted.length === 0) return 0;
  const idx = Math.ceil((p / 100) * sorted.length) - 1;
  return sorted[Math.max(0, idx)];
}

function computeStats(latencies) {
  const sorted = [...latencies].sort((a, b) => a - b);
  const sum = sorted.reduce((acc, v) => acc + v, 0);
  return {
    count: sorted.length,
    min: Math.round(sorted[0] ?? 0),
    max: Math.round(sorted[sorted.length - 1] ?? 0),
    mean: Math.round(sum / (sorted.length || 1)),
    p50: Math.round(percentile(sorted, 50)),
    p95: Math.round(percentile(sorted, 95)),
    p99: Math.round(percentile(sorted, 99)),
  };
}

// ─── Benchmark runner ──────────────────────────────────────────────────────

/**
 * Benchmark a single endpoint.
 * @param {string}   name       Display name (e.g. "GET /health")
 * @param {Function} fn         Async function that executes one request; must
 *                               return { latency_ms, status }.
 * @param {{ p99_ms: number, rps: number }} threshold
 * @returns {{ name, stats, rps, errors, violations }}
 */
async function bench(name, fn, threshold) {
  process.stdout.write(`\n  ▶ ${name}\n`);

  // Warmup
  if (WARMUP_COUNT > 0) {
    process.stdout.write(`    warmup (${WARMUP_COUNT})...`);
    await runBatch(fn, WARMUP_COUNT, Math.min(WARMUP_COUNT, CONCURRENCY));
    process.stdout.write(" done\n");
  }

  // Measurement
  process.stdout.write(
    `    measuring (n=${ITERATIONS}, concurrency=${CONCURRENCY})...`
  );
  const wallStart = Date.now();
  const { latencies, completed, errors } = await runBatch(fn, ITERATIONS, CONCURRENCY);
  const elapsed_s = (Date.now() - wallStart) / 1000;
  process.stdout.write(" done\n");

  const s = computeStats(latencies);
  const rps = completed / elapsed_s;

  // Check thresholds
  const violations = [];
  if (threshold && s.p99 > threshold.p99_ms) {
    violations.push(`p99 ${s.p99}ms > threshold ${threshold.p99_ms}ms`);
  }
  if (threshold && rps < threshold.rps) {
    violations.push(`rps ${rps.toFixed(1)} < threshold ${threshold.rps}`);
  }

  // Print results
  const badge = violations.length > 0 ? "⚠" : "✓";
  console.log(
    `    ${badge} min=${s.min}ms  mean=${s.mean}ms  p50=${s.p50}ms  p95=${s.p95}ms  p99=${s.p99}ms  max=${s.max}ms`
  );
  console.log(
    `      rps=${rps.toFixed(1)}  completed=${completed}  errors=${errors}  elapsed=${elapsed_s.toFixed(2)}s`
  );
  if (violations.length > 0) {
    for (const v of violations) {
      console.log(`    ✗ THRESHOLD BREACH: ${v}`);
    }
  }
  if (threshold) {
    console.log(
      `      thresholds: p99≤${threshold.p99_ms}ms  rps≥${threshold.rps}`
    );
  }

  return { name, stats: s, rps, errors, violations };
}

// ─── Setup: create isolated test fixtures ──────────────────────────────────

/**
 * Log in and return a session token.
 */
async function authenticate() {
  console.log("  Authenticating...");
  const { status, body } = await request("POST", "/api/v1/auth/login", {
    email: ADMIN_EMAIL,
    password: ADMIN_PASSWORD,
  });
  if (status !== 200) {
    throw new Error(`Login failed with HTTP ${status}: ${body}`);
  }
  const parsed = JSON.parse(body);
  const token = parsed.session_id;
  if (!token) {
    throw new Error("Login response missing session_id");
  }
  console.log("  Authentication OK");
  return token;
}

/**
 * Create a test party and two checking accounts.
 * Returns { partyId, accountId1, accountId2 }.
 */
async function setupFixtures(token) {
  console.log("  Creating benchmark fixtures...");
  const ts = Date.now();

  // Create party
  const partyResp = await request(
    "POST",
    "/api/v1/parties",
    {
      full_name: `Bench User ${ts}`,
      email: `bench_${ts}@example.com`,
      phone: "+10000000000",
      address: "1 Bench St",
    },
    token
  );
  if (partyResp.status !== 201 && partyResp.status !== 200) {
    throw new Error(
      `Failed to create bench party: HTTP ${partyResp.status} — ${partyResp.body}`
    );
  }
  const party = JSON.parse(partyResp.body);
  const partyId = party.party_id;

  // Create account 1
  const acct1Resp = await request(
    "POST",
    "/api/v1/accounts",
    { party_id: partyId, name: "Bench Alpha", currency: "USD" },
    token
  );
  if (acct1Resp.status !== 201 && acct1Resp.status !== 200) {
    throw new Error(
      `Failed to create bench account 1: HTTP ${acct1Resp.status} — ${acct1Resp.body}`
    );
  }
  const accountId1 = JSON.parse(acct1Resp.body).account_id;

  // Seed account 1 with funds so withdrawals and transfers don't fail
  await request(
    "POST",
    "/api/v1/transactions/deposit",
    {
      idempotency_key: `bench-seed-${ts}`,
      dest_account_id: accountId1,
      amount: 100000000, // 1 000 000.00 USD in minor units
      currency: "USD",
      description: "bench seed deposit",
    },
    token
  );

  // Create account 2
  const acct2Resp = await request(
    "POST",
    "/api/v1/accounts",
    { party_id: partyId, name: "Bench Beta", currency: "USD" },
    token
  );
  if (acct2Resp.status !== 201 && acct2Resp.status !== 200) {
    throw new Error(
      `Failed to create bench account 2: HTTP ${acct2Resp.status} — ${acct2Resp.body}`
    );
  }
  const accountId2 = JSON.parse(acct2Resp.body).account_id;

  console.log(
    `  Fixtures: party=${partyId}  acct1=${accountId1}  acct2=${accountId2}`
  );
  return { partyId, accountId1, accountId2 };
}

// ─── Main ──────────────────────────────────────────────────────────────────

async function main() {
  console.log("═══════════════════════════════════════════════════");
  console.log(" kinetic-core  API Performance Benchmark");
  console.log("═══════════════════════════════════════════════════");
  console.log(`  API_BASE     : ${API_BASE}`);
  console.log(`  CONCURRENCY  : ${CONCURRENCY}`);
  console.log(`  ITERATIONS   : ${ITERATIONS}`);
  console.log(`  WARMUP       : ${WARMUP_COUNT}`);
  console.log(`  STRICT       : ${STRICT}`);
  console.log("───────────────────────────────────────────────────");

  // ── Setup ────────────────────────────────────────────────────────────────
  let token;
  try {
    token = await authenticate();
  } catch (err) {
    console.error(`\nFatal: cannot authenticate — ${err.message}`);
    console.error("Ensure the API is running and credentials are correct.");
    process.exit(2);
  }

  let fixtures;
  try {
    fixtures = await setupFixtures(token);
  } catch (err) {
    console.error(`\nFatal: fixture setup failed — ${err.message}`);
    process.exit(2);
  }

  const { accountId1, accountId2 } = fixtures;

  // ── Benchmarks ───────────────────────────────────────────────────────────
  console.log("\n─ Benchmarks ───────────────────────────────────────");

  const results = [];
  let idCounter = 0;

  async function run(name, fn, threshold) {
    const result = await bench(name, fn, threshold);
    results.push(result);
  }

  // 1. Health — unauthenticated, baseline
  await run(
    "GET /health",
    () => request("GET", "/health"),
    T.health
  );

  // 2. List parties — authenticated read
  await run(
    "GET /api/v1/parties",
    () => request("GET", "/api/v1/parties", undefined, token),
    T.read
  );

  // 3. List accounts — authenticated read
  await run(
    "GET /api/v1/accounts",
    () => request("GET", "/api/v1/accounts", undefined, token),
    T.read
  );

  // 4. Get single account — authenticated read (point lookup)
  await run(
    "GET /api/v1/accounts/:id",
    () => request("GET", `/api/v1/accounts/${accountId1}`, undefined, token),
    T.read
  );

  // 5. Account balance — authenticated read
  await run(
    "GET /api/v1/accounts/:id/balance",
    () => request("GET", `/api/v1/accounts/${accountId1}/balance`, undefined, token),
    T.read
  );

  // 6. Deposit — authenticated write (mutation)
  await run(
    "POST /api/v1/transactions/deposit",
    () => {
      idCounter++;
      return request(
        "POST",
        "/api/v1/transactions/deposit",
        {
          idempotency_key: `bench-dep-${Date.now()}-${idCounter}`,
          dest_account_id: accountId1,
          amount: 100,
          currency: "USD",
          description: "bench deposit",
        },
        token
      );
    },
    T.write
  );

  // 7. Transfer — authenticated write (two-account mutation)
  await run(
    "POST /api/v1/transactions/transfer",
    () => {
      idCounter++;
      return request(
        "POST",
        "/api/v1/transactions/transfer",
        {
          idempotency_key: `bench-xfr-${Date.now()}-${idCounter}`,
          source_account_id: accountId1,
          dest_account_id: accountId2,
          amount: 1,
          currency: "USD",
          description: "bench transfer",
        },
        token
      );
    },
    T.write
  );

  // 8. General ledger — authenticated heavy read
  await run(
    "GET /api/v1/ledger/general-ledger",
    () =>
      request(
        "GET",
        "/api/v1/ledger/general-ledger?page_size=20",
        undefined,
        token
      ),
    T.ledger
  );

  // 9. Trial balance — authenticated aggregation read
  await run(
    "GET /api/v1/ledger/trial-balance",
    () =>
      request(
        "GET",
        "/api/v1/ledger/trial-balance?currency=USD",
        undefined,
        token
      ),
    T.ledger
  );

  // ── Summary ──────────────────────────────────────────────────────────────
  console.log("\n═══════════════════════════════════════════════════");
  console.log(" Summary");
  console.log("═══════════════════════════════════════════════════");
  console.log(
    padR("Endpoint", 46) +
      padL("p99(ms)", 9) +
      padL("rps", 8) +
      "  Status"
  );
  console.log("─".repeat(72));

  let totalViolations = 0;
  for (const r of results) {
    const status = r.violations.length > 0 ? `⚠ ${r.violations.join("; ")}` : "✓ pass";
    console.log(
      padR(r.name, 46) +
        padL(String(r.stats.p99), 9) +
        padL(r.rps.toFixed(1), 8) +
        `  ${status}`
    );
    totalViolations += r.violations.length;
  }

  console.log("─".repeat(72));
  console.log(
    `\n  Benchmarks run: ${results.length}   Threshold violations: ${totalViolations}`
  );

  if (totalViolations > 0) {
    console.log(
      STRICT
        ? "\n  STRICT mode: exiting 1 due to threshold violations."
        : "\n  (Run with BENCH_STRICT=1 to fail on threshold violations.)"
    );
  }

  console.log("═══════════════════════════════════════════════════\n");

  if (STRICT && totalViolations > 0) {
    process.exit(1);
  }
}

function padR(str, len) {
  return String(str).padEnd(len, " ").slice(0, len);
}

function padL(str, len) {
  return String(str).padStart(len, " ").slice(-len);
}

main().catch((err) => {
  console.error("Fatal:", err);
  process.exit(2);
});
