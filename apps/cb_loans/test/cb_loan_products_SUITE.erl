-module(cb_loan_products_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").
-include("loan.hrl").
-include_lib("cb_events/include/cb_events.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1, init_per_testcase/2, end_per_testcase/2]).
-export([
    create_product_invalid_amount_range/1,
    create_product_invalid_term_range/1,
    deactivate_and_activate_product/1,
    deactivate_already_inactive/1,
    activate_already_active/1,
    create_loan_rejects_inactive_product/1,
    create_loan_rejects_amount_out_of_product_range/1,
    create_loan_rejects_term_out_of_product_range/1,
    create_loan_accepts_active_in_range/1
]).

all() ->
    [
        create_product_invalid_amount_range,
        create_product_invalid_term_range,
        deactivate_and_activate_product,
        deactivate_already_inactive,
        activate_already_active,
        create_loan_rejects_inactive_product,
        create_loan_rejects_amount_out_of_product_range,
        create_loan_rejects_term_out_of_product_range,
        create_loan_accepts_active_in_range
    ].

init_per_suite(Config) ->
    mnesia:start(),
    case mnesia:create_table(event_outbox, [
        {ram_copies, [node()]},
        {attributes, record_info(fields, event_outbox)},
        {index, [status]}
    ]) of
        {atomic, ok} -> ok;
        {aborted, {already_exists, _}} -> ok
    end,
    {ok, _Started} = application:ensure_all_started(cb_loans),
    Config.

end_per_suite(_Config) ->
    ok = application:stop(cb_loans),
    mnesia:stop(),
    mnesia:delete_schema([node()]),
    ok.

init_per_testcase(_TestCase, Config) ->
    mnesia:clear_table(loan_products),
    mnesia:clear_table(loan_accounts),
    mnesia:clear_table(event_outbox),
    Config.

end_per_testcase(_TestCase, _Config) ->
    ok.

create_product_invalid_amount_range(_Config) ->
    {error, Reason} = cb_loan_products:create_product(
        <<"Bad Product">>,
        <<"invalid amount range">>,
        'USD',
        10000,
        1000,
        6,
        12,
        1200,
        flat
    ),
    ?assertEqual(invalid_amount_range, Reason),
    ok.

create_product_invalid_term_range(_Config) ->
    {error, Reason} = cb_loan_products:create_product(
        <<"Bad Product">>,
        <<"invalid term range">>,
        'USD',
        1000,
        10000,
        24,
        6,
        1200,
        flat
    ),
    ?assertEqual(invalid_term_range, Reason),
    ok.

deactivate_and_activate_product(_Config) ->
    {ok, ProductId} = create_standard_product(),

    {ok, Deactivated} = cb_loan_products:deactivate_product(ProductId),
    ?assertEqual(inactive, Deactivated#loan_product.status),

    {ok, Activated} = cb_loan_products:activate_product(ProductId),
    ?assertEqual(active, Activated#loan_product.status),
    ok.

deactivate_already_inactive(_Config) ->
    {ok, ProductId} = create_standard_product(),
    {ok, _} = cb_loan_products:deactivate_product(ProductId),
    {error, Reason} = cb_loan_products:deactivate_product(ProductId),
    ?assertEqual(product_already_inactive, Reason),
    ok.

activate_already_active(_Config) ->
    {ok, ProductId} = create_standard_product(),
    {error, Reason} = cb_loan_products:activate_product(ProductId),
    ?assertEqual(product_already_active, Reason),
    ok.

create_loan_rejects_inactive_product(_Config) ->
    {ok, ProductId} = create_standard_product(),
    {ok, _} = cb_loan_products:deactivate_product(ProductId),

    {error, Reason} = cb_loan_accounts:create_loan(
        ProductId,
        <<"party-1">>,
        <<"account-1">>,
        2000,
        'USD',
        12,
        1200
    ),
    ?assertEqual(product_inactive, Reason),
    ok.

create_loan_rejects_amount_out_of_product_range(_Config) ->
    {ok, ProductId} = create_standard_product(),

    {error, Reason} = cb_loan_accounts:create_loan(
        ProductId,
        <<"party-1">>,
        <<"account-1">>,
        6000,
        'USD',
        12,
        1200
    ),
    ?assertEqual(amount_out_of_product_range, Reason),
    ok.

create_loan_rejects_term_out_of_product_range(_Config) ->
    {ok, ProductId} = create_standard_product(),

    {error, Reason} = cb_loan_accounts:create_loan(
        ProductId,
        <<"party-1">>,
        <<"account-1">>,
        2000,
        'USD',
        48,
        1200
    ),
    ?assertEqual(term_out_of_product_range, Reason),
    ok.

create_loan_accepts_active_in_range(_Config) ->
    {ok, ProductId} = create_standard_product(),

    {ok, LoanId} = cb_loan_accounts:create_loan(
        ProductId,
        <<"party-1">>,
        <<"account-1">>,
        2000,
        'USD',
        12,
        1200
    ),
    ?assert(is_binary(LoanId)),
    ok.

create_standard_product() ->
    cb_loan_products:create_product(
        <<"Standard Loan">>,
        <<"Standard product">>,
        'USD',
        1000,
        5000,
        6,
        24,
        1200,
        flat
    ).

