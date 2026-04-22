% =============================================================================
% IronLedger Domain Types
% =============================================================================
%%
%% This file contains all type definitions and record structures for the
%% IronLedger double-entry bookkeeping system.
%%
%% == Double-Entry Bookkeeping Fundamentals ==
%%
%% Every financial transaction in IronLedger is recorded using double-entry
%% bookkeeping, where every debit has an equal and corresponding credit.
%% This ensures the fundamental accounting equation always holds:
%%
%%    Assets = Liabilities + Equity
%%
%% In double-entry terms:
%% - Debits (debit entries) represent money flowing OUT of an account
%% - Credits (credit entries) represent money flowing INTO an account
%%
%% For asset and expense accounts: Debits INCREASE the balance
%% For liability, equity, and revenue accounts: Credits INCREASE the balance
%%
%% == Ledger Entries ==
%%
%% A #ledger_entry represents a single line item in the general ledger.
%% Each entry is immutable once posted - it can never be modified or deleted.
%% If an error needs correction, a new entry (reversal or adjustment) is created.
%% This immutability is essential for:
%% - Audit trails and regulatory compliance
%% - Financial statement integrity
%% - Forensic accounting and reconciliation
%%
%% =============================================================================

%% @doc UUID representing a unique identifier for any entity in the system.
%% Uses binary format for efficiency in Mnesia storage.
-type uuid() :: binary().

%% @doc Monetary amount in minor units (cents, pence, etc.).
%% Examples: 100 = $1.00 USD, 1 = $0.01 USD
%% CRITICAL: Never use floats for monetary values in financial systems.
-type amount() :: non_neg_integer().

%% @doc ISO 4217 currency codes supported by the system.
-type currency() :: 'USD' | 'EUR' | 'GBP' | 'JPY' | 'CHF' | 'AUD' | 'CAD' | 'SGD' | 'HKD' | 'NZD'.

%% @doc Omnichannel access channel type.
%% - web: Browser-based internet banking
%% - mobile: iOS/Android mobile banking app
%% - branch: Bank branch teller system
%% - atm: Automated teller machine
-type channel_type() :: web | mobile | branch | atm.

%% @doc Risk classification tier for a party.
-type risk_tier() :: low | medium | high | critical.

%% @doc Timestamp in milliseconds since Unix epoch (1970-01-01 00:00:00 UTC).
%% Uses `erlang:system_time(millisecond)` for generation.
-type timestamp_ms() :: non_neg_integer().

%% @doc Status of a customer/party record.
%% - active: Party can perform transactions
%% - suspended: Party is temporarily restricted from transactions
%% - closed: Party account is permanently closed
-type account_status() :: active | frozen | closed.

%% @doc Status of a customer/party record.
%% - active: Party can open accounts and perform transactions
%% - suspended: Party is temporarily restricted from new accounts/transactions
%% - closed: Party record is permanently closed
-type party_status() :: active | suspended | closed.

%% @doc KYC (Know Your Customer) verification status.
%% - not_started: No KYC process has been initiated
%% - pending: KYC documents submitted, awaiting review
%% - approved: KYC review passed, party is verified
%% - rejected: KYC review failed; notes explain the reason
-type kyc_status() :: not_started | pending | approved | rejected.

%% @doc Onboarding completion status for a party.
%% - incomplete: Profile setup is not yet complete
%% - complete: Onboarding steps are finished
-type onboarding_status() :: incomplete | complete.

%% @doc Structured postal address for a party.
-type party_address() :: #
{
    line1 := binary(),
    line2 => binary(),
    city := binary(),
    state => binary(),
    postal_code => binary(),
    country := binary()
}.

%% @doc Status of a financial transaction.
%% - pending: Transaction created but not yet processed
%% - posted: Transaction successfully recorded in the ledger
%% - failed: Transaction failed during processing
%% - reversed: Transaction was reversed (original entry still exists for audit)
-type txn_status() :: pending | posted | failed | reversed.

%% @doc Type of financial transaction.
%% - transfer: Money moved between two accounts
%% - deposit: Money added to an account (from external source)
%% - withdrawal: Money removed from an account (to external destination)
%% - adjustment: Correction or correction to a previous transaction
-type txn_type() :: transfer | deposit | withdrawal | adjustment.

%% @doc Direction of a ledger entry in double-entry bookkeeping.
%% - debit: Represents money flowing OUT of an account
%% - credit: Represents money flowing INTO an account
%%
%% In the context of the accounting equation:
%% - Debits increase Assets and Expenses
%% - Credits increase Liabilities, Equity, and Revenue
-type entry_type() :: debit | credit.

%% @doc High-level chart of account categories.
-type gl_account_type() :: asset | liability | equity | revenue | expense.

%% =============================================================================
%% Record Definitions
%% =============================================================================

%% @doc Represents a customer/party in the banking system.
%% A party can own multiple accounts and is the primary entity for
%% customer relationship management and regulatory compliance (KYC/AML).
%%
%% Fields:
%% - party_id: Unique UUID identifier for the party
%% - full_name: Legal name of the party (UTF-8 binary)
%% - email: Contact email address (UTF-8 binary)
%% - status: Current status of the party relationship
%% - kyc_status: KYC verification state (not_started | pending | approved | rejected)
%% - onboarding_status: Onboarding completion state (incomplete | complete)
%% - review_notes: Optional notes from the most recent KYC review
%% - doc_refs: List of document reference identifiers provided for KYC
%% - address: Optional structured postal address
%% - version: Monotonic version for party updates
%% - merged_into_party_id: Target party ID if this record was merged
%% - created_at: Timestamp when the party record was created
%% - updated_at: Timestamp of last modification to the party record
-record(party, {
    party_id            :: uuid(),
    full_name           :: binary(),
    email               :: binary(),
    status              :: party_status(),
    kyc_status          :: kyc_status(),
    onboarding_status   :: onboarding_status(),
    review_notes        :: binary() | undefined,
    doc_refs            :: [binary()],
    risk_tier           :: risk_tier(),
    address             :: party_address() | undefined,
    age                 :: non_neg_integer() | undefined,
    ssn                 :: binary() | undefined,
    version             :: pos_integer(),
    merged_into_party_id :: uuid() | undefined,
    created_at          :: timestamp_ms(),
    updated_at          :: timestamp_ms()
}).

%% @doc Immutable audit event for party changes.
%%
%% Each write operation on party data emits an append-only audit entry.
-record(party_audit, {
    audit_id    :: uuid(),
    party_id    :: uuid(),
    action      :: atom(),
    version     :: pos_integer(),
    metadata    :: map(),
    created_at  :: timestamp_ms()
}).

%% @doc Represents a financial account within the banking system.
%% Each account is owned by a single party and holds a specific currency.
%% Accounts track balance through ledger entries using double-entry bookkeeping.
%%
%% Fields:
%% - account_id: Unique UUID identifier for the account
%% - party_id: UUID of the party who owns this account
%% - name: Descriptive name for the account (e.g., "Checking Account")
%% - currency: ISO 4217 currency code for the account
%% - balance: Current balance in minor units (sum of all debit/credit entries)
%% - status: Current operational status of the account
%% - created_at: Timestamp when the account was created
%% - updated_at: Timestamp of last modification to the account
%%
%% == Balance Calculation ==
%% The balance is calculated as: Sum(Credits) - Sum(Debits)
%% For asset accounts, a positive balance means the account holder has funds.
-record(account, {
    account_id        :: uuid(),
    party_id          :: uuid(),
    name              :: binary(),
    currency          :: currency(),
    balance           :: amount(),
    status            :: account_status(),
    withdrawal_limit  :: amount() | undefined,
    created_at        :: timestamp_ms(),
    updated_at        :: timestamp_ms()
}).

%% @doc Chart of accounts node used for ledger reporting and GL hierarchy.
-record(chart_account, {
    code        :: binary(),
    name        :: binary(),
    account_type :: gl_account_type(),
    parent_code :: binary() | undefined,
    status      :: active | inactive,
    created_at  :: timestamp_ms(),
    updated_at  :: timestamp_ms()
}).

%% @doc Historical point-in-time account balance snapshot.
-record(balance_snapshot, {
    snapshot_id :: uuid(),
    account_id  :: uuid(),
    balance     :: amount(),
    currency    :: currency(),
    snapshot_at :: timestamp_ms()
}).

%% @doc Represents a financial transaction in the system.
%% A transaction is the parent entity that groups together one or more
%% ledger entries. In double-entry bookkeeping, a transfer transaction
%% will have exactly two ledger entries (one debit, one credit).
%%
%% Fields:
%% - txn_id: Unique UUID identifier for this transaction
%% - idempotency_key: Client-provided key to ensure safe retries
%% - txn_type: Category of the transaction
%% - status: Current state of the transaction lifecycle
%% - amount: Monetary amount in minor units
%% - currency: ISO 4217 currency code (all entries must match)
%% - source_account_id: Account money is debited from (for transfers)
%% - dest_account_id: Account money is credited to (for transfers)
%% - description: Human-readable description for statements/reports
%% - created_at: Timestamp when the transaction was initiated
%% - posted_at: Timestamp when entries were successfully posted (if posted)
%%
%% == Idempotency ==
%% The idempotency_key ensures that if a client retries a request (due to
%% network failure or timeout), the transaction is only executed once.
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
    channel           :: binary() | undefined,
    created_at        :: timestamp_ms(),
    posted_at         :: timestamp_ms() | undefined
}).

%% @doc Represents a single line item in the general ledger.
%% This is the core record of double-entry bookkeeping. Every financial
%% movement is recorded as a ledger entry with either debit or credit type.
%%
%% Entries are IMMUTABLE once created - they can never be modified or deleted.
%% This immutability is essential for:
%% - Complete audit trail (SOX, GDPR compliance)
%% - Financial statement integrity
%% - Transaction reconciliation
%% - Forensic accounting
%%
%% Fields:
%% - entry_id: Unique UUID identifier for this ledger entry
%% - txn_id: Reference to the parent transaction
%% - account_id: Account this entry affects
%% - entry_type: Either debit or credit
%% - amount: Monetary amount in minor units
%% - currency: ISO 4217 currency code
%% - description: Human-readable description for this entry
%% - posted_at: Timestamp when this entry was recorded
%%
%% == Invariant ==
%% For every transaction, the sum of all debits MUST equal the sum of all
%% credits. This is the fundamental double-entry bookkeeping invariant.
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

%% @doc Status of a funds hold on an account.
%% - active: Hold is in effect; reduces available balance
%% - released: Hold was manually released before expiry
%% - expired: Hold passed its expiry time and is no longer active
-type hold_status() :: active | released | expired.

%% @doc Represents a temporary hold placed on account funds.
%%
%% A hold reserves a portion of an account's balance, reducing the available
%% balance without reducing the ledger balance. Holds are used for pending
%% authorizations, compliance holds, and other temporary restrictions.
%%
%% Fields:
%% - hold_id: Unique UUID identifier for this hold
%% - account_id: Account the hold is placed on
%% - amount: Amount reserved in minor units (non-negative)
%% - reason: Human-readable reason for the hold (e.g., "Pending authorization")
%% - status: Current state of the hold (active | released | expired)
%% - placed_at: Timestamp when the hold was created
%% - released_at: Timestamp when the hold was released (if released or expired)
%% - expires_at: Optional timestamp when the hold auto-expires
-record(account_hold, {
    hold_id     :: uuid(),
    account_id  :: uuid(),
    amount      :: amount(),
    reason      :: binary(),
    status      :: hold_status(),
    placed_at   :: timestamp_ms(),
    released_at :: timestamp_ms() | undefined,
    expires_at  :: timestamp_ms() | undefined
}).

%% @doc Currency configuration with ISO 4217 precision rules.
-record(currency_config, {
    currency_code    :: currency(),
    precision_digits :: non_neg_integer(),
    description      :: binary(),
    is_active        :: boolean(),
    created_at       :: timestamp_ms()
}).

%% @doc Exchange rate between two currencies, stored as integer millionths.
%% rate_millionths = 1_000_000 means 1:1 parity.
%% Example: USD/EUR at 0.92 = 920_000.
-record(exchange_rate, {
    rate_id         :: uuid(),
    from_currency   :: currency(),
    to_currency     :: currency(),
    rate_millionths :: pos_integer(),
    recorded_at     :: timestamp_ms()
}).

%% @doc Domestic payment order lifecycle record.
-record(payment_order, {
    payment_id        :: uuid(),
    idempotency_key   :: binary(),
    party_id          :: uuid(),
    source_account_id :: uuid(),
    dest_account_id   :: uuid(),
    amount            :: amount(),
    currency          :: currency(),
    description       :: binary(),
    status            :: initiated | validating | processing | completed | failed | cancelled,
    stp_decision      :: straight_through | exception_queued | undefined,
    failure_reason    :: binary() | undefined,
    retry_count       :: non_neg_integer(),
    created_at        :: timestamp_ms(),
    updated_at        :: timestamp_ms()
}).

%% @doc Exception queue item for manual intervention.
-record(exception_item, {
    item_id          :: uuid(),
    payment_id       :: uuid(),
    reason           :: binary(),
    status           :: pending | resolved,
    resolution       :: approved | rejected | undefined,
    resolved_by      :: binary() | undefined,
    resolution_notes :: binary() | undefined,
    created_at       :: timestamp_ms(),
    updated_at       :: timestamp_ms()
}).

%% @doc Per-channel transaction limit configuration.
%%
%% Limits are enforced per channel type and currency. The composite
%% `limit_key' `{channel_type(), currency()}' is used as the Mnesia
%% primary key so each (channel, currency) pair has exactly one row.
%% - daily_limit: Maximum cumulative transaction volume per day in minor units
%% - per_txn_limit: Maximum single transaction amount in minor units
%% A value of 0 means "unlimited".
-record(channel_limit, {
    limit_key     :: {channel_type(), currency()},
    daily_limit   :: non_neg_integer(),
    per_txn_limit :: non_neg_integer(),
    updated_at    :: timestamp_ms()
}).

%% @doc Immutable channel activity log entry.
%%
%% Records each inbound API request with its channel context.
-record(channel_activity, {
    log_id      :: uuid(),
    channel     :: channel_type() | undefined,
    party_id    :: uuid() | undefined,
    action      :: binary(),
    endpoint    :: binary(),
    status_code :: non_neg_integer(),
    created_at  :: timestamp_ms()
}).

%% @doc Notification channel preference for a party.
%%
%% Controls which channels receive which event type notifications.
-record(notification_preference, {
    pref_id     :: uuid(),
    party_id    :: uuid(),
    channel     :: channel_type(),
    event_types :: [binary()],
    enabled     :: boolean(),
    updated_at  :: timestamp_ms()
}).

%% @doc API key status type.
-type api_key_status() :: active | revoked.

%% @doc Partner API key for programmatic access.
%%
%% API keys are used as an alternative to session tokens for partner/system integrations.
%% The key_secret is never stored — only the SHA-256 hash is persisted.
%% Callers present the full key as a Bearer token; the middleware hashes it for lookup.
-record(api_key, {
    key_id             :: uuid(),
    key_hash           :: binary(),
    label              :: binary(),
    partner_id         :: binary(),
    role               :: admin | operations | read_only,
    status             :: api_key_status(),
    rate_limit_per_min :: pos_integer(),
    expires_at         :: timestamp_ms() | never,
    created_at         :: timestamp_ms(),
    updated_at         :: timestamp_ms()
}).
