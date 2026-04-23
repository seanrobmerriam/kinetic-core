%% @doc ETS-based HTTP request counters.
%%
%% Provides lightweight atomic counters stored in a named ETS table.
%% The table is owned by the application process started by
%% `cb_integration_app' and lives for the lifetime of the node.
%%
%% Call `init/0' once at application startup before any requests arrive.
-module(cb_metrics_counter).

-export([init/0, increment/1, get/1, get_all/0]).

-define(TABLE, cb_http_metrics).

-spec init() -> ok.
init() ->
    _ = ets:new(?TABLE, [named_table, public, {write_concurrency, true}]),
    ok.

-spec increment(atom()) -> ok.
increment(Counter) ->
    ets:update_counter(?TABLE, Counter, {2, 1}, {Counter, 0}),
    ok.

-spec get(atom()) -> non_neg_integer().
get(Counter) ->
    case ets:lookup(?TABLE, Counter) of
        [{Counter, N}] -> N;
        []             -> 0
    end.

-spec get_all() -> #{atom() => non_neg_integer()}.
get_all() ->
    maps:from_list(ets:tab2list(?TABLE)).
