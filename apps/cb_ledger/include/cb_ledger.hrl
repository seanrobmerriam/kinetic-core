%% IronLedger Domain Types
%% This file contains all type definitions from docs/domain-model.md §5

-type uuid()           :: binary().
-type amount()         :: non_neg_integer().
-type currency()       :: 'USD' | 'EUR' | 'GBP' | 'JPY' | 'CHF'.
-type timestamp_ms()   :: non_neg_integer().

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
