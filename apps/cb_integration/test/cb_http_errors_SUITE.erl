-module(cb_http_errors_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1]).

-export([
    maps_party_not_suspended/1,
    maps_product_errors/1,
    maps_loan_validation_errors/1,
    maps_auth_errors/1,
    maps_generic_not_found/1,
    maps_unknown_to_internal_error/1
]).

all() ->
    [
        maps_party_not_suspended,
        maps_product_errors,
        maps_loan_validation_errors,
        maps_auth_errors,
        maps_generic_not_found,
        maps_unknown_to_internal_error
    ].

init_per_suite(Config) ->
    Config.

end_per_suite(_Config) ->
    ok.

maps_party_not_suspended(_Config) ->
    ?assertEqual(
        {409, <<"party_not_suspended">>, <<"Party is not suspended">>},
        cb_http_errors:to_response(party_not_suspended)
    ).

maps_product_errors(_Config) ->
    ?assertEqual(
        {404, <<"product_not_found">>, <<"Product not found">>},
        cb_http_errors:to_response(product_not_found)
    ),
    ?assertEqual(
        {409, <<"product_already_inactive">>, <<"Product is already inactive">>},
        cb_http_errors:to_response(product_already_inactive)
    ).

maps_loan_validation_errors(_Config) ->
    ?assertEqual(
        {422, <<"invalid_interest_rate">>, <<"Invalid interest rate">>},
        cb_http_errors:to_response(invalid_interest_rate)
    ),
    ?assertEqual(
        {409, <<"invalid_status">>, <<"Operation is not allowed in the current status">>},
        cb_http_errors:to_response(invalid_status)
    ).

maps_auth_errors(_Config) ->
    ?assertEqual(
        {401, <<"unauthorized">>, <<"Authentication required">>},
        cb_http_errors:to_response(unauthorized)
    ),
    ?assertEqual(
        {401, <<"invalid_credentials">>, <<"Invalid credentials">>},
        cb_http_errors:to_response(invalid_credentials)
    ).

maps_generic_not_found(_Config) ->
    ?assertEqual(
        {404, <<"not_found">>, <<"Resource not found">>},
        cb_http_errors:to_response(not_found)
    ),
    ?assertEqual(
        {404, <<"accrual_not_found">>, <<"Interest accrual not found">>},
        cb_http_errors:to_response(accrual_not_found)
    ).

maps_unknown_to_internal_error(_Config) ->
    ?assertEqual(
        {500, <<"internal_error">>, <<"An unexpected error occurred">>},
        cb_http_errors:to_response(unknown_future_error)
    ).
