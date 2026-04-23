%% @doc HTTP handler for KYC workflow collection: POST (create) and GET (list).
-module(cb_kyc_workflows_handler).
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

init(Req, State) ->
    Method = cowboy_req:method(Req),
    handle(Method, Req, State).

handle(<<"POST">>, Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(Body, [{keys, atom}]) of
        {ok, Params, _} ->
            case cb_kyc_workflow:create(
                maps:get(party_id, Params, undefined),
                maps:get(name, Params, <<"Default KYC Workflow">>)
            ) of
                {ok, Workflow} ->
                    Req3 = cowboy_req:reply(201, headers(), jsone:encode(workflow_to_map(Workflow)), Req2),
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
handle(<<"GET">>, Req, State) ->
    QS = cowboy_req:parse_qs(Req),
    case proplists:get_value(<<"party_id">>, QS) of
        undefined ->
            {ok, Workflows} = cb_kyc_workflow:list_all(),
            Req2 = cowboy_req:reply(200, headers(), jsone:encode(#{workflows => [workflow_to_map(W) || W <- Workflows]}), Req),
            {ok, Req2, State};
        PartyId ->
            {ok, Workflows} = cb_kyc_workflow:list_for_party(PartyId),
            Req2 = cowboy_req:reply(200, headers(), jsone:encode(#{workflows => [workflow_to_map(W) || W <- Workflows]}), Req),
            {ok, Req2, State}
    end;
handle(_, Req, State) ->
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
