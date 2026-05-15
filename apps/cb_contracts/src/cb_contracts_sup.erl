%%%-------------------------------------------------------------------
%% @doc cb_contracts top-level supervisor.
%%
%% Contract evaluation modules are stateless; no workers are required in v1.
%% @end
%%%-------------------------------------------------------------------
-module(cb_contracts_sup).

-behaviour(supervisor).

-export([start_link/0, init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    SupFlags = #{strategy => one_for_one,
                 intensity => 10,
                 period => 60},
    {ok, {SupFlags, []}}.
