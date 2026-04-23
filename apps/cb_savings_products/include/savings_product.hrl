%%%
%%% @doc Savings product record definitions and type specifications.
%%%
%%% This header file defines the core data structures for savings products
%%% in the IronLedger core banking system.
%%%
%%% ## Savings Products in Banking
%%%
%%% A savings product is an interest-bearing deposit account that allows
%%% customers to deposit funds and earn interest over time. Savings products
%%% are fundamental to retail banking and form the basis for deposit-based
%%% income (interest spread).
%%%
%%% ### Key Concepts
%%%
%%% - **Interest Rate**: The annual percentage rate (APR) applied to the account
%%%   balance. Expressed as basis points (e.g., 500 = 5.00% APR).
%%%
%%% - **Interest Type**:
%%%   * `simple` - Interest calculated only on the principal balance
%%%   * `compound` - Interest calculated on principal + accumulated interest
%%%
%%% - **Compounding Period**: How frequently interest is calculated and
%%%   added to the account:
%%%   * `daily` - Interest compounds every day (365 periods/year)
%%%   * `monthly` - Interest compounds monthly (12 periods/year)
%%%   * `quarterly` - Interest compounds quarterly (4 periods/year)
%%%   * `annually` - Interest compounds once per year
%%%
%%% - **Minimum Balance**: The minimum account balance required to earn
%%%   interest. Accounts below this threshold may earn no interest or
%%%   reduced interest.
%%%
%%% ### Example Savings Products
%%%
%%% - Basic Savings: 0.01% APR, simple interest, monthly compounding
%%% - High-Yield Savings: 4.50% APR, compound interest, daily compounding
%%% - Youth Savings: 2.00% APR, compound interest, monthly compounding
%%%
%%% @see cb_savings_products

-ifndef(SAVINGS_PRODUCT_HRL).
-define(SAVINGS_PRODUCT_HRL, 1).

%%%
%%% @doc Savings product record representing an interest-bearing deposit product.
%%%
%%% This record defines the complete configuration for a savings product
%%% including pricing, terms, and operational status.
%%%
%%% ### Fields
%%%
%%% - `product_id`: Unique UUID identifier for this product definition.
%%%   Used to reference the product when creating savings accounts.
%%%
%%% - `name`: Human-readable name for the product (e.g., "High-Yield Savings").
%%%
%%% - `description`: Detailed description of the product terms and benefits.
%%%
%%% - `currency`: ISO 4217 currency code (atom) - 'USD', 'EUR', 'GBP', etc.
%%%   All monetary values for this product are denominated in this currency.
%%%
%%% - `interest_rate`: Annual interest rate in basis points.
%%%   Example: 475 = 4.75% APR.
%%%
%%% - `interest_type`: Either `simple` or `compound`.
%%%   Simple: Interest = Principal × Rate × Time
%%%   Compound: Interest = Principal × (1 + Rate)^Time - Principal
%%%
%%% - `compounding_period`: Frequency of interest calculation.
%%%   Valid values: `daily`, `monthly`, `quarterly`, `annually`
%%%
%%% - `minimum_balance`: Minimum balance required to earn interest.
%%%   Expressed in minor units (cents/pence). Example: 10000 = $100.00.
%%%
%%% - `status`: Current operational status of the product.
%%%   `active` - Product is available for new accounts
%%%   `inactive` - Product is deprecated and not available for new accounts
%%%
%%% - `created_at`: Unix timestamp (milliseconds) when the product was created.
%%%
%%% - `updated_at`: Unix timestamp (milliseconds) of last modification.
%%%
-record(savings_product, {
    product_id          :: binary(),
    name                :: binary(),
    description         :: binary(),
    currency            :: atom(),
    interest_rate       :: non_neg_integer(),
    interest_type       :: atom(),
    compounding_period  :: atom(),
    minimum_balance     :: integer(),
    status              :: atom(),
    version             :: pos_integer(),
    created_at          :: integer(),
    updated_at          :: integer()
}).

%%%
%%% @doc Type alias for savings product identifier.
%%%
-type product_id() :: binary().
%%% Unique UUID identifier for a savings product.

%%%
%%% @doc Type alias for valid currency codes.
%%%
-type currency_code() :: 'USD' | 'EUR' | 'GBP' | 'JPY'.
%%% ISO 4217 three-letter uppercase currency codes supported by the system.

%%%
%%% @doc Type alias for interest calculation methods.
%%%
-type interest_type() :: simple | compound.
%%% - `simple`: Interest calculated on principal only
%%% - `compound`: Interest calculated on principal plus accumulated interest

%%%
%%% @doc Type alias for compounding frequency.
%%%
-type compounding_period() :: daily | monthly | quarterly | annually.
%%% How frequently interest is calculated and capitalized:
%%% - `daily`: Every day (365 times per year)
%%% - `monthly`: Every month (12 times per year)
%%% - `quarterly`: Every quarter (4 times per year)
%%% - `annually`: Once per year

%%%
%%% @doc Type alias for product operational status.
%%%
-type product_status() :: draft | active | inactive | sunset.
%%% - `active`: Product is available for new savings accounts
%%% - `inactive`: Product is deprecated, no new accounts can be opened

%%%
%%% @doc Type alias representing a complete savings product record.
%%%
-type savings_product() :: #savings_product{}.

%%%
%%% @doc Valid currency codes for savings products.
%%%
-define(VALID_CURRENCIES, ['USD', 'EUR', 'GBP', 'JPY']).

%%%
%%% @doc Valid interest type options.
%%%
-define(VALID_INTEREST_TYPES, [simple, compound]).

%%%
%%% @doc Valid compounding period options.
%%%
-define(VALID_COMPOUNDING_PERIODS, [daily, monthly, quarterly, annually]).

-endif. % SAVINGS_PRODUCT_HRL
