%% @doc CSV export generation for IronLedger.
%%
%% Provides CSV exports for accounts, transactions, and events.
%% Returns {ok, binary()} containing the full CSV (including header row).
%% All monetary values are in minor units (cents) as stored.
-module(cb_exports).

-include_lib("cb_ledger/include/cb_ledger.hrl").
-include_lib("cb_events/include/cb_events.hrl").

-export([
    export_accounts/0,
    export_transactions/0,
    export_account_transactions/1,
    export_events/0
]).

%% @doc Export all accounts as CSV.
-dialyzer({nowarn_function, export_accounts/0}).
-spec export_accounts() -> {ok, binary()} | {error, atom()}.
export_accounts() ->
    F = fun() ->
        mnesia:select(account, [{#account{_ = '_'}, [], ['$_']}])
    end,
    case mnesia:transaction(F) of
        {atomic, Accounts} ->
            Header = <<"account_id,party_id,name,currency,balance,status,created_at,updated_at\r\n">>,
            Rows = [account_row(A) || A <- Accounts],
            {ok, iolist_to_binary([Header | Rows])};
        {aborted, Reason} ->
            {error, Reason}
    end.

%% @doc Export all transactions in the system as CSV.
-dialyzer({nowarn_function, export_transactions/0}).
-spec export_transactions() -> {ok, binary()} | {error, atom()}.
export_transactions() ->
    F = fun() ->
        mnesia:select(transaction, [{#transaction{_ = '_'}, [], ['$_']}])
    end,
    case mnesia:transaction(F) of
        {atomic, Txns} ->
            Sorted = lists:sort(
                fun(A, B) -> A#transaction.created_at =< B#transaction.created_at end,
                Txns
            ),
            Header = <<"txn_id,idempotency_key,txn_type,status,amount,currency,source_account_id,dest_account_id,description,created_at,posted_at\r\n">>,
            Rows = [txn_row(T) || T <- Sorted],
            {ok, iolist_to_binary([Header | Rows])};
        {aborted, Reason} ->
            {error, Reason}
    end.

%% @doc Export all transactions for a specific account as CSV.
-spec export_account_transactions(binary()) -> {ok, binary()} | {error, atom()}.
export_account_transactions(AccountId) ->
    F = fun() ->
        SourceTxns = mnesia:index_read(transaction, AccountId, source_account_id),
        DestTxns   = mnesia:index_read(transaction, AccountId, dest_account_id),
        All = SourceTxns ++ DestTxns,
        Unique = lists:ukeysort(#transaction.txn_id, All),
        lists:sort(
            fun(A, B) -> A#transaction.created_at =< B#transaction.created_at end,
            Unique
        )
    end,
    case mnesia:transaction(F) of
        {atomic, Txns} ->
            Header = <<"txn_id,idempotency_key,txn_type,status,amount,currency,source_account_id,dest_account_id,description,created_at,posted_at\r\n">>,
            Rows = [txn_row(T) || T <- Txns],
            {ok, iolist_to_binary([Header | Rows])};
        {aborted, Reason} ->
            {error, Reason}
    end.

%% @doc Export all domain events as CSV.
-spec export_events() -> {ok, binary()}.
export_events() ->
    Events = cb_events:list_events(),
    Header = <<"event_id,event_type,status,created_at,updated_at\r\n">>,
    Rows = [event_row(E) || E <- Events],
    {ok, iolist_to_binary([Header | Rows])}.

%% ===================================================================
%% Internal helpers
%% ===================================================================

account_row(A) ->
    Row = [
        A#account.account_id,
        A#account.party_id,
        escape_csv(A#account.name),
        atom_to_binary(A#account.currency, utf8),
        integer_to_binary(A#account.balance),
        atom_to_binary(A#account.status, utf8),
        integer_to_binary(A#account.created_at),
        integer_to_binary(A#account.updated_at)
    ],
    [iolist_to_binary(lists:join(",", Row)), <<"\r\n">>].

txn_row(T) ->
    Row = [
        T#transaction.txn_id,
        escape_csv(T#transaction.idempotency_key),
        atom_to_binary(T#transaction.txn_type, utf8),
        atom_to_binary(T#transaction.status, utf8),
        integer_to_binary(T#transaction.amount),
        atom_to_binary(T#transaction.currency, utf8),
        null_or_bin(T#transaction.source_account_id),
        null_or_bin(T#transaction.dest_account_id),
        escape_csv(T#transaction.description),
        integer_to_binary(T#transaction.created_at),
        null_or_int(T#transaction.posted_at)
    ],
    [iolist_to_binary(lists:join(",", Row)), <<"\r\n">>].

event_row(E) ->
    Row = [
        E#event_outbox.event_id,
        escape_csv(E#event_outbox.event_type),
        atom_to_binary(E#event_outbox.status, utf8),
        integer_to_binary(E#event_outbox.created_at),
        integer_to_binary(E#event_outbox.updated_at)
    ],
    [iolist_to_binary(lists:join(",", Row)), <<"\r\n">>].

%% Wrap value in quotes if it contains a comma, quote, or newline.
escape_csv(V) when is_binary(V) ->
    case binary:match(V, [<<",">>, <<"\"">>, <<"\n">>, <<"\r">>]) of
        nomatch -> V;
        _       ->
            Escaped = binary:replace(V, <<"\"">>, <<"\"\"">>, [global]),
            <<"\"", Escaped/binary, "\"">>
    end.

null_or_bin(undefined) -> <<"">>;
null_or_bin(V) -> V.

null_or_int(undefined) -> <<"">>;
null_or_int(V) -> integer_to_binary(V).
