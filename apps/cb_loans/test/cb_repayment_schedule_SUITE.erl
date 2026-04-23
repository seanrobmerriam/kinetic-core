-module(cb_repayment_schedule_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").
-include("loan.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1]).
-export([
    declining_balance_three_months/1,
    flat_rate_three_months/1,
    zero_interest_declining/1,
    single_month_declining/1,
    single_month_flat/1,
    due_dates_increment_by_month/1,
    invalid_amount_returns_error/1,
    invalid_term_returns_error/1,
    installment_count_matches_term/1,
    final_installment_balance_is_zero/1
]).

all() ->
    [
        declining_balance_three_months,
        flat_rate_three_months,
        zero_interest_declining,
        single_month_declining,
        single_month_flat,
        due_dates_increment_by_month,
        invalid_amount_returns_error,
        invalid_term_returns_error,
        installment_count_matches_term,
        final_installment_balance_is_zero
    ].

init_per_suite(Config) ->
    {ok, _} = application:ensure_all_started(cb_loans),
    Config.

end_per_suite(_Config) ->
    ok = application:stop(cb_loans),
    ok.

%% ============================================================
%% Declining balance tests
%% ============================================================

%% Verified test vector: 10 000 principal, 3 months, 12 % annual (1200 bps)
declining_balance_three_months(_Config) ->
    {ok, [I1, I2, I3]} = cb_repayment_schedule:generate_schedule(10000, 3, 1200, declining, 0),

    %% Month 1
    ?assertEqual(1,    I1#installment.month),
    ?assertEqual(0,    I1#installment.due_date),
    ?assertEqual(3401, I1#installment.payment),
    ?assertEqual(100,  I1#installment.interest),
    ?assertEqual(3301, I1#installment.principal),
    ?assertEqual(6699, I1#installment.balance),

    %% Month 2
    ?assertEqual(2,    I2#installment.month),
    ?assertEqual(67,   I2#installment.interest),
    ?assertEqual(3334, I2#installment.principal),
    ?assertEqual(3401, I2#installment.payment),
    ?assertEqual(3365, I2#installment.balance),

    %% Month 3 — last installment clears residual balance exactly
    ?assertEqual(3,    I3#installment.month),
    ?assertEqual(34,   I3#installment.interest),
    ?assertEqual(3365, I3#installment.principal),
    ?assertEqual(3399, I3#installment.payment),
    ?assertEqual(0,    I3#installment.balance),
    ok.

%% ============================================================
%% Flat rate tests
%% ============================================================

%% Verified test vector: 10 000 principal, 3 months, 12 % annual (1200 bps)
flat_rate_three_months(_Config) ->
    {ok, [I1, I2, I3]} = cb_repayment_schedule:generate_schedule(10000, 3, 1200, flat, 0),

    %% Month 1
    ?assertEqual(1,    I1#installment.month),
    ?assertEqual(0,    I1#installment.due_date),
    ?assertEqual(3434, I1#installment.payment),
    ?assertEqual(100,  I1#installment.interest),
    ?assertEqual(3334, I1#installment.principal),
    ?assertEqual(6666, I1#installment.balance),

    %% Month 2
    ?assertEqual(2,    I2#installment.month),
    ?assertEqual(3434, I2#installment.payment),
    ?assertEqual(100,  I2#installment.interest),
    ?assertEqual(3334, I2#installment.principal),
    ?assertEqual(3332, I2#installment.balance),

    %% Month 3 — last installment absorbs remainder
    ?assertEqual(3,    I3#installment.month),
    ?assertEqual(3432, I3#installment.payment),
    ?assertEqual(100,  I3#installment.interest),
    ?assertEqual(3332, I3#installment.principal),
    ?assertEqual(0,    I3#installment.balance),
    ok.

%% ============================================================
%% Zero interest
%% ============================================================

%% With 0 % interest, all payments are equal principal-only instalments
zero_interest_declining(_Config) ->
    {ok, [I1, I2, I3]} = cb_repayment_schedule:generate_schedule(3000, 3, 0, declining, 0),

    ?assertEqual(0, I1#installment.interest),
    ?assertEqual(0, I2#installment.interest),
    ?assertEqual(0, I3#installment.interest),

    ?assertEqual(1000, I1#installment.principal),
    ?assertEqual(1000, I2#installment.principal),
    ?assertEqual(1000, I3#installment.principal),

    ?assertEqual(2000, I1#installment.balance),
    ?assertEqual(1000, I2#installment.balance),
    ?assertEqual(0,    I3#installment.balance),
    ok.

%% ============================================================
%% Single-month edge cases
%% ============================================================

single_month_declining(_Config) ->
    {ok, [I]} = cb_repayment_schedule:generate_schedule(5000, 1, 1200, declining, 0),
    ?assertEqual(1,    I#installment.month),
    ?assertEqual(0,    I#installment.balance),
    %% Interest for one month at 12 % on 5000 = round(5000 * 1200 / 120000) = 50
    ?assertEqual(50,   I#installment.interest),
    ?assertEqual(5000, I#installment.principal),
    ?assertEqual(5050, I#installment.payment),
    ok.

single_month_flat(_Config) ->
    {ok, [I]} = cb_repayment_schedule:generate_schedule(5000, 1, 1200, flat, 0),
    ?assertEqual(1,    I#installment.month),
    ?assertEqual(0,    I#installment.balance),
    %% calculate_flat_interest(5000, 1, 1200) = round(5000 * 1200 * 1 / 120000) = 50
    ?assertEqual(50,   I#installment.interest),
    ?assertEqual(5000, I#installment.principal),
    ?assertEqual(5050, I#installment.payment),
    ok.

%% ============================================================
%% Due date propagation
%% ============================================================

due_dates_increment_by_month(_Config) ->
    FirstDate = 1000000000,
    MsPerMonth = 30 * 24 * 60 * 60 * 1000,
    {ok, [I1, I2, I3]} = cb_repayment_schedule:generate_schedule(
        6000, 3, 600, declining, FirstDate),
    ?assertEqual(FirstDate,               I1#installment.due_date),
    ?assertEqual(FirstDate + MsPerMonth,  I2#installment.due_date),
    ?assertEqual(FirstDate + 2*MsPerMonth, I3#installment.due_date),
    ok.

%% ============================================================
%% Error propagation
%% ============================================================

invalid_amount_returns_error(_Config) ->
    ?assertEqual({error, invalid_amount},
                 cb_repayment_schedule:generate_schedule(0, 3, 1200, declining, 0)),
    ?assertEqual({error, invalid_amount},
                 cb_repayment_schedule:generate_schedule(0, 3, 1200, flat, 0)),
    ok.

invalid_term_returns_error(_Config) ->
    ?assertEqual({error, invalid_term},
                 cb_repayment_schedule:generate_schedule(5000, 0, 1200, declining, 0)),
    ?assertEqual({error, invalid_term},
                 cb_repayment_schedule:generate_schedule(5000, 0, 1200, flat, 0)),
    ok.

%% ============================================================
%% Structural invariants
%% ============================================================

installment_count_matches_term(_Config) ->
    Term = 12,
    {ok, Schedule} = cb_repayment_schedule:generate_schedule(12000, Term, 800, declining, 0),
    ?assertEqual(Term, length(Schedule)),
    ok.

final_installment_balance_is_zero(_Config) ->
    {ok, ScheduleDeclining} = cb_repayment_schedule:generate_schedule(
        20000, 6, 1500, declining, 0),
    {ok, ScheduleFlat} = cb_repayment_schedule:generate_schedule(
        20000, 6, 1500, flat, 0),
    LastDeclining = lists:last(ScheduleDeclining),
    LastFlat      = lists:last(ScheduleFlat),
    ?assertEqual(0, LastDeclining#installment.balance),
    ?assertEqual(0, LastFlat#installment.balance),
    ok.
