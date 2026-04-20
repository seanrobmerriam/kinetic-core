%%%
%%% @doc Interest posting to the general ledger for IronLedger core banking system.
%%%
%%% This module handles the process of posting accrued interest to the general ledger.
%%% Interest posting is the mechanism that transfers accrued interest from the accrual
%%% records to actual ledger entries, making them part of the account's balance.
%%%
%%% == Banking Domain Concepts ==
%%%
%%% <b>Interest Posting Cycle</b>: Most banks follow a monthly interest posting cycle:
%%% <ol>
%%% <li>Interest accrues daily in the accrual tables</li>
%%% <li>At month-end, accrued interest is calculated</li>
%%% <li>Interest is posted to customer accounts via ledger entries</li>
%%% <li>Interest income/expense is recognized in the bank's general ledger</li>
%%% </ol>
%%%
%%% <b>Double-Entry Bookkeeping</b>: Every interest posting involves two entries:
%%% <ul>
%%% <li><b>Credit to customer account</b>: Increases the customer's balance (savings) or
%%%     increases the loan balance (interest charged)</li>
%%% <li><b>Debit/Credit to interest income/expense</b>: Records the bank's interest
%%%     income (savings) or interest expense (loans) in the general ledger</li>
%%% </ul>
%%%
%%% <b>Interest Expense Account</b>: A GL account that tracks interest the bank pays
%%% to depositors. This is an expense on the bank's income statement.
%%%
%%% <b>Interest Income Account</b>: A GL account that tracks interest the bank receives
%%% from borrowers. This is revenue on the bank's income statement.
%%%
-module(cb_interest_posting).

-include("cb_interest.hrl").
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([
    post_accrued_interest/2,
    process_daily_accruals/0,
    run_job/0,
    get_interest_expense_account_id/0,
    get_interest_income_account_id/0
]).

-define(INTEREST_EXPENSE_ACCOUNT_ID, <<"interest-expense">>).
-define(INTEREST_INCOME_ACCOUNT_ID, <<"interest-income">>).
-define(INTEREST_TXN_TYPE, interest_posting).

%%%
%%% @doc Post accrued interest to an account's ledger.
%%%
%%% This function creates the double-entry ledger entries for interest that has
%%% accumulated in the accrual record. It performs:
%%% <ol>
%%% <li>Validates the account exists and is not closed</li>
%%% <li>Creates a credit entry to the customer's account</li>
%%% <li>Creates a debit entry to the interest expense account (for savings) or
%%%     credit entry to interest income account (for loans)</li>
%%% </ol>
%%%
%%% The posting maintains the accounting equation and creates a complete audit trail.
%%%
%%% @param AccountId The UUID of the account to post interest to
%%% @param Amount The interest amount to post in minor units
%%% @returns {ok, TransactionId} on success, {error, Reason} on failure
%%%
-spec post_accrued_interest(uuid(), amount()) -> {ok, uuid()} | {error, atom()}.
post_accrued_interest(AccountId, Amount) when is_binary(AccountId), is_integer(Amount), Amount > 0 ->
    F = fun() ->
        case mnesia:read(account, AccountId) of
            [] ->
                {error, account_not_found};
            [Account] ->
                case Account#account.status of
                    closed ->
                        {error, account_closed};
                    _ ->
                        TxnId = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
                        Now = erlang:system_time(millisecond),
                        CreditEntry = #ledger_entry{
                            entry_id = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
                            txn_id = TxnId,
                            account_id = AccountId,
                            entry_type = credit,
                            amount = Amount,
                            currency = Account#account.currency,
                            description = <<"Interest posting">>,
                            posted_at = Now
                        },
                        DebitEntry = #ledger_entry{
                            entry_id = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
                            txn_id = TxnId,
                            account_id = get_interest_expense_account_id(),
                            entry_type = debit,
                            amount = Amount,
                            currency = Account#account.currency,
                            description = <<"Interest expense">>,
                            posted_at = Now
                        },
                        ok = cb_ledger:post_entries(DebitEntry, CreditEntry),
                        {ok, TxnId}
                end
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, _Reason} -> {error, database_error}
    end.

%%%
%%% @doc Process daily accruals for all active interest-bearing accounts.
%%%
%%% This function is typically run as a nightly batch job. It:
%%% <ol>
%%% <li>Retrieves all active (accruing) interest accruals</li>
%%% <li>For each accrual, calculates the daily interest</li>
%%% <li>Posts the interest to the customer's account</li>
%%% </ol>
%%%
%%% The function returns the count of successfully processed accounts.
%%%
%%% @returns {ok, Count} where Count is the number of accounts processed
%%%
-spec process_daily_accruals() -> {ok, non_neg_integer()}.
process_daily_accruals() ->
    Accruals = cb_interest_accrual:get_active_accruals(),
    process_accruals(Accruals, 0).

%%%
%%% @doc Job runner entry point for daily interest processing.
%%%
%%% This is the MFA target registered in `cb_jobs` for the `daily_interest` job.
%%% It delegates directly to `process_daily_accruals/0` and exists as a named
%%% entry point so job registration is self-documenting.
%%%
%%% @returns `{ok, Count}` — the number of accruals that were processed.
%%%
-spec run_job() -> {ok, non_neg_integer()}.
run_job() ->
    process_daily_accruals().

%%%
%%% @doc Get the account ID for interest expense ledger entries.
%%%
%%% This is the general ledger account used to track interest paid to depositors.
%%% For savings accounts, posting interest creates a debit to this expense account.
%%%
%%% @returns The interest expense account ID
%%%
-spec get_interest_expense_account_id() -> <<_:128>>.
get_interest_expense_account_id() ->
    ?INTEREST_EXPENSE_ACCOUNT_ID.

%%%
%%% @doc Get the account ID for interest income ledger entries.
%%%
%%% This is the general ledger account used to track interest received from borrowers.
%%% For loan accounts, charging interest creates a credit to this income account.
%%%
%%% @returns The interest income account ID
%%%
-spec get_interest_income_account_id() -> <<_:120>>.
get_interest_income_account_id() ->
    ?INTEREST_INCOME_ACCOUNT_ID.

%%%
%%% @doc Process a list of accruals, posting interest to each account.
%%%
%%% Internal helper function that iterates through accruals and posts interest.
%%% Failed postings are skipped but don't stop processing of other accounts.
%%%
%%% @param Accruals List of interest accrual records to process
%%% @param Count Counter for successfully processed accounts
%%% @returns {ok, Count} with final count of processed accounts
%%%
-spec process_accruals([interest_accrual()], non_neg_integer()) -> {ok, non_neg_integer()}.
process_accruals([], Count) ->
    {ok, Count};
process_accruals([Accrual | Rest], Count) ->
    AccountId = Accrual#interest_accrual.account_id,
    case cb_accounts:get_balance(AccountId) of
        {ok, #{balance := CurrentBalance}} ->
            case calculate_and_post_daily_interest(Accrual, CurrentBalance) of
                {ok, _TxnId} ->
                    process_accruals(Rest, Count + 1);
                {error, _} ->
                    process_accruals(Rest, Count)
            end;
        {error, _} ->
            process_accruals(Rest, Count)
    end.

%%%
%%% @doc Calculate and post daily interest for a single accrual.
%%%
%%% Calculates one day's worth of interest based on the accrual's daily rate
%%% and the current account balance. If interest is greater than zero, it posts
%%% to the ledger.
%%%
%%% @param Accrual The interest accrual record
%%% @param CurrentBalance The current account balance in minor units
%%% @returns {ok, TransactionId} if posted, {ok, <<"no-interest">>} if zero
%%%
-spec calculate_and_post_daily_interest(interest_accrual(), amount()) -> {ok, uuid()} | {error, atom()}.
calculate_and_post_daily_interest(Accrual, CurrentBalance) ->
    DailyRate = Accrual#interest_accrual.daily_rate,
    DailyInterest = cb_interest:calculate_interest(CurrentBalance, DailyRate, 1),
    if
        DailyInterest > 0 ->
            post_accrued_interest(Accrual#interest_accrual.account_id, DailyInterest);
        true ->
            {ok, <<"no-interest">>}
    end.
