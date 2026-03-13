-module(cb_router).

-export([dispatch/0]).

%% @doc Create Cowboy dispatch rules.
-spec dispatch() -> cowboy_router:dispatch_rules().
dispatch() ->
    cowboy_router:compile([
        {'_', [
            %% Health check
            {<<"/health">>, cb_health_handler, []},

            %% Parties
            {<<"/api/v1/parties">>, cb_parties_handler, []},
            {<<"/api/v1/parties/:party_id">>, cb_party_handler, []},
            {<<"/api/v1/parties/:party_id/suspend">>, cb_party_suspend_handler, []},
            {<<"/api/v1/parties/:party_id/close">>, cb_party_close_handler, []},

            %% Accounts
            {<<"/api/v1/accounts">>, cb_accounts_handler, []},
            {<<"/api/v1/accounts/:account_id">>, cb_account_handler, []},
            {<<"/api/v1/accounts/:account_id/balance">>, cb_account_balance_handler, []},
            {<<"/api/v1/accounts/:account_id/freeze">>, cb_account_freeze_handler, []},
            {<<"/api/v1/accounts/:account_id/unfreeze">>, cb_account_unfreeze_handler, []},
            {<<"/api/v1/accounts/:account_id/close">>, cb_account_close_handler, []},
            {<<"/api/v1/parties/:party_id/accounts">>, cb_party_accounts_handler, []},

            %% Transactions
            {<<"/api/v1/transactions/transfer">>, cb_transaction_transfer_handler, []},
            {<<"/api/v1/transactions/deposit">>, cb_transaction_deposit_handler, []},
            {<<"/api/v1/transactions/withdraw">>, cb_transaction_withdraw_handler, []},
            {<<"/api/v1/transactions/:txn_id">>, cb_transaction_handler, []},
            {<<"/api/v1/transactions/:txn_id/reverse">>, cb_transaction_reverse_handler, []},

            %% Ledger entries
            {<<"/api/v1/transactions/:txn_id/entries">>, cb_transaction_entries_handler, []},
            {<<"/api/v1/accounts/:account_id/entries">>, cb_account_entries_handler, []},

            %% 404 fallback
            {'_', cb_not_found_handler, []}
        ]}
    ]).
