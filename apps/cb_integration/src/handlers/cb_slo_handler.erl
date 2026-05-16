%% @doc SLO/SLA objectives and alert policy snapshot endpoint.
%%
%% GET /api/v1/operations/slo
%% Returns current objective evaluations and alert states.
-module(cb_slo_handler).

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    handle(Method, Req, State).

handle(<<"GET">>, Req, State) ->
    Snapshot = cb_slo_policies:evaluate(),
    Req2 = cowboy_req:reply(200, headers(), jsone:encode(Snapshot), Req),
    {ok, Req2, State};
handle(<<"OPTIONS">>, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};
handle(_, Req, State) ->
    {Code, Hdrs, Body} = cb_http_errors:to_response_with_metrics(method_not_allowed),
    Req2 = cowboy_req:reply(Code, Hdrs, Body, Req),
    {ok, Req2, State}.

headers() ->
    maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()).
