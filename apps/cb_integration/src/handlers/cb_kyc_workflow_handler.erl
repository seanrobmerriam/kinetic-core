%% @doc HTTP handler for a single KYC workflow: GET, PATCH, DELETE.
-module(cb_kyc_workflow_handler).
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

init(Req, State) ->
    Method = cowboy_req:method(Req),
    WorkflowId = cowboy_req:binding(workflow_id, Req),
    handle(Method, WorkflowId, Req, State).

handle(<<"GET">>, WorkflowId, Req, State) ->
    case cb_kyc_workflow:get_workflow(WorkflowId) of
        {ok, W} ->
            Req2 = cowboy_req:reply(200, headers(), jsone:encode(workflow_to_map(W)), Req),
            {ok, Req2, State};
        {error, Reason} ->
            reply_error(Reason, Req, State)
    end;
handle(<<"DELETE">>, WorkflowId, Req, State) ->
    case cb_kyc_workflow:abandon_workflow(WorkflowId) of
        {ok, W} ->
            Req2 = cowboy_req:reply(200, headers(), jsone:encode(workflow_to_map(W)), Req),
            {ok, Req2, State};
        {error, Reason} ->
            reply_error(Reason, Req, State)
    end;
handle(_, _, Req, State) ->
    Req2 = cowboy_req:reply(405, headers(), <<>>, Req),
    {ok, Req2, State}.

reply_error(Reason, Req, State) ->
    {Code, _Atom, Msg} = cb_http_errors:to_response(Reason),
    Req2 = cowboy_req:reply(Code, headers(), jsone:encode(#{error => Reason, message => Msg}), Req),
    {ok, Req2, State}.

workflow_to_map(#kyc_workflow{
    workflow_id = WId, party_id = PId, name = Name,
    status = Status, step_ids = StepIds, current_step_id = CurrStep,
    completed_at = CompAt, created_at = CreAt, updated_at = UpdAt
}) ->
    #{workflow_id => WId, party_id => PId, name => Name,
      status => Status, step_ids => StepIds, current_step_id => CurrStep,
      completed_at => CompAt, created_at => CreAt, updated_at => UpdAt}.

headers() ->
    maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()).
