%% @doc ETS-backed token bucket rate limiter.
%%
%% Tracks request counts per client key (typically IP address) within a
%% fixed 60-second sliding window.  The default limit is 200 requests
%% per window and can be overridden via the `cb_integration` application
%% environment key `rate_limit`.
%%
%% Public API:
%%   check_and_increment/1   – Return `allow` or `deny` and atomically
%%                             increment the counter if allowed.
%%   reset/1                 – Clear the counter for a given key (used in
%%                             tests and to simulate window expiry).
%%   get_limit/0             – Return the configured per-window limit.
-module(cb_rate_limiter).

-behaviour(gen_server).

-export([start_link/0, check_and_increment/1, reset/1, get_limit/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-define(TABLE,        cb_rate_limiter_ets).
-define(WINDOW_MS,    60_000).
-define(DEFAULT_LIMIT, 200).

%%% ============================================================
%%% Public API
%%% ============================================================

-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc Check whether `Key` is within the request limit for the current
%%      window.  If allowed the counter is atomically incremented.
%%      Returns `allow` or `deny`.
-spec check_and_increment(binary()) -> allow | deny.
check_and_increment(Key) ->
    gen_server:call(?MODULE, {check_and_increment, Key}).

%% @doc Reset (delete) the counter for `Key`.  Used in tests and to
%%      simulate a window expiry without waiting 60 s.
-spec reset(binary()) -> ok.
reset(Key) ->
    gen_server:cast(?MODULE, {reset, Key}).

%% @doc Return the configured per-window request limit.
-spec get_limit() -> pos_integer().
get_limit() ->
    application:get_env(cb_integration, rate_limit, ?DEFAULT_LIMIT).

%%% ============================================================
%%% gen_server callbacks
%%% ============================================================

init([]) ->
    ets:new(?TABLE, [named_table, public, set, {read_concurrency, true}]),
    %% Periodically sweep expired entries.
    erlang:send_after(?WINDOW_MS, self(), sweep),
    {ok, #{}}.

handle_call({check_and_increment, Key}, _From, State) ->
    Now   = erlang:monotonic_time(millisecond),
    Limit = get_limit(),
    Result = case ets:lookup(?TABLE, Key) of
        [] ->
            ets:insert(?TABLE, {Key, 1, Now}),
            allow;
        [{Key, Count, WindowStart}] ->
            Age = Now - WindowStart,
            if
                Age > ?WINDOW_MS ->
                    %% Window expired – start a fresh one.
                    ets:insert(?TABLE, {Key, 1, Now}),
                    allow;
                Count < Limit ->
                    ets:insert(?TABLE, {Key, Count + 1, WindowStart}),
                    allow;
                true ->
                    deny
            end
    end,
    {reply, Result, State}.

handle_cast({reset, Key}, State) ->
    ets:delete(?TABLE, Key),
    {noreply, State}.

handle_info(sweep, State) ->
    Now = erlang:monotonic_time(millisecond),
    %% Delete entries whose window has expired.
    ets:select_delete(?TABLE, [{{'_', '_', '$1'},
                                [{'>', {'-', Now, '$1'}, ?WINDOW_MS}],
                                [true]}]),
    erlang:send_after(?WINDOW_MS, self(), sweep),
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
