-module(cb_payments_app).
-behaviour(application).

-export([start/2, stop/1, config_change/3]).

-spec start(normal, any()) -> {ok, pid()} | {error, any()}.
start(_StartType, _StartArgs) ->
    cb_payments_sup:start_link().

-spec stop(any()) -> ok.
stop(_State) ->
    ok.

-spec config_change(list(), list(), list()) -> ok.
config_change(_Changed, _New, _Removed) ->
    ok.
