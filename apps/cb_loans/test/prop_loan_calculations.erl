-module(prop_loan_calculations).

-include_lib("proper/include/proper.hrl").

-export([
    prop_zero_rate_payment_matches_ceiling_division/0,
    prop_total_interest_matches_payment_schedule/0,
    prop_outstanding_balance_stays_within_bounds/0,
    prop_total_repayment_covers_principal/0,
    prop_interest_portion_non_negative/0,
    prop_principal_portion_non_negative/0,
    prop_flat_interest_scales_with_term/0
]).

-spec prop_zero_rate_payment_matches_ceiling_division() -> term().
prop_zero_rate_payment_matches_ceiling_division() ->
    ?FORALL({Principal, TermMonths}, {valid_amount(), valid_term()},
        begin
            {ok, Payment} = cb_loan_calculations:calculate_monthly_payment(Principal, TermMonths, 0),
            Payment =:= ceil_div(Principal, TermMonths)
        end
    ).

-spec prop_total_interest_matches_payment_schedule() -> term().
prop_total_interest_matches_payment_schedule() ->
    ?FORALL({Principal, TermMonths, AnnualRateBps}, {valid_amount(), valid_term(), valid_rate()},
        begin
            {ok, Payment} = cb_loan_calculations:calculate_monthly_payment(Principal, TermMonths, AnnualRateBps),
            {ok, TotalInterest} = cb_loan_calculations:calculate_total_interest(Principal, TermMonths, AnnualRateBps),
            TotalInterest =:= (Payment * TermMonths) - Principal andalso
            Payment >= ceil_div(Principal, TermMonths)
        end
    ).

-spec prop_outstanding_balance_stays_within_bounds() -> term().
prop_outstanding_balance_stays_within_bounds() ->
    ?FORALL({Principal, TotalPaid}, {valid_amount(), range(0, 2000000)},
        begin
            Outstanding = cb_loan_calculations:calculate_outstanding_balance(Principal, TotalPaid, 0),
            Outstanding >= 0 andalso Outstanding =< Principal
        end
    ).

%% Property: total repayment (payment × term) always covers principal
-spec prop_total_repayment_covers_principal() -> term().
prop_total_repayment_covers_principal() ->
    ?FORALL({Principal, TermMonths, AnnualRateBps}, {valid_amount(), valid_term(), valid_rate()},
        begin
            {ok, Payment} = cb_loan_calculations:calculate_monthly_payment(Principal, TermMonths, AnnualRateBps),
            Payment * TermMonths >= Principal
        end
    ).

%% Property: interest portion is always non-negative for valid inputs
-spec prop_interest_portion_non_negative() -> term().
prop_interest_portion_non_negative() ->
    ?FORALL({Balance, AnnualRateBps}, {valid_amount(), valid_rate()},
        begin
            InterestPortion = cb_loan_calculations:calculate_interest_portion(Balance, 0, AnnualRateBps),
            InterestPortion >= 0
        end
    ).

%% Property: principal portion is always non-negative for valid inputs
-spec prop_principal_portion_non_negative() -> term().
prop_principal_portion_non_negative() ->
    ?FORALL({TotalPayment, InterestPortion},
        {valid_amount(), range(0, 1000000)},
        begin
            Principal = cb_loan_calculations:calculate_principal_portion(TotalPayment, InterestPortion, 0),
            Principal >= 0
        end
    ).

%% Property: flat interest scales monotonically with term length
-spec prop_flat_interest_scales_with_term() -> term().
prop_flat_interest_scales_with_term() ->
    ?FORALL({Principal, AnnualRateBps, TermA, ExtraMonths},
        {valid_amount(), valid_rate(), valid_term(), range(0, 60)},
        begin
            TermB = TermA + ExtraMonths,
            FlatA = cb_loan_calculations:calculate_flat_interest(Principal, TermA, AnnualRateBps),
            FlatB = cb_loan_calculations:calculate_flat_interest(Principal, TermB, AnnualRateBps),
            FlatA >= 0 andalso FlatB >= FlatA
        end
    ).

valid_amount() ->
    range(1, 1000000).

valid_term() ->
    range(1, 360).

valid_rate() ->
    range(0, 10000).

ceil_div(Numerator, Denominator) ->
    (Numerator + Denominator - 1) div Denominator.
