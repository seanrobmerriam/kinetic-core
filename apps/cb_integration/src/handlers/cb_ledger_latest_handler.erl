-module(cb_ledger_latest_handler).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    Limit = query_int(Req, <<"limit">>, 20),
    handle(Method, Limit, Req, State).

handle(<<"GET">>, Limit, Req, State) ->
    case cb_ledger:get_latest_entries(Limit) of
        {ok, Entries} ->
            Resp = #{items => [entry_to_json(E) || E <- Entries]},
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

handle(<<"OPTIONS">>, _Limit, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};

handle(_, _Limit, Req, State) ->
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    Req2 = cowboy_req:reply(405, Headers, <<"{\"error\": \"method_not_allowed\"}">>, Req),
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
        Value ->
            try binary_to_integer(Value)
            catch _:_ -> Default
            end
    end.
