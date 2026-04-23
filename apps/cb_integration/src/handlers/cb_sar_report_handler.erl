%% @doc HTTP handler: GET/PATCH /compliance/sars/:sar_id
-module(cb_sar_report_handler).
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

init(Req, State) ->
    Method = cowboy_req:method(Req),
    SarId = cowboy_req:binding(sar_id, Req),
    handle(Method, SarId, Req, State).

handle(<<"GET">>, SarId, Req, State) ->
    case cb_sar:get_sar(SarId) of
        {ok, Sar} ->
            Req2 = cowboy_req:reply(200, headers(), jsone:encode(sar_to_map(Sar)), Req),
            {ok, Req2, State};
        {error, Reason} ->
            reply_error(Reason, Req, State)
    end;
handle(<<"PATCH">>, SarId, Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(Body, [{keys, atom}]) of
        {ok, Params, _} ->
            Action = maps:get(action, Params, undefined),
            case Action of
                <<"submit">> ->
                    Narrative = maps:get(narrative, Params, <<"">>),
                    case cb_sar:submit_sar(SarId, Narrative) of
                        {ok, Sar} ->
                            Req3 = cowboy_req:reply(200, headers(), jsone:encode(sar_to_map(Sar)), Req2),
                            {ok, Req3, State};
                        {error, Reason} ->
                            {Code, _Atom, Msg} = cb_http_errors:to_response(Reason),
                            Req3 = cowboy_req:reply(Code, headers(), jsone:encode(#{error => Reason, message => Msg}), Req2),
                            {ok, Req3, State}
                    end;
                <<"file">> ->
                    RefNum = maps:get(reference_number, Params, <<"">>),
                    case cb_sar:file_sar(SarId, RefNum) of
                        {ok, Sar} ->
                            Req3 = cowboy_req:reply(200, headers(), jsone:encode(sar_to_map(Sar)), Req2),
                            {ok, Req3, State};
                        {error, Reason} ->
                            {Code, _Atom, Msg} = cb_http_errors:to_response(Reason),
                            Req3 = cowboy_req:reply(Code, headers(), jsone:encode(#{error => Reason, message => Msg}), Req2),
                            {ok, Req3, State}
                    end;
                <<"withdraw">> ->
                    case cb_sar:withdraw_sar(SarId) of
                        {ok, Sar} ->
                            Req3 = cowboy_req:reply(200, headers(), jsone:encode(sar_to_map(Sar)), Req2),
                            {ok, Req3, State};
                        {error, Reason} ->
                            {Code, _Atom, Msg} = cb_http_errors:to_response(Reason),
                            Req3 = cowboy_req:reply(Code, headers(), jsone:encode(#{error => Reason, message => Msg}), Req2),
                            {ok, Req3, State}
                    end;
                _ ->
                    Req3 = cowboy_req:reply(422, headers(), jsone:encode(#{error => <<"invalid_action">>, message => <<"action must be submit, file, or withdraw">>}), Req2),
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
