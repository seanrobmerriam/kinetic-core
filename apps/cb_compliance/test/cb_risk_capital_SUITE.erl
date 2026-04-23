-module(cb_risk_capital_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1]).
-export([
    record_metric_ok/1,
    get_metric_ok/1,
    get_metric_not_found/1,
    list_metrics_ok/1,
    list_breaches_ok/1,
    check_limit_pass/1,
    check_limit_breach/1,
    allocate_buffer_ok/1,
    get_buffer_ok/1,
    get_buffer_not_found/1,
    list_buffers_ok/1,
    release_buffer_ok/1
]).

all() ->
    [
        record_metric_ok,
        get_metric_ok,
        get_metric_not_found,
        list_metrics_ok,
        list_breaches_ok,
        check_limit_pass,
        check_limit_breach,
        allocate_buffer_ok,
        get_buffer_ok,
        get_buffer_not_found,
        list_buffers_ok,
        release_buffer_ok
    ].

init_per_suite(Config) ->
    mnesia:start(),
    cb_schema:create_tables(),
    Config.

end_per_suite(_Config) ->
    mnesia:stop(),
    ok.

record_metric_ok(_Config) ->
    {ok, M} = cb_risk_capital:record_metric(#{
        account_id  => <<"acct-001">>,
        metric_type => var_95,
        value       => 120000,
        limit_value => 500000
    }),
    ?assert(is_binary(M#risk_metric.metric_id)),
    ?assertEqual(var_95, M#risk_metric.metric_type),
    ?assertEqual(false, M#risk_metric.breached).

get_metric_ok(_Config) ->
    {ok, M}   = cb_risk_capital:record_metric(#{
        account_id  => <<"acct-002">>,
        metric_type => exposure,
        value       => 50000,
        limit_value => 100000
    }),
    {ok, Got} = cb_risk_capital:get_metric(M#risk_metric.metric_id),
    ?assertEqual(M#risk_metric.metric_id, Got#risk_metric.metric_id).

get_metric_not_found(_Config) ->
    {error, not_found} = cb_risk_capital:get_metric(<<"no-metric">>).

list_metrics_ok(_Config) ->
    AccountId = <<"acct-list">>,
    {ok, _} = cb_risk_capital:record_metric(#{
        account_id  => AccountId, metric_type => liquidity_coverage,
        value => 1500000, limit_value => 1000000
    }),
    Ms = cb_risk_capital:list_metrics(AccountId, liquidity_coverage),
    ?assert(length(Ms) >= 1).

list_breaches_ok(_Config) ->
    {ok, _} = cb_risk_capital:record_metric(#{
        account_id  => <<"acct-breach">>, metric_type => var_99,
        value => 900000, limit_value => 500000
    }),
    Breaches = cb_risk_capital:current_breaches(),
    ?assert(length(Breaches) >= 1).

check_limit_pass(_Config) ->
    ok = cb_risk_capital:check_limit(var_95, 100000, 500000).

check_limit_breach(_Config) ->
    {breach, 600000, 500000} = cb_risk_capital:check_limit(exposure, 600000, 500000).

allocate_buffer_ok(_Config) ->
    {ok, B} = cb_risk_capital:allocate_buffer(#{
        buffer_type => conservation,
        amount      => 2000000,
        currency    => 'USD'
    }),
    ?assert(is_binary(B#capital_buffer.buffer_id)),
    ?assertEqual(conservation, B#capital_buffer.buffer_type).

get_buffer_ok(_Config) ->
    {ok, B}   = cb_risk_capital:allocate_buffer(#{
        buffer_type => countercyclical,
        amount => 1000000, currency => 'EUR'
    }),
    {ok, Got} = cb_risk_capital:get_buffer(B#capital_buffer.buffer_id),
    ?assertEqual(B#capital_buffer.buffer_id, Got#capital_buffer.buffer_id).

get_buffer_not_found(_Config) ->
    {error, not_found} = cb_risk_capital:get_buffer(<<"no-buf">>).

list_buffers_ok(_Config) ->
    {ok, _} = cb_risk_capital:allocate_buffer(#{
        buffer_type => systemic,
        amount => 5000000, currency => 'USD'
    }),
    Bufs = cb_risk_capital:list_buffers(),
    ?assert(length(Bufs) >= 1).

release_buffer_ok(_Config) ->
    {ok, B} = cb_risk_capital:allocate_buffer(#{
        buffer_type => conservation,
        amount => 3000000, currency => 'USD'
    }),
    ok = cb_risk_capital:release_buffer(B#capital_buffer.buffer_id),
    {error, not_found} = cb_risk_capital:get_buffer(B#capital_buffer.buffer_id).
