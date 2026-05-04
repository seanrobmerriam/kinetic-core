%%%-------------------------------------------------------------------
%% @doc cb_analytics application callback module.
%% @end
%%%-------------------------------------------------------------------
-module(cb_analytics_app).

-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    cb_analytics_sup:start_link().

stop(_State) ->
    ok.
