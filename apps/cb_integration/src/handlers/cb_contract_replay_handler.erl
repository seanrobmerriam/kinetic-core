%% @doc Contract execution trace and replay endpoints.
%%
%% Routes:
%%   GET  /api/v1/contracts/executions/:execution_id
%%   POST /api/v1/contracts/executions/:execution_id/replay
-module(cb_contract_replay_handler).

-include_lib("cb_contracts/include/cb_contracts.hrl").

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    ExecutionId = cowboy_req:binding(execution_id, Req, undefined),
    Action = cowboy_req:binding(action, Req, undefined),
    handle(Method, ExecutionId, Action, Req, State).

handle(<<"GET">>, ExecutionId, undefined, Req, State) ->
    case cb_contracts:get_execution_trace(ExecutionId) of
        {ok, Trace} ->
            json_reply(200, trace_to_map(Trace), Req, State);
        {error, Reason} ->
            reply_error(Reason, Req, State)
    end;

handle(<<"POST">>, ExecutionId, <<"replay">>, Req, State) ->
    {ok, BodyBin, Req2} = cowboy_req:read_body(Req),
    ContextOverride = case BodyBin of
        <<>> -> undefined;
        _ ->
            case jsone:try_decode(BodyBin) of
                {ok, Json, _} when is_map(Json) -> maps:get(<<"context">>, Json, undefined);
                _ -> undefined
            end
    end,
    case cb_contracts:replay_execution(ExecutionId, ContextOverride) of
        {ok, Result} ->
            json_reply(200, Result, Req2, State);
        {error, Reason} ->
            reply_error(Reason, Req2, State)
    end;

handle(<<"OPTIONS">>, _ExecutionId, _Action, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};

handle(_, _ExecutionId, _Action, Req, State) ->
    {Code, Hdrs, RespBody} = cb_http_errors:to_response_with_metrics(method_not_allowed),
    Req2 = cowboy_req:reply(Code, Hdrs, RespBody, Req),
    {ok, Req2, State}.

reply_error(Reason, Req, State) ->
    {Status, ErrorAtom, Message} = cb_http_errors:to_response(Reason),
    json_reply(Status, #{error => ErrorAtom, message => Message}, Req, State).

json_reply(Status, Body, Req, State) ->
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    Req2 = cowboy_req:reply(Status, Headers, jsone:encode(Body), Req),
    {ok, Req2, State}.

trace_to_map(#contract_execution_trace{
    execution_id = ExecutionId,
    contract_id = ContractId,
    contract_version = ContractVersion,
    request_id = RequestId,
    input_hash = InputHash,
    decision_hash = DecisionHash,
    result = Result,
    reason = Reason,
    started_at_us = StartedAtUs,
    finished_at_us = FinishedAtUs,
    duration_us = DurationUs,
    context_snapshot = Context,
    decision_snapshot = Decision,
    trace_payload = Payload,
    created_at = CreatedAt
}) ->
    #{execution_id => ExecutionId,
      contract_id => ContractId,
      contract_version => ContractVersion,
      request_id => RequestId,
      input_hash => InputHash,
      decision_hash => DecisionHash,
      result => Result,
      reason => Reason,
      started_at_us => StartedAtUs,
      finished_at_us => FinishedAtUs,
      duration_us => DurationUs,
      context_snapshot => Context,
      decision_snapshot => Decision,
      trace_payload => Payload,
      created_at => CreatedAt}.
