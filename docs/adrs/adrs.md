# ADR-001 — Use Mnesia as the Primary Data Store

**Date:** 2024-01-01  
**Status:** Accepted

## Context
IronLedger is an Erlang/OTP application. A data store is needed for parties, accounts,
transactions, and ledger entries.

## Decision
Use Mnesia, Erlang's built-in distributed database, as the sole data store for the prototype.

## Rationale
- Mnesia transactions integrate directly with Erlang processes; no driver, no protocol overhead.
- ACID transactions are available via `mnesia:transaction/1` with no external dependencies.
- Table locks and read/write semantics match banking requirements (serialisable isolation).
- No additional infrastructure to run locally (Postgres, Redis etc. would require Docker or
  system installs, complicating the prototype setup).

## Consequences
- All financial reads/writes must be inside `mnesia:transaction/1`. Dirty operations on
  financial tables are forbidden.
- For the prototype, `ram_copies` are used. Data does not persist across node restarts.
  Disk persistence (`disc_copies`) is a post-prototype concern.
- Mnesia does not support SQL. Queries use pattern matching and secondary indexes.
  Complex reporting queries may be slow on large datasets (acceptable for prototype scale).

---

# ADR-002 — Double-Entry Bookkeeping for All Financial Events

**Date:** 2024-01-01  
**Status:** Accepted

## Context
The ledger must be auditable and internally consistent. Two approaches were considered:
single-entry (record net changes) and double-entry (record both debit and credit legs).

## Decision
Use double-entry bookkeeping for all financial events. Every transaction produces exactly
one debit ledger entry and one credit ledger entry of equal amounts.

## Rationale
- Double-entry is the standard in accounting and banking; it enables balance sheet
  reconciliation and catches bugs (the debit/credit sum must always be zero).
- Immutable ledger entries provide a complete, verifiable audit trail.
- The `prop_double_entry` PropEr property can enforce this invariant programmatically.

## Consequences
- Every transaction write must produce exactly two ledger entries in the same Mnesia
  transaction. Writing one entry without the other is a bug.
- Account balance is maintained as a running total on the `account` record, not
  computed from ledger history at runtime. Both must stay in sync.
- Ledger entries are **never** updated or deleted.

---

# ADR-003 — Integer Minor Units for All Monetary Amounts

**Date:** 2024-01-01  
**Status:** Accepted

## Context
Monetary values must be stored and computed without floating-point rounding errors.

## Decision
All monetary amounts are stored and transmitted as non-negative integers representing
minor units (cents for USD/EUR/GBP/CHF; whole units for JPY).

## Rationale
- Floating-point arithmetic (IEEE 754) introduces rounding errors that are unacceptable
  in financial systems (e.g. `0.1 + 0.2 ≠ 0.3` in most languages).
- Integer arithmetic in Erlang is arbitrary-precision and exact.
- Minor units are the standard approach in payment processing (Stripe, ISO 8583, etc.).

## Consequences
- `100` = $1.00 USD. `1` = $0.01 USD.
- No division of amounts is permitted in the prototype (cross-currency and fee splitting
  are out of scope). If division is ever needed, use integer division with explicit
  rounding rules documented at the call site.
- The `amount()` type is `non_neg_integer()`. Dialyzer will catch any float in a monetary
  path if types are annotated correctly.
- The Go/Wasm dashboard receives amounts as integers and formats them for display
  (divide by 100 for 2dp currencies). It always transmits integers back to the API.

---

# ADR-004 — Cowboy as the HTTP Server

**Date:** 2024-01-01  
**Status:** Accepted

## Context
A REST HTTP API is required to expose banking functions to the dashboard and external clients.

## Decision
Use Cowboy 2.x as the HTTP server, with a thin handler layer in `cb_integration`.

## Rationale
- Cowboy is the de facto standard Erlang HTTP server; battle-tested, well-documented.
- Minimal abstraction: handlers are plain Erlang modules. No framework magic.
- Integrates naturally with OTP supervision.

## Consequences
- Each API resource has a dedicated handler module in `apps/cb_integration/src/handlers/`.
- JSON encoding/decoding uses `jsx` or `jsone` (add to `rebar.config`).
- Error responses all go through a single `cb_http_errors:to_response/1` function that
  reads from the error catalogue. No handler hardcodes HTTP status codes.
- No authentication middleware in the prototype (deferred; see feature-prd.md §3).

---

# ADR-005 — Go/Wasm Dashboard (No JS Framework)

**Date:** 2024-01-01  
**Status:** Accepted

## Context
A browser dashboard is required. Options considered: React SPA, plain HTML + JS,
Go compiled to WebAssembly.

## Decision
Write the dashboard in Go, compiled to WebAssembly (`GOARCH=wasm GOOS=js`).
No JavaScript frameworks. DOM manipulation via `syscall/js`.

## Rationale
- Keeps the technology stack consistent with IronLedger's philosophy: typed, compiled
  languages with explicit error handling over dynamic scripting.
- Go's strong typing catches bugs the way Erlang's type specs do on the backend.
- Wasm gives a single, reproducible build artifact (`ironledger.wasm`) with no
  `node_modules` or transpilation step.
- `syscall/js` is sufficient for the dashboard's relatively simple UI needs.

## Consequences
- The Wasm binary can be large (2–10 MB). Acceptable for a prototype on localhost.
- All state is in-memory Go structs. Page refresh resets UI state (acceptable for prototype).
- API calls use `syscall/js` fetch. Amounts are integers in JSON on the wire;
  the Go layer formats them as decimal strings for display.
- The `dist/` directory is a build artifact and must be listed in `.gitignore`.
- Build command: `cd apps/cb_dashboard && GOARCH=wasm GOOS=js go build -o dist/ironledger.wasm .`

---

# ADR-006 — Idempotency via Client-Supplied Keys

**Date:** 2024-01-01  
**Status:** Accepted

## Context
Network failures can cause clients to retry payment requests. Without idempotency,
retries could double-post transactions.

## Decision
All mutating transaction endpoints require a client-supplied `idempotency_key` (opaque
binary, max 128 bytes). The first successful request with a given key sets the result;
subsequent requests with the same key return the same result without re-executing.

## Rationale
- Standard pattern used by Stripe, Braintree, and other payment APIs.
- Simple to implement with a secondary index on the `transaction` table.
- Puts deduplication responsibility on the caller, where it belongs.

## Consequences
- The `idempotency_key` field is required on `POST /transactions/transfer`,
  `POST /transactions/deposit`, and `POST /transactions/withdraw`.
- Submitting the same key with a different operation type returns
  `{error, idempotency_conflict}`.
- Idempotency check is the first operation inside every Mnesia transaction,
  before any validation or balance mutation.