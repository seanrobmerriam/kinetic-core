%% @doc Account statement generation for IronLedger.
%%
%% Produces a chronological statement of ledger entries for an account,
%% with a running balance column computed from the oldest entry forward.
%% Supports optional date range filtering (from/to timestamps in ms).
-module(cb_statements).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([generate/2]).

%% @doc Generate a statement for an account.
%%
%% Options (all optional):
%%   from        => Timestamp ms — include only entries posted >= from
%%   to          => Timestamp ms — include only entries posted <= to
%%   page        => Page number (default 1)
%%   page_size   => Items per page (default 50, max 200)
%%
%% Returns:
%%   {ok, #{account_id, currency, entries, total, page, page_size,
%%          opening_balance, closing_balance}}
%%   {error, account_not_found | Reason}
-spec generate(binary(), map()) ->
    {ok, map()} | {error, atom()}.
generate(AccountId, Opts) ->
    Page     = maps:get(page, Opts, 1),
    PageSize = min(maps:get(page_size, Opts, 50), 200),
    From     = maps:get(from, Opts, undefined),
    To       = maps:get(to, Opts, undefined),
    case cb_accounts:get_account(AccountId) of
        {ok, Account} ->
            case fetch_entries(AccountId, From, To) of
                {ok, AllEntries} ->
                    Total = length(AllEntries),
                    WithBalance = running_balance(AllEntries),
                    OpeningBal = opening_balance(WithBalance),
                    ClosingBal = closing_balance(WithBalance),
                    Offset = (Page - 1) * PageSize,
                    PageEntries = lists:sublist(WithBalance, Offset + 1, PageSize),
                    {ok, #{
                        account_id       => Account#account.account_id,
                        party_id         => Account#account.party_id,
                        name             => Account#account.name,
                        currency         => Account#account.currency,
                        current_balance  => Account#account.balance,
                        opening_balance  => OpeningBal,
                        closing_balance  => ClosingBal,
                        entries          => PageEntries,
                        total            => Total,
                        page             => Page,
                        page_size        => PageSize,
                        from             => From,
                        to               => To
                    }};
                {error, Reason} ->
                    {error, Reason}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

%% Fetch all ledger entries for the account, applying optional date range,
%% sorted oldest-first so running balance can be accumulated forward.
fetch_entries(AccountId, From, To) ->
    F = fun() ->
        Entries = mnesia:index_read(ledger_entry, AccountId, account_id),
        Filtered = lists:filter(fun(E) -> in_range(E, From, To) end, Entries),
        Sorted = lists:sort(
            fun(A, B) -> A#ledger_entry.posted_at =< B#ledger_entry.posted_at end,
            Filtered
        ),
        Sorted
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> {ok, Result};
        {aborted, Reason} -> {error, Reason}
    end.

in_range(Entry, From, To) ->
    T = Entry#ledger_entry.posted_at,
    (From =:= undefined orelse T >= From) andalso
    (To   =:= undefined orelse T =< To).

%% Annotate each entry with a running balance (credits +, debits -).
running_balance(Entries) ->
    {WithBal, _} = lists:mapfoldl(
        fun(E, Acc) ->
            Delta = case E#ledger_entry.entry_type of
                credit -> E#ledger_entry.amount;
                debit  -> -E#ledger_entry.amount
            end,
            NewBal = Acc + Delta,
            Row = #{
                entry_id        => E#ledger_entry.entry_id,
                txn_id          => E#ledger_entry.txn_id,
                account_id      => E#ledger_entry.account_id,
                entry_type      => E#ledger_entry.entry_type,
                amount          => E#ledger_entry.amount,
                currency        => E#ledger_entry.currency,
                description     => E#ledger_entry.description,
                posted_at       => E#ledger_entry.posted_at,
                running_balance => NewBal
            },
            {Row, NewBal}
        end,
        0,
        Entries
    ),
    WithBal.

opening_balance([])      -> 0;
opening_balance([H | _]) ->
    maps:get(running_balance, H) -
    case maps:get(entry_type, H) of
        credit -> maps:get(amount, H);
        debit  -> -maps:get(amount, H)
    end.

closing_balance([]) -> 0;
closing_balance(Entries) ->
    Last = lists:last(Entries),
    maps:get(running_balance, Last).
