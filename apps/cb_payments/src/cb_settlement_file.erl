%% @doc Settlement File Generation
%%
%% Generates settlement files (CSV format) for batch payment processing.
%% Files contain all pending/completed payments for a given date and currency,
%% formatted for submission to external settlement systems or banks.
%%
-module(cb_settlement_file).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([
    generate_settlement_file/2
]).

-define(ISO8601_DATE_FORMAT, "~4.0B-~2.0B-~2.0B").

-type file_content() :: binary().
-type file_name() :: binary().

%% @doc Generate a settlement file for the given date and currency.
%%
%% Returns `{ok, FileContent, FileName}' where FileContent is the CSV binary
%% and FileName is a suggested filename including the date.
%%
%% The CSV format follows standard bank settlement conventions:
%% TransactionId,Amount,Currency,SourceAccount,DestAccount,BeneficiaryName,Status
%%
-spec generate_settlement_file(Date :: calendar:date(), Currency :: currency()) ->
    {ok, file_content(), file_name()} | {error, atom()}.
generate_settlement_file({Y, M, D} = Date, Currency) when is_integer(Y), is_integer(M), is_integer(D) ->
    FileName = iolist_to_binary([
        <<"settlement_">>,
        io_lib:format(?ISO8601_DATE_FORMAT, [Y, M, D]),
        <<"_">>, atom_to_binary(Currency, utf8),
        <<".csv">>
    ]),

    %% Read all transactions matching date and currency
    F = fun() ->
        MatchSpec = [{#transaction{
            currency = Currency,
            status = '$1',
            created_at = '$2',
            _ = '_'
        }, [
            {'>=', '$2', to_epoch_start(Date)},
            {'<', '$2', to_epoch_end(Date)},
            {'orelse', {'=:=', '$1', pending}, {'=:=', '$1', completed}}
        ], ['$_']}],
        mnesia:select(transaction, MatchSpec)
    end,

    case mnesia:transaction(F) of
        {atomic, Transactions} ->
            Lines = [format_transaction(T) || T <- Transactions],
            Header = <<"TransactionId,Amount,Currency,SourceAccount,DestAccount,BeneficiaryName,Status\r\n">>,
            FileContent = iolist_to_binary([Header | Lines]),
            {ok, FileContent, FileName};
        {aborted, Reason} ->
            {error, Reason}
    end.

%% @private Convert calendar:date() to epoch milliseconds at start of day (00:00:00 UTC)
-spec to_epoch_start(calendar:date()) -> integer().
to_epoch_start({Y, M, D}) ->
    Secs = calendar:datetime_to_gregorian_seconds({{Y, M, D}, {0, 0, 0}}),
    (Secs - 62167248000) * 1000.  %% Offset from epoch to Gregorian

%% @private Convert calendar:date() to epoch milliseconds at end of day (23:59:59.999 UTC)
-spec to_epoch_end(calendar:date()) -> integer().
to_epoch_end({Y, M, D}) ->
    Secs = calendar:datetime_to_gregorian_seconds({{Y, M, D}, {23, 59, 59}}),
    (Secs - 62167248000) * 1000 + 999.  %% Offset from epoch to Gregorian

%% @private Format a transaction into a CSV line
-spec format_transaction(#transaction{}) -> binary().
format_transaction(Txn) ->
    #transaction{
        txn_id = TxnId,
        amount = Amount,
        currency = Currency,
        source_account_id = SrcAcct,
        dest_account_id = DstAcct,
        status = Status
    } = Txn,
    %% In a real system we'd look up beneficiary name; for now use account IDs
    SrcStr = maybe_id(SrcAcct),
    DstStr = maybe_id(DstAcct),
    iolist_to_binary([
        TxnId, $,, integer_to_list(Amount), $,, atom_to_binary(Currency, utf8), $,,
        SrcStr, $,, DstStr, $,, <<"N/A">>, $,, atom_to_binary(Status, utf8), <<"\r\n">>
    ]).

-spec maybe_id(uuid() | undefined) -> binary().
maybe_id(undefined) -> <<"">>;
maybe_id(Id) -> Id.