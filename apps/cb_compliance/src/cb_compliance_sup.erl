%% @doc Top-level supervisor for the cb_compliance application.
%%
%% Uses a one_for_one strategy. All compliance domain modules are pure
%% functional modules (no processes), so the supervisor has no children
%% at this time. It is retained for future gen_server workers (e.g.,
%% AML rule evaluation engine, alert queue worker).
-module(cb_compliance_sup).
-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

-spec start_link() -> {ok, pid()} | {error, any()}.
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

-spec init([]) -> {ok, {supervisor:sup_flags(), [supervisor:child_spec()]}}.
init([]) ->
    SupFlags = #{strategy => one_for_one, intensity => 5, period => 10},
    {ok, {SupFlags, []}}.
