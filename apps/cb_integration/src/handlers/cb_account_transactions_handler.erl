-module(cb_account_transactions_handler).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    AccountId = cowboy_req:binding(account_id, Req),
    handle(Method, AccountId, Req, State).

handle(<<"GET">>, AccountId, Req, State) ->
    Qs = cowboy_req:parse_qs(Req),
    PageBin = proplists:get_value(<<"page">>, Qs, <<"1">>),
    PageSizeBin = proplists:get_value(<<"page_size">>, Qs, <<"20">>),
    Page = safe_binary_to_integer(PageBin, 1),
    PageSize = safe_binary_to_integer(PageSizeBin, 20),
    ValidPage = max(1, Page),
    ValidPageSize = max(1, min(100, PageSize)),
    case cb_payments:list_transactions_for_account(AccountId, ValidPage, ValidPageSize) of
        {ok, Result} ->
            Items = [transaction_to_json(Txn) || Txn <- maps:get(items, Result)],
            Resp = #{
                items => Items,
                total => maps:get(total, Result),
                page => maps:get(page, Result),
                page_size => maps:get(page_size, Result)
            },
            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
            Req2 = cowboy_req:reply(200, Headers, jsone:encode(Resp), Req),
            {ok, Req2, State};
        {error, Reason} ->
            {Status, ErrorAtom, Message} = cb_http_errors:to_response(Reason),
            Resp = #{error => ErrorAtom, message => Message},
            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
            Req2 = cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req),
            {ok, Req2, State}
    end;

handle(<<"OPTIONS">>, _AccountId, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};

handle(_, _AccountId, Req, State) ->
    {_Code405, _Hdrs405, _Body405} = cb_http_errors:to_response_with_metrics(method_not_allowed),
    Req2 = cowboy_req:reply(_Code405, _Hdrs405, _Body405, Req),
    {ok, Req2, State}.

safe_binary_to_integer(Binary, Default) ->
    try binary_to_integer(Binary) of
        Int when Int > 0 -> Int;
        _ -> Default
    catch
        _:_ -> Default
    end.

transaction_to_json(Txn) ->
    #{
        txn_id => Txn#transaction.txn_id,
        txn_type => Txn#transaction.txn_type,
        status => Txn#transaction.status,
        amount => Txn#transaction.amount,
        currency => Txn#transaction.currency,
        source_account_id => Txn#transaction.source_account_id,
        dest_account_id => Txn#transaction.dest_account_id,
        description => Txn#transaction.description,
        created_at => Txn#transaction.created_at,
        posted_at => Txn#transaction.posted_at
    }.
