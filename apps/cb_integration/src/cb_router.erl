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

            %% Accounts
            {<<"/api/v1/accounts">>, cb_accounts_list_handler, []},
            {<<"/api/v1/stats">>, cb_stats_handler, []},
            {<<"/api/v1/accounts/:account_id">>, cb_account_handler, []},
            {<<"/api/v1/accounts/:account_id/transactions">>, cb_account_transactions_handler, []},
            {<<"/api/v1/accounts/:account_id/balance">>, cb_account_balance_handler, []},
            {<<"/api/v1/accounts/:account_id/holds">>, cb_account_holds_handler, []},
            {<<"/api/v1/accounts/:account_id/holds/:hold_id">>, cb_account_holds_handler, []},
            {<<"/api/v1/accounts/:account_id/freeze">>, cb_account_freeze_handler, []},
            {<<"/api/v1/accounts/:account_id/unfreeze">>, cb_account_unfreeze_handler, []},
            {<<"/api/v1/accounts/:account_id/close">>, cb_account_close_handler, []},
            {<<"/api/v1/parties/:party_id/accounts">>, cb_party_accounts_handler, []},

            %% Transactions
            {<<"/api/v1/transactions/transfer">>, cb_transaction_transfer_handler, []},
            {<<"/api/v1/transactions/deposit">>, cb_transaction_deposit_handler, []},
            {<<"/api/v1/transactions/withdraw">>, cb_transaction_withdraw_handler, []},
            {<<"/api/v1/transactions/adjustment">>, cb_transaction_adjustment_handler, []},
            {<<"/api/v1/transactions/:txn_id">>, cb_transaction_handler, []},
            {<<"/api/v1/transactions/:txn_id/reverse">>, cb_transaction_reverse_handler, []},

            %% Ledger entries
            {<<"/api/v1/transactions/:txn_id/entries">>, cb_transaction_entries_handler, []},
            {<<"/api/v1/accounts/:account_id/entries">>, cb_account_entries_handler, []},

            %% Savings products
            {<<"/api/v1/savings-products">>, cb_savings_products_handler, []},
            {<<"/api/v1/savings-products/:product_id">>, cb_savings_products_handler, []},
            {<<"/api/v1/savings-products/:product_id/activate">>, cb_savings_products_handler, []},
            {<<"/api/v1/savings-products/:product_id/deactivate">>, cb_savings_products_handler, []},

            %% Loan products
            {<<"/api/v1/loan-products">>, cb_loan_products_handler, []},
            {<<"/api/v1/loan-products/:product_id">>, cb_loan_products_handler, []},
            {<<"/api/v1/loan-products/:product_id/activate">>, cb_loan_products_handler, []},
            {<<"/api/v1/loan-products/:product_id/deactivate">>, cb_loan_products_handler, []},

            %% Loans and repayments
            {<<"/api/v1/loans">>, cb_loans_handler, []},
            {<<"/api/v1/loans/:loan_id">>, cb_loans_handler, []},
            {<<"/api/v1/loans/:loan_id/approve">>, cb_loans_handler, []},
            {<<"/api/v1/loans/:loan_id/disburse">>, cb_loans_handler, []},
            {<<"/api/v1/loans/:loan_id/repayments">>, cb_loan_repayments_handler, []},

            %% 404 fallback
            {'_', cb_not_found_handler, []}
        ]}
    ]).
