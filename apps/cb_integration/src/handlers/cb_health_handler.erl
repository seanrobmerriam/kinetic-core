-module(cb_health_handler).

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Body = jsone:encode(#{status => <<"ok">>}),
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    Req2 = cowboy_req:reply(200, Headers, Body, Req),
    {ok, Req2, State}.
