# IronLedger Data Schema

This document defines every Mnesia table used by IronLedger. All `mnesia:create_table/2`
calls must exactly match these definitions. Do not deviate from field names, types, or
index declarations.

---

## 1. Mnesia Configuration

```erlang
%% In cb_integration/src/cb_integration_app.erl start/2:
mnesia:create_schema([node()]),
mnesia:start(),
cb_schema:create_tables().
```

All tables use `{ram_copies, [node()]}` for the prototype. Disk copies are deferred.

---

## 2. Table Definitions

### 2.1 `party` table

```erlang
mnesia:create_table(party, [
    {ram_copies, [node()]},
    {attributes, record_info(fields, party)},
    {index, [email, status]}
]).
```

| Position | Field | Type | Notes |
|----------|-------|------|-------|
| 1 | `party_id` | `binary()` | Primary key, UUID |
| 2 | `full_name` | `binary()` | Required |
| 3 | `email` | `binary()` | Unique; secondary index |
| 4 | `status` | `atom()` | `active \| suspended \| closed`; secondary index |
| 5 | `created_at` | `integer()` | Unix epoch ms |
| 6 | `updated_at` | `integer()` | Unix epoch ms |

**Access patterns:**
- Lookup by `party_id` → `mnesia:read(party, PartyId, read)`
- Lookup by `email` → `mnesia:index_read(party, Email, email)`
- List all → `mnesia:match_object(party, #party{_ = '_'}, read)`

---

### 2.2 `account` table

```erlang
mnesia:create_table(account, [
    {ram_copies, [node()]},
    {attributes, record_info(fields, account)},
    {index, [party_id, status]}
]).
```

| Position | Field | Type | Notes |
|----------|-------|------|-------|
| 1 | `account_id` | `binary()` | Primary key, UUID |
| 2 | `party_id` | `binary()` | Foreign key; secondary index |
| 3 | `name` | `binary()` | Display label |
| 4 | `currency` | `atom()` | `'USD' \| 'EUR' \| 'GBP' \| 'JPY' \| 'CHF'` |
| 5 | `balance` | `integer()` | Minor units; always `>= 0` |
| 6 | `status` | `atom()` | `active \| frozen \| closed`; secondary index |
| 7 | `created_at` | `integer()` | Unix epoch ms |
| 8 | `updated_at` | `integer()` | Unix epoch ms |

**Access patterns:**
- Lookup by `account_id` → `mnesia:read(account, AccountId, write)` (always write-lock for balance updates)
- List by `party_id` → `mnesia:index_read(account, PartyId, party_id)`

**Critical:** Balance must only be read and written inside `mnesia:transaction/1`. Never read balance outside a transaction when making a transfer decision.

---

### 2.3 `transaction` table

```erlang
mnesia:create_table(transaction, [
    {ram_copies, [node()]},
    {attributes, record_info(fields, transaction)},
    {index, [idempotency_key, source_account_id, dest_account_id, status]}
]).
```

| Position | Field | Type | Notes |
|----------|-------|------|-------|
| 1 | `txn_id` | `binary()` | Primary key, UUID |
| 2 | `idempotency_key` | `binary()` | Unique; secondary index |
| 3 | `txn_type` | `atom()` | `transfer \| deposit \| withdrawal \| adjustment` |
| 4 | `status` | `atom()` | `pending \| posted \| failed \| reversed`; secondary index |
| 5 | `amount` | `integer()` | Minor units; `> 0` |
| 6 | `currency` | `atom()` | ISO 4217 atom |
| 7 | `source_account_id` | `binary() \| undefined` | Debit side; secondary index |
| 8 | `dest_account_id` | `binary() \| undefined` | Credit side; secondary index |
| 9 | `description` | `binary()` | Memo |
| 10 | `created_at` | `integer()` | Unix epoch ms |
| 11 | `posted_at` | `integer() \| undefined` | Set on post |

**Access patterns:**
- Lookup by `txn_id` → `mnesia:read(transaction, TxnId, read)`
- Idempotency check → `mnesia:index_read(transaction, IdempotencyKey, idempotency_key)`
- List by `source_account_id` → `mnesia:index_read(transaction, AccountId, source_account_id)`
- List by `dest_account_id` → `mnesia:index_read(transaction, AccountId, dest_account_id)`

---

### 2.4 `ledger_entry` table

```erlang
mnesia:create_table(ledger_entry, [
    {ram_copies, [node()]},
    {attributes, record_info(fields, ledger_entry)},
    {index, [txn_id, account_id]}
]).
```

| Position | Field | Type | Notes |
|----------|-------|------|-------|
| 1 | `entry_id` | `binary()` | Primary key, UUID |
| 2 | `txn_id` | `binary()` | Parent transaction; secondary index |
| 3 | `account_id` | `binary()` | Owning account; secondary index |
| 4 | `entry_type` | `atom()` | `debit \| credit` |
| 5 | `amount` | `integer()` | Minor units; `> 0` |
| 6 | `currency` | `atom()` | ISO 4217 atom |
| 7 | `description` | `binary()` | Memo |
| 8 | `posted_at` | `integer()` | Unix epoch ms; set at commit |

**Access patterns:**
- Entries by transaction → `mnesia:index_read(ledger_entry, TxnId, txn_id)`
- Entries by account → `mnesia:index_read(ledger_entry, AccountId, account_id)`

**Immutability:** Ledger entries are written once and never updated. Any code that calls `mnesia:write` on an existing `ledger_entry` record is a bug.

---

## 3. Schema Module

All table creation must go through `cb_schema.erl` in `apps/cb_integration/src/`:

```erlang
-module(cb_schema).
-export([create_tables/0]).

create_tables() ->
    Tables = [party, account, transaction, ledger_entry],
    lists:foreach(fun create_if_not_exists/1, Tables).

create_if_not_exists(TableName) ->
    case mnesia:create_table(TableName, table_spec(TableName)) of
        {atomic, ok}                        -> ok;
        {aborted, {already_exists, _Table}} -> ok;
        {aborted, Reason}                   -> error({schema_error, TableName, Reason})
    end.
```

---

## 4. Transaction Sequence — Transfer

The following Mnesia transaction sequence must be used for all transfer operations:

```erlang
mnesia:transaction(fun() ->
    %% 1. Idempotency check
    case mnesia:index_read(transaction, IdempotencyKey, idempotency_key) of
        [Existing] -> {ok, Existing};          %% return early, no mutation
        [] ->
            %% 2. Lock and read both accounts
            [Source] = mnesia:read(account, SourceId, write),
            [Dest]   = mnesia:read(account, DestId,   write),

            %% 3. Validate
            ok = assert_active(Source),
            ok = assert_active(Dest),
            ok = assert_currency_match(Source, Dest, Currency),
            ok = assert_sufficient_funds(Source, Amount),

            %% 4. Update balances
            Now = erlang:system_time(millisecond),
            mnesia:write(Source#account{
                balance    = Source#account.balance - Amount,
                updated_at = Now
            }),
            mnesia:write(Dest#account{
                balance    = Dest#account.balance + Amount,
                updated_at = Now
            }),

            %% 5. Write transaction record
            Txn = #transaction{...},
            mnesia:write(Txn),

            %% 6. Write ledger entries (always two)
            mnesia:write(#ledger_entry{entry_type = debit,  account_id = SourceId, ...}),
            mnesia:write(#ledger_entry{entry_type = credit, account_id = DestId,   ...}),

            {ok, Txn}
    end
end).
```

This sequence must not be split across multiple transactions. All six steps are atomic.

---

## 5. Pagination

All list endpoints paginate using `page` (1-indexed) and `page_size` (default 20, max 100).

Since Mnesia does not support native offset pagination, use the following pattern:

```erlang
paginate(AllRecords, Page, PageSize) ->
    Total  = length(AllRecords),
    Offset = (Page - 1) * PageSize,
    Items  = lists:sublist(AllRecords, Offset + 1, PageSize),
    #{items => Items, total => Total, page => Page, page_size => PageSize}.
```

Sort records by `created_at` descending before paginating for transaction/ledger lists.