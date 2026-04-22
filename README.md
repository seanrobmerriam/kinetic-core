# IronLedger

A Docker-first core banking platform built on Erlang/OTP with a Next.js dashboard.

## Current Status

- Backend: Erlang/OTP release served by Cowboy on port 8081 (inside container)
- Dashboard: Next.js app served on port 80 (inside container)
- Local compose ports:
  - Dashboard: http://localhost:8080
  - API: http://localhost:18081/api/v1

## What Is In This Repository

- Core banking domains: parties, accounts, ledger, payments, savings products, loans, and interest
- Integration and control-plane domains: auth, approvals, events, reporting
- API layer: Cowboy router and REST handlers under `apps/cb_integration`
- Web dashboard: Next.js (TypeScript) under `apps/cb_dashboard`

## Repository Layout

```text
ironledger/
├── apps/
│   ├── cb_accounts/
│   ├── cb_approvals/
│   ├── cb_auth/
│   ├── cb_dashboard/
│   ├── cb_events/
│   ├── cb_integration/
│   ├── cb_interest/
│   ├── cb_ledger/
│   ├── cb_loans/
│   ├── cb_party/
│   ├── cb_payments/
│   ├── cb_reporting/
│   └── cb_savings_products/
├── config/
├── docs/
├── DEVELOPMENT.md
├── REQUIREMENTS.md
├── docker-compose.yml
├── Dockerfile.api
└── rebar.config
```

## Planning Documents

- Product requirements: `REQUIREMENTS.md`
- Phased execution plan: `DEVELOPMENT.md`

## Quick Start (Docker)

### Prerequisites

- Docker
- Docker Compose

### Run

```bash
docker compose up --build
```

Then open:

- Dashboard: http://localhost:8080
- API health: http://localhost:18081/health
- API base: http://localhost:18081/api/v1

### Stop

```bash
docker compose down
```

## Local Development

### Backend (Erlang)

Prerequisites:

- Erlang/OTP 25+
- rebar3

Commands:

```bash
# Compile all OTP apps
rebar3 compile

# Start interactive shell
rebar3 shell

# Build release
rebar3 release

# Run release in foreground
_build/default/rel/ironledger/bin/ironledger foreground
```

### Dashboard (Next.js)

Prerequisites:

- Node.js 20+
- npm

Commands:

```bash
cd apps/cb_dashboard
npm ci
npm run dev
```

Dashboard dev URL:

- http://localhost:3000

## Authentication

The API is protected by auth middleware.

Public endpoints:

- `GET /health`
- `POST /api/v1/auth/login`

Default bootstrap credentials (from `config/sys.config`):

- Email: `admin@example.com`
- Password: `secret-pass`

## API Surface (Summary)

Defined in `apps/cb_integration/src/cb_router.erl`.

### Auth

- `POST /api/v1/auth/login`
- `POST /api/v1/auth/logout`
- `GET /api/v1/auth/me`

### Parties

- `POST /api/v1/parties`
- `GET /api/v1/parties`
- `GET /api/v1/parties/:party_id`
- `POST /api/v1/parties/:party_id/suspend`
- `POST /api/v1/parties/:party_id/reactivate`
- `POST /api/v1/parties/:party_id/close`
- `POST /api/v1/parties/:party_id/kyc`

### Accounts

- `POST /api/v1/accounts`
- `GET /api/v1/accounts`
- `GET /api/v1/accounts/:account_id`
- `GET /api/v1/accounts/:account_id/balance`
- `GET /api/v1/accounts/:account_id/transactions`
- `GET/POST/DELETE /api/v1/accounts/:account_id/holds`
- `POST /api/v1/accounts/:account_id/freeze`
- `POST /api/v1/accounts/:account_id/unfreeze`
- `POST /api/v1/accounts/:account_id/close`
- `GET /api/v1/parties/:party_id/accounts`

### Transactions and Ledger

- `POST /api/v1/transactions/transfer`
- `POST /api/v1/transactions/deposit`
- `POST /api/v1/transactions/withdraw`
- `POST /api/v1/transactions/adjustment`
- `GET /api/v1/transactions/:txn_id`
- `POST /api/v1/transactions/:txn_id/reverse`
- `GET /api/v1/transactions/:txn_id/entries`
- `GET /api/v1/accounts/:account_id/entries`

### Product and Loan Flows

- Savings products: `/api/v1/savings-products` and activate or deactivate actions
- Loan products: `/api/v1/loan-products` and activate or deactivate actions
- Loans: `/api/v1/loans`, approve, disburse, and repayments

### Events, Webhooks, and Reporting

- Events: `/api/v1/events` (+ replay)
- Webhooks: `/api/v1/webhooks`
- Statements: `/api/v1/accounts/:account_id/statement`
- Exports: `/api/v1/export/:resource`

## Testing

Run from repository root unless noted.

```bash
# Erlang tests and analysis
rebar3 ct
rebar3 dialyzer
rebar3 proper

# Frontend lint
cd apps/cb_dashboard && npm run lint
```

If browser e2e is needed:

```bash
npm install
npx playwright install chromium
npm run test:e2e
```

## Notes

- Mnesia is configured for prototype-style runtime at `/tmp/ironledger_mnesia`.
- A named Docker volume (`ironledger_mnesia`) is mounted in compose.
- Development endpoints include `POST /api/v1/dev/mock-import` when dev tools are enabled.

## Contributing

Open an issue or pull request with a clear problem statement, test evidence, and rollback notes for operationally sensitive changes.
