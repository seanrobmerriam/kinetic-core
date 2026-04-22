# Dashboard Inventory

**Source:** `apps/cb_dashboard/src/` — Next.js 15 app with Mantine UI, file-based routing under
`src/app/(app)/`. All API calls are routed through the typed wrapper `api(method, path, body)` in
`src/lib/api.ts`, which prepends `http(s)://<host>:8081/api/v1`.

**Discovery method:** Enumerated every `page.tsx` under `src/app/(app)/`, then grep'd for the `api(`
helper to extract `(method, path)` tuples and the component context surrounding each call.

**Total dashboard pages:** 14 (login + 13 app routes). **Total distinct backend endpoints called:** 36.

---

## Pages and routes

| Frontend route | File | Primary resource | Operations exposed |
|---|---|---|---|
| `/login`         | `app/login/page.tsx`                          | Auth        | login |
| `/dashboard`     | `app/(app)/dashboard/page.tsx`                | Overview    | aggregated counts/timeline (read-only) |
| `/customers`     | `app/(app)/customers/page.tsx`                | Parties     | list, create, suspend, close |
| `/customers/:id` | `app/(app)/customers/[partyId]/page.tsx`      | Party       | detail, suspend, close, list accounts |
| `/accounts`      | `app/(app)/accounts/page.tsx`                 | Accounts    | list (per party), create (savings + loan) |
| `/accounts/:id`  | `app/(app)/accounts/[accountId]/page.tsx`     | Account     | detail, freeze/unfreeze/close, holds add/release, txn list |
| `/transactions`  | `app/(app)/transactions/page.tsx`             | Transactions| list per account, reverse |
| `/transfer`      | `app/(app)/transfer/page.tsx`                 | Transactions| transfer form |
| `/deposit`       | `app/(app)/deposit/page.tsx`                  | Transactions| deposit & withdraw forms |
| `/payments`      | `app/(app)/payments/page.tsx`                 | PaymentOrders| list, create, cancel, retry |
| `/products`      | `app/(app)/products/page.tsx`                 | Products    | list savings & loan products, create both |
| `/loans`         | `app/(app)/loans/page.tsx`                    | Loans       | list, originate, view detail+repayments, approve, disburse, record repayment |
| `/ledger`        | `app/(app)/ledger/page.tsx`                   | Ledger      | latest entries, account entries lookup |
| `/channels`      | `app/(app)/channels/page.tsx`                 | Channels    | list limits, edit limit (PUT), activity log |
| `/compliance`    | `app/(app)/compliance/page.tsx`               | KYC + Exceptions| KYC bulk view + update, exceptions list + resolve |
| `/developer`     | `app/(app)/developer/page.tsx`                | Devtools    | list api-keys, list webhooks, deprecations, key usage |
| `/settings`      | `app/(app)/settings/page.tsx`                 | (none)      | static settings page; no API calls |

Header component additionally calls `GET /dev/mock-import` and triggers `POST /dev/mock-import`.

---

## Dashboard API Call Registry

Calls are listed as **`METHOD /path`** with the originating component.

### Auth — `lib/auth.tsx`, `app/login/page.tsx`
- `POST /auth/login`     → login form (`auth.tsx:90`)
- `GET  /auth/me`        → session bootstrap (`auth.tsx:65`)
- `POST /auth/logout`    → user menu logout (`auth.tsx:109`)

### Header — `components/Header.tsx`
- `GET  /dev/mock-import`   → check demo mode flag
- `POST /dev/mock-import`   → import demo dataset

### Dashboard overview — `dashboard/page.tsx`
- `GET /parties`
- `GET /parties/:id/accounts`
- `GET /accounts/:id/transactions`
- `GET /accounts/:id/entries`

### Customers list — `customers/page.tsx`
- `GET  /parties`
- `POST /parties`                           (create form)
- `POST /parties/:id/suspend`
- `POST /parties/:id/close`

### Customer detail — `customers/[partyId]/page.tsx`
- `GET  /parties/:id`
- `GET  /parties/:id/accounts`
- `POST /parties/:id/suspend`
- `POST /parties/:id/close`

### Accounts list — `accounts/page.tsx`
- `GET  /parties`
- `GET  /parties/:id/accounts`
- `POST /accounts`                          (savings open)
- `POST /accounts`                          (loan account open)

### Account detail — `accounts/[accountId]/page.tsx`
- `GET    /parties` + `GET /parties/:id/accounts` + `GET /parties/:id` (locate party)
- `GET    /accounts/:id/transactions`
- `GET    /accounts/:id/holds`
- `POST   /accounts/:id/freeze`
- `POST   /accounts/:id/unfreeze`
- `POST   /accounts/:id/close`
- `POST   /accounts/:id/holds`
- `DELETE /accounts/:id/holds/:hold_id`

### Transactions — `transactions/page.tsx`
- `GET  /parties`
- `GET  /parties/:id/accounts`
- `GET  /accounts/:id/transactions`
- `POST /transactions/:id/reverse`

### Transfer — `transfer/page.tsx`
- `POST /transactions/transfer`

### Deposit/Withdraw — `deposit/page.tsx`
- `POST /transactions/deposit`
- `POST /transactions/withdraw`

### Payments — `payments/page.tsx`
- `GET  /parties`
- `GET  /parties/:id/accounts`
- `POST /payment-orders`
- `POST /payment-orders/:id/cancel`
- `POST /payment-orders/:id/retry`

### Products — `products/page.tsx`
- `GET  /savings-products`
- `GET  /loan-products`
- `POST /savings-products`
- `POST /loan-products`

### Loans — `loans/page.tsx`
- `GET  /parties`
- `GET  /parties/:id/accounts`
- `GET  /loan-products`
- `GET  /loans?party_id=...`
- `GET  /loans/:id`
- `GET  /loans/:id/repayments`
- `POST /loans`
- `POST /loans/:id/approve`
- `POST /loans/:id/disburse`
- `POST /loans/:id/repayments`

### Ledger — `ledger/page.tsx`
- `GET /ledger/entries/latest?limit=20`
- `GET /accounts/:id/entries`

### Channels — `channels/page.tsx`
- `GET /channel-limits`
- `PUT /channel-limits/:channel`
- `GET /channel-activity?...`

### Compliance — `compliance/page.tsx`
- `GET  /parties`
- `GET  /parties/:id/kyc`
- `PUT  /parties/:id/kyc`     ⚠ **STALE — handler does not implement PUT**
- `GET  /exceptions`
- `POST /exceptions/:id/resolve`

### Developer — `developer/page.tsx`
- `GET /api-keys`
- `GET /api-keys/:id/usage`
- `GET /webhooks`
- `GET /deprecations`
