# IronLedger Prototype — Feature PRD

**Version:** 1.0  
**Status:** Approved for build  
**Scope:** Minimum viable core banking prototype

---

## 1. Objective

Deliver a working IronLedger prototype that demonstrates core banking capabilities:
account management, money transfers, ledger history, and a Go/Wasm browser dashboard
that exercises all functions. The prototype must be functionally correct, not
production-hardened (no TLS, no auth, no rate limiting in this phase).

---

## 2. In Scope

### 2.1 Party Management
| ID | Feature | Notes |
|----|---------|-------|
| P-01 | Create a party | `full_name`, `email` required |
| P-02 | Get a party by ID | Returns party record |
| P-03 | List all parties | Paginated, 20 per page |
| P-04 | Suspend a party | Blocks transfers; does not affect accounts |
| P-05 | Close a party | Party must have no active accounts |

### 2.2 Account Management
| ID | Feature | Notes |
|----|---------|-------|
| A-01 | Create an account | `party_id`, `currency`, `name` required |
| A-02 | Get an account by ID | Returns account record including balance |
| A-03 | List accounts for a party | All statuses |
| A-04 | Freeze an account | Blocks debits and credits |
| A-05 | Unfreeze an account | Restores to `active` |
| A-06 | Close an account | Balance must be zero; permanent |
| A-07 | Get account balance | Returns current balance in minor units + formatted |

### 2.3 Transfers & Payments
| ID | Feature | Notes |
|----|---------|-------|
| T-01 | Transfer between accounts | Both accounts same currency; atomic |
| T-02 | Deposit to account | Credit only; no source account |
| T-03 | Withdraw from account | Debit only; no destination account |
| T-04 | Idempotent submission | Same `idempotency_key` returns original result |
| T-05 | Get transaction by ID | Full transaction record |
| T-06 | List transactions for account | Paginated, 20 per page, newest first |
| T-07 | Reverse a posted transaction | Creates equal and opposite ledger entries |

### 2.4 Ledger
| ID | Feature | Notes |
|----|---------|-------|
| L-01 | Get ledger entries for a transaction | All debit/credit legs |
| L-02 | Get ledger entries for an account | Paginated history |

### 2.5 Dashboard (Go/Wasm)
| ID | Feature | Notes |
|----|---------|-------|
| D-01 | Parties screen | List, create, suspend, close |
| D-02 | Accounts screen | List by party, create, freeze, unfreeze, close |
| D-03 | Account detail screen | Balance, transaction history, ledger entries |
| D-04 | Transfer screen | Form: source, destination, amount, currency, memo |
| D-05 | Deposit / Withdraw screen | Single-account credit or debit |
| D-06 | Transaction detail screen | Full record + ledger entries |
| D-07 | Error display | All API errors shown inline; never silent |
| D-08 | Amount formatting | Display as decimal (e.g. $10.00); transmit as integer |

---

## 3. Explicitly Out of Scope (Prototype)

The following must **not** be built in this phase. If the agent encounters a requirement
that implies these, it must stop and flag it rather than implement a partial version.

- Authentication, authorisation, JWT, OAuth
- TLS / HTTPS
- Foreign exchange / cross-currency conversion
- Fee schedules or interest calculations
- Scheduled or recurring payments
- Regulatory reporting (AML, KYC, PCI-DSS)
- Multi-node Mnesia clustering
- Event streaming (Kafka, RabbitMQ)
- Soft delete / audit log beyond ledger entries
- Email or SMS notifications
- Rate limiting or DDoS protection

---

## 4. Acceptance Criteria

The prototype is complete when:

1. `rebar3 dialyzer && rebar3 ct && rebar3 proper` all pass with zero failures.
2. `rebar3 shell` starts all OTP applications without error.
3. All 26 in-scope API endpoints return correct responses as defined in `docs/api-contract.yaml`.
4. The Go/Wasm dashboard compiles with `GOARCH=wasm GOOS=js go build` and loads in a
   browser without JavaScript errors.
5. All 8 dashboard screens are functional end-to-end against the running Erlang backend.
6. A transfer of 1000 units from Account A to Account B:
   - Decrements A's balance by 1000.
   - Increments B's balance by 1000.
   - Creates exactly 2 ledger entries summing to 1000 debit and 1000 credit.
   - Is idempotent: repeating the call with the same `idempotency_key` changes no balances.
7. Attempting to transfer more than an account's balance returns `{error, insufficient_funds}`.
8. Closing a non-zero balance account returns `{error, account_has_balance}`.

---

## 5. Non-Functional Targets (Prototype Only)

| Metric | Target |
|--------|--------|
| Transfer latency (local) | < 50ms p99 |
| Mnesia table type | RAM copies (disk copies deferred) |
| Dashboard initial load | < 2s on localhost |
| Concurrent users | 1 (prototype; no concurrency testing required) |

---

## 6. Build Deliverables

| Deliverable | Location |
|-------------|----------|
| Erlang apps | `apps/cb_accounts`, `cb_ledger`, `cb_payments`, `cb_party`, `cb_integration` |
| Go/Wasm dashboard | `apps/cb_dashboard/` |
| Compiled Wasm | `apps/cb_dashboard/dist/ironledger.wasm` |
| OpenAPI spec | `docs/api-contract.yaml` |
| Test suites | `apps/*/test/` |
| Domain types header | `apps/cb_ledger/include/cb_ledger.hrl` |