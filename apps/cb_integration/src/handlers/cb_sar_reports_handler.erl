%% @doc HTTP handler: POST/GET /compliance/sars
-module(cb_sar_reports_handler).
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

init(Req, State) ->
    Method = cowboy_req:method(Req),
    handle(Method, Req, State).

handle(<<"POST">>, Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(Body, [{keys, atom}]) of
        {ok, Params, _} ->
            case cb_sar:create_sar(Params) of
                {ok, Sar} ->
                    Req3 = cowboy_req:reply(201, headers(), jsone:encode(sar_to_map(Sar)), Req2),
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
    case proplists:get_value(<<"case_id">>, QS) of
        undefined ->
            {ok, Sars} = cb_sar:list_sars(),
            Req2 = cowboy_req:reply(200, headers(), jsone:encode(#{sars => [sar_to_map(S) || S <- Sars]}), Req),
            {ok, Req2, State};
        CaseId ->
            {ok, Sars} = cb_sar:list_sars_by_case(CaseId),
            Req2 = cowboy_req:reply(200, headers(), jsone:encode(#{sars => [sar_to_map(S) || S <- Sars]}), Req),
            {ok, Req2, State}
    end;
handle(_, Req, State) ->
    Req2 = cowboy_req:reply(405, headers(), <<>>, Req),
    {ok, Req2, State}.

sar_to_map(#sar_report{
    sar_id = SId, case_id = CId, party_id = PId,
    reference_number = RefNum, narrative = Narr, status = Status,
    submitted_at = SubAt, filed_at = FiledAt,
    created_at = CreAt, updated_at = UpdAt
}) ->
    #{sar_id => SId, case_id => CId, party_id => PId,
      reference_number => RefNum, narrative => Narr, status => Status,
      submitted_at => SubAt, filed_at => FiledAt,
      created_at => CreAt, updated_at => UpdAt}.

headers() ->
    maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()).
