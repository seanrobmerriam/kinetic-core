%% @doc HTTP handler: POST /kyc/workflows/:workflow_id/advance
%%
%% Body: { "outcome": "completed" | "failed" | "skipped" }
-module(cb_kyc_workflow_advance_handler).
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

init(Req, State) ->
    Method = cowboy_req:method(Req),
    WorkflowId = cowboy_req:binding(workflow_id, Req),
    handle(Method, WorkflowId, Req, State).

handle(<<"POST">>, WorkflowId, Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(Body, [{keys, atom}]) of
        {ok, Params, _} ->
            Outcome = maps:get(outcome, Params, completed),
            OutcomeAtom = case Outcome of
                <<"completed">> -> completed;
                <<"failed">>    -> failed;
                <<"skipped">>   -> skipped;
                A when is_atom(A) -> A;
                _               -> completed
            end,
            case cb_kyc_workflow:advance_step(WorkflowId, OutcomeAtom) of
                {ok, W} ->
                    Req3 = cowboy_req:reply(200, headers(), jsone:encode(workflow_to_map(W)), Req2),
                    {ok, Req3, State};
                {error, Reason} ->
                    {Code, _Atom, Msg} = cb_http_errors:to_response(Reason),
                    Req3 = cowboy_req:reply(Code, headers(), jsone:encode(#{error => Reason, message => Msg}), Req2),
                    {ok, Req3, State}
            end;
        {error, _} ->
            Req3 = cowboy_req:reply(400, headers(), jsone:encode(#{error => <<"bad_request">>, message => <<"Invalid JSON">>}), Req2),
            {ok, Req3, State}
    end;
handle(_, _, Req, State) ->
    Req2 = cowboy_req:reply(405, headers(), <<>>, Req),
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
