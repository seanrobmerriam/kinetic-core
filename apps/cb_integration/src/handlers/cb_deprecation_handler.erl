%% @doc Deprecation Handler
%%
%% GET /api/v1/deprecations
%%
%% Returns the full list of deprecated API paths with sunset dates
%% and successor recommendations.
-module(cb_deprecation_handler).

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    handle(Method, Req, State).

handle(<<"GET">>, Req, State) ->
    Entries = cb_deprecation:list_deprecated(),
    Resp = lists:map(fun cb_deprecation:entry_to_map/1, Entries),
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    Req2 = cowboy_req:reply(200, Headers, jsone:encode(Resp), Req),
    {ok, Req2, State};

handle(<<"OPTIONS">>, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};

handle(_, Req, State) ->
    {_Code405, _Hdrs405, _Body405} = cb_http_errors:to_response_with_metrics(method_not_allowed),
    Req2 = cowboy_req:reply(_Code405, _Hdrs405, _Body405, Req),
    {ok, Req2, State}.
