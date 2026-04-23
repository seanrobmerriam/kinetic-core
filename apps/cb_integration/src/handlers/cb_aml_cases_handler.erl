%% @doc HTTP handler: POST/GET /aml/cases
-module(cb_aml_cases_handler).
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

init(Req, State) ->
    Method = cowboy_req:method(Req),
    handle(Method, Req, State).

handle(<<"POST">>, Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(Body, [{keys, atom}]) of
        {ok, Params, _} ->
            case cb_aml:create_case(Params) of
                {ok, Case} ->
                    Req3 = cowboy_req:reply(201, headers(), jsone:encode(case_to_map(Case)), Req2),
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
    case proplists:get_value(<<"status">>, QS) of
        undefined ->
            {ok, Cases} = cb_aml:list_cases(),
            Req2 = cowboy_req:reply(200, headers(), jsone:encode(#{cases => [case_to_map(C) || C <- Cases]}), Req),
            {ok, Req2, State};
        StatusBin ->
            StatusAtom = binary_to_existing_atom(StatusBin, utf8),
            {ok, Cases} = cb_aml:list_cases_by_status(StatusAtom),
            Req2 = cowboy_req:reply(200, headers(), jsone:encode(#{cases => [case_to_map(C) || C <- Cases]}), Req),
            {ok, Req2, State}
    end;
handle(_, Req, State) ->
    Req2 = cowboy_req:reply(405, headers(), <<>>, Req),
    {ok, Req2, State}.

case_to_map(#aml_case{
    case_id = CId, party_id = PId, alert_ids = AIds, status = Status,
    assignee = Assignee, summary = Summary, resolution = Resolution,
    closed_at = ClosedAt, created_at = CreAt, updated_at = UpdAt
}) ->
    #{case_id => CId, party_id => PId, alert_ids => AIds, status => Status,
      assignee => Assignee, summary => Summary, resolution => Resolution,
      closed_at => ClosedAt, created_at => CreAt, updated_at => UpdAt}.

headers() ->
    maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()).
