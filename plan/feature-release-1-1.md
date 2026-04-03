# IronLedger 1.1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the full 1.1 release as a controlled, configurable, integration-ready banking runtime while preserving all 1.0 workflows.

**Architecture:** Build 1.1 in layered increments: first add cross-cutting control-plane capabilities (auth, permissions, approvals, audit), then extend product and ledger domain models, then expose integration/reporting surfaces, then complete customer lifecycle and dashboard operations. Keep the current OTP app layout, Cowboy router, Mnesia schema, and Go/Wasm dashboard, but introduce a small number of focused OTP apps for new cross-cutting responsibilities instead of pushing more behavior into existing handlers.

**Tech Stack:** Erlang/OTP 25, Mnesia, Cowboy, Common Test, PropEr, Go/WebAssembly dashboard, Playwright E2E.

---

## Planning Assumptions

- This plan targets the full 1.1 scope from [spec/process-release-1-1.md](/Users/sean/workspace/projects/github.com/ironledger/ironledger/spec/process-release-1-1.md), not a reduced MVP.
- The current workspace does not contain the `docs/` tree referenced by `README.md`, so 1.1 must treat missing documentation and OpenAPI artifacts as deliverables, not existing dependencies.
- 1.0 behavior is implemented directly in OTP apps plus Cowboy handlers. There is no existing auth layer, policy engine, approval engine, outbox, reporting module, or scheduled job subsystem.
- The dashboard is entirely client-side Go/Wasm and currently calls unauthenticated JSON endpoints directly.
- Mnesia is still `ram_copies` only. 1.1 should not try to solve clustering or durable production storage, but it must preserve correctness and testability in the current single-node model.

## Current Codebase Map

### Existing Runtime Surface

- `apps/cb_integration/src/cb_router.erl`
  Routes all API endpoints. This is the choke point for auth, approvals, reporting, and webhook routes.
- `apps/cb_integration/src/cb_schema.erl`
  Owns shared Mnesia table creation for most domain tables. New cross-app tables should be registered here unless the schema boot model is intentionally changed.
- `apps/cb_integration/src/handlers/*.erl`
  Thin JSON handlers for parties, accounts, transactions, products, loans, and stats. 1.1 should keep handlers thin and push new business rules into domain apps.
- `apps/cb_accounts/src/cb_accounts.erl`
  Owns account lifecycle and balance reads. This is the natural home for available-balance and hold-aware account behavior.
- `apps/cb_payments/src/cb_payments.erl`
  Owns posted transaction flows and mutable account balance updates. Holds, limits, templates, and approvals will change this file materially.
- `apps/cb_party/src/cb_party.erl`
  Owns party lifecycle. KYC state and onboarding metadata should extend this boundary.
- `apps/cb_savings_products/src/cb_savings_products.erl`
  Savings product CRUD. Product versioning, fees, and limits should extend this module or a sibling rules module, not handlers.
- `apps/cb_loans/src/cb_loan_products.erl`
  Loan product CRUD via gen_server. Product versioning, fees, and limits should extend this app.
- `apps/cb_loans/src/cb_loan_accounts.erl`
  Current loan lifecycle with direct approve and disburse transitions. Approval workflows will need to intercept this behavior.
- `apps/cb_interest/src/*.erl`
  Existing batch-style interest logic. Reuse its OTP patterns for scheduled fee and maturity jobs.
- `apps/cb_dashboard/api.go`
  Central browser-side API client. Login, session propagation, approvals, exports, and KYC UI state should be added here.
- `apps/cb_dashboard/app.go`
  Global dashboard state. User session, permissions, and approval inbox belong here.
- `apps/cb_dashboard/views.go`
  Current UI views and forms. This is the main dashboard change surface for login, approvals, exports, statements, and KYC.
- `test/dashboard-e2e.js`
  Existing packaged browser flow. 1.1 should extend it rather than replacing it.

### New App Boundaries Recommended for 1.1

- `apps/cb_auth/`
  User identities, password hashing, sessions, permission checks, auth audit events.
- `apps/cb_approvals/`
  Maker-checker workflow records, approval requests, approval decisions, approval policy checks.
- `apps/cb_events/`
  Domain event outbox, webhook subscriptions, delivery attempts, retry scheduling.
- `apps/cb_reporting/`
  Statement assembly, CSV export generation, reporting endpoints.

## Release Strategy

### Approach Options

1. Full vertical slices per feature area
   Best for visible progress, but risky because auth, approvals, and outbox concerns would be reimplemented across domains.

2. Control-plane first, then domain upgrades, then integration surfaces
   Best for this repo because current code is centralized and unauthenticated. It reduces rework by putting auth, entitlements, approvals, and audit primitives in place before product, ledger, and KYC changes depend on them.

3. Dashboard-first rollout
   Lowest backend disruption initially, but wrong for this repo because the backend currently has no authorization boundaries to enforce.

**Recommended:** Option 2. Build shared runtime controls first, then domain features, then reporting and lifecycle extensions.

## Workstreams

### Task 1: Establish 1.1 Platform Baseline

**Files:**
- Modify: `rebar.config`
- Modify: `config/sys.config`
- Modify: `README.md`
- Modify: `apps/cb_integration/src/cb_schema.erl`
- Test: `apps/cb_integration/test/cb_runtime_wiring_SUITE.erl`
- Create: `apps/cb_auth/src/*.erl`
- Create: `apps/cb_approvals/src/*.erl`
- Create: `apps/cb_events/src/*.erl`
- Create: `apps/cb_reporting/src/*.erl`

- [ ] Add new OTP applications to `rebar.config` release wiring and application dependency graph.
- [ ] Extend `cb_schema:create_tables/0` with all new 1.1 tables so test and shell boot remain one-command operations.
- [ ] Introduce shared record headers for new auth, approval, event, reporting, and account-hold data instead of overloading `cb_ledger.hrl`.
- [ ] Update runtime wiring tests to assert the new applications start cleanly and the new tables/indexes exist.
- [ ] Restore missing repo documentation references for 1.1 deliverables that the README currently claims but the workspace does not contain.

**Verification:**
- `rebar3 compile`
- `rebar3 ct --suite apps/cb_integration/test/cb_runtime_wiring_SUITE.erl`

### Task 2: Add Authentication, Sessions, and Role Enforcement

**Files:**
- Create: `apps/cb_auth/src/cb_auth.app.src`
- Create: `apps/cb_auth/src/cb_auth.erl`
- Create: `apps/cb_auth/src/cb_auth_app.erl`
- Create: `apps/cb_auth/src/cb_auth_sup.erl`
- Create: `apps/cb_auth/src/cb_auth_sessions.erl`
- Create: `apps/cb_auth/src/cb_auth_passwords.erl`
- Create: `apps/cb_auth/test/cb_auth_SUITE.erl`
- Modify: `apps/cb_integration/src/cb_router.erl`
- Modify: `apps/cb_integration/src/cb_integration_sup.erl`
- Create: `apps/cb_integration/src/cb_auth_middleware.erl`
- Create: `apps/cb_integration/src/handlers/cb_login_handler.erl`
- Create: `apps/cb_integration/src/handlers/cb_logout_handler.erl`
- Create: `apps/cb_integration/src/handlers/cb_me_handler.erl`
- Modify: `apps/cb_integration/test/cb_http_errors_SUITE.erl`
- Create: `apps/cb_integration/test/cb_auth_integration_SUITE.erl`
- Modify: `apps/cb_dashboard/api.go`
- Modify: `apps/cb_dashboard/app.go`
- Modify: `apps/cb_dashboard/views.go`
- Modify: `test/dashboard-e2e.js`

- [ ] Implement user creation, password hashing, session issuance, session lookup, and session invalidation in `cb_auth`.
- [ ] Define at least `admin`, `operations`, and `read_only` roles and a permission matrix for all mutating API endpoints.
- [ ] Add Cowboy auth middleware that leaves `/health` and login/logout routes public but requires authenticated sessions everywhere else.
- [ ] Add dashboard login, logout, session bootstrap, and permission-aware navigation.
- [ ] Record login, logout, failed login, and admin-role operations in an auth audit trail.

**Verification:**
- `rebar3 ct --suite apps/cb_auth/test/cb_auth_SUITE.erl`
- `rebar3 ct --suite apps/cb_integration/test/cb_auth_integration_SUITE.erl`
- `npm run test:e2e`

### Task 3: Introduce Audit Trail and Approval Infrastructure

**Files:**
- Create: `apps/cb_approvals/src/cb_approvals.app.src`
- Create: `apps/cb_approvals/src/cb_approvals.erl`
- Create: `apps/cb_approvals/src/cb_approvals_app.erl`
- Create: `apps/cb_approvals/src/cb_approvals_sup.erl`
- Create: `apps/cb_approvals/test/cb_approvals_SUITE.erl`
- Modify: `apps/cb_integration/src/cb_http_errors.erl`
- Create: `apps/cb_integration/src/handlers/cb_approvals_handler.erl`
- Create: `apps/cb_integration/src/handlers/cb_audit_handler.erl`
- Modify: `apps/cb_integration/src/cb_router.erl`
- Modify: `apps/cb_dashboard/api.go`
- Modify: `apps/cb_dashboard/app.go`
- Modify: `apps/cb_dashboard/views.go`
- Modify: `test/dashboard-e2e.js`

- [ ] Create generic approval-request records with `resource_type`, `resource_id`, `action`, `requested_by`, `status`, and decision history.
- [ ] Introduce approval policy evaluation based on role, amount, and operation type so high-risk writes can become `pending_approval` instead of posting immediately.
- [ ] Add dashboard approval inbox and decision actions.
- [ ] Add audit browsing endpoints sufficient for operator review and debugging.

**Verification:**
- `rebar3 ct --suite apps/cb_approvals/test/cb_approvals_SUITE.erl`
- `rebar3 ct --suite apps/cb_integration/test/cb_auth_integration_SUITE.erl`

### Task 4: Apply Maker-Checker to Real Operational Flows

**Files:**
- Modify: `apps/cb_payments/src/cb_payments.erl`
- Modify: `apps/cb_loans/src/cb_loan_accounts.erl`
- Modify: `apps/cb_integration/src/handlers/cb_transaction_transfer_handler.erl`
- Modify: `apps/cb_integration/src/handlers/cb_transaction_deposit_handler.erl`
- Modify: `apps/cb_integration/src/handlers/cb_transaction_withdraw_handler.erl`
- Modify: `apps/cb_integration/src/handlers/cb_transaction_adjustment_handler.erl`
- Modify: `apps/cb_integration/src/handlers/cb_loans_handler.erl`
- Test: `apps/cb_payments/test/cb_payments_SUITE.erl`
- Test: `apps/cb_loans/test/cb_loans_SUITE.erl`
- Test: `apps/cb_integration/test/cb_auth_integration_SUITE.erl`
- Modify: `test/dashboard-e2e.js`

- [ ] Convert at least one payment flow and one loan lifecycle action to approval-gated execution.
- [ ] Ensure approved operations are replayable exactly once and preserve idempotency semantics.
- [ ] Make the dashboard show pending, approved, rejected, and executed states instead of assuming direct success for all writes.
- [ ] Preserve existing direct-post behavior when a policy says approval is not required.

**Verification:**
- `rebar3 ct --suite apps/cb_payments/test/cb_payments_SUITE.erl`
- `rebar3 ct --suite apps/cb_loans/test/cb_loans_SUITE.erl`
- `npm run test:e2e`

### Task 5: Upgrade Product Factory for Versions, Fees, and Limits

**Files:**
- Modify: `apps/cb_savings_products/src/cb_savings_products.erl`
- Modify: `apps/cb_loans/src/cb_loan_products.erl`
- Create: `apps/cb_savings_products/include/savings_rules.hrl`
- Create: `apps/cb_loans/include/loan_rules.hrl`
- Create: `apps/cb_savings_products/test/cb_savings_products_rules_SUITE.erl`
- Create: `apps/cb_loans/test/cb_loan_products_rules_SUITE.erl`
- Modify: `apps/cb_integration/src/handlers/cb_savings_products_handler.erl`
- Modify: `apps/cb_integration/src/handlers/cb_loan_products_handler.erl`
- Modify: `apps/cb_dashboard/api.go`
- Modify: `apps/cb_dashboard/app.go`
- Modify: `apps/cb_dashboard/views.go`

- [ ] Add product version records so a product can have multiple inactive and active definitions without destructive updates.
- [ ] Model fee schedules and operational limits in the domain layer, not as ad hoc handler fields.
- [ ] Add activation and deactivation semantics for product versions.
- [ ] Apply configured limits to payment and loan creation flows through reusable validation functions.
- [ ] Keep existing 1.0 create/list flows backward compatible by defaulting old products into version `1`.

**Verification:**
- `rebar3 ct --suite apps/cb_savings_products/test/cb_savings_products_SUITE.erl`
- `rebar3 ct --suite apps/cb_savings_products/test/cb_savings_products_rules_SUITE.erl`
- `rebar3 ct --suite apps/cb_loans/test/cb_loans_SUITE.erl`
- `rebar3 ct --suite apps/cb_loans/test/cb_loan_products_rules_SUITE.erl`

### Task 6: Add Holds, Available Balance, and Internal Posting Controls

**Files:**
- Modify: `apps/cb_accounts/src/cb_accounts.erl`
- Create: `apps/cb_accounts/src/cb_account_holds.erl`
- Create: `apps/cb_accounts/test/cb_account_holds_SUITE.erl`
- Modify: `apps/cb_payments/src/cb_payments.erl`
- Modify: `apps/cb_ledger/include/cb_ledger.hrl`
- Create: `apps/cb_ledger/src/cb_posting_templates.erl`
- Create: `apps/cb_ledger/test/cb_posting_templates_SUITE.erl`
- Modify: `apps/cb_integration/src/handlers/cb_account_balance_handler.erl`
- Create: `apps/cb_integration/src/handlers/cb_account_holds_handler.erl`
- Modify: `apps/cb_integration/src/cb_router.erl`
- Modify: `apps/cb_dashboard/api.go`
- Modify: `apps/cb_dashboard/app.go`
- Modify: `apps/cb_dashboard/views.go`
- Test: `test/prop_generators.hrl`
- Create: `apps/cb_accounts/test/prop_account_holds.erl`

- [ ] Extend account data to distinguish ledger balance from available balance without breaking current balance reads.
- [ ] Add hold placement, release, expiration, and reason capture.
- [ ] Enforce hold-aware funds checks in payments and loan-related postings.
- [ ] Introduce internal/system-account configuration and posting templates for fees, interest, and operational adjustments.
- [ ] Reuse the new posting-template layer for future scheduled jobs instead of scattering internal posting logic across modules.

**Verification:**
- `rebar3 ct --suite apps/cb_accounts/test/cb_accounts_SUITE.erl`
- `rebar3 ct --suite apps/cb_accounts/test/cb_account_holds_SUITE.erl`
- `rebar3 proper --module=prop_account_holds`
- `rebar3 ct --suite apps/cb_ledger/test/cb_posting_templates_SUITE.erl`

### Task 7: Add Scheduled Operational Jobs

**Files:**
- Create: `apps/cb_reporting/src/cb_jobs.erl`
- Modify: `apps/cb_interest/src/cb_interest_accrual.erl`
- Modify: `apps/cb_interest/src/cb_interest_posting.erl`
- Modify: `apps/cb_ledger/src/cb_posting_templates.erl`
- Create: `apps/cb_reporting/test/cb_jobs_SUITE.erl`

- [ ] Introduce a lightweight OTP job runner pattern for fee assessment, statement generation, maturity actions, and webhook retry processing.
- [ ] Wire the runner so jobs are explicit, idempotent, and callable from tests without waiting on real wall-clock scheduling.
- [ ] Use the same infrastructure for event retry and statement generation later in the plan.

**Verification:**
- `rebar3 ct --suite apps/cb_reporting/test/cb_jobs_SUITE.erl`
- `rebar3 ct --suite apps/cb_interest/test/cb_interest_SUITE.erl`

### Task 8: Implement Domain Events, Outbox, and Webhooks

**Files:**
- Create: `apps/cb_events/src/cb_events.app.src`
- Create: `apps/cb_events/src/cb_events.erl`
- Create: `apps/cb_events/src/cb_events_app.erl`
- Create: `apps/cb_events/src/cb_events_sup.erl`
- Create: `apps/cb_events/src/cb_webhooks.erl`
- Create: `apps/cb_events/test/cb_events_SUITE.erl`
- Modify: `apps/cb_payments/src/cb_payments.erl`
- Modify: `apps/cb_loans/src/cb_loan_accounts.erl`
- Modify: `apps/cb_savings_products/src/cb_savings_products.erl`
- Modify: `apps/cb_loans/src/cb_loan_products.erl`
- Create: `apps/cb_integration/src/handlers/cb_webhooks_handler.erl`
- Create: `apps/cb_integration/src/handlers/cb_events_handler.erl`
- Modify: `apps/cb_integration/src/cb_router.erl`
- Modify: `apps/cb_dashboard/api.go`
- Modify: `apps/cb_dashboard/views.go`

- [ ] Emit outbox events for posted transactions, loan lifecycle changes, and product version changes inside the same transaction that mutates the source record.
- [ ] Add webhook subscription CRUD, delivery records, retry attempts, and dead-letter visibility.
- [ ] Expose operator endpoints for replay and failure inspection.
- [ ] Use the scheduled-job runner from Task 7 for webhook retries.

**Verification:**
- `rebar3 ct --suite apps/cb_events/test/cb_events_SUITE.erl`
- `rebar3 ct --suite apps/cb_loans/test/cb_loans_SUITE.erl`
- `rebar3 ct --suite apps/cb_payments/test/cb_payments_SUITE.erl`

### Task 9: Add Statements, CSV Exports, and Read Models

**Files:**
- Create: `apps/cb_reporting/src/cb_reporting.app.src`
- Create: `apps/cb_reporting/src/cb_reporting_app.erl`
- Create: `apps/cb_reporting/src/cb_reporting_sup.erl`
- Create: `apps/cb_reporting/src/cb_statements.erl`
- Create: `apps/cb_reporting/src/cb_exports.erl`
- Create: `apps/cb_reporting/test/cb_reporting_SUITE.erl`
- Modify: `apps/cb_integration/src/handlers/cb_account_entries_handler.erl`
- Create: `apps/cb_integration/src/handlers/cb_statements_handler.erl`
- Create: `apps/cb_integration/src/handlers/cb_exports_handler.erl`
- Modify: `apps/cb_integration/src/cb_router.erl`
- Modify: `apps/cb_dashboard/api.go`
- Modify: `apps/cb_dashboard/app.go`
- Modify: `apps/cb_dashboard/views.go`
- Modify: `test/dashboard-e2e.js`

- [ ] Build statement generation from existing account, transaction, and ledger-entry records with hold-aware balances where relevant.
- [ ] Add CSV export endpoints for accounts, transactions, loans, approvals, and events.
- [ ] Keep reporting generation server-side and expose downloadable artifacts or inline text responses through the dashboard.
- [ ] Add operator-visible export history if generation is asynchronous.

**Verification:**
- `rebar3 ct --suite apps/cb_reporting/test/cb_reporting_SUITE.erl`
- `npm run test:e2e`

### Task 10: Extend Party Lifecycle with Onboarding and KYC State

**Files:**
- Modify: `apps/cb_party/src/cb_party.erl`
- Create: `apps/cb_party/test/cb_party_kyc_SUITE.erl`
- Modify: `apps/cb_integration/src/handlers/cb_parties_handler.erl`
- Modify: `apps/cb_integration/src/handlers/cb_party_handler.erl`
- Create: `apps/cb_integration/src/handlers/cb_party_kyc_handler.erl`
- Modify: `apps/cb_integration/src/cb_router.erl`
- Modify: `apps/cb_dashboard/api.go`
- Modify: `apps/cb_dashboard/app.go`
- Modify: `apps/cb_dashboard/views.go`
- Modify: `test/dashboard-e2e.js`

- [ ] Extend the party model with onboarding status, KYC status, review notes, and document metadata references.
- [ ] Add permissioned status transitions and optionally approval-gate high-risk KYC state changes through `cb_approvals`.
- [ ] Expose KYC state in dashboard customer views and approval queues.
- [ ] Preserve current active, suspended, and closed lifecycle semantics for 1.0 compatibility.

**Verification:**
- `rebar3 ct --suite apps/cb_party/test/cb_party_SUITE.erl`
- `rebar3 ct --suite apps/cb_party/test/cb_party_kyc_SUITE.erl`
- `npm run test:e2e`

### Task 11: Tighten API Contracts and Backward Compatibility

**Files:**
- Modify: `apps/cb_integration/src/cb_http_errors.erl`
- Modify: `apps/cb_integration/src/handlers/*.erl`
- Create: `apps/cb_integration/test/cb_api_compat_SUITE.erl`
- Create: `docs/api-contract.yaml`
- Create: `docs/release-checklist-1-1.md`

- [ ] Ensure 1.0 routes remain valid unless explicitly superseded by authenticated equivalents.
- [ ] Normalize new error atoms such as `unauthorized`, `forbidden`, `approval_required`, `hold_insufficient_funds`, and webhook/reporting failures.
- [ ] Recreate the missing API contract file and document all 1.1 routes, payloads, and auth behavior.
- [ ] Add an explicit 1.1 release checklist with command evidence requirements.

**Verification:**
- `rebar3 ct --suite apps/cb_integration/test/cb_api_compat_SUITE.erl`
- `rebar3 ct --suite apps/cb_integration/test/cb_http_errors_SUITE.erl`

### Task 12: Run the Full 1.1 Release Gate

**Files:**
- Modify: `test/dashboard-e2e.js`
- Modify: `README.md`
- Modify: `docs/release-checklist-1-1.md`

- [ ] Expand the dashboard E2E flow to cover login, at least one approval workflow, at least one hold-aware operation, at least one export, and one KYC status change.
- [ ] Run the full regression gate over Common Test, PropEr, Dialyzer, and Playwright.
- [ ] Record the exact commands and outputs in the 1.1 release checklist.

**Verification:**
- `rebar3 dialyzer`
- `rebar3 ct`
- `rebar3 proper`
- `npm run test:e2e`

## Dependency Order

1. Task 1 must land first.
2. Task 2 must land before any dashboard or API changes that assume authenticated state.
3. Task 3 must land before Task 4 and before any KYC approval workflow.
4. Task 5 should precede the final hold and internal posting integration so fees and limits can inform posting rules.
5. Task 6 should precede statements and exports.
6. Task 7 should precede webhook retry and asynchronous reporting generation.
7. Task 8 should precede final release reporting, because exports and audit views should be able to include event delivery state.
8. Task 10 can overlap with Tasks 8 and 9 after auth and approvals are stable.
9. Tasks 11 and 12 are final hardening and gate tasks, not starting points.

## Major Risks and Containment

- **Auth retrofitting risk**
  Containment: add middleware and session primitives first, then convert handlers route-by-route with integration tests.

- **Approval workflow complexity risk**
  Containment: start with a generic approval engine and enable it for a narrow set of operations before broadening policy coverage.

- **Ledger regression risk from holds**
  Containment: keep ledger balance semantics unchanged and introduce available balance as a derived or separately stored control-plane concept validated by PropEr tests.

- **Schema drift risk**
  Containment: keep one authoritative schema creation path and assert table/index expectations in runtime wiring tests.

- **Dashboard regression risk**
  Containment: keep current views working behind auth, then incrementally add approval, export, and KYC screens with Playwright coverage.

## Definition of Done for 1.1

- Dashboard and mutating API routes require authentication.
- Role-based permissions are enforced for admin, operations, and read-only users.
- At least one maker-checker flow completes end-to-end in the dashboard.
- Savings or loan products support configurable versions, fees, and limits without code changes.
- Holds affect available balance without corrupting ledger balance behavior.
- Posted transactions and loan lifecycle changes emit outbox events and at least one webhook path is operational.
- Statements or CSV exports are available from the dashboard.
- Party records expose onboarding or KYC state and that state is manageable in the dashboard.
- Existing 1.0 tests and workflows still pass.

## Recommended Execution Slices

1. Platform baseline plus auth
2. Approvals plus loan/payment integration
3. Product factory upgrades
4. Holds plus posting templates
5. Events plus webhook delivery
6. Reporting plus exports
7. KYC lifecycle
8. Full regression and release evidence
