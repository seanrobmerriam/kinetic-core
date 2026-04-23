%% @doc HTTP Error Response Mapping
%%
%% This module converts internal error atoms from the business logic layer
%% into HTTP responses suitable for API clients.
%%
%% <h2>Error Response Format</h2>
%%
%% All error responses follow a consistent JSON format:
%% <pre>
%% {
%%   "error": "error_atom",
%%   "message": "Human readable message"
%% }
%% </pre>
%%
%% This allows API clients to:
%% <ul>
%%   <li>Programmatically identify the error type (error atom)</li>
%%   <li>Display a user-friendly message to end users</li>
%%   <li>Log the error atom for debugging</li>
%% </ul>
%%
%% <h2>HTTP Status Codes</h2>
%%
%% <ul>
%%   <li><b>400 Bad Request</b>: Client sent invalid data (e.g., invalid JSON)</li>
%%   <li><b>401 Unauthorized</b>: Authentication required (future use)</li>
%%   <li><b>402 Payment Required</b>: Insufficient funds</li>
%%   <li><b>404 Not Found</b>: Resource doesn't exist</li>
%%   <li><b>409 Conflict</b>: Resource state prevents operation (e.g., account frozen)</li>
%%   <li><b>422 Unprocessable Entity</b>: Business rule violation</li>
%%   <li><b>500 Internal Server Error</b>: Unexpected system error</li>
%% </ul>
%%
%% <h2>Error Categories</h2>
%%
%% <ol>
%%   <li><b>Account errors</b>: Account not found, frozen, closed, balance issues</li>
%%   <li><b>Party errors</b>: Party not found, suspended, closed, duplicate email</li>
%%   <li><b>Transaction errors</b>: Insufficient funds, currency mismatch, idempotency</li>
%%   <li><b>Ledger errors</b>: Entry not found, imbalance</li>
%%   <li><b>Validation errors</b>: Missing fields, invalid format, pagination errors</li>
%%   <li><b>System errors</b>: Database errors, internal errors, not implemented</li>
%% </ol>
%%
%% @see cb_http_errors:to_response/1
-module(cb_http_errors).

-export([to_response/1, to_response_with_metrics/1]).

%% @doc Convert an error atom to an HTTP response tuple.
%%
%% Maps an internal error atom from the business logic to a tuple containing:
%% <ul>
%%   <li>HTTP status code (integer)</li>
%%   <li>Error atom (binary) - for programmatic error identification</li>
%%   <li>Human-readable message (binary) - for display to users</li>
%% </ul>
%%
%% @param ErrorAtom The internal error atom from business logic
%% @returns `{Status, ErrorAtom, Message}' tuple ready for HTTP response
-spec to_response(term()) ->
    {400 | 401 | 402 | 403 | 404 | 405 | 409 | 422 | 429 | 500 | 501,
     <<_:64, _:_*8>>,
     <<_:64, _:_*8>>}.

%% Account errors
to_response(account_not_found) ->
    {404, <<"account_not_found">>, <<"Account not found">>};
to_response(account_frozen) ->
    {409, <<"account_frozen">>, <<"Account is frozen">>};
to_response(account_closed) ->
    {409, <<"account_closed">>, <<"Account is closed">>};
to_response(account_has_balance) ->
    {409, <<"account_has_balance">>, <<"Account has non-zero balance">>};
to_response(account_already_frozen) ->
    {409, <<"account_already_frozen">>, <<"Account is already frozen">>};
to_response(account_not_frozen) ->
    {409, <<"account_not_frozen">>, <<"Account is not frozen">>};

%% Hold errors
to_response(hold_not_found) ->
    {404, <<"hold_not_found">>, <<"Hold not found">>};
to_response(hold_already_released) ->
    {409, <<"hold_already_released">>, <<"Hold has already been released">>};
to_response(hold_already_expired) ->
    {409, <<"hold_already_expired">>, <<"Hold has already expired">>};
to_response(insufficient_available_balance) ->
    {402, <<"insufficient_available_balance">>, <<"Insufficient available balance (funds are on hold)">>};

to_response(account_currency_immutable) ->
    {422, <<"account_currency_immutable">>, <<"Account currency cannot be changed">>};

%% Party errors
to_response(party_not_found) ->
    {404, <<"party_not_found">>, <<"Party not found">>};
to_response(party_suspended) ->
    {409, <<"party_suspended">>, <<"Party is suspended">>};
to_response(party_closed) ->
    {409, <<"party_closed">>, <<"Party is closed">>};
to_response(party_has_active_accounts) ->
    {409, <<"party_has_active_accounts">>, <<"Party has active accounts">>};
to_response(party_already_suspended) ->
    {409, <<"party_already_suspended">>, <<"Party is already suspended">>};
to_response(party_not_suspended) ->
    {409, <<"party_not_suspended">>, <<"Party is not suspended">>};
to_response(email_already_exists) ->
    {409, <<"email_already_exists">>, <<"Email already exists">>};

%% Transaction / Payment errors
to_response(insufficient_funds) ->
    {402, <<"insufficient_funds">>, <<"Insufficient funds">>};
to_response(currency_mismatch) ->
    {409, <<"currency_mismatch">>, <<"Currency mismatch between accounts">>};
to_response(unsupported_currency) ->
    {422, <<"unsupported_currency">>, <<"Unsupported currency">>};
to_response(idempotency_conflict) ->
    {409, <<"idempotency_conflict">>, <<"Idempotency key conflict">>};
to_response(transaction_not_found) ->
    {404, <<"transaction_not_found">>, <<"Transaction not found">>};
to_response(transaction_not_posted) ->
    {409, <<"transaction_not_posted">>, <<"Transaction is not posted">>};
to_response(transaction_already_reversed) ->
    {409, <<"transaction_already_reversed">>, <<"Transaction is already reversed">>};
to_response(zero_amount) ->
    {422, <<"zero_amount">>, <<"Amount must be greater than zero">>};
to_response(amount_overflow) ->
    {422, <<"amount_overflow">>, <<"Amount exceeds maximum allowed value">>};
to_response(same_account_transfer) ->
    {422, <<"same_account_transfer">>, <<"Source and destination accounts are the same">>};
to_response(withdrawal_limit_exceeded) ->
    {422, <<"withdrawal_limit_exceeded">>, <<"Amount exceeds the per-transaction withdrawal limit">>};
to_response(per_txn_limit_exceeded) ->
    {422, <<"per_txn_limit_exceeded">>, <<"Amount exceeds the per-transaction channel limit">>};
to_response(daily_limit_exceeded) ->
    {422, <<"daily_limit_exceeded">>, <<"Daily transaction volume limit exceeded for this channel">>};
to_response(transaction_tag_not_found) ->
    {404, <<"transaction_tag_not_found">>, <<"Transaction tags not found">>};
to_response(forbidden) ->
    {403, <<"forbidden">>, <<"Insufficient permissions for this operation">>};
to_response(rate_limit_exceeded) ->
    {429, <<"rate_limit_exceeded">>, <<"Too many requests. Please slow down.">>};

%% Ledger errors
to_response(ledger_entry_not_found) ->
    {404, <<"ledger_entry_not_found">>, <<"Ledger entry not found">>};
to_response(ledger_imbalance) ->
    {500, <<"ledger_imbalance">>, <<"Ledger imbalance detected">>};

%% Product / Loan / Interest errors
to_response(product_not_found) ->
    {404, <<"product_not_found">>, <<"Product not found">>};
to_response(product_already_active) ->
    {409, <<"product_already_active">>, <<"Product is already active">>};
to_response(product_already_inactive) ->
    {409, <<"product_already_inactive">>, <<"Product is already inactive">>};
to_response(product_inactive) ->
    {409, <<"product_inactive">>, <<"Product is inactive">>};
to_response(amount_out_of_product_range) ->
    {422, <<"amount_out_of_product_range">>, <<"Amount is outside product limits">>};
to_response(term_out_of_product_range) ->
    {422, <<"term_out_of_product_range">>, <<"Term is outside product limits">>};
to_response(invalid_amount_range) ->
    {422, <<"invalid_amount_range">>, <<"Invalid amount range">>};
to_response(invalid_term_range) ->
    {422, <<"invalid_term_range">>, <<"Invalid term range">>};
to_response(not_found) ->
    {404, <<"not_found">>, <<"Resource not found">>};
to_response(accrual_not_found) ->
    {404, <<"accrual_not_found">>, <<"Interest accrual not found">>};
to_response(invalid_interest_type) ->
    {422, <<"invalid_interest_type">>, <<"Invalid interest type">>};
to_response(invalid_compounding_period) ->
    {422, <<"invalid_compounding_period">>, <<"Invalid compounding period">>};
to_response(invalid_interest_rate) ->
    {422, <<"invalid_interest_rate">>, <<"Invalid interest rate">>};
to_response(interest_rate_too_high) ->
    {422, <<"interest_rate_too_high">>, <<"Interest rate exceeds the allowed maximum">>};
to_response(invalid_term) ->
    {422, <<"invalid_term">>, <<"Invalid loan term">>};
to_response(term_too_long) ->
    {422, <<"term_too_long">>, <<"Loan term exceeds the allowed maximum">>};
to_response(invalid_product_id) ->
    {422, <<"invalid_product_id">>, <<"Invalid product identifier">>};
to_response(invalid_status) ->
    {409, <<"invalid_status">>, <<"Operation is not allowed in the current status">>};
to_response(invalid_parameters) ->
    {422, <<"invalid_parameters">>, <<"Invalid parameters">>};

%% Validation errors
to_response(unauthorized) ->
    {401, <<"unauthorized">>, <<"Authentication required">>};
to_response(dev_tools_disabled) ->
    {403, <<"dev_tools_disabled">>, <<"Development tools are disabled">>};
to_response(invalid_credentials) ->
    {401, <<"invalid_credentials">>, <<"Invalid credentials">>};
to_response(missing_required_field) ->
    {422, <<"missing_required_field">>, <<"Missing required field">>};
to_response(invalid_uuid) ->
    {422, <<"invalid_uuid">>, <<"Invalid UUID format">>};
to_response(invalid_amount) ->
    {422, <<"invalid_amount">>, <<"Invalid amount">>};
to_response(invalid_currency) ->
    {422, <<"invalid_currency">>, <<"Invalid currency">>};
to_response(invalid_page) ->
    {422, <<"invalid_page">>, <<"Invalid page number">>};
to_response(invalid_page_size) ->
    {422, <<"invalid_page_size">>, <<"Invalid page size">>};
to_response(invalid_json) ->
    {400, <<"invalid_json">>, <<"Invalid JSON">>};
to_response(invalid_pagination) ->
    {422, <<"invalid_pagination">>, <<"Invalid pagination parameters">>};

to_response(method_not_allowed) ->
    {405, <<"method_not_allowed">>, <<"Method not allowed">>};

%% OAuth errors
to_response(oauth_invalid_client) ->
    {401, <<"invalid_client">>, <<"Invalid client credentials">>};
to_response(oauth_invalid_grant) ->
    {400, <<"unsupported_grant_type">>, <<"Unsupported grant type">>};

%% System errors
to_response(database_error) ->
    {500, <<"database_error">>, <<"Database error">>};
to_response(internal_error) ->
    {500, <<"internal_error">>, <<"An unexpected error occurred">>};
to_response(not_implemented) ->
    {501, <<"not_implemented">>, <<"Not implemented">>};

%% Catch-all
to_response(_Unknown) ->
    {500, <<"internal_error">>, <<"An unexpected error occurred">>}.

%% @doc Convert an error reason to a Cowboy reply tuple.
%%
%% Increments the 5xx counter for server error responses so that
%% `cb_metrics_handler' can surface the count.
-spec to_response_with_metrics(atom()) ->
    {non_neg_integer(), map(), binary()}.
to_response_with_metrics(Reason) ->
    {Code, ErrorAtom, Message} = to_response(Reason),
    Body = jsone:encode(#{error => ErrorAtom, message => Message}),
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    case Code >= 500 of
        true  -> cb_metrics_counter:increment(http_5xx_total);
        false -> ok
    end,
    {Code, Headers, Body}.
