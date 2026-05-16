# TASK-096: Input Sanitization and Injection Prevention

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enforce input sanitization and injection prevention across all API entry points in `cb_integration`.

**Architecture:** A three-layer approach: (1) a new Cowboy middleware `cb_sanitize_middleware` that enforces request-level constraints (body size, Content-Type, query string bounds) for all requests before any handler runs; (2) enhanced `cb_validate` field-level helpers for safe text and bounded binaries; (3) targeted handler fixes for unsafe atom creation and unguarded integer parsing.

**Tech Stack:** Erlang/OTP, Cowboy HTTP server, Mnesia, Common Test.

---

## Root Cause Analysis

Code review found these injection/sanitization gaps:

| File | Issue | Risk |
|---|---|---|
| `cb_accounts_handler.erl` | `binary_to_atom(CurrencyBin, utf8)` — creates new atoms | Atom table exhaustion (DoS) |
| `cb_accounts_handler.erl` | `binary_to_integer(proplists:get_value(...))` without guard | Crashes on non-integer → 500 |
| `cb_transaction_deposit_handler.erl` | `binary_to_existing_atom(CurrencyBin, utf8)` before validation | Crashes on unknown currency → 500 |
| All handlers | No body size cap before handler reads body | Large body abuse |
| All write handlers | No Content-Type enforcement | Confuse jsone decoder with non-JSON |
| All handlers | No query string value size limit | Large value injection |
| Text fields | `full_name`, `email`, `description`, `name` accepted at any size | Oversized string injection |

## File Map

### New files
- `apps/cb_integration/src/cb_sanitize_middleware.erl` — Cowboy middleware: body size, Content-Type, query-string checks
- `apps/cb_integration/test/cb_input_sanitization_SUITE.erl` — CT suite for A03 injection coverage

### Modified files
- `apps/cb_integration/src/cb_validate.erl` — add `safe_text/2`, `bounded_binary/3`, `safe_path_param/1`
- `apps/cb_integration/src/cb_http_errors.erl` — add `request_too_large`, `unsupported_media_type`, `invalid_query_param`, `invalid_text`, `field_too_large`, `invalid_path_param`
- `apps/cb_integration/src/cb_integration_app.erl` — add `cb_sanitize_middleware` to middleware chain
- `apps/cb_integration/src/handlers/cb_accounts_handler.erl` — fix `binary_to_atom` and bare `binary_to_integer`
- `apps/cb_integration/src/handlers/cb_transaction_deposit_handler.erl` — validate currency before atom conversion

---

## Tasks

### Step 1: Add error codes to cb_http_errors

- [ ] Add `request_too_large` → 413 to `cb_http_errors:to_response/1`
- [ ] Add `unsupported_media_type` → 415
- [ ] Add `invalid_query_param` → 400
- [ ] Add `invalid_text` → 422
- [ ] Add `field_too_large` → 422
- [ ] Add `invalid_path_param` → 400
- [ ] Compile: `rebar3 compile`

### Step 2: Enhance cb_validate

- [ ] Add `safe_text/2` spec and implementation
- [ ] Add `bounded_binary/3` spec and implementation
- [ ] Add `safe_path_param/1` spec and implementation
- [ ] Export all three new functions
- [ ] Compile: `rebar3 compile`

### Step 3: Create cb_sanitize_middleware

- [ ] Write module skeleton with `-behaviour(cowboy_middleware)`
- [ ] Implement `execute/2`:
  - Pass OPTIONS through immediately
  - For POST/PUT/PATCH: check `content-type` header is `application/json`; reject 415 if not
  - For POST/PUT/PATCH: check `content-length` header; reject 413 if > 65536
  - For all methods: validate each query-string value (max 512 bytes, no null bytes); reject 400 if violated
- [ ] Compile: `rebar3 compile`

### Step 4: Wire middleware into app

- [ ] Insert `cb_sanitize_middleware` after `cb_auth_middleware` and before `cb_deprecation_middleware` in `cb_integration_app.erl`
- [ ] Compile: `rebar3 compile`

### Step 5: Fix handlers

- [ ] `cb_accounts_handler.erl` POST: replace `binary_to_atom` with `cb_validate:currency/1` + `binary_to_existing_atom`
- [ ] `cb_accounts_handler.erl` GET: replace bare `binary_to_integer` with safe guard wrappers using `cb_validate:optional_integer/3`
- [ ] `cb_transaction_deposit_handler.erl` POST: call `cb_validate:currency/1` before `binary_to_existing_atom`, short-circuit on error
- [ ] Compile: `rebar3 compile`

### Step 6: Write CT test suite

- [ ] `init_per_suite/1`: start app on test port 18086
- [ ] `end_per_suite/1`: stop app
- [ ] Test `oversized_body_rejected`: POST with Content-Length: 70000 → 413
- [ ] Test `wrong_content_type_rejected`: POST with `text/plain` → 415
- [ ] Test `invalid_currency_safe`: POST deposit with `currency: "'; DROP TABLE--"` → 422, not 500
- [ ] Test `invalid_page_safe`: GET `/api/v1/accounts?page=not_a_number` → 422 or 400, not 500
- [ ] Test `null_byte_in_query_rejected`: GET with null byte in query value → 400
- [ ] Test `oversized_query_value_rejected`: GET with 600-byte query value → 400
- [ ] Run tests: `rebar3 ct --suite cb_input_sanitization_SUITE`

### Step 7: Full test pass + commit

- [ ] `rebar3 ct` — all suites green
- [ ] `rebar3 compile` with no warnings
- [ ] `git add -A && git commit`
- [ ] Update `DEVELOPMENT.md` TASK-096 entry
