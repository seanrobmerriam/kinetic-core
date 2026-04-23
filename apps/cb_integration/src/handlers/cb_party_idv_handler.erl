%% @doc HTTP handler: POST/GET /parties/:party_id/identity-checks
-module(cb_party_idv_handler).
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

init(Req, State) ->
    Method = cowboy_req:method(Req),
    PartyId = cowboy_req:binding(party_id, Req),
    handle(Method, PartyId, Req, State).

handle(<<"POST">>, PartyId, Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(Body, [{keys, atom}]) of
        {ok, Params, _} ->
            Provider = maps:get(provider, Params, equifax),
            ProviderAtom = case Provider of
                <<"equifax">>      -> equifax;
                <<"experian">>     -> experian;
                <<"transunion">>   -> transunion;
                <<"jumio">>        -> jumio;
                <<"onfido">>       -> onfido;
                A when is_atom(A) -> A;
                _                 -> equifax
            end,
            case cb_idv:initiate_check(PartyId, ProviderAtom, maps:get(params, Params, #{})) of
                {ok, Check} ->
                    Req3 = cowboy_req:reply(201, headers(), jsone:encode(check_to_map(Check)), Req2),
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
handle(<<"GET">>, PartyId, Req, State) ->
    {ok, Checks} = cb_idv:list_for_party(PartyId),
    Req2 = cowboy_req:reply(200, headers(), jsone:encode(#{checks => [check_to_map(C) || C <- Checks]}), Req),
    {ok, Req2, State};
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
