-module(cb_cors).
-export([headers/0, reply_preflight/1]).

%% CORS headers to attach to every response
-spec headers() -> #{<<_:64,_:_*8>> => <<_:8,_:_*16>>}.
headers() ->
    #{
        <<"access-control-allow-origin">>  => <<"*">>,
        <<"access-control-allow-methods">> => <<"GET, POST, PUT, DELETE, OPTIONS">>,
        <<"access-control-allow-headers">> => <<"content-type, authorization">>,
        <<"access-control-max-age">>       => <<"86400">>
    }.

%% Respond to an OPTIONS preflight with 204 No Content + CORS headers
-spec reply_preflight(cowboy_req:req()) -> cowboy_req:req().
reply_preflight(Req) ->
    cowboy_req:reply(204, headers(), <<>>, Req).
