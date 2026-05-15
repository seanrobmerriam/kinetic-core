%%%-------------------------------------------------------------------
%% @doc cb_contracts application callback module.
%% @end
%%%-------------------------------------------------------------------
-module(cb_contracts_app).

-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    cb_contracts_sup:start_link().

stop(_State) ->
    ok.
