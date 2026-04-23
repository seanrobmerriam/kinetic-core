%%%===================================================================
%%%
%%% @doc Loan domain types and record definitions for the IronLedger
%%%      core banking system.
%%%
%%% This module defines the core data structures for loan management,
%%% including loan products, loan accounts, and repayment records.
%%%
%%% == Loan Domain Concepts ==
%%%
%%% A *loan* in banking is a financial product where a lender provides
%%% a borrower with a principal amount that must be repaid over a fixed
%%% term with interest. The key components are:
%%%
%%% <ul>
%%%   <li><b>Principal</b>: The original amount borrowed</li>
%%%   <li><b>Interest Rate</b>: The annual rate charged on the outstanding balance</li>
%%%   <li><b>Term</b>: The duration of the loan in months</li>
%%%   <li><b>Monthly Payment</b>: The fixed payment due each month</li>
%%% </ul>
%%%
%%% == Loan Lifecycle ==
%%%
%%% Loans progress through the following states:
%%%
%%% <ol>
%%%   <li><b>pending</b>: Loan application submitted, awaiting approval</li>
%%%   <li><b>approved</b>: Loan application approved, awaiting disbursement</li>
%%%   <li><b>disbursed</b>: Funds disbursed to borrower, repayment begins</li>
%%%   <li><b>repaid</b>: All principal and interest paid off</li>
%%%   <li><b>rejected</b>: Loan application denied</li>
%%% </ol>
%%%
%%% == Interest Calculation Methods ==
%%%
%%% Two interest calculation methods are supported:
%%%
%%% <ul>
%%%   <li><b>flat</b>: Simple interest calculated on original principal</li>
%%%   <li><b>declining</b>: Diminishing interest on remaining balance (amortizing)</li>
%%% </ul>
%%%
%%% @end
%%%===================================================================

%%
%% @doc Defines a loan product template that can be instantiated
%%      to create specific loans.
%%
%% A loan product represents a standardized loan offering with
%% predefined terms such as minimum/maximum amounts, term ranges,
%% and interest rates. Customers can apply for loans based on
%% these product templates.
%%
%% <h3>Fields</h3>
%% <ul>
%%   <li><b>product_id</b>: Unique identifier (UUID) for this product</li>
%%   <li><b>name</b>: Human-readable product name</li>
%%   <li><b>description</b>: Detailed description of the product</li>
%%   <li><b>currency</b>: ISO 4217 currency code (e.g., 'USD', 'EUR')</li>
%%   <li><b>min_amount</b>: Minimum principal amount allowed (minor units)</li>
%%   <li><b>max_amount</b>: Maximum principal amount allowed (minor units)</li>
%%   <li><b>min_term_months</b>: Minimum loan term in months</li>
%%   <li><b>max_term_months</b>: Maximum loan term in months</li>
%%   <li><b>interest_rate</b>: Annual interest rate in basis points (e.g., 500 = 5.00%)</li>
%%   <li><b>interest_type</b>: 'flat' or 'declining' (amortizing)</li>
%%   <li><b>status</b>: 'active' or 'inactive' product status</li>
%%   <li><b>created_at</b>: Creation timestamp (milliseconds since epoch)</li>
%%   <li><b>updated_at</b>: Last modification timestamp</li>
%% </ul>
%%
-record(loan_product, {
    product_id :: binary(),
    name :: binary(),
    description :: binary(),
    currency :: atom(),
    min_amount :: integer(),
    max_amount :: integer(),
    min_term_months :: integer(),
    max_term_months :: integer(),
    interest_rate :: non_neg_integer(),
    interest_type :: atom(),
    status :: atom(),
    version :: pos_integer(),
    eligibility :: map(),
    fees :: map(),
    created_at :: integer(),
    updated_at :: integer()
}).

%%
%% @doc Represents an active loan account for a specific borrower.
%%
%% A loan account tracks the ongoing state of a loan from approval
%% through full repayment. It maintains the outstanding balance,
%% payment history, and current status.
%%
%% <h3>Fields</h3>
%% <ul>
%%   <li><b>loan_id</b>: Unique identifier (UUID) for this loan</li>
%%   <li><b>product_id</b>: Reference to the loan product used</li>
%%   <li><b>party_id</b>: Reference to the borrower (customer)</li>
%%   <li><b>account_id</b>: Disbursement account for funds</li>
%%   <li><b>principal</b>: Original principal amount (minor units)</li>
%%   <li><b>currency</b>: ISO 4217 currency code</li>
%%   <li><b>interest_rate</b>: Annual interest rate applied in basis points</li>
%%   <li><b>term_months</b>: Loan term in months</li>
%%   <li><b>monthly_payment</b>: Calculated monthly payment amount</li>
%%   <li><b>outstanding_balance</b>: Remaining principal to repay</li>
%%   <li><b>status</b>: Current loan state (see lifecycle above)</li>
%%   <li><b>disbursed_at</b>: Timestamp when funds were disbursed</li>
%%   <li><b>created_at</b>: Loan creation timestamp</li>
%%   <li><b>updated_at</b>: Last modification timestamp</li>
%% </ul>
%%
-record(loan_account, {
    loan_id :: binary(),
    product_id :: binary(),
    party_id :: binary(),
    account_id :: binary(),
    principal :: integer(),
    currency :: atom(),
    interest_rate :: non_neg_integer(),
    term_months :: integer(),
    monthly_payment :: integer(),
    outstanding_balance :: integer(),
    status :: atom(),
    disbursed_at :: integer(),
    created_at :: integer(),
    updated_at :: integer()
}).

%%
%% @doc Records a single loan repayment installment.
%%
%% Each loan generates multiple repayment records representing
%% scheduled payments. A repayment record tracks the amount due,
%% portions applied to principal vs interest, and payment status.
%%
%% <h3>Fields</h3>
%% <ul>
%%   <li><b>repayment_id</b>: Unique identifier (UUID) for this repayment</li>
%%   <li><b>loan_id</b>: Reference to the parent loan</li>
%%   <li><b>amount</b>: Total payment amount due</li>
%%   <li><b>principal_portion</b>: Portion applied to principal</li>
%%   <li><b>interest_portion</b>: Portion applied to interest</li>
%%   <li><b>penalty</b>: Late payment penalty (if any)</li>
%%   <li><b>due_date</b>: Scheduled due date (timestamp)</li>
%%   <li><b>paid_at</b>: Actual payment timestamp (0 if unpaid)</li>
%%   <li><b>status</b>: 'pending', 'paid', 'late', or 'defaulted'</li>
%%   <li><b>created_at</b>: Record creation timestamp</li>
%% </ul>
%%
-record(loan_repayment, {
    repayment_id :: binary(),
    loan_id :: binary(),
    amount :: integer(),
    principal_portion :: integer(),
    interest_portion :: integer(),
    penalty :: integer(),
    due_date :: integer(),
    paid_at :: integer(),
    status :: atom(),
    created_at :: integer()
}).

%%
%% @doc Represents one installment in a generated repayment schedule.
%%
%% @see cb_repayment_schedule
%%
-record(installment, {
    month   :: pos_integer(),
    due_date :: integer(),
    payment :: integer(),
    principal :: integer(),
    interest :: integer(),
    balance :: integer()
}).

%%
%% @doc Type alias for a repayment schedule installment.
%%
-type installment() :: #installment{}.

%%
%% @doc Type alias for a loan product record.
%%
%% Represents a standardized loan product template that can be
%% instantiated to create specific loan accounts.
%%
-type loan_product() :: #loan_product{}.

%%
%% @doc Type alias for a loan account record.
%%
%% Represents an active loan with all its associated state,
%% including balance, terms, and current status.
%%
-type loan_account() :: #loan_account{}.

%%
%% @doc Type alias for a loan repayment record.
%%
%% Represents a single repayment installment for a loan,
%% including payment status and breakdown.
%%
-type loan_repayment() :: #loan_repayment{}.

%%
%% @doc Type alias for a loan identifier.
%%
%% Unique UUID binary identifier for a loan account.
%%
-type loan_id() :: binary().

%%
%% @doc Type alias for a loan product identifier.
%%
%% Unique UUID binary identifier for a loan product template.
%%
-type product_id() :: binary().

%%
%% @doc Type alias for a repayment identifier.
%%
%% Unique UUID binary identifier for a repayment record.
%%
-type repayment_id() :: binary().
