%%%
%%% @doc Interest calculation and accrual types for Kinetic Core core banking system.
%%%
%%% This module defines the core types and records used for interest calculation,
%%% accrual tracking, and interest posting in the Kinetic Core core banking system.
%%%
%%% == Banking Domain Concepts ==
%%%
%%% <ul>
%%% <li><b>Interest</b>: The cost of borrowing money (for loans) or the reward for saving
%%%     (for deposits). In banking, interest is calculated as a percentage of the principal
%%%     balance over time.</li>
%%%
%%% <li><b>Annual Percentage Rate (APR)</b>: The yearly interest rate expressed as a percentage.
%%%     For example, 5% APR means interest is charged at 5% per year on the outstanding balance.</li>
%%%
%%% <li><b>Annual Percentage Yield (APY)</b>: The effective annual return on an investment,
%%%     taking into account the effect of compounding interest. APY is always higher than or
%%%     equal to APR for accounts that compound interest more frequently than annually.</li>
%%%
%%% <li><b>Basis Points (bps)</b>: A unit of measure equal to 1/100th of 1 percent.
%%%     100 basis points = 1%. Basis points are commonly used in banking to express
%%%     interest rate changes precisely (e.g., "a 25 basis point rate hike").</li>
%%%
%%% <li><b>Simple Interest</b>: Interest calculated only on the original principal amount.
%%%     Formula: Interest = Principal × Rate × Time</li>
%%%
%%% <li><b>Compound Interest</b>: Interest calculated on the principal plus accumulated interest.
%%%     This is how most savings and checking accounts work. The more frequent the compounding,
%%%     the higher the effective yield (APY).</li>
%%%
%%% <li><b>Compounding Period</b>: The interval at which interest is calculated and added to
%%%     the balance. Common periods: daily, monthly, quarterly, annually.</li>
%%%
%%% <li><b>Accrual</b>: The process of accumulating interest over time before it is actually
%%%     paid or charged. Accrued interest represents interest that has been earned but not yet
%%%     posted to the account.</li>
%%%
%%% <li><b>Daily Interest Calculation</b>: Most modern banking systems calculate interest
%%%     daily based on the daily rate (APR ÷ 365 or 366 days). This provides accurate
%%%     accruals and fair interest calculation.</li>
%%% </ul>
%%%

-ifndef(CB_INTEREST_HRL).
-define(CB_INTEREST_HRL, true).

%%%
%%% @doc Interest calculation method.
%%%
%%% <b>simple</b>: Interest is calculated only on the original principal balance.
%%%     No interest is earned on previously accumulated interest.
%%%
%%% <b>compound</b>: Interest is calculated on the principal plus accumulated interest.
%%%     This is the standard method for savings and deposit accounts.
%%%
-type interest_type() :: simple | compound.

%%%
%%% @doc The frequency at which compound interest is calculated and added to the balance.
%%%
%%% <b>daily</b>: Interest compounds every day (365 periods per year). Highest APY.
%%%
%%% <b>monthly</b>: Interest compounds monthly (12 periods per year).
%%%
%%% <b>quarterly</b>: Interest compounds quarterly (4 periods per year).
%%%
%%% <b>annually</b>: Interest compounds once per year (1 period per year).
%%%
-type compounding_period() :: daily | monthly | quarterly | annually.

%%%
%%% @doc Annual interest rate represented in basis points.
%%%
%%% 100 basis points = 1.00%. 500 basis points = 5.00%.
%%%
-type interest_rate() :: non_neg_integer().

%%% @doc Daily rate represented as a fraction in parts per billion.
%%%
%%% This keeps daily accrual calculations integer-safe while preserving more
%%% precision than whole basis points per day.
%%%
-type daily_rate_ppb() :: non_neg_integer().

%%%
%%% @doc Status of an interest accrual record.
%%%
%%% <b>accruing</b>: The accrual is active and accumulating interest daily.
%%%
%%% <b>posted</b>: The accrued interest has been posted (credited or debited) to the account.
%%%
%%% <b>closed</b>: The accrual has ended (e.g., account closed, product changed).
%%%
-type accrual_status() :: accruing | posted | closed.

%%%
%%% @doc Interest accrual record tracking accumulated interest for an account.
%%%
%%% This record represents an active interest accrual for a specific account and product.
%%% It tracks the principal balance, interest rate, and accumulated interest amount.
%%%
%%% <ul>
%%% <li><b>accrual_id</b>: Unique identifier (UUID) for this accrual record.</li>
%%%
%%% <li><b>account_id</b>: The account UUID this accrual belongs to.</li>
%%%
%%% <li><b>product_id</b>: The savings/loan product UUID defining the interest terms.</li>
%%%
%%% <li><b>interest_rate</b>: The annual interest rate in basis points.</li>
%%%
%%% <li><b>daily_rate</b>: The daily rate in parts per billion.</li>
%%%
%%% <li><b>start_date</b>: Timestamp (milliseconds since epoch) when accrual began.</li>
%%%
%%% <li><b>end_date</b>: Timestamp when accrual ended, or undefined if still active.</li>
%%%
%%% <li><b>balance</b>: The principal balance on which interest is calculated (in minor units).</li>
%%%
%%% <li><b>accrued_amount</b>: Total interest accumulated but not yet posted (in minor units).</li>
%%%
%%% <li><b>status</b>: Current state of the accrual (accruing, posted, or closed).</li>
%%%
%%% <li><b>created_at</b>: Timestamp when this accrual record was created.</li>
%%% </ul>
%%%
-record(interest_accrual, {
    accrual_id     :: binary(),
    account_id     :: binary(),
    product_id     :: binary(),
    interest_rate  :: interest_rate(),
    daily_rate     :: daily_rate_ppb(),
    start_date     :: non_neg_integer(),
    end_date       :: non_neg_integer() | undefined,
    balance        :: non_neg_integer(),
    accrued_amount :: non_neg_integer(),
    status         :: accrual_status(),
    created_at     :: non_neg_integer()
}).

%%%
%%% @doc Type alias for interest_accrual record.
%%%
-type interest_accrual() :: #interest_accrual{}.

%%%
%%% @doc Interest product configuration.
%%%
%%% Defines the terms and rules for interest calculation on a product type
%%% (e.g., savings account, certificate of deposit, loan).
%%%
%%% <ul>
%%% <li><b>product_id</b>: Unique identifier for the product.</li>
%%%
%%% <li><b>interest_type</b>: Either simple or compound interest calculation.</li>
%%%
%%% <li><b>compounding_period</b>: How often compound interest is calculated.</li>
%%%
%%% <li><b>annual_rate</b>: The annual interest rate in basis points.</li>
%%% </ul>
%%%
-type interest_product() :: #{
    product_id => binary(),
    interest_type => interest_type(),
    compounding_period => compounding_period(),
    annual_rate => interest_rate()
}.

-export_type([
    interest_type/0,
    compounding_period/0,
    interest_rate/0,
    daily_rate_ppb/0,
    accrual_status/0,
    interest_accrual/0,
    interest_product/0
]).

-endif.
