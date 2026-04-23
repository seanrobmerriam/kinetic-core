%% @doc CT tests for cb_stp_hooks (TASK-051 — compliance hooks).
-module(cb_stp_hooks_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1, init_per_testcase/2, end_per_testcase/2]).
-export([
    run_hooks_passes_for_clean_party/1,
    sanctions_hook_halts_blocked_party/1,
    sanctions_hook_halts_unknown_party/1,
    run_hooks_short_circuits_on_sanctions/1
]).

all() ->
    [
        run_hooks_passes_for_clean_party,
        sanctions_hook_halts_blocked_party,
        sanctions_hook_halts_unknown_party,
        run_hooks_short_circuits_on_sanctions
    ].

init_per_suite(Config) ->
    mnesia:start(),
    cb_schema:create_tables(),
    Config.

end_per_suite(_Config) ->
    mnesia:stop(),
    mnesia:delete_schema([node()]),
    ok.

init_per_testcase(_TestCase, Config) ->
    lists:foreach(fun(T) -> mnesia:clear_table(T) end,
                  [party, party_audit, account, aml_rule, suspicious_activity]),
    Config.

end_per_testcase(_TestCase, _Config) ->
    ok.

make_order(PartyId, Amount) ->
    #payment_order{
        payment_id        = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
        idempotency_key   = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
        party_id          = PartyId,
        source_account_id = <<"acc-src">>,
        dest_account_id   = <<"acc-dst">>,
        amount            = Amount,
        currency          = 'USD',
        description       = <<"Hooks test">>,
        status            = initiated,
        stp_decision      = undefined,
        failure_reason    = undefined,
        retry_count       = 0,
        created_at        = erlang:system_time(millisecond),
        updated_at        = erlang:system_time(millisecond)
    }.

%%% ---------------------------------------------------------------- TESTS ---

run_hooks_passes_for_clean_party(_Config) ->
    {ok, Party} = cb_party:create_party(<<"Hooks Test">>, <<"hooks@test.com">>),
    Order = make_order(Party#party.party_id, 50_000),
    ?assertEqual(ok, cb_stp_hooks:run_hooks(Order)).

sanctions_hook_halts_blocked_party(_Config) ->
    {ok, Party} = cb_party:create_party(<<"Blocked">>, <<"blocked@test.com">>),
    Pid = Party#party.party_id,
    %% Write party back with sanctions_blocked = true in metadata
    Blocked = Party#party{metadata = #{sanctions_blocked => true}},
    {atomic, ok} = mnesia:transaction(fun() ->
        mnesia:write(party, Blocked, write)
    end),
    Order = make_order(Pid, 50_000),
    ?assertMatch({halt, _}, cb_stp_hooks:sanctions_hook(Order)).

sanctions_hook_halts_unknown_party(_Config) ->
    Order = make_order(<<"no-such-party">>, 50_000),
    ?assertMatch({halt, _}, cb_stp_hooks:sanctions_hook(Order)).

run_hooks_short_circuits_on_sanctions(_Config) ->
    {ok, Party} = cb_party:create_party(<<"SC Test">>, <<"sc@test.com">>),
    Pid = Party#party.party_id,
    Blocked = Party#party{metadata = #{sanctions_blocked => true}},
    {atomic, ok} = mnesia:transaction(fun() ->
        mnesia:write(party, Blocked, write)
    end),
    Order = make_order(Pid, 50_000),
    %% Sanctions hook fires first; AML hook never reached
    ?assertMatch({halt, <<"Sanctions check", _/binary>>},
                 cb_stp_hooks:run_hooks(Order)).
