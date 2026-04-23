%% @doc HTTP handler: GET/PATCH /identity-checks/:check_id
-module(cb_idv_check_handler).
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

init(Req, State) ->
    Method = cowboy_req:method(Req),
    CheckId = cowboy_req:binding(check_id, Req),
    handle(Method, CheckId, Req, State).

handle(<<"GET">>, CheckId, Req, State) ->
    case cb_idv:get_check(CheckId) of
        {ok, Check} ->
            Req2 = cowboy_req:reply(200, headers(), jsone:encode(check_to_map(Check)), Req),
            {ok, Req2, State};
        {error, Reason} ->
            reply_error(Reason, Req, State)
    end;
handle(<<"PATCH">>, CheckId, Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(Body, [{keys, atom}]) of
        {ok, Params, _} ->
            StatusStr = maps:get(status, Params, undefined),
            StatusAtom = case StatusStr of
                <<"completed">> -> completed;
                <<"failed">>    -> failed;
                <<"expired">>   -> expired;
                A when is_atom(A), A =/= undefined -> A;
                _ -> undefined
            end,
            case StatusAtom of
                undefined ->
                    Req3 = cowboy_req:reply(422, headers(), jsone:encode(#{error => <<"missing_status">>, message => <<"status is required">>}), Req2),
                    {ok, Req3, State};
                _ ->
                    ResultData = maps:get(result_data, Params, #{}),
                    case cb_idv:submit_result(CheckId, StatusAtom, ResultData) of
                        {ok, Check} ->
                            Req3 = cowboy_req:reply(200, headers(), jsone:encode(check_to_map(Check)), Req2),
                            {ok, Req3, State};
                        {error, Reason} ->
                            {Code, _Atom, Msg} = cb_http_errors:to_response(Reason),
                            Req3 = cowboy_req:reply(Code, headers(), jsone:encode(#{error => Reason, message => Msg}), Req2),
                            {ok, Req3, State}
                    end
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

check_to_map(#idv_check{
    check_id = CId, party_id = PId, provider = Prov, status = Status,
    retry_count = RC, max_retries = MR, provider_ref = PRef,
    result_data = RD, requested_at = ReqAt, expires_at = ExpAt,
    completed_at = CompAt, created_at = CreAt, updated_at = UpdAt
}) ->
    #{check_id => CId, party_id => PId, provider => Prov, status => Status,
      retry_count => RC, max_retries => MR, provider_ref => PRef,
      result_data => RD, requested_at => ReqAt, expires_at => ExpAt,
      completed_at => CompAt, created_at => CreAt, updated_at => UpdAt}.

headers() ->
    maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()).
