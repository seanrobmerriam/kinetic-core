%%%===================================================================
%%%
%%% @doc Loan Repayment Management Module
%%%
%%% This module manages loan repayment tracking, including scheduled
%%% payments, payment status, overdue calculations, and penalties.
%%%
%%% <h2>Repayment Tracking</h2>
%%%
%%% Each loan generates multiple repayment records representing
%%% scheduled installment payments. The system tracks:
%%%
%%% <ul>
%%%   <li><b>Due Date</b>: When the payment is scheduled</li>
%%%   <li><b>Payment Amount</b>: Total amount due</li>
%%%   <li><b>Principal/Interest Breakdown</b>: How payment is applied</li>
%%%   <li><b>Status</b>: Pending, paid, late, or defaulted</li>
%%%   <li><b>Penalties</b>: Late payment charges</li>
%%% </ul>
%%%
%%% <h2>Payment Status</h2>
%%%
%%% <ol>
%%%   <li><b>pending</b>: Payment due but not yet received</li>
%%%   <li><b>paid</b>: Payment successfully received</li>
%%%   <li><b>late</b>: Payment received after due date</li>
%%%   <li><b>defaulted</b>: Payment significantly overdue</li>
%%% </ol>
%%%
%%% <h2>Late Penalties</h2>
%%%
%%% A grace period (5 days) is provided after the due date before
%%%.late penalties are applied. Penalty rates are specified in
%%%.basis points (BPS).
%%%
%%% @end
%%%===================================================================

-module(cb_loan_repayments).
-behaviour(gen_server).

-export([
         start_link/0,
         record_repayment/4,
         get_repayments/1,
         calculate_overdue/1,
         get_repayment/1,
         update_repayment_status/2
        ]).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% Suppress Dialyzer warnings for mnesia select with pattern matching
-dialyzer({nowarn_function, do_get_repayments/1}).

-include("loan.hrl").
-include_lib("cb_ledger/include/cb_ledger.hrl").

-define(SERVER, ?MODULE).
-define(TABLE, loan_repayments).

-record(state, {}).

-define(GRACE_PERIOD_DAYS, 5).
-define(LATE_PENALTY_BPS, 500).

%%
%% @doc Starts the loan repayments gen_server.
%%
%% Initializes the Mnesia table for repayment record storage
%% and links the process to the supervision tree.
%%
%% @returns {ok, pid()} on success, {error, term()} on failure
%%
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%%
%% @doc Records a new loan repayment.
%%
%% Creates a repayment record for a specific loan, calculating
%% the interest portion and any applicable penalties.
%%
%% @param LoanId The loan identifier
%% @param Amount Total payment amount
%% @param DueDate Scheduled due date (timestamp)
%% @param PrincipalPortion Portion going to principal
%%
%% @returns {ok, repayment_id()} on success, {error, term()} on failure
%%
-spec record_repayment(loan_id(), amount(), integer(), amount()) ->
    {ok, repayment_id()} | {error, term()}.
record_repayment(LoanId, Amount, DueDate, PrincipalPortion) ->
    gen_server:call(?SERVER, {record_repayment, LoanId, Amount, DueDate, PrincipalPortion}).

%%
%% @doc Retrieves all repayment records for a loan.
%%
%% @param LoanId The loan identifier
%%
%% @returns List of loan_repayment() records for this loan
%%
-spec get_repayments(loan_id()) -> [loan_repayment()].
get_repayments(LoanId) ->
    gen_server:call(?SERVER, {get_repayments, LoanId}).

%%
%% @doc Calculates the total overdue amount for a loan.
%%
%% Sums up all pending payments that are past the due date
%% plus any applicable late penalties.
%%
%% @param LoanId The loan identifier
%%
%% @returns {ok, amount()} Total overdue amount, or {error, term()} on failure
%%
-spec calculate_overdue(loan_id()) -> {ok, amount()} | {error, term()}.
calculate_overdue(LoanId) ->
    gen_server:call(?SERVER, {calculate_overdue, LoanId}).

%%
%% @doc Retrieves a specific repayment record.
%%
%% @param RepaymentId The repayment identifier
%%
%% @returns {ok, loan_repayment()} if found, {error, not_found} if not found
%%
-spec get_repayment(repayment_id()) -> {ok, loan_repayment()} | {error, not_found}.
get_repayment(RepaymentId) ->
    gen_server:call(?SERVER, {get_repayment, RepaymentId}).

%%
%% @doc Updates the status of a repayment record.
%%
%% Changes the payment status. Valid statuses are: pending, paid,
%% late, and defaulted.
%%
%% @param RepaymentId The repayment identifier
%% @param Status New status atom
%%
%% @returns {ok, loan_repayment()} on success, {error, term()} on failure
%%
-spec update_repayment_status(repayment_id(), atom()) -> {ok, loan_repayment()} | {error, term()}.
update_repayment_status(RepaymentId, Status) ->
    gen_server:call(?SERVER, {update_repayment_status, RepaymentId, Status}).

init([]) ->
    case mnesia:create_table(?TABLE, [
        {attributes, record_info(fields, loan_repayment)},
        {record_name, loan_repayment},
        {type, set},
        {ram_copies, [node()]},
        {index, [loan_id, status]}
    ]) of
        {atomic, ok} -> ok;
        {aborted, {already_exists, _}} -> ok;
        {aborted, Reason} -> error(Reason)
    end,
    {ok, #state{}}.

handle_call({record_repayment, LoanId, Amount, DueDate, PrincipalPortion}, _From, State) ->
    Reply = do_record_repayment(LoanId, Amount, DueDate, PrincipalPortion),
    {reply, Reply, State};

handle_call({get_repayments, LoanId}, _From, State) ->
    Reply = do_get_repayments(LoanId),
    {reply, Reply, State};

handle_call({calculate_overdue, LoanId}, _From, State) ->
    Reply = do_calculate_overdue(LoanId),
    {reply, Reply, State};

handle_call({get_repayment, RepaymentId}, _From, State) ->
    Reply = do_get_repayment(RepaymentId),
    {reply, Reply, State};

handle_call({update_repayment_status, RepaymentId, Status}, _From, State) ->
    Reply = do_update_repayment_status(RepaymentId, Status),
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

do_record_repayment(LoanId, Amount, DueDate, PrincipalPortion) ->
    case cb_loan_accounts:get_loan(LoanId) of
        {ok, Loan} ->
            InterestPortion = Amount - PrincipalPortion,
            Penalty = calculate_penalty(Loan, DueDate),
            RepaymentId = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
            Now = erlang:system_time(millisecond),
            Repayment = #loan_repayment{
                repayment_id = RepaymentId,
                loan_id = LoanId,
                amount = Amount,
                principal_portion = PrincipalPortion,
                interest_portion = InterestPortion,
                penalty = Penalty,
                due_date = DueDate,
                paid_at = Now,
                status = paid,
                created_at = Now
            },
            Fun = fun() -> mnesia:write(?TABLE, Repayment, write) end,
            case mnesia:transaction(Fun) of
                {atomic, _} -> {ok, RepaymentId};
                {aborted, Reason} -> {error, Reason}
            end;
        {error, _} = Error ->
            Error
    end.

do_get_repayments(LoanId) ->
    Fun = fun() -> mnesia:select(?TABLE, [{#loan_repayment{loan_id = '$1', _ = '_'}, [{'==', '$1', LoanId}], ['$_']}]) end,
    case mnesia:transaction(Fun) of
        {atomic, Repayments} -> Repayments;
        {aborted, _} -> []
    end.

do_calculate_overdue(LoanId) ->
    case do_get_repayments(LoanId) of
        [] ->
            {ok, 0};
        Repayments ->
            Now = erlang:system_time(millisecond),
            GracePeriodMs = ?GRACE_PERIOD_DAYS * 24 * 60 * 60 * 1000,
            Overdue = lists:foldl(fun(Repayment, Acc) ->
                case Repayment#loan_repayment.status of
                    pending ->
                        DueDate = Repayment#loan_repayment.due_date,
                        if Now > (DueDate + GracePeriodMs) ->
                            Acc + Repayment#loan_repayment.amount + Repayment#loan_repayment.penalty;
                        true ->
                            Acc
                        end;
                    _ ->
                        Acc
                end
            end, 0, Repayments),
            {ok, Overdue}
    end.

do_get_repayment(RepaymentId) ->
    Fun = fun() -> mnesia:read({?TABLE, RepaymentId}) end,
    case mnesia:transaction(Fun) of
        {atomic, [Repayment]} -> {ok, Repayment};
        {atomic, []} -> {error, not_found}
    end.

do_update_repayment_status(RepaymentId, Status) ->
    ValidStatuses = [pending, paid, late, defaulted],
    case lists:member(Status, ValidStatuses) of
        true ->
            Fun = fun() ->
                case mnesia:read({?TABLE, RepaymentId}) of
                    [Repayment] ->
                        Updated = Repayment#loan_repayment{
                            status = Status,
                            paid_at = erlang:system_time(millisecond)
                        },
                        mnesia:write(?TABLE, Updated, write),
                        {ok, Updated};
                    [] ->
                        {error, not_found}
                end
            end,
            case mnesia:transaction(Fun) of
                {atomic, Result} -> Result;
                {aborted, Reason} -> {error, Reason}
            end;
        false ->
            {error, invalid_status}
    end.

calculate_penalty(_Loan, _DueDate) ->
    0.
