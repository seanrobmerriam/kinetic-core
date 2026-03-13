# IronLedger Testing Strategy

---

## 1. Philosophy

Tests verify the contracts defined in `-spec` annotations and this document.
A spec is written first; a test is written to prove the spec is honoured.
No test may be written for a function that lacks a correct `-spec`.

---

## 2. Test Layers

### 2.1 Dialyzer (Static Analysis)
- Runs on every module.
- Catches type violations, unreachable code, and broken specs at compile time.
- Must report **zero warnings** before any CT or PropEr run.
- Command: `rebar3 dialyzer`

### 2.2 Common Test (Deterministic Unit & Integration)
- Location: `apps/<app>/test/<module>_SUITE.erl`
- Covers specific, handpicked scenarios with known inputs and expected outputs.
- Required for every public function: at minimum one happy-path case and one error case.
- Command: `rebar3 ct`

### 2.3 PropEr (Property-Based)
- Location: `apps/<app>/test/<module>_prop.erl`
- Required for any function that performs arithmetic on monetary amounts.
- Generates random inputs to find edge cases the author didn't think of.
- Minimum: 100 test cases per property.
- Command: `rebar3 proper --numtests 100`

---

## 3. Common Test Rules

### 3.1 Setup and Teardown

Every suite must implement:
```erlang
init_per_suite(Config) ->
    mnesia:start(),
    cb_schema:create_tables(),
    Config.

end_per_suite(_Config) ->
    mnesia:stop(),
    mnesia:delete_schema([node()]).

init_per_testcase(_TestCase, Config) ->
    %% Clear all tables before each test
    lists:foreach(fun(T) -> mnesia:clear_table(T) end,
                  [party, account, transaction, ledger_entry]),
    Config.

end_per_testcase(_TestCase, _Config) -> ok.
```

### 3.2 Assertion Style
- Use `?assertEqual(Expected, Actual)` — never bare `=` pattern matches.
- Use `?assertMatch(Pattern, Expr)` for partial structure checks.
- Use `?assertError(ErrorTerm, Expr)` for expected exceptions.
- Monetary assertions must compare integers: `?assertEqual(1000, Balance)`.

### 3.3 Test Case Categories

Each suite organises test cases into these groups:

| Category | Tag | Description |
|----------|-----|-------------|
| Happy path | `happy` | Valid inputs, expected success |
| Error path | `error` | Invalid inputs or precondition violations |
| Boundary | `boundary` | Edge values: zero, max amount, empty strings |
| Idempotency | `idempotency` | Repeat calls with same idempotency key |
| Atomicity | `atomicity` | Partial-failure scenarios; verify no partial writes |
| Concurrency | `concurrency` | Two conflicting operations on the same account |

---

## 4. Required Test Cases by Feature

### 4.1 Account Management (cb_accounts_SUITE)

| Test | Category | Description |
|------|----------|-------------|
| `create_account_ok` | happy | Valid party, valid currency → account created, balance = 0 |
| `create_account_party_not_found` | error | Unknown `party_id` → `{error, party_not_found}` |
| `create_account_unsupported_currency` | error | `"XYZ"` currency → `{error, unsupported_currency}` |
| `close_account_zero_balance` | happy | Balance = 0, status → `closed` |
| `close_account_nonzero_balance` | error | Balance > 0 → `{error, account_has_balance}` |
| `freeze_unfreeze_account` | happy | Freeze → `frozen`; unfreeze → `active` |
| `debit_frozen_account` | error | Attempt transfer from frozen account → `{error, account_frozen}` |
| `credit_frozen_account` | error | Attempt deposit to frozen account → `{error, account_frozen}` |
| `get_account_not_found` | error | Unknown ID → `{error, account_not_found}` |

### 4.2 Transfers (cb_payments_SUITE)

| Test | Category | Description |
|------|----------|-------------|
| `transfer_ok` | happy | Valid transfer; balances updated; 2 ledger entries created |
| `transfer_insufficient_funds` | error | Amount > source balance → `{error, insufficient_funds}` |
| `transfer_zero_amount` | boundary | Amount = 0 → `{error, zero_amount}` |
| `transfer_max_amount` | boundary | Amount = 9_999_999_999_99; verify no overflow |
| `transfer_currency_mismatch` | error | Accounts in different currencies → `{error, currency_mismatch}` |
| `transfer_same_account` | error | Source = dest → `{error, same_account_transfer}` |
| `transfer_idempotent` | idempotency | Same key twice → same result, balance unchanged after 2nd call |
| `transfer_idempotency_conflict` | idempotency | Same key, different operation type → `{error, idempotency_conflict}` |
| `transfer_atomicity_on_failure` | atomicity | Simulate failure after debit write; source balance unchanged |
| `deposit_ok` | happy | Valid deposit; balance incremented; credit ledger entry created |
| `withdrawal_ok` | happy | Valid withdrawal; balance decremented; debit ledger entry created |
| `withdrawal_insufficient` | error | Amount > balance → `{error, insufficient_funds}` |
| `reverse_transfer_ok` | happy | Reverse a posted transfer; opposite entries created; balances restored |
| `reverse_non_posted_txn` | error | Reverse a `failed` txn → `{error, transaction_not_posted}` |

### 4.3 Ledger (cb_ledger_SUITE)

| Test | Category | Description |
|------|----------|-------------|
| `double_entry_balance` | happy | After transfer, sum(debits) = sum(credits) for txn |
| `entries_immutable` | atomicity | Write, then attempt overwrite → original record unchanged |
| `entries_by_account` | happy | Ledger list for account includes correct entries |
| `entries_by_transaction` | happy | Exactly 2 entries returned for a standard transfer |

### 4.4 Party Management (cb_party_SUITE)

| Test | Category | Description |
|------|----------|-------------|
| `create_party_ok` | happy | Valid fields → party created |
| `create_party_duplicate_email` | error | Same email twice → `{error, email_already_exists}` |
| `suspend_party_ok` | happy | Active → suspended |
| `close_party_with_accounts` | error | Party has active account → `{error, party_has_active_accounts}` |
| `close_party_ok` | happy | No active accounts → closed |

---

## 5. Required PropEr Properties

### 5.1 cb_payments_prop

```erlang
%% P1 — Double-entry: debits always equal credits for any valid transfer
prop_double_entry() ->
    ?FORALL({Amount, Currency}, {valid_amount(), valid_currency()},
        begin
            {SourceId, DestId} = setup_accounts(Currency),
            seed_balance(SourceId, Amount),
            cb_payments:transfer(#{...}),
            sum_entries(debit, TxnId) =:= sum_entries(credit, TxnId)
        end).

%% P2 — Amount preservation: total money in system unchanged after transfer
prop_amount_preservation() ->
    ?FORALL({Amount, Currency}, {valid_amount(), valid_currency()},
        begin
            {SourceId, DestId} = setup_accounts(Currency),
            seed_balance(SourceId, Amount * 2),
            TotalBefore = get_balance(SourceId) + get_balance(DestId),
            cb_payments:transfer(#{amount => Amount, ...}),
            TotalAfter = get_balance(SourceId) + get_balance(DestId),
            TotalBefore =:= TotalAfter
        end).

%% P3 — No negative balances
prop_no_negative_balance() ->
    ?FORALL({Amount, InitialBalance, Currency}, {valid_amount(), valid_amount(), valid_currency()},
        begin
            {AccountId, _} = setup_accounts(Currency),
            seed_balance(AccountId, InitialBalance),
            _ = cb_payments:transfer(#{amount => Amount, source_account_id => AccountId, ...}),
            get_balance(AccountId) >= 0
        end).

%% P4 — Integer integrity: no float ever appears in a ledger entry
prop_integer_amounts() ->
    ?FORALL({Amount, Currency}, {valid_amount(), valid_currency()},
        begin
            {SourceId, DestId} = setup_accounts(Currency),
            seed_balance(SourceId, Amount),
            {ok, Txn} = cb_payments:transfer(#{amount => Amount, ...}),
            Entries = cb_ledger:get_entries_for_transaction(Txn#transaction.txn_id),
            lists:all(fun(E) -> is_integer(E#ledger_entry.amount) end, Entries)
        end).
```

### 5.2 Generators

```erlang
valid_amount() ->
    ?SUCHTHAT(A, pos_integer(), A > 0 andalso A =< 9_999_999_999_99).

valid_currency() ->
    oneof(['USD', 'EUR', 'GBP', 'CHF']).  %% JPY excluded from division tests

idempotency_key() ->
    ?LET(N, pos_integer(), list_to_binary("key-" ++ integer_to_list(N))).
```

---

## 6. Running the Full Suite

```bash
# Step 1: Static analysis
rebar3 dialyzer

# Step 2: Unit and integration tests
rebar3 ct

# Step 3: Property-based tests
rebar3 proper --numtests 100

# All in one (must all pass before any feature is considered done)
rebar3 dialyzer && rebar3 ct && rebar3 proper --numtests 100
```

Expected output for a passing build:
```
Dialyzer   : 0 warnings
Common Test: N tests, 0 failures
PropEr     : All properties passed (100 cases each)
```

Any failure blocks further development on that feature until resolved.