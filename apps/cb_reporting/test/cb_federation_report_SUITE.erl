-module(cb_federation_report_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1]).
-export([
    submit_ok/1,
    get_report_ok/1,
    get_report_not_found/1,
    list_reports_ok/1,
    run_consolidated_balance_ok/1,
    run_cross_product_pnl_ok/1,
    run_regulatory_snapshot_ok/1,
    run_customer_360_ok/1
]).

all() ->
    [
        submit_ok,
        get_report_ok,
        get_report_not_found,
        list_reports_ok,
        run_consolidated_balance_ok,
        run_cross_product_pnl_ok,
        run_regulatory_snapshot_ok,
        run_customer_360_ok
    ].

init_per_suite(Config) ->
    mnesia:start(),
    cb_schema:create_tables(),
    Config.

end_per_suite(_Config) ->
    mnesia:stop(),
    ok.

submit_ok(_Config) ->
    {ok, R} = cb_federation_report:submit(#{
        report_type  => consolidated_balance,
        requested_by => <<"user-001">>,
        params       => #{}
    }),
    ?assert(is_binary(R#federation_report.report_id)),
    ?assertEqual(pending, R#federation_report.status).

get_report_ok(_Config) ->
    {ok, R}   = cb_federation_report:submit(#{
        report_type  => cross_product_pnl,
        requested_by => <<"user-002">>,
        params       => #{}
    }),
    {ok, Got} = cb_federation_report:get_report(R#federation_report.report_id),
    ?assertEqual(R#federation_report.report_id, Got#federation_report.report_id).

get_report_not_found(_Config) ->
    {error, not_found} = cb_federation_report:get_report(<<"no-report-id">>).

list_reports_ok(_Config) ->
    User = <<"user-list">>,
    {ok, _} = cb_federation_report:submit(#{
        report_type  => regulatory_snapshot,
        requested_by => User,
        params       => #{}
    }),
    Reports = cb_federation_report:list_reports(User),
    ?assert(length(Reports) >= 1).

run_consolidated_balance_ok(_Config) ->
    {ok, R}    = cb_federation_report:submit(#{
        report_type  => consolidated_balance,
        requested_by => <<"user-cb">>,
        params       => #{}
    }),
    {ok, Done} = cb_federation_report:run(R#federation_report.report_id),
    ?assertEqual(completed, Done#federation_report.status),
    ?assert(is_map(Done#federation_report.result)).

run_cross_product_pnl_ok(_Config) ->
    {ok, R}    = cb_federation_report:submit(#{
        report_type  => cross_product_pnl,
        requested_by => <<"user-pnl">>,
        params       => #{}
    }),
    {ok, Done} = cb_federation_report:run(R#federation_report.report_id),
    ?assertEqual(completed, Done#federation_report.status),
    ?assertMatch(#{fee_income := _, interest_income := _, total_pnl := _},
                 Done#federation_report.result).

run_regulatory_snapshot_ok(_Config) ->
    {ok, R}    = cb_federation_report:submit(#{
        report_type  => regulatory_snapshot,
        requested_by => <<"user-reg">>,
        params       => #{}
    }),
    {ok, Done} = cb_federation_report:run(R#federation_report.report_id),
    ?assertEqual(completed, Done#federation_report.status),
    ?assertMatch(#{metrics := _, breached_metrics := _, capital_buffers := _},
                 Done#federation_report.result).

run_customer_360_ok(_Config) ->
    {ok, R}    = cb_federation_report:submit(#{
        report_type  => customer_360,
        requested_by => <<"user-c360">>,
        params       => #{party_id => <<"party-z">>}
    }),
    {ok, Done} = cb_federation_report:run(R#federation_report.report_id),
    ?assertEqual(completed, Done#federation_report.status),
    ?assertMatch(#{accounts := _, instruments := _}, Done#federation_report.result).
