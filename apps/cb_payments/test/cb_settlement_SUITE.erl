-module(cb_settlement_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1]).
-export([
    create_run_ok/1,
    get_run_ok/1,
    get_run_not_found/1,
    list_runs_ok/1,
    add_entry_ok/1,
    close_run_ok/1,
    auto_reconcile_ok/1,
    list_unmatched_ok/1
]).

all() ->
    [
        create_run_ok,
        get_run_ok,
        get_run_not_found,
        list_runs_ok,
        add_entry_ok,
        close_run_ok,
        auto_reconcile_ok,
        list_unmatched_ok
    ].

init_per_suite(Config) ->
    mnesia:start(),
    cb_schema:create_tables(),
    Config.

end_per_suite(_Config) ->
    mnesia:stop(),
    ok.

create_run_ok(_Config) ->
    {ok, RunId} = cb_settlement:create_run(#{rail => <<"sepa">>}),
    ?assert(is_binary(RunId)).

get_run_ok(_Config) ->
    {ok, RunId} = cb_settlement:create_run(#{rail => <<"swift">>}),
    {ok, Run} = cb_settlement:get_run(RunId),
    ?assertEqual(RunId, Run#settlement_run.run_id).

get_run_not_found(_Config) ->
    {error, not_found} = cb_settlement:get_run(<<"no-such-run">>).

list_runs_ok(_Config) ->
    {ok, _} = cb_settlement:create_run(#{rail => <<"ach">>}),
    All = cb_settlement:list_runs(),
    ?assert(length(All) >= 1).

add_entry_ok(_Config) ->
    {ok, RunId} = cb_settlement:create_run(#{rail => <<"sepa">>}),
    Params = #{payment_id      => <<"pay-001">>,
               expected_amount => 10000,
               currency        => <<"EUR">>},
    {ok, EntryId} = cb_settlement:add_entry(RunId, Params),
    ?assert(is_binary(EntryId)).

close_run_ok(_Config) ->
    {ok, RunId} = cb_settlement:create_run(#{rail => <<"ach">>}),
    ok = cb_settlement:close_run(RunId).

auto_reconcile_ok(_Config) ->
    {ok, RunId} = cb_settlement:create_run(#{rail => <<"sepa">>}),
    Params = #{payment_id      => <<"pay-recon-001">>,
               expected_amount => 5000,
               currency        => <<"EUR">>},
    {ok, _} = cb_settlement:add_entry(RunId, Params),
    {ok, Summary} = cb_settlement:auto_reconcile(RunId),
    ?assert(is_map(Summary)).

list_unmatched_ok(_Config) ->
    {ok, RunId} = cb_settlement:create_run(#{rail => <<"swift">>}),
    Params = #{payment_id      => <<"pay-unmatched">>,
               expected_amount => 99999,
               currency        => <<"USD">>},
    {ok, _} = cb_settlement:add_entry(RunId, Params),
    Unmatched = cb_settlement:list_unmatched(RunId),
    ?assert(length(Unmatched) >= 1).
