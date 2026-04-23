-module(cb_channel_session_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1, init_per_testcase/2, end_per_testcase/2]).
-export([
    create_returns_active_session/1,
    get_returns_not_found/1,
    get_returns_session/1,
    list_for_party_returns_all/1,
    invalidate_marks_session/1,
    invalidate_returns_not_found/1,
    invalidate_all_returns_count/1
]).

all() ->
    [
        create_returns_active_session,
        get_returns_not_found,
        get_returns_session,
        list_for_party_returns_all,
        invalidate_marks_session,
        invalidate_returns_not_found,
        invalidate_all_returns_count
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
    mnesia:clear_table(channel_session),
    Config.

end_per_testcase(_TestCase, _Config) ->
    ok.

create_returns_active_session(_Config) ->
    {ok, Session} = cb_channel_session:create(<<"party-1">>, web),
    ?assertEqual(<<"party-1">>, Session#channel_session.party_id),
    ?assertEqual(web, Session#channel_session.channel),
    ?assertEqual(active, Session#channel_session.status),
    ?assertEqual(undefined, Session#channel_session.invalidated_at).

get_returns_not_found(_Config) ->
    ?assertEqual({error, not_found}, cb_channel_session:get(<<"no-such-id">>)).

get_returns_session(_Config) ->
    {ok, Created} = cb_channel_session:create(<<"party-2">>, mobile),
    {ok, Got} = cb_channel_session:get(Created#channel_session.session_id),
    ?assertEqual(Created#channel_session.session_id, Got#channel_session.session_id).

list_for_party_returns_all(_Config) ->
    {ok, _} = cb_channel_session:create(<<"party-3">>, web),
    {ok, _} = cb_channel_session:create(<<"party-3">>, mobile),
    {ok, Sessions} = cb_channel_session:list_for_party(<<"party-3">>),
    ?assertEqual(2, length(Sessions)).

invalidate_marks_session(_Config) ->
    {ok, Session} = cb_channel_session:create(<<"party-4">>, atm),
    {ok, Invalidated} = cb_channel_session:invalidate(Session#channel_session.session_id),
    ?assertEqual(invalidated, Invalidated#channel_session.status),
    ?assertNotEqual(undefined, Invalidated#channel_session.invalidated_at).

invalidate_returns_not_found(_Config) ->
    ?assertEqual({error, not_found}, cb_channel_session:invalidate(<<"no-such-id">>)).

invalidate_all_returns_count(_Config) ->
    {ok, _} = cb_channel_session:create(<<"party-5">>, web),
    {ok, _} = cb_channel_session:create(<<"party-5">>, mobile),
    {ok, Count} = cb_channel_session:invalidate_all_for_party(<<"party-5">>),
    ?assertEqual(2, Count),
    {ok, Sessions} = cb_channel_session:list_for_party(<<"party-5">>),
    Active = [S || S <- Sessions, S#channel_session.status =:= active],
    ?assertEqual(0, length(Active)).
