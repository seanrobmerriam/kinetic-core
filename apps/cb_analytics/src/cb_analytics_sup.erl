%%%-------------------------------------------------------------------
%% @doc cb_analytics top-level supervisor. No long-lived children for now;
%% domain modules are stateless and operate against Mnesia directly.
%% @end
%%%-------------------------------------------------------------------
-module(cb_analytics_sup).

-behaviour(supervisor).

-export([start_link/0, init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    SupFlags = #{strategy  => one_for_one,
                 intensity => 10,
                 period    => 60},
    {ok, {SupFlags, []}}.
