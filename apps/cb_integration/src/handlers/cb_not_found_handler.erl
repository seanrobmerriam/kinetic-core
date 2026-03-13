-module(cb_not_found_handler).

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Body = jsone:encode(#{
        error => <<"not_found">>,
        message => <<"Resource not found">>
    }),
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    Req2 = cowboy_req:reply(404, Headers, Body, Req),
    {ok, Req2, State}.
