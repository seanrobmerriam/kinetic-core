%%%
%%% @doc Pure integer-safe interest calculation functions for Kinetic Core.
%%%
%%% All annual rates are expressed in basis points. Daily rates are represented
%%% internally as parts per billion so daily accrual can remain integer-safe.
%%%
-module(cb_interest).

-include("cb_interest.hrl").

-export([
    calculate_daily_rate/1,
    calculate_interest/3,
    calculate_compound_interest/4,
    basis_points_to_float/1,
    float_to_basis_points/1
]).

-define(DAYS_IN_YEAR, 365).
-define(BASIS_POINTS_FACTOR, 10000).
-define(PPB_SCALE, 1000000000).
-define(PPB_PER_BASIS_POINT, 100000).

-spec calculate_daily_rate(interest_rate()) -> daily_rate_ppb().
calculate_daily_rate(AnnualRateBps)
        when is_integer(AnnualRateBps), AnnualRateBps >= 0 ->
    (AnnualRateBps * ?PPB_PER_BASIS_POINT) div ?DAYS_IN_YEAR.

-spec calculate_interest(non_neg_integer(), daily_rate_ppb(), non_neg_integer()) -> non_neg_integer().
calculate_interest(Balance, _DailyRatePpb, 0)
        when is_integer(Balance), Balance >= 0 ->
    0;
calculate_interest(Balance, DailyRatePpb, Days)
        when is_integer(Balance), Balance >= 0,
             is_integer(DailyRatePpb), DailyRatePpb >= 0,
             is_integer(Days), Days > 0 ->
    (Balance * DailyRatePpb * Days) div ?PPB_SCALE.

-spec calculate_compound_interest(non_neg_integer(), interest_rate(), non_neg_integer(), compounding_period()) ->
    non_neg_integer().
calculate_compound_interest(InitialBalance, _AnnualRateBps, 0, _CompoundingPeriod)
        when is_integer(InitialBalance), InitialBalance >= 0 ->
    InitialBalance;
calculate_compound_interest(InitialBalance, AnnualRateBps, Days, CompoundingPeriod)
        when is_integer(InitialBalance), InitialBalance >= 0,
             is_integer(AnnualRateBps), AnnualRateBps >= 0,
             is_integer(Days), Days >= 0 ->
    DailyRatePpb = calculate_daily_rate(AnnualRateBps),
    PeriodDays = period_days(CompoundingPeriod),
    compound_over_periods(InitialBalance, DailyRatePpb, Days, PeriodDays).

-spec basis_points_to_float(non_neg_integer()) -> float().
basis_points_to_float(Bps) when is_integer(Bps), Bps >= 0 ->
    Bps / ?BASIS_POINTS_FACTOR.

-spec float_to_basis_points(float()) -> non_neg_integer().
float_to_basis_points(Rate) when is_float(Rate), Rate >= 0 ->
    round(Rate * ?BASIS_POINTS_FACTOR).

-spec period_days(compounding_period()) -> 1 | 30 | 91 | 365.
period_days(daily) ->
    1;
period_days(monthly) ->
    30;
period_days(quarterly) ->
    91;
period_days(annually) ->
    ?DAYS_IN_YEAR.

-spec compound_over_periods(non_neg_integer(), daily_rate_ppb(), non_neg_integer(), 1 | 30 | 91 | 365) ->
    non_neg_integer().
compound_over_periods(Balance, _DailyRatePpb, 0, _PeriodDays) ->
    Balance;
compound_over_periods(Balance, DailyRatePpb, DaysRemaining, PeriodDays) ->
    DaysThisPeriod = min(DaysRemaining, PeriodDays),
    Interest = calculate_interest(Balance, DailyRatePpb, DaysThisPeriod),
    compound_over_periods(Balance + Interest, DailyRatePpb, DaysRemaining - DaysThisPeriod, PeriodDays).
