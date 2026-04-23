%%%===================================================================
%%%
%%% @doc Loan Product Management Module
%%%
%%% This module manages loan product definitions in the IronLedger
%%% core banking system. Loan products are templates that define
%%% standardized loan offerings.
%%%
%%% <h2>Loan Products</h2>
%%%
%%% A loan product represents a standardized loan offering with
%%% predefined terms that customers can apply for. Products include:
%%%
%%% <ul>
%%%   <li><b>Product Type</b>: Personal loan, auto loan, mortgage, etc.</li>
%%%   <li><b>Amount Range</b>: Minimum and maximum principal amounts</li>
%%%   <li><b>Term Range</b>: Minimum and maximum loan terms</li>
%%%   <li><b>Interest Rate</b>: Annual rate and calculation method</li>
%%%   <li><b>Currency</b>: Supported currencies</li>
%%% </ul>
%%%
%%% <h2>Product Lifecycle</h2>
%%%
%%% <ol>
%%%   <li><b>Draft</b>: Product configured but not yet available</li>
%%%   <li><b>Active</b>: Product is available for new applications</li>
%%%   <li><b>Inactive</b>: Product temporarily suspended</li>
%%%   <li><b>Sunset</b>: Product permanently retired</li>
%%% </ol>
%%%
%%% @end
%%%===================================================================

-module(cb_loan_products).
-behaviour(gen_server).

-export([
         start_link/0,
         create_product/9,
         create_draft_product/9,
         get_product/1,
         list_products/0,
         update_product/2,
         activate_product/1,
         deactivate_product/1,
         launch_product/1,
         sunset_product/1,
         set_eligibility/2,
         set_fees/2,
         check_eligibility/2
        ]).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% Suppress Dialyzer warnings for mnesia select with pattern matching
-dialyzer({nowarn_function, do_list_products/0}).

-include("loan.hrl").
-include_lib("cb_ledger/include/cb_ledger.hrl").
-include_lib("cb_events/include/cb_events.hrl").

-define(SERVER, ?MODULE).
-define(TABLE, loan_products).
-define(BPS_FACTOR, 10000).

-record(state, {}).

%%
%% @doc Starts the loan products gen_server.
%%
%% Initializes the Mnesia table for product storage and
%% links the process to the supervision tree.
%%
%% @returns {ok, pid()} on success, {error, term()} on failure
%%
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%%
%% @doc Creates a new loan product definition.
%%
%% Defines a new loan product template with specified terms.
%% The product is created in 'active' status and immediately
%% available for loan applications.
%%
%% @param Name Product name (e.g., "Personal Loan")
%% @param Description Detailed product description
%% @param Currency ISO 4217 currency code
%% @param MinAmount Minimum principal amount
%% @param MaxAmount Maximum principal amount
%% @param MinTermMonths Minimum term in months
%% @param MaxTermMonths Maximum term in months
%% @param InterestRate Annual interest rate
%% @param InterestType 'flat' or 'declining'
%%
%% @returns {ok, product_id()} on success, {error, term()} on failure
%%
-spec create_product(binary(), binary(), atom(), integer(), integer(), integer(), integer(), non_neg_integer(), atom()) ->
    {ok, product_id()} | {error, term()}.
create_product(Name, Description, Currency, MinAmount, MaxAmount, MinTermMonths, MaxTermMonths, InterestRate, InterestType) ->
    gen_server:call(?SERVER, {create_product, Name, Description, Currency, MinAmount, MaxAmount, MinTermMonths, MaxTermMonths, InterestRate, InterestType}).

%%
%% @doc Retrieves a loan product by its identifier.
%%
%% @param ProductId The unique product identifier
%%
%% @returns {ok, loan_product()} if found, {error, not_found} if not found
%%
-spec get_product(product_id()) -> {ok, loan_product()} | {error, not_found}.
get_product(ProductId) ->
    gen_server:call(?SERVER, {get_product, ProductId}).

%%
%% @doc Lists all active loan products.
%%
%% Returns all products that are currently active and available
%% for new loan applications.
%%
%% @returns List of active loan_product() records
%%
-spec list_products() -> [loan_product()].
list_products() ->
    gen_server:call(?SERVER, list_products).

%%
%% @doc Updates an existing loan product.
%%
%% Allows modification of product attributes such as rates,
%% amounts, and terms. Only active fields can be updated.
%%
%% @param ProductId The unique product identifier
%% @param Updates Map of field names to new values
%%
%% @returns {ok, loan_product()} on success, {error, term()} on failure
%%
-spec update_product(product_id(), map()) -> {ok, loan_product()} | {error, term()}.
update_product(ProductId, Updates) ->
    gen_server:call(?SERVER, {update_product, ProductId, Updates}).

%%
%% @doc Activates an inactive loan product.
%%
%% Marks the product as inactive, preventing new loan applications
%% while preserving existing loans for reporting purposes.
%%
%% @param ProductId The unique product identifier
%%
%% @returns {ok, loan_product()} on success, {error, term()} on failure
%%
-spec activate_product(product_id()) -> {ok, loan_product()} | {error, term()}.
activate_product(ProductId) ->
    gen_server:call(?SERVER, {activate_product, ProductId}).

%%
%% @doc Deactivates a loan product.
%%
%% Marks the product as inactive, preventing new loan applications
%% while preserving existing loans for reporting purposes.
%%
%% @param ProductId The unique product identifier
%%
%% @returns {ok, loan_product()} on success, {error, term()} on failure
%%
-spec deactivate_product(product_id()) -> {ok, loan_product()} | {error, term()}.
deactivate_product(ProductId) ->
    gen_server:call(?SERVER, {deactivate_product, ProductId}).

init([]) ->
    case mnesia:create_table(?TABLE, [
        {attributes, record_info(fields, loan_product)},
        {record_name, loan_product},
        {type, set},
        {ram_copies, [node()]},
        {index, [currency, status]}
    ]) of
        {atomic, ok} -> ok;
        {aborted, {already_exists, _}} -> ok;
        {aborted, Reason} -> error(Reason)
    end,
    {ok, #state{}}.

handle_call({create_product, Name, Description, Currency, MinAmount, MaxAmount, MinTermMonths, MaxTermMonths, InterestRate, InterestType}, _From, State) ->
    Reply = do_create_product(Name, Description, Currency, MinAmount, MaxAmount, MinTermMonths, MaxTermMonths, InterestRate, InterestType),
    {reply, Reply, State};

handle_call({get_product, ProductId}, _From, State) ->
    Reply = do_get_product(ProductId),
    {reply, Reply, State};

handle_call(list_products, _From, State) ->
    Reply = do_list_products(),
    {reply, Reply, State};

handle_call({update_product, ProductId, Updates}, _From, State) ->
    Reply = do_update_product(ProductId, Updates),
    {reply, Reply, State};

handle_call({activate_product, ProductId}, _From, State) ->
    Reply = do_activate_product(ProductId),
    {reply, Reply, State};

handle_call({deactivate_product, ProductId}, _From, State) ->
    Reply = do_deactivate_product(ProductId),
    {reply, Reply, State};

handle_call({create_draft_product, Name, Description, Currency, MinAmount, MaxAmount, MinTermMonths, MaxTermMonths, InterestRate, InterestType}, _From, State) ->
    Reply = do_create_draft_product(Name, Description, Currency, MinAmount, MaxAmount, MinTermMonths, MaxTermMonths, InterestRate, InterestType),
    {reply, Reply, State};

handle_call({launch_product, ProductId}, _From, State) ->
    Reply = do_launch_product(ProductId),
    {reply, Reply, State};

handle_call({sunset_product, ProductId}, _From, State) ->
    Reply = do_sunset_product(ProductId),
    {reply, Reply, State};

handle_call({set_eligibility, ProductId, Eligibility}, _From, State) ->
    Reply = do_set_eligibility(ProductId, Eligibility),
    {reply, Reply, State};

handle_call({set_fees, ProductId, Fees}, _From, State) ->
    Reply = do_set_fees(ProductId, Fees),
    {reply, Reply, State};

handle_call({check_eligibility, ProductId, Application}, _From, State) ->
    Reply = do_check_eligibility(ProductId, Application),
    {reply, Reply, State};

handle_call(_Request, _From, State) ->
    {reply, unknown_call, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

do_create_product(Name, Description, Currency, MinAmount, MaxAmount, MinTermMonths, MaxTermMonths, InterestRate, InterestType) ->
    ValidCurrency = validate_currency(Currency),
    ValidInterestType = validate_interest_type(InterestType),
    ValidInterestRate = validate_interest_rate(InterestRate),
    ValidRanges = validate_product_ranges(MinAmount, MaxAmount, MinTermMonths, MaxTermMonths),
    case {ValidCurrency, ValidInterestType, ValidInterestRate, ValidRanges} of
        {ok, ok, ok, ok} ->
            ProductId = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
            Now = erlang:system_time(millisecond),
            Product = #loan_product{
                product_id = ProductId,
                name = Name,
                description = Description,
                currency = Currency,
                min_amount = MinAmount,
                max_amount = MaxAmount,
                min_term_months = MinTermMonths,
                max_term_months = MaxTermMonths,
                interest_rate = InterestRate,
                interest_type = InterestType,
                status = active,
                version = 1,
                eligibility = #{},
                fees = #{},
                created_at = Now,
                updated_at = Now
            },
            Fun = fun() ->
                mnesia:write(?TABLE, Product, write),
                _ = cb_events:write_outbox(<<"loan_product.created">>, #{product_id => ProductId})
            end,
            case mnesia:transaction(Fun) of
                {atomic, _} -> {ok, ProductId};
                {aborted, Reason} -> {error, Reason}
            end;
        {{error, _} = CurrencyError, _, _, _} ->
            CurrencyError;
        {ok, {error, _} = InterestTypeError, _, _} ->
            InterestTypeError;
        {ok, ok, {error, _} = InterestRateError, _} ->
            InterestRateError;
        {ok, ok, ok, {error, _} = RangeError} ->
            RangeError
    end.

do_get_product(ProductId) ->
    Fun = fun() -> mnesia:read({?TABLE, ProductId}) end,
    case mnesia:transaction(Fun) of
        {atomic, [Product]} -> {ok, Product};
        {atomic, []} -> {error, not_found}
    end.

do_list_products() ->
    Fun = fun() -> mnesia:select(?TABLE, [{#loan_product{status = '$1', _ = '_'}, [{'==', '$1', active}], ['$_']}]) end,
    case mnesia:transaction(Fun) of
        {atomic, Products} -> Products
    end.

do_update_product(ProductId, Updates) ->
    case is_binary(ProductId) of
        true ->
            do_update_product_binary(ProductId, Updates);
        false ->
            {error, invalid_product_id}
    end.

do_update_product_binary(ProductId, Updates) ->
    Fun = fun() ->
        case mnesia:read({?TABLE, ProductId}) of
            [Product] ->
                UpdatedProduct = apply_updates(Product, Updates),
                case validate_product_ranges(
                    UpdatedProduct#loan_product.min_amount,
                    UpdatedProduct#loan_product.max_amount,
                    UpdatedProduct#loan_product.min_term_months,
                    UpdatedProduct#loan_product.max_term_months
                ) of
                    ok ->
                        mnesia:write(?TABLE, UpdatedProduct, write),
                        {ok, UpdatedProduct};
                    {error, _} = RangeError ->
                        RangeError
                end;
            [] ->
                {error, not_found}
        end
    end,
    case mnesia:transaction(Fun) of
        {atomic, Result} -> Result;
        {aborted, Reason} -> {error, Reason}
    end.

do_activate_product(ProductId) when is_binary(ProductId) ->
    do_set_product_status(ProductId, active);
do_activate_product(_ProductId) ->
    {error, invalid_product_id}.

do_deactivate_product(ProductId) when is_binary(ProductId) ->
    do_set_product_status(ProductId, inactive);
do_deactivate_product(_ProductId) ->
    {error, invalid_product_id}.

do_set_product_status(ProductId, DesiredStatus) ->
    Fun = fun() ->
        case mnesia:read({?TABLE, ProductId}) of
            [Product] ->
                CurrentStatus = Product#loan_product.status,
                case {CurrentStatus, DesiredStatus} of
                    {active, active} ->
                        {error, product_already_active};
                    {inactive, inactive} ->
                        {error, product_already_inactive};
                    _ ->
                        Updated = Product#loan_product{
                            status = DesiredStatus,
                            updated_at = erlang:system_time(millisecond)
                        },
                        mnesia:write(?TABLE, Updated, write),
                        EventType = case DesiredStatus of
                            active   -> <<"loan_product.activated">>;
                            inactive -> <<"loan_product.deactivated">>
                        end,
                        _ = cb_events:write_outbox(EventType, #{product_id => ProductId}),
                        {ok, Updated}
                end;
            [] ->
                {error, product_not_found}
        end
    end,
    case mnesia:transaction(Fun) of
        {atomic, Result} -> Result;
        {aborted, Reason} -> {error, Reason}
    end.

apply_updates(Product, Updates) ->
    Now = erlang:system_time(millisecond),
    WithFields = maps:fold(fun(K, V, Acc) ->
        case K of
            name -> Acc#loan_product{name = V, updated_at = Now};
            description -> Acc#loan_product{description = V, updated_at = Now};
            currency -> Acc#loan_product{currency = V, updated_at = Now};
            min_amount -> Acc#loan_product{min_amount = V, updated_at = Now};
            max_amount -> Acc#loan_product{max_amount = V, updated_at = Now};
            min_term_months -> Acc#loan_product{min_term_months = V, updated_at = Now};
            max_term_months -> Acc#loan_product{max_term_months = V, updated_at = Now};
            interest_rate -> Acc#loan_product{interest_rate = V, updated_at = Now};
            interest_type -> Acc#loan_product{interest_type = V, updated_at = Now};
            status -> Acc#loan_product{status = V, updated_at = Now};
            _ -> Acc
        end
    end, Product, Updates),
    WithFields#loan_product{
        version = Product#loan_product.version + 1,
        updated_at = Now
    }.

%%
%% @doc Creates a new loan product in draft status.
%%
%% Same parameters as create_product/9 but the product starts in
%% 'draft' state and must be launched before accepting applications.
%%
-spec create_draft_product(binary(), binary(), atom(), integer(), integer(), integer(), integer(), non_neg_integer(), atom()) ->
    {ok, product_id()} | {error, term()}.
create_draft_product(Name, Description, Currency, MinAmount, MaxAmount, MinTermMonths, MaxTermMonths, InterestRate, InterestType) ->
    gen_server:call(?SERVER, {create_draft_product, Name, Description, Currency, MinAmount, MaxAmount, MinTermMonths, MaxTermMonths, InterestRate, InterestType}).

%%
%% @doc Transitions a loan product from draft to active.
%%
%% Only products in 'draft' status can be launched. Bumps the version.
%%
-spec launch_product(product_id()) -> {ok, loan_product()} | {error, term()}.
launch_product(ProductId) ->
    gen_server:call(?SERVER, {launch_product, ProductId}).

%%
%% @doc Permanently retires an active loan product.
%%
%% Transitions the product from 'active' to 'sunset'. Bumps the version.
%% No new loans can be created under a sunset product.
%%
-spec sunset_product(product_id()) -> {ok, loan_product()} | {error, term()}.
sunset_product(ProductId) ->
    gen_server:call(?SERVER, {sunset_product, ProductId}).

%%
%% @doc Sets the eligibility criteria map for a loan product.
%%
%% Eligibility keys: min_credit_score, max_dti_bps, min_annual_income.
%% Bumps the product version on each call.
%%
-spec set_eligibility(product_id(), map()) -> {ok, loan_product()} | {error, term()}.
set_eligibility(ProductId, Eligibility) ->
    gen_server:call(?SERVER, {set_eligibility, ProductId, Eligibility}).

%%
%% @doc Sets the fee schedule map for a loan product.
%%
%% Fees keys: origination_fee_bps, late_fee, prepayment_fee_bps.
%% Bumps the product version on each call.
%%
-spec set_fees(product_id(), map()) -> {ok, loan_product()} | {error, term()}.
set_fees(ProductId, Fees) ->
    gen_server:call(?SERVER, {set_fees, ProductId, Fees}).

%%
%% @doc Checks whether an application meets the product eligibility criteria.
%%
%% Application map keys: credit_score, dti_bps, annual_income.
%%
-spec check_eligibility(product_id(), map()) -> ok | {error, term()}.
check_eligibility(ProductId, Application) ->
    gen_server:call(?SERVER, {check_eligibility, ProductId, Application}).

validate_currency(Currency) ->
    ValidCurrencies = ['USD', 'EUR', 'GBP', 'JPY'],
    case lists:member(Currency, ValidCurrencies) of
        true -> ok;
        false -> {error, unsupported_currency}
    end.

validate_interest_type(InterestType) ->
    ValidTypes = [flat, declining],
    case lists:member(InterestType, ValidTypes) of
        true -> ok;
        false -> {error, invalid_interest_type}
    end.

validate_interest_rate(InterestRate) when not is_integer(InterestRate) ->
    {error, invalid_interest_rate};
validate_interest_rate(InterestRate) when InterestRate < 0 ->
    {error, invalid_interest_rate};
validate_interest_rate(InterestRate) when InterestRate > ?BPS_FACTOR ->
    {error, interest_rate_too_high};
validate_interest_rate(_InterestRate) ->
    ok.

validate_product_ranges(MinAmount, MaxAmount, MinTermMonths, MaxTermMonths)
        when is_integer(MinAmount), is_integer(MaxAmount),
             is_integer(MinTermMonths), is_integer(MaxTermMonths) ->
    case {MinAmount > 0, MaxAmount >= MinAmount} of
        {true, true} ->
            case {MinTermMonths > 0, MaxTermMonths >= MinTermMonths} of
                {true, true} -> ok;
                _ -> {error, invalid_term_range}
            end;
        _ ->
            {error, invalid_amount_range}
    end;
validate_product_ranges(_, _, _, _) ->
    {error, invalid_parameters}.

do_create_draft_product(Name, Description, Currency, MinAmount, MaxAmount, MinTermMonths, MaxTermMonths, InterestRate, InterestType) ->
    ValidCurrency = validate_currency(Currency),
    ValidInterestType = validate_interest_type(InterestType),
    ValidInterestRate = validate_interest_rate(InterestRate),
    ValidRanges = validate_product_ranges(MinAmount, MaxAmount, MinTermMonths, MaxTermMonths),
    case {ValidCurrency, ValidInterestType, ValidInterestRate, ValidRanges} of
        {ok, ok, ok, ok} ->
            ProductId = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
            Now = erlang:system_time(millisecond),
            Product = #loan_product{
                product_id = ProductId,
                name = Name,
                description = Description,
                currency = Currency,
                min_amount = MinAmount,
                max_amount = MaxAmount,
                min_term_months = MinTermMonths,
                max_term_months = MaxTermMonths,
                interest_rate = InterestRate,
                interest_type = InterestType,
                status = draft,
                version = 1,
                eligibility = #{},
                fees = #{},
                created_at = Now,
                updated_at = Now
            },
            Fun = fun() ->
                mnesia:write(?TABLE, Product, write),
                _ = cb_events:write_outbox(<<"loan_product.draft_created">>, #{product_id => ProductId})
            end,
            case mnesia:transaction(Fun) of
                {atomic, _} -> {ok, ProductId};
                {aborted, Reason} -> {error, Reason}
            end;
        {{error, _} = CurrencyError, _, _, _} ->
            CurrencyError;
        {ok, {error, _} = InterestTypeError, _, _} ->
            InterestTypeError;
        {ok, ok, {error, _} = InterestRateError, _} ->
            InterestRateError;
        {ok, ok, ok, {error, _} = RangeError} ->
            RangeError
    end.

do_launch_product(ProductId) when is_binary(ProductId) ->
    Fun = fun() ->
        case mnesia:read({?TABLE, ProductId}) of
            [Product] ->
                case Product#loan_product.status of
                    draft ->
                        Now = erlang:system_time(millisecond),
                        Updated = Product#loan_product{
                            status = active,
                            version = Product#loan_product.version + 1,
                            updated_at = Now
                        },
                        mnesia:write(?TABLE, Updated, write),
                        _ = cb_events:write_outbox(<<"loan_product.launched">>, #{product_id => ProductId}),
                        {ok, Updated};
                    _ ->
                        {error, product_not_in_draft}
                end;
            [] ->
                {error, product_not_found}
        end
    end,
    case mnesia:transaction(Fun) of
        {atomic, Result} -> Result;
        {aborted, Reason} -> {error, Reason}
    end;
do_launch_product(_) ->
    {error, invalid_product_id}.

do_sunset_product(ProductId) when is_binary(ProductId) ->
    Fun = fun() ->
        case mnesia:read({?TABLE, ProductId}) of
            [Product] ->
                case Product#loan_product.status of
                    active ->
                        Now = erlang:system_time(millisecond),
                        Updated = Product#loan_product{
                            status = sunset,
                            version = Product#loan_product.version + 1,
                            updated_at = Now
                        },
                        mnesia:write(?TABLE, Updated, write),
                        _ = cb_events:write_outbox(<<"loan_product.sunset">>, #{product_id => ProductId}),
                        {ok, Updated};
                    _ ->
                        {error, product_not_active}
                end;
            [] ->
                {error, product_not_found}
        end
    end,
    case mnesia:transaction(Fun) of
        {atomic, Result} -> Result;
        {aborted, Reason} -> {error, Reason}
    end;
do_sunset_product(_) ->
    {error, invalid_product_id}.

do_set_eligibility(ProductId, Eligibility) when is_binary(ProductId), is_map(Eligibility) ->
    Fun = fun() ->
        case mnesia:read({?TABLE, ProductId}) of
            [Product] ->
                Now = erlang:system_time(millisecond),
                Updated = Product#loan_product{
                    eligibility = Eligibility,
                    version = Product#loan_product.version + 1,
                    updated_at = Now
                },
                mnesia:write(?TABLE, Updated, write),
                {ok, Updated};
            [] ->
                {error, product_not_found}
        end
    end,
    case mnesia:transaction(Fun) of
        {atomic, Result} -> Result;
        {aborted, Reason} -> {error, Reason}
    end;
do_set_eligibility(_, _) ->
    {error, invalid_parameters}.

do_set_fees(ProductId, Fees) when is_binary(ProductId), is_map(Fees) ->
    Fun = fun() ->
        case mnesia:read({?TABLE, ProductId}) of
            [Product] ->
                Now = erlang:system_time(millisecond),
                Updated = Product#loan_product{
                    fees = Fees,
                    version = Product#loan_product.version + 1,
                    updated_at = Now
                },
                mnesia:write(?TABLE, Updated, write),
                {ok, Updated};
            [] ->
                {error, product_not_found}
        end
    end,
    case mnesia:transaction(Fun) of
        {atomic, Result} -> Result;
        {aborted, Reason} -> {error, Reason}
    end;
do_set_fees(_, _) ->
    {error, invalid_parameters}.

do_check_eligibility(ProductId, Application) when is_binary(ProductId), is_map(Application) ->
    case do_get_product(ProductId) of
        {ok, Product} ->
            check_eligibility_criteria(Product#loan_product.eligibility, Application);
        Error ->
            Error
    end;
do_check_eligibility(_, _) ->
    {error, invalid_parameters}.

check_eligibility_criteria(Eligibility, Application) ->
    Checks = [
        fun() -> check_min_credit_score(Eligibility, Application) end,
        fun() -> check_max_dti(Eligibility, Application) end,
        fun() -> check_min_income(Eligibility, Application) end
    ],
    lists:foldl(fun
        (_, {error, _} = Err) -> Err;
        (CheckFun, ok)        -> CheckFun()
    end, ok, Checks).

check_min_credit_score(Eligibility, Application) ->
    case maps:get(min_credit_score, Eligibility, undefined) of
        undefined -> ok;
        MinScore ->
            case maps:get(credit_score, Application, 0) of
                Score when Score >= MinScore -> ok;
                _ -> {error, insufficient_credit_score}
            end
    end.

check_max_dti(Eligibility, Application) ->
    case maps:get(max_dti_bps, Eligibility, undefined) of
        undefined -> ok;
        MaxDti ->
            case maps:get(dti_bps, Application, 0) of
                Dti when Dti =< MaxDti -> ok;
                _ -> {error, dti_too_high}
            end
    end.

check_min_income(Eligibility, Application) ->
    case maps:get(min_annual_income, Eligibility, undefined) of
        undefined -> ok;
        MinIncome ->
            case maps:get(annual_income, Application, 0) of
                Income when Income >= MinIncome -> ok;
                _ -> {error, insufficient_income}
            end
    end.
