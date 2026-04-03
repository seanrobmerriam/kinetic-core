-module(cb_runtime_wiring_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").
-include_lib("cb_ledger/include/cb_ledger.hrl").
-include_lib("cb_loans/include/loan.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1, init_per_testcase/2, end_per_testcase/2]).

-export([
    schema_creates_feature_tables/1,
    applications_start_feature_workers/1,
    feature_lifecycle_ok/1
]).

all() ->
    [
        schema_creates_feature_tables,
        applications_start_feature_workers,
        feature_lifecycle_ok
    ].

init_per_suite(Config) ->
    mnesia:start(),
    cb_schema:create_tables(),
    {ok, _} = application:ensure_all_started(cb_interest),
    {ok, _} = application:ensure_all_started(cb_loans),
    {ok, _} = application:ensure_all_started(cb_auth),
    {ok, _} = application:ensure_all_started(cb_approvals),
    {ok, _} = application:ensure_all_started(cb_events),
    {ok, _} = application:ensure_all_started(cb_reporting),
    Config.

end_per_suite(_Config) ->
    ok = application:stop(cb_reporting),
    ok = application:stop(cb_events),
    ok = application:stop(cb_approvals),
    ok = application:stop(cb_auth),
    ok = application:stop(cb_loans),
    ok = application:stop(cb_interest),
    ok = application:stop(cb_savings_products),
    mnesia:stop(),
    mnesia:delete_schema([node()]),
    ok.

init_per_testcase(_TestCase, Config) ->
    lists:foreach(
        fun(Table) -> mnesia:clear_table(Table) end,
        [party, account, transaction, ledger_entry, savings_product,
         loan_products, loan_accounts, loan_repayments, interest_accrual,
         auth_user, auth_session, audit_log, approval_request, approval_decision,
         event_outbox, webhook_subscription, webhook_delivery,
         report_statement, report_export]
    ),
    Config.

end_per_testcase(_TestCase, _Config) ->
    ok.

index_names(Table) ->
    Attributes = mnesia:table_info(Table, attributes),
    [lists:nth(Position - 1, Attributes) || Position <- mnesia:table_info(Table, index)].

schema_creates_feature_tables(_Config) ->
    ?assertEqual(loan_product, mnesia:table_info(loan_products, record_name)),
    ?assertEqual(loan_account, mnesia:table_info(loan_accounts, record_name)),
    ?assertEqual(loan_repayment, mnesia:table_info(loan_repayments, record_name)),
    ?assertEqual(
        [currency, status],
        lists:sort(index_names(loan_products))
    ),
    ?assertEqual(
        [account_id, party_id, status],
        lists:sort(index_names(loan_accounts))
    ),
    ?assertEqual(
        [loan_id, status],
        lists:sort(index_names(loan_repayments))
    ),
    ?assertEqual(
        [account_id, status],
        lists:sort(index_names(interest_accrual))
    ),
    ?assertEqual(
        [email, role, status],
        lists:sort(index_names(auth_user))
    ),
    ?assertEqual(
        [expires_at, user_id],
        lists:sort(index_names(auth_session))
    ),
    ?assertEqual(
        [actor_user_id, entity_type],
        lists:sort(index_names(audit_log))
    ),
    ?assertEqual(
        [resource_id, resource_type, status],
        lists:sort(index_names(approval_request))
    ),
    ?assertEqual(
        [approved_by, request_id],
        lists:sort(index_names(approval_decision))
    ),
    ?assertEqual(
        [event_type, status],
        lists:sort(index_names(event_outbox))
    ),
    ?assertEqual(
        [event_type, status],
        lists:sort(index_names(webhook_subscription))
    ),
    ?assertEqual(
        [attempt_status, subscription_id],
        lists:sort(index_names(webhook_delivery))
    ),
    ?assertEqual(
        [account_id, generated_at],
        lists:sort(index_names(report_statement))
    ),
    ?assertEqual(
        [export_type, status],
        lists:sort(index_names(report_export))
    ),
    ok.

applications_start_feature_workers(_Config) ->
    RunningApps = [App || {App, _Description, _Vsn} <- application:which_applications()],
    ?assert(lists:member(cb_auth, RunningApps)),
    ?assert(lists:member(cb_approvals, RunningApps)),
    ?assert(lists:member(cb_events, RunningApps)),
    ?assert(lists:member(cb_reporting, RunningApps)),
    ?assert(lists:member(cb_interest, RunningApps)),
    ?assert(lists:member(cb_savings_products, RunningApps)),
    ?assert(lists:member(cb_loans, RunningApps)),
    ?assertMatch(Pid when is_pid(Pid), whereis(cb_loan_products)),
    ?assertMatch(Pid when is_pid(Pid), whereis(cb_loan_accounts)),
    ?assertMatch(Pid when is_pid(Pid), whereis(cb_loan_repayments)),
    ?assertMatch(Pid when is_pid(Pid), whereis(cb_auth_sessions)),
    ?assertMatch(Pid when is_pid(Pid), whereis(cb_approvals)),
    ?assertMatch(Pid when is_pid(Pid), whereis(cb_events)),
    ?assertMatch(Pid when is_pid(Pid), whereis(cb_reporting)),
    ok.

feature_lifecycle_ok(_Config) ->
    {ok, SavingsProduct} = cb_savings_products:create_product(
        <<"High Yield Savings">>,
        <<"Interest bearing savings product">>,
        'USD',
        450,
        compound,
        monthly,
        10000
    ),
    SavingsProductId = element(2, SavingsProduct),
    {ok, SavingsProduct} = cb_savings_products:get_product(SavingsProductId),
    {ok, [ListedSavingsProduct]} = cb_savings_products:list_products(),
    ?assertEqual(SavingsProductId, element(2, ListedSavingsProduct)),

    {ok, Party} = cb_party:create_party(<<"Runtime Wiring Customer">>, <<"runtime@example.com">>),
    {ok, Account} = cb_accounts:create_account(Party#party.party_id, <<"Loan Settlement">>, 'USD'),
    {ok, LoanProductId} = cb_loan_products:create_product(
        <<"Runtime Loan">>,
        <<"Loan product used by runtime wiring tests">>,
        'USD',
        10000,
        500000,
        6,
        24,
        1200,
        flat
    ),
    {ok, LoanProduct} = cb_loan_products:get_product(LoanProductId),
    ?assertEqual(1200, LoanProduct#loan_product.interest_rate),
    ?assertEqual(1, length(cb_loan_products:list_products())),

    {ok, LoanId} = cb_loan_accounts:create_loan(
        LoanProductId,
        Party#party.party_id,
        Account#account.account_id,
        20000,
        'USD',
        12,
        1200
    ),
    {ok, ApprovedLoan} = cb_loan_accounts:approve_loan(LoanId),
    ?assertEqual(approved, ApprovedLoan#loan_account.status),
    {ok, DisbursedLoan} = cb_loan_accounts:disburse_loan(LoanId),
    ?assertEqual(disbursed, DisbursedLoan#loan_account.status),

    DueDate = erlang:system_time(millisecond) + 30 * 24 * 60 * 60 * 1000,
    {ok, RepaymentId} = cb_loan_repayments:record_repayment(LoanId, 5000, DueDate, 5000),
    {ok, UpdatedLoan, 15000} = cb_loan_accounts:make_repayment(LoanId, 5000),
    ?assertEqual(disbursed, UpdatedLoan#loan_account.status),
    [Repayment] = cb_loan_repayments:get_repayments(LoanId),
    ?assertEqual(RepaymentId, Repayment#loan_repayment.repayment_id),
    ?assertEqual(5000, Repayment#loan_repayment.principal_portion),
    ?assertEqual(paid, Repayment#loan_repayment.status),
    ok.
