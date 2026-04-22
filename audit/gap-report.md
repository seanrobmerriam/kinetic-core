# API Coverage Gap Report

**Generated:** 2026-04-22
**Source:** `audit/endpoint-inventory.md` × `audit/dashboard-inventory.md`
**Coverage matrix:** `audit/coverage-matrix.csv`

## Summary

| Metric | Count |
|---|---:|
| Total endpoints (verb × path) | **94** |
| ✅ Covered  | **49** |
| 🟡 Partial | **1** |
| 🔴 Missing | **43** |
| 💀 Stale   | **1** |
| **Coverage** | **52%** |

### By resource group

| Resource         | Endpoints | Covered | Missing | Coverage |
|---|---:|---:|---:|---:|
| Auth             |   3 |   3 |   0 | 100% |
| Parties          |  13 |   8 |   4 |  62% |
| Accounts         |  15 |  10 |   4 |  67% |
| Transactions     |   7 |   4 |   3 |  57% |
| Ledger           |   1 |   1 |   0 | 100% |
| Savings products |   5 |   2 |   3 |  40% |
| Loan products    |   5 |   2 |   3 |  40% |
| Loans            |   7 |   7 |   0 | 100% |
| Events           |   4 |   0 |   4 |   0% |
| Webhooks         |   5 |   1 |   4 |  20% |
| Statements/export|   2 |   0 |   2 |   0% |
| Payment orders   |   5 |   3 |   2 |  60% |
| Exceptions       |   4 |   2 |   2 |  50% |
| Channels         |   4 |   3 |   1 |  75% |
| API keys         |   5 |   2 |   3 |  40% |
| Meta (openapi/metrics/graphql/depr) | 5 | 1 | 4 | 20% |
| Dev tools        |   2 |   2 |   0 | 100% |
| ATM              |   2 |   0 |   2 |   0% |
| Health           |   1 |   0 |   1 |   0% |

---

## 💀 STALE CALLS (1)

### [STALE-001] `PUT /api/v1/parties/:party_id/kyc`
- **Caller:** `app/(app)/compliance/page.tsx:272`
- **Backend reality:** `cb_party_kyc_handler` only accepts `GET`, `PATCH`, `POST`. The `PUT`
  request will return 405/404 from Cowboy and silently break the "Save KYC" button in compliance.
- **Severity:** 🔴 **CRITICAL** — production compliance workflow is broken.
- **Fix:** Change the dashboard call to `PATCH`. (Detailed in remediation task `FIX-KYC-PUT`.)

---

## 🟡 PARTIAL COVERAGE (1)

### [PARTIAL-001] `GET /api/v1/accounts/:account_id`
- **Endpoint exists** as a clean account-detail read.
- **Dashboard never calls it directly.** `accounts/[accountId]/page.tsx` instead pulls the full
  party list, then iterates through each party's accounts to find the one matching the URL — an
  N+1 anti-pattern that also leaks every customer's accounts to anyone viewing one account.
- **Severity:** 🟠 **HIGH** (performance + privacy/least-privilege concern)
- **Fix:** Replace the multi-step lookup with a single `GET /accounts/:id` and only fetch the
  owning party afterward. (Task `REFACTOR-ACCOUNT-DETAIL`.)

---

## 🔴 MISSING COVERAGE (43)

Grouped by severity. Severity assigned by financial / compliance impact:

### CRITICAL — Production safety / compliance gaps

| ID | Endpoint | Reason |
|---|---|---|
| GAP-001 | `POST /api/v1/parties/:party_id/reactivate`           | Suspended customers can never be unsuspended via UI. |
| GAP-002 | `POST /api/v1/transactions/adjustment`                | Manual ledger adjustments cannot be made — operations team has no UI for break-fix entries. |
| GAP-003 | `GET /api/v1/transactions/:txn_id`                    | No standalone transaction detail view; users see txn rows but cannot drill in. |
| GAP-004 | `GET /api/v1/transactions/:txn_id/entries`            | Cannot view the double-entry ledger lines for a transaction → audit trail invisible. |
| GAP-005 | `GET /api/v1/accounts/:account_id/statement`          | No statement download anywhere — required for AA-level customer self-service & regulatory delivery. |
| GAP-006 | `GET /api/v1/export/:resource`                        | No bulk export UI — compliance/reporting cannot extract data without API client. |
| GAP-007 | `POST /api/v1/parties/:party_id/kyc` (add doc_ref)    | KYC document references cannot be attached from the UI — compliance evidence is unrecorded. |

### HIGH — Resource lifecycle missing or one-way only

| ID | Endpoint | Reason |
|---|---|---|
| GAP-010 | `POST   /api/v1/savings-products/:id/activate`        | Products can be created but never activated through the UI. |
| GAP-011 | `POST   /api/v1/savings-products/:id/deactivate`      | No way to retire a savings product. |
| GAP-012 | `GET    /api/v1/savings-products/:id`                 | No detail view per product. |
| GAP-013 | `POST   /api/v1/loan-products/:id/activate`           | Same — loan products cannot be activated from UI. |
| GAP-014 | `POST   /api/v1/loan-products/:id/deactivate`         | Same — cannot retire. |
| GAP-015 | `GET    /api/v1/loan-products/:id`                    | No detail view. |
| GAP-016 | `POST   /api/v1/webhooks`                             | Developer page lists webhooks but cannot subscribe new ones. |
| GAP-017 | `PATCH  /api/v1/webhooks/:id`                         | Cannot edit subscriptions. |
| GAP-018 | `DELETE /api/v1/webhooks/:id`                         | Cannot delete subscriptions. |
| GAP-019 | `GET    /api/v1/webhooks/:id/deliveries`              | Cannot inspect delivery attempts → silent webhook failures invisible. |
| GAP-020 | `POST   /api/v1/api-keys`                             | API keys are listed but cannot be issued from UI. |
| GAP-021 | `DELETE /api/v1/api-keys/:id`                         | Cannot revoke leaked keys → security gap. |
| GAP-022 | `GET    /api/v1/api-keys/:id`                         | No key metadata / scopes view. |

### HIGH — Visibility into critical sub-resources

| ID | Endpoint | Reason |
|---|---|---|
| GAP-030 | `GET /api/v1/parties/:id/profile`                     | Omnichannel unified profile not surfaced anywhere on customer detail. |
| GAP-031 | `GET /api/v1/parties/:id/notification-preferences`    | Notification prefs not visible. |
| GAP-032 | `PUT /api/v1/parties/:id/notification-preferences`    | …and not editable. |
| GAP-033 | `GET /api/v1/accounts/:id/balance`                    | Available-vs-current balance not exposed; dashboard re-derives client-side from holds. |
| GAP-034 | `GET /api/v1/accounts/:id/summary`                    | Aggregate summary panel never rendered. |
| GAP-035 | `GET /api/v1/stats`                                   | Dashboard overview re-fetches per-party and per-account data instead of using the dedicated stats endpoint. |
| GAP-036 | `GET /api/v1/accounts`                                | List view that should drive `/accounts` page is bypassed in favour of nested `/parties/:id/accounts` lookups. |
| GAP-037 | `GET /api/v1/payment-orders`                          | Payments page only displays orders created in the current session — no historical list. |
| GAP-038 | `GET /api/v1/payment-orders/:id`                      | No payment-order detail page. |
| GAP-039 | `GET /api/v1/exceptions/:id`                          | Exception items have no detail view (only resolve from list). |
| GAP-040 | `GET /api/v1/channel-limits/:channel`                 | Single-channel detail not used (full list is fetched instead). |

### MEDIUM — Audit / event ops surfaces

| ID | Endpoint | Reason |
|---|---|---|
| GAP-050 | `GET  /api/v1/events`                                 | Domain-event audit log has no UI tab anywhere. |
| GAP-051 | `GET  /api/v1/events/:event_id`                       | Cannot inspect a single event payload. |
| GAP-052 | `POST /api/v1/events`                                 | Admin-only event injection (replay tooling) — no UI. |
| GAP-053 | `POST /api/v1/events/:event_id/replay`                | Cannot replay an event from UI. |

### LOW — Meta / infra / external integrations

| ID | Endpoint | Reason |
|---|---|---|
| GAP-060 | `GET /health`                                         | Health endpoint expected to be probed by infra, not the dashboard — no action needed; mark as **N/A**. |
| GAP-061 | `GET /metrics`                                        | Prometheus scrape endpoint — N/A for dashboard. |
| GAP-062 | `GET /api/v1/openapi.json`                            | Could be linked from `/developer` ("Download API spec"). |
| GAP-063 | `GET  /api/graphql` (introspection)                   | Could be linked from `/developer` ("GraphiQL"). |
| GAP-064 | `POST /api/graphql`                                   | GraphQL playground panel on `/developer`. |
| GAP-065 | `POST /api/v1/atm/inquiry`                            | ATM-channel test harness on `/channels` would let ops simulate ATM transactions; otherwise N/A for dashboard. |
| GAP-066 | `POST /api/v1/atm/withdraw`                           | Same. |
| GAP-067 | `POST /api/v1/exceptions`                             | System-internal — exceptions are produced by the system, not by humans through UI. **N/A** for dashboard. |

**Reclassification after triage:** GAP-060, 061, 067 are infra/system-only and not appropriate for the
dashboard. They should be **excluded** from the gap calculation, dropping the denominator to **91**
and lifting effective coverage to **49 / 91 = 54%**. GAP-065/066 belong to a future ops-tools surface
and are acceptable to defer. GAP-062–064 are nice-to-have developer affordances.

---

## Coverage by surface area

```
Customer detail view      [████████░░] 80%   (missing: profile, notification prefs, audit-log view)
Account detail view       [██████░░░░] 60%   (missing: statement, balance/summary, transaction drill-in)
Compliance / KYC          [██████░░░░] 60%   (broken PUT; missing doc-ref upload)
Developer surface         [█████░░░░░] 50%   (read-only — no key issuance, no webhook CRUD)
Products                  [████░░░░░░] 40%   (no activate/deactivate, no detail view)
Webhooks                  [██░░░░░░░░] 20%   (read-only)
Events / audit log        [░░░░░░░░░░]  0%   (resource group entirely absent from dashboard)
Statements / exports      [░░░░░░░░░░]  0%   (entire export channel missing from UI)
```

---

## Cross-cutting findings (not single-endpoint gaps)

These are systemic issues uncovered while building the matrix:

- **No audit-log surface for a user.** Every write the dashboard makes generates a domain event,
  but the customer detail view does not expose them. This breaks the requirement in `AGENTS.md` that
  "all financial operations have audit trail entries visible in the UI".
- **No transaction detail page.** `/transactions` is a list view; rows are not navigable. Reverse
  is exposed but you cannot inspect the entries the reversal generated.
- **No pagination, sort, filter, or export on most list views.** The CRUD-completeness checklist
  in `AGENTS.md` (Phase 5) is failing for `/customers`, `/accounts`, `/transactions`, `/loans`,
  `/payments`, `/products`.
- **Sensitive-field masking not implemented.** Account numbers and party identifiers are shown
  in full; per `AGENTS.md` they should be masked with reveal-on-demand.
- **N+1 / over-fetch pattern repeated.** `/accounts`, `/transactions`, `/payments`, and `/loans`
  all begin by fetching all parties and then loop through party→accounts. The dedicated
  `GET /accounts` endpoint is never used. This is a both a performance and a least-privilege issue.
- **No reactivation path** for either parties or (through soft-close) accounts.
- **Stale-data risk in payments.** Created orders are kept in component state only; refreshing
  `/payments` loses the entire history because `GET /payment-orders` is never called.

---

## Recommendation

Pause here for human review. The 1 STALE call is a **production-breaking bug** and warrants a
hot-fix PR independent of the rest of the audit. The 43 MISSING items should be triaged into
the prioritized remediation plan (Phase 4) once the gap report is signed off.
