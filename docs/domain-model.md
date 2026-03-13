# IronLedger Domain Model

This document defines the core entities, their relationships, and the invariants that must
hold across the entire system. Every Erlang type, Mnesia table, and API field must be
consistent with the definitions here.

---

## 1. Core Entities

### 1.1 Party

A Party is a legal or natural person who can own one or more accounts.

| Field | Type | Description |
|-------|------|-------------|
| `party_id` | `binary()` UUID | Immutable primary key |
| `full_name` | `binary()` | Display name |
| `email` | `binary()` | Unique contact email |
| `status` | `atom()` | `active` \| `suspended` \| `closed` |
| `created_at` | `integer()` | Unix epoch milliseconds |
| `updated_at` | `integer()` | Unix epoch milliseconds |

**Invariants:**
- `party_id` is assigned on creation and never changes.
- A Party in `closed` status may not own new accounts.
- A Party in `suspended` status may not initiate transfers.

---

### 1.2 Account

An Account belongs to exactly one Party and holds a balance in a single currency.

| Field | Type | Description |
|-------|------|-------------|
| `account_id` | `binary()` UUID | Immutable primary key |
| `party_id` | `binary()` UUID | Owning party (foreign key) |
| `name` | `binary()` | Human label (e.g. "Savings") |
| `currency` | `atom()` | ISO 4217 atom: `'USD'`, `'EUR'`, etc. |
| `balance` | `non_neg_integer()` | Current balance in minor units |
| `status` | `atom()` | `active` \| `frozen` \| `closed` |
| `created_at` | `integer()` | Unix epoch milliseconds |
| `updated_at` | `integer()` | Unix epoch milliseconds |

**Invariants:**
- `balance` is always `>= 0`. It is impossible to create a negative balance through any
  normal operation. Any operation that would produce a negative balance is rejected with
  `{error, insufficient_funds}`.
- `currency` is set at creation and is immutable.
- A `frozen` account may not be debited or credited.
- A `closed` account may not be debited or credited. Closure is permanent.
- `balance` is never computed from ledger history at runtime; it is maintained as a
  running total updated atomically with each transaction.

---

### 1.3 Ledger Entry

A Ledger Entry is an immutable record of a single monetary movement. Every financial
transaction produces exactly two ledger entries (double-entry bookkeeping): one debit
and one credit.

| Field | Type | Description |
|-------|------|-------------|
| `entry_id` | `binary()` UUID | Immutable primary key |
| `txn_id` | `binary()` UUID | Parent transaction |
| `account_id` | `binary()` UUID | Account this entry applies to |
| `entry_type` | `atom()` | `debit` \| `credit` |
| `amount` | `non_neg_integer()` | Amount in minor units (always positive) |
| `currency` | `atom()` | ISO 4217 atom |
| `description` | `binary()` | Human-readable memo |
| `posted_at` | `integer()` | Unix epoch milliseconds |

**Invariants:**
- Ledger entries are **immutable**. They are never updated or deleted.
- For every `txn_id`, the sum of all `debit` amounts equals the sum of all `credit` amounts
  (double-entry invariant).
- `amount` is always `> 0`. Zero-value entries are rejected.
- `posted_at` is set at the moment of Mnesia commit and never modified.

---

### 1.4 Transaction

A Transaction represents a complete, atomic financial event. It is the parent of one or
more Ledger Entry pairs.

| Field | Type | Description |
|-------|------|-------------|
| `txn_id` | `binary()` UUID | Immutable primary key |
| `idempotency_key` | `binary()` | Caller-supplied unique key |
| `txn_type` | `atom()` | `transfer` \| `deposit` \| `withdrawal` \| `adjustment` |
| `status` | `atom()` | `pending` \| `posted` \| `failed` \| `reversed` |
| `amount` | `non_neg_integer()` | Principal amount in minor units |
| `currency` | `atom()` | ISO 4217 atom |
| `source_account_id` | `binary()` UUID \| `undefined` | Debit side (undefined for deposits) |
| `dest_account_id` | `binary()` UUID \| `undefined` | Credit side (undefined for withdrawals) |
| `description` | `binary()` | Memo |
| `created_at` | `integer()` | Unix epoch milliseconds |
| `posted_at` | `integer()` \| `undefined` | Set when status → `posted` |

**Invariants:**
- `idempotency_key` is globally unique. Submitting the same key twice returns the original
  transaction, regardless of the parameters in the second request.
- A `posted` transaction cannot be modified, only `reversed`.
- A `failed` transaction never has ledger entries.
- `amount` always equals the absolute value of the debit and credit legs.

---

## 2. Currency Model

- Supported currencies for the prototype: `'USD'`, `'EUR'`, `'GBP'`, `'JPY'`, `'CHF'`.
- **Minor units by currency:**

| Currency | Minor unit | Example: 1 unit |
|----------|-----------|-----------------|
| USD | cent (1/100) | `100` = $1.00 |
| EUR | cent (1/100) | `100` = €1.00 |
| GBP | penny (1/100) | `100` = £1.00 |
| CHF | rappen (1/100) | `100` = CHF 1.00 |
| JPY | yen (no minor unit) | `1` = ¥1 |

- For JPY, the "minor unit" is the yen itself. `amount` stores whole yen.
- **Cross-currency transfers are out of scope for the prototype.** Reject with
  `{error, currency_mismatch}`.

---

## 3. Entity Relationships

```
Party (1) ──────< Account (0..*)
                     │
                     │ source / dest
                     ▼
               Transaction (1) >────── LedgerEntry (2..*)
```

- One Party owns zero or more Accounts.
- One Transaction references up to two Accounts (source, destination).
- One Transaction produces two or more Ledger Entries (always even count).

---

## 4. Status Lifecycles

### Account Status
```
         create
           │
           ▼
        [active] ──── freeze ────► [frozen] ──── unfreeze ────► [active]
           │                                                        │
           └──────────────────── close ──────────────────────► [closed]
```
`closed` is terminal. No transitions out of `closed`.

### Transaction Status
```
  submit
    │
    ▼
[pending] ──── post ────► [posted] ──── reverse ────► [reversed]
    │
    └── fail ────► [failed]
```
`reversed` and `failed` are terminal.

---

## 5. Erlang Type Definitions

These types must be declared in `apps/cb_ledger/include/cb_ledger.hrl` and included
by all apps that deal with financial data.

```erlang
-type uuid()           :: binary().                          %% <<"xxxxxxxx-xxxx-...">>
-type amount()         :: non_neg_integer().                 %% minor units
-type currency()       :: 'USD' | 'EUR' | 'GBP' | 'JPY' | 'CHF'.
-type timestamp_ms()   :: non_neg_integer().                 %% Unix epoch ms

-type account_status() :: active | frozen | closed.
-type party_status()   :: active | suspended | closed.
-type txn_status()     :: pending | posted | failed | reversed.
-type txn_type()       :: transfer | deposit | withdrawal | adjustment.
-type entry_type()     :: debit | credit.

-record(party, {
    party_id    :: uuid(),
    full_name   :: binary(),
    email       :: binary(),
    status      :: party_status(),
    created_at  :: timestamp_ms(),
    updated_at  :: timestamp_ms()
}).

-record(account, {
    account_id  :: uuid(),
    party_id    :: uuid(),
    name        :: binary(),
    currency    :: currency(),
    balance     :: amount(),
    status      :: account_status(),
    created_at  :: timestamp_ms(),
    updated_at  :: timestamp_ms()
}).

-record(transaction, {
    txn_id            :: uuid(),
    idempotency_key   :: binary(),
    txn_type          :: txn_type(),
    status            :: txn_status(),
    amount            :: amount(),
    currency          :: currency(),
    source_account_id :: uuid() | undefined,
    dest_account_id   :: uuid() | undefined,
    description       :: binary(),
    created_at        :: timestamp_ms(),
    posted_at         :: timestamp_ms() | undefined
}).

-record(ledger_entry, {
    entry_id    :: uuid(),
    txn_id      :: uuid(),
    account_id  :: uuid(),
    entry_type  :: entry_type(),
    amount      :: amount(),
    currency    :: currency(),
    description :: binary(),
    posted_at   :: timestamp_ms()
}).
```