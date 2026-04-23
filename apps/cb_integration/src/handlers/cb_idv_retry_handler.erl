%% @doc HTTP handler: POST /identity-checks/:check_id/retry
-module(cb_idv_retry_handler).
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

init(Req, State) ->
    Method = cowboy_req:method(Req),
    CheckId = cowboy_req:binding(check_id, Req),
    handle(Method, CheckId, Req, State).

handle(<<"POST">>, CheckId, Req, State) ->
    case cb_idv:retry_check(CheckId) of
        {ok, Check} ->
            Req2 = cowboy_req:reply(200, headers(), jsone:encode(check_to_map(Check)), Req),
            {ok, Req2, State};
        {error, Reason} ->
            {Code, _Atom, Msg} = cb_http_errors:to_response(Reason),
            Req2 = cowboy_req:reply(Code, headers(), jsone:encode(#{error => Reason, message => Msg}), Req),
            {ok, Req2, State}
    end;
handle(_, _, Req, State) ->
    Req2 = cowboy_req:reply(405, headers(), <<>>, Req),
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
