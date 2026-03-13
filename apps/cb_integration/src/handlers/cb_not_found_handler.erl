-module(cb_not_found_handler).

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Body = jsone:encode(#{
        error => <<"not_found">>,
        message => <<"Resource not found">>
    }),
    Req2 = cowboy_req:reply(404, #{<<"content-type">> => <<"application/json">>}, Body, Req),
    {ok, Req2, State}.
