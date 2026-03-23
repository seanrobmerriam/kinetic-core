---
goal: IronLedger 1.1 Deliverable Plan
version: 1.0
date_created: 2026-03-23
last_updated: 2026-03-23
owner: Sean
status: Proposed
tags: [feature, roadmap, release, 1.1, controls]
---

# Introduction

This plan translates the 1.1 product direction into implementation work.

The 1.1 theme is: controls, configuration, and integration readiness.

## 1. Strategic Decision

Version 1.1 should not try to out-feature enterprise banking suites. It should close the biggest credibility gaps between a deployable prototype and a modern banking platform:

1. Security and entitlements
2. Product configuration and pricing controls
3. Operational controls like holds and approvals
4. Integration surfaces like events, webhooks, and exports
5. Customer lifecycle and KYC state

## 2. Feature List

### Priority A

1. Authentication and session management
2. RBAC and operator permissions
3. Maker-checker approval workflows
4. Product fees, limits, and versions
5. Internal system accounts and posting templates
6. Holds and available balance
7. Event outbox and webhooks
8. Statements and CSV exports

### Priority B

9. Customer onboarding and KYC state
10. Notifications
11. Payment rails abstraction
12. Collections and delinquency workflows

### Priority C

13. Multi-currency and FX
14. Analytics-ready read models
15. AI-assisted operational workflows

## 3. Implementation Phases

### Phase 1: Security Foundation

Goal:

- Add access control without destabilizing the 1.0 runtime

Tasks:

- Create a new auth app, likely `cb_auth`, for user identities, password handling, sessions, and role checks
- Add an authenticated API gateway layer in `cb_integration`
- Add dashboard login and session handling in `apps/cb_dashboard/`
- Define roles and permission checks for write operations
- Add audit records for login, approval, and administrative actions

Exit criteria:

- Dashboard requires login
- API rejects unauthorized requests
- Roles are enforced for at least admin, operator, and read-only user classes

### Phase 2: Product Factory V2

Goal:

- Make account, savings, and loan behavior configurable

Tasks:

- Add product versioning to savings and loan products
- Add fee schedule support
- Add configurable limits such as min or max transfer, withdrawal, and approval thresholds
- Add activation and deactivation workflows for product versions
- Introduce a product rules module or app instead of embedding more logic in handler code

Likely touch points:

- `apps/cb_savings_products/`
- `apps/cb_loans/`
- `apps/cb_integration/src/handlers/`
- `docs/api-contract.yaml`

Exit criteria:

- At least one fee and one limit can be configured through product definitions
- Product behavior changes without code changes

### Phase 3: Ledger Controls

Goal:

- Add banking realism to the account model

Tasks:

- Add funds holds or encumbrances
- Separate ledger balance from available balance
- Generalize system or internal accounts for fees, interest, and operational postings
- Add posting templates or posting rules for recurring internal movements
- Add scheduled jobs for fee assessment, statement generation, or maturity actions

Likely touch points:

- `apps/cb_ledger/`
- `apps/cb_accounts/`
- `apps/cb_payments/`
- `apps/cb_interest/`

Exit criteria:

- Holds affect available balance
- Internal postings use configured accounts and rules

### Phase 4: Events, Webhooks, and Reporting

Goal:

- Make IronLedger integration-friendly

Tasks:

- Add an outbox or event app, likely `cb_events`
- Emit events for transaction posting, account lifecycle changes, product changes, and loan events
- Add webhook delivery and retry behavior
- Add downloadable statements and CSV exports
- Add read models or export-friendly reporting endpoints

Likely touch points:

- `apps/cb_integration/`
- new `apps/cb_events/`
- `apps/cb_dashboard/`

Exit criteria:

- At least one event stream or webhook path is live
- Statements and exports are available through the dashboard

### Phase 5: Customer Lifecycle and KYC

Goal:

- Move party management closer to real onboarding flows

Tasks:

- Extend `cb_party` with onboarding or KYC status, review notes, and document metadata
- Add dashboard views for KYC review state
- Add approval workflows for status changes
- Add risk or compliance flags visible to operators

Exit criteria:

- Party records include KYC state
- Status is visible and manageable through the dashboard

## 4. Recommended Order

Recommended order:

1. Security Foundation
2. Product Factory V2
3. Ledger Controls
4. Events, Webhooks, and Reporting
5. Customer Lifecycle and KYC
6. Payment rails abstraction if time remains

Reasoning:

- Security and approvals should exist before adding more operational power
- Product configuration and ledger controls build directly on the strongest current code
- Eventing and reporting unlock integrations and future AI without forcing a major platform rewrite

## 5. Technical Risks

- Auth touches every API route and dashboard request path
- Holds and balance-state changes can introduce subtle ledger regressions
- Webhooks require reliable retry and failure handling to avoid operational ambiguity
- Product factory work can become a large abstraction exercise if not constrained to fees, limits, and versions first

## 6. Suggested 1.1 Release Gate

Add these to the existing 1.0 gate:

- Auth integration tests
- Approval workflow dashboard E2E tests
- Hold and balance invariant PropEr tests
- Webhook or event outbox tests
- Statement or export generation tests

## 7. Recommendation

Recommendation:

- Treat 1.1 as an operational maturity release, not a business-line expansion release

This is the shortest path from a strong 1.0 demo to a credible next-gen banking platform.
