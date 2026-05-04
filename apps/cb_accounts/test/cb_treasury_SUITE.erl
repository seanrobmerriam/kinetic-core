-module(cb_treasury_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1]).
-export([
    open_position_ok/1,
    get_position_ok/1,
    get_position_not_found/1,
    list_positions_ok/1,
    encumber_ok/1,
    encumber_insufficient/1,
    release_ok/1,
    close_position_ok/1,
    record_forecast_ok/1,
    get_forecasts_ok/1,
    place_interbank_ok/1
]).

all() ->
    [
        open_position_ok,
        get_position_ok,
        get_position_not_found,
        list_positions_ok,
        encumber_ok,
        encumber_insufficient,
        release_ok,
        close_position_ok,
        record_forecast_ok,
        get_forecasts_ok,
        place_interbank_ok
    ].

init_per_suite(Config) ->
    mnesia:start(),
    cb_schema:create_tables(),
    Config.

end_per_suite(_Config) ->
    mnesia:stop(),
    ok.

open_position_ok(_Config) ->
    {ok, Pos} = cb_treasury:open_position(#{
        account_id       => <<"acct-001">>,
        source_type      => central_bank,
        currency         => 'USD',
        available_amount => 1000000
    }),
    ?assert(is_binary(Pos#treasury_position.position_id)),
    ?assertEqual(active, Pos#treasury_position.status),
    ?assertEqual(0, Pos#treasury_position.encumbered_amount).

get_position_ok(_Config) ->
    {ok, Pos} = cb_treasury:open_position(#{
        account_id       => <<"acct-002">>,
        source_type      => repo,
        currency         => 'EUR',
        available_amount => 500000
    }),
    {ok, Got} = cb_treasury:get_position(Pos#treasury_position.position_id),
    ?assertEqual(Pos#treasury_position.position_id, Got#treasury_position.position_id).

get_position_not_found(_Config) ->
    {error, not_found} = cb_treasury:get_position(<<"no-such-id">>).

list_positions_ok(_Config) ->
    AccountId = <<"acct-list-test">>,
    {ok, _} = cb_treasury:open_position(#{
        account_id => AccountId, source_type => equity,
        currency => 'USD', available_amount => 100
    }),
    Positions = cb_treasury:list_positions(AccountId),
    ?assert(length(Positions) >= 1).

encumber_ok(_Config) ->
    {ok, Pos} = cb_treasury:open_position(#{
        account_id => <<"acct-enc">>, source_type => customer_deposits,
        currency => 'USD', available_amount => 10000
    }),
    {ok, Updated} = cb_treasury:encumber(Pos#treasury_position.position_id, 3000, <<"reserve">>),
    ?assertEqual(7000, Updated#treasury_position.available_amount),
    ?assertEqual(3000, Updated#treasury_position.encumbered_amount).

encumber_insufficient(_Config) ->
    {ok, Pos} = cb_treasury:open_position(#{
        account_id => <<"acct-enc2">>, source_type => interbank,
        currency => 'USD', available_amount => 500
    }),
    {error, insufficient_available} =
        cb_treasury:encumber(Pos#treasury_position.position_id, 1000, <<"too much">>).

release_ok(_Config) ->
    {ok, Pos} = cb_treasury:open_position(#{
        account_id => <<"acct-rel">>, source_type => central_bank,
        currency => 'USD', available_amount => 5000
    }),
    {ok, Encumbered} = cb_treasury:encumber(Pos#treasury_position.position_id, 2000, <<"reserve">>),
    {ok, Released}   = cb_treasury:release(Encumbered#treasury_position.position_id, 1000, <<"free">>),
    ?assertEqual(4000, Released#treasury_position.available_amount),
    ?assertEqual(1000, Released#treasury_position.encumbered_amount).

close_position_ok(_Config) ->
    {ok, Pos} = cb_treasury:open_position(#{
        account_id => <<"acct-close">>, source_type => repo,
        currency => 'USD', available_amount => 1000
    }),
    ok = cb_treasury:close_position(Pos#treasury_position.position_id),
    {ok, Closed} = cb_treasury:get_position(Pos#treasury_position.position_id),
    ?assertEqual(closed, Closed#treasury_position.status).

record_forecast_ok(_Config) ->
    {ok, FC} = cb_treasury:record_forecast(#{
        account_id    => <<"acct-fc">>,
        currency      => 'USD',
        forecast_date => 20250101,
        inflow_amount  => 100000,
        outflow_amount => 60000
    }),
    ?assertEqual(40000, FC#cash_forecast.net_amount).

get_forecasts_ok(_Config) ->
    AccountId = <<"acct-fc2">>,
    {ok, _} = cb_treasury:record_forecast(#{
        account_id    => AccountId,
        currency      => 'EUR',
        forecast_date => 20250201,
        inflow_amount  => 200000,
        outflow_amount => 150000
    }),
    FCs = cb_treasury:get_forecasts(AccountId, 'EUR'),
    ?assert(length(FCs) >= 1).

place_interbank_ok(_Config) ->
    {ok, Pos} = cb_treasury:place_interbank(<<"acct-ib">>, 'USD', 2000000, 1800000000000),
    ?assertEqual(interbank, Pos#treasury_position.source_type),
    ?assertEqual(active, Pos#treasury_position.status).
