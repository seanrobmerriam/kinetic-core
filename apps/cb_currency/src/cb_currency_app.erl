-module(cb_currency_app).
-behaviour(application).
-export([start/2, stop/1]).

-spec start(application:start_type(), term()) -> {ok, pid()}.
start(_Type, _Args) ->
    cb_currency_sup:start_link().

-spec stop(term()) -> ok.
stop(_State) ->
    ok.
