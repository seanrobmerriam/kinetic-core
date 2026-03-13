-module(cb_log_middleware).
-behaviour(cowboy_middleware).
-export([execute/2]).

-spec execute(cowboy_req:req(), cowboy_middleware:env()) -> {ok, cowboy_req:req(), cowboy_middleware:env()}.
execute(Req, Env) ->
    Method = cowboy_req:method(Req),
    Path   = cowboy_req:path(Req),

    %% Log the incoming request
    logger:info(#{
        event  => request_received,
        method => Method,
        path   => Path,
        time   => erlang:system_time(millisecond)
    }),

    %% Continue to next middleware
    {ok, Req, Env}.
