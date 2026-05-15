-module(prop_interest).

-include_lib("proper/include/proper.hrl").

-export([
    prop_zero_rate_produces_zero_interest/0,
    prop_daily_rate_is_monotonic/0,
    prop_compound_interest_never_below_principal/0,
    prop_simple_interest_non_negative/0,
    prop_simple_interest_monotonic_in_balance/0,
    prop_simple_interest_monotonic_in_days/0,
    prop_compound_never_below_simple/0
]).

-spec prop_zero_rate_produces_zero_interest() -> term().
prop_zero_rate_produces_zero_interest() ->
    ?FORALL({Balance, Days}, {range(0, 1000000), range(0, 3650)},
        begin
            DailyRate = cb_interest:calculate_daily_rate(0),
            0 =:= cb_interest:calculate_interest(Balance, DailyRate, Days)
        end
    ).

-spec prop_daily_rate_is_monotonic() -> term().
prop_daily_rate_is_monotonic() ->
    ?FORALL({RateA, RateB}, {range(0, 10000), range(0, 10000)},
        begin
            DailyA = cb_interest:calculate_daily_rate(RateA),
            DailyB = cb_interest:calculate_daily_rate(RateB),
            case RateA =< RateB of
                true -> DailyA =< DailyB;
                false -> DailyA >= DailyB
            end
        end
    ).

-spec prop_compound_interest_never_below_principal() -> term().
prop_compound_interest_never_below_principal() ->
    ?FORALL({Balance, Rate, Days, Period},
        {range(0, 1000000), range(0, 10000), range(0, 3650), compounding_period()},
        cb_interest:calculate_compound_interest(Balance, Rate, Days, Period) >= Balance
    ).

%% Property: simple interest is always non-negative
-spec prop_simple_interest_non_negative() -> term().
prop_simple_interest_non_negative() ->
    ?FORALL({Balance, Rate, Days},
        {range(0, 100000000), range(0, 10000), range(0, 3650)},
        begin
            DailyRate = cb_interest:calculate_daily_rate(Rate),
            cb_interest:calculate_interest(Balance, DailyRate, Days) >= 0
        end
    ).

%% Property: simple interest is monotonically non-decreasing in balance
-spec prop_simple_interest_monotonic_in_balance() -> term().
prop_simple_interest_monotonic_in_balance() ->
    ?FORALL({BalanceLow, Extra, Rate, Days},
        {range(0, 500000), range(0, 500000), range(1, 10000), range(1, 3650)},
        begin
            DailyRate = cb_interest:calculate_daily_rate(Rate),
            BalanceHigh = BalanceLow + Extra,
            cb_interest:calculate_interest(BalanceLow, DailyRate, Days) =<
            cb_interest:calculate_interest(BalanceHigh, DailyRate, Days)
        end
    ).

%% Property: simple interest is monotonically non-decreasing in number of days
-spec prop_simple_interest_monotonic_in_days() -> term().
prop_simple_interest_monotonic_in_days() ->
    ?FORALL({Balance, Rate, DaysLow, ExtraDays},
        {range(0, 1000000), range(1, 10000), range(0, 1825), range(0, 1825)},
        begin
            DailyRate = cb_interest:calculate_daily_rate(Rate),
            DaysHigh = DaysLow + ExtraDays,
            cb_interest:calculate_interest(Balance, DailyRate, DaysLow) =<
            cb_interest:calculate_interest(Balance, DailyRate, DaysHigh)
        end
    ).

%% Property: compound result is always >= simple linear result for the same inputs
-spec prop_compound_never_below_simple() -> term().
prop_compound_never_below_simple() ->
    ?FORALL({Balance, Rate, Days, Period},
        {range(1, 1000000), range(0, 10000), range(1, 3650), compounding_period()},
        begin
            Compound = cb_interest:calculate_compound_interest(Balance, Rate, Days, Period),
            DailyRate = cb_interest:calculate_daily_rate(Rate),
            Simple = Balance + cb_interest:calculate_interest(Balance, DailyRate, Days),
            Compound >= Simple
        end
    ).

compounding_period() ->
    elements([daily, monthly, quarterly, annually]).
