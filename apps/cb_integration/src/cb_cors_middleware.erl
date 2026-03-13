-module(cb_cors_middleware).
-behaviour(cowboy_middleware).

-export([execute/2]).

-spec execute(cowboy_req:req(), cowboy_middleware:env()) -> {ok, cowboy_req:req(), cowboy_middleware:env()}.
execute(Req, Env) ->
    Req1 = cowboy_req:set_resp_header(<<"access-control-allow-origin">>, <<"*">>, Req),
    Req2 = cowboy_req:set_resp_header(<<"access-control-allow-methods">>, <<"GET, POST, PUT, DELETE, OPTIONS">>, Req1),
    Req3 = cowboy_req:set_resp_header(<<"access-control-allow-headers">>, <<"content-type, authorization">>, Req2),
    
    case cowboy_req:method(Req3) of
        <<"OPTIONS">> ->
            Req4 = cowboy_req:set_resp_header(<<"access-control-max-age">>, <<"86400">>, Req3),
            {stop, cowboy_req:reply(204, #{}, <<>>, Req4)};
        _ ->
            {ok, Req3, Env}
    end.
