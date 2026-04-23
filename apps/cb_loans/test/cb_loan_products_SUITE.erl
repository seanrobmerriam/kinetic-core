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
    create_loan_accepts_active_in_range/1,
    % P2-S3: versioning
    create_product_version_is_one/1,
    update_product_increments_version/1,
    % P2-S3: draft / lifecycle
    create_draft_product/1,
    launch_product_from_draft/1,
    launch_product_requires_draft/1,
    sunset_product_from_active/1,
    sunset_product_requires_active/1,
    draft_product_not_in_list/1,
    % P2-S3: eligibility and fees
    set_and_get_eligibility/1,
    check_eligibility_passes/1,
    check_eligibility_fails_credit_score/1,
    set_and_get_fees/1
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
        create_loan_accepts_active_in_range,
        % P2-S3: versioning
        create_product_version_is_one,
        update_product_increments_version,
        % P2-S3: draft / lifecycle
        create_draft_product,
        launch_product_from_draft,
        launch_product_requires_draft,
        sunset_product_from_active,
        sunset_product_requires_active,
        draft_product_not_in_list,
        % P2-S3: eligibility and fees
        set_and_get_eligibility,
        check_eligibility_passes,
        check_eligibility_fails_credit_score,
        set_and_get_fees
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

%% =============================================================================
%% P2-S3: Versioning tests
%% =============================================================================

create_product_version_is_one(_Config) ->
    {ok, ProductId} = create_standard_product(),
    {ok, Product} = cb_loan_products:get_product(ProductId),
    ?assertEqual(1, Product#loan_product.version),
    ok.

update_product_increments_version(_Config) ->
    {ok, ProductId} = create_standard_product(),
    {ok, Updated} = cb_loan_products:update_product(ProductId, #{name => <<"Updated Loan">>}),
    ?assertEqual(2, Updated#loan_product.version),
    ok.

%% =============================================================================
%% P2-S3: Draft / lifecycle tests
%% =============================================================================

create_draft_product(_Config) ->
    {ok, ProductId} = cb_loan_products:create_draft_product(
        <<"Draft Loan">>, <<"A draft">>, 'USD', 500, 3000, 3, 12, 800, flat),
    {ok, Product} = cb_loan_products:get_product(ProductId),
    ?assertEqual(draft, Product#loan_product.status),
    ok.

launch_product_from_draft(_Config) ->
    {ok, ProductId} = cb_loan_products:create_draft_product(
        <<"Draft Loan">>, <<"A draft">>, 'USD', 500, 3000, 3, 12, 800, flat),
    {ok, Launched} = cb_loan_products:launch_product(ProductId),
    ?assertEqual(active, Launched#loan_product.status),
    ok.

launch_product_requires_draft(_Config) ->
    {ok, ProductId} = create_standard_product(),
    {error, Reason} = cb_loan_products:launch_product(ProductId),
    ?assertEqual(product_not_in_draft, Reason),
    ok.

sunset_product_from_active(_Config) ->
    {ok, ProductId} = create_standard_product(),
    {ok, Sunset} = cb_loan_products:sunset_product(ProductId),
    ?assertEqual(sunset, Sunset#loan_product.status),
    ok.

sunset_product_requires_active(_Config) ->
    {ok, ProductId} = cb_loan_products:create_draft_product(
        <<"Draft Loan">>, <<"A draft">>, 'USD', 500, 3000, 3, 12, 800, flat),
    {error, Reason} = cb_loan_products:sunset_product(ProductId),
    ?assertEqual(product_not_active, Reason),
    ok.

draft_product_not_in_list(_Config) ->
    {ok, _DraftId} = cb_loan_products:create_draft_product(
        <<"Draft Loan">>, <<"A draft">>, 'USD', 500, 3000, 3, 12, 800, flat),
    {ok, _ActiveId} = create_standard_product(),
    Products = cb_loan_products:list_products(),
    Statuses = [P#loan_product.status || P <- Products],
    ?assertNot(lists:member(draft, Statuses)),
    ok.

%% =============================================================================
%% P2-S3: Eligibility and fees tests
%% =============================================================================

set_and_get_eligibility(_Config) ->
    {ok, ProductId} = create_standard_product(),
    Eligibility = #{min_credit_score => 650, max_dti_bps => 4300, min_annual_income => 50000},
    {ok, Updated} = cb_loan_products:set_eligibility(ProductId, Eligibility),
    ?assertEqual(650, maps:get(min_credit_score, Updated#loan_product.eligibility)),
    ?assertEqual(4300, maps:get(max_dti_bps, Updated#loan_product.eligibility)),
    ?assertEqual(50000, maps:get(min_annual_income, Updated#loan_product.eligibility)),
    ok.

check_eligibility_passes(_Config) ->
    {ok, ProductId} = create_standard_product(),
    Eligibility = #{min_credit_score => 650, max_dti_bps => 4300, min_annual_income => 50000},
    {ok, _} = cb_loan_products:set_eligibility(ProductId, Eligibility),
    Applicant = #{credit_score => 720, dti_bps => 3500, annual_income => 60000},
    ?assertEqual(ok, cb_loan_products:check_eligibility(ProductId, Applicant)),
    ok.

check_eligibility_fails_credit_score(_Config) ->
    {ok, ProductId} = create_standard_product(),
    Eligibility = #{min_credit_score => 700, max_dti_bps => 4300, min_annual_income => 50000},
    {ok, _} = cb_loan_products:set_eligibility(ProductId, Eligibility),
    Applicant = #{credit_score => 650, dti_bps => 3500, annual_income => 60000},
    {error, Reason} = cb_loan_products:check_eligibility(ProductId, Applicant),
    ?assertEqual(insufficient_credit_score, Reason),
    ok.

set_and_get_fees(_Config) ->
    {ok, ProductId} = create_standard_product(),
    Fees = #{origination_fee_bps => 150, late_fee => 2500, prepayment_fee_bps => 50},
    {ok, Updated} = cb_loan_products:set_fees(ProductId, Fees),
    ?assertEqual(150, maps:get(origination_fee_bps, Updated#loan_product.fees)),
    ?assertEqual(2500, maps:get(late_fee, Updated#loan_product.fees)),
    ?assertEqual(50, maps:get(prepayment_fee_bps, Updated#loan_product.fees)),
    ok.

