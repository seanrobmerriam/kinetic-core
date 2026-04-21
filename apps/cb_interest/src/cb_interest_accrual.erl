%%%
%%% @doc Interest accrual tracking for IronLedger core banking system.
%%%
%%% This module manages the lifecycle of interest accruals. Interest accrual is the
%%% process of accumulating interest over time before it is actually paid or charged.
%%%
%%% == Banking Domain Concepts ==
%%%
%%% <b>Accrual Accounting</b>: In banking, interest is typically accrued daily but
%%% posted monthly. This follows the accrual accounting principle where revenue/expenses
%%% are recognized when earned/incurred, not when cash changes hands.
%%%
%%% <b>Accrued Interest</b>: The cumulative interest that has been earned (for savings)
%%% or charged (for loans) since the last interest posting. This represents a liability
%%% for the bank (savings) or an asset (loans).
%%%
%%% <b>Daily Accrual</b>: Most modern core banking systems calculate interest accruals
%%% daily. This provides:
%%% <ul>
%%% <li>Accurate tracking of interest for partial periods</li>
%%% <li>Fair treatment of accounts that open/close mid-period</li>
%%% <li>Real-time visibility into interest income/expense</li>
%%% </ul>
%%%
-module(cb_interest_accrual).

-include("cb_interest.hrl").
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([
    start_accrual/4,
    calculate_daily_accrual/2,
    get_accrual/1,
    close_accrual/1,
    get_active_accruals/0,
    get_accruals_for_account/1,
    process_expired_accruals/0
]).

-dialyzer({nowarn_function, get_active_accruals/0}).
-dialyzer({nowarn_function, get_accruals_for_account/1}).

-define(ACCRUAL_TABLE, interest_accrual).

%%%
%%% @doc Start a new interest accrual for an account.
%%%
%%% Creates a new accrual record when interest-bearing activity begins on an account.
%%% This typically happens when:
%%% <ul>
%%% <li>A savings account is opened</li>
%%% <li>A loan is disbursed</li>
%%% <li>A new interest-bearing product is activated</li>
%%% </ul>
%%%
%%% The accrual is created with zero accrued amount and status 'accruing'.
%%% Daily interest will be accumulated until the accrual is closed or posted.
%%%
%%% @param AccountId The UUID of the account to start accruing interest for
%%% @param ProductId The UUID of the interest-bearing product
%%% @param Balance The initial balance in minor units
%%% @param AnnualRate The annual interest rate in basis points
%%% @returns {ok, InterestAccrual} on success, {error, Reason} on failure
%%%
-spec start_accrual(uuid(), uuid(), amount(), interest_rate()) -> {ok, interest_accrual()} | {error, atom()}.
start_accrual(AccountId, ProductId, Balance, AnnualRate)
        when is_binary(AccountId), is_binary(ProductId),
             is_integer(Balance), Balance >= 0,
             is_integer(AnnualRate), AnnualRate >= 0 ->
    F = fun() ->
        case mnesia:read(account, AccountId) of
            [] ->
                {error, account_not_found};
            [Account] ->
                case Account#account.status of
                    closed ->
                        {error, account_closed};
                    _ ->
                        DailyRate = cb_interest:calculate_daily_rate(AnnualRate),
                        Now = erlang:system_time(millisecond),
                        AccrualId = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
                        Accrual = #interest_accrual{
                            accrual_id = AccrualId,
                            account_id = AccountId,
                            product_id = ProductId,
                            interest_rate = AnnualRate,
                            daily_rate = DailyRate,
                            start_date = Now,
                            end_date = undefined,
                            balance = Balance,
                            accrued_amount = 0,
                            status = accruing,
                            created_at = Now
                        },
                        mnesia:write(Accrual),
                        {ok, Accrual}
                end
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, _Reason} -> {error, database_error}
    end.

%%%
%%% @doc Calculate the daily interest accrual for an account.
%%%
%%% This function calculates how much interest has accrued for a specific account
%%% based on its current balance and the daily interest rate. It reads the existing
%%% accrual record (if any) and calculates the new accrued amount.
%%%
%%% For accounts with status 'accruing', the daily interest is calculated as:
%%% <pre>
%%%   Daily Interest = Balance × Daily Rate
%%% </pre>
%%%
%%% The returned amount is added to the existing accrued amount in the record.
%%%
%%% @param AccountId The UUID of the account
%%% @param Balance The current account balance in minor units
%%% @returns The daily accrued interest amount in minor units
%%%
-spec calculate_daily_accrual(uuid(), amount()) -> amount().
calculate_daily_accrual(AccountId, Balance) when is_binary(AccountId), is_integer(Balance), Balance >= 0 ->
    F = fun() ->
        case mnesia:index_read(?ACCRUAL_TABLE, AccountId, account_id) of
            [] ->
                0;
            [Accrual | _] ->
                case Accrual#interest_accrual.status of
                    accruing ->
                        DailyRate = Accrual#interest_accrual.daily_rate,
                        cb_interest:calculate_interest(Balance, DailyRate, 1);
                    _ ->
                        0
                end
        end
    end,
    {atomic, Result} = mnesia:transaction(F),
    Result.

%%%
%%% @doc Retrieve an interest accrual record by its ID.
%%%
%%% @param AccrualId The UUID of the accrual record to retrieve
%%% @returns {ok, InterestAccrual} if found, {error, accrual_not_found} if not found
%%%
-spec get_accrual(uuid()) -> {ok, interest_accrual()} | {error, atom()}.
get_accrual(AccrualId) ->
    F = fun() ->
        case mnesia:read(?ACCRUAL_TABLE, AccrualId) of
            [Accrual] -> {ok, Accrual};
            [] -> {error, accrual_not_found}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, _Reason} -> {error, database_error}
    end.

%%%
%%% @doc Close an interest accrual record.
%%%
%%% Closes an active accrual when interest-bearing activity ends. This happens when:
%%% <ul>
%%% <li>An account is closed</li>
%%% <li>The account switches to a non-interest-bearing product</li>
%%% <li>The interest-bearing term ends (e.g., CD matures)</li>
%%% </ul>
%%%
%%% Closing sets the end_date to the current timestamp and changes status to 'closed'.
%%% The accrued interest remains in the record for reporting purposes.
%%%
%%% @param AccrualId The UUID of the accrual to close
%%% @returns {ok, UpdatedAccrual} on success, {error, Reason} on failure
%%%
-spec close_accrual(uuid()) -> {ok, interest_accrual()} | {error, atom()}.
close_accrual(AccrualId) ->
    F = fun() ->
        case mnesia:read(?ACCRUAL_TABLE, AccrualId, write) of
            [] ->
                {error, accrual_not_found};
            [Accrual] ->
                Now = erlang:system_time(millisecond),
                Updated = Accrual#interest_accrual{
                    end_date = Now,
                    status = closed
                },
                mnesia:write(Updated),
                {ok, Updated}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, _Reason} -> {error, database_error}
    end.

%%%
%%% @doc Get all active (accruing) interest accruals in the system.
%%%
%%% This function is used for batch processing of daily interest calculations.
%%% It returns all accruals with status 'accruing', which represent accounts
%%% that are actively accumulating interest.
%%%
%%% @returns List of all active interest accrual records
%%%
-spec get_active_accruals() -> [interest_accrual()].
get_active_accruals() ->
    F = fun() ->
        MatchHead = #interest_accrual{status = accruing, _ = '_'},
        mnesia:select(?ACCRUAL_TABLE, [{MatchHead, [], ['$_']}])
    end,
    {atomic, Accruals} = mnesia:transaction(F),
    Accruals.

%%%
%%% @doc Get all interest accruals for a specific account.
%%%
%%% Returns all accrual records associated with an account, including active,
%%% posted, and closed accruals. This is useful for:
%%% <ul>
%%% <li>Account interest history reporting</li>
%%% <li>Auditing past accruals</li>
%%% <li>Handling account transitions between products</li>
%%% </ul>
%%%
%%% @param AccountId The UUID of the account
%%% @returns List of all accrual records for the account
%%%
-spec get_accruals_for_account(binary()) -> [interest_accrual()].
get_accruals_for_account(AccountId) ->
    F = fun() ->
        mnesia:index_read(?ACCRUAL_TABLE, AccountId, account_id)
    end,
    {atomic, Accruals} = mnesia:transaction(F),
    Accruals.

%%%
%%% @doc Close all active accruals whose end_date has passed.
%%%
%%% This function is the entry point for the `maturity_check` scheduled job. It
%%% scans all accruing records and closes those whose `end_date` is set to a
%%% timestamp that has already elapsed. Accruals with `end_date = undefined` are
%%% assumed to have no fixed term and are left untouched.
%%%
%%% Called by `cb_jobs` as the handler for the `maturity_check` job.
%%%
%%% @returns `{ok, ClosedCount}` — the number of accruals transitioned to closed.
%%%
-spec process_expired_accruals() -> {ok, non_neg_integer()}.
process_expired_accruals() ->
    Now = erlang:system_time(millisecond),
    Active = get_active_accruals(),
    Expired = [A || A <- Active,
                    A#interest_accrual.end_date =/= undefined,
                    A#interest_accrual.end_date =< Now],
    Results = [close_accrual(A#interest_accrual.accrual_id) || A <- Expired],
    Closed = length([ok || {ok, _} <- Results]),
    {ok, Closed}.
