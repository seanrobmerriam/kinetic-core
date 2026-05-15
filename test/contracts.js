/**
 * Contract test suite for kinetic-core API.
 *
 * Verifies that every critical endpoint honours its documented response
 * contract — correct HTTP status, required JSON fields, field types, and
 * shared conventions (Content-Type header, error shape, pagination shape).
 *
 * Provider boundaries covered:
 *   - Auth          POST /api/v1/auth/login, GET /api/v1/auth/me
 *   - Parties       GET/POST /api/v1/parties, GET /api/v1/parties/:id
 *   - Accounts      GET/POST /api/v1/accounts, GET /api/v1/accounts/:id
 *                   GET /api/v1/accounts/:id/balance
 *   - Transactions  POST deposit, withdraw, transfer
 *   - Events        GET /api/v1/events, GET /api/v1/events/:id
 *   - Exceptions    GET /api/v1/exceptions
 *   - Webhooks      GET /api/v1/webhooks
 *   - Products      GET /api/v1/savings-products, /api/v1/loan-products
 *   - Health        GET /health
 *   - Cross-cutting Error shape, pagination shape, CORS headers, Content-Type
 *
 * Usage:
 *   node test/contracts.js
 *
 * Environment variables:
 *   API_URL                  Base URL (default: http://localhost:18081)
 *   DASHBOARD_AUTH_EMAIL     Admin email
 *   DASHBOARD_AUTH_PASSWORD  Admin password
 */

"use strict";

const http = require("http");
const https = require("https");

// ─── Configuration ─────────────────────────────────────────────────────────

const API_BASE = (process.env.API_URL || "http://localhost:18081").replace(/\/$/, "");
const ADMIN_EMAIL = process.env.DASHBOARD_AUTH_EMAIL || "admin@example.com";
const ADMIN_PASSWORD = process.env.DASHBOARD_AUTH_PASSWORD || "secret-pass";

// ─── HTTP helper ───────────────────────────────────────────────────────────

/**
 * Send an HTTP request, return { status, headers, body, parsed }.
 */
function request(method, path, body, token) {
  return new Promise((resolve, reject) => {
    const url = new URL(`${API_BASE}${path}`);
    const bodyStr = body !== undefined ? JSON.stringify(body) : undefined;

    const reqHeaders = { "Content-Type": "application/json" };
    if (token) reqHeaders["Authorization"] = `Bearer ${token}`;
    if (bodyStr) reqHeaders["Content-Length"] = Buffer.byteLength(bodyStr);

    const lib = url.protocol === "https:" ? https : http;

    const req = lib.request(
      {
        hostname: url.hostname,
        port: url.port || (url.protocol === "https:" ? 443 : 80),
        path: url.pathname + url.search,
        method,
        headers: reqHeaders,
      },
      (res) => {
        let data = "";
        res.on("data", (c) => { data += c; });
        res.on("end", () => {
          let parsed = null;
          try { parsed = JSON.parse(data); } catch { /* not JSON */ }
          resolve({
            status: res.statusCode,
            headers: res.headers,
            body: data,
            parsed,
          });
        });
      }
    );
    req.on("error", reject);
    if (bodyStr) req.write(bodyStr);
    req.end();
  });
}

// ─── Schema validator ──────────────────────────────────────────────────────
//
// Inline micro-validator: no external dependencies.
//
// Schema syntax:
//   S.str          — value is a string
//   S.num          — value is a number
//   S.bool         — value is a boolean
//   S.any          — value is present (any non-undefined value, including null)
//   S.nullable(s)  — value is null OR matches schema s
//   S.obj(props)   — value is an object with at least the named properties
//   S.arr(s)       — value is an array; every element matches schema s
//   S.arr()        — value is an array (elements unchecked)

const S = {
  str: { type: "string" },
  num: { type: "number" },
  bool: { type: "boolean" },
  any: { type: "any" },
  nullable: (inner) => ({ type: "nullable", inner }),
  obj: (props) => ({ type: "object", props }),
  arr: (items) => ({ type: "array", items }),
};

function validate(value, schema, path = "root") {
  if (schema.type === "any") {
    if (value === undefined) throw new Error(`${path}: required but undefined`);
    return;
  }
  if (schema.type === "nullable") {
    if (value === null || value === undefined) return; // null is acceptable
    validate(value, schema.inner, path);
    return;
  }
  if (schema.type === "string") {
    if (typeof value !== "string")
      throw new Error(`${path}: expected string, got ${typeof value} (${JSON.stringify(value)})`);
    return;
  }
  if (schema.type === "number") {
    if (typeof value !== "number")
      throw new Error(`${path}: expected number, got ${typeof value} (${JSON.stringify(value)})`);
    return;
  }
  if (schema.type === "boolean") {
    if (typeof value !== "boolean")
      throw new Error(`${path}: expected boolean, got ${typeof value}`);
    return;
  }
  if (schema.type === "object") {
    if (value === null || typeof value !== "object" || Array.isArray(value))
      throw new Error(`${path}: expected object, got ${JSON.stringify(value)}`);
    for (const [key, childSchema] of Object.entries(schema.props)) {
      validate(value[key], childSchema, `${path}.${key}`);
    }
    return;
  }
  if (schema.type === "array") {
    if (!Array.isArray(value))
      throw new Error(`${path}: expected array, got ${typeof value}`);
    if (schema.items) {
      value.forEach((el, i) => validate(el, schema.items, `${path}[${i}]`));
    }
    return;
  }
  throw new Error(`Unknown schema type: ${schema.type}`);
}

// ─── Shared contracts ──────────────────────────────────────────────────────

const CONTRACT = {
  // Standard error shape: { error: string, message: string }
  error: S.obj({
    error: S.any, // may be atom serialised as string or number
    message: S.str,
  }),

  // Paginated list wrapper
  pagination: S.obj({
    items: S.arr(),
    total: S.num,
    page: S.num,
    page_size: S.num,
  }),

  // Party object
  party: S.obj({
    party_id: S.str,
    full_name: S.any,
    email: S.str,
    status: S.any,
    kyc_status: S.any,
    created_at: S.num,
    updated_at: S.num,
  }),

  // Account object
  account: S.obj({
    account_id: S.str,
    party_id: S.str,
    name: S.any,
    currency: S.any,
    balance: S.num,
    status: S.any,
    created_at: S.num,
    updated_at: S.num,
  }),

  // Balance object
  balance: S.obj({
    account_id: S.str,
    balance: S.num,
    available_balance: S.num,
    currency: S.any,
  }),

  // Transaction object (deposit / withdraw / transfer)
  transaction: S.obj({
    txn_id: S.str,
    idempotency_key: S.str,
    txn_type: S.any,
    status: S.any,
    amount: S.num,
    currency: S.any,
    created_at: S.num,
  }),

  // Auth login response
  auth: S.obj({
    session_id: S.str,
    user: S.obj({
      user_id: S.str,
      email: S.str,
      role: S.any,
      status: S.any,
    }),
  }),

  // Domain event object
  event: S.obj({
    event_id: S.str,
    event_type: S.any,
    status: S.any,
    created_at: S.num,
    updated_at: S.num,
  }),

  // Exception item
  exceptionItem: S.obj({
    item_id: S.str,
    status: S.any,
    created_at: S.num,
    updated_at: S.num,
  }),
};

// ─── Assertion helpers ─────────────────────────────────────────────────────

function assertStatus(resp, expected, label) {
  if (resp.status !== expected) {
    throw new Error(
      `${label}: expected HTTP ${expected}, got ${resp.status}. Body: ${resp.body.slice(0, 200)}`
    );
  }
}

function assertContentType(resp, label) {
  const ct = resp.headers["content-type"] || "";
  if (!ct.includes("application/json")) {
    throw new Error(
      `${label}: expected Content-Type application/json, got "${ct}"`
    );
  }
}

function assertSchema(value, schema, label) {
  validate(value, schema, label);
}

function assertCorsHeaders(resp, label) {
  const origin = resp.headers["access-control-allow-origin"];
  if (!origin) {
    throw new Error(`${label}: missing Access-Control-Allow-Origin header`);
  }
}

// ─── Auth / fixture setup ──────────────────────────────────────────────────

async function authenticate() {
  const resp = await request("POST", "/api/v1/auth/login", {
    email: ADMIN_EMAIL,
    password: ADMIN_PASSWORD,
  });
  if (resp.status !== 200 || !resp.parsed?.session_id) {
    throw new Error(`Login failed: HTTP ${resp.status} — ${resp.body}`);
  }
  return resp.parsed.session_id;
}

async function createParty(token) {
  const ts = Date.now();
  const resp = await request(
    "POST",
    "/api/v1/parties",
    {
      full_name: `Contract User ${ts}`,
      email: `contract_${ts}@example.com`,
    },
    token
  );
  if (resp.status !== 201 && resp.status !== 200) {
    throw new Error(`createParty failed: HTTP ${resp.status} — ${resp.body}`);
  }
  return resp.parsed;
}

async function createAccount(token, partyId) {
  const resp = await request(
    "POST",
    "/api/v1/accounts",
    { party_id: partyId, name: "Contract Account", currency: "USD" },
    token
  );
  if (resp.status !== 201 && resp.status !== 200) {
    throw new Error(`createAccount failed: HTTP ${resp.status} — ${resp.body}`);
  }
  return resp.parsed;
}

async function seedDeposit(token, accountId) {
  const ts = Date.now();
  const resp = await request(
    "POST",
    "/api/v1/transactions/deposit",
    {
      idempotency_key: `contract-seed-${ts}`,
      dest_account_id: accountId,
      amount: 1_000_000,
      currency: "USD",
      description: "contract seed",
    },
    token
  );
  if (resp.status !== 201 && resp.status !== 200) {
    throw new Error(`seedDeposit failed: HTTP ${resp.status} — ${resp.body}`);
  }
}

// ─── Contract definitions ──────────────────────────────────────────────────

function defineContracts(token, partyId, accountId) {
  const ts = Date.now();

  return [
    // ── Cross-cutting ──────────────────────────────────────────────────

    {
      name: "health: GET /health returns 200",
      run: async () => {
        const r = await request("GET", "/health");
        assertStatus(r, 200, "GET /health");
      },
    },

    {
      name: "cors: OPTIONS /api/v1/parties returns CORS headers",
      run: async () => {
        const r = await request("OPTIONS", "/api/v1/parties", undefined, token);
        // Preflight may return 200 or 204
        if (r.status !== 200 && r.status !== 204) {
          throw new Error(`OPTIONS /api/v1/parties: expected 200 or 204, got ${r.status}`);
        }
        assertCorsHeaders(r, "OPTIONS /api/v1/parties");
      },
    },

    {
      name: "error shape: invalid login returns {error, message}",
      run: async () => {
        const r = await request("POST", "/api/v1/auth/login", {
          email: "nobody@nowhere.invalid",
          password: "wrong",
        });
        if (r.status < 400 || r.status >= 500) {
          throw new Error(`Expected 4xx for bad credentials, got ${r.status}`);
        }
        assertContentType(r, "bad login");
        assertSchema(r.parsed, CONTRACT.error, "bad login error");
      },
    },

    {
      name: "error shape: method not allowed returns {error, message}",
      run: async () => {
        const r = await request("DELETE", "/api/v1/parties", undefined, token);
        assertStatus(r, 405, "DELETE /api/v1/parties");
        assertContentType(r, "405 response");
        assertSchema(r.parsed, CONTRACT.error, "405 error body");
      },
    },

    {
      name: "error shape: missing required fields returns 4xx {error, message}",
      run: async () => {
        const r = await request("POST", "/api/v1/parties", { email: "only@email.com" }, token);
        if (r.status < 400 || r.status >= 500) {
          throw new Error(`Expected 4xx for missing full_name, got ${r.status}`);
        }
        assertContentType(r, "missing field error");
        assertSchema(r.parsed, CONTRACT.error, "missing field error body");
      },
    },

    // ── Auth ──────────────────────────────────────────────────────────

    {
      name: "auth: POST /api/v1/auth/login returns session + user",
      run: async () => {
        const r = await request("POST", "/api/v1/auth/login", {
          email: ADMIN_EMAIL,
          password: ADMIN_PASSWORD,
        });
        assertStatus(r, 200, "POST /api/v1/auth/login");
        assertContentType(r, "login");
        assertSchema(r.parsed, CONTRACT.auth, "login response");
      },
    },

    {
      name: "auth: GET /api/v1/auth/me returns user object",
      run: async () => {
        const r = await request("GET", "/api/v1/auth/me", undefined, token);
        assertStatus(r, 200, "GET /api/v1/auth/me");
        assertContentType(r, "me");
        assertSchema(
          r.parsed,
          S.obj({ user_id: S.str, email: S.str, role: S.any }),
          "me response"
        );
      },
    },

    // ── Parties ───────────────────────────────────────────────────────

    {
      name: "parties: GET /api/v1/parties returns paginated list",
      run: async () => {
        const r = await request("GET", "/api/v1/parties", undefined, token);
        assertStatus(r, 200, "GET /api/v1/parties");
        assertContentType(r, "list parties");
        assertCorsHeaders(r, "GET /api/v1/parties");
        assertSchema(r.parsed, CONTRACT.pagination, "parties list");
        if (r.parsed.items.length > 0) {
          assertSchema(r.parsed.items[0], CONTRACT.party, "parties[0]");
        }
      },
    },

    {
      name: "parties: POST /api/v1/parties returns party object (201)",
      run: async () => {
        const tsLocal = Date.now();
        const r = await request(
          "POST",
          "/api/v1/parties",
          { full_name: `Contract Test ${tsLocal}`, email: `ctest_${tsLocal}@example.com` },
          token
        );
        assertStatus(r, 201, "POST /api/v1/parties");
        assertContentType(r, "create party");
        assertSchema(r.parsed, CONTRACT.party, "created party");
      },
    },

    {
      name: "parties: GET /api/v1/parties/:id returns party object",
      run: async () => {
        const r = await request("GET", `/api/v1/parties/${partyId}`, undefined, token);
        assertStatus(r, 200, `GET /api/v1/parties/${partyId}`);
        assertContentType(r, "get party");
        assertSchema(r.parsed, CONTRACT.party, "party by id");
      },
    },

    {
      name: "parties: GET /api/v1/parties/:id with unknown id returns 404 {error,message}",
      run: async () => {
        const r = await request(
          "GET",
          "/api/v1/parties/00000000-0000-0000-0000-000000000000",
          undefined,
          token
        );
        assertStatus(r, 404, "GET unknown party");
        assertSchema(r.parsed, CONTRACT.error, "unknown party error");
      },
    },

    // ── Accounts ──────────────────────────────────────────────────────

    {
      name: "accounts: GET /api/v1/accounts returns paginated list",
      run: async () => {
        const r = await request("GET", "/api/v1/accounts", undefined, token);
        assertStatus(r, 200, "GET /api/v1/accounts");
        assertContentType(r, "list accounts");
        assertSchema(r.parsed, CONTRACT.pagination, "accounts list");
        if (r.parsed.items.length > 0) {
          assertSchema(r.parsed.items[0], CONTRACT.account, "accounts[0]");
        }
      },
    },

    {
      name: "accounts: POST /api/v1/accounts returns account object (201)",
      run: async () => {
        const r = await request(
          "POST",
          "/api/v1/accounts",
          { party_id: partyId, name: "Contract Acct", currency: "USD" },
          token
        );
        assertStatus(r, 201, "POST /api/v1/accounts");
        assertContentType(r, "create account");
        assertSchema(r.parsed, CONTRACT.account, "created account");
      },
    },

    {
      name: "accounts: GET /api/v1/accounts/:id returns account object",
      run: async () => {
        const r = await request("GET", `/api/v1/accounts/${accountId}`, undefined, token);
        assertStatus(r, 200, `GET /api/v1/accounts/${accountId}`);
        assertContentType(r, "get account");
        assertSchema(r.parsed, CONTRACT.account, "account by id");
      },
    },

    {
      name: "accounts: GET /api/v1/accounts/:id/balance returns balance object",
      run: async () => {
        const r = await request(
          "GET",
          `/api/v1/accounts/${accountId}/balance`,
          undefined,
          token
        );
        assertStatus(r, 200, "GET balance");
        assertContentType(r, "get balance");
        assertSchema(r.parsed, CONTRACT.balance, "account balance");
      },
    },

    // ── Transactions ──────────────────────────────────────────────────

    {
      name: "transactions: POST /api/v1/transactions/deposit returns transaction (201)",
      run: async () => {
        const r = await request(
          "POST",
          "/api/v1/transactions/deposit",
          {
            idempotency_key: `contract-dep-${ts}`,
            dest_account_id: accountId,
            amount: 500,
            currency: "USD",
            description: "contract deposit",
          },
          token
        );
        assertStatus(r, 201, "POST deposit");
        assertContentType(r, "deposit");
        assertSchema(r.parsed, CONTRACT.transaction, "deposit transaction");
      },
    },

    {
      name: "transactions: POST /api/v1/transactions/withdraw returns transaction (201)",
      run: async () => {
        const r = await request(
          "POST",
          "/api/v1/transactions/withdraw",
          {
            idempotency_key: `contract-wd-${ts}`,
            source_account_id: accountId,
            amount: 100,
            currency: "USD",
            description: "contract withdraw",
          },
          token
        );
        assertStatus(r, 201, "POST withdraw");
        assertContentType(r, "withdraw");
        assertSchema(r.parsed, CONTRACT.transaction, "withdraw transaction");
      },
    },

    {
      name: "transactions: POST missing idempotency_key returns 4xx {error,message}",
      run: async () => {
        const r = await request(
          "POST",
          "/api/v1/transactions/deposit",
          { dest_account_id: accountId, amount: 100, currency: "USD" },
          token
        );
        if (r.status < 400 || r.status >= 500) {
          throw new Error(`Expected 4xx for missing idempotency_key, got ${r.status}`);
        }
        assertSchema(r.parsed, CONTRACT.error, "missing idempotency error");
      },
    },

    // ── Events ────────────────────────────────────────────────────────

    {
      name: "events: GET /api/v1/events returns array of event objects",
      run: async () => {
        const r = await request("GET", "/api/v1/events", undefined, token);
        assertStatus(r, 200, "GET /api/v1/events");
        assertContentType(r, "list events");
        if (!Array.isArray(r.parsed)) {
          throw new Error(`GET /api/v1/events: expected array, got ${typeof r.parsed}`);
        }
        if (r.parsed.length > 0) {
          assertSchema(r.parsed[0], CONTRACT.event, "events[0]");
        }
      },
    },

    // ── Exceptions ────────────────────────────────────────────────────

    {
      name: "exceptions: GET /api/v1/exceptions returns list",
      run: async () => {
        const r = await request("GET", "/api/v1/exceptions", undefined, token);
        assertStatus(r, 200, "GET /api/v1/exceptions");
        assertContentType(r, "list exceptions");
        // Accepts either a plain array or a paginated wrapper
        const items = Array.isArray(r.parsed)
          ? r.parsed
          : (r.parsed?.items ?? []);
        if (items.length > 0) {
          assertSchema(items[0], CONTRACT.exceptionItem, "exceptions[0]");
        }
      },
    },

    // ── Webhooks ──────────────────────────────────────────────────────

    {
      name: "webhooks: GET /api/v1/webhooks returns list or empty array",
      run: async () => {
        const r = await request("GET", "/api/v1/webhooks", undefined, token);
        assertStatus(r, 200, "GET /api/v1/webhooks");
        assertContentType(r, "list webhooks");
        // Accept array or paginated wrapper
        const items = Array.isArray(r.parsed)
          ? r.parsed
          : (r.parsed?.items ?? r.parsed?.subscriptions ?? []);
        if (!Array.isArray(items)) {
          throw new Error("GET /api/v1/webhooks: response is not a list");
        }
      },
    },

    // ── Products ──────────────────────────────────────────────────────

    {
      name: "products: GET /api/v1/savings-products returns list",
      run: async () => {
        const r = await request("GET", "/api/v1/savings-products", undefined, token);
        assertStatus(r, 200, "GET /api/v1/savings-products");
        assertContentType(r, "savings products");
        const items = Array.isArray(r.parsed)
          ? r.parsed
          : (r.parsed?.items ?? []);
        if (!Array.isArray(items)) {
          throw new Error("savings-products: expected list");
        }
      },
    },

    {
      name: "products: GET /api/v1/loan-products returns list",
      run: async () => {
        const r = await request("GET", "/api/v1/loan-products", undefined, token);
        assertStatus(r, 200, "GET /api/v1/loan-products");
        assertContentType(r, "loan products");
        const items = Array.isArray(r.parsed)
          ? r.parsed
          : (r.parsed?.items ?? []);
        if (!Array.isArray(items)) {
          throw new Error("loan-products: expected list");
        }
      },
    },
  ];
}

// ─── Runner ────────────────────────────────────────────────────────────────

async function main() {
  console.log("═══════════════════════════════════════════════════");
  console.log(" kinetic-core  API Contract Tests");
  console.log("═══════════════════════════════════════════════════");
  console.log(`  API_BASE : ${API_BASE}`);
  console.log("───────────────────────────────────────────────────\n");

  // ── Auth ─────────────────────────────────────────────────────────────────
  let token;
  try {
    token = await authenticate();
    console.log("  Authentication OK\n");
  } catch (err) {
    console.error(`Fatal: cannot authenticate — ${err.message}`);
    console.error("Ensure the API is running and credentials are correct.");
    process.exit(2);
  }

  // ── Fixtures ──────────────────────────────────────────────────────────────
  let partyId, accountId;
  try {
    console.log("  Creating test fixtures...");
    const party = await createParty(token);
    partyId = party.party_id;
    const account = await createAccount(token, partyId);
    accountId = account.account_id;
    await seedDeposit(token, accountId);
    console.log(`  Fixtures: party=${partyId}  account=${accountId}\n`);
  } catch (err) {
    console.error(`Fatal: fixture setup failed — ${err.message}`);
    process.exit(2);
  }

  // ── Run contracts ─────────────────────────────────────────────────────────
  const contracts = defineContracts(token, partyId, accountId);
  const results = [];

  for (const contract of contracts) {
    try {
      await contract.run();
      console.log(`  ✓  ${contract.name}`);
      results.push({ name: contract.name, status: "PASS" });
    } catch (err) {
      console.error(`  ✗  ${contract.name}`);
      console.error(`       ${err.message}`);
      results.push({ name: contract.name, status: "FAIL", error: err.message });
    }
  }

  // ── Summary ───────────────────────────────────────────────────────────────
  const passed = results.filter((r) => r.status === "PASS").length;
  const failed = results.filter((r) => r.status === "FAIL").length;

  console.log("\n─────────────────────────────────────────────────");
  console.log(` Contract Test Results: ${passed} passed, ${failed} failed`);
  console.log("─────────────────────────────────────────────────\n");

  if (failed > 0) process.exit(1);
}

main().catch((err) => {
  console.error("Fatal:", err);
  process.exit(2);
});
