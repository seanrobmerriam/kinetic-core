# IronLedger Error Catalogue

All error atoms returned by IronLedger functions are defined here. No error atom may be
used in code unless it appears in this catalogue. To add a new error, add it here first.

Error responses over HTTP always use the shape:
```json
{ "error": "error_atom", "message": "Human-readable description" }
```

---

## 1. Account Errors

| Atom | HTTP Status | Description |
|------|-------------|-------------|
| `account_not_found` | 404 | No account exists with the given ID |
| `account_frozen` | 409 | Operation rejected; account is in `frozen` status |
| `account_closed` | 409 | Operation rejected; account is in `closed` status and cannot be modified |
| `account_has_balance` | 409 | Account closure rejected; balance must be zero before closing |
| `account_already_frozen` | 409 | Freeze rejected; account is already frozen |
| `account_not_frozen` | 409 | Unfreeze rejected; account is not currently frozen |
| `account_currency_immutable` | 422 | Attempt to change currency on an existing account |

---

## 2. Party Errors

| Atom | HTTP Status | Description |
|------|-------------|-------------|
| `party_not_found` | 404 | No party exists with the given ID |
| `party_suspended` | 409 | Operation rejected; party is suspended |
| `party_closed` | 409 | Operation rejected; party is closed |
| `party_has_active_accounts` | 409 | Party closure rejected; party still has non-closed accounts |
| `party_already_suspended` | 409 | Suspend rejected; party is already suspended |
| `email_already_exists` | 409 | Party creation rejected; email is already registered |

---

## 3. Transaction / Payment Errors

| Atom | HTTP Status | Description |
|------|-------------|-------------|
| `insufficient_funds` | 402 | Debit account balance is less than the requested amount |
| `currency_mismatch` | 409 | Source and destination accounts have different currencies |
| `unsupported_currency` | 422 | Currency code is not in the supported set |
| `idempotency_conflict` | 409 | Idempotency key is already used by a different operation type |
| `transaction_not_found` | 404 | No transaction exists with the given ID |
| `transaction_not_posted` | 409 | Reversal rejected; only `posted` transactions can be reversed |
| `transaction_already_reversed` | 409 | Reversal rejected; transaction is already reversed |
| `zero_amount` | 422 | Transaction amount must be greater than zero |
| `amount_overflow` | 422 | Amount exceeds maximum allowed value (`9_999_999_999_99`) |
| `same_account_transfer` | 422 | Source and destination account IDs are identical |

---

## 4. Ledger Errors

| Atom | HTTP Status | Description |
|------|-------------|-------------|
| `ledger_entry_not_found` | 404 | No ledger entry exists with the given ID |
| `ledger_imbalance` | 500 | Internal: debit and credit totals for a transaction do not match (should never surface; indicates a bug) |

---

## 5. Validation Errors

| Atom | HTTP Status | Description |
|------|-------------|-------------|
| `missing_required_field` | 422 | A required request field is absent or null |
| `invalid_uuid` | 422 | A field expected to be a UUID has an invalid format |
| `invalid_amount` | 422 | Amount is not a positive integer |
| `invalid_currency` | 422 | Currency is not a recognised ISO 4217 code |
| `invalid_page` | 422 | Page number is less than 1 |
| `invalid_page_size` | 422 | Page size is less than 1 or greater than 100 |
| `invalid_json` | 400 | Request body is not valid JSON |

---

## 6. System Errors

| Atom | HTTP Status | Description |
|------|-------------|-------------|
| `internal_error` | 500 | Unexpected internal error; details logged server-side |
| `database_error` | 500 | Mnesia transaction failed unexpectedly |
| `not_implemented` | 501 | Endpoint exists in spec but is not yet implemented |

---

## 7. Erlang Usage

Errors are returned as `{error, Atom}` tuples. Example:

```erlang
case cb_accounts:get_account(AccountId) of
    {ok, Account}           -> Account;
    {error, account_not_found} -> handle_not_found()
end.
```

In `cb_integration`, HTTP handlers translate error atoms to HTTP responses using a
single mapping function:

```erlang
error_to_http(account_not_found)      -> {404, <<"account_not_found">>,     <<"Account not found">>};
error_to_http(insufficient_funds)     -> {402, <<"insufficient_funds">>,     <<"Insufficient funds">>};
error_to_http(currency_mismatch)      -> {409, <<"currency_mismatch">>,      <<"Currency mismatch between accounts">>};
%% ... one clause per catalogue entry
error_to_http(_Unknown)               -> {500, <<"internal_error">>,         <<"An unexpected error occurred">>}.
```

This function is the only place where error atoms are mapped to HTTP status codes.
No handler module should hardcode HTTP status integers directly.