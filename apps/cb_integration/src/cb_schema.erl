-module(cb_schema).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([create_tables/0]).

%% @doc Create all Mnesia tables if they don't exist.
-spec create_tables() -> ok.
create_tables() ->
    Tables = [party, account, transaction, ledger_entry],
    lists:foreach(fun create_if_not_exists/1, Tables),
    ok.

%% @private Create a single table if it doesn't exist.
-spec create_if_not_exists(party | account | transaction | ledger_entry) -> ok.
create_if_not_exists(TableName) ->
    case mnesia:create_table(TableName, table_spec(TableName)) of
        {atomic, ok} ->
            ok;
        {aborted, {already_exists, _Table}} ->
            ok;
        {aborted, Reason} ->
            error({schema_error, TableName, Reason})
    end.

%% @private Table specifications from docs/data-schema.md.
-spec table_spec(party | account | transaction | ledger_entry) ->
    [{'attributes',[atom(),...]} |
     {'index',['account_id' | 'dest_account_id' | 'email' | 'idempotency_key' |
              'party_id' | 'source_account_id' | 'status' | 'txn_id',...]} |
     {'ram_copies',[atom(),...]},...].
table_spec(party) ->
    [
        {ram_copies, [node()]},
        {attributes, record_info(fields, party)},
        {index, [email, status]}
    ];
table_spec(account) ->
    [
        {ram_copies, [node()]},
        {attributes, record_info(fields, account)},
        {index, [party_id, status]}
    ];
table_spec(transaction) ->
    [
        {ram_copies, [node()]},
        {attributes, record_info(fields, transaction)},
        {index, [idempotency_key, source_account_id, dest_account_id, status]}
    ];
table_spec(ledger_entry) ->
    [
        {ram_copies, [node()]},
        {attributes, record_info(fields, ledger_entry)},
        {index, [txn_id, account_id]}
    ].
