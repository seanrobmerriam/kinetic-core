# IronLedger

<img width="1376" height="525" alt="image" src="https://github.com/user-attachments/assets/d53bb17f-88e0-4004-b625-ead3ef8d3d2e" />


A core banking application built with Erlang/OTP 25.3, featuring double-entry bookkeeping, REST API, and a Next.js dashboard.

## Overview

IronLedger is a Dockerized core banking system that provides:

- **Party Management**: Customer onboarding with KYC data
- **Account Management**: Multi-currency accounts with lifecycle states
- **Double-Entry Ledger**: Immutable financial transaction recording
- **Payment Processing**: Transfers, deposits, and withdrawals with idempotency
- **REST API**: Cowboy-based HTTP interface
- **Next.js Dashboard**: React/TypeScript browser UI with locally packaged fonts and icons


## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    IronLedger System                        │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐ │
│  │  cb_party   │  │ cb_accounts │  │    cb_payments      │ │
│  │  (Parties)  │  │  (Accounts) │  │  (Transactions)     │ │
│  └──────┬──────┘  └──────┬──────┘  └──────────┬──────────┘ │
│         │                │                    │            │
│         └────────────────┼────────────────────┘            │
│                          │                                  │
│                   ┌──────┴──────┐                          │
│                   │  cb_ledger  │                          │
│                   │  (Entries)  │                          │
│                   └──────┬──────┘                          │
│                          │                                  │
│  ┌───────────────────────┼───────────────────────┐         │
│  │              cb_integration                   │         │
│  │  ┌─────────┐  ┌─────────┐  ┌───────────────┐ │         │
│  │  │ Cowboy  │  │ Router  │  │   Handlers    │ │         │
│  │  │ (HTTP)  │  │(Routing)│  │ (REST API)    │ │         │
│  │  └─────────┘  └─────────┘  └───────────────┘ │         │
│  └───────────────────────┬───────────────────────┘         │
│                          │                                  │
│  ┌───────────────────────┴───────────────────────┐         │
│  │              cb_dashboard                     │         │
│  │           (Next.js + React UI)                │         │
│  └───────────────────────────────────────────────┘         │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │     Mnesia      │
                    │  (In-Memory DB) │
                    └─────────────────┘
```

## Project Structure

```
ironledger/
├── apps/
│   ├── cb_accounts/        # Account lifecycle management (OTP active app)
│   ├── cb_dashboard/       # Next.js browser dashboard
│   ├── cb_integration/     # HTTP API (Cowboy, routing, handlers) - OTP active app
│   ├── cb_ledger/          # Double-entry ledger engine (OTP library app)
│   ├── cb_party/           # Party (customer) management (OTP library app)
│   └── cb_payments/        # Transfer orchestration & idempotency (OTP active app)
├── config/
│   ├── sys.config          # Application configuration
│   └── vm.args             # VM arguments (node name, cookie, heart)
├── docs/
│   ├── api-contract.yaml   # OpenAPI 3.1 specification
│   ├── data-schema.md      # Mnesia table schemas
│   ├── domain-model.md     # Domain entities and types
│   ├── error-catalogue.md  # Error atoms and meanings
│   ├── testing-strategy.md # Testing approach
│   └── adrs/               # Architecture Decision Records
├── rebar.config            # Build configuration with relx release
└── README.md               # This file
```

## Documentation

Comprehensive module documentation is available in two formats:

### Markdown Documentation

| Module | Description | Location |
|--------|-------------|----------|
| [Architecture](./docs/architecture.md) | System architecture overview | `docs/architecture.md` |
| [cb_ledger](./apps/cb_ledger/README.md) | Double-entry bookkeeping | `apps/cb_ledger/README.md` |
| [cb_accounts](./apps/cb_accounts/README.md) | Account lifecycle | `apps/cb_accounts/README.md` |
| [cb_payments](./apps/cb_payments/README.md) | Payment processing | `apps/cb_payments/README.md` |
| [cb_party](./apps/cb_party/README.md) | Customer management | `apps/cb_party/README.md` |
| [cb_savings_products](./apps/cb_savings_products/README.md) | Savings products | `apps/cb_savings_products/README.md` |
| [cb_loans](./apps/cb_loans/README.md) | Loan management | `apps/cb_loans/README.md` |
| [cb_interest](./apps/cb_interest/README.md) | Interest calculations | `apps/cb_interest/README.md` |
| [cb_integration](./apps/cb_integration/README.md) | HTTP API layer | `apps/cb_integration/README.md` |

### HTML Documentation

A browsable HTML documentation website is available in `docs/website/`. Open `docs/website/index.html` in a browser for an interactive documentation experience.
The current release-candidate validation evidence is documented in `docs/release-checklist-1-0.md`.

### OTP Application Structure

IronLedger follows OTP application standards:

| Application | Type | Description |
|-------------|------|-------------|
| `cb_integration` | **permanent** | Core HTTP API - node restarts if it fails |
| `cb_accounts` | temporary | Account management supervision tree |
| `cb_payments` | temporary | Payment processing supervision tree |
| `cb_ledger` | library | Pure functions for ledger operations |
| `cb_party` | library | Pure functions for party operations |
| `sasl` | permanent | OTP System Architecture Support |

All active applications implement the `application` behaviour with:
- `start/2` - Starts top-level supervisor
- `stop/1` - Cleanup on shutdown
- `prep_stop/1` - Drain work before shutdown (cb_integration)
- `config_change/3` - Runtime configuration change handling

## Quick Start

### Prerequisites

- Erlang/OTP 25.3 or later
- rebar3 (Erlang build tool)
- Node.js 20+ and npm (for the dashboard build and local browser E2E validation)
- Docker and Docker Compose (for packaged local deployment)

### Build

```bash
# Compile all Erlang applications
rebar3 compile

# Build the Next.js dashboard
cd apps/cb_dashboard
npm install
npm run build
```

### Run with Docker Compose

```bash
docker compose up --build

# Dashboard: http://localhost:8080
# API:       http://localhost:18081/api/v1
```

The compose setup starts:
- `api` on port `18081`
- `dashboard` on port `8080`
- a named Docker volume for Mnesia data at `/tmp/ironledger_mnesia`

The dashboard image serves all required static assets locally, including:
- `Google Sans Flex`
- `Material Symbols Outlined`

### Run Tests

All rebar3 test commands should be run from the ironledger root directory


```bash
# Run all Common Test suites
rebar3 ct

# Run Dialyzer static analysis
rebar3 dialyzer

# Run PropEr property-based tests
rebar3 proper

# Full verification (must pass before commits)
rebar3 dialyzer && rebar3 ct && rebar3 proper

# Browser E2E verification for the packaged dashboard
npm install
npx playwright install chromium
npm run test:e2e
```

### Start the Application

```bash
# Start interactive shell (development)
rebar3 shell

# The HTTP server will start on port 8081 inside the container/runtime
# Docker Compose publishes it on host port 18081
# API base URL: http://localhost:18081/api/v1
```

### Build and Run a Release

```bash
# Build a production release
rebar3 release

# Run the release
_build/default/rel/ironledger/bin/ironledger foreground

# Or start in daemon mode
_build/default/rel/ironledger/bin/ironledger start
```

### Release Evidence

The current 1.0 release-candidate checklist and command evidence live in
`docs/release-checklist-1-0.md`.

### Configuration

Application configuration is managed through:

- `config/sys.config` - Application environment variables
- `config/vm.args` - VM arguments (node name, cookie, heart, process limits)

Key configuration values:
- `cb_integration.http_port` - HTTP server port (default: 8081)
- `cb_integration.http_acceptors` - Number of HTTP acceptors (default: 10)
- `mnesia.dir` - Mnesia data directory (default: /tmp/ironledger_mnesia)

### Serve the Dashboard

```bash
cd apps/cb_dashboard
npm run dev

# Dashboard available at http://localhost:3000 (proxies API at NEXT_PUBLIC_API_BASE)
```

## API Endpoints

### Parties
| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/v1/parties` | Create a new party |
| GET | `/api/v1/parties/:id` | Get party by ID |
| GET | `/api/v1/parties` | List parties (paginated) |
| POST | `/api/v1/parties/:id/suspend` | Suspend a party |
| POST | `/api/v1/parties/:id/close` | Close a party |

### Accounts
| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/v1/accounts` | Create a new account |
| GET | `/api/v1/accounts/:id` | Get account by ID |
| GET | `/api/v1/accounts` | List accounts (paginated) |
| POST | `/api/v1/accounts/:id/freeze` | Freeze an account |
| POST | `/api/v1/accounts/:id/unfreeze` | Unfreeze an account |
| POST | `/api/v1/accounts/:id/close` | Close an account |
| GET | `/api/v1/accounts/:id/balance` | Get account balance |

### Transactions
| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/v1/transactions/transfer` | Execute a transfer |
| POST | `/api/v1/transactions/deposit` | Make a deposit |
| POST | `/api/v1/transactions/withdraw` | Make a withdrawal |
| GET | `/api/v1/transactions/:id` | Get transaction by ID |
| GET | `/api/v1/transactions` | List transactions (paginated) |
| POST | `/api/v1/transactions/:id/reverse` | Reverse a transaction |

### Ledger
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/v1/ledger/entries/transaction/:id` | Get entries for transaction |
| GET | `/api/v1/ledger/entries/account/:id` | Get entries for account |

## OTP Compliance

IronLedger adheres to Erlang/OTP application standards:

- **Application Resource Files**: All `.app.src` files properly declare `mod`, `registered`, `applications`, and use `{modules, []}` for rebar3 auto-fill
- **Start Types**: Explicit start types in release configuration (`permanent` for core, `temporary` for supporting apps)
- **Callback Modules**: All active applications implement `start/2`, `stop/1`, `prep_stop/1`, and `config_change/3`
- **VM Configuration**: `vm.args` configures node name, cookie, kernel polling, and heartbeat monitoring
- **Supervision Trees**: Each active application has a top-level supervisor with proper child specs

## Key Design Principles

### Monetary Arithmetic
- All amounts are **non-negative integers in minor units** (cents, pence, etc.)
- `100` = $1.00 USD, `1` = $0.01 USD
- **Floats are strictly forbidden** in any monetary path
- Integer overflow guard: amounts exceeding $100 billion return `{error, amount_overflow}`

### Currency
- ISO 4217 three-letter uppercase atoms: `'USD'`, `'EUR'`, `'GBP'`, `'JPY'`, `'CHF'`
- Cross-currency transfers are rejected with `{error, currency_mismatch}`

### Error Handling
- All functions return `{ok, Value} | {error, Reason}`
- Error atoms are defined in `docs/error-catalogue.md`
- No bare `catch` expressions; specific error classes only

### Database Access
- All financial table operations use `mnesia:transaction/1` or `mnesia:sync_transaction/1`
- No `mnesia:dirty_*` calls on financial tables
- Tables use RAM copies for the prototype

### Entity IDs
- All IDs are UUIDs represented as binaries
- Generated via the `uuid` library
- No sequential integers used as entity IDs

## Testing

The project uses multiple testing approaches:

- **Common Test**: Integration and acceptance tests
- **PropEr**: Property-based testing for arithmetic functions
- **Dialyzer**: Static type analysis

Test suites:
- `cb_party_SUITE`: 9 tests (party CRUD, lifecycle)
- `cb_accounts_SUITE`: 13 tests (account management, balance)
- `cb_ledger_SUITE`: 6 tests (double-entry posting)
- `cb_payments_SUITE`: 11 tests (transfers, idempotency, reversals)

## Documentation

- [API Contract](docs/api-contract.yaml) - OpenAPI 3.1 specification
- [Domain Model](docs/domain-model.md) - Entity relationships and types
- [Data Schema](docs/data-schema.md) - Mnesia table definitions
- [Error Catalogue](docs/error-catalogue.md) - Error atoms and descriptions
- [Testing Strategy](docs/testing-strategy.md) - Testing approach and guidelines
- [Glossary](docs/glossary.md) - Domain terminology

## License

Copyright © 2026 IronLedger Project

## Contributing

Please read [AGENTS.md](AGENTS.md) for the authoritative development guide and coding standards.

---

**Note**: This is a prototype system using in-memory Mnesia storage. Not intended for production use without additional hardening.
