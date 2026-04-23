%% @doc HTTP handler: GET/PATCH /aml/cases/:case_id
-module(cb_aml_case_handler).
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

init(Req, State) ->
    Method = cowboy_req:method(Req),
    CaseId = cowboy_req:binding(case_id, Req),
    handle(Method, CaseId, Req, State).

handle(<<"GET">>, CaseId, Req, State) ->
    case cb_aml:get_case(CaseId) of
        {ok, Case} ->
            Req2 = cowboy_req:reply(200, headers(), jsone:encode(case_to_map(Case)), Req),
            {ok, Req2, State};
        {error, Reason} ->
            reply_error(Reason, Req, State)
    end;
handle(<<"PATCH">>, CaseId, Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(Body, [{keys, atom}]) of
        {ok, Params, _} ->
            case cb_aml:update_case(CaseId, Params) of
                {ok, Case} ->
                    Req3 = cowboy_req:reply(200, headers(), jsone:encode(case_to_map(Case)), Req2),
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

reply_error(Reason, Req, State) ->
    {Code, _Atom, Msg} = cb_http_errors:to_response(Reason),
    Req2 = cowboy_req:reply(Code, headers(), jsone:encode(#{error => Reason, message => Msg}), Req),
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
