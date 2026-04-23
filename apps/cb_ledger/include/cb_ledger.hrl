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
    metadata            :: map() | undefined,
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

%% @doc Categorization and free-form tags attached to a transaction.
%%
%% Stored in a separate table so the immutable #transaction{} record
%% never needs to be modified.  One record per transaction; upsert via PUT.
%%
%% Fields:
%% - tag_id: Unique UUID for this tag record
%% - txn_id: Foreign key → transaction.txn_id
%% - category: A single top-level category string (e.g. <<"payroll">>)
%% - tags: Zero or more free-form tag strings
%% - created_at: Millisecond timestamp of first write
%% - updated_at: Millisecond timestamp of last write
-record(transaction_tag, {
    tag_id     :: uuid(),
    txn_id     :: uuid(),
    category   :: binary() | undefined,
    tags       :: [binary()],
    created_at :: timestamp_ms(),
    updated_at :: timestamp_ms()
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
%%
%% SLA fields:
%% - sla_minutes: resolution target in minutes (undefined = no SLA set)
%% - sla_deadline: absolute deadline in ms since epoch (undefined = no SLA set)
%% - escalation_tier: 0 = not escalated, 1 = supervisor, 2 = manager
-record(exception_item, {
    item_id          :: uuid(),
    payment_id       :: uuid(),
    reason           :: binary(),
    status           :: pending | resolved | escalated,
    resolution       :: approved | rejected | undefined,
    resolved_by      :: binary() | undefined,
    resolution_notes :: binary() | undefined,
    sla_minutes      :: pos_integer() | undefined,
    sla_deadline     :: timestamp_ms() | undefined,
    escalation_tier  :: non_neg_integer(),
    created_at       :: timestamp_ms(),
    updated_at       :: timestamp_ms()
}).

%% @doc Configurable STP routing rule.
%%
%% Rules are evaluated in ascending priority order (lower number = higher priority).
%% The first rule whose condition matches determines the routing outcome.
%%
%% Condition types:
%% - amount:          condition_params = #{threshold => pos_integer()}
%% - kyc:             condition_params = #{required_status => approved | pending | ...}
%% - account_status:  condition_params = #{required_status => active | ...}
%% - aml:             condition_params = #{} (delegates to cb_aml)
%% - sanctions:       condition_params = #{} (delegates to party blocked flag)
%% - velocity:        condition_params = #{max_daily_amount => pos_integer()}
%%
%% Actions:
%% - straight_through: auto-approve the payment
%% - exception:        route to manual review queue
%% - block:            reject outright (no manual review)
-record(stp_routing_rule, {
    rule_id          :: uuid(),
    name             :: binary(),
    priority         :: pos_integer(),
    condition_type   :: amount | kyc | account_status | aml | sanctions | velocity,
    condition_params :: map(),
    action           :: straight_through | exception | block,
    enabled          :: boolean(),
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

%% @doc Cross-channel session record.
%%
%% Tracks a party's authenticated session on a specific channel.
%% Sessions can be invalidated individually or all at once for a party,
%% enabling cross-channel session synchronisation and forced logout flows.
-record(channel_session, {
    session_id     :: uuid(),
    party_id       :: uuid(),
    channel        :: channel_type(),
    status         :: active | invalidated,
    initiated_at   :: timestamp_ms(),
    invalidated_at :: timestamp_ms() | undefined,
    metadata       :: map()
}).

%% @doc Per-channel feature flag.
%%
%% Controls which features are enabled on a per-channel basis.
%% Keyed by the composite `{channel_type(), FeatureName}' to allow
%% O(1) lookups. The `channel' field is stored separately to support
%% secondary index queries by channel.
-record(channel_feature_flag, {
    flag_key   :: {channel_type(), binary()},
    channel    :: channel_type(),
    feature    :: binary(),
    enabled    :: boolean(),
    updated_at :: timestamp_ms()
}).

%% =============================================================================
%% Compliance & AML Types
%% =============================================================================

%% @doc Status of a KYC verification workflow instance.
-type kyc_workflow_status() :: pending | in_progress | completed | failed | abandoned.

%% @doc Status of a single step within a KYC workflow.
-type kyc_step_status() :: pending | in_progress | completed | failed | skipped.

%% @doc Step type within a KYC workflow.
-type kyc_step_type() :: document_collection | identity_check | sanctions_screening |
                         risk_assessment | manual_review | approval.

%% @doc Identity verification provider.
-type idv_provider() :: internal | equifax | experian | lexisnexis.

%% @doc Status of an identity verification check.
-type idv_check_status() :: pending | submitted | passed | failed | timed_out.

%% @doc AML rule condition type.
-type aml_condition_type() :: amount_threshold | country_risk | frequency | velocity | pattern.

%% @doc AML rule action when the condition is triggered.
-type aml_rule_action() :: flag | block | alert | escalate.

%% @doc Status of a suspicious activity alert.
-type suspicious_activity_status() :: open | under_review | cleared | escalated | filed.

%% @doc Status of an AML compliance case.
-type aml_case_status() :: open | investigating | closed | escalated.

%% @doc Status of a Suspicious Activity Report.
-type sar_report_status() :: draft | submitted | filed | withdrawn.

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

%% @doc Records a single API request made with an API key.
%%
%% Used to build per-key usage reports in the Developer Hub.
-record(api_usage_event, {
    event_id    :: uuid(),
    key_id      :: uuid(),
    method      :: binary(),
    path        :: binary(),
    recorded_at :: timestamp_ms()
}).

%% =============================================================================
%% Compliance & AML Records (P2-S1)
%% =============================================================================

%% @doc A single step within a KYC verification workflow.
%%
%% Steps are created as part of a workflow and advance independently.
-record(kyc_step, {
    step_id         :: uuid(),
    workflow_id     :: uuid(),
    name            :: binary(),
    step_type       :: kyc_step_type(),
    sequence_order  :: pos_integer(),
    status          :: kyc_step_status(),
    data            :: map(),
    completed_at    :: timestamp_ms() | undefined,
    created_at      :: timestamp_ms()
}).

%% @doc A KYC verification workflow instance bound to a party.
%%
%% A workflow progresses through ordered steps: document collection,
%% identity check, sanctions screening, risk assessment, and approval.
%% The current_step_id tracks the active step.
-record(kyc_workflow, {
    workflow_id         :: uuid(),
    party_id            :: uuid(),
    name                :: binary(),
    status              :: kyc_workflow_status(),
    step_ids            :: [uuid()],
    current_step_id     :: uuid() | undefined,
    completed_at        :: timestamp_ms() | undefined,
    created_at          :: timestamp_ms(),
    updated_at          :: timestamp_ms()
}).

%% @doc An identity verification check request to an external provider.
%%
%% The check orchestrator submits a request, polls or receives a callback,
%% and retries up to max_retries on transient failures.
-record(idv_check, {
    check_id        :: uuid(),
    party_id        :: uuid(),
    provider        :: idv_provider(),
    status          :: idv_check_status(),
    retry_count     :: non_neg_integer(),
    max_retries     :: non_neg_integer(),
    provider_ref    :: binary() | undefined,
    result_data     :: map(),
    requested_at    :: timestamp_ms(),
    expires_at      :: timestamp_ms() | undefined,
    completed_at    :: timestamp_ms() | undefined,
    created_at      :: timestamp_ms(),
    updated_at      :: timestamp_ms()
}).

%% @doc An AML rule definition used to evaluate transactions and party behaviour.
%%
%% Rules have a condition type (e.g., amount_threshold, velocity) with a
%% threshold value, and an action to take when the condition fires.
-record(aml_rule, {
    rule_id         :: uuid(),
    name            :: binary(),
    description     :: binary(),
    condition_type  :: aml_condition_type(),
    threshold_value :: number(),
    action          :: aml_rule_action(),
    enabled         :: boolean(),
    version         :: pos_integer(),
    created_at      :: timestamp_ms(),
    updated_at      :: timestamp_ms()
}).

%% @doc A suspicious activity alert raised by the AML rules engine.
%%
%% Alerts are generated when a rule fires and enter the open queue.
%% Compliance staff review them and either clear or escalate to a case.
-record(suspicious_activity, {
    alert_id        :: uuid(),
    party_id        :: uuid(),
    txn_id          :: uuid() | undefined,
    rule_id         :: uuid(),
    reason          :: binary(),
    status          :: suspicious_activity_status(),
    risk_score      :: non_neg_integer(),
    metadata        :: map(),
    reviewed_by     :: uuid() | undefined,
    reviewed_at     :: timestamp_ms() | undefined,
    created_at      :: timestamp_ms(),
    updated_at      :: timestamp_ms()
}).

%% @doc A compliance case grouping one or more suspicious activity alerts.
%%
%% Cases are opened when alerts require deeper investigation. A case may
%% be closed (no action), escalated (requires SAR filing), or still open.
-record(aml_case, {
    case_id         :: uuid(),
    party_id        :: uuid(),
    alert_ids       :: [uuid()],
    status          :: aml_case_status(),
    assignee        :: uuid() | undefined,
    summary         :: binary(),
    resolution      :: binary() | undefined,
    closed_at       :: timestamp_ms() | undefined,
    created_at      :: timestamp_ms(),
    updated_at      :: timestamp_ms()
}).

%% ---------------------------------------------------------------------------
%% Marketplace / Connector types (P3-S2)
%% ---------------------------------------------------------------------------

%% @doc Connector provider type.
-type connector_type() :: aws | azure | stripe | custom.

%% @doc Connector lifecycle status.
-type connector_status() :: registered | enabled | disabled | deprecated.

%% @doc Partner application workflow status.
-type partner_application_status() :: pending | approved | rejected.

%% ---------------------------------------------------------------------------

%% @doc A registered connector definition in the marketplace.
%%
%% Connectors describe external service integrations. Each connector implements
%% the cb_connector_behaviour callbacks and is registered here before use.
-record(connector_definition, {
    connector_id    :: uuid(),
    name            :: binary(),
    type            :: connector_type(),
    module          :: module(),
    status          :: connector_status(),
    version         :: binary(),
    capabilities    :: [binary()],
    config_schema   :: map(),
    description     :: binary(),
    created_at      :: timestamp_ms(),
    updated_at      :: timestamp_ms()
}).

%% @doc An immutable snapshot of a connector's state at a point in time.
%%
%% Created before each update so the connector can be rolled back to
%% any prior configuration. Only one version is marked active at a time.
-record(connector_version, {
    version_id          :: uuid(),
    connector_id        :: uuid(),
    version             :: binary(),
    module              :: module(),
    capabilities        :: [binary()],
    config_snapshot     :: map(),
    is_active           :: boolean(),
    created_at          :: timestamp_ms(),
    rolled_back_at      :: timestamp_ms() | undefined
}).

%% @doc A partner application requesting access to marketplace connectors.
%%
%% Partners submit applications that are reviewed by operations staff.
%% The compatibility check validates that all requested connectors are
%% registered and enabled before approval is permitted.
-record(partner_application, {
    application_id          :: uuid(),
    partner_id              :: uuid(),
    name                    :: binary(),
    contact_email           :: binary(),
    requested_connectors    :: [uuid()],
    status                  :: partner_application_status(),
    reviewed_by             :: uuid() | undefined,
    reviewed_at             :: timestamp_ms() | undefined,
    rejection_reason        :: binary() | undefined,
    created_at              :: timestamp_ms(),
    updated_at              :: timestamp_ms()
}).

%% @doc A Suspicious Activity Report filed with a regulatory body.
%%
%% SARs are generated from escalated compliance cases. The report progresses
%% from draft through submission to filed status.
-record(sar_report, {
    sar_id              :: uuid(),
    case_id             :: uuid(),
    party_id            :: uuid(),
    reference_number    :: binary() | undefined,
    narrative           :: binary(),
    status              :: sar_report_status(),
    submitted_at        :: timestamp_ms() | undefined,
    filed_at            :: timestamp_ms() | undefined,
    created_at          :: timestamp_ms(),
    updated_at          :: timestamp_ms()
}).

%%====================================================================
%% P3-S3: Streaming and Advanced Payments Types
%%====================================================================

%% Schema compatibility policy: backward = new readers can read old data;
%% forward = old readers can read new data; full = both.
-type schema_compatibility() :: backward | forward | full | none.

%% SWIFT/ISO 20022 message classification.
-type swift_message_type() :: mt103 | mt202 | mx_pain001 | mx_camt053.

%% SWIFT/ISO 20022 processing status.
-type swift_message_status() :: received | validated | rejected | translated | posted.

%% Settlement run lifecycle.
-type settlement_run_status() :: open | closed | reconciled | failed.

%% Reconciliation match state for a single entry.
-type reconciliation_match_status() :: matched | unmatched | disputed.

%%====================================================================
%% P4-S2: Real-Time Processing Scale Types

-type cluster_node_status() :: active | inactive | unreachable.
-type cluster_node_role()   :: primary | secondary | observer.

-type scaling_direction() :: scale_out | scale_in.
-type scaling_rule_status() :: triggered | idle.

-type recovery_status() :: pending | active | completed | aborted.

%% P3-S3: Streaming and Advanced Payments Records
%%====================================================================

%% @doc Versioned event schema definition for the registry.
%%
%% Each (event_type, version) pair is unique. The schema field holds
%% a map describing the expected payload structure. Compatibility controls
%% which evolution strategies are allowed for this event type.
-record(event_schema_version, {
    schema_id     :: uuid(),
    event_type    :: binary(),
    version       :: pos_integer(),
    schema        :: map(),
    compatibility :: schema_compatibility(),
    created_at    :: timestamp_ms()
}).

%% @doc Streaming consumer cursor — tracks read offset per consumer/topic.
%%
%% last_event_ts: millisecond timestamp of the last event successfully
%% delivered to this consumer. Used for cursor-based replay.
-record(consumer_cursor, {
    cursor_id     :: uuid(),
    consumer_id   :: binary(),
    topic         :: binary(),
    last_event_ts :: timestamp_ms(),
    updated_at    :: timestamp_ms()
}).

%% @doc Incoming SWIFT or ISO 20022 payment message.
%%
%% raw_payload holds the original binary (MT field string or XML).
%% parsed_fields holds a normalized key-value map extracted by the pipeline.
%% payment_id is set once the message has been translated to a payment_order.
-record(swift_message, {
    message_id     :: uuid(),
    message_type   :: swift_message_type(),
    sender_bic     :: binary(),
    receiver_bic   :: binary(),
    reference      :: binary(),
    amount         :: amount() | undefined,
    currency       :: currency() | undefined,
    raw_payload    :: binary(),
    parsed_fields  :: map(),
    status         :: swift_message_status(),
    rejection_reason :: binary() | undefined,
    payment_id     :: uuid() | undefined,
    received_at    :: timestamp_ms(),
    updated_at     :: timestamp_ms()
}).

%% @doc A settlement batch run for a single payment rail.
%%
%% expected_total: sum of expected settlement credits/debits (minor units).
%% actual_total: sum of matched entries from the ledger.
-record(settlement_run, {
    run_id         :: uuid(),
    rail           :: binary(),
    status         :: settlement_run_status(),
    expected_total :: amount(),
    actual_total   :: amount(),
    opened_at      :: timestamp_ms(),
    closed_at      :: timestamp_ms() | undefined,
    reconciled_at  :: timestamp_ms() | undefined,
    updated_at     :: timestamp_ms()
}).

%% @doc One entry in a settlement reconciliation run.
%%
%% payment_id and ledger_entry_id pair: if match_status = matched,
%% both are present and the amounts agree. If unmatched, ledger_entry_id
%% may be undefined (no matching ledger entry was found).
-record(reconciliation_entry, {
    entry_id        :: uuid(),
    run_id          :: uuid(),
    payment_id      :: uuid(),
    ledger_entry_id :: uuid() | undefined,
    expected_amount :: amount(),
    actual_amount   :: amount() | undefined,
    currency        :: currency(),
    match_status    :: reconciliation_match_status(),
    created_at      :: timestamp_ms(),
    updated_at      :: timestamp_ms()
}).

%% P4-S2: Real-Time Processing Scale Records

%% @doc Registered member of the distributed processing cluster.
%%
%% erlang_node is the Erlang node atom (e.g. 'kinetic@host1').
%% role identifies whether this node accepts primary write traffic.
%% last_heartbeat_at is updated on each health probe.
-record(cluster_node, {
    node_id          :: uuid(),
    erlang_node      :: atom(),
    host             :: binary(),
    port             :: pos_integer(),
    role             :: cluster_node_role(),
    status           :: cluster_node_status(),
    registered_at    :: timestamp_ms(),
    last_heartbeat_at :: timestamp_ms()
}).

%% @doc Optimistic concurrency version token for a tracked resource.
%%
%% version is a monotonically increasing integer incremented on each write.
%% resource_type identifies the record type (e.g. account, payment_order).
-record(version_token, {
    token_id      :: uuid(),
    resource_type :: binary(),
    resource_id   :: uuid(),
    version       :: non_neg_integer(),
    created_at    :: timestamp_ms(),
    updated_at    :: timestamp_ms()
}).

%% @doc Autoscaling rule evaluated against live capacity samples.
%%
%% metric_name is the key used in capacity_sample records.
%% threshold is the numeric boundary that triggers scaling action.
%% cooldown_seconds prevents rapid re-triggering after an event.
-record(scaling_rule, {
    rule_id          :: uuid(),
    name             :: binary(),
    metric_name      :: binary(),
    threshold        :: number(),
    direction        :: scaling_direction(),
    cooldown_seconds :: non_neg_integer(),
    enabled          :: boolean(),
    last_triggered_at :: timestamp_ms() | undefined,
    created_at       :: timestamp_ms(),
    updated_at       :: timestamp_ms()
}).

%% @doc A single capacity metric observation used by autoscaling rules.
-record(capacity_sample, {
    sample_id   :: uuid(),
    metric_name :: binary(),
    value       :: number(),
    node_id     :: uuid() | undefined,
    recorded_at :: timestamp_ms()
}).

%% @doc Snapshot checkpoint for failover and state recovery.
%%
%% state_snapshot holds the serialised state binary captured at checkpoint time.
%% completed_at is set when recovery using this checkpoint finishes.
-record(recovery_checkpoint, {
    checkpoint_id :: uuid(),
    resource_type :: binary(),
    resource_id   :: uuid(),
    state_snapshot :: binary(),
    status        :: recovery_status(),
    created_at    :: timestamp_ms(),
    completed_at  :: timestamp_ms() | undefined
}).
