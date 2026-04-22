%% @doc Mnesia Database Schema Management
%%
%% This module is responsible for creating and managing the Mnesia database schema
%% and tables for the IronLedger core banking system.
%%
%% <h2>What is Mnesia?</h2>
%%
%% Mnesia is a distributed, soft real-time database management system (DBMS) bundled
%% with Erlang/OTP. It provides:
%%
%% <ul>
%%   <li>ACID transactions (atomic, consistent, isolated, durable)</li>
%%   <li>Schema flexibility - can be modified at runtime</li>
%%   <li>Replication - tables can be replicated across nodes</li>
%%   <li>In-memory and disk storage options</li>
%% </ul>
%%
%% <h2>Table Configuration</h2>
%%
%% All tables in IronLedger use `ram_copies' (in-memory only) for the prototype.
%% This provides fast read/write performance but data is lost on node restart.
%% For production, consider:
%%
%% <ul>
%%   <li>`disc_copies' - Persist to disk, survive node restarts</li>
%%   <li>`disc_only_copies' - Disk-only for large datasets</li>
%%   <li>Table replication across multiple nodes for HA</li>
%% </ul>
%%
%% <h2>Table Indexes</h2>
%%
%% Each table has secondary indexes defined to speed up common query patterns:
%% <ul>
%%   <li>party: email, status</li>
%%   <li>account: party_id, status</li>
%%   <li>transaction: idempotency_key, source_account_id, dest_account_id, status</li>
%%   <li>ledger_entry: txn_id, account_id</li>
%% </ul>
%%
%% @see mnesia
-module(cb_schema).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([create_tables/0]).

%% @doc Create all Mnesia tables if they don't exist.
%%
%% This function creates the following tables:
%% <ul>
%%   <li>`party' - Customer/party records</li>
%%   <li>`account' - Bank accounts</li>
%%   <li>`transaction' - Financial transactions</li>
%%   <li>`ledger_entry' - Double-entry ledger entries</li>
%%   <li>`savings_product' - Savings product definitions</li>
%%   <li>`loan_products' - Loan product definitions</li>
%%   <li>`loan_accounts' - Loan accounts</li>
%%   <li>`loan_repayments' - Loan repayment records</li>
%%   <li>`interest_accrual' - Interest accrual tracking</li>
%%   <li>`auth_user' - Authentication users and roles</li>
%%   <li>`auth_session' - Dashboard and API sessions</li>
%%   <li>`audit_log' - Authentication and operational audit entries</li>
%%   <li>`approval_request' - Maker-checker approval requests</li>
%%   <li>`approval_decision' - Approval decisions and comments</li>
%%   <li>`event_outbox' - Domain events pending delivery</li>
%%   <li>`webhook_subscription' - Webhook destinations</li>
%%   <li>`webhook_delivery' - Webhook attempt history</li>
%%   <li>`report_statement' - Generated statement metadata</li>
%%   <li>`report_export' - Generated export metadata</li>
%% </ul>
%%
%% Each table is created with the specification defined in table_spec/1.
%% If a table already exists, the function returns successfully (idempotent).
%%
%% @returns `ok' on success (always succeeds if Mnesia is running)
-spec create_tables() -> ok.
create_tables() ->
    Tables = [party, party_audit, account, transaction, ledger_entry,
              chart_account, balance_snapshot, account_hold,
              currency_config, exchange_rate, payment_order, exception_item,
              channel_limit, channel_activity, notification_preference,
              api_keys,
              savings_product,
              loan_products, loan_accounts, loan_repayments, interest_accrual,
              auth_user, auth_session, audit_log, approval_request,
              approval_decision, event_outbox, webhook_subscription,
              webhook_delivery, report_statement, report_export],
    lists:foreach(fun create_if_not_exists/1, Tables),
    ok.

%% @private Create a single table if it doesn't exist.
%%
%% Attempts to create a table with the specified name and attributes.
%% If the table already exists, this is treated as a successful operation.
%% Any other error is propagated as a runtime error.
%%
%% @param TableName The name of the table to create
%% @returns `ok' on success
-spec create_if_not_exists(
    party | party_audit | account | transaction | ledger_entry |
    chart_account | balance_snapshot | account_hold |
    currency_config | exchange_rate | payment_order | exception_item |
    channel_limit | channel_activity | notification_preference |
    api_keys |
    savings_product | loan_products | loan_accounts | loan_repayments |
    interest_accrual | auth_user | auth_session | audit_log |
    approval_request | approval_decision | event_outbox |
    webhook_subscription | webhook_delivery | report_statement |
    report_export
) -> ok.
create_if_not_exists(TableName) ->
    case mnesia:create_table(TableName, table_spec(TableName)) of
        {atomic, ok} ->
            ok;
        {aborted, {already_exists, _Table}} ->
            ok;
        {aborted, Reason} ->
            error({schema_error, TableName, Reason})
    end.

%% @private Table specifications from docs/data-schema.md.
%%
%% Returns the Mnesia table specification for each table type, including:
%% <ul>
%%   <li>Storage type (ram_copies)</li>
%%   <li>Record attributes (from record_info)</li>
%%   <li>Secondary indexes for common query patterns</li>
%% </ul>
%%
%% @param TableName The table to get spec for
%% @returns Mnesia table specification proplist
-spec table_spec(
    party | party_audit | account | transaction | ledger_entry |
    chart_account | balance_snapshot | account_hold |
    currency_config | exchange_rate | payment_order | exception_item |
    channel_limit | channel_activity | notification_preference |
    api_keys |
    savings_product | loan_products | loan_accounts | loan_repayments |
    interest_accrual | auth_user | auth_session | audit_log |
    approval_request | approval_decision | event_outbox |
    webhook_subscription | webhook_delivery | report_statement |
    report_export
) ->
    [{'attributes', [atom(), ...]} |
     {'index', ['account_id' | 'currency' | 'dest_account_id' | 'email' |
                'entity_type' | 'event_type' | 'expires_at' | 'export_type' |
                'generated_at' | 'idempotency_key' | 'loan_id' | 'name' |
                'party_id' | 'request_id' | 'resource_id' | 'resource_type' |
                'role' | 'source_account_id' | 'status' | 'subscription_id' |
                'txn_id' | 'user_id' | 'actor_user_id' | 'approved_by' |
                'action' | 'version' | 'account_type' | 'parent_code' |
                'snapshot_at' | 'attempt_status' |
                'is_active' | 'from_currency' | 'to_currency' | 'recorded_at' |
                'payment_id', ...]} |
     {'record_name', 'loan_account' | 'loan_product' | 'loan_repayment'} |
     {'ram_copies', [atom(), ...]}, ...].
table_spec(party) ->
    [
        {ram_copies, [node()]},
        {attributes, record_info(fields, party)},
        {index, [email, status, kyc_status]}
    ];
table_spec(party_audit) ->
    [
        {ram_copies, [node()]},
        {attributes, record_info(fields, party_audit)},
        {index, [party_id, action, version]}
    ];
table_spec(account) ->
    [
        {ram_copies, [node()]},
        {attributes, record_info(fields, account)},
        {index, [party_id, status]}
    ];
table_spec(transaction) ->
    [
        {ram_copies, [node()]},
        {attributes, record_info(fields, transaction)},
        {index, [idempotency_key, source_account_id, dest_account_id, status]}
    ];
table_spec(ledger_entry) ->
    [
        {ram_copies, [node()]},
        {attributes, record_info(fields, ledger_entry)},
        {index, [txn_id, account_id, currency]}
    ];
table_spec(chart_account) ->
    [
        {ram_copies, [node()]},
        {attributes, record_info(fields, chart_account)},
        {index, [account_type, parent_code, status]}
    ];
table_spec(balance_snapshot) ->
    [
        {ram_copies, [node()]},
        {attributes, record_info(fields, balance_snapshot)},
        {index, [account_id, snapshot_at]}
    ];
table_spec(account_hold) ->
    [
        {ram_copies, [node()]},
        {attributes, record_info(fields, account_hold)},
        {index, [account_id, status]}
    ];
table_spec(currency_config) ->
    [
        {ram_copies, [node()]},
        {attributes, record_info(fields, currency_config)},
        {index, [is_active]}
    ];
table_spec(exchange_rate) ->
    [
        {ram_copies, [node()]},
        {attributes, record_info(fields, exchange_rate)},
        {index, [from_currency, to_currency, recorded_at]}
    ];
table_spec(payment_order) ->
    [
        {ram_copies, [node()]},
        {attributes, record_info(fields, payment_order)},
        {index, [idempotency_key, party_id, source_account_id, status]}
    ];
table_spec(exception_item) ->
    [
        {ram_copies, [node()]},
        {attributes, record_info(fields, exception_item)},
        {index, [payment_id, status]}
    ];
table_spec(channel_limit) ->
    [
        {ram_copies, [node()]},
        {attributes, record_info(fields, channel_limit)}
    ];
table_spec(channel_activity) ->
    [
        {ram_copies, [node()]},
        {attributes, record_info(fields, channel_activity)},
        {index, [channel, party_id, created_at]}
    ];
table_spec(notification_preference) ->
    [
        {ram_copies, [node()]},
        {attributes, record_info(fields, notification_preference)},
        {index, [party_id, channel]}
    ];
table_spec(api_keys) ->
    [
        {ram_copies, [node()]},
        {record_name, api_key},
        {attributes, record_info(fields, api_key)},
        {index, [key_hash, partner_id, status]}
    ];
table_spec(savings_product) ->
    [
        {ram_copies, [node()]},
        {attributes, [product_id, name, description, currency, interest_rate,
                      interest_type, compounding_period, minimum_balance,
                      status, created_at, updated_at]},
        {index, [status, name]}
    ];
table_spec(loan_products) ->
    [
        {ram_copies, [node()]},
        {record_name, loan_product},
        {attributes, [product_id, name, description, currency, min_amount,
                      max_amount, min_term_months, max_term_months,
                      interest_rate, interest_type, status, created_at,
                      updated_at]},
        {index, [status, currency]}
    ];
table_spec(loan_accounts) ->
    [
        {ram_copies, [node()]},
        {record_name, loan_account},
        {attributes, [loan_id, product_id, party_id, account_id, principal,
                      currency, interest_rate, term_months, monthly_payment,
                      outstanding_balance, status, disbursed_at, created_at,
                      updated_at]},
        {index, [party_id, account_id, status]}
    ];
table_spec(loan_repayments) ->
    [
        {ram_copies, [node()]},
        {record_name, loan_repayment},
        {attributes, [repayment_id, loan_id, amount, principal_portion,
                      interest_portion, penalty, due_date, paid_at, status,
                      created_at]},
        {index, [loan_id, status]}
    ];
table_spec(interest_accrual) ->
    [
        {ram_copies, [node()]},
        {attributes, [accrual_id, account_id, product_id, interest_rate,
                      daily_rate, start_date, end_date, balance,
                      accrued_amount, status, created_at]},
        {index, [account_id, status]}
    ];
table_spec(auth_user) ->
    [
        {ram_copies, [node()]},
        {attributes, [user_id, email, password_hash, role, status,
                      created_at, updated_at]},
        {index, [email, role, status]}
    ];
table_spec(auth_session) ->
    [
        {ram_copies, [node()]},
        {attributes, [session_id, user_id, status, expires_at,
                      created_at, updated_at, channel_type]},
        {index, [user_id, expires_at]}
    ];
table_spec(audit_log) ->
    [
        {ram_copies, [node()]},
        {attributes, [audit_id, actor_user_id, action, entity_type, entity_id,
                      metadata, created_at]},
        {index, [actor_user_id, entity_type]}
    ];
table_spec(approval_request) ->
    [
        {ram_copies, [node()]},
        {attributes, [request_id, resource_type, resource_id, action,
                      requested_by, status, payload, created_at, updated_at]},
        {index, [resource_type, resource_id, status]}
    ];
table_spec(approval_decision) ->
    [
        {ram_copies, [node()]},
        {attributes, [decision_id, request_id, approved_by, decision,
                      comment, created_at]},
        {index, [request_id, approved_by]}
    ];
table_spec(event_outbox) ->
    [
        {ram_copies, [node()]},
        {attributes, [event_id, event_type, payload, status, created_at,
                      updated_at]},
        {index, [event_type, status]}
    ];
table_spec(webhook_subscription) ->
    [
        {ram_copies, [node()]},
        {attributes, [subscription_id, event_type, callback_url, status,
                      created_at, updated_at]},
        {index, [event_type, status]}
    ];
table_spec(webhook_delivery) ->
    [
        {ram_copies, [node()]},
        {attributes, [delivery_id, subscription_id, event_id, attempt_status,
                      response_code, created_at, updated_at]},
        {index, [subscription_id, attempt_status]}
    ];
table_spec(report_statement) ->
    [
        {ram_copies, [node()]},
        {attributes, [statement_id, account_id, period_start, period_end,
                      generated_at, status]},
        {index, [account_id, generated_at]}
    ];
table_spec(report_export) ->
    [
        {ram_copies, [node()]},
        {attributes, [export_id, export_type, parameters, status,
                      generated_at, created_at]},
        {index, [export_type, status]}
    ].
