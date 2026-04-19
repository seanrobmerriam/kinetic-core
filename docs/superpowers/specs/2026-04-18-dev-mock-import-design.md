# Dev Mock Data Import Design

Date: 2026-04-18
Owner: GitHub Copilot
Status: Approved design draft

## 1. Objective

Add a backend-driven, idempotent mock data importer that can be triggered from an explicit dev endpoint and from a dev-mode dashboard button.

## 2. Requirements

- Import is backend-based (not client-side fake data).
- Trigger must be explicit endpoint, not automatic startup seeding.
- Dashboard should expose an import button in dev mode.
- Import must cover full demo domain set:
  - parties
  - accounts and balances
  - transactions / ledger side effects
  - holds
  - savings products
  - loan products
  - loans
  - repayments
- Import behavior must be idempotent/upsert-safe.

## 3. High-Level Approach

### 3.1 Backend importer service

Create a dedicated importer module in integration app:
- `cb_mock_data_importer:seed_all/0`
- deterministic keys and idempotency keys
- per-domain helper routines for create-or-reuse behavior
- structured summary output

### 3.2 Explicit dev endpoint

Create `POST /api/v1/dev/mock-import` handler that:
- checks `cb_integration.enable_dev_tools`
- returns disabled error when feature flag is off
- invokes importer and returns summary
- supports OPTIONS for CORS

### 3.3 Dashboard dev action

Add dashboard API method + UI button:
- button visible when dev-tools capability is enabled
- button triggers mock import endpoint
- refreshes key datasets after success

## 4. Safety and Idempotency

- Namespaced deterministic identifiers and idempotency keys with `mock-` prefixes.
- Re-running import should not duplicate entities.
- Transaction-like operations should use deterministic idempotency keys and existing domain APIs to preserve invariants.
- Endpoint is configuration-gated to avoid accidental prod exposure.

## 5. Data Model for Demo Seed

Seed set includes:
- 8-15 parties with varied statuses where supported
- 15-30 accounts across parties
- balances established via deposit/transfer/withdraw operations
- 5-15 holds tied to selected accounts
- 3-5 savings products
- 3-5 loan products
- 6-12 loans spanning lifecycle statuses where supported
- repayments for eligible loans
- resulting ledger and transaction history through normal flows

## 6. API Contract

### Request

`POST /api/v1/dev/mock-import`

No body required.

### Success response

```json
{
  "ok": true,
  "mode": "idempotent",
  "summary": {
    "parties_created": 10,
    "parties_reused": 0,
    "accounts_created": 20,
    "accounts_reused": 0,
    "transactions_created": 42,
    "transactions_reused": 0,
    "holds_created": 8,
    "holds_reused": 0,
    "savings_products_created": 4,
    "savings_products_reused": 0,
    "loan_products_created": 4,
    "loan_products_reused": 0,
    "loans_created": 7,
    "loans_reused": 0,
    "repayments_created": 6,
    "repayments_reused": 0
  }
}
```

### Disabled response

When `enable_dev_tools` is false:
- status: 403 (or 404 by policy)
- error: `dev_tools_disabled`

## 7. File Plan

Create:
- `apps/cb_integration/src/cb_mock_data_importer.erl`
- `apps/cb_integration/src/handlers/cb_dev_mock_import_handler.erl`

Modify:
- `apps/cb_integration/src/cb_router.erl`
- `apps/cb_integration/src/cb_http_errors.erl` (if needed)
- `config/sys.config` (dev tools flag)
- `apps/cb_dashboard/api.go`
- `apps/cb_dashboard/app.go`
- `apps/cb_dashboard/main.go`
- `apps/cb_dashboard/dist/index.html` (optional button styling only)

## 8. Verification Strategy

1. Compile Erlang apps: `rebar3 compile`
2. Call endpoint twice and verify second run reports reuse and no duplicates.
3. Confirm dashboard button triggers import and refreshes views.
4. Validate key pages display populated data.
5. Confirm endpoint rejects when dev flag disabled.

## 9. Acceptance Criteria

- One-click dev import from dashboard works.
- Full dataset is present after import.
- Re-running import is safe and duplicate-free.
- Existing dashboard and backend flows remain functional.
