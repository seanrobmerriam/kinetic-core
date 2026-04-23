-module(cb_savings_products_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").
-include("savings_product.hrl").
-include_lib("cb_events/include/cb_events.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1, init_per_testcase/2, end_per_testcase/2]).
-export([
    % Happy path tests
    create_product_ok/1,
    get_product_ok/1,
    list_products_ok/1,
    activate_product_ok/1,
    deactivate_product_ok/1,
    % Error path tests
    create_product_invalid_currency/1,
    create_product_invalid_interest_type/1,
    create_product_invalid_compounding_period/1,
    create_product_invalid_parameters/1,
    get_product_not_found/1,
    get_product_invalid_id/1,
    activate_product_not_found/1,
    activate_product_already_active/1,
    activate_product_invalid_id/1,
    deactivate_product_not_found/1,
    deactivate_product_already_inactive/1,
    deactivate_product_invalid_id/1,
    % Boundary tests
    create_product_zero_minimum_balance/1,
    list_products_empty/1,
    % Idempotency tests (not applicable - products are created fresh each time)
    % Atomicity tests (not applicable - single table operations)
    create_and_activate_product/1,
    create_and_deactivate_product/1,
    % P2-S3: versioning
    create_product_version_is_one/1,
    update_product_increments_version/1,
    % P2-S3: draft / lifecycle
    create_draft_product/1,
    launch_product_from_draft/1,
    launch_product_requires_draft/1,
    sunset_product_from_active/1,
    sunset_product_requires_active/1
]).

all() ->
    [
        % Happy path
        create_product_ok,
        get_product_ok,
        list_products_ok,
        activate_product_ok,
        deactivate_product_ok,
        % Error path
        create_product_invalid_currency,
        create_product_invalid_interest_type,
        create_product_invalid_compounding_period,
        create_product_invalid_parameters,
        get_product_not_found,
        get_product_invalid_id,
        activate_product_not_found,
        activate_product_already_active,
        activate_product_invalid_id,
        deactivate_product_not_found,
        deactivate_product_already_inactive,
        deactivate_product_invalid_id,
        % Boundary
        create_product_zero_minimum_balance,
        list_products_empty,
        % Combined state tests
        create_and_activate_product,
        create_and_deactivate_product,
        % P2-S3: versioning
        create_product_version_is_one,
        update_product_increments_version,
        % P2-S3: draft / lifecycle
        create_draft_product,
        launch_product_from_draft,
        launch_product_requires_draft,
        sunset_product_from_active,
        sunset_product_requires_active
    ].

init_per_suite(Config) ->
    mnesia:start(),
    % Create the savings_product table
    case mnesia:create_table(savings_product, [
        {ram_copies, [node()]},
        {attributes, record_info(fields, savings_product)},
        {index, [status, name]}
    ]) of
        {atomic, ok} -> ok;
        {aborted, {already_exists, _}} -> ok;
        {aborted, Reason} -> error({failed_to_create_table, Reason})
    end,
    case mnesia:create_table(event_outbox, [
        {ram_copies, [node()]},
        {attributes, record_info(fields, event_outbox)},
        {index, [status]}
    ]) of
        {atomic, ok} -> ok;
        {aborted, {already_exists, _}} -> ok;
        {aborted, Reason2} -> error({failed_to_create_table, Reason2})
    end,
    Config.

end_per_suite(_Config) ->
    mnesia:stop(),
    mnesia:delete_schema([node()]),
    ok.

init_per_testcase(_TestCase, Config) ->
    mnesia:clear_table(savings_product),
    mnesia:clear_table(event_outbox),
    Config.

end_per_testcase(_TestCase, _Config) ->
    ok.

%% =============================================================================
%% Happy Path Tests
%% =============================================================================

%% Test: Create a savings product with valid data
create_product_ok(_Config) ->
    {ok, Product} = cb_savings_products:create_product(
        <<"Premium Savings">>,
        <<"High interest savings account">>,
        'USD',
        250,
        simple,
        monthly,
        1000
    ),
    ?assertEqual(<<"Premium Savings">>, Product#savings_product.name),
    ?assertEqual(<<"High interest savings account">>, Product#savings_product.description),
    ?assertEqual('USD', Product#savings_product.currency),
    ?assertEqual(250, Product#savings_product.interest_rate),
    ?assertEqual(simple, Product#savings_product.interest_type),
    ?assertEqual(monthly, Product#savings_product.compounding_period),
    ?assertEqual(1000, Product#savings_product.minimum_balance),
    ?assertEqual(active, Product#savings_product.status),
    ?assert(is_binary(Product#savings_product.product_id)),
    ok.

%% Test: Get an existing savings product
get_product_ok(_Config) ->
    {ok, Created} = cb_savings_products:create_product(
        <<"Basic Savings">>,
        <<"Simple savings account">>,
        'EUR',
        150,
        compound,
        quarterly,
        500
    ),
    {ok, Retrieved} = cb_savings_products:get_product(Created#savings_product.product_id),
    ?assertEqual(Created#savings_product.product_id, Retrieved#savings_product.product_id),
    ?assertEqual(<<"Basic Savings">>, Retrieved#savings_product.name),
    ?assertEqual('EUR', Retrieved#savings_product.currency),
    ok.

%% Test: List all savings products
list_products_ok(_Config) ->
    {ok, _P1} = cb_savings_products:create_product(
        <<"Product 1">>, <<"Desc 1">>, 'USD', 100, simple, daily, 100),
    {ok, _P2} = cb_savings_products:create_product(
        <<"Product 2">>, <<"Desc 2">>, 'GBP', 200, compound, monthly, 200),
    {ok, _P3} = cb_savings_products:create_product(
        <<"Product 3">>, <<"Desc 3">>, 'EUR', 300, simple, quarterly, 300),

    {ok, Products} = cb_savings_products:list_products(),
    ?assertEqual(3, length(Products)),
    ok.

%% Test: Activate an inactive product
activate_product_ok(_Config) ->
    {ok, Created} = cb_savings_products:create_product(
        <<"Test Product">>, <<"Test">>, 'USD', 100, simple, daily, 100),
    % Products are created as active by default, so deactivate first
    {ok, Inactive} = cb_savings_products:deactivate_product(Created#savings_product.product_id),
    ?assertEqual(inactive, Inactive#savings_product.status),

    {ok, Activated} = cb_savings_products:activate_product(Created#savings_product.product_id),
    ?assertEqual(active, Activated#savings_product.status),
    ok.

%% Test: Deactivate an active product
deactivate_product_ok(_Config) ->
    {ok, Created} = cb_savings_products:create_product(
        <<"Test Product">>, <<"Test">>, 'USD', 100, simple, daily, 100),
    ?assertEqual(active, Created#savings_product.status),

    {ok, Deactivated} = cb_savings_products:deactivate_product(Created#savings_product.product_id),
    ?assertEqual(inactive, Deactivated#savings_product.status),
    ok.

%% =============================================================================
%% Error Path Tests
%% =============================================================================

%% Test: Create product with unsupported currency
create_product_invalid_currency(_Config) ->
    {error, Reason} = cb_savings_products:create_product(
        <<"Test">>, <<"Test">>, 'XYZ', 100, simple, daily, 100),
    ?assertEqual(unsupported_currency, Reason),
    ok.

%% Test: Create product with invalid interest type
create_product_invalid_interest_type(_Config) ->
    {error, Reason} = cb_savings_products:create_product(
        <<"Test">>, <<"Test">>, 'USD', 100, invalid_type, daily, 100),
    ?assertEqual(invalid_interest_type, Reason),
    ok.

%% Test: Create product with invalid compounding period
create_product_invalid_compounding_period(_Config) ->
    {error, Reason} = cb_savings_products:create_product(
        <<"Test">>, <<"Test">>, 'USD', 100, simple, invalid_period, 100),
    ?assertEqual(invalid_compounding_period, Reason),
    ok.

%% Test: Create product with invalid parameters (negative minimum balance)
create_product_invalid_parameters(_Config) ->
    {error, Reason} = cb_savings_products:create_product(
        <<"Test">>, <<"Test">>, 'USD', 100, simple, daily, -100),
    ?assertEqual(invalid_parameters, Reason),
    ok.

%% Test: Get non-existent product
get_product_not_found(_Config) ->
    FakeId = <<"00000000-0000-0000-0000-000000000000">>,
    {error, Reason} = cb_savings_products:get_product(FakeId),
    ?assertEqual(product_not_found, Reason),
    ok.

%% Test: Get product with invalid ID (non-binary)
get_product_invalid_id(_Config) ->
    {error, Reason} = cb_savings_products:get_product(not_a_binary),
    ?assertEqual(invalid_product_id, Reason),
    ok.

%% Test: Activate non-existent product
activate_product_not_found(_Config) ->
    FakeId = <<"00000000-0000-0000-0000-000000000000">>,
    {error, Reason} = cb_savings_products:activate_product(FakeId),
    ?assertEqual(product_not_found, Reason),
    ok.

%% Test: Activate already active product
activate_product_already_active(_Config) ->
    {ok, Created} = cb_savings_products:create_product(
        <<"Test">>, <<"Test">>, 'USD', 100, simple, daily, 100),
    % Already active by default
    {error, Reason} = cb_savings_products:activate_product(Created#savings_product.product_id),
    ?assertEqual(product_already_active, Reason),
    ok.

%% Test: Activate product with invalid ID (non-binary)
activate_product_invalid_id(_Config) ->
    {error, Reason} = cb_savings_products:activate_product(not_a_binary),
    ?assertEqual(invalid_product_id, Reason),
    ok.

%% Test: Deactivate non-existent product
deactivate_product_not_found(_Config) ->
    FakeId = <<"00000000-0000-0000-0000-000000000000">>,
    {error, Reason} = cb_savings_products:deactivate_product(FakeId),
    ?assertEqual(product_not_found, Reason),
    ok.

%% Test: Deactivate already inactive product
deactivate_product_already_inactive(_Config) ->
    {ok, Created} = cb_savings_products:create_product(
        <<"Test">>, <<"Test">>, 'USD', 100, simple, daily, 100),
    {ok, _Inactive} = cb_savings_products:deactivate_product(Created#savings_product.product_id),
    {error, Reason} = cb_savings_products:deactivate_product(Created#savings_product.product_id),
    ?assertEqual(product_already_inactive, Reason),
    ok.

%% Test: Deactivate product with invalid ID (non-binary)
deactivate_product_invalid_id(_Config) ->
    {error, Reason} = cb_savings_products:deactivate_product(not_a_binary),
    ?assertEqual(invalid_product_id, Reason),
    ok.

%% =============================================================================
%% Boundary Tests
%% =============================================================================

%% Test: Create product with zero minimum balance (valid boundary)
create_product_zero_minimum_balance(_Config) ->
    {ok, Product} = cb_savings_products:create_product(
        <<"Zero Minimum">>,
        <<"No minimum balance required">>,
        'JPY',
        50,
        compound,
        annually,
        0
    ),
    ?assertEqual(0, Product#savings_product.minimum_balance),
    ok.

%% Test: List products when none exist
list_products_empty(_Config) ->
    {ok, Products} = cb_savings_products:list_products(),
    ?assertEqual([], Products),
    ok.

%% =============================================================================
%% Combined State Tests (verify product lifecycle)
%% =============================================================================

%% Test: Full product lifecycle - create, deactivate, then activate
create_and_activate_product(_Config) ->
    {ok, Created} = cb_savings_products:create_product(
        <<"Lifecycle Product">>, <<"Testing lifecycle">>, 'JPY', 10, simple, monthly, 10000),
    ?assertEqual(active, Created#savings_product.status),

    {ok, Deactivated} = cb_savings_products:deactivate_product(Created#savings_product.product_id),
    ?assertEqual(inactive, Deactivated#savings_product.status),

    {ok, Reactivated} = cb_savings_products:activate_product(Created#savings_product.product_id),
    ?assertEqual(active, Reactivated#savings_product.status),

    ok.

%% Test: Full product lifecycle - create, activate, then deactivate
create_and_deactivate_product(_Config) ->
    {ok, Created} = cb_savings_products:create_product(
        <<"Lifecycle Product 2">>, <<"Testing lifecycle 2">>, 'GBP', 100, compound, quarterly, 5000),
    ?assertEqual(active, Created#savings_product.status),

    {ok, Deactivated} = cb_savings_products:deactivate_product(Created#savings_product.product_id),
    ?assertEqual(inactive, Deactivated#savings_product.status),

    ok.

%% =============================================================================
%% P2-S3: Versioning tests
%% =============================================================================

create_product_version_is_one(_Config) ->
    {ok, Product} = cb_savings_products:create_product(
        <<"Version Test">>, <<"Test">>, 'USD', 100, simple, monthly, 500),
    ?assertEqual(1, Product#savings_product.version),
    ok.

update_product_increments_version(_Config) ->
    {ok, Product} = cb_savings_products:create_product(
        <<"Version Test">>, <<"Test">>, 'USD', 100, simple, monthly, 500),
    ?assertEqual(1, Product#savings_product.version),
    {ok, Updated} = cb_savings_products:update_product(
        Product#savings_product.product_id, #{name => <<"Updated Name">>}),
    ?assertEqual(2, Updated#savings_product.version),
    ok.

%% =============================================================================
%% P2-S3: Draft / lifecycle tests
%% =============================================================================

create_draft_product(_Config) ->
    {ok, Product} = cb_savings_products:create_draft_product(
        <<"Draft Savings">>, <<"A draft">>, 'USD', 150, simple, monthly, 200),
    ?assertEqual(draft, Product#savings_product.status),
    ok.

launch_product_from_draft(_Config) ->
    {ok, Product} = cb_savings_products:create_draft_product(
        <<"Draft Savings">>, <<"A draft">>, 'USD', 150, simple, monthly, 200),
    {ok, Launched} = cb_savings_products:launch_product(Product#savings_product.product_id),
    ?assertEqual(active, Launched#savings_product.status),
    ok.

launch_product_requires_draft(_Config) ->
    {ok, Product} = cb_savings_products:create_product(
        <<"Active Product">>, <<"Already active">>, 'USD', 100, simple, monthly, 100),
    {error, Reason} = cb_savings_products:launch_product(Product#savings_product.product_id),
    ?assertEqual(product_not_in_draft, Reason),
    ok.

sunset_product_from_active(_Config) ->
    {ok, Product} = cb_savings_products:create_product(
        <<"Active Product">>, <<"Will sunset">>, 'USD', 100, simple, monthly, 100),
    {ok, Sunset} = cb_savings_products:sunset_product(Product#savings_product.product_id),
    ?assertEqual(sunset, Sunset#savings_product.status),
    ok.

sunset_product_requires_active(_Config) ->
    {ok, Product} = cb_savings_products:create_draft_product(
        <<"Draft Savings">>, <<"A draft">>, 'USD', 150, simple, monthly, 200),
    {error, Reason} = cb_savings_products:sunset_product(Product#savings_product.product_id),
    ?assertEqual(product_not_active, Reason),
    ok.
