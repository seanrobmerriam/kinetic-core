-module(cb_account_entries_handler).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    AccountId = cowboy_req:binding(account_id, Req),
    Page = query_int(Req, <<"page">>, 1),
    PageSize = query_int(Req, <<"page_size">>, 20),
    handle(Method, AccountId, Page, PageSize, Req, State).

handle(<<"GET">>, AccountId, Page, PageSize, Req, State) ->
    case cb_ledger:get_entries_for_account(AccountId, Page, PageSize) of
        {ok, Result} ->
            Resp = #{
                items => [entry_to_json(E) || E <- maps:get(items, Result)],
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

handle(<<"OPTIONS">>, _AccountId, _Page, _PageSize, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};

handle(_, _AccountId, _Page, _PageSize, Req, State) ->
    {_Code405, _Hdrs405, _Body405} = cb_http_errors:to_response_with_metrics(method_not_allowed),
    Req2 = cowboy_req:reply(_Code405, _Hdrs405, _Body405, Req),
    {ok, Req2, State}.

entry_to_json(Entry) ->
    #{
        entry_id => Entry#ledger_entry.entry_id,
        txn_id => Entry#ledger_entry.txn_id,
        account_id => Entry#ledger_entry.account_id,
        entry_type => Entry#ledger_entry.entry_type,
        amount => Entry#ledger_entry.amount,
        currency => Entry#ledger_entry.currency,
        description => Entry#ledger_entry.description,
        posted_at => Entry#ledger_entry.posted_at
    }.

query_int(Req, Key, Default) ->
    Qs = cowboy_req:parse_qs(Req),
    case proplists:get_value(Key, Qs) of
        undefined -> Default;
        Value -> binary_to_integer(Value)
    end.
