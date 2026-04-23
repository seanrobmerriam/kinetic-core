-module(cb_idv_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1, init_per_testcase/2, end_per_testcase/2]).
-export([
    %% Happy path
    initiate_check_ok/1,
    get_check_ok/1,
    list_for_party_ok/1,
    submit_result_ok/1,
    retry_check_ok/1,
    %% Error path
    get_check_not_found/1,
    submit_result_not_found/1,
    retry_check_not_found/1,
    retry_check_max_retries/1
]).

all() ->
    [
        initiate_check_ok,
        get_check_ok,
        list_for_party_ok,
        submit_result_ok,
        retry_check_ok,
        get_check_not_found,
        submit_result_not_found,
        retry_check_not_found,
        retry_check_max_retries
    ].

init_per_suite(Config) ->
    mnesia:start(),
    Tables = [
        {idv_check, [
            {ram_copies, [node()]},
            {attributes, record_info(fields, idv_check)},
            {index, [party_id, status]}
        ]},
        {party, [
            {ram_copies, [node()]},
            {attributes, record_info(fields, party)},
            {index, [status, kyc_status, risk_tier]}
        ]}
    ],
    lists:foreach(fun({Table, Opts}) ->
        case mnesia:create_table(Table, Opts) of
            {atomic, ok} -> ok;
            {aborted, {already_exists, _}} -> ok;
            {aborted, Reason} -> error({failed_to_create_table, Table, Reason})
        end
    end, Tables),
    Config.

end_per_suite(_Config) ->
    mnesia:stop(),
    mnesia:delete_schema([node()]),
    ok.

init_per_testcase(_TestCase, Config) ->
    mnesia:clear_table(idv_check),
    mnesia:clear_table(party),
    seed_party(<<"party-001">>),
    seed_party(<<"party-xyz">>),
    seed_party(<<"other-party">>),
    seed_party(<<"p1">>),
    Config.

end_per_testcase(_TestCase, _Config) ->
    ok.

seed_party(PartyId) ->
    Now = erlang:system_time(millisecond),
    P = #party{
        party_id          = PartyId,
        full_name         = <<"Test Party">>,
        email             = <<"test@example.com">>,
        status            = active,
        kyc_status        = not_started,
        onboarding_status = pending,
        review_notes      = undefined,
        doc_refs          = [],
        risk_tier         = low,
        address           = undefined,
        age               = undefined,
        ssn               = undefined,
        version           = 1,
        merged_into_party_id = undefined,
        created_at        = Now,
        updated_at        = Now
    },
    mnesia:dirty_write(party, P).

%% =============================================================================
%% Happy Path Tests
%% =============================================================================

initiate_check_ok(_Config) ->
    PartyId = <<"party-001">>,
    {ok, Check} = cb_idv:initiate_check(PartyId, onfido, #{}),
    ?assertEqual(PartyId, Check#idv_check.party_id),
    ?assertEqual(onfido, Check#idv_check.provider),
    ?assertEqual(pending, Check#idv_check.status),
    ?assertEqual(0, Check#idv_check.retry_count),
    ?assert(is_binary(Check#idv_check.check_id)),
    ok.

get_check_ok(_Config) ->
    {ok, C} = cb_idv:initiate_check(<<"p1">>, jumio, #{}),
    {ok, Retrieved} = cb_idv:get_check(C#idv_check.check_id),
    ?assertEqual(C#idv_check.check_id, Retrieved#idv_check.check_id),
    ok.

list_for_party_ok(_Config) ->
    PartyId = <<"party-xyz">>,
    {ok, _C1} = cb_idv:initiate_check(PartyId, onfido, #{}),
    {ok, _C2} = cb_idv:initiate_check(PartyId, jumio, #{}),
    {ok, _C3} = cb_idv:initiate_check(<<"other-party">>, onfido, #{}),
    {ok, Checks} = cb_idv:list_for_party(PartyId),
    ?assertEqual(2, length(Checks)),
    ok.

submit_result_ok(_Config) ->
    {ok, C} = cb_idv:initiate_check(<<"p1">>, onfido, #{}),
    {ok, Updated} = cb_idv:submit_result(C#idv_check.check_id, passed, #{<<"score">> => 99}),
    ?assertEqual(passed, Updated#idv_check.status),
    ok.

retry_check_ok(_Config) ->
    {ok, C} = cb_idv:initiate_check(<<"p1">>, onfido, #{}),
    {ok, _} = cb_idv:submit_result(C#idv_check.check_id, failed, #{}),
    {ok, Retried} = cb_idv:retry_check(C#idv_check.check_id),
    ?assertEqual(1, Retried#idv_check.retry_count),
    ?assertEqual(pending, Retried#idv_check.status),
    ok.

%% =============================================================================
%% Error Path Tests
%% =============================================================================

get_check_not_found(_Config) ->
    {error, not_found} = cb_idv:get_check(<<"no-such-id">>),
    ok.

submit_result_not_found(_Config) ->
    {error, not_found} = cb_idv:submit_result(<<"no-such-id">>, passed, #{}),
    ok.

retry_check_not_found(_Config) ->
    {error, not_found} = cb_idv:retry_check(<<"no-such-id">>),
    ok.

retry_check_max_retries(_Config) ->
    {ok, C} = cb_idv:initiate_check(<<"p1">>, onfido, #{max_retries => 1}),
    {ok, _} = cb_idv:submit_result(C#idv_check.check_id, failed, #{}),
    {ok, _R1} = cb_idv:retry_check(C#idv_check.check_id),
    {ok, _} = cb_idv:submit_result(C#idv_check.check_id, failed, #{}),
    {error, max_retries_exceeded} = cb_idv:retry_check(C#idv_check.check_id),
    ok.
