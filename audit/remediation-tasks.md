# Remediation Task Plan

**Generated:** 2026-04-22
**Source:** `audit/gap-report.md`
**Scope:** 1 STALE bug, 1 PARTIAL refactor, 43 MISSING gaps (3 reclassified N/A → 40 actionable).

Tasks are grouped by sprint/wave so each wave is independently shippable. All tasks follow TDD —
tests are listed first under "TDD anchors". Effort uses XS (≤2h) / S (≤½d) / M (≤2d) / L (≤1w) / XL (>1w).

---

## Wave 0 — Hot-fix (ship immediately, separate PR)

### TASK FIX-KYC-PUT — Repair broken KYC save action  *(STALE-001)*

**Priority:** 🚨 CRITICAL · **Effort:** XS

**What to build:** Change the `PUT` to `PATCH` so compliance officers can save KYC updates.

**Where:** `apps/cb_dashboard/src/app/(app)/compliance/page.tsx:272`

**API contract:**
- Method: `PATCH`
- Endpoint: `/api/v1/parties/:party_id/kyc`
- Request: `{ status: "pending" | "approved" | "rejected", notes?: string }`
- Response: `{ ok: true, kyc: {...} }`

**Acceptance criteria**
- [ ] Saving KYC from the compliance page returns 200 and the row updates without page reload.
- [ ] Network tab shows `PATCH`, not `PUT`.
- [ ] Backend `cb_party_kyc_handler` audit log records the change.

**TDD anchors**
- [ ] Unit (Jest + RTL): on submit, the wrapped `api()` mock is called with `("PATCH", "/parties/<id>/kyc", body)`.
- [ ] Unit: error path renders `<Alert>` when API returns `{ error }`.
- [ ] Manual smoke (until Playwright is wired): change a KYC status in dev and confirm reload shows the change.

---

## Wave 1 — Critical visibility & lifecycle gaps

### TASK GAP-001 — Reactivate suspended customer

**Priority:** 🚨 CRITICAL · **Effort:** S

**What to build:** "Reactivate" action button on suspended/closed customer detail header.

**Where:** `apps/cb_dashboard/src/app/(app)/customers/[partyId]/page.tsx` — actions menu next to status badge.

**API contract:** `POST /api/v1/parties/:party_id/reactivate` → `{ ok, party }`

**Acceptance criteria**
- [ ] Button visible only when `party.status ∈ {suspended, closed}`.
- [ ] Confirmation dialog explains audit-trail implications.
- [ ] On success, status badge updates and toast confirms.
- [ ] Error from backend (e.g. KYC not approved) shown inline.

**TDD anchors**
- [ ] Unit: button is hidden when `status === 'active'`.
- [ ] Unit: confirm dialog must be accepted before `api()` is called.
- [ ] Unit: API mock is called with `("POST", "/parties/<id>/reactivate")` and refresh fires.

---

### TASK GAP-002 — Manual ledger adjustment form

**Priority:** 🚨 CRITICAL · **Effort:** M

**What to build:** Operations-only "Manual Adjustment" form (debit / credit pair) on `/transactions`.

**Where:** New page `apps/cb_dashboard/src/app/(app)/transactions/adjustment/page.tsx` and a button on `/transactions`.

**API contract:** `POST /api/v1/transactions/adjustment`
- Request: `{ debit_account_id, credit_account_id, amount_minor, currency, reason, reference }`
- Response: `{ ok, transaction_id, entries: [...] }`

**Acceptance criteria**
- [ ] Money entered in major units, persisted as minor units (per `AGENTS.md`).
- [ ] Both accounts validated to exist and be in the same currency before submit.
- [ ] Mandatory `reason` field (≥10 chars) — recorded in audit trail.
- [ ] Success view shows resulting transaction id with link to detail page (GAP-003).
- [ ] Role-gated: only `ops_admin` role can see the entry point (until handler enforces, gate in UI).

**TDD anchors**
- [ ] Unit: enters "12.50" in amount → submits `1250` minor.
- [ ] Unit: cross-currency selection blocks submit and shows inline error.
- [ ] Unit: missing reason fails validation pre-submit; `api()` not called.
- [ ] Unit: API mock asserts payload shape.

---

### TASK GAP-003 + GAP-004 — Transaction detail page with double-entry view

**Priority:** 🚨 CRITICAL · **Effort:** M

**What to build:** Detail page rendering transaction header + ledger entries table.

**Where:** New `apps/cb_dashboard/src/app/(app)/transactions/[txnId]/page.tsx`. Make rows in
`/transactions` and account-detail transaction tables clickable.

**API contracts**
- `GET /api/v1/transactions/:txn_id` → header
- `GET /api/v1/transactions/:txn_id/entries` → array of `{ entry_id, account_id, dr_cr, amount_minor, currency, created_at }`

**Acceptance criteria**
- [ ] Header shows id, type, status, amount, currency, created_at, reversal pointer if any.
- [ ] Entries table sums to zero per currency (display warning if not).
- [ ] "Reverse" button (if not already reversed) calls existing `POST /transactions/:id/reverse`.
- [ ] Empty/error/loading states handled.

**TDD anchors**
- [ ] Unit: renders both API responses (mocked) without crashing on missing reversal.
- [ ] Unit: balanced-entries assertion (sum == 0) when fixture is balanced.
- [ ] Unit: warning banner appears when fixture is unbalanced.
- [ ] Unit: clicking "Reverse" opens confirm dialog; only then is `api()` called.

---

### TASK GAP-005 — Account statement download

**Priority:** 🚨 CRITICAL · **Effort:** S

**What to build:** "Download statement" button on account detail page with date-range picker.

**Where:** `apps/cb_dashboard/src/app/(app)/accounts/[accountId]/page.tsx` header actions.

**API contract:** `GET /api/v1/accounts/:account_id/statement?from=YYYY-MM-DD&to=YYYY-MM-DD&format=csv|pdf`

**Acceptance criteria**
- [ ] Date range defaults to current month.
- [ ] Format selector (CSV, PDF) defaults to PDF.
- [ ] Triggers a browser download; failure surfaces an alert and never silently drops.
- [ ] Audit event logged backend-side (out of scope for this task, but verify in dev).

**TDD anchors**
- [ ] Unit: invalid range (`from > to`) disables download button.
- [ ] Unit: clicking triggers `fetch` with the constructed query string.
- [ ] Unit: non-2xx response shows error toast.

---

### TASK GAP-006 — Bulk export center

**Priority:** 🚨 CRITICAL · **Effort:** M

**What to build:** New `/exports` page with resource selector + filter controls.

**Where:** New `apps/cb_dashboard/src/app/(app)/exports/page.tsx`. Add nav link (Compliance section).

**API contract:** `GET /api/v1/export/:resource?format=csv|jsonl&from=...&to=...`
Resources: `parties`, `accounts`, `transactions`, `loans`, `payment-orders`, `events`, `exceptions`.

**Acceptance criteria**
- [ ] Resource dropdown lists exactly the supported resources.
- [ ] Each export run shows a row in a "Recent exports" table (in-memory is acceptable; persistence is a follow-up).
- [ ] Errors visible inline; download blob saved with filename `<resource>-<from>-<to>.<ext>`.

**TDD anchors**
- [ ] Unit: changing the resource dropdown updates the URL preview.
- [ ] Unit: download triggers correct `GET` with query.
- [ ] Unit: empty export (zero rows) still surfaces a non-error empty-state toast.

---

### TASK GAP-007 — Attach KYC document reference

**Priority:** 🚨 CRITICAL · **Effort:** S

**What to build:** "Add document reference" form in KYC drawer of `/compliance` and on customer detail.

**Where:** Extend the KYC drawer in `apps/cb_dashboard/src/app/(app)/compliance/page.tsx`.

**API contract:** `POST /api/v1/parties/:party_id/kyc` body `{ doc_type, doc_ref, expires_at? }`

**Acceptance criteria**
- [ ] `doc_type` enum dropdown (passport, national_id, utility_bill, ...).
- [ ] `doc_ref` is a free-text identifier — required, ≥3 chars.
- [ ] After save, document list re-renders with the new row.
- [ ] Validation error from backend rendered without losing form state.

**TDD anchors**
- [ ] Unit: form fails validation when `doc_ref` is empty.
- [ ] Unit: payload posts as `("POST", "/parties/<id>/kyc", { doc_type, doc_ref, expires_at })`.
- [ ] Unit: backend error preserves user input.

---

## Wave 2 — Resource lifecycle (HIGH)

### TASK GAP-010..012 — Savings product detail / activate / deactivate

**Priority:** ⚠️ HIGH · **Effort:** S

**Where:** `apps/cb_dashboard/src/app/(app)/products/page.tsx` — extend rows with detail link;
new `apps/cb_dashboard/src/app/(app)/products/savings/[productId]/page.tsx`.

**API contracts**
- `GET    /api/v1/savings-products/:id` → product detail
- `POST   /api/v1/savings-products/:id/activate`
- `POST   /api/v1/savings-products/:id/deactivate`

**Acceptance criteria**
- [ ] Detail page shows interest rules, min/max balance, fees, lifecycle state.
- [ ] Activate/Deactivate buttons mutually exclusive based on `status`.
- [ ] State change confirmed via dialog and reflected in list view on return.

**TDD anchors**
- [ ] Unit: only the appropriate button renders for each `status` value.
- [ ] Unit: API mock receives the correct verb+path.

---

### TASK GAP-013..015 — Loan product detail / activate / deactivate

**Priority:** ⚠️ HIGH · **Effort:** S

Same structure as GAP-010..012 against `/api/v1/loan-products/...`. New page
`apps/cb_dashboard/src/app/(app)/products/loans/[productId]/page.tsx`.

**Acceptance criteria & TDD anchors:** mirror GAP-010..012.

---

### TASK GAP-016..019 — Webhook CRUD + delivery inspector

**Priority:** ⚠️ HIGH · **Effort:** M

**Where:** Extend `apps/cb_dashboard/src/app/(app)/developer/page.tsx` and add a webhook detail
drawer.

**API contracts**
- `POST   /api/v1/webhooks` — `{ url, events: [...], secret? }`
- `PATCH  /api/v1/webhooks/:id` — partial update
- `DELETE /api/v1/webhooks/:id`
- `GET    /api/v1/webhooks/:id/deliveries` — list of `{ delivery_id, status, attempted_at, response_code, body }`

**Acceptance criteria**
- [ ] "New webhook" form validates URL is https in production env.
- [ ] Edit drawer pre-populates current subscription.
- [ ] Delete requires typing the URL to confirm.
- [ ] Deliveries tab lists last 50 attempts with status colour, expandable body.

**TDD anchors**
- [ ] Unit: HTTP URL rejected when `NODE_ENV==='production'`.
- [ ] Unit: confirmation typed-text gate works.
- [ ] Unit: delete mock called with correct id.
- [ ] Unit: deliveries renders empty state when list is empty.

---

### TASK GAP-020..022 — API key issuance / detail / revoke

**Priority:** ⚠️ HIGH · **Effort:** S

**Where:** `apps/cb_dashboard/src/app/(app)/developer/page.tsx` (new "API keys" section + drawer).

**API contracts**
- `POST   /api/v1/api-keys` → `{ id, key (one-time), scopes }` — display once with copy-to-clipboard
- `GET    /api/v1/api-keys/:id` → metadata
- `DELETE /api/v1/api-keys/:id` → revoke

**Acceptance criteria**
- [ ] Generated key shown exactly once with explicit warning.
- [ ] Scopes selectable from a known list.
- [ ] Revoke action requires typed confirmation.
- [ ] List view marks revoked keys as such (no longer offers revoke).

**TDD anchors**
- [ ] Unit: secret reveal modal appears only on create; subsequent visits never expose it.
- [ ] Unit: revoke calls `("DELETE", "/api-keys/<id>")` after typed confirmation.

---

## Wave 3 — Visibility & sub-resource exposure (HIGH)

### TASK GAP-030 — Customer omnichannel profile panel

**Priority:** ⚠️ HIGH · **Effort:** S

**Where:** `customers/[partyId]/page.tsx` — add "Profile" tab.

**API contract:** `GET /api/v1/parties/:id/profile` → unified channel-presence view.

**TDD anchors:** mocked render; empty-state when no channels enrolled.

---

### TASK GAP-031..032 — Notification preferences view + edit

**Priority:** ⚠️ HIGH · **Effort:** S

**Where:** `customers/[partyId]/page.tsx` — "Notifications" tab with toggle grid (channel × event type).

**API contracts**
- `GET /api/v1/parties/:id/notification-preferences`
- `PUT /api/v1/parties/:id/notification-preferences` — full replacement payload.

**TDD anchors**
- [ ] Unit: toggling a switch and clicking Save posts the merged preferences object.
- [ ] Unit: dirty-state warning if user navigates away before saving.

---

### TASK GAP-033..034 — Account balance + summary panels

**Priority:** ⚠️ HIGH · **Effort:** XS each

**Where:** `accounts/[accountId]/page.tsx` — replace client-side derived numbers with API values.

**API contracts**
- `GET /api/v1/accounts/:id/balance` → `{ available_minor, current_minor, currency }`
- `GET /api/v1/accounts/:id/summary` → counts (pending txns, holds, last activity)

**TDD anchors**
- [ ] Unit: balance card uses API response, not derived value.
- [ ] Unit: summary loading skeleton renders before fetch resolves.

---

### TASK GAP-035 — Use `/stats` for overview

**Priority:** ⚠️ HIGH · **Effort:** XS

**Where:** `apps/cb_dashboard/src/app/(app)/dashboard/page.tsx`.

**API contract:** `GET /api/v1/stats` → aggregated tile values.

**Acceptance criteria**
- [ ] All four tiles read from a single `/stats` call.
- [ ] Per-party / per-account derivations are removed.
- [ ] Initial paint completes in one round-trip.

**TDD anchors**
- [ ] Unit: only one `api()` call is made on mount.
- [ ] Unit: tiles render placeholder during loading.

---

### TASK GAP-036 — Use `/accounts` list endpoint and refactor account-detail lookup *(merges PARTIAL-001)*

**Priority:** ⚠️ HIGH · **Effort:** S

**Where:** `apps/cb_dashboard/src/app/(app)/accounts/page.tsx` and `accounts/[accountId]/page.tsx`.

**API contracts**
- `GET /api/v1/accounts` (with pagination) for list view
- `GET /api/v1/accounts/:id` for detail
- `GET /api/v1/parties/:id` to fetch the owning party only after the account is loaded

**Acceptance criteria**
- [ ] List page no longer scans `/parties`.
- [ ] Detail page loads with two parallel calls (`account` + `party`) and not N+1.
- [ ] No customer's accounts beyond the requested account are fetched.

**TDD anchors**
- [ ] Unit: spy on `api()` confirms only `("GET", "/accounts")` on list mount.
- [ ] Unit: spy confirms only `("GET", "/accounts/<id>")` then `("GET", "/parties/<owner>")` on detail mount.

---

### TASK GAP-037..038 — Payment orders list + detail

**Priority:** ⚠️ HIGH · **Effort:** S

**Where:** `apps/cb_dashboard/src/app/(app)/payments/page.tsx` (table) + new
`apps/cb_dashboard/src/app/(app)/payments/[orderId]/page.tsx`.

**API contracts**
- `GET /api/v1/payment-orders`
- `GET /api/v1/payment-orders/:id`

**Acceptance criteria**
- [ ] List survives page reload (no longer relies on component state).
- [ ] Row click opens detail view with timeline of state transitions.

**TDD anchors**
- [ ] Unit: list renders fixture rows after API resolves.
- [ ] Unit: detail page renders state-transition timeline.

---

### TASK GAP-039 — Exception detail view

**Priority:** ⚠️ HIGH · **Effort:** XS

**Where:** Drawer or new page from `apps/cb_dashboard/src/app/(app)/compliance/page.tsx` exceptions table.

**API contract:** `GET /api/v1/exceptions/:id`.

**TDD anchors:** mocked-render test; resolve action retained from existing flow.

---

### TASK GAP-040 — Channel-limit drill-in

**Priority:** 🟡 MEDIUM · **Effort:** XS

**Where:** `apps/cb_dashboard/src/app/(app)/channels/page.tsx` — make rows clickable.

**API contract:** `GET /api/v1/channel-limits/:channel`.

---

## Wave 4 — Audit / events (MEDIUM)

### TASK GAP-050..053 — Events / audit log surface

**Priority:** 🟡 MEDIUM · **Effort:** M

**What to build:** New `/audit` (or `/events`) page with filters (resource, type, date range), a
detail drawer, and an admin-only "Replay" action.

**Where:** New `apps/cb_dashboard/src/app/(app)/audit/page.tsx`. Also embed a per-customer
"Audit Trail" tab into `customers/[partyId]/page.tsx` calling the same endpoint with `party_id` filter.

**API contracts**
- `GET  /api/v1/events?resource=&type=&from=&to=&cursor=`
- `GET  /api/v1/events/:event_id`
- `POST /api/v1/events` — admin event injection (gated)
- `POST /api/v1/events/:event_id/replay`

**Acceptance criteria**
- [ ] Filter panel persists in URL query string.
- [ ] Detail drawer pretty-prints the event JSON payload.
- [ ] Replay action requires confirmation and shows the new event id afterward.
- [ ] Per-customer tab renders subset filtered by `party_id`.

**TDD anchors**
- [ ] Unit: changing a filter pushes the new URL and re-issues the API call.
- [ ] Unit: replay button calls `POST /events/<id>/replay` only after confirmation.
- [ ] Unit: per-customer embed only requests events for that party.

---

## Wave 5 — Developer affordances (LOW)

### TASK GAP-062..064 — Developer tooling links

**Priority:** 🟢 LOW · **Effort:** XS

**Where:** `apps/cb_dashboard/src/app/(app)/developer/page.tsx`.

**Items**
- Link to `GET /api/v1/openapi.json` ("Download OpenAPI spec")
- Embedded GraphiQL pointing to `/api/graphql`
- Inline `curl` snippets that match the OpenAPI examples.

---

## Wave 6 — Deferred / Out of scope

| Item | Reason |
|---|---|
| GAP-060 `GET /health`, GAP-061 `GET /metrics`, GAP-067 `POST /exceptions` | Infra/system-only — not appropriate for dashboard. |
| GAP-065/066 ATM endpoints | Belong to a future ops "channel test harness" surface. |

---

## Cross-cutting tasks (uncovered in gap report)

These are **not single endpoints** but are required by `AGENTS.md` Phase 5 checklist.

### TASK XCUT-A11Y — WCAG 2.2 AA conformance pass

**Priority:** ⚠️ HIGH · **Effort:** M

- [ ] All interactive elements keyboard reachable, with visible focus state.
- [ ] All form fields have label associations.
- [ ] All confirmation dialogs trap focus.
- [ ] Lighthouse a11y score ≥ 95 on each `(app)` route.

### TASK XCUT-MASK — Sensitive-field masking

**Priority:** ⚠️ HIGH · **Effort:** S

- [ ] Account numbers and party identifiers masked by default with a per-row reveal toggle.
- [ ] Reveal events written to audit trail server-side.

### TASK XCUT-LIST — List-view CRUD completeness

**Priority:** 🟡 MEDIUM · **Effort:** M (per page)

For every list view, add:
- [ ] Search / filter inputs
- [ ] Server-side pagination (`limit`, `cursor`)
- [ ] Sortable columns where the API supports `order_by`
- [ ] CSV export (uses GAP-006 export endpoint)

### TASK XCUT-EMPTY — Loading / empty / error states

**Priority:** 🟡 MEDIUM · **Effort:** S

- [ ] Each API-backed component renders skeleton on load, friendly empty-state when zero rows,
      and an actionable error UI on failure.

---

## Suggested execution order

1. **Wave 0** as a one-line hot-fix PR (FIX-KYC-PUT).
2. **Wave 1** in priority order (GAP-005, GAP-007, GAP-001, GAP-003+004, GAP-002, GAP-006).
3. **Wave 2** in any order (independent of each other).
4. **Wave 3** alongside Wave 2.
5. **Wave 4** once event volume justifies the page.
6. **Wave 5** before any external-developer launch.
7. **Cross-cutting tasks** interleaved — XCUT-MASK before any production demo.

Per `AGENTS.md`: one logical change per commit, verification gates
(`rebar3 compile/ct/dialyzer/proper`, `npm ci/lint/build` from `apps/cb_dashboard`) green
before merge, and `Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>` trailer
on every commit.
