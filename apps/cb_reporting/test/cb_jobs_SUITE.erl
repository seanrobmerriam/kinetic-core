%%% @doc Common Test suite for the cb_jobs scheduled job runner.
%%%
%%% Tests cover:
%%% <ul>
%%% <li>Listing and introspecting registered jobs</li>
%%% <li>Running individual and all jobs explicitly (no wall-clock wait)</li>
%%% <li>last_run metadata being updated after execution</li>
%%% <li>Unknown job error handling</li>
%%% <li>Timer-based scheduling and cancellation</li>
%%% <li>Maturity check closing expired accruals</li>
%%% </ul>

-module(cb_jobs_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").
-include_lib("cb_interest/include/cb_interest.hrl").
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([all/0, groups/0, init_per_suite/1, end_per_suite/1,
         init_per_testcase/2, end_per_testcase/2]).

-export([
    list_jobs_returns_all_registered/1,
    run_noop_job_ok/1,
    run_daily_interest_no_accruals/1,
    run_maturity_check_no_expired/1,
    run_maturity_check_closes_expired/1,
    run_unknown_job_returns_error/1,
    run_all_returns_all_results/1,
    last_run_undefined_before_first_run/1,
    last_run_populated_after_run/1,
    last_run_unknown_job_returns_error/1,
    schedule_job_fires_automatically/1,
    cancel_schedule_stops_automatic_runs/1
]).

all() ->
    [{group, basic}, {group, interest}, {group, scheduling}].

groups() ->
    [
        {basic, [sequence], [
            list_jobs_returns_all_registered,
            run_noop_job_ok,
            run_unknown_job_returns_error,
            run_all_returns_all_results,
            last_run_undefined_before_first_run,
            last_run_populated_after_run,
            last_run_unknown_job_returns_error
        ]},
        {interest, [sequence], [
            run_daily_interest_no_accruals,
            run_maturity_check_no_expired,
            run_maturity_check_closes_expired
        ]},
        {scheduling, [sequence], [
            schedule_job_fires_automatically,
            cancel_schedule_stops_automatic_runs
        ]}
    ].

init_per_suite(Config) ->
    mnesia:start(),
    create_tables(),
    start_cb_jobs(),
    Config.

end_per_suite(_Config) ->
    stop_cb_jobs(),
    mnesia:stop(),
    mnesia:delete_schema([node()]),
    ok.

init_per_testcase(_TestCase, Config) ->
    lists:foreach(fun mnesia:clear_table/1,
                  [party, account, transaction, ledger_entry, interest_accrual]),
    Config.

end_per_testcase(_TestCase, _Config) ->
    ok.

%% =============================================================================
%% Basic group
%% =============================================================================

%% Five built-in jobs must be present at startup.
list_jobs_returns_all_registered(_Config) ->
    Jobs = cb_jobs:list_jobs(),
    Names = [maps:get(name, J) || J <- Jobs],
    ?assert(lists:member(daily_interest, Names)),
    ?assert(lists:member(maturity_check, Names)),
    ?assert(lists:member(fee_assessment, Names)),
    ?assert(lists:member(webhook_retry, Names)),
    ?assert(lists:member(statement_generation, Names)),
    ?assertEqual(5, length(Jobs)),
    ok.

%% Noop placeholder jobs return {ok, noop}.
run_noop_job_ok(_Config) ->
    ?assertEqual({ok, noop}, cb_jobs:run(fee_assessment)),
    ?assertEqual({ok, noop}, cb_jobs:run(webhook_retry)),
    ?assertEqual({ok, noop}, cb_jobs:run(statement_generation)),
    ok.

%% Unregistered job name returns {error, job_not_found}.
run_unknown_job_returns_error(_Config) ->
    ?assertEqual({error, job_not_found}, cb_jobs:run(nonexistent_job)),
    ok.

%% run_all/0 returns one result per registered job.
run_all_returns_all_results(_Config) ->
    Results = cb_jobs:run_all(),
    ?assertEqual(5, length(Results)),
    Names = [N || {N, _} <- Results],
    ?assert(lists:member(daily_interest, Names)),
    ?assert(lists:member(maturity_check, Names)),
    ok.

%% Before any run, last_run_at and last_result are undefined.
last_run_undefined_before_first_run(_Config) ->
    %% Restart a fresh server to guarantee a clean slate.
    stop_cb_jobs(),
    start_cb_jobs(),
    {ok, Info} = cb_jobs:last_run(fee_assessment),
    ?assertEqual(undefined, maps:get(last_run_at, Info)),
    ?assertEqual(undefined, maps:get(last_result, Info)),
    ok.

%% After run/1, last_run_at is a timestamp and last_result is the return value.
last_run_populated_after_run(_Config) ->
    Before = erlang:system_time(millisecond),
    {ok, noop} = cb_jobs:run(fee_assessment),
    {ok, Info} = cb_jobs:last_run(fee_assessment),
    LastRunAt = maps:get(last_run_at, Info),
    ?assert(is_integer(LastRunAt)),
    ?assert(LastRunAt >= Before),
    ?assertEqual({ok, noop}, maps:get(last_result, Info)),
    ok.

%% last_run/1 for an unknown job returns {error, not_found}.
last_run_unknown_job_returns_error(_Config) ->
    ?assertEqual({error, not_found}, cb_jobs:last_run(mystery_job)),
    ok.

%% =============================================================================
%% Interest group — requires Mnesia tables
%% =============================================================================

%% With no active accruals, daily_interest processes zero accounts.
run_daily_interest_no_accruals(_Config) ->
    ?assertEqual({ok, 0}, cb_jobs:run(daily_interest)),
    ok.

%% With active accruals that have no end_date, maturity_check closes none.
run_maturity_check_no_expired(_Config) ->
    Account = create_test_account(),
    {ok, _} = cb_interest_accrual:start_accrual(
        Account#account.account_id, <<"p1">>, 10000, 500),
    ?assertEqual({ok, 0}, cb_jobs:run(maturity_check)),
    ok.

%% Accruals with end_date in the past are closed by the maturity_check job.
run_maturity_check_closes_expired(_Config) ->
    Account = create_test_account(),
    PastTimestamp = erlang:system_time(millisecond) - 1000,
    {ok, Accrual} = cb_interest_accrual:start_accrual(
        Account#account.account_id, <<"p1">>, 10000, 500),
    %% Manually set end_date to the past to simulate a matured term.
    set_accrual_end_date(Accrual#interest_accrual.accrual_id, PastTimestamp),

    {ok, Closed} = cb_jobs:run(maturity_check),
    ?assertEqual(1, Closed),

    {ok, Updated} = cb_interest_accrual:get_accrual(Accrual#interest_accrual.accrual_id),
    ?assertEqual(closed, Updated#interest_accrual.status),
    ok.

%% =============================================================================
%% Scheduling group
%% =============================================================================

%% A scheduled job fires automatically after the configured interval.
schedule_job_fires_automatically(_Config) ->
    stop_cb_jobs(),
    start_cb_jobs(),

    ok = cb_jobs:schedule(fee_assessment, 50),
    timer:sleep(200),

    {ok, Info} = cb_jobs:last_run(fee_assessment),
    ?assert(maps:get(last_run_at, Info) =/= undefined),
    ok.

%% Cancelling a schedule prevents further automatic runs.
cancel_schedule_stops_automatic_runs(_Config) ->
    stop_cb_jobs(),
    start_cb_jobs(),

    ok = cb_jobs:schedule(fee_assessment, 50),
    ok = cb_jobs:cancel_schedule(fee_assessment),

    %% Give enough time that the job *would* have fired if not cancelled.
    timer:sleep(200),

    {ok, Info} = cb_jobs:last_run(fee_assessment),
    %% last_run_at is still undefined because the job never executed.
    ?assertEqual(undefined, maps:get(last_run_at, Info)),
    ok.

%% =============================================================================
%% Internal helpers
%% =============================================================================

%% Start cb_jobs without linking to the calling process (so CT's init_per_suite
%% process can exit without killing the server).  Handle the case where the OTP
%% application has already started the server under a supervisor.
start_cb_jobs() ->
    case cb_jobs:start() of
        {ok, _}                        -> ok;
        {error, {already_started, _}}  -> ok
    end.

stop_cb_jobs() ->
    case whereis(cb_jobs) of
        undefined -> ok;
        _Pid      -> gen_server:stop(cb_jobs)
    end.

create_test_account() ->
    Unique = integer_to_binary(erlang:unique_integer([positive])),
    Email  = <<"jobtest", Unique/binary, "@example.com">>,
    {ok, Party}   = cb_party:create_party(<<"Job Test ", Unique/binary>>, Email),
    {ok, Account} = cb_accounts:create_account(
        Party#party.party_id, <<"Job Account ", Unique/binary>>, 'USD'),
    Account.

%% Force-set end_date on an accrual so we can simulate a matured term.
set_accrual_end_date(AccrualId, EndDate) ->
    F = fun() ->
        [A] = mnesia:read(interest_accrual, AccrualId, write),
        mnesia:write(A#interest_accrual{end_date = EndDate})
    end,
    {atomic, ok} = mnesia:transaction(F),
    ok.

create_tables() ->
    Tables = [party, account, transaction, ledger_entry, interest_accrual],
    lists:foreach(fun create_table/1, Tables).

create_table(interest_accrual) ->
    case mnesia:create_table(interest_accrual, [
        {ram_copies, [node()]},
        {attributes, record_info(fields, interest_accrual)},
        {index, [account_id, status]}
    ]) of
        {atomic, ok}              -> ok;
        {aborted, {already_exists, _}} -> ok
    end;
create_table(Name) ->
    Spec = table_spec(Name),
    case mnesia:create_table(Name, Spec) of
        {atomic, ok}              -> ok;
        {aborted, {already_exists, _}} -> ok
    end.

table_spec(party) ->
    [{ram_copies, [node()]},
     {attributes, record_info(fields, party)},
     {index, [email, status]}];
table_spec(account) ->
    [{ram_copies, [node()]},
     {attributes, record_info(fields, account)},
     {index, [party_id, status]}];
table_spec(transaction) ->
    [{ram_copies, [node()]},
     {attributes, record_info(fields, transaction)},
     {index, [idempotency_key, source_account_id, dest_account_id, status]}];
table_spec(ledger_entry) ->
    [{ram_copies, [node()]},
     {attributes, record_info(fields, ledger_entry)},
     {index, [txn_id, account_id]}].
