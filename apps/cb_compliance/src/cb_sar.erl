%% @doc SAR (Suspicious Activity Report) Generation Workflow.
%%
%% Manages the lifecycle of regulatory Suspicious Activity Reports filed
%% from escalated compliance cases.
%%
%% == SAR Lifecycle ==
%%
%% ```
%% draft -> submitted -> filed
%%       -> withdrawn
%% ```
%%
%% SARs are created from escalated `aml_case' records. The narrative is
%% authored by compliance staff. Once submitted, a reference number is
%% expected from the regulatory body. Filing finalises the record.
-module(cb_sar).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([
    create_sar/1,
    get_sar/1,
    list_sars/0,
    list_sars_by_case/1,
    submit_sar/2,
    file_sar/2,
    withdraw_sar/1
]).

%% @doc Create a draft SAR from an escalated compliance case.
%%
%% Required keys in Params: case_id, party_id, narrative.
-spec create_sar(map()) -> {ok, #sar_report{}} | {error, atom()}.
create_sar(Params) ->
    case {maps:get(case_id, Params, undefined),
          maps:get(party_id, Params, undefined),
          maps:get(narrative, Params, undefined)} of
        {undefined, _, _} -> {error, missing_required_field};
        {_, undefined, _} -> {error, missing_required_field};
        {_, _, undefined} -> {error, missing_required_field};
        {CaseId, PartyId, Narrative} ->
            case mnesia:dirty_read(aml_case, CaseId) of
                [] ->
                    {error, case_not_found};
                [AmlCase] when AmlCase#aml_case.status =/= escalated ->
                    {error, invalid_case_status};
                [_] ->
                    Now = erlang:system_time(millisecond),
                    Sar = #sar_report{
                        sar_id           = uuid:get_v4_urandom(),
                        case_id          = CaseId,
                        party_id         = PartyId,
                        reference_number = undefined,
                        narrative        = Narrative,
                        status           = draft,
                        submitted_at     = undefined,
                        filed_at         = undefined,
                        created_at       = Now,
                        updated_at       = Now
                    },
                    F = fun() -> mnesia:write(sar_report, Sar, write), Sar end,
                    case mnesia:transaction(F) of
                        {atomic, S} -> {ok, S};
                        {aborted, Reason} -> {error, Reason}
                    end
            end
    end.

%% @doc Retrieve a SAR by its ID.
-spec get_sar(uuid()) -> {ok, #sar_report{}} | {error, not_found}.
get_sar(SarId) ->
    case mnesia:dirty_read(sar_report, SarId) of
        [] -> {error, not_found};
        [S] -> {ok, S}
    end.

%% @doc List all SARs.
-spec list_sars() -> {ok, [#sar_report{}]}.
list_sars() ->
    Sars = mnesia:dirty_match_object(sar_report, mnesia:table_info(sar_report, wild_pattern)),
    {ok, Sars}.

%% @doc List SARs for a given compliance case.
-spec list_sars_by_case(uuid()) -> {ok, [#sar_report{}]}.
list_sars_by_case(CaseId) ->
    Sars = mnesia:dirty_index_read(sar_report, CaseId, case_id),
    {ok, Sars}.

%% @doc Submit a draft SAR to the regulatory body.
%%
%% Transitions the SAR to submitted status and records submission timestamp.
-spec submit_sar(uuid(), binary()) -> {ok, #sar_report{}} | {error, atom()}.
submit_sar(SarId, Narrative) ->
    F = fun() ->
        case mnesia:read(sar_report, SarId, write) of
            [] ->
                {error, not_found};
            [S] when S#sar_report.status =/= draft ->
                {error, invalid_sar_status};
            [S] ->
                Now = erlang:system_time(millisecond),
                S2 = S#sar_report{
                    narrative    = Narrative,
                    status       = submitted,
                    submitted_at = Now,
                    updated_at   = Now
                },
                mnesia:write(sar_report, S2, write),
                S2
        end
    end,
    case mnesia:transaction(F) of
        {atomic, {error, _} = Err} -> Err;
        {atomic, S}                -> {ok, S};
        {aborted, Reason}          -> {error, Reason}
    end.

%% @doc File a submitted SAR with a regulatory reference number.
-spec file_sar(uuid(), binary()) -> {ok, #sar_report{}} | {error, atom()}.
file_sar(SarId, ReferenceNumber) ->
    F = fun() ->
        case mnesia:read(sar_report, SarId, write) of
            [] ->
                {error, not_found};
            [S] when S#sar_report.status =/= submitted ->
                {error, invalid_sar_status};
            [S] ->
                Now = erlang:system_time(millisecond),
                S2 = S#sar_report{
                    reference_number = ReferenceNumber,
                    status           = filed,
                    filed_at         = Now,
                    updated_at       = Now
                },
                mnesia:write(sar_report, S2, write),
                S2
        end
    end,
    case mnesia:transaction(F) of
        {atomic, {error, _} = Err} -> Err;
        {atomic, S}                -> {ok, S};
        {aborted, Reason}          -> {error, Reason}
    end.

%% @doc Withdraw a draft or submitted SAR.
-spec withdraw_sar(uuid()) -> {ok, #sar_report{}} | {error, atom()}.
withdraw_sar(SarId) ->
    F = fun() ->
        case mnesia:read(sar_report, SarId, write) of
            [] ->
                {error, not_found};
            [S] when S#sar_report.status =:= filed ->
                {error, case_already_filed};
            [S] when S#sar_report.status =:= withdrawn ->
                {error, invalid_sar_status};
            [S] ->
                Now = erlang:system_time(millisecond),
                S2 = S#sar_report{status = withdrawn, updated_at = Now},
                mnesia:write(sar_report, S2, write),
                S2
        end
    end,
    case mnesia:transaction(F) of
        {atomic, {error, _} = Err} -> Err;
        {atomic, S}                -> {ok, S};
        {aborted, Reason}          -> {error, Reason}
    end.
