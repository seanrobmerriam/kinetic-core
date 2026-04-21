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
-type currency() :: 'USD' | 'EUR' | 'GBP' | 'JPY' | 'CHF'.

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
    created_at          :: timestamp_ms(),
    updated_at          :: timestamp_ms()
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
    account_id  :: uuid(),
    party_id    :: uuid(),
    name        :: binary(),
    currency    :: currency(),
    balance     :: amount(),
    status      :: account_status(),
    created_at  :: timestamp_ms(),
    updated_at  :: timestamp_ms()
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
