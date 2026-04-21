-module(cb_reporting_sup).
-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

-spec start_link() -> {ok, pid()} | {error, any()}.
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

-spec init([]) -> {ok, {supervisor:sup_flags(), [supervisor:child_spec()]}}.
init([]) ->
    SupFlags = #{
        strategy => one_for_one,
        intensity => 5,
        period => 10
    },
    Children = [
        #{id => cb_reporting,
          start => {cb_reporting, start_link, []},
          restart => permanent,
          shutdown => 5000,
          type => worker,
          modules => [cb_reporting]},
        #{id => cb_jobs,
          start => {cb_jobs, start_link, []},
          restart => permanent,
          shutdown => 5000,
          type => worker,
          modules => [cb_jobs]}
    ],
    {ok, {SupFlags, Children}}.
