%%%===================================================================
%%%
%%% @doc Loan Account Management Module
%%%
%%% This module manages the complete lifecycle of loan accounts in the
%%% IronLedger core banking system. It handles loan creation, approval,
%%% rejection, disbursement, and repayment processing.
%%%
%%% <h2>Loan Lifecycle</h2>
%%%
%%% <ol>
%%%   <li><b>Create</b>: A loan application is submitted with product and amount</li>
%%%   <li><b>Approve</b>: The loan is approved and ready for disbursement</li>
%%%   <li><b>Disburse</b>: Funds are transferred to the borrower's account</li>
%%%   <li><b>Repay</b>: Borrower makes payments against the outstanding balance</li>
%%%   <li><b>Close</b>: Loan is fully repaid and closed</li>
%%% </ol>
%%%
%%% <h2>Amortization</h2>
%%%
%%% Loans use standard amortization where each payment contains both
%%% principal and interest. The interest portion decreases over time
%%% while the principal portion increases.
%%%
%%% @end
%%%===================================================================

-module(cb_loan_accounts).
-behaviour(gen_server).

-export([
         start_link/0,
         create_loan/7,
         approve_loan/1,
         reject_loan/2,
         disburse_loan/1,
         get_loan/1,
         list_loans/1,
         list_all_loans/0,
         make_repayment/2,
         calculate_overdue_amount/1
        ]).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% Suppress Dialyzer warnings for mnesia select with pattern matching
-dialyzer({nowarn_function, do_list_loans/1}).
-dialyzer({nowarn_function, do_list_all_loans/0}).

-include("loan.hrl").
-include_lib("cb_ledger/include/cb_ledger.hrl").
-include_lib("cb_events/include/cb_events.hrl").

-define(SERVER, ?MODULE).
-define(TABLE, loan_accounts).

-record(state, {}).

%%
%% @doc Starts the loan accounts gen_server.
%%
%% Initializes the Mnesia table for loan account storage and
%% links the process to the supervision tree.
%%
%% @returns {ok, pid()} on success, {error, term()} on failure
%%
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%%
%% @doc Creates a new loan account.
%%
%% Creates a new loan in 'pending' status based on the specified product
%% and terms. The monthly payment is automatically calculated using
%% standard amortization formulas.
%%
%% @param ProductId The loan product identifier
%% @param PartyId The borrower party identifier
%% @param AccountId The disbursement account identifier
%% @param Amount The principal amount in minor units
%% @param Currency The ISO 4217 currency code
%% @param TermMonths The loan term in months
%% @param InterestRate The annual interest rate in basis points
%%
%% @returns {ok, loan_id()} on success, {error, term()} on failure
%%
-spec create_loan(product_id(), binary(), binary(), amount(), atom(), integer(), non_neg_integer()) ->
    {ok, loan_id()} | {error, term()}.
create_loan(ProductId, PartyId, AccountId, Amount, Currency, TermMonths, InterestRate) ->
    gen_server:call(?SERVER, {create_loan, ProductId, PartyId, AccountId, Amount, Currency, TermMonths, InterestRate}).

%%
%% @doc Approves a pending loan application.
%%
%% Changes the loan status from 'pending' to 'approved', indicating
%% that the loan has been verified and is ready for disbursement.
%%
%% @param LoanId The unique loan identifier
%%
%% @returns {ok, loan_account()} on success, {error, term()} if not found or invalid status
%%
-spec approve_loan(loan_id()) -> {ok, loan_account()} | {error, term()}.
approve_loan(LoanId) ->
    gen_server:call(?SERVER, {approve_loan, LoanId}).

%%
%% @doc Rejects a pending loan application.
%%
%% Changes the loan status from 'pending' to 'rejected', indicating
%% that the loan application was denied.
%%
%% @param LoanId The unique loan identifier
%% @param Reason The rejection reason (for audit trail)
%%
%% @returns {ok, loan_account()} on success, {error, term()} if not found or invalid status
%%
-spec reject_loan(loan_id(), binary()) -> {ok, loan_account()} | {error, term()}.
reject_loan(LoanId, Reason) ->
    gen_server:call(?SERVER, {reject_loan, LoanId, Reason}).

%%
%% @doc Disburses funds for an approved loan.
%%
%% Changes the loan status from 'approved' to 'disbursed',
%% recording the disbursement timestamp. This marks the point
%% when interest begins accruing and repayment begins.
%%
%% @param LoanId The unique loan identifier
%%
%% @returns {ok, loan_account()} on success, {error, term()} if not found or invalid status
%%
-spec disburse_loan(loan_id()) -> {ok, loan_account()} | {error, term()}.
disburse_loan(LoanId) ->
    gen_server:call(?SERVER, {disburse_loan, LoanId}).

%%
%% @doc Retrieves a loan account by its identifier.
%%
%% @param LoanId The unique loan identifier
%%
%% @returns {ok, loan_account()} if found, {error, not_found} if not found
%%
-spec get_loan(loan_id()) -> {ok, loan_account()} | {error, not_found}.
get_loan(LoanId) ->
    gen_server:call(?SERVER, {get_loan, LoanId}).

%%
%% @doc Lists all loans for a specific party (borrower).
%%
%% @param PartyId The party (customer) identifier
%%
%% @returns List of loan_account() records for this party
%%
-spec list_loans(binary()) -> [loan_account()].
list_loans(PartyId) ->
    gen_server:call(?SERVER, {list_loans, PartyId}).

%%
%% @doc Lists all loan accounts in the system.
%%
%% Primarily used for administrative and reporting purposes.
%%
%% @returns List of all loan_account() records
%%
-spec list_all_loans() -> [loan_account()].
list_all_loans() ->
    gen_server:call(?SERVER, list_all_loans).

%%
%% @doc Records a loan repayment payment.
%%
%% Processes a payment against the loan's outstanding balance.
%% The payment is applied first to accrued interest, then to principal.
%% If the balance reaches zero, the loan status changes to 'repaid'.
%%
%% @param LoanId The unique loan identifier
%% @param Amount The payment amount in minor units
%%
%% @returns {ok, loan_account(), amount()} with updated loan and new balance,
%%          or {error, term()} on failure
%%
-spec make_repayment(loan_id(), amount()) -> {ok, loan_account(), amount()} | {error, term()}.
make_repayment(LoanId, Amount) ->
    gen_server:call(?SERVER, {make_repayment, LoanId, Amount}).

%%
%% @doc Calculates the overdue amount for a loan.
%%
%% Determines how much of the scheduled payments are overdue
%% based on the disbursement date and current date. Only applies
%% to loans in 'disbursed' status.
%%
%% @param LoanId The unique loan identifier
%%
%% @returns {ok, amount()} The overdue amount in minor units,
%%          or {error, term()} on failure
%%
-spec calculate_overdue_amount(loan_id()) -> {ok, amount()} | {error, term()}.
calculate_overdue_amount(LoanId) ->
    gen_server:call(?SERVER, {calculate_overdue_amount, LoanId}).

init([]) ->
    case mnesia:create_table(?TABLE, [
        {attributes, record_info(fields, loan_account)},
        {record_name, loan_account},
        {type, set},
        {ram_copies, [node()]},
        {index, [party_id, account_id, status]}
    ]) of
        {atomic, ok} -> ok;
        {aborted, {already_exists, _}} -> ok;
        {aborted, Reason} -> error(Reason)
    end,
    {ok, #state{}}.

handle_call({create_loan, ProductId, PartyId, AccountId, Amount, Currency, TermMonths, InterestRate}, _From, State) ->
    Reply = do_create_loan(ProductId, PartyId, AccountId, Amount, Currency, TermMonths, InterestRate),
    {reply, Reply, State};

handle_call({approve_loan, LoanId}, _From, State) ->
    Reply = do_approve_loan(LoanId),
    {reply, Reply, State};

handle_call({reject_loan, LoanId, _Reason}, _From, State) ->
    Reply = do_reject_loan(LoanId),
    {reply, Reply, State};

handle_call({disburse_loan, LoanId}, _From, State) ->
    Reply = do_disburse_loan(LoanId),
    {reply, Reply, State};

handle_call({get_loan, LoanId}, _From, State) ->
    Reply = do_get_loan(LoanId),
    {reply, Reply, State};

handle_call({list_loans, PartyId}, _From, State) ->
    Reply = do_list_loans(PartyId),
    {reply, Reply, State};

handle_call(list_all_loans, _From, State) ->
    Reply = do_list_all_loans(),
    {reply, Reply, State};

handle_call({make_repayment, LoanId, Amount}, _From, State) ->
    Reply = do_make_repayment(LoanId, Amount),
    {reply, Reply, State};

handle_call({calculate_overdue_amount, LoanId}, _From, State) ->
    Reply = do_calculate_overdue_amount(LoanId),
    {reply, Reply, State};

handle_call(_Request, _From, State) ->
    {reply, unknown_call, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

do_create_loan(ProductId, PartyId, AccountId, Amount, Currency, TermMonths, InterestRate) ->
    case validate_loan_creation(ProductId, PartyId, AccountId, Amount, Currency, TermMonths, InterestRate) of
        ok ->
            case cb_loan_calculations:calculate_monthly_payment(Amount, TermMonths, InterestRate) of
                {ok, MonthlyPayment} ->
                    LoanId = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
                    Now = erlang:system_time(millisecond),
                    Loan = #loan_account{
                        loan_id = LoanId,
                        product_id = ProductId,
                        party_id = PartyId,
                        account_id = AccountId,
                        principal = Amount,
                        currency = Currency,
                        interest_rate = InterestRate,
                        term_months = TermMonths,
                        monthly_payment = MonthlyPayment,
                        outstanding_balance = Amount,
                        status = pending,
                        disbursed_at = 0,
                        created_at = Now,
                        updated_at = Now
                    },
                    Fun = fun() ->
                    mnesia:write(?TABLE, Loan, write),
                    _ = cb_events:write_outbox(<<"loan.created">>, #{
                        loan_id   => LoanId,
                        party_id  => PartyId,
                        principal => Amount,
                        currency  => Currency
                    })
                end,
                    case mnesia:transaction(Fun) of
                        {atomic, _} -> {ok, LoanId};
                        {aborted, Reason} -> {error, Reason}
                    end;
                {error, _} = Error ->
                    Error
            end;
        Error ->
            Error
    end.

do_approve_loan(LoanId) ->
    Fun = fun() ->
        case mnesia:read({?TABLE, LoanId}) of
            [Loan] ->
                case Loan#loan_account.status of
                    pending ->
                        UpdatedLoan = Loan#loan_account{
                            status = approved,
                            updated_at = erlang:system_time(millisecond)
                        },
                        mnesia:write(?TABLE, UpdatedLoan, write),
                        _ = cb_events:write_outbox(<<"loan.approved">>, #{loan_id => LoanId}),
                        {ok, UpdatedLoan};
                    _Status ->
                        {error, invalid_status}
                end;
            [] ->
                {error, not_found}
        end
    end,
    case mnesia:transaction(Fun) of
        {atomic, Result} -> Result;
        {aborted, Reason} -> {error, Reason}
    end.

do_reject_loan(LoanId) ->
    Fun = fun() ->
        case mnesia:read({?TABLE, LoanId}) of
            [Loan] ->
                case Loan#loan_account.status of
                    pending ->
                        UpdatedLoan = Loan#loan_account{
                            status = rejected,
                            updated_at = erlang:system_time(millisecond)
                        },
                        mnesia:write(?TABLE, UpdatedLoan, write),
                        _ = cb_events:write_outbox(<<"loan.rejected">>, #{loan_id => LoanId}),
                        {ok, UpdatedLoan};
                    _Status ->
                        {error, invalid_status}
                end;
            [] ->
                {error, not_found}
        end
    end,
    case mnesia:transaction(Fun) of
        {atomic, Result} -> Result;
        {aborted, Reason} -> {error, Reason}
    end.

do_disburse_loan(LoanId) ->
    Fun = fun() ->
        case mnesia:read({?TABLE, LoanId}) of
            [Loan] ->
                case Loan#loan_account.status of
                    approved ->
                        Now = erlang:system_time(millisecond),
                        UpdatedLoan = Loan#loan_account{
                            status = disbursed,
                            disbursed_at = Now,
                            updated_at = Now
                        },
                        mnesia:write(?TABLE, UpdatedLoan, write),
                        _ = cb_events:write_outbox(<<"loan.disbursed">>, #{loan_id => LoanId}),
                        {ok, UpdatedLoan};
                    _Status ->
                        {error, invalid_status}
                end;
            [] ->
                {error, not_found}
        end
    end,
    case mnesia:transaction(Fun) of
        {atomic, Result} -> Result;
        {aborted, Reason} -> {error, Reason}
    end.

do_get_loan(LoanId) ->
    Fun = fun() -> mnesia:read({?TABLE, LoanId}) end,
    case mnesia:transaction(Fun) of
        {atomic, [Loan]} -> {ok, Loan};
        {atomic, []} -> {error, not_found}
    end.

do_list_loans(PartyId) ->
    Fun = fun() -> mnesia:select(?TABLE, [{#loan_account{party_id = '$1', _ = '_'}, [{'==', '$1', PartyId}], ['$_']}]) end,
    case mnesia:transaction(Fun) of
        {atomic, Loans} -> Loans
    end.

do_list_all_loans() ->
    Fun = fun() -> mnesia:select(?TABLE, [{#loan_account{_ = '_'}, [], ['$_']}]) end,
    case mnesia:transaction(Fun) of
        {atomic, Loans} -> Loans
    end.

do_make_repayment(LoanId, Amount) ->
    Fun = fun() ->
        case mnesia:read({?TABLE, LoanId}) of
            [Loan] ->
                case Loan#loan_account.status of
                    disbursed ->
                        NewBalance = max(0, Loan#loan_account.outstanding_balance - Amount),
                        UpdatedLoan = Loan#loan_account{
                            outstanding_balance = NewBalance,
                            status = case NewBalance of
                                        0 -> repaid;
                                        _ -> disbursed
                                    end,
                            updated_at = erlang:system_time(millisecond)
                        },
                        mnesia:write(?TABLE, UpdatedLoan, write),
                        {ok, UpdatedLoan, NewBalance};
                    _Status ->
                        {error, invalid_status}
                end;
            [] ->
                {error, not_found}
        end
    end,
    case mnesia:transaction(Fun) of
        {atomic, Result} -> Result;
        {aborted, Reason} -> {error, Reason}
    end.

do_calculate_overdue_amount(LoanId) ->
    case do_get_loan(LoanId) of
        {ok, Loan} ->
            case Loan#loan_account.status of
                disbursed ->
                    Now = erlang:system_time(millisecond),
                    DisbursedAt = Loan#loan_account.disbursed_at,
                    MonthsElapsed = (Now - DisbursedAt) div (30 * 24 * 60 * 60 * 1000),
                    TermMonths = Loan#loan_account.term_months,
                    ExpectedPayments = min(MonthsElapsed, TermMonths),
                    ExpectedTotal = ExpectedPayments * Loan#loan_account.monthly_payment,
                    Outstanding = Loan#loan_account.outstanding_balance,
                    Overdue = max(0, ExpectedTotal - (Outstanding)),
                    {ok, Overdue};
                _ ->
                    {ok, 0}
            end;
        {error, _} = Error ->
            Error
    end.

validate_loan_creation(ProductId, _PartyId, _AccountId, Amount, Currency, TermMonths, InterestRate) ->
    case Amount of
        A when A =< 0 -> {error, invalid_amount};
        A when A > 9999999999999 -> {error, amount_overflow};
        _ ->
            case TermMonths of
                T when T =< 0 -> {error, invalid_term};
                T when T > 360 -> {error, term_too_long};
                _ ->
                    case InterestRate of
                        R when not is_integer(R) -> {error, invalid_interest_rate};
                        R when R < 0 -> {error, invalid_interest_rate};
                        R when R > 10000 -> {error, interest_rate_too_high};
                        _ -> validate_product_constraints(ProductId, Amount, Currency, TermMonths, InterestRate)
                    end
            end
    end.

validate_product_constraints(ProductId, Amount, Currency, TermMonths, InterestRate) when is_binary(ProductId) ->
    Fun = fun() -> mnesia:read(loan_products, ProductId) end,
    case mnesia:transaction(Fun) of
        {atomic, [Product]} ->
            case Product#loan_product.status of
                inactive ->
                    {error, product_inactive};
                active ->
                    case Currency =:= Product#loan_product.currency of
                        false ->
                            {error, currency_mismatch};
                        true ->
                            case InterestRate =:= Product#loan_product.interest_rate of
                                false ->
                                    {error, invalid_interest_rate};
                                true ->
                                    case Amount >= Product#loan_product.min_amount andalso Amount =< Product#loan_product.max_amount of
                                        false ->
                                            {error, amount_out_of_product_range};
                                        true ->
                                            case TermMonths >= Product#loan_product.min_term_months andalso TermMonths =< Product#loan_product.max_term_months of
                                                false -> {error, term_out_of_product_range};
                                                true -> ok
                                            end
                                    end
                            end
                    end
            end;
        {atomic, []} ->
            {error, product_not_found};
        {aborted, _Reason} ->
            {error, database_error}
    end;
validate_product_constraints(_ProductId, _Amount, _Currency, _TermMonths, _InterestRate) ->
    {error, invalid_product_id}.
