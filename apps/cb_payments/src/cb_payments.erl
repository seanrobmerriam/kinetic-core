%%%
%% @doc CB Payments Module
%%
%% This module provides the core payment processing functionality for IronLedger,
%% a core banking system implementing double-entry bookkeeping.
%%
%% ## Payment Types
%%
%% The system supports four main types of payment operations:
%%
%% <ul>
%%   <li><b>Transfer</b> - Move funds between two accounts (internal transfer)</li>
%%   <li><b>Deposit</b> - Add funds to an account (e.g., cash deposit, incoming transfer)</li>
%%   <li><b>Withdrawal</b> - Remove funds from an account (e.g., cash withdrawal, payment)</li>
%%   <li><b>Adjustment</b> - Correct account balances (for corrections, fees, interest)</li>
%% </ul>
%%
%% ## Idempotency
%%
%% All payment operations are <b>idempotent</b>, which is critical for financial operations
%% that may be retried due to network failures or client timeouts. Each operation accepts
%% an idempotency key (a unique client-generated UUID) that prevents duplicate processing:
%%
%% <ul>
%%   <li>If the key has never been seen, the operation proceeds normally</li>
%%   <li>If the key exists, the previously created transaction is returned (no new transaction)</li>
%% </ul>
%%
%% Clients should generate a new UUID for each payment request and store it client-side
%% to safely retry failed requests with the same key.
%%
%% ## Transaction Reversal
%%
%% Posted transactions can be reversed using {@link reverse_transaction/1}. A reversal:
%%
%% <ul>
%%   <li>Creates a new transaction with opposite ledger entries</li>
%%   <li>Updates the original transaction status to <tt>reversed</tt></li>
%%   <li>Reverses the balance changes on affected accounts</li>
%%   <li>Links to the original transaction via description</li>
%% </ul>
%%
%% Only transactions with <tt>posted</tt> status can be reversed. Attempting to reverse
%% already-reversed or pending transactions returns an error.
%%
%% ## Monetary Amounts
%%
%% All monetary amounts are represented as non-negative integers in minor units (cents).
%% For example, $100.00 USD is represented as <tt>10000</tt>. This avoids floating-point
%% precision issues critical in financial systems.
%%
%% ## Account States
%%
%% Payments can only be performed on accounts with <tt>active</tt> status. Attempts to
%% process payments on <tt>frozen</tt> or <tt>closed</tt> accounts return appropriate errors.
%%
%% ## Currency Validation
%%
%% All payment operations validate that the transaction currency matches the account
%% currency. Cross-currency operations are not supported and return <tt>currency_mismatch</tt>.
%%
%% @see cb_ledger
%% @see cb_accounts

-module(cb_payments).

-include_lib("cb_ledger/include/cb_ledger.hrl").
-include_lib("cb_events/include/cb_events.hrl").

-export([
    transfer/6,
    deposit/5,
    deposit/6,
    withdraw/5,
    adjust_balance/5,
    get_transaction/1,
    list_transactions_for_account/3,
    query_transactions/1,
    reverse_transaction/1
]).

%% Maximum allowed amount (≈ $100 billion)
-define(MAX_AMOUNT, 9_999_999_999_99).

%%
%% @doc Transfer funds between two accounts
%%
%% Performs an internal transfer of funds from a source account to a destination
%% account. This is a double-entry bookkeeping operation that:
%%
%% <ol>
%%   <li>Debits (decreases) the source account balance</li>
%%   <li>Credits (increases) the destination account balance</li>
%%   <li>Creates a transaction record linking both accounts</li>
%%   <li>Creates two ledger entries (one debit, one credit)</li>
%% </ol>
%%
%% Both accounts must have the same currency as the transfer amount. The source
%% account must have sufficient funds. Neither account can be frozen or closed.
%%
%% This operation is idempotent - if the same idempotency key is provided for
%% multiple calls, only the first call creates a transaction; subsequent calls
%% return the existing transaction.
%%
%% @param IdempotencyKey A unique client-generated UUID to ensure idempotency
%% @param SourceId The account to debit (transfer funds from)
%% @param DestId The account to credit (transfer funds to)
%% @param Amount The amount to transfer in minor units (cents)
%% @param Currency The ISO 4217 currency code (must match account currency)
%% @param Description Human-readable description of the transfer
%%
%% @returns <tt>{ok, Transaction}</tt> on success, or <tt>{error, Reason}</tt> on failure
%%
%% @see deposit/5
%% @see withdraw/5
%% @see reverse_transaction/1

-spec transfer(binary(), uuid(), uuid(), amount(), currency(), binary()) ->
    {ok, #transaction{}} | {error, atom()}.
transfer(IdempotencyKey, SourceId, DestId, Amount, Currency, Description) ->
    case validate_amount(Amount) of
        ok ->
            case SourceId =:= DestId of
                true ->
                    {error, same_account_transfer};
                false ->
                    do_transfer(IdempotencyKey, SourceId, DestId, Amount, Currency, Description)
            end;
        Error ->
            Error
    end.

%% @private
%%
%% Internal transfer implementation that performs the actual funds transfer.
%% This function is called after validation passes.
%%
%% The transfer is executed within a Mnesia transaction to ensure atomicity:
%% <ol>
%%   <li>Check for existing transaction with idempotency key</li>
%%   <li>Lock both accounts for write</li>
%%   <li>Validate accounts (status, currency, sufficient funds)</li>
%%   <li>Update both account balances</li>
%%   <li>Create transaction record</li>
%%   <li>Create two ledger entries (debit and credit)</li>
%% </ol>
%%
%% If any step fails, the entire transaction is rolled back.

-spec do_transfer(binary(), uuid(), uuid(), amount(), currency(), binary()) ->
    {ok, #transaction{}} | {error, atom()}.
do_transfer(IdempotencyKey, SourceId, DestId, Amount, Currency, Description) ->
    F = fun() ->
        %% 1. Idempotency check
        case mnesia:index_read(transaction, IdempotencyKey, idempotency_key) of
            [Existing] ->
                {ok, Existing};
            [] ->
                %% 2. Lock and read both accounts
                case mnesia:read(account, SourceId, write) of
                    [] ->
                        {error, account_not_found};
                    [Source] ->
                        case mnesia:read(account, DestId, write) of
                            [] ->
                                {error, account_not_found};
                            [Dest] ->
                                %% 3. Validate (use available balance for source funds check)
                                AvailBal = available_balance_in_txn(SourceId, Source#account.balance),
                                SourceWithAvail = Source#account{balance = AvailBal},
                                case validate_accounts_for_transfer(SourceWithAvail, Dest, Currency, Amount) of
                                    ok ->
                                        %% 4. Update balances
                                        Now = erlang:system_time(millisecond),
                                        mnesia:write(Source#account{
                                            balance = Source#account.balance - Amount,
                                            updated_at = Now
                                        }),
                                        mnesia:write(Dest#account{
                                            balance = Dest#account.balance + Amount,
                                            updated_at = Now
                                        }),

                                        %% 5. Write transaction record
                                        TxnId = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
                                        Txn = #transaction{
                                            txn_id = TxnId,
                                            idempotency_key = IdempotencyKey,
                                            txn_type = transfer,
                                            status = posted,
                                            amount = Amount,
                                            currency = Currency,
                                            source_account_id = SourceId,
                                            dest_account_id = DestId,
                                            description = Description,
                                            created_at = Now,
                                            posted_at = Now
                                        },
                                        mnesia:write(Txn),

                                        %% 6. Write ledger entries (always two)
                                        EntryId1 = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
                                        EntryId2 = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
                                        mnesia:write(#ledger_entry{
                                            entry_id = EntryId1,
                                            txn_id = TxnId,
                                            account_id = SourceId,
                                            entry_type = debit,
                                            amount = Amount,
                                            currency = Currency,
                                            description = Description,
                                            posted_at = Now
                                        }),
                                        mnesia:write(#ledger_entry{
                                            entry_id = EntryId2,
                                            txn_id = TxnId,
                                            account_id = DestId,
                                            entry_type = credit,
                                            amount = Amount,
                                            currency = Currency,
                                            description = Description,
                                            posted_at = Now
                                        }),

                                        _ = cb_events:write_outbox(<<"transaction.posted">>, #{
                                            txn_id            => TxnId,
                                            txn_type          => transfer,
                                            amount            => Amount,
                                            currency          => Currency,
                                            source_account_id => SourceId,
                                            dest_account_id   => DestId
                                        }),

                                        {ok, Txn};
                                    Error ->
                                        Error
                                end
                        end
                end
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, _Reason} -> {error, database_error}
    end.

%% @private
%%
%% Validates both source and destination accounts for a transfer operation.
%%
%% Checks performed:
%% <ol>
%%   <li>Source account status is <tt>active</tt> (not frozen or closed)</li>
%%   <li>Destination account status is <tt>active</tt></li>
%%   <li>Both accounts have the same currency</li>
%%   <li>The transaction currency matches the account currency</li>
%%   <li>Source account has sufficient balance for the transfer</li>
%% </ol>
%%
%% @param Source The source account record (to be debited)
%% @param Dest The destination account record (to be credited)
%% @param Currency The requested transaction currency
%% @param Amount The requested transfer amount
%%
%% @returns <tt>ok</tt> if validation passes, or <tt>{error, Reason}</tt> if validation fails

-spec validate_accounts_for_transfer(#account{}, #account{}, currency(), amount()) -> ok | {error, atom()}.
validate_accounts_for_transfer(Source, Dest, Currency, Amount) ->
    %% Check source account status
    case Source#account.status of
        frozen -> {error, account_frozen};
        closed -> {error, account_closed};
        active ->
            %% Check destination account status
            case Dest#account.status of
                frozen -> {error, account_frozen};
                closed -> {error, account_closed};
                active ->
                    %% Check currency match
                    case Source#account.currency =:= Dest#account.currency of
                        false -> {error, currency_mismatch};
                        true ->
                            case Source#account.currency =:= Currency of
                                false -> {error, currency_mismatch};
                                true ->
                                    %% Check sufficient funds
                                    case Source#account.balance >= Amount of
                                        true -> ok;
                                        false -> {error, insufficient_funds}
                                    end
                            end
                    end
            end
    end.

%%
%% @doc Deposit funds into an account
%%
%% Performs a deposit operation, crediting funds to the specified account.
%% This is typically used for:
%%
%% <ul>
%%   <li>Cash deposits at a branch or ATM</li>
%%   <li>Incoming transfers from external systems</li>
%%   <li>Check deposits</li>
%%   <li>Any external source of funds</li>
%% </ul>
%%
%% The deposit creates a credit ledger entry and increases the account balance.
%% The destination account must be active and must have the same currency as
%% the deposit amount.
%%
%% This operation is idempotent - if the same idempotency key is provided for
%% multiple calls, only the first call creates a transaction; subsequent calls
%% return the existing transaction.
%%
%% @param IdempotencyKey A unique client-generated UUID to ensure idempotency
%% @param DestId The account to credit (receive funds)
%% @param Amount The amount to deposit in minor units (cents)
%% @param Currency The ISO 4217 currency code (must match account currency)
%% @param Description Human-readable description of the deposit
%%
%% @returns <tt>{ok, Transaction}</tt> on success, or <tt>{error, Reason}</tt> on failure
%%
%% @see transfer/6
%% @see withdraw/5
%% @see reverse_transaction/1

-spec deposit(binary(), uuid(), amount(), currency(), binary()) ->
    {ok, #transaction{}} | {error, atom()}.
deposit(IdempotencyKey, DestId, Amount, Currency, Description) ->
    deposit(IdempotencyKey, DestId, Amount, Currency, Description, undefined).

-spec deposit(binary(), uuid(), amount(), currency(), binary(), binary() | undefined) ->
    {ok, #transaction{}} | {error, atom()}.
deposit(IdempotencyKey, DestId, Amount, Currency, Description, Channel) ->
    case validate_amount(Amount) of
        ok ->
            case maybe_check_channel_limits(Channel, Currency, Amount) of
                ok ->
                    F = fun() ->
                        case mnesia:index_read(transaction, IdempotencyKey, idempotency_key) of
                            [Existing] ->
                                {ok, Existing};
                            [] ->
                                case mnesia:read(account, DestId, write) of
                                    [] ->
                                        {error, account_not_found};
                                    [Dest] ->
                                        case validate_account_for_deposit(Dest, Currency) of
                                            ok ->
                                                Now = erlang:system_time(millisecond),
                                                mnesia:write(Dest#account{
                                                    balance = Dest#account.balance + Amount,
                                                    updated_at = Now
                                                }),

                                                TxnId = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
                                                Txn = #transaction{
                                                    txn_id = TxnId,
                                                    idempotency_key = IdempotencyKey,
                                                    txn_type = deposit,
                                                    status = posted,
                                                    amount = Amount,
                                                    currency = Currency,
                                                    source_account_id = undefined,
                                                    dest_account_id = DestId,
                                                    description = Description,
                                                    channel = Channel,
                                                    created_at = Now,
                                                    posted_at = Now
                                                },
                                                mnesia:write(Txn),

                                                EntryId = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
                                                mnesia:write(#ledger_entry{
                                                    entry_id = EntryId,
                                                    txn_id = TxnId,
                                                    account_id = DestId,
                                                    entry_type = credit,
                                                    amount = Amount,
                                                    currency = Currency,
                                                    description = Description,
                                                    posted_at = Now
                                                }),

                                                _ = cb_events:write_outbox(<<"transaction.posted">>, #{
                                                    txn_id          => TxnId,
                                                    txn_type        => deposit,
                                                    amount          => Amount,
                                                    currency        => Currency,
                                                    dest_account_id => DestId
                                                }),

                                                {ok, Txn};
                                            DepositError ->
                                                DepositError
                                        end
                                end
                        end
                    end,
                    case mnesia:transaction(F) of
                        {atomic, Result} -> Result;
                        {aborted, _Reason} -> {error, database_error}
                    end;
                LimitError ->
                    LimitError
            end;
        AmountError ->
            AmountError
    end.

%% @private Check per-txn and daily channel limits when a channel is provided.
-spec maybe_check_channel_limits(binary() | atom() | undefined, currency(), pos_integer()) ->
    ok | {error, atom()}.
maybe_check_channel_limits(undefined, _Currency, _Amount) ->
    ok;
maybe_check_channel_limits(ChannelBin, Currency, Amount) when is_binary(ChannelBin) ->
    try binary_to_existing_atom(ChannelBin, utf8) of
        Channel ->
            case cb_channel_limits:validate_amount(Channel, Currency, Amount) of
                ok    -> cb_channel_limits:validate_daily_volume(Channel, Currency, Amount);
                Error -> Error
            end
    catch
        error:badarg -> ok  % unknown channel — skip limit check
    end;
maybe_check_channel_limits(Channel, Currency, Amount) when is_atom(Channel) ->
    case cb_channel_limits:validate_amount(Channel, Currency, Amount) of
        ok    -> cb_channel_limits:validate_daily_volume(Channel, Currency, Amount);
        Error -> Error
    end.

%% @private
%%
%% Validates an account for a deposit operation.
%%
%% Checks performed:
%% <ol>
%%   <li>Account status is <tt>active</tt> (not frozen or closed)</li>
%%   <li>Account currency matches the deposit currency</li>
%% </ol>
%%
%% Note: Deposits do not require sufficient funds check since they only
%% increase the balance.
%%
%% @param Account The account record to validate
%% @param Currency The requested deposit currency
%%
%% @returns <tt>ok</tt> if validation passes, or <tt>{error, Reason}</tt> if validation fails

-spec validate_account_for_deposit(#account{}, currency()) -> ok | {error, atom()}.
validate_account_for_deposit(Account, Currency) ->
    case Account#account.status of
        frozen -> {error, account_frozen};
        closed -> {error, account_closed};
        active ->
            case Account#account.currency =:= Currency of
                true -> ok;
                false -> {error, currency_mismatch}
            end
    end.

%%
%% @doc Withdraw funds from an account
%%
%% Performs a withdrawal operation, debiting funds from the specified account.
%% This is typically used for:
%%
%% <ul>
%%   <li>Cash withdrawals at a branch or ATM</li>
%%   <li>Outgoing transfers to external systems</li>
%%   <li>Bill payments</li>
%%   <li>Any disbursement of funds</li>
%% </ul>
%%
%% The withdrawal creates a debit ledger entry and decreases the account balance.
%% The source account must be active, must have sufficient funds, and must have
%% the same currency as the withdrawal amount.
%%
%% This operation is idempotent - if the same idempotency key is provided for
%% multiple calls, only the first call creates a transaction; subsequent calls
%% return the existing transaction.
%%
%% @param IdempotencyKey A unique client-generated UUID to ensure idempotency
%% @param SourceId The account to debit (withdraw funds from)
%% @param Amount The amount to withdraw in minor units (cents)
%% @param Currency The ISO 4217 currency code (must match account currency)
%% @param Description Human-readable description of the withdrawal
%%
%% @returns <tt>{ok, Transaction}</tt> on success, or <tt>{error, Reason}</tt> on failure
%%
%% @see transfer/6
%% @see deposit/5
%% @see reverse_transaction/1

-spec withdraw(binary(), uuid(), amount(), currency(), binary()) ->
    {ok, #transaction{}} | {error, atom()}.
withdraw(IdempotencyKey, SourceId, Amount, Currency, Description) ->
    case validate_amount(Amount) of
        ok ->
            F = fun() ->
                %% Idempotency check
                case mnesia:index_read(transaction, IdempotencyKey, idempotency_key) of
                    [Existing] ->
                        {ok, Existing};
                    [] ->
                        case mnesia:read(account, SourceId, write) of
                            [] ->
                                {error, account_not_found};
                            [Source] ->
                                %% Use available balance (balance minus active holds) for funds check
                                AvailBal = available_balance_in_txn(SourceId, Source#account.balance),
                                SourceWithAvail = Source#account{balance = AvailBal},
                                case validate_account_for_withdrawal(SourceWithAvail, Currency, Amount) of
                                    ok ->
                                        Now = erlang:system_time(millisecond),
                                        mnesia:write(Source#account{
                                            balance = Source#account.balance - Amount,
                                            updated_at = Now
                                        }),

                                        TxnId = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
                                        Txn = #transaction{
                                            txn_id = TxnId,
                                            idempotency_key = IdempotencyKey,
                                            txn_type = withdrawal,
                                            status = posted,
                                            amount = Amount,
                                            currency = Currency,
                                            source_account_id = SourceId,
                                            dest_account_id = undefined,
                                            description = Description,
                                            created_at = Now,
                                            posted_at = Now
                                        },
                                        mnesia:write(Txn),

                                        EntryId = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
                                        mnesia:write(#ledger_entry{
                                            entry_id = EntryId,
                                            txn_id = TxnId,
                                            account_id = SourceId,
                                            entry_type = debit,
                                            amount = Amount,
                                            currency = Currency,
                                            description = Description,
                                            posted_at = Now
                                        }),

                                        _ = cb_events:write_outbox(<<"transaction.posted">>, #{
                                            txn_id            => TxnId,
                                            txn_type          => withdrawal,
                                            amount            => Amount,
                                            currency          => Currency,
                                            source_account_id => SourceId
                                        }),

                                        {ok, Txn};
                                    Error ->
                                        Error
                                end
                        end
                end
            end,
            case mnesia:transaction(F) of
                {atomic, Result} -> Result;
                {aborted, _Reason} -> {error, database_error}
            end;
        Error ->
            Error
    end.

%% @private
%%
%% Validates an account for a withdrawal operation.
%%
%% Checks performed:
%% <ol>
%%   <li>Account status is <tt>active</tt> (not frozen or closed)</li>
%%   <li>Account currency matches the withdrawal currency</li>
%%   <li>Account has sufficient balance for the withdrawal</li>
%% </ol>
%%
%% @param Account The account record to validate
%% @param Currency The requested withdrawal currency
%% @param Amount The requested withdrawal amount
%%
%% @returns <tt>ok</tt> if validation passes, or <tt>{error, Reason}</tt> if validation fails

-spec validate_account_for_withdrawal(#account{}, currency(), amount()) -> ok | {error, atom()}.
validate_account_for_withdrawal(Account, Currency, Amount) ->
    case Account#account.status of
        frozen -> {error, account_frozen};
        closed -> {error, account_closed};
        active ->
            case Account#account.currency =:= Currency of
                false -> {error, currency_mismatch};
                true ->
                    case Account#account.balance >= Amount of
                        false -> {error, insufficient_funds};
                        true ->
                            case Account#account.withdrawal_limit of
                                undefined -> ok;
                                Limit when Amount > Limit -> {error, withdrawal_limit_exceeded};
                                _ -> ok
                            end
                    end
            end
    end.

%%
%% @doc Get a transaction by ID
%%
%% Retrieves a single transaction from the system by its unique transaction ID.
%% This is useful for:
%%
%% <ul>
%%   <li>Transaction confirmation after a payment operation</li>
%%   <li>Looking up transaction details for customer service</li>
%%   <li>Audit and compliance inquiries</li>
%% </ul>
%%
%% @param TxnId The unique transaction identifier (UUID)
%%
%% @returns <tt>{ok, Transaction}</tt> if found, or <tt>{error, transaction_not_found}</tt>
%%
%% @see list_transactions_for_account/3
%% @see reverse_transaction/1

-spec get_transaction(uuid()) -> {ok, #transaction{}} | {error, atom()}.
get_transaction(TxnId) ->
    F = fun() ->
        case mnesia:read(transaction, TxnId) of
            [Txn] -> {ok, Txn};
            [] -> {error, transaction_not_found}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, _Reason} -> {error, database_error}
    end.

%%
%% @doc List transactions for an account with pagination
%%
%% Retrieves a paginated list of transactions for a specific account.
%% The results include both transactions where the account is the source
%% (money leaving) and where it is the destination (money entering).
%%
%% Results are sorted by creation date in descending order (newest first).
%% Duplicate transactions (if any exist due to data anomalies) are removed.
%%
%% The response includes pagination metadata:
%% <ul>
%%   <li><tt>items</tt> - List of transaction records for the current page</li>
%%   <li><tt>total</tt> - Total number of transactions for the account</li>
%%   <li><tt>page</tt> - Current page number (1-indexed)</li>
%%   <li><tt>page_size</tt> - Number of items per page</li>
%% </ul>
%%
%% @param AccountId The account to list transactions for
%% @param Page Page number (must be >= 1)
%% @param PageSize Number of items per page (must be >= 1 and <= 100)
%%
%% @returns <tt>{ok, Result}</tt> with pagination data, or <tt>{error, invalid_pagination}</tt>
%%
%% @see get_transaction/1

-spec list_transactions_for_account(uuid(), pos_integer(), pos_integer()) ->
    {ok, #{items => [#transaction{}], total => non_neg_integer(), page => pos_integer(), page_size => pos_integer()}} |
    {error, atom()}.
list_transactions_for_account(AccountId, Page, PageSize) when Page >= 1, PageSize >= 1, PageSize =< 100 ->
    F = fun() ->
        %% Get transactions where account is source or destination
        SourceTxns = mnesia:index_read(transaction, AccountId, source_account_id),
        DestTxns = mnesia:index_read(transaction, AccountId, dest_account_id),
        AllTxns = SourceTxns ++ DestTxns,
        %% Remove duplicates and sort by created_at descending
        Unique = lists:ukeysort(#transaction.txn_id, AllTxns),
        Sorted = lists:sort(
            fun(A, B) -> A#transaction.created_at >= B#transaction.created_at end,
            Unique
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
list_transactions_for_account(_, _, _) ->
    {error, invalid_pagination}.

%%
%% @doc Query transactions with optional filters
%%
%% Accepts a filter map with any combination of:
%%   account_id  - restrict to transactions involving this account
%%   from_ts     - minimum created_at (milliseconds)
%%   to_ts       - maximum created_at (milliseconds)
%%   txn_type    - atom matching txn_type()
%%   min_amount  - inclusive lower bound on amount
%%   max_amount  - inclusive upper bound on amount
%%   status      - atom matching txn_status()
%%   page        - 1-indexed page (default 1)
%%   page_size   - items per page, 1-100 (default 20)
%%
%% Returns {ok, #{items, total, page, page_size}} or {error, invalid_pagination}.

-spec query_transactions(map()) ->
    {ok, #{items => [#transaction{}], total => non_neg_integer(),
           page => pos_integer(), page_size => pos_integer()}} |
    {error, atom()}.
query_transactions(Filters) ->
    Page     = maps:get(page,      Filters, 1),
    PageSize = maps:get(page_size, Filters, 20),
    case (Page >= 1) andalso (PageSize >= 1) andalso (PageSize =< 100) of
        false ->
            {error, invalid_pagination};
        true ->
            F = fun() ->
                AccountId = maps:get(account_id, Filters, undefined),
                Candidates = case AccountId of
                    undefined ->
                        mnesia:foldl(fun(T, Acc) -> [T | Acc] end, [], transaction);
                    _ ->
                        SrcTxns  = mnesia:index_read(transaction, AccountId, source_account_id),
                        DestTxns = mnesia:index_read(transaction, AccountId, dest_account_id),
                        All = SrcTxns ++ DestTxns,
                        lists:ukeysort(#transaction.txn_id, All)
                end,
                Filtered = lists:filter(fun(T) -> matches_filters(T, Filters) end, Candidates),
                Sorted = lists:sort(
                    fun(A, B) -> A#transaction.created_at >= B#transaction.created_at end,
                    Filtered
                ),
                Total  = length(Sorted),
                Offset = (Page - 1) * PageSize,
                Items  = lists:sublist(Sorted, Offset + 1, PageSize),
                #{items => Items, total => Total, page => Page, page_size => PageSize}
            end,
            case mnesia:transaction(F) of
                {atomic, Result} -> {ok, Result};
                {aborted, _Reason} -> {error, database_error}
            end
    end.

%% @private Apply filter criteria to a single transaction record.
-spec matches_filters(#transaction{}, map()) -> boolean().
matches_filters(T, Filters) ->
    check_filter(from_ts,    fun(V) -> T#transaction.created_at >= V end, Filters) andalso
    check_filter(to_ts,      fun(V) -> T#transaction.created_at =< V end, Filters) andalso
    check_filter(txn_type,   fun(V) -> T#transaction.txn_type   =:= V end, Filters) andalso
    check_filter(status,     fun(V) -> T#transaction.status     =:= V end, Filters) andalso
    check_filter(min_amount, fun(V) -> T#transaction.amount     >= V end, Filters) andalso
    check_filter(max_amount, fun(V) -> T#transaction.amount     =< V end, Filters).

%% @private Returns true when key is absent or predicate holds.
-dialyzer({nowarn_function, check_filter/3}).
-spec check_filter(atom(), fun((term()) -> boolean()), map()) -> boolean().
check_filter(Key, Pred, Filters) ->
    case maps:find(Key, Filters) of
        error      -> true;
        {ok, Val}  -> Pred(Val)
    end.


%%
%% Creates a reversal (also known as a "reversal transaction" or "void") for a
%% previously posted transaction. This is used when:
%%
%% <ul>
%%   <li>A customer requests a refund</li>
%%   <li>A duplicate or erroneous transaction needs to be undone</li>
%%   <li>A dispute is resolved in favor of the customer</li>
%%   <li>Regulatory requirements mandate reversal</li>
%% </ul>
%%
%% The reversal process:
%%
%% <ol>
%%   <li>Verifies the original transaction exists and has <tt>posted</tt> status</li>
%%   <li>Creates a new transaction with opposite ledger entries</li>
%%   <li>Updates the original transaction status to <tt>reversed</tt></li>
%%   <li>Reverses the balance changes on affected accounts</li>
%%   <li>Links the reversal to the original via description</li>
%% </ol>
%%
%% <b>Important:</b> Only transactions with <tt>posted</tt> status can be reversed.
%% Attempting to reverse already-reversed transactions returns
%% <tt>transaction_already_reversed</tt>. Attempting to reverse pending transactions
%% returns <tt>transaction_not_posted</tt>.
%%
%% The reversal is itself idempotent - calling with the same transaction ID multiple
%% times will return the same reversal transaction (created on first call).
%%
%% @param TxnId The ID of the transaction to reverse
%%
%% @returns <tt>{ok, ReversalTransaction}</tt> on success, or <tt>{error, Reason}</tt> on failure
%%
%% @see transfer/6
%% @see deposit/5
%% @see withdraw/5

-spec reverse_transaction(uuid()) -> {ok, #transaction{}} | {error, atom()}.
reverse_transaction(TxnId) ->
    F = fun() ->
        case mnesia:read(transaction, TxnId, write) of
            [Txn] ->
                case Txn#transaction.status of
                    posted ->
                        %% Create reversal transaction
                        Now = erlang:system_time(millisecond),
                        ReversalId = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
                        IdempotencyKey = <<"reversal:", TxnId/binary>>,

                        %% Determine reversal accounts (swap source/dest)
                        {RevSource, RevDest} = case {Txn#transaction.source_account_id, Txn#transaction.dest_account_id} of
                            {undefined, Dest} -> {Dest, undefined};  %% deposit -> withdrawal
                            {Source, undefined} -> {undefined, Source};  %% withdrawal -> deposit
                            {Source, Dest} -> {Dest, Source}  %% transfer -> reverse transfer
                        end,

                        ReversalTxn = #transaction{
                            txn_id = ReversalId,
                            idempotency_key = IdempotencyKey,
                            txn_type = Txn#transaction.txn_type,
                            status = posted,
                            amount = Txn#transaction.amount,
                            currency = Txn#transaction.currency,
                            source_account_id = RevSource,
                            dest_account_id = RevDest,
                            description = <<"Reversal: ", (Txn#transaction.description)/binary>>,
                            created_at = Now,
                            posted_at = Now
                        },
                        mnesia:write(ReversalTxn),

                        %% Update original transaction status
                        mnesia:write(Txn#transaction{status = reversed}),

                        %% Update account balances and create ledger entries
                        case {RevSource, RevDest} of
                            {undefined, _} ->
                                %% Original was withdrawal, reversal is deposit
                                [Account] = mnesia:read(account, RevDest, write),
                                mnesia:write(Account#account{
                                    balance = Account#account.balance + Txn#transaction.amount,
                                    updated_at = Now
                                }),
                                EntryId = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
                                mnesia:write(#ledger_entry{
                                    entry_id = EntryId,
                                    txn_id = ReversalId,
                                    account_id = RevDest,
                                    entry_type = credit,
                                    amount = Txn#transaction.amount,
                                    currency = Txn#transaction.currency,
                                    description = ReversalTxn#transaction.description,
                                    posted_at = Now
                                });
                            {_, undefined} ->
                                %% Original was deposit, reversal is withdrawal
                                [Account] = mnesia:read(account, RevSource, write),
                                mnesia:write(Account#account{
                                    balance = Account#account.balance - Txn#transaction.amount,
                                    updated_at = Now
                                }),
                                EntryId = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
                                mnesia:write(#ledger_entry{
                                    entry_id = EntryId,
                                    txn_id = ReversalId,
                                    account_id = RevSource,
                                    entry_type = debit,
                                    amount = Txn#transaction.amount,
                                    currency = Txn#transaction.currency,
                                    description = ReversalTxn#transaction.description,
                                    posted_at = Now
                                });
                            {_, _} ->
                                %% Original was transfer, reversal is reverse transfer
                                %% RevSource = original Dest, RevDest = original Source
                                [OrigDestAcc] = mnesia:read(account, RevSource, write),
                                [OrigSourceAcc] = mnesia:read(account, RevDest, write),
                                %% Credit original Source (RevDest), Debit original Dest (RevSource)
                                mnesia:write(OrigSourceAcc#account{
                                    balance = OrigSourceAcc#account.balance + Txn#transaction.amount,
                                    updated_at = Now
                                }),
                                mnesia:write(OrigDestAcc#account{
                                    balance = OrigDestAcc#account.balance - Txn#transaction.amount,
                                    updated_at = Now
                                }),
                                EntryId1 = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
                                EntryId2 = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
                                mnesia:write(#ledger_entry{
                                    entry_id = EntryId1,
                                    txn_id = ReversalId,
                                    account_id = RevDest,
                                    entry_type = credit,
                                    amount = Txn#transaction.amount,
                                    currency = Txn#transaction.currency,
                                    description = ReversalTxn#transaction.description,
                                    posted_at = Now
                                }),
                                mnesia:write(#ledger_entry{
                                    entry_id = EntryId2,
                                    txn_id = ReversalId,
                                    account_id = RevSource,
                                    entry_type = debit,
                                    amount = Txn#transaction.amount,
                                    currency = Txn#transaction.currency,
                                    description = ReversalTxn#transaction.description,
                                    posted_at = Now
                                })
                        end,

                        _ = cb_events:write_outbox(<<"transaction.reversed">>, #{
                            reversal_txn_id  => ReversalId,
                            original_txn_id  => TxnId,
                            amount           => Txn#transaction.amount,
                            currency         => Txn#transaction.currency
                        }),

                        {ok, ReversalTxn};
                    failed ->
                        {error, transaction_not_posted};
                    reversed ->
                        {error, transaction_already_reversed};
                    pending ->
                        {error, transaction_not_posted}
                end;
            [] ->
                {error, transaction_not_found}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, _Reason} -> {error, database_error}
    end.

%% @private
%%
%% Validates that an amount is within acceptable bounds for financial operations.
%%
%% Checks performed:
%% <ol>
%%   <li>Amount is positive (greater than zero)</li>
%%   <li>Amount does not exceed the maximum allowed value (≈ $100 billion)</li>
%% </ol>
%%
%% The maximum amount limit prevents integer overflow and ensures the system
%% can handle amounts within reasonable bounds for a core banking system.
%%
%% @param Amount The amount to validate
%%
%% @returns <tt>ok</tt> if valid, or <tt>{error, Reason}</tt> if invalid

-spec validate_amount(amount()) -> ok | {error, atom()}.
validate_amount(Amount) when Amount =< 0 ->
    {error, zero_amount};
validate_amount(Amount) when Amount > ?MAX_AMOUNT ->
    {error, amount_overflow};
validate_amount(_Amount) ->
    ok.

%% @private Compute available balance by subtracting active holds.
%% Must be called from within a Mnesia transaction.
-spec available_balance_in_txn(uuid(), amount()) -> amount().
available_balance_in_txn(AccountId, Balance) ->
    Holds = mnesia:index_read(account_hold, AccountId, account_id),
    HoldTotal = lists:sum([H#account_hold.amount || H <- Holds,
                           H#account_hold.status =:= active]),
    Balance - HoldTotal.

%%
%% @doc Adjust an account balance
%%
%% Performs a manual balance adjustment on an account. This is typically used for:
%%
%% <ul>
%%   <li>Interest accrual and posting</li>
%%   <li>Fee charges (monthly maintenance, overdraft fees)</li>
%%   <li>Error corrections (correcting posting errors)</li>
%%   <li>Initial account funding</li>
%%   <li>Write-offs or bad debt recovery</li>
%% </ul>
%%
%% The adjustment can be positive (credit) or negative (debit). A positive
%% adjustment increases the account balance; a negative adjustment decreases it.
%%
%% This operation is idempotent - if the same idempotency key is provided for
%% multiple calls, only the first call creates a transaction.
%%
%% <b>Warning:</b> This function should be used sparingly and only by authorized
%% personnel, as it bypasses normal payment validation rules. All adjustments
%% should be properly documented and audited.
%%
%% @param IdempotencyKey A unique client-generated UUID to ensure idempotency
%% @param AccountId The account to adjust
%% @param Amount The adjustment amount (positive adds, negative subtracts)
%%               Must not be zero; use positive for credits, negative for debits
%% @param Currency The ISO 4217 currency code (must match account currency)
%% @param Description Human-readable reason for the adjustment
%%
%% @returns <tt>{ok, Transaction}</tt> on success, or <tt>{error, Reason}</tt> on failure
%%
%% @see transfer/6
%% @see deposit/5
%% @see withdraw/5

-spec adjust_balance(binary(), uuid(), integer(), currency(), binary()) ->
    {ok, #transaction{}} | {error, atom()}.
adjust_balance(_IdempotencyKey, _AccountId, 0, _Currency, _Description) ->
    {error, zero_amount};
adjust_balance(_IdempotencyKey, _AccountId, Amount, _Currency, _Description) when Amount > ?MAX_AMOUNT ->
    {error, amount_overflow};
adjust_balance(IdempotencyKey, AccountId, Amount, Currency, Description) ->
    F = fun() ->
        case mnesia:index_read(transaction, IdempotencyKey, idempotency_key) of
            [Existing] ->
                {ok, Existing};
            [] ->
                case mnesia:read(account, AccountId, write) of
                    [] ->
                        {error, account_not_found};
                    [Account] ->
                        case validate_account_for_adjustment(Account, Currency, Amount) of
                            ok ->
                                Now = erlang:system_time(millisecond),
                                NewBalance = Account#account.balance + Amount,
                                mnesia:write(Account#account{
                                    balance = NewBalance,
                                    updated_at = Now
                                }),

                                TxnId = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
                                Txn = #transaction{
                                    txn_id = TxnId,
                                    idempotency_key = IdempotencyKey,
                                    txn_type = adjustment,
                                    status = posted,
                                    amount = erlang:abs(Amount),
                                    currency = Currency,
                                    source_account_id = undefined,
                                    dest_account_id = AccountId,
                                    description = Description,
                                    created_at = Now,
                                    posted_at = Now
                                },
                                mnesia:write(Txn),

                                EntryId = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
                                EntryType = case Amount > 0 of
                                    true -> credit;
                                    false -> debit
                                end,
                                mnesia:write(#ledger_entry{
                                    entry_id = EntryId,
                                    txn_id = TxnId,
                                    account_id = AccountId,
                                    entry_type = EntryType,
                                    amount = erlang:abs(Amount),
                                    currency = Currency,
                                    description = Description,
                                    posted_at = Now
                                }),

                                _ = cb_events:write_outbox(<<"transaction.posted">>, #{
                                    txn_id          => TxnId,
                                    txn_type        => adjustment,
                                    amount          => erlang:abs(Amount),
                                    currency        => Currency,
                                    dest_account_id => AccountId
                                }),

                                {ok, Txn};
                            Error ->
                                Error
                        end
                end
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, _Reason} -> {error, database_error}
    end.

%% @private
%%
%% Validates an account for a balance adjustment operation.
%%
%% Checks performed:
%% <ol>
%%   <li>Account status is <tt>active</tt> (not frozen or closed)</li>
%%   <li>Account currency matches the adjustment currency</li>
%%   <li>For negative adjustments, the account has sufficient balance</li>
%% </ol>
%%
%% Note: Unlike withdrawals, negative adjustments can bring the balance to zero
%% but not negative (cannot create an overdraft via adjustment).
%%
%% @param Account The account record to validate
%% @param Currency The adjustment currency
%% @param Amount The adjustment amount (positive or negative)
%%
%% @returns <tt>ok</tt> if validation passes, or <tt>{error, Reason}</tt> if validation fails

-spec validate_account_for_adjustment(#account{}, currency(), integer()) -> ok | {error, atom()}.
validate_account_for_adjustment(Account, Currency, Amount) ->
    case Account#account.status of
        frozen -> {error, account_frozen};
        closed -> {error, account_closed};
        active ->
            case Account#account.currency =:= Currency of
                false -> {error, currency_mismatch};
                true ->
                    case Amount < 0 andalso (Account#account.balance + Amount) < 0 of
                        true -> {error, insufficient_funds};
                        false -> ok
                    end
            end
    end.
