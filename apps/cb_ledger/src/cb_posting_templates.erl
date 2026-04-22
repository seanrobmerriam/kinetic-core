%% @doc Posting Templates Module
%%
%% Defines named posting templates for common internal financial operations
%% such as fee charges, interest postings, and operational adjustments.
%%
%% A posting template specifies:
%% - The template name (atom)
%% - Which account type is debited
%% - Which account type is credited
%% - A description pattern for the generated transaction
%%
%% Templates are pure configuration — they do not hold process state and do not
%% have their own Mnesia table. The `apply_template/3` function resolves a template
%% by name and returns the parameters needed for a `cb_payments:adjust_balance/5`
%% call.
%%
%% Usage example:
%% ```
%% {ok, {AccountId, Amount, Currency, Description}} =
%%     cb_posting_templates:apply_template(fee, AccountId, Params),
%% cb_payments:adjust_balance(IdempKey, AccountId, Amount, Currency, Description).
%% ```
%%
%% @see cb_payments

-module(cb_posting_templates).

-export([
    apply_template/3,
    list_templates/0,
    get_template/1
]).

%% Template record (compile-time only, no Mnesia table)
-record(posting_template, {
    name                 :: atom(),
    debit_account_type   :: atom(),
    credit_account_type  :: atom(),
    description_pattern  :: binary()
}).

%% =============================================================================
%% Template Registry
%% =============================================================================

%% @private All defined templates.
-dialyzer({nowarn_function, templates/0}).
-spec templates() -> [#posting_template{}].
templates() ->
    [
        #posting_template{
            name                = fee,
            debit_account_type  = customer,
            credit_account_type = income,
            description_pattern = <<"Fee charge: ">>
        },
        #posting_template{
            name                = interest,
            debit_account_type  = customer,
            credit_account_type = income,
            description_pattern = <<"Interest charge: ">>
        },
        #posting_template{
            name                = interest_credit,
            debit_account_type  = expense,
            credit_account_type = customer,
            description_pattern = <<"Interest credit: ">>
        },
        #posting_template{
            name                = operational_adjustment,
            debit_account_type  = operational,
            credit_account_type = customer,
            description_pattern = <<"Operational adjustment: ">>
        },
        #posting_template{
            name                = reversal_adjustment,
            debit_account_type  = customer,
            credit_account_type = operational,
            description_pattern = <<"Reversal adjustment: ">>
        }
    ].

%% =============================================================================
%% Public API
%% =============================================================================

%% @doc Apply a posting template to produce parameters for `cb_payments:adjust_balance/5`.
%%
%% Given a template name, an account ID, and a map of parameters, returns a
%% tuple ready to pass to `cb_payments:adjust_balance/5`.
%%
%% Required parameters in Params:
%% - `amount` (integer, minor units)
%% - `currency` (atom, e.g. `'USD'`)
%% - `note` (binary, appended to the description pattern)
%%
%% @param TemplateName The template to apply (e.g. `fee`, `interest`, `operational_adjustment`)
%% @param AccountId The customer account to post against
%% @param Params Map of `#{amount => amount(), currency => currency(), note => binary()}`
%% @returns `{ok, {AccountId, Amount, Currency, Description}}` or `{error, atom()}`
%%
-spec apply_template(atom(), binary(), #{amount => integer(), currency => atom(), note => binary()}) ->
    {ok, {binary(), integer(), atom(), binary()}} | {error, atom()}.
apply_template(TemplateName, AccountId, #{amount := Amount, currency := Currency, note := Note}) ->
    case get_template(TemplateName) of
        {ok, Template} ->
            Description = <<(Template#posting_template.description_pattern)/binary, Note/binary>>,
            {ok, {AccountId, Amount, Currency, Description}};
        {error, Reason} ->
            {error, Reason}
    end;
apply_template(_, _, _) ->
    {error, missing_required_field}.

%% @doc List all available posting templates.
%%
%% Returns all registered templates as a list of maps, suitable for JSON encoding.
%%
%% @returns List of template maps
-dialyzer({nowarn_function, list_templates/0}).
-spec list_templates() -> [map()].
list_templates() ->
    [template_to_map(T) || T <- templates()].

%% @doc Retrieve a single template by name.
%%
%% @param Name The template atom name
%% @returns `{ok, #posting_template{}}` or `{error, template_not_found}`
-spec get_template(atom()) -> {ok, #posting_template{}} | {error, atom()}.
get_template(Name) ->
    case lists:keyfind(Name, #posting_template.name, templates()) of
        false    -> {error, template_not_found};
        Template -> {ok, Template}
    end.

%% =============================================================================
%% Internal Helpers
%% =============================================================================

-dialyzer({nowarn_function, template_to_map/1}).
-spec template_to_map(#posting_template{}) -> map().
template_to_map(T) ->
    #{
        name                => T#posting_template.name,
        debit_account_type  => T#posting_template.debit_account_type,
        credit_account_type => T#posting_template.credit_account_type,
        description_pattern => T#posting_template.description_pattern
    }.
