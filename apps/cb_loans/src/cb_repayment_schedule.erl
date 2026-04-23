%%%===================================================================
%%%
%%% @doc Repayment schedule engine for IronLedger loan products.
%%%
%%% Generates an ordered list of installments for a loan given its
%%% principal, term, annual interest rate, and interest type.
%%%
%%% All monetary values are integer minor units. Rates are basis points.
%%%
%%% Supports two interest types:
%%%
%%% <ul>
%%%   <li><b>declining</b>: Amortising schedule. Each month a fixed
%%%       payment is applied; the interest portion falls as the
%%%       balance reduces. The final installment is adjusted to
%%%       exactly clear the remaining balance.</li>
%%%   <li><b>flat</b>: Simple interest calculated once on the
%%%       original principal and spread evenly across all months.
%%%       Principal is distributed using ceiling division so that
%%%       any remainder lands on the last installment.</li>
%%% </ul>
%%%
%%% @end
%%%===================================================================

-module(cb_repayment_schedule).
-include("loan.hrl").

-export([generate_schedule/5]).

-define(MS_PER_MONTH, 30 * 24 * 60 * 60 * 1000).

%%--------------------------------------------------------------------
%% Public API
%%--------------------------------------------------------------------

-spec generate_schedule(
    Principal      :: pos_integer(),
    TermMonths     :: pos_integer(),
    AnnualRateBps  :: non_neg_integer(),
    InterestType   :: flat | declining,
    FirstDueDateMs :: non_neg_integer()
) -> {ok, [installment()]} | {error, atom()}.

generate_schedule(Principal, TermMonths, AnnualRateBps, declining, FirstDueDateMs) ->
    case cb_loan_calculations:calculate_monthly_payment(Principal, TermMonths, AnnualRateBps) of
        {ok, Payment} ->
            Schedule = build_declining_schedule(
                Principal, TermMonths, AnnualRateBps, Payment, FirstDueDateMs, 1, []),
            {ok, Schedule};
        Error ->
            Error
    end;

generate_schedule(Principal, TermMonths, AnnualRateBps, flat, FirstDueDateMs) ->
    case cb_loan_calculations:calculate_monthly_payment(Principal, TermMonths, AnnualRateBps) of
        {error, Reason} ->
            {error, Reason};
        {ok, _} ->
            TotalInterest = cb_loan_calculations:calculate_flat_interest(
                Principal, TermMonths, AnnualRateBps),
            RegPrincipal = ceil_div(Principal, TermMonths),
            RegInterest  = TotalInterest div TermMonths,
            Schedule = build_flat_schedule(
                Principal, TermMonths, TotalInterest, RegPrincipal, RegInterest,
                FirstDueDateMs, 1, []),
            {ok, Schedule}
    end.

%%--------------------------------------------------------------------
%% Internal helpers — declining balance
%%--------------------------------------------------------------------

-spec build_declining_schedule(
    Balance        :: non_neg_integer(),
    MonthsLeft     :: non_neg_integer(),
    AnnualRateBps  :: non_neg_integer(),
    Payment        :: pos_integer(),
    FirstDueDateMs :: non_neg_integer(),
    Month          :: pos_integer(),
    Acc            :: [installment()]
) -> [installment()].

build_declining_schedule(_Balance, 0, _Rate, _Payment, _FirstDate, _Month, Acc) ->
    lists:reverse(Acc);

build_declining_schedule(Balance, 1, AnnualRateBps, _Payment, FirstDueDateMs, Month, Acc) ->
    Interest    = cb_loan_calculations:calculate_interest_portion(Balance, Balance, AnnualRateBps),
    LastPayment = Balance + Interest,
    DueDate     = FirstDueDateMs + (Month - 1) * ?MS_PER_MONTH,
    Inst = #installment{
        month    = Month,
        due_date = DueDate,
        payment  = LastPayment,
        principal = Balance,
        interest  = Interest,
        balance   = 0
    },
    lists:reverse([Inst | Acc]);

build_declining_schedule(Balance, MonthsLeft, AnnualRateBps, Payment, FirstDueDateMs, Month, Acc) ->
    Interest   = cb_loan_calculations:calculate_interest_portion(Balance, Payment, AnnualRateBps),
    Principal  = max(0, Payment - Interest),
    NewBalance = max(0, Balance - Principal),
    DueDate    = FirstDueDateMs + (Month - 1) * ?MS_PER_MONTH,
    Inst = #installment{
        month    = Month,
        due_date = DueDate,
        payment  = Payment,
        principal = Principal,
        interest  = Interest,
        balance   = NewBalance
    },
    build_declining_schedule(
        NewBalance, MonthsLeft - 1, AnnualRateBps, Payment, FirstDueDateMs, Month + 1,
        [Inst | Acc]).

%%--------------------------------------------------------------------
%% Internal helpers — flat rate
%%--------------------------------------------------------------------

-spec build_flat_schedule(
    Balance        :: non_neg_integer(),
    MonthsLeft     :: pos_integer(),
    RemInterest    :: non_neg_integer(),
    RegPrincipal   :: pos_integer(),
    RegInterest    :: non_neg_integer(),
    FirstDueDateMs :: non_neg_integer(),
    Month          :: pos_integer(),
    Acc            :: [installment()]
) -> [installment()].

build_flat_schedule(Balance, 1, RemInterest, _RegPrincipal, _RegInterest,
                    FirstDueDateMs, Month, Acc) ->
    Payment = Balance + RemInterest,
    DueDate = FirstDueDateMs + (Month - 1) * ?MS_PER_MONTH,
    Inst = #installment{
        month    = Month,
        due_date = DueDate,
        payment  = Payment,
        principal = Balance,
        interest  = RemInterest,
        balance   = 0
    },
    lists:reverse([Inst | Acc]);

build_flat_schedule(Balance, MonthsLeft, RemInterest, RegPrincipal, RegInterest,
                    FirstDueDateMs, Month, Acc) ->
    NewBalance   = Balance - RegPrincipal,
    Payment      = RegPrincipal + RegInterest,
    DueDate      = FirstDueDateMs + (Month - 1) * ?MS_PER_MONTH,
    Inst = #installment{
        month    = Month,
        due_date = DueDate,
        payment  = Payment,
        principal = RegPrincipal,
        interest  = RegInterest,
        balance   = NewBalance
    },
    build_flat_schedule(
        NewBalance, MonthsLeft - 1, RemInterest - RegInterest, RegPrincipal, RegInterest,
        FirstDueDateMs, Month + 1, [Inst | Acc]).

%%--------------------------------------------------------------------
%% Utilities
%%--------------------------------------------------------------------

-spec ceil_div(non_neg_integer(), pos_integer()) -> non_neg_integer().
ceil_div(Numerator, Denominator) ->
    (Numerator + Denominator - 1) div Denominator.
