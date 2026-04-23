%%%
%%% @doc Savings Products Management Module.
%%%
%%% This module provides the core API for managing savings products in the
%%% IronLedger core banking system.
%%%
%%% ## Overview
%%%
%%% Savings products define the terms and conditions for interest-bearing
%%% deposit accounts. Banks offer various savings products to meet different
%%% customer needs - from basic savings accounts to high-yield savings accounts.
%%%
%%% This module allows:
%%% <ul>
%%%   <li>Creating new savings product definitions</li>
%%%   <li>Retrieving product details</li>
%%%   <li>Listing all available products</li>
%%%   <li>Activating/deactivating products</li>
%%% </ul>
%%%
%%% ## Usage Example
%%%
%%% <pre>
%%% % Create a high-yield savings product
%%% {ok, Product} = cb_savings_products:create_product(
%%%     <<"High-Yield Savings">>,
%%%     <<"4.5% APY, daily compounding, $100 minimum balance">>,
%%%     'USD',
%%%     450,
%%%     compound,
%%%     daily,
%%%     10000
%%% ).
%%%
%%% % List all active products
%%% {ok, Products} = cb_savings_products:list_products().
%%%
%%% % Deactivate a product (e.g., promotional product ended)
%%% {ok, Updated} = cb_savings_products:deactivate_product(ProductId).
%%% </pre>
%%%
%%% ## Data Storage
%%%
%%% All savings products are stored in the Mnesia table `savings_product`.
%%% All operations are transactional to ensure consistency.
%%%
%%% @see savings_product.hrl
%%% @see cb_interest

-module(cb_savings_products).

-include("savings_product.hrl").
-include_lib("cb_events/include/cb_events.hrl").

-export([
    create_product/7,
    create_draft_product/7,
    get_product/1,
    list_products/0,
    update_product/2,
    activate_product/1,
    deactivate_product/1,
    launch_product/1,
    sunset_product/1
]).

%%%
%%% @doc Creates a new savings product with the specified parameters.
%%%
%%% Creates and persists a new savings product definition. The product
%%% is created with `active` status, making it immediately available
%%% for opening new savings accounts.
%%%
%%% @param Name Human-readable name for the product
%%% @param Description Detailed description of product terms
%%% @param Currency ISO 4217 currency code (atom)
%%% @param InterestRate Annual interest rate in basis points (e.g., 500 = 5.00%)
%%% @param InterestType Type of interest calculation: `simple` or `compound`
%%% @param CompoundingPeriod How often interest compounds: `daily`, `monthly`, `quarterly`, `annually`
%%% @param MinimumBalance Minimum balance in minor units to earn interest
%%%
%%% @returns `{ok, SavingsProduct}' on success
%%% @returns `{error, unsupported_currency}' if currency not supported
%%% @returns `{error, invalid_interest_type}' if interest type is invalid
%%% @returns `{error, invalid_compounding_period}' if compounding period is invalid
%%% @returns `{error, invalid_parameters}' if any parameter fails validation
%%% @returns `{error, database_error}' if Mnesia transaction fails
%%%
%%% @example
%%% {ok, Product} = cb_savings_products:create_product(
%%%     <<"Basic Savings">>,
%%%     <<"Simple savings account with competitive rates">>,
%%%     'USD',
%%%     10,
%%%     simple,
%%%     monthly,
%%%     0
%%% ).
%%%
-spec create_product(
    Name        :: binary(),
    Description :: binary(),
    Currency    :: atom(),
    InterestRate :: non_neg_integer(),
    InterestType :: atom(),
    CompoundingPeriod :: atom(),
    MinimumBalance :: integer()
) -> {ok, savings_product()} | {error, atom()}.
create_product(Name, Description, Currency, InterestRate, InterestType, CompoundingPeriod, MinimumBalance)
        when is_binary(Name), is_binary(Description),
             is_integer(InterestRate), InterestRate >= 0, InterestRate =< 10000,
             is_integer(MinimumBalance), MinimumBalance >= 0 ->
    case lists:member(Currency, ?VALID_CURRENCIES) of
        true ->
            case lists:member(InterestType, ?VALID_INTEREST_TYPES) of
                true ->
                    case lists:member(CompoundingPeriod, ?VALID_COMPOUNDING_PERIODS) of
                        true ->
                            F = fun() ->
                                Now = erlang:system_time(millisecond),
                                ProductId = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
                                Product = #savings_product{
                                    product_id = ProductId,
                                    name = Name,
                                    description = Description,
                                    currency = Currency,
                                    interest_rate = InterestRate,
                                    interest_type = InterestType,
                                    compounding_period = CompoundingPeriod,
                                    minimum_balance = MinimumBalance,
                                    status = active,
                                    version = 1,
                                    created_at = Now,
                                    updated_at = Now
                                },
                                mnesia:write(Product),
                                _ = cb_events:write_outbox(<<"savings_product.created">>, #{
                                    product_id => ProductId,
                                    name       => Name,
                                    currency   => Currency
                                }),
                                {ok, Product}
                            end,
                            case mnesia:transaction(F) of
                                {atomic, Result} -> Result;
                                {aborted, _Reason} -> {error, database_error}
                            end;
                        false ->
                            {error, invalid_compounding_period}
                    end;
                false ->
                    {error, invalid_interest_type}
            end;
        false ->
            {error, unsupported_currency}
    end;
create_product(_, _, _, _, _, _, _) ->
    {error, invalid_parameters}.

%%%
%%% @doc Retrieves a savings product by its unique identifier.
%%%
%%% Looks up a savings product in the database by its product ID.
%%% Returns the complete product record including all configuration details.
%%%
%%% @param ProductId Unique UUID of the savings product
%%%
%%% @returns `{ok, SavingsProduct}' if product exists
%%% @returns `{error, product_not_found}' if no product with given ID exists
%%% @returns `{error, invalid_product_id}' if ProductId is not a binary
%%% @returns `{error, database_error}' if Mnesia transaction fails
%%%
%%% @example
%%% {ok, Product} = cb_savings_products:get_product(ProductId),
%%% io:format("Product: ~p~n", [Product#savings_product.name]).
%%%
-spec get_product(ProductId :: product_id()) -> {ok, savings_product()} | {error, atom()}.
get_product(ProductId) when is_binary(ProductId) ->
    F = fun() ->
        case mnesia:read(savings_product, ProductId) of
            [Product] -> {ok, Product};
            [] -> {error, product_not_found}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, _Reason} -> {error, database_error}
    end;
get_product(_) ->
    {error, invalid_product_id}.

%%%
%%% @doc Lists all savings products in the system.
%%%
%%% Retrieves all savings product definitions, sorted by creation date
%%% (newest first). Returns all products regardless of status - both
%%% active and inactive products are included.
%%%
%%% @returns `{ok, [SavingsProduct]}' containing all products sorted by creation date
%%% @returns `{error, database_error}' if Mnesia transaction fails
%%%
%%% @example
%%% {ok, Products} = cb_savings_products:list_products(),
%%% ActiveProducts = [P || P <- Products, P#savings_product.status =:= active].
%%%
-spec list_products() -> {ok, [savings_product()]} | {error, atom()}.
list_products() ->
    F = fun() ->
        AllProducts = mnesia:select(savings_product, [{'_', [], ['$_']}]),
        Sorted = lists:sort(
            fun(A, B) -> A#savings_product.created_at >= B#savings_product.created_at end,
            AllProducts
        ),
        Sorted
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> {ok, Result};
        {aborted, _Reason} -> {error, database_error}
    end.

%%%
%%% @doc Activates a previously inactive savings product.
%%%
%%% Changes the status of a savings product from `inactive` to `active`.
%%% Once activated, new savings accounts can be opened under this product.
%%%
%%% This operation is useful for:
%%% <ul>
%%%   <li>Reactivating a promotional product</li>
%%%   <li>Enabling a product that was temporarily suspended</li>
%%%   <li>Launching a new product in phases</li>
%%% </ul>
%%%
%%% @param ProductId Unique UUID of the savings product to activate
%%%
%%% @returns `{ok, UpdatedProduct}' with updated status if successful
%%% @returns `{error, product_not_found}' if product doesn't exist
%%% @returns `{error, product_already_active}' if product is already active
%%% @returns `{error, invalid_product_id}' if ProductId is not a binary
%%% @returns `{error, database_error}' if Mnesia transaction fails
%%%
%%% @example
%%% {ok, Updated} = cb_savings_products:activate_product(ProductId),
%%% true = Updated#savings_product.status =:= active.
%%%
-spec activate_product(ProductId :: product_id()) -> {ok, savings_product()} | {error, atom()}.
activate_product(ProductId) when is_binary(ProductId) ->
    F = fun() ->
        case mnesia:read(savings_product, ProductId, write) of
            [Product] ->
                case Product#savings_product.status of
                    inactive ->
                        Now = erlang:system_time(millisecond),
                        Updated = Product#savings_product{status = active, updated_at = Now},
                        mnesia:write(Updated),
                        _ = cb_events:write_outbox(<<"savings_product.activated">>, #{product_id => ProductId}),
                        {ok, Updated};
                    active ->
                        {error, product_already_active}
                end;
            [] ->
                {error, product_not_found}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, _Reason} -> {error, database_error}
    end;
activate_product(_) ->
    {error, invalid_product_id}.

%%%
%%% @doc Deactivates an active savings product.
%%%
%%% Changes the status of a savings product from `active` to `inactive`.
%%% Once deactivated, no new savings accounts can be opened under this product.
%%% Existing accounts continue to function normally and earn interest.
%%%
%%% This operation is useful for:
%%% <ul>
%%%   <li>Ending a promotional product offer</li>
%%%   <li>Phasing out an obsolete product</li>
%%%   <li>Temporarily suspending new account openings</li>
%%% </ul>
%%%
%%% Note: Deactivating a product does NOT affect existing savings accounts
%%% opened under that product. They remain active and continue to earn
%%% interest according to the product terms.
%%%
%%% @param ProductId Unique UUID of the savings product to deactivate
%%%
%%% @returns `{ok, UpdatedProduct}' with updated status if successful
%%% @returns `{error, product_not_found}' if product doesn't exist
%%% @returns `{error, product_already_inactive}' if product is already inactive
%%% @returns `{error, invalid_product_id}' if ProductId is not a binary
%%% @returns `{error, database_error}' if Mnesia transaction fails
%%%
%%% @example
%%% % End a promotional high-yield product
%%% {ok, Updated} = cb_savings_products:deactivate_product(PromotionalProductId),
%%% true = Updated#savings_product.status =:= inactive.
%%%
-spec deactivate_product(ProductId :: product_id()) -> {ok, savings_product()} | {error, atom()}.
deactivate_product(ProductId) when is_binary(ProductId) ->
    F = fun() ->
        case mnesia:read(savings_product, ProductId, write) of
            [Product] ->
                case Product#savings_product.status of
                    active ->
                        Now = erlang:system_time(millisecond),
                        Updated = Product#savings_product{status = inactive, updated_at = Now},
                        mnesia:write(Updated),
                        _ = cb_events:write_outbox(<<"savings_product.deactivated">>, #{product_id => ProductId}),
                        {ok, Updated};
                    inactive ->
                        {error, product_already_inactive}
                end;
            [] ->
                {error, product_not_found}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, _Reason} -> {error, database_error}
    end;
deactivate_product(_) ->
    {error, invalid_product_id}.

%%%
%%% @doc Creates a new savings product in draft status.
%%%
%%% Same parameters as create_product/7 but the product starts in `draft`
%%% state. Use launch_product/1 to make it available for new accounts.
%%%
-spec create_draft_product(
    Name        :: binary(),
    Description :: binary(),
    Currency    :: atom(),
    InterestRate :: non_neg_integer(),
    InterestType :: atom(),
    CompoundingPeriod :: atom(),
    MinimumBalance :: integer()
) -> {ok, savings_product()} | {error, atom()}.
create_draft_product(Name, Description, Currency, InterestRate, InterestType, CompoundingPeriod, MinimumBalance)
        when is_binary(Name), is_binary(Description),
             is_integer(InterestRate), InterestRate >= 0, InterestRate =< 10000,
             is_integer(MinimumBalance), MinimumBalance >= 0 ->
    case lists:member(Currency, ?VALID_CURRENCIES) of
        true ->
            case lists:member(InterestType, ?VALID_INTEREST_TYPES) of
                true ->
                    case lists:member(CompoundingPeriod, ?VALID_COMPOUNDING_PERIODS) of
                        true ->
                            F = fun() ->
                                Now = erlang:system_time(millisecond),
                                ProductId = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
                                Product = #savings_product{
                                    product_id = ProductId,
                                    name = Name,
                                    description = Description,
                                    currency = Currency,
                                    interest_rate = InterestRate,
                                    interest_type = InterestType,
                                    compounding_period = CompoundingPeriod,
                                    minimum_balance = MinimumBalance,
                                    status = draft,
                                    version = 1,
                                    created_at = Now,
                                    updated_at = Now
                                },
                                mnesia:write(Product),
                                _ = cb_events:write_outbox(<<"savings_product.draft_created">>, #{
                                    product_id => ProductId,
                                    name       => Name,
                                    currency   => Currency
                                }),
                                {ok, Product}
                            end,
                            case mnesia:transaction(F) of
                                {atomic, Result} -> Result;
                                {aborted, _Reason} -> {error, database_error}
                            end;
                        false ->
                            {error, invalid_compounding_period}
                    end;
                false ->
                    {error, invalid_interest_type}
            end;
        false ->
            {error, unsupported_currency}
    end;
create_draft_product(_, _, _, _, _, _, _) ->
    {error, invalid_parameters}.

%%%
%%% @doc Transitions a draft savings product to active status.
%%%
%%% Only products in `draft` status can be launched. Bumps the version counter.
%%%
-spec launch_product(ProductId :: product_id()) -> {ok, savings_product()} | {error, atom()}.
launch_product(ProductId) when is_binary(ProductId) ->
    F = fun() ->
        case mnesia:read(savings_product, ProductId, write) of
            [Product] ->
                case Product#savings_product.status of
                    draft ->
                        Now = erlang:system_time(millisecond),
                        Updated = Product#savings_product{
                            status = active,
                            version = Product#savings_product.version + 1,
                            updated_at = Now
                        },
                        mnesia:write(Updated),
                        _ = cb_events:write_outbox(<<"savings_product.launched">>, #{product_id => ProductId}),
                        {ok, Updated};
                    _ ->
                        {error, product_not_in_draft}
                end;
            [] ->
                {error, product_not_found}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, _Reason} -> {error, database_error}
    end;
launch_product(_) ->
    {error, invalid_product_id}.

%%%
%%% @doc Permanently retires an active savings product.
%%%
%%% Transitions the product from `active` to `sunset`. Bumps the version.
%%% No new accounts can be opened under a sunset product.
%%%
-spec sunset_product(ProductId :: product_id()) -> {ok, savings_product()} | {error, atom()}.
sunset_product(ProductId) when is_binary(ProductId) ->
    F = fun() ->
        case mnesia:read(savings_product, ProductId, write) of
            [Product] ->
                case Product#savings_product.status of
                    active ->
                        Now = erlang:system_time(millisecond),
                        Updated = Product#savings_product{
                            status = sunset,
                            version = Product#savings_product.version + 1,
                            updated_at = Now
                        },
                        mnesia:write(Updated),
                        _ = cb_events:write_outbox(<<"savings_product.sunset">>, #{product_id => ProductId}),
                        {ok, Updated};
                    _ ->
                        {error, product_not_active}
                end;
            [] ->
                {error, product_not_found}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, _Reason} -> {error, database_error}
    end;
sunset_product(_) ->
    {error, invalid_product_id}.

%%%
%%% @doc Updates fields on an existing savings product and bumps the version.
%%%
%%% Updatable fields: name, description, interest_rate, interest_type,
%%% compounding_period, minimum_balance. Currency and status are immutable
%%% via this function.
%%%
-spec update_product(ProductId :: product_id(), Updates :: map()) -> {ok, savings_product()} | {error, atom()}.
update_product(ProductId, Updates) when is_binary(ProductId), is_map(Updates) ->
    F = fun() ->
        case mnesia:read(savings_product, ProductId, write) of
            [Product] ->
                Now = erlang:system_time(millisecond),
                Updated = apply_savings_updates(Product, Updates, Now),
                mnesia:write(Updated),
                _ = cb_events:write_outbox(<<"savings_product.updated">>, #{product_id => ProductId}),
                {ok, Updated};
            [] ->
                {error, product_not_found}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, _Reason} -> {error, database_error}
    end;
update_product(_, _) ->
    {error, invalid_product_id}.

apply_savings_updates(Product, Updates, Now) ->
    WithFields = maps:fold(fun(K, V, Acc) ->
        case K of
            name               -> Acc#savings_product{name = V, updated_at = Now};
            description        -> Acc#savings_product{description = V, updated_at = Now};
            interest_rate      -> Acc#savings_product{interest_rate = V, updated_at = Now};
            interest_type      -> Acc#savings_product{interest_type = V, updated_at = Now};
            compounding_period -> Acc#savings_product{compounding_period = V, updated_at = Now};
            minimum_balance    -> Acc#savings_product{minimum_balance = V, updated_at = Now};
            _                  -> Acc
        end
    end, Product, Updates),
    WithFields#savings_product{
        version = Product#savings_product.version + 1,
        updated_at = Now
    }.
