-module(cb_events_sup).
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
        #{id => cb_events,
          start => {cb_events, start_link, []},
          restart => permanent,
          shutdown => 5000,
          type => worker,
          modules => [cb_events]}
    ],
    {ok, {SupFlags, Children}}.
