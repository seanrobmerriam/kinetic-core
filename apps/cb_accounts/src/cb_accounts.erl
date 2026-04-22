%%%
%% @doc cb_accounts - Account Lifecycle Management Module
%%
%% This module provides the core account management functionality for IronLedger,
%% a core banking system. It handles the complete lifecycle of bank accounts
%% including creation, retrieval, status management (freeze/unfreeze), and closure.
%%
%% h2. Account Concepts
%%
%% In banking terminology, an <em>account</em> (also called a ledger account or
%% GL account) represents a record that holds monetary value for a customer.
%% Unlike a physical wallet which holds cash, a bank account is a digital record
%% that tracks:
%% <ul>
%%   <li>The owner (party/customer)</li>
%%   <li>The current balance (funds available)</li>
%%   <li>The currency of denomination</li>
%%   <li>The status (active, frozen, or closed)</li>
%% </ul>
%%
%% h3. Account States
%%
%% <ul>
%%   <li><strong>active</strong>: Normal operational state. Deposits, withdrawals,
%%       and transfers are permitted.</li>
%%   <li><strong>frozen</strong>: Temporary restriction state. The account cannot
%%       accept new transactions but existing balance is preserved. Typically
%%       used for regulatory holds, fraud investigation, or customer request.</li>
%%   <li><strong>closed</strong>: Permanent terminal state. No transactions are
%%       permitted. The account balance must be zero before closure.</li>
%% </ul>
%%
%% h3. Currency Handling
%%
%% IronLedger supports multi-currency accounts. Each account is denominated in
%% a single currency (ISO 4217). Supported currencies:
%% <ul>
%%   <li><strong>USD</strong> - US Dollar</li>
%%   <li><strong>EUR</strong> - Euro</li>
%%   <li><strong>GBP</strong> - British Pound</li>
%%   <li><strong>JPY</strong> - Japanese Yen</li>
%%   <li><strong>CHF</strong> - Swiss Franc</li>
%% </ul>
%%
%% h3. Monetary Amounts
%%
%% All monetary amounts are stored as <em>minor units</em> (cents, pence, etc.).
%% This prevents floating-point precision errors in financial calculations.
%% Examples:
%% <ul>
%%   <li>$10.00 USD = 1000 minor units</li>
%%   <li>¥100 JPY = 100 minor units (JPY has no decimal places)</li>
%% </ul>
%%
%% h3. Balance Management
%%
%% The account balance represents the net funds held by the account holder.
%% It is updated through the double-entry ledger system (see {@link cb_ledger}).
%% This module provides read-only access to the balance; modifications are
%% performed via the ledger posting engine.
%%
%% @see cb_ledger
%% @see cb_payments
%% @see cb_party

-module(cb_accounts).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([
    create_account/3,
    get_account/1,
    list_accounts/2,
    list_accounts_for_party/3,
    freeze_account/1,
    unfreeze_account/1,
    close_account/1,
    get_balance/1,
    set_withdrawal_limit/2
]).

%% Supported currencies
-define(VALID_CURRENCIES, ['USD', 'EUR', 'GBP', 'JPY', 'CHF']).

%% =============================================================================
%% Account Lifecycle Functions
%% =============================================================================

%% @doc Creates a new bank account for an existing party.
%%
%% Creates a new account record linked to a party (customer). The account
%% is initialized with zero balance and active status.
%%
%% h4. Business Rules
%% <ul>
%%   <li>The party must exist and must not be closed</li>
%%   <li>The currency must be a supported ISO 4217 code</li>
%%   <li>Account ID is generated as a UUID</li>
%%   <li>Initial balance is zero</li>
%% </ul>
%%
%% h4. Errors
%% <ul>
%%   <li>{@type {error, party_not_found}} - Party ID does not exist</li>
%%   <li>{@type {error, party_closed}} - Party is closed and cannot have new accounts</li>
%%   <li>{@type {error, unsupported_currency}} - Currency code is not supported</li>
%%   <li>{@type {error, database_error}} - Mnesia transaction failed</li>
%% </ul>
%%
%% @param PartyId The unique identifier of the party (customer) who owns this account
%% @param Name A human-readable name for the account (e.g., "Primary Checking")
%% @param Currency The ISO 4217 currency code for the account denomination
%% @returns {@type {ok, #account{}}} on success, {@type {error, atom()}} on failure
%%
-spec create_account(uuid(), binary(), currency()) -> {ok, #account{}} | {error, atom()}.
create_account(PartyId, Name, Currency) when is_binary(Name) ->
    case lists:member(Currency, ?VALID_CURRENCIES) of
        true ->
            F = fun() ->
                %% Verify party exists
                case mnesia:read(party, PartyId) of
                    [] ->
                        {error, party_not_found};
                    [Party] ->
                        case Party#party.status of
                            closed ->
                                {error, party_closed};
                            _ ->
                                Now = erlang:system_time(millisecond),
                                AccountId = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
                                Account = #account{
                                    account_id = AccountId,
                                    party_id = PartyId,
                                    name = Name,
                                    currency = Currency,
                                    balance = 0,
                                    status = active,
                                    created_at = Now,
                                    updated_at = Now
                                },
                                mnesia:write(Account),
                                {ok, Account}
                        end
                end
            end,
            case mnesia:transaction(F) of
                {atomic, Result} -> Result;
                {aborted, _Reason} -> {error, database_error}
            end;
        false ->
            {error, unsupported_currency}
    end.

%% @doc Retrieves an account by its unique identifier.
%%
%% Fetches the complete account record including current balance, status,
%% and timestamps. Used for account details display and validation.
%%
%% @param AccountId The unique identifier of the account to retrieve
%% @returns {@type {ok, #account{}}} if found, {@type {error, account_not_found}} if not found
%%
-spec get_account(uuid()) -> {ok, #account{}} | {error, atom()}.
get_account(AccountId) ->
    F = fun() ->
        case mnesia:read(account, AccountId) of
            [Account] -> {ok, Account};
            [] -> {error, account_not_found}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, _Reason} -> {error, database_error}
    end.

%% @doc Lists all accounts with pagination support.
%%
%% Returns a paginated list of all accounts in the system, sorted by
%% creation date (newest first). Used for account listing pages and
%% administrative functions.
%%
%% h4. Pagination
%% <ul>
%%   <li>Page numbers start at 1</li>
%%   <li>Maximum page size is 100</li>
%% </ul>
%%
%% @param Page The page number to retrieve (must be >= 1)
%% @param PageSize The number of items per page (must be >= 1 and <= 100)
%% @returns {@type {ok, #{items => [#account{}], total => non_neg_integer(), page => pos_integer(), page_size => pos_integer()}}}
%%          on success, {@type {error, invalid_pagination}} if parameters are invalid
%%
-spec list_accounts(pos_integer(), pos_integer()) ->
    {ok, #{items => [#account{}], total => non_neg_integer(), page => pos_integer(), page_size => pos_integer()}} |
    {error, atom()}.
list_accounts(Page, PageSize) when Page >= 1, PageSize >= 1, PageSize =< 100 ->
    F = fun() ->
        AllAccounts = mnesia:select(account, [{'_', [], ['$_']}]),
        Sorted = lists:sort(
            fun(A, B) -> A#account.created_at >= B#account.created_at end,
            AllAccounts
        ),
        Total = length(Sorted),
        Offset = (Page - 1) * PageSize,
        Items = lists:sublist(Sorted, Offset + 1, PageSize),
        #{items => Items, total => Total, page => Page, page_size => PageSize}
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> {ok, Result};
        {aborted, _Reason} -> {error, database_error}
    end;
list_accounts(_, _) ->
    {error, invalid_pagination}.

%% @doc Lists all accounts belonging to a specific party with pagination.
%%
%% Returns accounts owned by a particular party (customer), sorted by
%% creation date. Used for customer dashboard and account overview screens.
%%
%% h4. Business Rules
%% <ul>
%%   <li>The party must exist</li>
%%   <li>Returns accounts across all statuses (active, frozen, closed)</li>
%% </ul>
%%
%% @param PartyId The unique identifier of the party whose accounts to list
%% @param Page The page number to retrieve (must be >= 1)
%% @param PageSize The number of items per page (must be >= 1 and <= 100)
%% @returns {@type {ok, #{items => [#account{}], total => non_neg_integer(), page => pos_integer(), page_size => pos_integer()}}}
%%          on success, {@type {error, party_not_found}} if party doesn't exist,
%%          {@type {error, invalid_pagination}} if parameters are invalid
%%
-spec list_accounts_for_party(uuid(), pos_integer(), pos_integer()) ->
    {ok, #{items => [#account{}], total => non_neg_integer(), page => pos_integer(), page_size => pos_integer()}} |
    {error, atom()}.
list_accounts_for_party(PartyId, Page, PageSize) when Page >= 1, PageSize >= 1, PageSize =< 100 ->
    F = fun() ->
        %% Verify party exists
        case mnesia:read(party, PartyId) of
            [] ->
                {error, party_not_found};
            _ ->
                Accounts = mnesia:index_read(account, PartyId, party_id),
                Sorted = lists:sort(
                    fun(A, B) -> A#account.created_at >= B#account.created_at end,
                    Accounts
                ),
                Total = length(Sorted),
                Offset = (Page - 1) * PageSize,
                Items = lists:sublist(Sorted, Offset + 1, PageSize),
                #{items => Items, total => Total, page => Page, page_size => PageSize}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, {error, _} = Error} -> Error;
        {atomic, Result} -> {ok, Result};
        {aborted, _Reason} -> {error, database_error}
    end;
list_accounts_for_party(_, _, _) ->
    {error, invalid_pagination}.

%% @doc Freezes an account, temporarily restricting all transactions.
%%
%% Places an account into a frozen state where no deposits, withdrawals,
%% or transfers are permitted. The current balance is preserved.
%%
%% h4. Use Cases
%% <ul>
%%   <li>Regulatory compliance holds</li>
%%   <li>Fraud investigation</li>
%%   <li>Customer-initiated freeze (e.g., lost card)</li>
%%   <li>Legal disputes</li>
%% </ul>
%%
%% h4. Business Rules
%% <ul>
%%   <li>Account must exist</li>
%%   <li>Account must currently be in active state</li>
%%   <li>Closed accounts cannot be frozen</li>
%% </ul>
%%
%% @param AccountId The unique identifier of the account to freeze
%% @returns {@type {ok, #account{}} with updated status} on success,
%%          {@type {error, account_not_found}} if account doesn't exist,
%%          {@type {error, account_already_frozen}} if already frozen,
%%          {@type {error, account_closed}} if account is closed
%%
-spec freeze_account(uuid()) -> {ok, #account{}} | {error, atom()}.
freeze_account(AccountId) ->
    F = fun() ->
        case mnesia:read(account, AccountId, write) of
            [Account] ->
                case Account#account.status of
                    active ->
                        Now = erlang:system_time(millisecond),
                        Updated = Account#account{status = frozen, updated_at = Now},
                        mnesia:write(Updated),
                        {ok, Updated};
                    frozen ->
                        {error, account_already_frozen};
                    closed ->
                        {error, account_closed}
                end;
            [] ->
                {error, account_not_found}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, _Reason} -> {error, database_error}
    end.

%% @doc Unfreezes a previously frozen account, restoring normal operations.
%%
%% Returns a frozen account to active state, allowing all transactions
%% to resume. The balance remains unchanged.
%%
%% h4. Use Cases
%% <ul>
%%   <li>Completion of fraud investigation</li>
%%   <li>Customer request to lift hold</li>
%%   <li>Regulatory clearance</li>
%% </ul>
%%
%% h4. Business Rules
%% <ul>
%%   <li>Account must exist</li>
%%   <li>Account must currently be in frozen state</li>
%%   <li>Closed accounts cannot be unfrozen</li>
%% </ul>
%%
%% @param AccountId The unique identifier of the account to unfreeze
%% @returns {@type {ok, #account{}} with updated status} on success,
%%          {@type {error, account_not_found}} if account doesn't exist,
%%          {@type {error, account_not_frozen}} if account is not frozen,
%%          {@type {error, account_closed}} if account is closed
%%
-spec unfreeze_account(uuid()) -> {ok, #account{}} | {error, atom()}.
unfreeze_account(AccountId) ->
    F = fun() ->
        case mnesia:read(account, AccountId, write) of
            [Account] ->
                case Account#account.status of
                    frozen ->
                        Now = erlang:system_time(millisecond),
                        Updated = Account#account{status = active, updated_at = Now},
                        mnesia:write(Updated),
                        {ok, Updated};
                    active ->
                        {error, account_not_frozen};
                    closed ->
                        {error, account_closed}
                end;
            [] ->
                {error, account_not_found}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, _Reason} -> {error, database_error}
    end.

%% @doc Permanently closes an account.
%%
%% Closes an account permanently, making it inactive. The account balance
%% must be zero before closure can occur. This is a terminal state -
%% closed accounts cannot be reopened.
%%
%% h4. Use Cases
%% <ul>
%%   <li>Customer requests account closure</li>
%%   <li>Account inactivity (after dormancy period)</li>
%%   <li>Regulatory requirement</li>
%% </ul>
%%
%% h4. Business Rules
%% <ul>
%%   <li>Account must exist</li>
%%   <li>Account balance must be zero (all funds must be withdrawn or transferred)</li>
%%   <li>Once closed, the account cannot be reopened</li>
%% </ul>
%%
%% @param AccountId The unique identifier of the account to close
%% @returns {@type {ok, #account{}} with updated status} on success,
%%          {@type {error, account_not_found}} if account doesn't exist,
%%          {@type {error, account_has_balance}} if balance is not zero
%%
-spec close_account(uuid()) -> {ok, #account{}} | {error, atom()}.
close_account(AccountId) ->
    F = fun() ->
        case mnesia:read(account, AccountId, write) of
            [Account] ->
                case Account#account.balance of
                    0 ->
                        Now = erlang:system_time(millisecond),
                        Updated = Account#account{status = closed, updated_at = Now},
                        mnesia:write(Updated),
                        {ok, Updated};
                    _ ->
                        {error, account_has_balance}
                end;
            [] ->
                {error, account_not_found}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, _Reason} -> {error, database_error}
    end.

%% @doc Retrieves the current balance of an account with formatted display.
%%
%% Returns the account's current balance along with currency information
%% and a human-readable formatted string for display purposes.
%%
%% h4. Balance Representation
%% <ul>
%%   <li>Raw balance is stored in minor units (cents, pence, etc.)</li>
%%   <li>Formatted balance includes currency symbol and decimal places</li>
%%   <li>JPY is displayed without decimals (no minor units)</li>
%% </ul>
%%
%% h4. Example Output
%% <ul>
%%   <li>USD 1000 -> "$10.00"</li>
%%   <li>JPY 1000 -> "¥1000"</li>
%%   <li>EUR 12345 -> "€123.45"</li>
%% </ul>
%%
%% @param AccountId The unique identifier of the account
%% @returns {@type {ok, #{account_id => uuid(), currency => currency(), balance => amount(), balance_formatted => binary()}}}
%%          on success, {@type {error, account_not_found}} if account doesn't exist
%%
-spec get_balance(uuid()) -> {ok, #{account_id => uuid(), currency => currency(), balance => amount(), available_balance => amount(), balance_formatted => binary()}} | {error, atom()}.
get_balance(AccountId) ->
    F = fun() ->
        case mnesia:read(account, AccountId) of
            [Account] ->
                Formatted = format_balance(Account#account.balance, Account#account.currency),
                {ok, #{
                    account_id        => AccountId,
                    currency          => Account#account.currency,
                    balance           => Account#account.balance,
                    available_balance => available_balance_for_account(AccountId, Account#account.balance),
                    balance_formatted => Formatted
                }};
            [] ->
                {error, account_not_found}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, _Reason} -> {error, database_error}
    end.

%% @doc Set a per-transaction withdrawal limit on an account.
%%
%% Any withdrawal exceeding this amount will be rejected with
%% `withdrawal_limit_exceeded'. Pass `undefined' to remove the limit.
%%
%% @param AccountId The account to configure
%% @param Limit     Max single withdrawal in minor units
%% @returns ok on success, {error, account_not_found} if missing

-spec set_withdrawal_limit(uuid(), amount() | undefined) -> ok | {error, atom()}.
set_withdrawal_limit(AccountId, Limit) ->
    F = fun() ->
        case mnesia:read(account, AccountId, write) of
            [] -> {error, account_not_found};
            [Account] ->
                mnesia:write(Account#account{withdrawal_limit = Limit}),
                ok
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, _Reason} -> {error, database_error}
    end.

%% =============================================================================
%% Internal Helper Functions
%% =============================================================================

%% @private Compute available balance accounting for active holds.
%% Must be called from within a Mnesia transaction.
-spec available_balance_for_account(uuid(), amount()) -> amount().
available_balance_for_account(AccountId, Balance) ->
    Holds = mnesia:index_read(account_hold, AccountId, account_id),
    HoldTotal = lists:sum([H#account_hold.amount || H <- Holds, H#account_hold.status =:= active]),
    Balance - HoldTotal.

%% @private Formats a monetary balance for human display.
%%
%% Converts the internal minor-unit representation to a formatted string
%% with appropriate currency symbol and decimal places.
%%
%% h4. Currency-Specific Formatting
%% <ul>
%%   <li><strong>USD, EUR, GBP</strong>: Symbol + dollars + "." + cents (2 decimals)</li>
%%   <li><strong>JPY</strong>: Symbol + yen (no decimals)</li>
%%   <li><strong>CHF</strong>: "CHF " prefix + amount + "." + cents</li>
%% </ul>
%%
%% @param Balance The amount in minor units
%% @param Currency The ISO 4217 currency code
%% @returns A binary string formatted for display
%%
-spec format_balance(amount(), currency()) -> binary().
format_balance(Balance, 'JPY') ->
    iolist_to_binary([<<"¥">>, integer_to_binary(Balance)]);
format_balance(Balance, 'USD') ->
    iolist_to_binary([<<"$">>, format_decimal(Balance)]);
format_balance(Balance, 'EUR') ->
    iolist_to_binary([<<"€">>, format_decimal(Balance)]);
format_balance(Balance, 'GBP') ->
    iolist_to_binary([<<"£">>, format_decimal(Balance)]);
format_balance(Balance, 'CHF') ->
    iolist_to_binary([<<"CHF ">>, format_decimal(Balance)]).

%% @private Formats a decimal amount (minor units to dollars.cents).
%%
%% Converts an amount in minor units (e.g., 1234 = $12.34) to a decimal
%% string representation with exactly 2 decimal places.
%%
%% @param Amount The amount in minor units (non-negative integer)
%% @returns Binary string in format "D.CC" (e.g., "12.34")
%%
-spec format_decimal(amount()) -> binary().
format_decimal(Amount) ->
    Dollars = Amount div 100,
    Cents = Amount rem 100,
    iolist_to_binary([
        integer_to_binary(Dollars),
        <<".">>,
        string:pad(integer_to_binary(Cents), 2, leading, "0")
    ]).
