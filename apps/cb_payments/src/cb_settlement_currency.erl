%% @doc Settlement Currency Module
%%
%% Handles assignment and retrieval of settlement currency for transactions.
%% Settlement currency defines the currency in which a transaction is ultimately
%% settled, which may differ from the transaction's primary currency in
%% multi-currency scenarios.
%%
-module(cb_settlement_currency).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([
    assign_settlement_currency/2,
    get_settlement_currency/1
]).

-type result() :: {ok, #transaction{}} | {error, atom()}.

%% @doc Assign (or update) the settlement currency for a transaction.
%%
%% The settlement currency must be a valid currency that the transaction
%% can be settled in. If the transaction already has a settlement currency
%% set, this will update it.
%%
%% Only transactions in `pending' or `posted' status can have their
%% settlement currency modified. Completed or reversed transactions
%% cannot be modified.
%%
-spec assign_settlement_currency(TxnId :: uuid(), SettlementCurrency :: currency()) -> result().
assign_settlement_currency(TxnId, SettlementCurrency) when is_binary(TxnId) ->
    F = fun() ->
        case mnesia:read({transaction, TxnId}) of
            [#transaction{} = Txn] when Txn#transaction.status =:= pending;
                                        Txn#transaction.status =:= posted ->
                UpdatedTxn = Txn#transaction{
                    settlement_currency = SettlementCurrency
                },
                mnesia:write(UpdatedTxn),
                {ok, UpdatedTxn};
            [#transaction{status = completed}] ->
                {error, transaction_completed};
            [#transaction{status = reversed}] ->
                {error, transaction_reversed};
            [#transaction{status = failed}] ->
                {error, transaction_failed};
            [] ->
                {error, transaction_not_found}
        end
    end,
    mnesia:transaction(F).

%% @doc Get the settlement currency for a transaction.
%%
%% Returns `{ok, SettlementCurrency}' if set, or `{ok, undefined}' if
%% no settlement currency has been assigned.
%%
-spec get_settlement_currency(TxnId :: uuid()) -> {ok, currency() | undefined} | {error, atom()}.
get_settlement_currency(TxnId) when is_binary(TxnId) ->
    F = fun() ->
        case mnesia:read({transaction, TxnId}) of
            [#transaction{} = Txn] ->
                {ok, Txn#transaction.settlement_currency};
            [] ->
                {error, transaction_not_found}
        end
    end,
    mnesia:transaction(F).