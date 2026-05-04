%% @doc Cowboy Router Configuration for IronLedger HTTP API
%%
%% This module defines the routing table for the Cowboy HTTP server. Cowboy routing
%% matches incoming HTTP requests to handler modules based on the request path and
%% HTTP method.
%%
%% <h2>How Cowboy Routing Works</h2>
%%
%% Cowboy uses a dispatch list containing host and route specifications. Each route
%% consists of:
%%
%% <ul>
%%   <li>A path pattern (e.g., <<"/api/v1/parties">>)</li>
%%   <li>A handler module (e.g., cb_parties_handler)</li>
%%   <li>Handler-specific state (typically an empty list)</li>
%% </ul>
%%
%% Path patterns can contain binding variables using the colon syntax (e.g.,
%% <<":party_id">>) which capture parts of the URL. These bindings are accessible
%% in the handler via cowboy_req:binding/2.
%%
%% <h2>REST API Structure</h2>
%%
%% The IronLedger API follows RESTful conventions:
%%
%% <ul>
%%   <li><b>GET</b> - Retrieve resources (list or single)</li>
%%   <li><b>POST</b> - Create new resources</li>
%%   <li><b>PUT/PATCH</b> - Update existing resources</li>
%%   <li><b>DELETE</b> - Remove resources</li>
%%   <li><b>OPTIONS</b> - CORS preflight requests</li>
%% </ul>
%%
%% <h2>API Versioning</h2>
%%
%% The API is versioned under the path prefix `/api/v1/`. This allows for future
%% backward-compatible changes while maintaining support for older clients.
%%
%% <h2>Routing Order</h2>
%%
%% Routes are matched in order from top to bottom. The last route uses the
%% wildcard pattern `' _'` to catch all unmatched requests and route them to
%% cb_not_found_handler.
%%
%% @see cowboy_router
%% @see cowboy
-module(cb_router).

-export([dispatch/0]).

%% @doc Compile the Cowboy dispatch rules.
%%
%% This function builds and compiles the dispatch list for Cowboy. It maps all
%% API endpoints to their corresponding handler modules. The dispatch rules are
%% passed to Cowboy when starting the HTTP server.
%%
%% Routes are organized by functional area:
%% <ul>
%%   <li>Health checks - `/health`</li>
%%   <li>Parties - Customer/party management</li>
%%   <li>Accounts - Bank account operations</li>
%%   <li>Transactions - Transfers, deposits, withdrawals</li>
%%   <li>Ledger entries - Journal entries</li>
%%   <li>Products - Savings and loan products</li>
%%   <li>Loans - Loan management</li>
%% </ul>
%%
%% @returns Compiled dispatch rules for Cowboy
-spec dispatch() -> cowboy_router:dispatch_rules().
dispatch() ->
    cowboy_router:compile([
        {'_', [
            %% Health check
            {<<"/health">>, cb_health_handler, []},

            %% Authentication
            {<<"/api/v1/auth/login">>, cb_login_handler, []},
            {<<"/api/v1/auth/logout">>, cb_logout_handler, []},
            {<<"/api/v1/auth/me">>, cb_me_handler, []},

            %% Parties
            {<<"/api/v1/parties">>, cb_parties_handler, []},
            {<<"/api/v1/parties/:party_id">>, cb_party_handler, []},
            {<<"/api/v1/parties/:party_id/suspend">>, cb_party_suspend_handler, []},
            {<<"/api/v1/parties/:party_id/reactivate">>, cb_party_reactivate_handler, []},
            {<<"/api/v1/parties/:party_id/close">>, cb_party_close_handler, []},
            {<<"/api/v1/parties/:party_id/kyc">>, cb_party_kyc_handler, []},

            %% Accounts
            {<<"/api/v1/accounts">>, cb_accounts_list_handler, []},
            {<<"/api/v1/stats">>, cb_stats_handler, []},
            {<<"/api/v1/accounts/:account_id">>, cb_account_handler, []},
            {<<"/api/v1/accounts/:account_id/transactions">>, cb_account_transactions_handler, []},
            {<<"/api/v1/accounts/:account_id/balance">>, cb_account_balance_handler, []},
            {<<"/api/v1/accounts/:account_id/summary">>, cb_account_summary_handler, []},
            {<<"/api/v1/accounts/:account_id/holds">>, cb_account_holds_handler, []},
            {<<"/api/v1/accounts/:account_id/holds/:hold_id">>, cb_account_holds_handler, []},
            {<<"/api/v1/accounts/:account_id/freeze">>, cb_account_freeze_handler, []},
            {<<"/api/v1/accounts/:account_id/unfreeze">>, cb_account_unfreeze_handler, []},
            {<<"/api/v1/accounts/:account_id/close">>, cb_account_close_handler, []},
            {<<"/api/v1/parties/:party_id/accounts">>, cb_party_accounts_handler, []},

            %% Transactions
            {<<"/api/v1/transactions">>, cb_transactions_search_handler, []},
            {<<"/api/v1/transactions/transfer">>, cb_transaction_transfer_handler, []},
            {<<"/api/v1/transactions/deposit">>, cb_transaction_deposit_handler, []},
            {<<"/api/v1/transactions/withdraw">>, cb_transaction_withdraw_handler, []},
            {<<"/api/v1/transactions/adjustment">>, cb_transaction_adjustment_handler, []},
            {<<"/api/v1/transactions/:txn_id">>, cb_transaction_handler, []},
            {<<"/api/v1/transactions/:txn_id/reverse">>, cb_transaction_reverse_handler, []},
            {<<"/api/v1/transactions/:txn_id/receipt">>, cb_transaction_receipt_handler, []},
            {<<"/api/v1/transactions/:txn_id/tags">>, cb_transaction_tags_handler, []},

            %% Ledger entries
            {<<"/api/v1/ledger/entries/latest">>, cb_ledger_latest_handler, []},
            {<<"/api/v1/ledger/trial-balance">>, cb_ledger_trial_balance_handler, []},
            {<<"/api/v1/ledger/general-ledger">>, cb_ledger_gl_handler, []},
            {<<"/api/v1/ledger/chart-of-accounts">>, cb_chart_accounts_handler, []},
            {<<"/api/v1/ledger/chart-of-accounts/:code">>, cb_chart_accounts_handler, []},
            {<<"/api/v1/transactions/:txn_id/entries">>, cb_transaction_entries_handler, []},
            {<<"/api/v1/accounts/:account_id/entries">>, cb_account_entries_handler, []},
            {<<"/api/v1/accounts/:account_id/snapshots">>, cb_account_snapshots_handler, []},

            %% Savings products
            {<<"/api/v1/savings-products">>, cb_savings_products_handler, []},
            {<<"/api/v1/savings-products/:product_id">>, cb_savings_products_handler, []},
            {<<"/api/v1/savings-products/:product_id/activate">>, cb_savings_products_handler, []},
            {<<"/api/v1/savings-products/:product_id/deactivate">>, cb_savings_products_handler, []},
            {<<"/api/v1/savings-products/:product_id/launch">>, cb_savings_products_handler, []},
            {<<"/api/v1/savings-products/:product_id/sunset">>, cb_savings_products_handler, []},

            %% Loan products
            {<<"/api/v1/loan-products">>, cb_loan_products_handler, []},
            {<<"/api/v1/loan-products/:product_id">>, cb_loan_products_handler, []},
            {<<"/api/v1/loan-products/:product_id/activate">>, cb_loan_products_handler, []},
            {<<"/api/v1/loan-products/:product_id/deactivate">>, cb_loan_products_handler, []},
            {<<"/api/v1/loan-products/:product_id/launch">>, cb_loan_products_handler, []},
            {<<"/api/v1/loan-products/:product_id/sunset">>, cb_loan_products_handler, []},
            {<<"/api/v1/loan-products/:product_id/set-eligibility">>, cb_loan_products_handler, []},
            {<<"/api/v1/loan-products/:product_id/set-fees">>, cb_loan_products_handler, []},

            %% Loans and repayments
            {<<"/api/v1/loans">>, cb_loans_handler, []},
            {<<"/api/v1/loans/:loan_id">>, cb_loans_handler, []},
            {<<"/api/v1/loans/:loan_id/approve">>, cb_loans_handler, []},
            {<<"/api/v1/loans/:loan_id/disburse">>, cb_loans_handler, []},
            {<<"/api/v1/loans/:loan_id/repayments">>, cb_loan_repayments_handler, []},

            %% Domain events
            {<<"/api/v1/events">>, cb_events_handler, []},
            {<<"/api/v1/events/:event_id">>, cb_events_handler, []},
            {<<"/api/v1/events/:event_id/replay">>, cb_events_handler, []},

            %% Webhook subscriptions
            {<<"/api/v1/webhooks">>, cb_webhooks_handler, []},
            {<<"/api/v1/webhooks/:subscription_id">>, cb_webhooks_handler, []},
            {<<"/api/v1/webhooks/:subscription_id/deliveries">>, cb_webhook_deliveries_handler, []},

            %% Statements and CSV exports
            {<<"/api/v1/accounts/:account_id/statement">>, cb_statements_handler, []},
            {<<"/api/v1/export/:resource">>, cb_exports_handler, []},

            %% Development tools
            {<<"/api/v1/dev/mock-import">>, cb_dev_mock_import_handler, []},

            %% API specification
            {<<"/api/v1/openapi.json">>, cb_openapi_handler, []},

            %% OAuth 2.0 token endpoint
            {<<"/api/v1/oauth/token">>, cb_oauth_handler, []},

            %% VM metrics
            {<<"/metrics">>, cb_metrics_handler, []},

            %% Payment orders
            {<<"/api/v1/payment-orders">>, cb_payment_orders_handler, []},
            {<<"/api/v1/payment-orders/:payment_id">>, cb_payment_orders_handler, []},
            {<<"/api/v1/payment-orders/:payment_id/cancel">>, cb_payment_orders_handler, []},
            {<<"/api/v1/payment-orders/:payment_id/retry">>, cb_payment_orders_handler, []},

            %% Exception queue
            {<<"/api/v1/exceptions">>, cb_exceptions_handler, []},
            {<<"/api/v1/exceptions/:item_id">>, cb_exceptions_handler, []},
            {<<"/api/v1/exceptions/:item_id/resolve">>, cb_exceptions_handler, []},

            %% Omnichannel — channel limits
            {<<"/api/v1/channel-limits">>, cb_channel_limits_handler, []},
            {<<"/api/v1/channel-limits/:channel">>, cb_channel_limits_handler, []},

            %% Omnichannel — channel activity log
            {<<"/api/v1/channel-activity">>, cb_channel_activity_handler, []},

            %% Omnichannel — unified party profile
            {<<"/api/v1/parties/:party_id/profile">>, cb_party_profile_handler, []},

            %% Omnichannel — notification preferences
            {<<"/api/v1/parties/:party_id/notification-preferences">>, cb_notification_prefs_handler, []},

            %% Omnichannel — channel context (TASK-042)
            {<<"/api/v1/parties/:party_id/channel-context/:channel">>, cb_channel_context_handler, []},

            %% Omnichannel — channel sessions (TASK-043)
            %% Note: literal 'invalidate-all' route MUST precede the :session_id wildcard
            {<<"/api/v1/parties/:party_id/channel-sessions">>, cb_channel_sessions_handler, []},
            {<<"/api/v1/parties/:party_id/channel-sessions/invalidate-all">>, cb_channel_sessions_invalidate_handler, []},
            {<<"/api/v1/parties/:party_id/channel-sessions/:session_id">>, cb_channel_sessions_handler, []},

            %% Omnichannel — channel feature flags (TASK-044)
            {<<"/api/v1/channel-features/:channel">>, cb_channel_features_handler, []},
            {<<"/api/v1/channel-features/:channel/:feature">>, cb_channel_features_handler, []},

            %% Omnichannel — notification dispatch (TASK-045)
            {<<"/api/v1/parties/:party_id/notifications/dispatch">>, cb_notification_dispatch_handler, []},

            %% Partner API keys
            {<<"/api/v1/api-keys">>, cb_api_keys_handler, []},
            {<<"/api/v1/api-keys/:key_id">>, cb_api_keys_handler, []},
            {<<"/api/v1/api-keys/:key_id/usage">>, cb_api_usage_handler, []},

            %% API deprecation notices
            {<<"/api/v1/deprecations">>, cb_deprecation_handler, []},

            %% GraphQL gateway
            {<<"/api/graphql">>, cb_graphql_handler, []},

            %% ATM baseline interface
            {<<"/api/v1/atm/inquiry">>, cb_atm_handler, []},
            {<<"/api/v1/atm/withdraw">>, cb_atm_handler, []},

            %% KYC workflow management (P2-S1)
            {<<"/api/v1/kyc/workflows">>, cb_kyc_workflows_handler, []},
            {<<"/api/v1/kyc/workflows/:workflow_id">>, cb_kyc_workflow_handler, []},
            {<<"/api/v1/kyc/workflows/:workflow_id/start">>, cb_kyc_workflow_start_handler, []},
            {<<"/api/v1/kyc/workflows/:workflow_id/advance">>, cb_kyc_workflow_advance_handler, []},
            {<<"/api/v1/kyc/workflows/:workflow_id/steps">>, cb_kyc_workflow_steps_handler, []},

            %% Identity verification (P2-S1)
            {<<"/api/v1/parties/:party_id/identity-checks">>, cb_party_idv_handler, []},
            {<<"/api/v1/identity-checks/:check_id">>, cb_idv_check_handler, []},
            {<<"/api/v1/identity-checks/:check_id/retry">>, cb_idv_retry_handler, []},

            %% AML rules (P2-S1)
            {<<"/api/v1/aml/rules">>, cb_aml_rules_handler, []},
            {<<"/api/v1/aml/rules/:rule_id">>, cb_aml_rule_handler, []},

            %% Suspicious activity queue (P2-S1)
            {<<"/api/v1/aml/suspicious-activity">>, cb_suspicious_activity_handler, []},
            {<<"/api/v1/aml/suspicious-activity/:alert_id">>, cb_suspicious_activity_item_handler, []},

            %% AML compliance cases (P2-S1)
            {<<"/api/v1/aml/cases">>, cb_aml_cases_handler, []},
            {<<"/api/v1/aml/cases/:case_id">>, cb_aml_case_handler, []},

            %% SAR reports (P2-S1)
            {<<"/api/v1/compliance/sars">>, cb_sar_reports_handler, []},
            {<<"/api/v1/compliance/sars/:sar_id">>, cb_sar_report_handler, []},

            %% STP routing rules (P3-S1)
            {<<"/api/v1/stp/rules">>, cb_stp_rules_handler, []},
            {<<"/api/v1/stp/rules/:rule_id">>, cb_stp_rules_handler, []},

            %% STP metrics dashboard (P3-S1)
            {<<"/api/v1/stp/metrics">>, cb_stp_metrics_handler, []},

            %% Exception SLA and escalation (P3-S1)
            {<<"/api/v1/stp/exceptions/overdue">>, cb_stp_exceptions_handler, []},
            {<<"/api/v1/stp/exceptions/:item_id/:action">>, cb_stp_exceptions_handler, []},

            %% Marketplace: connector registry (P3-S2)
            {<<"/api/v1/marketplace/connectors">>, cb_connectors_handler, []},
            {<<"/api/v1/marketplace/connectors/:connector_id">>, cb_connectors_handler, []},
            {<<"/api/v1/marketplace/connectors/:connector_id/:action">>, cb_connectors_handler, []},

            %% Marketplace: connector versioning (P3-S2)
            {<<"/api/v1/marketplace/connectors/:connector_id/versions">>, cb_connector_versions_handler, []},
            {<<"/api/v1/marketplace/connectors/:connector_id/versions/:version_id">>, cb_connector_versions_handler, []},
            {<<"/api/v1/marketplace/connectors/:connector_id/versions/:version_id/:action">>, cb_connector_versions_handler, []},

            %% Marketplace: partner onboarding (P3-S2)
            {<<"/api/v1/marketplace/partners">>, cb_partner_onboarding_handler, []},
            {<<"/api/v1/marketplace/partners/:application_id">>, cb_partner_onboarding_handler, []},
            {<<"/api/v1/marketplace/partners/:application_id/:action">>, cb_partner_onboarding_handler, []},

            %% Event schema registry (P3-S3)
            {<<"/api/v1/events/schemas">>, cb_event_schema_handler, []},
            {<<"/api/v1/events/schemas/:event_type">>, cb_event_schema_handler, []},
            {<<"/api/v1/events/schemas/:event_type/:version">>, cb_event_schema_handler, []},

            %% Streaming consumers (P3-S3)
            {<<"/api/v1/streams/consumers">>, cb_streaming_handler, []},
            {<<"/api/v1/streams/backfill">>, cb_streaming_handler, []},
            {<<"/api/v1/streams/consumers/:consumer_id/:action">>, cb_streaming_handler, []},

            %% SWIFT / ISO 20022 pipeline (P3-S3)
            {<<"/api/v1/payments/swift">>, cb_swift_handler, []},
            {<<"/api/v1/payments/swift/status/:action">>, cb_swift_handler, []},
            {<<"/api/v1/payments/swift/:message_id">>, cb_swift_handler, []},
            {<<"/api/v1/payments/swift/:message_id/:action">>, cb_swift_handler, []},

            %% Settlement and reconciliation (P3-S3)
            {<<"/api/v1/settlements">>, cb_settlement_handler, []},
            {<<"/api/v1/settlements/:run_id">>, cb_settlement_handler, []},
            {<<"/api/v1/settlements/:run_id/:action">>, cb_settlement_handler, []},

            %% Treasury liquidity and cash management (P4-S1, TASK-062)
            {<<"/api/v1/treasury/positions">>, cb_treasury_handler, []},
            {<<"/api/v1/treasury/positions/:id">>, cb_treasury_handler, []},
            {<<"/api/v1/treasury/positions/:id/:action">>, cb_treasury_handler, []},
            {<<"/api/v1/treasury/forecasts">>, cb_treasury_handler, []},
            {<<"/api/v1/treasury/placements">>, cb_treasury_handler, []},
            {<<"/api/v1/treasury/placements/:id">>, cb_treasury_handler, []},

            %% Trade finance instruments (P4-S1, TASK-063)
            {<<"/api/v1/trade/instruments">>, cb_trade_finance_handler, []},
            {<<"/api/v1/trade/instruments/:id">>, cb_trade_finance_handler, []},
            {<<"/api/v1/trade/instruments/:id/:action">>, cb_trade_finance_handler, []},
            {<<"/api/v1/trade/documents/:id/:action">>, cb_trade_finance_handler, []},

            %% Risk metrics and capital buffers (P4-S1, TASK-064)
            {<<"/api/v1/risk/metrics">>, cb_risk_capital_handler, []},
            {<<"/api/v1/risk/metrics/:id">>, cb_risk_capital_handler, []},
            {<<"/api/v1/risk/breaches">>, cb_risk_capital_handler, []},
            {<<"/api/v1/risk/check">>, cb_risk_capital_handler, []},
            {<<"/api/v1/capital/buffers">>, cb_risk_capital_handler, []},
            {<<"/api/v1/capital/buffers/:id">>, cb_risk_capital_handler, []},

            %% Federated cross-module reporting (P4-S1, TASK-065)
            {<<"/api/v1/reports/federation">>, cb_federation_report_handler, []},
            {<<"/api/v1/reports/federation/:id">>, cb_federation_report_handler, []},
            {<<"/api/v1/reports/federation/:id/:action">>, cb_federation_report_handler, []},
            %% Cluster management (P4-S2 TASK-066)
            {<<"/api/v1/cluster/nodes">>, cb_cluster_handler, []},
            {<<"/api/v1/cluster/nodes/active">>, cb_cluster_handler, []},
            {<<"/api/v1/cluster/nodes/:node_id">>, cb_cluster_handler, []},
            {<<"/api/v1/cluster/nodes/:node_id/:action">>, cb_cluster_handler, []},

            %% Scaling rules and metrics (P4-S2 TASK-068)
            {<<"/api/v1/scaling/rules">>, cb_scaling_handler, []},
            {<<"/api/v1/scaling/metrics">>, cb_scaling_handler, []},
            {<<"/api/v1/scaling/evaluate">>, cb_scaling_handler, []},
            {<<"/api/v1/scaling/rules/:rule_id">>, cb_scaling_handler, []},
            {<<"/api/v1/scaling/rules/:rule_id/:action">>, cb_scaling_handler, []},

            %% Recovery checkpoints (P4-S2 TASK-069)
            {<<"/api/v1/recovery/checkpoints">>, cb_recovery_handler, []},
            {<<"/api/v1/recovery/checkpoints/:checkpoint_id">>, cb_recovery_handler, []},
            {<<"/api/v1/recovery/checkpoints/:checkpoint_id/:action">>, cb_recovery_handler, []},
            {<<"/api/v1/recovery/:resource_type/:resource_id/:action">>, cb_recovery_handler, []},

            %% 404 fallback
            {'_', cb_not_found_handler, []}
        ]}
    ]).
