-module(cb_channel_activity_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1, init_per_testcase/2, end_per_testcase/2]).
-export([
    log_creates_record/1,
    list_for_party_returns_party_entries/1,
    list_for_channel_returns_channel_entries/1,
    list_recent_respects_limit/1,
    log_with_metadata/1
]).

all() ->
    [
        log_creates_record,
        list_for_party_returns_party_entries,
        list_for_channel_returns_channel_entries,
        list_recent_respects_limit,
        log_with_metadata
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
    mnesia:clear_table(channel_activity),
    Config.

end_per_testcase(_TestCase, _Config) ->
    ok.

log_creates_record(_Config) ->
    PartyId = <<"party-001">>,
    ok = cb_channel_activity:log(web, PartyId, <<"login">>, <<"/api/v1/login">>),
    [Act | _] = cb_channel_activity:list_for_party(PartyId),
    ?assertEqual(PartyId, Act#channel_activity.party_id),
    ?assertEqual(web, Act#channel_activity.channel),
    ?assertEqual(<<"login">>, Act#channel_activity.action).

list_for_party_returns_party_entries(_Config) ->
    P1 = <<"party-aaa">>,
    P2 = <<"party-bbb">>,
    ok = cb_channel_activity:log(web,    P1, <<"login">>,    <<"/api/v1/login">>),
    ok = cb_channel_activity:log(mobile, P1, <<"transfer">>, <<"/api/v1/payment-orders">>),
    ok = cb_channel_activity:log(atm,    P2, <<"withdraw">>, <<"/api/v1/atm/withdraw">>),
    Acts1 = cb_channel_activity:list_for_party(P1),
    Acts2 = cb_channel_activity:list_for_party(P2),
    ?assertEqual(2, length(Acts1)),
    ?assertEqual(1, length(Acts2)).

list_for_channel_returns_channel_entries(_Config) ->
    ok = cb_channel_activity:log(atm,    <<"p1">>, <<"withdraw">>,  <<"/api/v1/atm/withdraw">>),
    ok = cb_channel_activity:log(atm,    <<"p2">>, <<"inquiry">>,   <<"/api/v1/atm/inquiry">>),
    ok = cb_channel_activity:log(mobile, <<"p3">>, <<"login">>,     <<"/api/v1/login">>),
    AtmActs = cb_channel_activity:list_for_channel(atm),
    ?assertEqual(2, length(AtmActs)).

list_recent_respects_limit(_Config) ->
    lists:foreach(fun(I) ->
        Bin = integer_to_binary(I),
        PartyId = <<"party-", Bin/binary>>,
        cb_channel_activity:log(web, PartyId, <<"login">>, <<"/api/v1/login">>)
    end, lists:seq(1, 10)),
    Recent5 = cb_channel_activity:list_recent(5),
    ?assertEqual(5, length(Recent5)).

log_with_metadata(_Config) ->
    ok = cb_channel_activity:log(mobile, <<"p-meta">>, <<"login">>, <<"/api/v1/login">>, 200),
    [Act | _] = cb_channel_activity:list_for_party(<<"p-meta">>),
    ?assertEqual(200, Act#channel_activity.status_code).
