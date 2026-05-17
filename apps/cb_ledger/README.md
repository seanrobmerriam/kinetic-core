# cb_ledger

Double-entry bookkeeping core module. Posts debit/credit entry pairs and maintains the accounting equation.

## Module Overview

The cb_ledger module is the heart of Kinetic Core's accounting system. It implements double-entry bookkeeping where every financial transaction creates paired debit and credit entries. The sum of all debits always equals the sum of all credits, maintaining the fundamental accounting equation: Assets = Liabilities + Equity.

## Types

### account_id()
UUID binary representing a unique account identifier.

### amount()
Non-negative integer representing monetary amount in minor units (cents, pence, etc.). 100 = $1.00 USD.

### entry_id()
UUID binary for a ledger entry.

### entry_type()
Atom representing entry type: `debit` | `credit`.

### currency()
ISO 4217 currency code atom: `USD` | `EUR` | `GBP` | `JPY`.

### balance()
Current account balance as `amount()`.

### entry()
Record representing a ledger entry with id, account_id, amount, type, description, reference, and timestamp.

## Functions

### post_entry(AccountId, EntryType, Amount, Description, Reference)

Posts a single entry (debit or credit) to an account. This is the fundamental building block for all ledger operations.

**Parameters:**
- `AccountId` - Target account UUID
- `EntryType` - `debit` or `credit`
- `Amount` - Positive integer in minor units
- `Description` - Human-readable description
- `Reference` - External reference

**Returns:** `{ok, entry_id()} | {error, Reason}`

### post_transaction(Entries, Description)

Posts a multi-entry transaction. Ensures the sum of debits equals the sum of credits (balanced transaction). If any entry fails, all entries are rolled back.

**Parameters:**
- `Entries` - List of entry records
- `Description` - Transaction description

**Returns:** `{ok, [entry_id()]} | {error, not_balanced} | {error, Reason}`

### get_balance(AccountId)

Calculates the current balance for an account by summing all debit and credit entries. Balance = total_credits - total_debits.

**Returns:** `{ok, balance()} | {error, account_not_found}`

### get_entries(AccountId, FromTimestamp, ToTimestamp)

Retrieves all entries for an account within a time range. Useful for account statements and audit trails.

**Returns:** `{ok, [entry()]}`

### create_account(AccountId, Currency)

Initializes a new account in the ledger. Creates the account record with zero balance.

**Returns:** `{ok, account_id()} | {error, account_already_exists} | {error, unsupported_currency}`

## Error Reasons

- `account_not_found` - Account does not exist
- `account_already_exists` - Account ID already in use
- `unsupported_currency` - Currency not supported
- `not_balanced` - Debits don't equal credits
- `invalid_amount` - Amount is negative or zero
- `amount_overflow` - Amount exceeds maximum allowed

## Example Usage

```erlang
% Deposit $100 to an account
DepositAccount = <<"550e8400-e29b-41d4-a716-446655440000">>,
CashAccount = <<"550e8400-e29b-41d4-a716-446655440001">>,

Entries = [
    #{account_id => DepositAccount, 
      amount => 10000, 
      type => credit,
      description => "Cash deposit",
      reference => <<"DEP-001">>},
    #{account_id => CashAccount, 
      amount => 10000, 
      type => debit,
      description => "Cash in vault",
      reference => <<"DEP-001">>}
],

case cb_ledger:post_transaction(Entries, "Customer deposit") of
    {ok, _EntryIds} -> 
        {ok, Balance} = cb_ledger:get_balance(DepositAccount),
        io:format("New balance: ~p~n", [Balance]);
    {error, Reason} ->
        io:format("Error: ~p~n", [Reason])
end.
```

## See Also

- [Architecture](../docs/architecture.md)
- [cb_accounts](../apps/cb_accounts/README.md)
- [cb_payments](../apps/cb_payments/README.md)
