-module(cb_kyc_workflow_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1, init_per_testcase/2, end_per_testcase/2]).
-export([
    %% Happy path
    create_workflow_ok/1,
    get_workflow_ok/1,
    list_for_party_ok/1,
    list_all_ok/1,
    start_workflow_ok/1,
    advance_step_ok/1,
    abandon_workflow_ok/1,
    get_steps_ok/1,
    %% Error path
    get_workflow_not_found/1,
    start_workflow_not_found/1,
    start_workflow_already_started/1,
    advance_step_not_found/1,
    advance_step_invalid_status/1,
    abandon_workflow_not_found/1
]).

all() ->
    [
        create_workflow_ok,
        get_workflow_ok,
        list_for_party_ok,
        list_all_ok,
        start_workflow_ok,
        advance_step_ok,
        abandon_workflow_ok,
        get_steps_ok,
        get_workflow_not_found,
        start_workflow_not_found,
        start_workflow_already_started,
        advance_step_not_found,
        advance_step_invalid_status,
        abandon_workflow_not_found
    ].

init_per_suite(Config) ->
    mnesia:start(),
    Tables = [
        {kyc_workflow, [
            {ram_copies, [node()]},
            {attributes, record_info(fields, kyc_workflow)},
            {index, [party_id, status]}
        ]},
        {kyc_step, [
            {ram_copies, [node()]},
            {attributes, record_info(fields, kyc_step)},
            {index, [workflow_id]}
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
    mnesia:clear_table(kyc_workflow),
    mnesia:clear_table(kyc_step),
    mnesia:clear_table(party),
    %% Seed stub parties used across tests
    seed_party(<<"party-001">>),
    seed_party(<<"party-a">>),
    seed_party(<<"party-b">>),
    seed_party(<<"p1">>),
    seed_party(<<"p2">>),
    Config.

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

end_per_testcase(_TestCase, _Config) ->
    ok.

%% =============================================================================
%% Happy Path Tests
%% =============================================================================

create_workflow_ok(_Config) ->
    PartyId = <<"party-001">>,
    {ok, W} = cb_kyc_workflow:create(PartyId, <<"Onboarding">>),
    ?assertEqual(PartyId, W#kyc_workflow.party_id),
    ?assertEqual(<<"Onboarding">>, W#kyc_workflow.name),
    ?assertEqual(pending, W#kyc_workflow.status),
    ?assert(is_binary(W#kyc_workflow.workflow_id)),
    ok.

get_workflow_ok(_Config) ->
    {ok, W} = cb_kyc_workflow:create(<<"p1">>, <<"KYC">>),
    {ok, Retrieved} = cb_kyc_workflow:get_workflow(W#kyc_workflow.workflow_id),
    ?assertEqual(W#kyc_workflow.workflow_id, Retrieved#kyc_workflow.workflow_id),
    ok.

list_for_party_ok(_Config) ->
    {ok, _W1} = cb_kyc_workflow:create(<<"party-a">>, <<"KYC 1">>),
    {ok, _W2} = cb_kyc_workflow:create(<<"party-a">>, <<"KYC 2">>),
    {ok, _W3} = cb_kyc_workflow:create(<<"party-b">>, <<"KYC 3">>),
    {ok, Ws} = cb_kyc_workflow:list_for_party(<<"party-a">>),
    ?assertEqual(2, length(Ws)),
    ok.

list_all_ok(_Config) ->
    {ok, _W1} = cb_kyc_workflow:create(<<"p1">>, <<"W1">>),
    {ok, _W2} = cb_kyc_workflow:create(<<"p2">>, <<"W2">>),
    {ok, All} = cb_kyc_workflow:list_all(),
    ?assert(length(All) >= 2),
    ok.

start_workflow_ok(_Config) ->
    {ok, W} = cb_kyc_workflow:create(<<"p1">>, <<"KYC">>),
    ?assertEqual(pending, W#kyc_workflow.status),
    {ok, Started} = cb_kyc_workflow:start_workflow(W#kyc_workflow.workflow_id),
    ?assertEqual(in_progress, Started#kyc_workflow.status),
    ?assert(Started#kyc_workflow.current_step_id =/= undefined),
    ok.

advance_step_ok(_Config) ->
    {ok, W} = cb_kyc_workflow:create(<<"p1">>, <<"KYC">>),
    {ok, Started} = cb_kyc_workflow:start_workflow(W#kyc_workflow.workflow_id),
    StepId = Started#kyc_workflow.current_step_id,
    {ok, Advanced} = cb_kyc_workflow:advance_step(W#kyc_workflow.workflow_id,
        #{step_id => StepId, outcome => completed, data => #{}}),
    ?assert(Advanced#kyc_workflow.status =:= in_progress orelse
            Advanced#kyc_workflow.status =:= completed),
    ok.

abandon_workflow_ok(_Config) ->
    {ok, W} = cb_kyc_workflow:create(<<"p1">>, <<"KYC">>),
    {ok, _} = cb_kyc_workflow:start_workflow(W#kyc_workflow.workflow_id),
    {ok, Abandoned} = cb_kyc_workflow:abandon_workflow(W#kyc_workflow.workflow_id),
    ?assertEqual(abandoned, Abandoned#kyc_workflow.status),
    ok.

get_steps_ok(_Config) ->
    {ok, W} = cb_kyc_workflow:create(<<"p1">>, <<"KYC">>),
    {ok, _} = cb_kyc_workflow:start_workflow(W#kyc_workflow.workflow_id),
    {ok, Steps} = cb_kyc_workflow:get_steps(W#kyc_workflow.workflow_id),
    ?assert(length(Steps) > 0),
    ok.

%% =============================================================================
%% Error Path Tests
%% =============================================================================

get_workflow_not_found(_Config) ->
    {error, not_found} = cb_kyc_workflow:get_workflow(<<"no-such-id">>),
    ok.

start_workflow_not_found(_Config) ->
    {error, not_found} = cb_kyc_workflow:start_workflow(<<"no-such-id">>),
    ok.

start_workflow_already_started(_Config) ->
    {ok, W} = cb_kyc_workflow:create(<<"p1">>, <<"KYC">>),
    {ok, _} = cb_kyc_workflow:start_workflow(W#kyc_workflow.workflow_id),
    {error, invalid_workflow_status} = cb_kyc_workflow:start_workflow(W#kyc_workflow.workflow_id),
    ok.

advance_step_not_found(_Config) ->
    {error, not_found} = cb_kyc_workflow:advance_step(<<"no-such-id">>,
        #{step_id => <<"x">>, outcome => completed, data => #{}}),
    ok.

advance_step_invalid_status(_Config) ->
    {ok, W} = cb_kyc_workflow:create(<<"p1">>, <<"KYC">>),
    {error, invalid_workflow_status} = cb_kyc_workflow:advance_step(W#kyc_workflow.workflow_id,
        #{step_id => <<"x">>, outcome => completed, data => #{}}),
    ok.

abandon_workflow_not_found(_Config) ->
    {error, not_found} = cb_kyc_workflow:abandon_workflow(<<"no-such-id">>),
    ok.
