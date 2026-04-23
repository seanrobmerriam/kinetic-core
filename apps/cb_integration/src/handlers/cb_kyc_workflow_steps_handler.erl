%% @doc HTTP handler: GET /kyc/workflows/:workflow_id/steps
-module(cb_kyc_workflow_steps_handler).
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

init(Req, State) ->
    Method = cowboy_req:method(Req),
    WorkflowId = cowboy_req:binding(workflow_id, Req),
    handle(Method, WorkflowId, Req, State).

handle(<<"GET">>, WorkflowId, Req, State) ->
    case cb_kyc_workflow:get_steps(WorkflowId) of
        {ok, Steps} ->
            Req2 = cowboy_req:reply(200, headers(), jsone:encode(#{steps => [step_to_map(S) || S <- Steps]}), Req),
            {ok, Req2, State};
        {error, Reason} ->
            {Code, _Atom, Msg} = cb_http_errors:to_response(Reason),
            Req2 = cowboy_req:reply(Code, headers(), jsone:encode(#{error => Reason, message => Msg}), Req),
            {ok, Req2, State}
    end;
handle(_, _, Req, State) ->
    Req2 = cowboy_req:reply(405, headers(), <<>>, Req),
    {ok, Req2, State}.

step_to_map(#kyc_step{
    step_id = SId, workflow_id = WId, name = Name, step_type = Type,
    sequence_order = Seq, status = Status, data = Data,
    completed_at = CompAt, created_at = CreAt
}) ->
    #{step_id => SId, workflow_id => WId, name => Name, step_type => Type,
      sequence_order => Seq, status => Status, data => Data,
      completed_at => CompAt, created_at => CreAt}.

headers() ->
    maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()).
