-module(prop_repayment_schedule).

-include_lib("proper/include/proper.hrl").
-include_lib("cb_loans/include/loan.hrl").

-export([
    prop_declining_schedule_has_exact_length/0,
    prop_flat_schedule_has_exact_length/0,
    prop_declining_schedule_all_balances_non_negative/0,
    prop_declining_schedule_final_balance_is_zero/0,
    prop_schedule_due_dates_strictly_increasing/0
]).

-define(EPOCH_MS, 1700000000000).

%% Property: a declining schedule always contains exactly TermMonths installments
-spec prop_declining_schedule_has_exact_length() -> term().
prop_declining_schedule_has_exact_length() ->
    ?FORALL({Principal, TermMonths, AnnualRateBps},
        {valid_amount(), valid_term(), valid_rate()},
        begin
            {ok, Schedule} = cb_repayment_schedule:generate_schedule(
                Principal, TermMonths, AnnualRateBps, declining, ?EPOCH_MS),
            length(Schedule) =:= TermMonths
        end
    ).

%% Property: a flat schedule always contains exactly TermMonths installments
-spec prop_flat_schedule_has_exact_length() -> term().
prop_flat_schedule_has_exact_length() ->
    ?FORALL({Principal, TermMonths, AnnualRateBps},
        {valid_amount(), valid_term(), valid_rate()},
        begin
            {ok, Schedule} = cb_repayment_schedule:generate_schedule(
                Principal, TermMonths, AnnualRateBps, flat, ?EPOCH_MS),
            length(Schedule) =:= TermMonths
        end
    ).

%% Property: every installment in a declining schedule has a non-negative remaining balance
-spec prop_declining_schedule_all_balances_non_negative() -> term().
prop_declining_schedule_all_balances_non_negative() ->
    ?FORALL({Principal, TermMonths, AnnualRateBps},
        {valid_amount(), valid_term(), valid_rate()},
        begin
            {ok, Schedule} = cb_repayment_schedule:generate_schedule(
                Principal, TermMonths, AnnualRateBps, declining, ?EPOCH_MS),
            lists:all(fun(I) -> I#installment.balance >= 0 end, Schedule)
        end
    ).

%% Property: the final installment of a declining schedule clears the balance to zero
-spec prop_declining_schedule_final_balance_is_zero() -> term().
prop_declining_schedule_final_balance_is_zero() ->
    ?FORALL({Principal, TermMonths, AnnualRateBps},
        {valid_amount(), valid_term(), valid_rate()},
        begin
            {ok, Schedule} = cb_repayment_schedule:generate_schedule(
                Principal, TermMonths, AnnualRateBps, declining, ?EPOCH_MS),
            Last = lists:last(Schedule),
            Last#installment.balance =:= 0
        end
    ).

%% Property: due dates in any schedule are strictly increasing
-spec prop_schedule_due_dates_strictly_increasing() -> term().
prop_schedule_due_dates_strictly_increasing() ->
    ?FORALL({Principal, TermMonths, AnnualRateBps, InterestType},
        {valid_amount(), valid_term(), valid_rate(), interest_type()},
        begin
            {ok, Schedule} = cb_repayment_schedule:generate_schedule(
                Principal, TermMonths, AnnualRateBps, InterestType, ?EPOCH_MS),
            DueDates = [I#installment.due_date || I <- Schedule],
            strictly_increasing(DueDates)
        end
    ).

%%  ─── Generators ──────────────────────────────────────────────────────────────

valid_amount() ->
    range(100, 10000000).

valid_term() ->
    range(1, 360).

valid_rate() ->
    range(0, 10000).

interest_type() ->
    elements([declining, flat]).

%%  ─── Helpers ─────────────────────────────────────────────────────────────────

-spec strictly_increasing([integer()]) -> boolean().
strictly_increasing([]) -> true;
strictly_increasing([_]) -> true;
strictly_increasing([A, B | Rest]) when A < B -> strictly_increasing([B | Rest]);
strictly_increasing(_) -> false.
