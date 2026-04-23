-module(cb_channel_context_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1, init_per_testcase/2, end_per_testcase/2]).
-export([
    get_context_returns_not_found/1,
    get_context_returns_map_for_known_party/1,
    get_context_includes_accounts/1,
    get_context_includes_notification_prefs/1
]).

all() ->
    [
        get_context_returns_not_found,
        get_context_returns_map_for_known_party,
        get_context_includes_accounts,
        get_context_includes_notification_prefs
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
    mnesia:clear_table(party),
    mnesia:clear_table(account),
    mnesia:clear_table(channel_session),
    mnesia:clear_table(notification_preference),
    mnesia:clear_table(channel_limit),
    Config.

end_per_testcase(_TestCase, _Config) ->
    ok.

get_context_returns_not_found(_Config) ->
    ?assertEqual({error, not_found}, cb_channel_context:get_context(<<"no-such-party">>, web)).

get_context_returns_map_for_known_party(_Config) ->
    Party = test_party(<<"ctx-party-1">>),
    {atomic, ok} = mnesia:transaction(fun() -> mnesia:write(Party) end),
    {ok, Ctx} = cb_channel_context:get_context(<<"ctx-party-1">>, web),
    ?assertEqual(<<"ctx-party-1">>, maps:get(party_id, Ctx)),
    ?assertEqual(web, maps:get(channel, Ctx)).

get_context_includes_accounts(_Config) ->
    Party = test_party(<<"ctx-party-2">>),
    Account = test_account(<<"ctx-party-2">>, <<"acc-1">>),
    {atomic, ok} = mnesia:transaction(fun() ->
        mnesia:write(Party),
        mnesia:write(Account)
    end),
    {ok, Ctx} = cb_channel_context:get_context(<<"ctx-party-2">>, web),
    Accounts = maps:get(accounts, Ctx),
    ?assertEqual(1, length(Accounts)).

get_context_includes_notification_prefs(_Config) ->
    Party = test_party(<<"ctx-party-3">>),
    {atomic, ok} = mnesia:transaction(fun() -> mnesia:write(Party) end),
    {ok, _} = cb_notification_prefs:set_pref(<<"ctx-party-3">>, web, [<<"txn">>], true),
    {ok, Ctx} = cb_channel_context:get_context(<<"ctx-party-3">>, web),
    Prefs = maps:get(notification_prefs, Ctx),
    ?assertEqual(1, length(Prefs)).

%% Helpers

test_party(PartyId) ->
    Now = erlang:system_time(millisecond),
    #party{
        party_id            = PartyId,
        full_name           = <<"Test User">>,
        email               = <<"test@example.com">>,
        status              = active,
        kyc_status          = approved,
        onboarding_status   = complete,
        review_notes        = undefined,
        doc_refs            = [],
        risk_tier           = low,
        address             = undefined,
        age                 = undefined,
        ssn                 = undefined,
        version             = 1,
        merged_into_party_id = undefined,
        created_at          = Now,
        updated_at          = Now
    }.

test_account(PartyId, AccountId) ->
    Now = erlang:system_time(millisecond),
    #account{
        account_id       = AccountId,
        party_id         = PartyId,
        name             = <<"Checking">>,
        currency         = 'USD',
        balance          = 0,
        status           = active,
        withdrawal_limit = undefined,
        created_at       = Now,
        updated_at       = Now
    }.
