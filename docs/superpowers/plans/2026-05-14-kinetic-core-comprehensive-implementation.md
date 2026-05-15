---
name: kinetic-core-comprehensive-implementation
description: Full implementation plan for all missing Kinetic Core platform features
version: 1.0
created: 2026-05-14
source: REQUIREMENTS.md + codebase audit
scope: All phases — Release-Blocking through Phase 5 Intelligence
---

# Kinetic Core — Comprehensive Implementation Plan

> **Source:** `REQUIREMENTS.md` + full codebase audit against `audit/gap-report.md` and `audit/remediation-tasks.md`
> **Phases:** 0 (hotfix) → 1 → 2 → 3 → 4 → 5
> **Convention:** All Erlang source files live under `apps/<app>/src/`. All dashboard files under `apps/cb_dashboard/src/`.

---

## Phase 0 — Hotfix (ship immediately, separate PR)

### PH0-TASK-001 — Fix broken KYC save action *(STALE-001)*
**Priority:** 🚨 CRITICAL · **Effort:** XS

**What:** Dashboard compliance page calls `PUT /parties/:id/kyc` but backend only supports `GET/PATCH/POST`. Change to `PATCH`.

**Files:**
- `apps/cb_dashboard/src/app/(app)/compliance/page.tsx` — line ~272, change `api("PUT", ...)` to `api("PATCH", ...)`

**Acceptance criteria:**
- [ ] Saving KYC from compliance page returns 200, row updates without reload
- [ ] Network tab shows `PATCH` not `PUT`

---

### PH0-TASK-002 — Refactor account detail N+1 query *(PARTIAL-001)*
**Priority:** 🟠 HIGH · **Effort:** S

**What:** Account detail page fetches full party list then iterates accounts to find match. Replace with direct `GET /accounts/:id`.

**Files:**
- `apps/cb_dashboard/src/app/(app)/accounts/[accountId]/page.tsx`

**Acceptance criteria:**
- [ ] Single `GET /accounts/:id` call replaces N+1 pattern
- [ ] Owning party fetched separately only when needed
- [ ] Performance regression test passes

---

## Phase 1 — Release-Blocking Core Completions

### PH1-TASK-001 — Customer duplicate detection and merge
**Priority:** 🚨 CRITICAL · **Effort:** M

**What:** Add `detect_duplicates/1` and `merge_customers/2` functions to `cb_party`.

**Backend files:**
- `apps/cb_party/src/cb_party.erl` — add `detect_duplicates/1` and `merge_customers/2`
- `apps/cb_integration/src/handlers/cb_party_merge_handler.erl` — new handler
- `apps/cb_integration/src/cb_router.erl` — register:
  - `POST /api/v1/parties/:party_id/merge` → `cb_party_merge_handler`
  - `GET /api/v1/parties/duplicates` → `cb_party_merge_handler`
- `apps/cb_integration/src/cb_schema.erl` — add `party_merge` table spec

**Dashboard files:**
- `apps/cb_dashboard/src/app/(app)/customers/[partyId]/page.tsx` — add "Merge" action button
- `apps/cb_dashboard/src/lib/api.ts` — add `mergeParties(sourceId, targetId)` and `findDuplicates(params)`

**API contract:**
- `POST /parties/:party_id/merge` body: `{ target_party_id, reason }` → `{ ok, merged_party }`
- `GET /parties/duplicates?{field}={value}` → `{ ok, candidates: [...] }`

**Acceptance criteria:**
- [ ] Duplicates detected by name + DOB + document number fuzzy match
- [ ] Merge is atomic — source party archived, accounts transferred
- [ ] Audit trail records `party_merged` action with both IDs
- [ ] UI shows candidate duplicates before confirmation

---

### PH1-TASK-002 — Trial balance and GL reporting endpoints
**Priority:** 🚨 CRITICAL · **Effort:** M

**What:** Implement `GET /api/v1/ledger/trial-balance` and `GET /api/v1/ledger/general-ledger`.

**Backend files:**
- `apps/cb_ledger/src/cb_trial_balance.erl` — new module:
  - `generate_trial_balance(AsOfDate)` → `#{account => #{currency => balance_minor}}`
  - Include all accounts regardless of zero balance
- `apps/cb_integration/src/handlers/cb_trial_balance_handler.erl` — new handler
- `apps/cb_integration/src/handlers/cb_general_ledger_handler.erl` — new handler
- `apps/cb_integration/src/cb_router.erl` — register both routes
- `apps/cb_integration/src/cb_openapi_handler.erl` — add OpenAPI specs for both
- `apps/cb_integration/src/cb_schema.erl` — add `trial_balance` table spec

**Dashboard files:**
- `apps/cb_dashboard/src/app/(app)/reports/trial-balance/page.tsx` — new page
- `apps/cb_dashboard/src/app/(app)/reports/general-ledger/page.tsx` — new page
- `apps/cb_dashboard/src/lib/api.ts` — add `getTrialBalance(date)` and `getGeneralLedger(filters)`

**API contract:**
- `GET /api/v1/ledger/trial-balance?as_of_date=YYYY-MM-DD` → `{ accounts: [{account_id, account_name, currency, debit_balance_minor, credit_balance_minor}], generated_at }`
- `GET /api/v1/ledger/general-ledger?from=&to=&account_id=` → `{ entries: [...] }`

**Acceptance criteria:**
- [ ] Trial balance totals debit == credit
- [ ] Supports `as_of_date` parameter for point-in-time
- [ ] GL entries paginated, filterable by date range and account

---

### PH1-TASK-003 — Manual ledger adjustment workflow
**Priority:** 🚨 CRITICAL · **Effort:** M

**What:** Add `POST /transactions/adjustment` for operations team break-fix entries.

**Backend files:**
- `apps/cb_ledger/src/cb_ledger_adjustment.erl` — new module:
  - `create_adjustment(debit_account, credit_account, amount_minor, currency, reason, reference)` → `{ok, transaction_id}`
  - Reason required (≥10 chars), recorded in audit trail
- `apps/cb_integration/src/handlers/cb_transaction_adjustment_handler.erl` — new handler
- `apps/cb_integration/src/cb_router.erl` — register `POST /api/v1/transactions/adjustment`
- `apps/cb_integration/src/cb_openapi_handler.erl` — add OpenAPI spec
- `apps/cb_integration/src/cb_http_errors.erl` — add `adjustment_reason_required` and `cross_currency_mismatch` error codes

**Dashboard files:**
- `apps/cb_dashboard/src/app/(app)/transactions/adjustment/page.tsx` — new page (ops_admin only)
- `apps/cb_dashboard/src/lib/api.ts` — add `createAdjustment(payload)`
- `apps/cb_dashboard/src/lib/types.ts` — add `AdjustmentPayload` type

**Acceptance criteria:**
- [ ] Amount entered in major units, converted to minor units
- [ ] Both accounts validated as same currency before submit
- [ ] Mandatory reason ≥10 chars enforced pre-submit
- [ ] Success view shows resulting transaction ID with link to detail

---

### PH1-TASK-004 — Transaction detail and ledger entries view
**Priority:** 🚨 CRITICAL · **Effort:** M

**What:** Implement `GET /transactions/:txn_id` and `GET /transactions/:txn_id/entries`.

**Backend files:**
- `apps/cb_integration/src/handlers/cb_transaction_detail_handler.erl` — new handler
- `apps/cb_integration/src/handlers/cb_transaction_entries_handler.erl` — new handler
- `apps/cb_integration/src/cb_router.erl` — register both routes
- `apps/cb_integration/src/cb_openapi_handler.erl` — add OpenAPI specs

**Dashboard files:**
- `apps/cb_dashboard/src/app/(app)/transactions/[txnId]/page.tsx` — new detail page
- Make transaction rows in `/transactions` and account detail tables clickable links
- `apps/cb_dashboard/src/lib/api.ts` — add `getTransaction(id)` and `getTransactionEntries(id)`

**API contract:**
- `GET /transactions/:txn_id` → `{ transaction_id, type, status, amount, currency, created_at, posted_at, description, entries: [...] }`
- `GET /transactions/:txn_id/entries` → `{ entries: [{entry_id, account_id, account_name, debit_minor, credit_minor, currency}] }`

**Acceptance criteria:**
- [ ] Double-entry ledger lines visible for any transaction
- [ ] Audit trail accessible from transaction detail

---

### PH1-TASK-005 — Account statement download ✅ DONE
**Priority:** 🚨 CRITICAL · **Effort:** S

**What:** Implement `GET /accounts/:account_id/statement`.

**Backend files:**
- `apps/cb_reporting/src/cb_statement_generator.erl` — new module:
  - `generate_statement(AccountId, FromDate, ToDate, Format)` → PDF or CSV binary
  - Format: ISO 20022 camt.053 or CSV
- `apps/cb_integration/src/handlers/cb_statement_handler.erl` — new handler
- `apps/cb_integration/src/cb_router.erl` — register `GET /api/v1/accounts/:account_id/statement`
- `apps/cb_integration/src/cb_openapi_handler.erl` — add OpenAPI spec

**Dashboard files:**
- `apps/cb_dashboard/src/app/(app)/accounts/[accountId]/statement/page.tsx` — new page
- `apps/cb_dashboard/src/components/StatementDownload.tsx` — extend to handle account statement
- `apps/cb_dashboard/src/lib/api.ts` — add `getAccountStatement(accountId, from, to, format)`
- `apps/cb_dashboard/src/app/(app)/accounts/[accountId]/page.tsx` — add "Download Statement" button

**API contract:**
- `GET /accounts/:account_id/statement?from=&to=&format=csv|camt053` → binary (PDF/CSV)

**Acceptance criteria:**
- [ ] CSV format: txn_id, date, description, debit, credit, balance
- [ ] camt.053 format: ISO 20022 compliant XML
- [ ] Date range filter enforced

---

### PH1-TASK-006 — Bulk export API
**Priority:** 🚨 CRITICAL · **Effort:** S

**What:** Implement `GET /export/:resource`.

**Backend files:**
- `apps/cb_reporting/src/cb_exports.erl` — extend to support `GET /export/:resource`:
  - `export_resource(Resource, Filters)` → `{ok, binary, content_type}`
  - Resources: `parties`, `accounts`, `transactions`, `ledger`
- `apps/cb_integration/src/handlers/cb_export_handler.erl` — new handler
- `apps/cb_integration/src/cb_router.erl` — register `GET /api/v1/export/:resource`
- `apps/cb_integration/src/cb_openapi_handler.erl` — add OpenAPI spec

**Dashboard files:**
- `apps/cb_dashboard/src/app/(app)/exports/page.tsx` — new page
- `apps/cb_dashboard/src/lib/api.ts` — add `exportResource(resource, filters)`

**API contract:**
- `GET /export/:resource?from=&to=&format=csv|json` → binary

**Acceptance criteria:**
- [ ] Supports all major resource types
- [ ] Server-side streaming for large exports (avoid memory spike)
- [ ] Role-gated: only `ops_admin` or `compliance_officer`

---

### PH1-TASK-007 — Customer reactivate endpoint and UI ✅ DONE (already implemented)
**Priority:** 🚨 CRITICAL · **Effort:** S

**What:** `POST /parties/:party_id/reactivate` and UI button.

**Backend files:**
- `apps/cb_party/src/cb_party.erl` — add `reactivate_customer/1`
- `apps/cb_integration/src/handlers/cb_party_reactivate_handler.erl` — new handler
- `apps/cb_integration/src/cb_router.erl` — register `POST /api/v1/parties/:party_id/reactivate`
- `apps/cb_integration/src/cb_openapi_handler.erl` — add OpenAPI spec

**Dashboard files:**
- `apps/cb_dashboard/src/app/(app)/customers/[partyId]/page.tsx` — add Reactivate button in actions menu
- `apps/cb_dashboard/src/lib/api.ts` — add `reactivateParty(id)`

**API contract:**
- `POST /parties/:party_id/reactivate` → `{ ok, party }`

**Acceptance criteria:**
- [ ] Button visible only when `party.status ∈ {suspended, closed}`
- [ ] KYC must be approved before reactivate succeeds
- [ ] Confirmation dialog explains audit implications

---

### PH1-TASK-008 — KYC document reference attachment
**Priority:** 🚨 CRITICAL · **Effort:** S

**What:** `POST /parties/:party_id/kyc` (add doc_ref) to attach document evidence.

**Backend files:**
- `apps/cb_party/src/cb_party.erl` — extend `update_kyc_status/3` to accept `document_refs` map
- `apps/cb_integration/src/handlers/cb_party_kyc_handler.erl` — extend to accept `document_refs` in PATCH body
- `apps/cb_integration/src/cb_openapi_handler.erl` — update KYC endpoint spec

**Dashboard files:**
- `apps/cb_dashboard/src/app/(app)/compliance/page.tsx` — add document upload/attach section

**API contract:**
- `PATCH /parties/:party_id/kyc` body: `{ status, notes?, document_refs?: [{type, ref, uploaded_at}] }`

**Acceptance criteria:**
- [ ] Document references recorded in audit trail
- [ ] Supports multiple document types (ID card, proof of address, etc.)

---

### PH1-TASK-009 — Currency pair spread configuration
**Priority:** 🟠 HIGH · **Effort:** S

**What:** Add spread configuration per currency pair.

**Backend files:**
- `apps/cb_currency/src/cb_currency_pair.erl` — new module:
  - `create_pair(from_currency, to_currency, spread_bps,生效日期)` → `{ok, #currency_pair{}}`
  - `get_spread/2` → basis points spread
- `apps/cb_currency/src/cb_fx_rates.erl` — integrate spread into conversion cost calculation
- `apps/cb_integration/src/handlers/cb_currency_pair_handler.erl` — new handler
- `apps/cb_integration/src/cb_router.erl` — register:
  - `POST /api/v1/currency-pairs`
  - `GET /api/v1/currency-pairs`
  - `GET /api/v1/currency-pairs/:pair_id`
  - `PATCH /api/v1/currency-pairs/:pair_id`
- `apps/cb_integration/src/cb_openapi_handler.erl` — add OpenAPI spec
- `apps/cb_integration/src/cb_schema.erl` — add `currency_pair` table spec

**Acceptance criteria:**
- [ ] Spread stored in basis points (1/100th of 1%)
- [ ] Conversion cost includes spread when `cb_currency:convert/3` is called

---

### PH1-TASK-010 — Settlement currency assignment API
**Priority:** 🟠 HIGH · **Effort:** S

**What:** Expose settlement currency assignment per transaction as a first-class API.

**Backend files:**
- `apps/cb_payments/src/cb_settlement_currency.erl` — new module:
  - `assign_settlement_currency(TransactionId, SettlementCurrency)` → `{ok, transaction}`
- `apps/cb_integration/src/handlers/cb_settlement_currency_handler.erl` — new handler
- `apps/cb_integration/src/cb_router.erl` — register:
  - `GET /api/v1/transactions/:txn_id/settlement-currency`
  - `PUT /api/v1/transactions/:txn_id/settlement-currency`
- `apps/cb_integration/src/cb_openapi_handler.erl` — add OpenAPI spec

**Acceptance criteria:**
- [ ] Settlement currency can be set at transaction initiation or post-hoc
- [ ] Validation: settlement currency must be one of the transaction's multi-currency components

---

### PH1-TASK-011 — Payment cancellation and recall
**Priority:** 🟠 HIGH · **Effort:** M

**What:** Implement cancel and recall for payment orders.

**Backend files:**
- `apps/cb_payments/src/cb_payment_orders.erl` — add `cancel_payment/1` and `recall_payment/1`:
  - `cancel_payment` — only for `pending` orders
  - `recall_payment` — for `completed` orders (initiates reversal workflow)
- `apps/cb_integration/src/handlers/cb_payment_cancel_handler.erl` — new handler
- `apps/cb_integration/src/handlers/cb_payment_recall_handler.erl` — new handler
- `apps/cb_integration/src/cb_router.erl` — register:
  - `POST /api/v1/payment-orders/:order_id/cancel`
  - `POST /api/v1/payment-orders/:order_id/recall`
- `apps/cb_integration/src/cb_openapi_handler.erl` — add OpenAPI specs

**Dashboard files:**
- `apps/cb_dashboard/src/app/(app)/payments/[orderId]/page.tsx` — add Cancel/Recall actions

**Acceptance criteria:**
- [ ] Cancel only available while order is `pending`
- [ ] Recall triggers reversal workflow and notifies beneficiary
- [ ] SLA timer displayed in UI for pending items

---

### PH1-TASK-012 — Beneficiary (payee) management
**Priority:** 🟠 HIGH · **Effort:** M

**What:** Full CRUD for payee/beneficiary records.

**Backend files:**
- `apps/cb_payments/src/cb_beneficiary.erl` — new module:
  - `create_beneficiary(PartyId, Name, AccountNumber, BankCode, Currency, Country)` → `{ok, #beneficiary{}}`
  - `list_beneficiaries/1`, `get_beneficiary/1`, `update_beneficiary/2`, `delete_beneficiary/1`
- `apps/cb_integration/src/handlers/cb_beneficiary_handler.erl` — new handler
- `apps/cb_integration/src/cb_router.erl` — register:
  - `POST /api/v1/beneficiaries`
  - `GET /api/v1/beneficiaries?party_id=`
  - `GET /api/v1/beneficiaries/:id`
  - `PATCH /api/v1/beneficiaries/:id`
  - `DELETE /api/v1/beneficiaries/:id`
- `apps/cb_integration/src/cb_openapi_handler.erl` — add OpenAPI spec
- `apps/cb_integration/src/cb_schema.erl` — add `beneficiary` table spec

**Dashboard files:**
- `apps/cb_dashboard/src/app/(app)/beneficiaries/page.tsx` — new page
- `apps/cb_dashboard/src/lib/api.ts` — add beneficiary CRUD methods

**Acceptance criteria:**
- [ ] Beneficiary validated against SWIFT bank code lookup
- [ ] Duplicate beneficiary detection by account+bank+country

---

### PH1-TASK-013 — Settlement file generation for batch processing
**Priority:** 🟠 HIGH · **Effort:** M

**What:** Generate settlement files (CSV) for batch payment processing.

**Backend files:**
- `apps/cb_payments/src/cb_settlement_file.erl` — new module:
  - `generate_settlement_file(Date, Currency)` → `{ok, FileContent, FileName}`
  - Format: ISO 20022 pain.001 or bank-specific CSV
- `apps/cb_reporting/src/cb_jobs.erl` — add `settlement_file` job type:
  - `cb_settlement_file:generate_settlement_file(Date, Currency)`
- `apps/cb_integration/src/handlers/cb_settlement_file_handler.erl` — new handler
- `apps/cb_integration/src/cb_router.erl` — register:
  - `GET /api/v1/settlements/files?date=&currency=`
  - `POST /api/v1/settlements/generate`
- `apps/cb_integration/src/cb_openapi_handler.erl` — add OpenAPI spec

**Acceptance criteria:**
- [ ] File includes all completed payments for the settlement cut-off time
- [ ] File name: `settlement_YYYYMMDD_HHMMSS_<currency>.csv`
- [ ] File checksum (MD5) recorded

---

### PH1-TASK-014 — Audit log retention policy enforcement
**Priority:** 🟠 HIGH · **Effort:** S

**What:** Enforce configurable retention periods; auto-archive or delete old audit entries.

**Backend files:**
- `apps/cb_compliance/src/cb_audit_retention.erl` — new module:
  - `set_retention_policy(Resource, RetentionDays)` → ok
  - `apply_retention_policies()` → deletes/moves records older than policy
  - `get_retention_policy/1` → current policy
- `apps/cb_reporting/src/cb_jobs.erl` — add `audit_retention` scheduled job:
  - `cb_audit_retention:apply_retention_policies()`
- `apps/cb_integration/src/handlers/cb_audit_retention_handler.erl` — new handler
- `apps/cb_integration/src/cb_router.erl` — register:
  - `POST /api/v1/audit/retention-policies`
  - `GET /api/v1/audit/retention-policies`
  - `POST /api/v1/audit/apply-retention` (trigger)
- `apps/cb_integration/src/cb_openapi_handler.erl` — add OpenAPI spec
- `apps/cb_integration/src/cb_schema.erl` — add `audit_retention_policy` table spec

**Acceptance criteria:**
- [ ] Policies configurable per resource type (ledger_entry, transaction, party_audit)
- [ ] Retention job runs daily via `cb_jobs`
- [ ] Deletion logged (not permanently lost — moved to archive table)

---

### PH1-TASK-015 — SLA monitoring for transaction completion
**Priority:** 🟠 HIGH · **Effort:** S

**What:** Extend `cb_exception_sla` to send alerts on SLA breach.

**Backend files:**
- `apps/cb_approvals/src/cb_exception_sla.erl` — add `send_sla_alert/2`:
  - Alert to compliance officer queue when `time_in_queue > sla_hours`
  - Uses `cb_notification_router` for routing
- `apps/cb_reporting/src/cb_jobs.erl` — add `sla_monitor` job:
  - `cb_exception_sla:check_all_items()`
- `apps/cb_integration/src/cb_schema.erl` — add `sla_config` table spec

**Dashboard files:**
- `apps/cb_dashboard/src/app/(app)/exceptions/page.tsx` — add SLA timer column
- Color-code rows: green → yellow (75% of SLA) → red (SLA breached)

**Acceptance criteria:**
- [ ] SLA timers visible on all exception queue items
- [ ] Automated alert fired when SLA breaches
- [ ] Escalation path configurable per exception type

---

### PH1-TASK-016 — Health and metrics API endpoints
**Priority:** 🟠 HIGH · **Effort:** S

**What:** Implement missing health endpoint and extend metrics.

**Backend files:**
- `apps/cb_integration/src/handlers/cb_health_handler.erl` — new handler:
  - `GET /api/v1/health` → `{ status: ok|degraded, checks: [{service, status, latency_ms}] }`
  - Checks: Mnesia, cb_ledger, cb_payments, cb_auth, cb_events
- `apps/cb_integration/src/handlers/cb_metrics_handler.erl` — new handler:
  - `GET /api/v1/metrics` → Prometheus-format metrics
- `apps/cb_integration/src/cb_router.erl` — register both routes

**Dashboard files:**
- `apps/cb_dashboard/src/app/(app)/settings/health/page.tsx` — new health dashboard page

**Acceptance criteria:**
- [ ] Health endpoint returns 200 when all checks pass
- [ ] Health endpoint returns 503 when any critical check fails
- [ ] Metrics include: request_count, error_count, latency_p50/p95/p99, payment_txn_count

---

### PH1-TASK-017 — API key lifecycle UI
**Priority:** 🟠 HIGH · **Effort:** S

**What:** Full CRUD for API keys in developer portal.

**Backend files:**
- `apps/cb_auth/src/cb_api_keys.erl` — extend with `revoke_key/1`, `update_key/2`
- `apps/cb_integration/src/handlers/cb_api_keys_handler.erl` — extend handler for full CRUD

**Dashboard files:**
- `apps/cb_dashboard/src/app/(app)/developer/api-keys/page.tsx` — new page
  - List keys, create new key (POST), revoke key (DELETE), view key metadata
- `apps/cb_dashboard/src/lib/api.ts` — add `createApiKey`, `revokeApiKey`, `listApiKeys`

**Acceptance criteria:**
- [ ] Keys displayed masked (show only last 4 chars)
- [ ] Expiry date editable
- [ ] Revoke immediately invalidates key

---

### PH1-TASK-018 — Webhook subscription CRUD UI
**Priority:** 🟠 HIGH · **Effort:** S

**What:** Full CRUD for webhook subscriptions in developer portal.

**Backend files:**
- `apps/cb_events/src/cb_webhooks.erl` — extend with `update_subscription/2`, `delete_subscription/1`
- `apps/cb_integration/src/handlers/cb_webhook_handler.erl` — extend for full CRUD

**Dashboard files:**
- `apps/cb_dashboard/src/app/(app)/developer/webhooks/page.tsx` — extend existing page
  - Add create, edit, delete subscription actions
  - Add delivery history inspection (`GET /webhooks/:id/deliveries`)

**Acceptance criteria:**
- [ ] Subscribe/unsubscribe new event types from UI
- [ ] View delivery attempts and failure reasons
- [ ] Test event delivery (send sample event)

---

### PH1-TASK-019 — Savings and loan product lifecycle UI
**Priority:** 🟠 HIGH · **Effort:** M

**What:** Activate/deactivate/detail views for savings and loan products.

**Backend files:**
- `apps/cb_savings_products/src/cb_savings_products.erl` — add `activate/1`, `deactivate/1`
- `apps/cb_loans/src/cb_loan_products.erl` — add `activate/1`, `deactivate/1`
- `apps/cb_integration/src/handlers/cb_savings_product_detail_handler.erl` — new handler
- `apps/cb_integration/src/handlers/cb_loan_product_detail_handler.erl` — new handler
- `apps/cb_integration/src/cb_router.erl` — register:
  - `POST /api/v1/savings-products/:id/activate`
  - `POST /api/v1/savings-products/:id/deactivate`
  - `GET /api/v1/savings-products/:id`
  - `POST /api/v1/loan-products/:id/activate`
  - `POST /api/v1/loan-products/:id/deactivate`
  - `GET /api/v1/loan-products/:id`
- `apps/cb_integration/src/cb_openapi_handler.erl` — add OpenAPI specs

**Dashboard files:**
- `apps/cb_dashboard/src/app/(app)/products/savings/[productId]/page.tsx` — new detail page
- `apps/cb_dashboard/src/app/(app)/products/loans/[productId]/page.tsx` — new detail page
- `apps/cb_dashboard/src/app/(app)/products/savings/page.tsx` — add Activate/Deactivate actions
- `apps/cb_dashboard/src/app/(app)/products/loans/page.tsx` — same

**Acceptance criteria:**
- [ ] Products list shows activation status
- [ ] Activate/deactivate is a state transition (not delete)
- [ ] Only active products eligible for new accounts

---

## Phase 2 — Release-Blocking Dashboard Completions

### PH2-TASK-001 — Refactor account detail page with direct API call
**Priority:** 🟠 HIGH · **Effort:** S

*(Supersedes PH0-TASK-002 — the detailed refactoring work)*

**Files:** Full implementation in `apps/cb_dashboard/src/app/(app)/accounts/[accountId]/page.tsx`

**Acceptance criteria:**
- [ ] Single `GET /accounts/:id` call on page load
- [ ] Owning party fetched separately on explicit action
- [ ] No customer data leakage between accounts

---

### PH2-TASK-002 — Refactor customer list with proper pagination
**Priority:** 🟠 HIGH · **Effort:** S

**Files:** `apps/cb_dashboard/src/app/(app)/customers/page.tsx`

**Acceptance criteria:**
- [ ] Server-side pagination (not client-side slice)
- [ ] Page size selector (25, 50, 100)
- [ ] Total count shown

---

## Phase 3 — Phase 1 Completions (API & Internationalization)

### PH3-TASK-001 — Complete OpenAPI 3.0 specification for all endpoints
**Priority:** 🟡 MEDIUM · **Effort:** L

**What:** Close the 43-gap OpenAPI spec. All 94 endpoints should be documented.

**Files:**
- `apps/cb_integration/src/handlers/cb_openapi_handler.erl` — extend with all missing specs
- Cross-reference `audit/endpoint-inventory.md` and `audit/coverage-matrix.csv`

**Acceptance criteria:**
- [ ] All 94 endpoints documented in OpenAPI spec
- [ ] All schemas have type, description, example
- [ ] All endpoints have summary and operationId

---

### PH3-TASK-002 — GraphQL gateway layer extension
**Priority:** 🟡 MEDIUM · **Effort:** M

**What:** Extend `cb_graphql.erl` beyond skeleton to cover full schema.

**Files:**
- `apps/cb_integration/src/cb_graphql.erl` — add resolvers for all entities

**Acceptance criteria:**
- [ ] Party, Account, Transaction, LedgerEntry types fully resolvable
- [ ] Pagination support for list queries

---

### PH3-TASK-003 — API usage analytics dashboard
**Priority:** 🟡 MEDIUM · **Effort:** S

**What:** Wire `cb_api_usage.erl` data into a dashboard view.

**Files:**
- `apps/cb_dashboard/src/app/(app)/developer/usage/page.tsx` — new page
- `apps/cb_dashboard/src/lib/api.ts` — add usage API methods

**Acceptance criteria:**
- [ ] Usage chart: requests per key per day (bar chart)
- [ ] Top endpoints by volume
- [ ] Rate limit utilization gauge per key

---

### PH3-TASK-004 — API contract testing automation
**Priority:** 🟡 MEDIUM · **Effort:** M

**What:** Add `rebar3 ct` suite for API contract testing against live running system.

**Files:**
- `apps/cb_integration/test/cb_api_contract_SUITE.erl` — new test suite
- `apps/cb_integration/test/cb_api_baseline_SUITE.erl` — extend existing

**Acceptance criteria:**
- [ ] All documented endpoints have positive and negative test cases
- [ ] Contract tests run in CI against a seeded test environment

---

## Phase 4 — Phase 2 Completions (Compliance & Channels)

### PH4-TASK-001 — KYC workflow builder engine UI
**Priority:** 🟡 MEDIUM · **Effort:** L

**What:** Visual workflow builder for KYC steps.

**Files:**
- `apps/cb_dashboard/src/app/(app)/compliance/kyc-builder/page.tsx` — new page
- `apps/cb_compliance/src/cb_kyc_workflow.erl` — add `create_workflow/1`, `update_workflow/2`

**Acceptance criteria:**
- [ ] Drag-and-drop KYC step sequencing
- [ ] Step types: document_upload, id_verification, manual_review, automated_check
- [ ] Workflow versioning with rollback

---

### PH4-TASK-002 — Transaction monitoring rule definition UI
**Priority:** 🟡 MEDIUM · **Effort:** M

**What:** UI for defining AML rules.

**Files:**
- `apps/cb_dashboard/src/app/(app)/compliance/rules/page.tsx` — new page
- `apps/cb_compliance/src/cb_aml.erl` — add `create_rule_from_map/1`

**Acceptance criteria:**
- [ ] Rule builder: IF [field] [operator] [value] THEN [action]
- [ ] Test rule against historical transactions before activating
- [ ] Rule versioning

---

### PH4-TASK-003 — Compliance dashboard
**Priority:** 🟡 MEDIUM · **Effort:** M

**What:** Dedicated compliance monitoring dashboard.

**Files:**
- `apps/cb_dashboard/src/app/(app)/compliance/dashboard/page.tsx` — new page
- Aggregate: AML cases, SARs, KYC queue, risk tiers distribution

**Acceptance criteria:**
- [ ] AML case queue with status filtering
- [ ] SAR submission history
- [ ] KYC refresh schedule calendar

---

### PH4-TASK-004 — Channel preference management per customer
**Priority:** 🟡 MEDIUM · **Effort:** S

**What:** Let customers choose notification channels per event type.

**Files:**
- `apps/cb_channels/src/cb_channel_preferences.erl` — new module
- `apps/cb_integration/src/handlers/cb_channel_preferences_handler.erl` — new handler
- `apps/cb_integration/src/cb_router.erl` — register routes
- `apps/cb_dashboard/src/app/(app)/settings/channels/page.tsx` — new page

**Acceptance criteria:**
- [ ] Per event type: select email/SMS/push/in-app
- [ ] Customer sees preference center in settings

---

### PH4-TASK-005 — Real-time channel availability monitoring
**Priority:** 🟡 MEDIUM · **Effort:** S

**What:** Health status for each channel (web, mobile, ATM, branch).

**Files:**
- `apps/cb_channels/src/cb_channel_monitor.erl` — new module
- `apps/cb_integration/src/handlers/cb_channel_status_handler.erl` — new handler
- `apps/cb_integration/src/cb_router.erl` — register `GET /api/v1/channels/status`
- `apps/cb_dashboard/src/app/(app)/settings/channel-status/page.tsx` — new page

**Acceptance criteria:**
- [ ] Real-time status: online/degraded/offline per channel
- [ ] Incident log with duration

---

## Phase 5 — Phase 3 Completions (Automation & Ecosystem)

### PH5-TASK-001 — Automated sanctions screening integration
**Priority:** 🟡 MEDIUM · **Effort:** M

**What:** Integrate sanctions screening at transaction pre-validation.

**Files:**
- `apps/cb_compliance/src/cb_sanctions_screening.erl` — new module:
  - `screen_party/1` → `{ok, result, score}` (hit/no-hit/pending)
  - `screen_transaction/1` → same
  - Pluggable provider: OFAC, EU Sanctions List, custom
- `apps/cb_approvals/src/cb_stp_hooks.erl` — call sanctions screening at pre-validation
- `apps/cb_integration/src/cb_schema.erl` — add `sanctions_screen_result` table spec

**Acceptance criteria:**
- [ ] All new parties screened before account activation
- [ ] High-risk transactions screened before SWIFT submission
- [ ] Results logged for audit

---

### PH5-TASK-002 — STP rate tracking dashboard
**Priority:** 🟡 MEDIUM · **Effort:** S

**What:** Dashboard view for straight-through processing rates.

**Files:**
- `apps/cb_dashboard/src/app/(app)/reports/stp/page.tsx` — new page
- `apps/cb_approvals/src/cb_stp_metrics.erl` — ensure data exposed via API
- `apps/cb_integration/src/handlers/cb_stp_metrics_handler.erl` — new handler
- `apps/cb_integration/src/cb_router.erl` — register

**Acceptance criteria:**
- [ ] STP rate % displayed (target: >95%)
- [ ] Breakdown by transaction type and channel
- [ ] Trend chart (last 30 days)

---

### PH5-TASK-003 — Connector abstraction framework completion
**Priority:** 🟡 MEDIUM · **Effort:** M

**What:** Complete connector versioning and compatibility management.

**Files:**
- `apps/cb_marketplace/src/cb_connector_versions.erl` — extend with `check_compatibility/2`
- `apps/cb_marketplace/src/cb_partner_onboarding.erl` — complete workflow
- `apps/cb_integration/src/cb_router.erl` — register partner onboarding routes
- `apps/cb_dashboard/src/app/(app)/marketplace/connectors/page.tsx` — new page

**Acceptance criteria:**
- [ ] Connectors listed with version compatibility status
- [ ] Partner onboarding workflow UI: apply → review → approve → configure

---

### PH5-TASK-004 — Marketplace listing and discovery UI
**Priority:** 🟡 MEDIUM · **Effort:** M

**What:** Public marketplace for third-party service connectors.

**Files:**
- `apps/cb_dashboard/src/app/(app)/marketplace/listings/page.tsx` — new page
- `apps/cb_marketplace/src/cb_marketplace.erl` — extend with listing management

**Acceptance criteria:**
- [ ] Listing catalog with categories and search
- [ ] One-click install for compatible connectors

---

### PH5-TASK-005 — Cross-border payment routing optimization
**Priority:** 🟡 MEDIUM · **Effort:** L

**What:** Rule-based router that selects best payment rail per transaction.

**Files:**
- `apps/cb_payments/src/cb_payment_router.erl` — new module:
  - `route_payment/1` → `{ok, Route, EstimatedCost, EstimatedTime}`
  - Rules: amount, currency, destination country, urgency
- `apps/cb_payments/src/cb_payment_rails.erl` — new module defining available rails
- `apps/cb_integration/src/cb_router.erl` — register routes for rail config

**Acceptance criteria:**
- [ ] Router selects cheapest rail automatically when amount > threshold
- [ ] Manual override available per transaction
- [ ] Cost and time estimates visible before confirmation

---

### PH5-TASK-006 — International payment tracking (SWIFT trace)
**Priority:** 🟡 MEDIUM · **Effort:** M

**What:** UETR tracking for cross-border SWIFT payments.

**Files:**
- `apps/cb_payments/src/cb_payment_tracker.erl` — new module:
  - `track_payment(UETR)` → `{ok, Status, History}`
  - Integrates with SWIFT Gateway for status updates
- `apps/cb_integration/src/handlers/cb_payment_tracker_handler.erl` — new handler
- `apps/cb_integration/src/cb_router.erl` — register `GET /api/v1/payments/track/:uetrr`

**Dashboard files:**
- `apps/cb_dashboard/src/app/(app)/payments/[orderId]/tracking/page.tsx` — new page

**Acceptance criteria:**
- [ ] Track by UETR (SWIFT unique end-to-end transaction reference)
- [ ] Status history with timestamps and locations
- [ ] Estimated delivery time

---

### PH5-TASK-007 — Payment analytics and reporting module
**Priority:** 🟡 MEDIUM · **Effort:** M

**What:** Payment-specific analytics beyond general ledger.

**Files:**
- `apps/cb_reporting/src/cb_payment_analytics.erl` — new module:
  - `payment_volume_by_channel/1`, `payment_success_rate/1`, `avg_payment_value/1`
  - `payment_router_stats/1`
- `apps/cb_integration/src/handlers/cb_payment_analytics_handler.erl` — new handler
- `apps/cb_integration/src/cb_router.erl` — register
- `apps/cb_dashboard/src/app/(app)/reports/payments/page.tsx` — new page

**Acceptance criteria:**
- [ ] Volume charts by currency, channel, direction (in/out)
- [ ] Failure reason breakdown
- [ ] Cost analysis by payment method

---

## Phase 6 — Phase 4 Completions (Enterprise Scale)

### PH6-TASK-001 — Treasury module full implementation
**Priority:** 🟡 MEDIUM · **Effort:** L

**What:** Full cash management and liquidity pooling per `cb_treasury_handler` API surface.

**Files:**
- `apps/cb_accounts/src/cb_treasury.erl` — complete liquidity pool operations
- `apps/cb_integration/src/handlers/cb_treasury_handler.erl` — ensure all 9 endpoints implemented
- `apps/cb_integration/src/cb_openapi_handler.erl` — full OpenAPI spec
- `apps/cb_dashboard/src/app/(app)/treasury/page.tsx` — new dashboard page

**Acceptance criteria:**
- [ ] Liquidity positions tracked per currency
- [ ] Encumbrance system prevents double-pledging
- [ ] Interbank placement and maturity tracking

---

### PH6-TASK-002 — Fund transfer pricing calculation engine
**Priority:** 🟡 MEDIUM · **Effort:** M

**What:** FTP engine for internal fund transfers between business units.

**Files:**
- `apps/cb_reporting/src/cb_ftp_engine.erl` — new module:
  - `calculate_ftp(SourceAccountId, DestAccountId, Amount, Term)` → FTP cost/revenue
  - Uses product type + term to look up FTP schedule
- `apps/cb_integration/src/handlers/cb_ftp_handler.erl` — new handler
- `apps/cb_integration/src/cb_router.erl` — register
- `apps/cb_integration/src/cb_schema.erl` — add `ftp_schedule` table spec

**Acceptance criteria:**
- [ ] FTP rate per product type and term
- [ ] Monthly FTP reports per business unit
- [ ] FTP recorded on internal ledger entries

---

### PH6-TASK-003 — Real-time balance notification push
**Priority:** 🟡 MEDIUM · **Effort:** M

**What:** WebSocket or SSE push for real-time balance updates.

**Files:**
- `apps/cb_integration/src/cb_balance_push.erl` — new module:
  - `subscribe_balance(AccountId, ClientRef)` → `{ok, subscription_id}`
  - Push via SSE endpoint `/api/v1/accounts/:id/balance/stream`
- `apps/cb_integration/src/handlers/cb_balance_stream_handler.erl` — new handler
- `apps/cb_integration/src/cb_router.erl` — register SSE route
- `apps/cb_integration/src/cb_openapi_handler.erl` — add OpenAPI spec

**Dashboard files:**
- `apps/cb_dashboard/src/lib/useBalanceStream.ts` — new React hook

**Acceptance criteria:**
- [ ] Balance updates pushed within 500ms of transaction posting
- [ ] Automatic reconnection on disconnect
- [ ] Subscription tied to authenticated session

---

### PH6-TASK-004 — In-memory transaction cache layer
**Priority:** 🟡 MEDIUM · **Effort:** L

**What:** ETS-backed cache for hot transaction data.

**Files:**
- `apps/cb_integration/src/cb_txn_cache.erl` — new module:
  - `cache_transaction/1` → store in ETS with TTL
  - `get_cached_transaction/1` → read from cache (fallback to DB)
  - Cache invalidation on ledger update
- `apps/cb_integration/src/cb_schema.erl` — add `txn_cache` table spec (ETS-backed)

**Acceptance criteria:**
- [ ] Hot path reads served from ETS (sub-ms)
- [ ] TTL: 60 seconds, auto-refresh on read
- [ ] Cache miss falls through to Mnesia

---

### PH6-TASK-005 — Optimistic locking for concurrent transactions
**Priority:** 🟡 MEDIUM · **Effort:** M

**What:** Add version-based optimistic locking to account balance updates.

**Files:**
- `apps/cb_accounts/src/cb_accounts.erl` — add `account_version` field and `update_balance_optimistic/3`:
  - `update_balance_optimistic(AccountId, DeltaMinor, ExpectedVersion)` → `{ok, NewVersion}` or `{error, version_conflict}`
- `apps/cb_ledger/src/cb_ledger.erl` — integrate with posting flow
- `apps/cb_integration/src/cb_http_errors.erl` — add `version_conflict` error code

**Acceptance criteria:**
- [ ] Concurrent updates to same account detected and rejected with 409
- [ ] Client retries with fresh balance on conflict
- [ ] No data loss or inconsistency

---

### PH6-TASK-006 — Immutable audit log with cryptographic chaining
**Priority:** 🟡 MEDIUM · **Effort:** M

**What:** Extend `cb_audit_chain.erl` with SHA-256 chaining.

**Files:**
- `apps/cb_ledger/src/cb_audit_chain.erl` — add `compute_chained_hash/2` using SHA-256:
  - Each entry includes `previous_hash` field
  - Genesis entry uses genesis block hash
  - `verify_chain/1` → validates entire chain integrity

**Acceptance criteria:**
- [ ] Tampering with any historical entry breaks chain verification
- [ ] `verify_chain/1` returns `{ok, valid}` or `{error, tampered, entry_id}`
- [ ] Verification can be run on-demand or scheduled

---

### PH6-TASK-007 — Cross-module transaction linking
**Priority:** 🟡 MEDIUM · **Effort:** L

**What:** Ability to link related transactions across modules (e.g., loan disbursement + repayment).

**Files:**
- `apps/cb_ledger/src/cb_txn_links.erl` — new module:
  - `link_transactions(PrimaryTxnId, LinkedTxnId, LinkType)` → ok
  - `get_linked_transactions/1` → list
  - Link types: `related`, `reversal`, `split`, `parent_child`
- `apps/cb_integration/src/cb_schema.erl` — add `transaction_link` table spec
- `apps/cb_integration/src/cb_router.erl` — register:
  - `POST /api/v1/transactions/:txn_id/links`
  - `GET /api/v1/transactions/:txn_id/links`
- `apps/cb_integration/src/cb_openapi_handler.erl` — add OpenAPI spec

**Acceptance criteria:**
- [ ] Linked transactions shown as a group in UI
- [ ] Link type labels visible in transaction detail
- [ ] Reporting can filter by linked groups

---

## Phase 7 — Phase 5 Completions (Intelligence)

### PH7-TASK-001 — Transaction categorization ML model integration
**Priority:** 🟡 MEDIUM · **Effort:** L

**What:** Integrate ML model for auto-categorization of transactions.

**Files:**
- `apps/cb_analytics/src/cb_txn_categorizer.erl` — new module:
  - `categorize_transaction/1` → `{ok, Category, Confidence}`
  - Model served via REST (external) or embedded (Edge)
  - Fallback rules when model unavailable
- `apps/cb_payments/src/cb_payments.erl` — call categorizer at transaction creation
- `apps/cb_integration/src/cb_schema.erl` — add `txn_category` table spec

**Acceptance criteria:**
- [ ] Transactions auto-categorized at creation
- [ ] Category editable by user (override)
- [ ] Model retraining trigger when override rate > 20%

---

### PH7-TASK-002 — Customer lifetime value and churn scoring
**Priority:** 🟡 MEDIUM · **Effort:** M

**What:** Add CLV prediction and churn risk scoring.

**Files:**
- `apps/cb_analytics/src/cb_clv_model.erl` — new module:
  - `calculate_clv/1` → `{ok, clv_minor, clv_band}`
  - Uses: tenure, transaction volume, product count, engagement score
- `apps/cb_analytics/src/cb_churn_model.erl` — new module:
  - `score_churn_risk/1` → `{ok, risk_score_0_100, risk_band}`
  - Bands: low (<30), medium (30-60), high (>60)
- `apps/cb_integration/src/cb_router.erl` — register:
  - `GET /api/v1/parties/:party_id/clv`
  - `GET /api/v1/parties/:party_id/churn-risk`
- `apps/cb_dashboard/src/app/(app)/customers/[partyId]/insights/page.tsx` — new page

**Acceptance criteria:**
- [ ] CLV displayed in customer detail view
- [ ] Churn risk shown as a gauge component
- [ ] High-risk customers highlighted in list view

---

### PH7-TASK-003 — Behavioral anomaly detection for fraud
**Priority:** 🟡 MEDIUM · **Effort:** L

**What:** Rule + statistical anomaly detection on transaction patterns.

**Files:**
- `apps/cb_analytics/src/cb_anomaly_detector.erl` — new module:
  - `detect_anomaly/1` → `{ok, is_anomaly, anomaly_score, factors}`
  - Methods: z-score on amount, frequency analysis, geo-velocity check
- `apps/cb_approvals/src/cb_stp_hooks.erl` — call anomaly detector at pre-validation
- `apps/cb_compliance/src/cb_aml.erl` — escalate to AML case if anomaly score > threshold

**Acceptance criteria:**
- [ ] Normal transaction baseline learned per customer (30-day rolling window)
- [ ] Anomaly detection runs without blocking transaction (async)
- [ ] Alerts routed to compliance queue when anomaly detected

---

### PH7-TASK-004 — Smart contract runtime environment
**Priority:** 🔴 LOW · **Effort:** XL

**Status checkpoint (2026-05-14):** TASK-081 completed via design spec at `docs/superpowers/specs/2026-05-14-smart-contract-runtime-design.md`; TASK-082 completed via `apps/cb_contracts` scaffold + bounded evaluator runtime; TASK-083 completed via contract registry, version lifecycle, migration APIs, and integration routes; TASK-084 completed via variant experiments and persisted execution replay endpoints.

**What:** Design and implement smart contract DSL and execution engine. This is Phase 5 and requires significant architecture work.

**Design document first:** See `docs/superpowers/specs/` for a design spec before any implementation.

**Files (overview — design first):**
- `apps/cb_contracts/src/` — new app for contract runtime
- Contract DSL grammar (initially simple rule-based, not full Turing-complete)
- Execution sandbox with metering
- Product template library

**Acceptance criteria:**
- [x] Design spec approved before any code
- [x] MVP: simple if-then product rules expressible as smart contracts
- [x] Contract execution audited and reversible in MVP phase

---

## Verification Gate

After each phase, run from repository root:

```bash
# Erlang backend
rebar3 compile
rebar3 ct
rebar3 dialyzer
rebar3 proper

# Dashboard frontend
cd apps/cb_dashboard
npm ci
npm run lint
npm run build
```

---

## Priority Summary Table

| Phase | Priority | Tasks | Key Items |
|---|---|---|---|
| **PH0** | 🚨 CRITICAL | 2 | KYC fix, Account N+1 |
| **PH1** | 🚨 CRITICAL | 19 | Customer merge, trial balance, statement, adjustment, SLA |
| **PH2** | 🟠 HIGH | 2 | Dashboard refactors |
| **PH3** | 🟡 MEDIUM | 4 | OpenAPI completion, GraphQL, API analytics, contract tests |
| **PH4** | 🟡 MEDIUM | 5 | KYC builder, AML rules UI, compliance dashboard, channel prefs |
| **PH5** | 🟡 MEDIUM | 7 | Sanctions screening, STP dashboard, payment routing, marketplace |
| **PH6** | 🟡 MEDIUM | 7 | Treasury, FTP, balance push, txn cache, locking, audit chain |
| **PH7** | 🟡 MEDIUM | 4 | ML categorization, CLV/churn, anomaly detection, smart contracts |

**Total: 50 discrete implementation tasks across 8 phases.**