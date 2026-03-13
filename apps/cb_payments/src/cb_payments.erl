-module(cb_payments).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([
    transfer/6,
    deposit/5,
    withdraw/5,
    get_transaction/1,
    list_transactions_for_account/3,
    reverse_transaction/1
]).

%% Maximum allowed amount (≈ $100 billion)
-define(MAX_AMOUNT, 9_999_999_999_99).

%% @doc Transfer funds between two accounts.
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

%% @private Internal transfer implementation.
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
                                %% 3. Validate
                                case validate_accounts_for_transfer(Source, Dest, Currency, Amount) of
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

%% @private Validate accounts for transfer.
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

%% @doc Deposit funds into an account.
-spec deposit(binary(), uuid(), amount(), currency(), binary()) ->
    {ok, #transaction{}} | {error, atom()}.
deposit(IdempotencyKey, DestId, Amount, Currency, Description) ->
    case validate_amount(Amount) of
        ok ->
            F = fun() ->
                %% Idempotency check
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

%% @private Validate account for deposit.
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

%% @doc Withdraw funds from an account.
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
                                case validate_account_for_withdrawal(Source, Currency, Amount) of
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

%% @private Validate account for withdrawal.
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
                        true -> ok;
                        false -> {error, insufficient_funds}
                    end
            end
    end.

%% @doc Get a transaction by ID.
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

%% @doc List transactions for an account with pagination.
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

%% @doc Reverse a posted transaction.
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

%% @private Validate amount.
-spec validate_amount(amount()) -> ok | {error, atom()}.
validate_amount(Amount) when Amount =< 0 ->
    {error, zero_amount};
validate_amount(Amount) when Amount > ?MAX_AMOUNT ->
    {error, amount_overflow};
validate_amount(_Amount) ->
    ok.
