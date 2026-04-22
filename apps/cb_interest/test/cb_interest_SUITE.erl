-module(cb_interest_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").
-include("cb_interest.hrl").
-include_lib("cb_ledger/include/cb_ledger.hrl").
-include_lib("cb_events/include/cb_events.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1, init_per_testcase/2, end_per_testcase/2]).
-export([
    % Happy path tests - cb_interest (pure calculations)
    calculate_daily_rate_ok/1,
    calculate_interest_ok/1,
    calculate_compound_interest_daily/1,
    calculate_compound_interest_monthly/1,
    calculate_compound_interest_quarterly/1,
    calculate_compound_interest_annually/1,
    basis_points_to_float_ok/1,
    float_to_basis_points_ok/1,
    % Error/boundary tests - cb_interest
    calculate_daily_rate_invalid/1,
    calculate_interest_zero_balance/1,
    calculate_interest_zero_days/1,
    calculate_compound_interest_zero_days/1,
    basis_points_to_float_zero/1,
    float_to_basis_points_zero/1,
    % cb_interest_accrual tests
    start_accrual_ok/1,
    start_accrual_account_not_found/1,
    start_accrual_account_closed/1,
    get_accrual_ok/1,
    get_accrual_not_found/1,
    close_accrual_ok/1,
    close_accrual_not_found/1,
    get_active_accruals_ok/1,
    get_accruals_for_account_ok/1,
    calculate_daily_accrual_ok/1,
    % cb_interest_posting tests
    post_accrued_interest_ok/1,
    post_accrued_interest_account_not_found/1,
    post_accrued_interest_account_closed/1,
    post_accrued_interest_zero_amount/1,
    get_interest_expense_account_id_ok/1,
    get_interest_income_account_id_ok/1
]).

all() ->
    [
        % Happy path - cb_interest
        calculate_daily_rate_ok,
        calculate_interest_ok,
        calculate_compound_interest_daily,
        calculate_compound_interest_monthly,
        calculate_compound_interest_quarterly,
        calculate_compound_interest_annually,
        basis_points_to_float_ok,
        float_to_basis_points_ok,
        % Error/boundary - cb_interest
        calculate_daily_rate_invalid,
        calculate_interest_zero_balance,
        calculate_interest_zero_days,
        calculate_compound_interest_zero_days,
        basis_points_to_float_zero,
        float_to_basis_points_zero,
        % cb_interest_accrual
        start_accrual_ok,
        start_accrual_account_not_found,
        start_accrual_account_closed,
        get_accrual_ok,
        get_accrual_not_found,
        close_accrual_ok,
        close_accrual_not_found,
        get_active_accruals_ok,
        get_accruals_for_account_ok,
        calculate_daily_accrual_ok,
        % cb_interest_posting
        post_accrued_interest_ok,
        post_accrued_interest_account_not_found,
        post_accrued_interest_account_closed,
        post_accrued_interest_zero_amount,
        get_interest_expense_account_id_ok,
        get_interest_income_account_id_ok
    ].

init_per_suite(Config) ->
    mnesia:start(),
    % Create required tables
    Tables = [party, party_audit, account, transaction, ledger_entry,
              interest_accrual, event_outbox],
    lists:foreach(fun create_table/1, Tables),
    Config.

create_table(interest_accrual) ->
    case mnesia:create_table(interest_accrual, [
        {ram_copies, [node()]},
        {attributes, record_info(fields, interest_accrual)},
        {index, [account_id, status]}
    ]) of
        {atomic, ok} -> ok;
        {aborted, {already_exists, _}} -> ok;
        {aborted, Reason} -> error({failed_to_create_table, interest_accrual, Reason})
    end;
create_table(TableName) ->
    case mnesia:create_table(TableName, table_spec(TableName)) of
        {atomic, ok} -> ok;
        {aborted, {already_exists, _}} -> ok;
        {aborted, Reason} -> error({failed_to_create_table, TableName, Reason})
    end.

table_spec(party) ->
    [
        {ram_copies, [node()]},
        {attributes, record_info(fields, party)},
        {index, [email, status]}
    ];
table_spec(account) ->
    [
        {ram_copies, [node()]},
        {attributes, record_info(fields, account)},
        {index, [party_id, status]}
    ];
table_spec(transaction) ->
    [
        {ram_copies, [node()]},
        {attributes, record_info(fields, transaction)},
        {index, [idempotency_key, source_account_id, dest_account_id, status]}
    ];
table_spec(party_audit) ->
    [
        {ram_copies, [node()]},
        {attributes, record_info(fields, party_audit)},
        {index, [party_id, action, version]}
    ];
table_spec(event_outbox) ->
    [
        {ram_copies, [node()]},
        {attributes, record_info(fields, event_outbox)},
        {index, [status]}
    ];
table_spec(ledger_entry) ->
    [
        {ram_copies, [node()]},
        {attributes, record_info(fields, ledger_entry)},
        {index, [txn_id, account_id]}
    ].

end_per_suite(_Config) ->
    mnesia:stop(),
    mnesia:delete_schema([node()]),
    ok.

init_per_testcase(_TestCase, Config) ->
    % Clear all relevant tables before each test
    lists:foreach(fun(T) -> mnesia:clear_table(T) end,
                  [party, party_audit, account, transaction, ledger_entry,
                   interest_accrual, event_outbox]),
    Config.

end_per_testcase(_TestCase, _Config) ->
    ok.

%% =============================================================================
%% Happy Path Tests - cb_interest (Pure Calculation Functions)
%% =============================================================================

%% Test: Calculate daily rate from annual rate
calculate_daily_rate_ok(_Config) ->
    DailyRate = cb_interest:calculate_daily_rate(1000),
    Expected = (1000 * 100000) div 365,
    ?assertEqual(Expected, DailyRate),
    ok.

%% Test: Calculate simple interest (uses higher balance to ensure non-zero result)
calculate_interest_ok(_Config) ->
    DailyRate = cb_interest:calculate_daily_rate(1000),
    Interest = cb_interest:calculate_interest(1000000, DailyRate, 30),  % $10000 for 30 days
    ?assert(is_integer(Interest)),
    ?assert(Interest >= 0),
    ok.

%% Test: Calculate compound interest - daily compounding
calculate_compound_interest_daily(_Config) ->
    Result = cb_interest:calculate_compound_interest(10000, 1000, 30, daily),
    ?assert(is_integer(Result)),
    ?assert(Result >= 10000),  % Should be at least principal
    ok.

%% Test: Calculate compound interest - monthly compounding
calculate_compound_interest_monthly(_Config) ->
    Result = cb_interest:calculate_compound_interest(10000, 1000, 60, monthly),
    ?assert(is_integer(Result)),
    ?assert(Result >= 10000),
    ok.

%% Test: Calculate compound interest - quarterly compounding
calculate_compound_interest_quarterly(_Config) ->
    Result = cb_interest:calculate_compound_interest(10000, 1000, 182, quarterly),
    ?assert(is_integer(Result)),
    ?assert(Result >= 10000),
    ok.

%% Test: Calculate compound interest - annually compounding
calculate_compound_interest_annually(_Config) ->
    Result = cb_interest:calculate_compound_interest(10000, 1000, 365, annually),
    ?assert(is_integer(Result)),
    ?assert(Result >= 10000),
    ok.

%% Test: Convert basis points to float
basis_points_to_float_ok(_Config) ->
    Float = cb_interest:basis_points_to_float(250),  % 250 bps = 2.5%
    ?assertEqual(0.025, Float),
    ok.

%% Test: Convert float to basis points
float_to_basis_points_ok(_Config) ->
    Bps = cb_interest:float_to_basis_points(0.025),  % 2.5% = 250 bps
    ?assertEqual(250, Bps),
    ok.

%% =============================================================================
%% Error/Boundary Tests - cb_interest
%% =============================================================================

%% Test: Calculate daily rate with invalid input (negative rate throws)
calculate_daily_rate_invalid(_Config) ->
    ?assertError(function_clause, cb_interest:calculate_daily_rate(-10)),
    ok.

%% Test: Calculate interest with zero balance
calculate_interest_zero_balance(_Config) ->
    DailyRate = cb_interest:calculate_daily_rate(1000),
    Interest = cb_interest:calculate_interest(0, DailyRate, 30),
    ?assertEqual(0, Interest),
    ok.

%% Test: Calculate interest with zero days
calculate_interest_zero_days(_Config) ->
    DailyRate = cb_interest:calculate_daily_rate(1000),
    Interest = cb_interest:calculate_interest(10000, DailyRate, 0),
    ?assertEqual(0, Interest),
    ok.

%% Test: Calculate compound interest with zero days
calculate_compound_interest_zero_days(_Config) ->
    Result = cb_interest:calculate_compound_interest(10000, 1000, 0, daily),
    ?assertEqual(10000, Result),  % Should return principal unchanged
    ok.

%% Test: Convert zero basis points to float
basis_points_to_float_zero(_Config) ->
    Float = cb_interest:basis_points_to_float(0),
    ?assertEqual(0.0, Float),
    ok.

%% Test: Convert zero float to basis points
float_to_basis_points_zero(_Config) ->
    Bps = cb_interest:float_to_basis_points(0.0),
    ?assertEqual(0, Bps),
    ok.

%% =============================================================================
%% cb_interest_accrual Tests
%% =============================================================================

create_test_account(_Config) ->
    UniqueId = integer_to_binary(erlang:unique_integer()),
    Email = <<"test", (UniqueId)/binary, "@example.com">>,
    {ok, Party} = cb_party:create_party(<<"Test Party ", UniqueId/binary>>, Email),
    {ok, Account} = cb_accounts:create_account(Party#party.party_id, <<"Test Account ", UniqueId/binary>>, 'USD'),
    Account.

%% Test: Start an accrual for an account
start_accrual_ok(_Config) ->
    Account = create_test_account(_Config),
    {ok, Accrual} = cb_interest_accrual:start_accrual(
        Account#account.account_id,
        <<"product-1">>,
        10000,
        500
    ),
    ?assertEqual(Account#account.account_id, Accrual#interest_accrual.account_id),
    ?assertEqual(500, Accrual#interest_accrual.interest_rate),
    ?assertEqual(accruing, Accrual#interest_accrual.status),
    ok.

%% Test: Start accrual for non-existent account
start_accrual_account_not_found(_Config) ->
    FakeId = <<"00000000-0000-0000-0000-000000000000">>,
    {error, Reason} = cb_interest_accrual:start_accrual(
        FakeId,
        <<"product-1">>,
        10000,
        500
    ),
    ?assertEqual(account_not_found, Reason),
    ok.

%% Test: Start accrual for closed account
start_accrual_account_closed(_Config) ->
    Account = create_test_account(_Config),
    {ok, _Closed} = cb_accounts:close_account(Account#account.account_id),
    {error, Reason} = cb_interest_accrual:start_accrual(
        Account#account.account_id,
        <<"product-1">>,
        10000,
        500
    ),
    ?assertEqual(account_closed, Reason),
    ok.

%% Test: Get an existing accrual
get_accrual_ok(_Config) ->
    Account = create_test_account(_Config),
    {ok, Created} = cb_interest_accrual:start_accrual(
        Account#account.account_id,
        <<"product-1">>,
        10000,
        500
    ),
    {ok, Retrieved} = cb_interest_accrual:get_accrual(Created#interest_accrual.accrual_id),
    ?assertEqual(Created#interest_accrual.accrual_id, Retrieved#interest_accrual.accrual_id),
    ok.

%% Test: Get non-existent accrual
get_accrual_not_found(_Config) ->
    FakeId = <<"00000000-0000-0000-0000-000000000000">>,
    {error, Reason} = cb_interest_accrual:get_accrual(FakeId),
    ?assertEqual(accrual_not_found, Reason),
    ok.

%% Test: Close an active accrual
close_accrual_ok(_Config) ->
    Account = create_test_account(_Config),
    {ok, Created} = cb_interest_accrual:start_accrual(
        Account#account.account_id,
        <<"product-1">>,
        10000,
        500
    ),
    {ok, Closed} = cb_interest_accrual:close_accrual(Created#interest_accrual.accrual_id),
    ?assertEqual(closed, Closed#interest_accrual.status),
    ?assert(is_integer(Closed#interest_accrual.end_date)),
    ok.

%% Test: Close non-existent accrual
close_accrual_not_found(_Config) ->
    FakeId = <<"00000000-0000-0000-0000-000000000000">>,
    {error, Reason} = cb_interest_accrual:close_accrual(FakeId),
    ?assertEqual(accrual_not_found, Reason),
    ok.

%% Test: Get active accruals
get_active_accruals_ok(_Config) ->
    Account1 = create_test_account(_Config),
    Account2 = create_test_account(_Config),
    {ok, _A1} = cb_interest_accrual:start_accrual(
        Account1#account.account_id, <<"p1">>, 10000, 500),
    {ok, _A2} = cb_interest_accrual:start_accrual(
        Account2#account.account_id, <<"p2">>, 20000, 300),

    Accruals = cb_interest_accrual:get_active_accruals(),
    ?assertEqual(2, length(Accruals)),
    ok.

%% Test: Get accruals for account
get_accruals_for_account_ok(_Config) ->
    Account = create_test_account(_Config),
    {ok, _A1} = cb_interest_accrual:start_accrual(
        Account#account.account_id, <<"p1">>, 10000, 500),
    {ok, _A2} = cb_interest_accrual:start_accrual(
        Account#account.account_id, <<"p2">>, 20000, 300),

    Accruals = cb_interest_accrual:get_accruals_for_account(Account#account.account_id),
    ?assertEqual(2, length(Accruals)),
    ok.

%% Test: Calculate daily accrual
calculate_daily_accrual_ok(_Config) ->
    Account = create_test_account(_Config),
    {ok, _Accrual} = cb_interest_accrual:start_accrual(
        Account#account.account_id,
        <<"product-1">>,
        10000,
        500
    ),

    DailyAccrual = cb_interest_accrual:calculate_daily_accrual(
        Account#account.account_id,
        10000
    ),
    ?assert(is_integer(DailyAccrual)),
    ?assert(DailyAccrual >= 0),
    ok.

%% =============================================================================
%% cb_interest_posting Tests
%% =============================================================================

%% Test: Post accrued interest to account
post_accrued_interest_ok(_Config) ->
    Account = create_test_account(_Config),
    {ok, TxnId} = cb_interest_posting:post_accrued_interest(
        Account#account.account_id,
        100
    ),
    ?assert(is_binary(TxnId)),
    ok.

%% Test: Post interest to non-existent account
post_accrued_interest_account_not_found(_Config) ->
    FakeId = <<"00000000-0000-0000-0000-000000000000">>,
    {error, Reason} = cb_interest_posting:post_accrued_interest(FakeId, 100),
    ?assertEqual(account_not_found, Reason),
    ok.

%% Test: Post interest to closed account
post_accrued_interest_account_closed(_Config) ->
    Account = create_test_account(_Config),
    {ok, _Closed} = cb_accounts:close_account(Account#account.account_id),
    {error, Reason} = cb_interest_posting:post_accrued_interest(
        Account#account.account_id,
        100
    ),
    ?assertEqual(account_closed, Reason),
    ok.

%% Test: Post zero interest amount (throws function_clause)
post_accrued_interest_zero_amount(_Config) ->
    Account = create_test_account(_Config),
    %% Zero amount throws function_clause as guard requires > 0
    ?assertError(function_clause, cb_interest_posting:post_accrued_interest(
        Account#account.account_id,
        0
    )),
    ok.

%% Test: Get interest expense account ID
get_interest_expense_account_id_ok(_Config) ->
    AccountId = cb_interest_posting:get_interest_expense_account_id(),
    ?assertEqual(<<"interest-expense">>, AccountId),
    ok.

%% Test: Get interest income account ID
get_interest_income_account_id_ok(_Config) ->
    AccountId = cb_interest_posting:get_interest_income_account_id(),
    ?assertEqual(<<"interest-income">>, AccountId),
    ok.
