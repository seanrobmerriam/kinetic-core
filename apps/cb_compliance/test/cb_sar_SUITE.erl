-module(cb_sar_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1, init_per_testcase/2, end_per_testcase/2]).
-export([
    %% Happy path
    create_sar_ok/1,
    get_sar_ok/1,
    list_sars_ok/1,
    list_sars_by_case_ok/1,
    submit_sar_ok/1,
    file_sar_ok/1,
    withdraw_draft_ok/1,
    withdraw_submitted_ok/1,
    %% Error path
    get_sar_not_found/1,
    create_sar_case_not_escalated/1,
    submit_sar_not_found/1,
    file_sar_not_submitted/1,
    withdraw_filed_sar/1
]).

all() ->
    [
        create_sar_ok,
        get_sar_ok,
        list_sars_ok,
        list_sars_by_case_ok,
        submit_sar_ok,
        file_sar_ok,
        withdraw_draft_ok,
        withdraw_submitted_ok,
        get_sar_not_found,
        create_sar_case_not_escalated,
        submit_sar_not_found,
        file_sar_not_submitted,
        withdraw_filed_sar
    ].

init_per_suite(Config) ->
    mnesia:start(),
    Tables = [
        {sar_report, [
            {ram_copies, [node()]},
            {attributes, record_info(fields, sar_report)},
            {index, [case_id, party_id, status]}
        ]},
        {aml_case, [
            {ram_copies, [node()]},
            {attributes, record_info(fields, aml_case)},
            {index, [party_id, status]}
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
    mnesia:clear_table(sar_report),
    mnesia:clear_table(aml_case),
    Config.

end_per_testcase(_TestCase, _Config) ->
    ok.

%% Helpers

make_escalated_case() ->
    CaseId = list_to_binary("case-" ++ integer_to_list(erlang:unique_integer([positive]))),
    PartyId = <<"party-001">>,
    Now = erlang:system_time(millisecond),
    C = #aml_case{
        case_id = CaseId,
        party_id = PartyId,
        alert_ids = [],
        status = escalated,
        assignee = undefined,
        summary = <<"Escalated case">>,
        resolution = undefined,
        closed_at = undefined,
        created_at = Now,
        updated_at = Now
    },
    {atomic, ok} = mnesia:transaction(fun() -> mnesia:write(aml_case, C, write) end),
    C.

make_open_case() ->
    CaseId = list_to_binary("case-open-" ++ integer_to_list(erlang:unique_integer([positive]))),
    Now = erlang:system_time(millisecond),
    C = #aml_case{
        case_id = CaseId,
        party_id = <<"party-002">>,
        alert_ids = [],
        status = open,
        assignee = undefined,
        summary = <<"Open case">>,
        resolution = undefined,
        closed_at = undefined,
        created_at = Now,
        updated_at = Now
    },
    {atomic, ok} = mnesia:transaction(fun() -> mnesia:write(aml_case, C, write) end),
    C.

%% =============================================================================
%% Happy Path Tests
%% =============================================================================

create_sar_ok(_Config) ->
    C = make_escalated_case(),
    {ok, Sar} = cb_sar:create_sar(#{
        case_id => C#aml_case.case_id,
        party_id => C#aml_case.party_id,
        narrative => <<"Suspicious activity detected in multiple transactions">>
    }),
    ?assertEqual(C#aml_case.case_id, Sar#sar_report.case_id),
    ?assertEqual(draft, Sar#sar_report.status),
    ?assert(is_binary(Sar#sar_report.sar_id)),
    ok.

get_sar_ok(_Config) ->
    C = make_escalated_case(),
    {ok, Sar} = cb_sar:create_sar(#{
        case_id => C#aml_case.case_id,
        party_id => C#aml_case.party_id,
        narrative => <<"Narrative">>
    }),
    {ok, Got} = cb_sar:get_sar(Sar#sar_report.sar_id),
    ?assertEqual(Sar#sar_report.sar_id, Got#sar_report.sar_id),
    ok.

list_sars_ok(_Config) ->
    C1 = make_escalated_case(),
    C2 = make_escalated_case(),
    {ok, _S1} = cb_sar:create_sar(#{
        case_id => C1#aml_case.case_id, party_id => C1#aml_case.party_id,
        narrative => <<"N1">>
    }),
    {ok, _S2} = cb_sar:create_sar(#{
        case_id => C2#aml_case.case_id, party_id => C2#aml_case.party_id,
        narrative => <<"N2">>
    }),
    {ok, Sars} = cb_sar:list_sars(),
    ?assertEqual(2, length(Sars)),
    ok.

list_sars_by_case_ok(_Config) ->
    C = make_escalated_case(),
    {ok, S} = cb_sar:create_sar(#{
        case_id => C#aml_case.case_id, party_id => C#aml_case.party_id,
        narrative => <<"N">>
    }),
    {ok, Sars} = cb_sar:list_sars_by_case(C#aml_case.case_id),
    ?assertEqual(1, length(Sars)),
    [Head | _] = Sars,
    ?assertEqual(S#sar_report.sar_id, Head#sar_report.sar_id),
    ok.

submit_sar_ok(_Config) ->
    C = make_escalated_case(),
    {ok, Sar} = cb_sar:create_sar(#{
        case_id => C#aml_case.case_id, party_id => C#aml_case.party_id,
        narrative => <<"N">>
    }),
    {ok, Submitted} = cb_sar:submit_sar(Sar#sar_report.sar_id, <<"submitter-001">>),
    ?assertEqual(submitted, Submitted#sar_report.status),
    ?assert(Submitted#sar_report.submitted_at =/= undefined),
    ok.

file_sar_ok(_Config) ->
    C = make_escalated_case(),
    {ok, Sar} = cb_sar:create_sar(#{
        case_id => C#aml_case.case_id, party_id => C#aml_case.party_id,
        narrative => <<"N">>
    }),
    {ok, Submitted} = cb_sar:submit_sar(Sar#sar_report.sar_id, <<"submitter-001">>),
    {ok, Filed} = cb_sar:file_sar(Submitted#sar_report.sar_id, <<"REF-2024-001">>),
    ?assertEqual(filed, Filed#sar_report.status),
    ?assertEqual(<<"REF-2024-001">>, Filed#sar_report.reference_number),
    ?assert(Filed#sar_report.filed_at =/= undefined),
    ok.

withdraw_draft_ok(_Config) ->
    C = make_escalated_case(),
    {ok, Sar} = cb_sar:create_sar(#{
        case_id => C#aml_case.case_id, party_id => C#aml_case.party_id,
        narrative => <<"N">>
    }),
    {ok, Withdrawn} = cb_sar:withdraw_sar(Sar#sar_report.sar_id),
    ?assertEqual(withdrawn, Withdrawn#sar_report.status),
    ok.

withdraw_submitted_ok(_Config) ->
    C = make_escalated_case(),
    {ok, Sar} = cb_sar:create_sar(#{
        case_id => C#aml_case.case_id, party_id => C#aml_case.party_id,
        narrative => <<"N">>
    }),
    {ok, Submitted} = cb_sar:submit_sar(Sar#sar_report.sar_id, <<"s-001">>),
    {ok, Withdrawn} = cb_sar:withdraw_sar(Submitted#sar_report.sar_id),
    ?assertEqual(withdrawn, Withdrawn#sar_report.status),
    ok.

%% =============================================================================
%% Error Path Tests
%% =============================================================================

get_sar_not_found(_Config) ->
    {error, not_found} = cb_sar:get_sar(<<"no-such-sar">>),
    ok.

create_sar_case_not_escalated(_Config) ->
    C = make_open_case(),
    {error, invalid_case_status} = cb_sar:create_sar(#{
        case_id => C#aml_case.case_id, party_id => C#aml_case.party_id,
        narrative => <<"N">>
    }),
    ok.

submit_sar_not_found(_Config) ->
    {error, not_found} = cb_sar:submit_sar(<<"no-such-sar">>, <<"s">>),
    ok.

file_sar_not_submitted(_Config) ->
    C = make_escalated_case(),
    {ok, Sar} = cb_sar:create_sar(#{
        case_id => C#aml_case.case_id, party_id => C#aml_case.party_id,
        narrative => <<"N">>
    }),
    {error, invalid_sar_status} = cb_sar:file_sar(Sar#sar_report.sar_id, <<"REF-001">>),
    ok.

withdraw_filed_sar(_Config) ->
    C = make_escalated_case(),
    {ok, Sar} = cb_sar:create_sar(#{
        case_id => C#aml_case.case_id, party_id => C#aml_case.party_id,
        narrative => <<"N">>
    }),
    {ok, S} = cb_sar:submit_sar(Sar#sar_report.sar_id, <<"s">>),
    {ok, F} = cb_sar:file_sar(S#sar_report.sar_id, <<"REF">>),
    {error, case_already_filed} = cb_sar:withdraw_sar(F#sar_report.sar_id),
    ok.
