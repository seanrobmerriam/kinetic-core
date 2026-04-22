%%% @doc Scheduled operational job runner for IronLedger.
%%%
%%% This gen_server maintains a registry of named background jobs and provides
%%% an explicit-trigger API so that jobs can be called from tests or operator
%%% tooling without depending on wall-clock scheduling.
%%%
%%% == Job lifecycle ==
%%%
%%% Every job has a name (atom), an MFA handler, an optional recurring schedule
%%% (interval in milliseconds), and a record of the last execution time and result.
%%%
%%% Jobs are idempotent by contract: running the same job multiple times must be
%%% safe. The runner does not enforce idempotency — each job's handler is
%%% responsible for correctness.
%%%
%%% == Built-in jobs ==
%%%
%%% <ul>
%%% <li>`daily_interest` — posts one day of interest accruals to the ledger via
%%%     `cb_interest_posting:process_daily_accruals/0`.</li>
%%% <li>`maturity_check` — closes accruals whose end_date has passed via
%%%     `cb_interest_accrual:process_expired_accruals/0`.</li>
%%% <li>`fee_assessment` — placeholder for fee charging (noop until Task 9).</li>
%%% <li>`webhook_retry` — placeholder for webhook retry delivery (noop until Task 8).</li>
%%% <li>`statement_generation` — placeholder for statement assembly (noop until Task 9).</li>
%%% </ul>
%%%
%%% == Usage from tests ==
%%%
%%% ```
%%% {ok, Count} = cb_jobs:run(daily_interest),
%%% Jobs        = cb_jobs:list_jobs(),
%%% {ok, Info}  = cb_jobs:last_run(daily_interest).
%%% ```
%%%
%%% == Scheduling ==
%%%
%%% ```
%%% ok = cb_jobs:schedule(daily_interest, 86400000),   %% once per day
%%% ok = cb_jobs:cancel_schedule(daily_interest).
%%% ```

-module(cb_jobs).
-behaviour(gen_server).

-export([start_link/0, start/0]).
-export([run/1, run_all/0, list_jobs/0, last_run/1, schedule/2, cancel_schedule/1]).
%% Exported so it can be used as an MFA handler by builtin_jobs/0
-export([noop_job/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-define(SERVER, ?MODULE).

-record(job, {
    name        :: atom(),
    handler     :: {atom(), atom(), [any()]},
    schedule    :: pos_integer() | undefined,
    timer_ref   :: reference() | undefined,
    last_run_at :: integer() | undefined,
    last_result :: term()
}).

-type job_name() :: atom().
-type job_info() :: #{
    name        := job_name(),
    last_run_at := integer() | undefined,
    last_result := term()
}.

%% =============================================================================
%% Public API
%% =============================================================================

-spec start_link() -> {ok, pid()} | {error, any()}.
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%% @doc Start the server without linking to the caller.
%%
%% Intended for use in test suites where the calling process (e.g. an
%% init_per_suite callback) exits after setup — a plain start keeps the
%% server alive for the lifetime of the test run.
-spec start() -> {ok, pid()} | {error, any()}.
start() ->
    gen_server:start({local, ?SERVER}, ?MODULE, [], []).

%% @doc Run a registered job immediately by name.
%%
%% Returns the job handler's result, or `{error, job_not_found}` if the name
%% is not registered. Exceptions thrown by the handler are caught and returned
%% as `{error, {Class, Reason}}`.
-spec run(job_name()) -> {ok, term()} | {error, term()}.
run(JobName) ->
    gen_server:call(?SERVER, {run, JobName}, 30000).

%% @doc Run every registered job sequentially and return results.
%%
%% Returns a list of `{JobName, Result}` tuples. Order is not guaranteed.
-spec run_all() -> [{job_name(), {ok, term()} | {error, term()}}].
run_all() ->
    gen_server:call(?SERVER, run_all, 60000).

%% @doc List all registered jobs with their last execution metadata.
-spec list_jobs() -> [job_info()].
list_jobs() ->
    gen_server:call(?SERVER, list_jobs).

%% @doc Return the last execution metadata for a single job.
-spec last_run(job_name()) -> {ok, job_info()} | {error, not_found}.
last_run(JobName) ->
    gen_server:call(?SERVER, {last_run, JobName}).

%% @doc Schedule a job to run automatically every `IntervalMs` milliseconds.
%%
%% The first execution fires after one interval. If the job is already scheduled
%% the existing timer is cancelled and replaced.
-spec schedule(job_name(), pos_integer()) -> ok | {error, not_found}.
schedule(JobName, IntervalMs) ->
    gen_server:call(?SERVER, {schedule, JobName, IntervalMs}).

%% @doc Cancel automatic scheduling for a job.
%%
%% The job can still be triggered explicitly via `run/1`.
-spec cancel_schedule(job_name()) -> ok | {error, not_found}.
cancel_schedule(JobName) ->
    gen_server:call(?SERVER, {cancel_schedule, JobName}).

%% @doc Placeholder handler for jobs not yet implemented.
-spec noop_job() -> {ok, noop}.
noop_job() ->
    {ok, noop}.

%% =============================================================================
%% gen_server callbacks
%% =============================================================================

-spec init([]) -> {ok, #{job_name() => #job{}}}.
init([]) ->
    State = lists:foldl(fun(J, Acc) ->
        maps:put(J#job.name, J, Acc)
    end, #{}, builtin_jobs()),
    {ok, State}.

handle_call({run, JobName}, _From, State) ->
    case maps:find(JobName, State) of
        error ->
            {reply, {error, job_not_found}, State};
        {ok, Job} ->
            {Result, UpdatedJob} = execute_job(Job),
            {reply, Result, maps:put(JobName, UpdatedJob, State)}
    end;

handle_call(run_all, _From, State) ->
    {Results, NewState} = maps:fold(fun(Name, Job, {Acc, S}) ->
        {Result, UpdatedJob} = execute_job(Job),
        {[{Name, Result} | Acc], maps:put(Name, UpdatedJob, S)}
    end, {[], State}, State),
    {reply, Results, NewState};

handle_call(list_jobs, _From, State) ->
    Infos = [job_to_info(J) || J <- maps:values(State)],
    {reply, Infos, State};

handle_call({last_run, JobName}, _From, State) ->
    case maps:find(JobName, State) of
        error ->
            {reply, {error, not_found}, State};
        {ok, Job} ->
            {reply, {ok, job_to_info(Job)}, State}
    end;

handle_call({schedule, JobName, IntervalMs}, _From, State) ->
    case maps:find(JobName, State) of
        error ->
            {reply, {error, not_found}, State};
        {ok, Job} ->
            cancel_timer(Job#job.timer_ref),
            Ref = erlang:send_after(IntervalMs, self(), {run_job, JobName}),
            Updated = Job#job{schedule = IntervalMs, timer_ref = Ref},
            {reply, ok, maps:put(JobName, Updated, State)}
    end;

handle_call({cancel_schedule, JobName}, _From, State) ->
    case maps:find(JobName, State) of
        error ->
            {reply, {error, not_found}, State};
        {ok, Job} ->
            cancel_timer(Job#job.timer_ref),
            Updated = Job#job{schedule = undefined, timer_ref = undefined},
            {reply, ok, maps:put(JobName, Updated, State)}
    end;

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_call}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({run_job, JobName}, State) ->
    case maps:find(JobName, State) of
        error ->
            {noreply, State};
        {ok, Job} ->
            {_Result, Updated0} = execute_job(Job),
            %% Reschedule if still configured
            Updated = case Updated0#job.schedule of
                undefined ->
                    Updated0#job{timer_ref = undefined};
                Ms ->
                    Ref = erlang:send_after(Ms, self(), {run_job, JobName}),
                    Updated0#job{timer_ref = Ref}
            end,
            {noreply, maps:put(JobName, Updated, State)}
    end;

handle_info(_Info, State) ->
    {noreply, State}.

-spec terminate(any(), #{job_name() => #job{}}) -> ok.
terminate(_Reason, State) ->
    maps:foreach(fun(_, J) -> cancel_timer(J#job.timer_ref) end, State),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% =============================================================================
%% Internal helpers
%% =============================================================================

-dialyzer({nowarn_function, builtin_jobs/0}).
-spec builtin_jobs() -> [#job{}].
builtin_jobs() ->
    [
        #job{
            name        = daily_interest,
            handler     = {cb_interest_posting, run_job, []},
            schedule    = undefined,
            timer_ref   = undefined,
            last_run_at = undefined,
            last_result = undefined
        },
        #job{
            name        = maturity_check,
            handler     = {cb_interest_accrual, process_expired_accruals, []},
            schedule    = undefined,
            timer_ref   = undefined,
            last_run_at = undefined,
            last_result = undefined
        },
        #job{
            name        = fee_assessment,
            handler     = {cb_jobs, noop_job, []},
            schedule    = undefined,
            timer_ref   = undefined,
            last_run_at = undefined,
            last_result = undefined
        },
        #job{
            name        = webhook_retry,
            handler     = {cb_webhooks, retry_failed_deliveries, []},
            schedule    = undefined,
            timer_ref   = undefined,
            last_run_at = undefined,
            last_result = undefined
        },
        #job{
            name        = statement_generation,
            handler     = {cb_jobs, noop_job, []},
            schedule    = undefined,
            timer_ref   = undefined,
            last_run_at = undefined,
            last_result = undefined
        }
    ].

-dialyzer({nowarn_function, execute_job/1}).
-spec execute_job(#job{}) -> {{ok, term()} | {error, term()}, #job{}}.
execute_job(Job) ->
    {M, F, A} = Job#job.handler,
    Result = try
        apply(M, F, A)
    catch
        Class:Reason ->
            {error, {Class, Reason}}
    end,
    Now = erlang:system_time(millisecond),
    {Result, Job#job{last_run_at = Now, last_result = Result}}.

-spec job_to_info(#job{}) -> job_info().
job_to_info(J) ->
    #{
        name        => J#job.name,
        last_run_at => J#job.last_run_at,
        last_result => J#job.last_result
    }.

-spec cancel_timer(reference() | undefined) -> ok.
cancel_timer(undefined) -> ok;
cancel_timer(Ref)       -> _ = erlang:cancel_timer(Ref), ok.
