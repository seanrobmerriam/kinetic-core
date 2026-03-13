# IronLedger

A core banking application built with Erlang/OTP 25.3, featuring double-entry bookkeeping, REST API, and a WebAssembly dashboard.

## Overview

IronLedger is a prototype core banking system that demonstrates:

- **Party Management**: Customer onboarding with KYC data
- **Account Management**: Multi-currency accounts with lifecycle states
- **Double-Entry Ledger**: Immutable financial transaction recording
- **Payment Processing**: Transfers, deposits, and withdrawals with idempotency
- **REST API**: Cowboy-based HTTP interface
- **WebAssembly Dashboard**: Go-compiled browser UI

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
│  │         (Go → WebAssembly UI)                 │         │
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
│   ├── cb_accounts/        # Account lifecycle management
│   ├── cb_dashboard/       # Go/Wasm browser dashboard
│   ├── cb_integration/     # HTTP API (Cowboy, routing, handlers)
│   ├── cb_ledger/          # Double-entry ledger engine
│   ├── cb_party/           # Party (customer) management
│   └── cb_payments/        # Transfer orchestration & idempotency
├── config/
│   ├── sys.config          # Application configuration
│   └── vm.args             # VM arguments
├── docs/
│   ├── api-contract.yaml   # OpenAPI 3.1 specification
│   ├── data-schema.md      # Mnesia table schemas
│   ├── domain-model.md     # Domain entities and types
│   ├── error-catalogue.md  # Error atoms and meanings
│   ├── testing-strategy.md # Testing approach
│   └── adrs/               # Architecture Decision Records
├── rebar.config            # Build configuration
└── README.md               # This file
```

## Quick Start

### Prerequisites

- Erlang/OTP 25.3 or later
- rebar3 (Erlang build tool)
- Go 1.21+ (for dashboard compilation)

### Build

```bash
# Compile all Erlang applications
rebar3 compile

# Build the WebAssembly dashboard
cd apps/cb_dashboard
GOARCH=wasm GOOS=js go build -o dist/ironledger.wasm .
```

### Run Tests

```bash
# Run all Common Test suites
rebar3 ct

# Run Dialyzer static analysis
rebar3 dialyzer

# Run PropEr property-based tests
rebar3 proper

# Full verification (must pass before commits)
rebar3 dialyzer && rebar3 ct && rebar3 proper
```

### Start the Application

```bash
# Start interactive shell
rebar3 shell

# The HTTP server will start on port 8081
# API base URL: http://localhost:8081/api/v1
```

### Serve the Dashboard

```bash
cd apps/cb_dashboard
go run serve.go

# Dashboard available at http://localhost:8080
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
