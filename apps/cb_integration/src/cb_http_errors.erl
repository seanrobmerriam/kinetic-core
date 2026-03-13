-module(cb_http_errors).

-export([to_response/1]).

%% @doc Convert an error atom to an HTTP response tuple {Status, ErrorAtom, Message}.
-spec to_response(atom()) -> {non_neg_integer(), binary(), binary()}.

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

%% Ledger errors
to_response(ledger_entry_not_found) ->
    {404, <<"ledger_entry_not_found">>, <<"Ledger entry not found">>};
to_response(ledger_imbalance) ->
    {500, <<"ledger_imbalance">>, <<"Ledger imbalance detected">>};

%% Validation errors
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
