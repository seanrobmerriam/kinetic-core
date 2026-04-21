%%% @doc Common Test suite for cb_reporting: statement generation and CSV exports.
%%%
%%% Tests cover:
%%% <ul>
%%% <li>Statement generation for an account with transactions</li>
%%% <li>Statement running balance accuracy</li>
%%% <li>Statement date range filtering</li>
%%% <li>Empty account statement</li>
%%% <li>CSV export for accounts</li>
%%% <li>CSV export for transactions</li>
%%% <li>CSV export for events</li>
%%% </ul>

-module(cb_reporting_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").
-include_lib("cb_ledger/include/cb_ledger.hrl").
-include_lib("cb_events/include/cb_events.hrl").

-export([all/0, groups/0, init_per_suite/1, end_per_suite/1,
         init_per_testcase/2, end_per_testcase/2]).

-export([
    statement_empty_account/1,
    statement_with_entries/1,
    statement_running_balance/1,
    statement_date_range_filter/1,
    export_accounts_csv/1,
    export_transactions_csv/1,
    export_events_csv/1
]).

all() ->
    [{group, statements}, {group, exports}].

groups() ->
    [
        {statements, [sequence], [
            statement_empty_account,
            statement_with_entries,
            statement_running_balance,
            statement_date_range_filter
        ]},
        {exports, [sequence], [
            export_accounts_csv,
            export_transactions_csv,
            export_events_csv
        ]}
    ].

init_per_suite(Config) ->
    mnesia:start(),
    create_tables(),
    Config.

end_per_suite(_Config) ->
    mnesia:stop(),
    mnesia:delete_schema([node()]),
    ok.

init_per_testcase(_TestCase, Config) ->
    lists:foreach(fun mnesia:clear_table/1,
                  [party, account, transaction, ledger_entry, event_outbox]),
    Config.

end_per_testcase(_TestCase, _Config) ->
    ok.

%% ===================================================================
%% Statements
%% ===================================================================

statement_empty_account(_Config) ->
    {ok, Party}   = cb_party:create_party(<<"Alice">>, <<"alice@test.com">>),
    {ok, Account} = cb_accounts:create_account(Party#party.party_id, <<"Savings">>, 'USD'),
    {ok, Stmt} = cb_statements:generate(Account#account.account_id, #{}),
    ?assertEqual(0, maps:get(total, Stmt)),
    ?assertEqual([], maps:get(entries, Stmt)),
    ?assertEqual(0, maps:get(opening_balance, Stmt)),
    ?assertEqual(0, maps:get(closing_balance, Stmt)).

statement_with_entries(_Config) ->
    {ok, Party}   = cb_party:create_party(<<"Bob">>, <<"bob@test.com">>),
    {ok, Account} = cb_accounts:create_account(Party#party.party_id, <<"Checking">>, 'USD'),
    AccId = Account#account.account_id,
    %% Write two ledger entries directly (credit then debit)
    write_entry(AccId, credit, 10000),
    write_entry(AccId, debit, 3000),
    {ok, Stmt} = cb_statements:generate(AccId, #{}),
    ?assertEqual(2, maps:get(total, Stmt)),
    ?assertEqual(2, length(maps:get(entries, Stmt))).

statement_running_balance(_Config) ->
    {ok, Party}   = cb_party:create_party(<<"Carol">>, <<"carol@test.com">>),
    {ok, Account} = cb_accounts:create_account(Party#party.party_id, <<"Checking">>, 'USD'),
    AccId = Account#account.account_id,
    write_entry_at(AccId, credit, 5000, 1000),
    write_entry_at(AccId, credit, 3000, 2000),
    write_entry_at(AccId, debit,  2000, 3000),
    {ok, Stmt} = cb_statements:generate(AccId, #{}),
    Entries = maps:get(entries, Stmt),
    Balances = [maps:get(running_balance, E) || E <- Entries],
    ?assertEqual([5000, 8000, 6000], Balances),
    ?assertEqual(0,    maps:get(opening_balance, Stmt)),
    ?assertEqual(6000, maps:get(closing_balance, Stmt)).

statement_date_range_filter(_Config) ->
    {ok, Party}   = cb_party:create_party(<<"Dave">>, <<"dave@test.com">>),
    {ok, Account} = cb_accounts:create_account(Party#party.party_id, <<"Checking">>, 'USD'),
    AccId = Account#account.account_id,
    write_entry_at(AccId, credit, 1000, 100),
    write_entry_at(AccId, credit, 2000, 500),
    write_entry_at(AccId, credit, 3000, 900),
    {ok, Stmt} = cb_statements:generate(AccId, #{from => 200, to => 800}),
    ?assertEqual(1, maps:get(total, Stmt)),
    [Entry] = maps:get(entries, Stmt),
    ?assertEqual(2000, maps:get(amount, Entry)).

%% ===================================================================
%% CSV Exports
%% ===================================================================

export_accounts_csv(_Config) ->
    {ok, Party}   = cb_party:create_party(<<"Eve">>, <<"eve@test.com">>),
    {ok, _Account} = cb_accounts:create_account(Party#party.party_id, <<"Savings">>, 'USD'),
    {ok, Csv} = cb_exports:export_accounts(),
    Lines = binary:split(Csv, <<"\r\n">>, [global]),
    %% First line is header
    [Header | DataLines] = Lines,
    ?assert(binary:match(Header, <<"account_id">>) =/= nomatch),
    ?assert(binary:match(Header, <<"currency">>) =/= nomatch),
    NonEmpty = [L || L <- DataLines, L =/= <<>>],
    ?assert(length(NonEmpty) >= 1).

export_transactions_csv(_Config) ->
    {ok, Party}   = cb_party:create_party(<<"Frank">>, <<"frank@test.com">>),
    {ok, Acc1}    = cb_accounts:create_account(Party#party.party_id, <<"Source">>, 'USD'),
    {ok, _Txn} = cb_payments:deposit(<<"export-test-deposit">>, Acc1#account.account_id, 5000, 'USD', <<"Test deposit">>),
    {ok, Csv} = cb_exports:export_transactions(),
    Lines = binary:split(Csv, <<"\r\n">>, [global]),
    [Header | DataLines] = Lines,
    ?assert(binary:match(Header, <<"txn_id">>) =/= nomatch),
    NonEmpty = [L || L <- DataLines, L =/= <<>>],
    ?assert(length(NonEmpty) >= 1).

export_events_csv(_Config) ->
    %% Emit a test event
    cb_events:emit(<<"test.event">>, #{key => <<"value">>}),
    {ok, Csv} = cb_exports:export_events(),
    Lines = binary:split(Csv, <<"\r\n">>, [global]),
    [Header | DataLines] = Lines,
    ?assert(binary:match(Header, <<"event_id">>) =/= nomatch),
    NonEmpty = [L || L <- DataLines, L =/= <<>>],
    ?assert(length(NonEmpty) >= 1).

%% ===================================================================
%% Helpers
%% ===================================================================

write_entry(AccountId, Type, Amount) ->
    write_entry_at(AccountId, Type, Amount, erlang:system_time(millisecond)).

write_entry_at(AccountId, Type, Amount, PostedAt) ->
    EntryId = list_to_binary(ref_to_list(make_ref())),
    TxnId   = list_to_binary(ref_to_list(make_ref())),
    Entry = #ledger_entry{
        entry_id    = EntryId,
        txn_id      = TxnId,
        account_id  = AccountId,
        entry_type  = Type,
        amount      = Amount,
        currency    = 'USD',
        description = <<"test entry">>,
        posted_at   = PostedAt
    },
    {atomic, ok} = mnesia:transaction(fun() -> mnesia:write(Entry) end).

create_tables() ->
    Tables = [party, account, transaction, ledger_entry, event_outbox, webhook_subscription, webhook_delivery],
    lists:foreach(fun create_table/1, Tables).

create_table(party) ->
    ensure_table(party, [{attributes, record_info(fields, party)}, {index, [email, status]}]);
create_table(account) ->
    ensure_table(account, [{attributes, record_info(fields, account)}, {index, [party_id, status]}]);
create_table(transaction) ->
    ensure_table(transaction, [{attributes, record_info(fields, transaction)},
                                {index, [idempotency_key, source_account_id, dest_account_id, status]}]);
create_table(ledger_entry) ->
    ensure_table(ledger_entry, [{attributes, record_info(fields, ledger_entry)}, {index, [txn_id, account_id]}]);
create_table(event_outbox) ->
    ensure_table(event_outbox, [{attributes, record_info(fields, event_outbox)}, {index, [status]}]);
create_table(webhook_subscription) ->
    ensure_table(webhook_subscription, [{attributes, record_info(fields, webhook_subscription)},
                                         {index, [event_type, status]}]);
create_table(webhook_delivery) ->
    ensure_table(webhook_delivery, [{attributes, record_info(fields, webhook_delivery)},
                                     {index, [event_id, subscription_id]}]).

ensure_table(Name, ExtraOpts) ->
    Opts = [{ram_copies, [node()]} | ExtraOpts],
    case mnesia:create_table(Name, Opts) of
        {atomic, ok}                    -> ok;
        {aborted, {already_exists, _}}  -> ok
    end.
