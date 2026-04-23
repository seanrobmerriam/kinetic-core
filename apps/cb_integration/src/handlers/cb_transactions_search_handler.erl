%% @doc Handler for GET /api/v1/transactions
%%
%% Searches and filters transactions across all accounts.  All parameters
%% are optional; omitting a parameter removes that filter.
%%
%% Query parameters:
%%   from_ts      – unix ms lower bound for created_at (inclusive)
%%   to_ts        – unix ms upper bound for created_at (inclusive)
%%   type         – transaction type atom: deposit | withdrawal | transfer | adjustment | reversal
%%   status       – status atom: posted | pending | failed | reversed
%%   min_amount   – minimum amount in minor units
%%   max_amount   – maximum amount in minor units
%%   account_id   – match source_account_id or dest_account_id
%%   page         – 1-based page number (default 1)
%%   page_size    – results per page (default 25, max 100)
-module(cb_transactions_search_handler).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    handle(Method, Req, State).

handle(<<"GET">>, Req, State) ->
    Filters = parse_filters(cowboy_req:parse_qs(Req)),
    case cb_payments:query_transactions(Filters) of
        {ok, #{items := Txns, total := Total, page := Page, page_size := PageSize}} ->
            Resp = #{
                items     => [txn_to_json(T) || T <- Txns],
                total     => Total,
                page      => Page,
                page_size => PageSize
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

handle(<<"OPTIONS">>, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};

handle(_, Req, State) ->
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    Req2 = cowboy_req:reply(405, Headers, <<"{\"error\": \"method_not_allowed\"}">>, Req),
    {ok, Req2, State}.

%% @private Build a filter map from parsed query-string pairs.
-spec parse_filters([{binary(), binary()}]) -> map().
parse_filters(QS) ->
    lists:foldl(fun({Key, Val}, Acc) ->
        case Key of
            <<"from_ts">>   -> maybe_put(from_ts,    safe_integer(Val), Acc);
            <<"to_ts">>     -> maybe_put(to_ts,      safe_integer(Val), Acc);
            <<"type">>      -> maybe_put(txn_type,   safe_atom(Val),    Acc);
            <<"status">>    -> maybe_put(status,     safe_atom(Val),    Acc);
            <<"min_amount">>-> maybe_put(min_amount, safe_integer(Val), Acc);
            <<"max_amount">>-> maybe_put(max_amount, safe_integer(Val), Acc);
            <<"account_id">>-> maps:put(account_id,  Val,               Acc);
            <<"page">>      -> maybe_put(page,       safe_pos_integer(Val, 1),   Acc);
            <<"page_size">> -> maybe_put(page_size,  safe_bounded_integer(Val, 1, 100, 25), Acc);
            _               -> Acc
        end
    end, #{}, QS).

maybe_put(_Key, undefined, Acc) -> Acc;
maybe_put(Key,  Value,     Acc) -> maps:put(Key, Value, Acc).

safe_integer(Bin) ->
    try binary_to_integer(Bin) catch _:_ -> undefined end.

safe_pos_integer(Bin, Default) ->
    case safe_integer(Bin) of
        V when is_integer(V), V > 0 -> V;
        _                           -> Default
    end.

safe_bounded_integer(Bin, Min, Max, Default) ->
    case safe_integer(Bin) of
        V when is_integer(V), V >= Min, V =< Max -> V;
        _                                        -> Default
    end.

safe_atom(Bin) ->
    try binary_to_existing_atom(Bin, utf8) catch _:_ -> undefined end.

txn_to_json(T) ->
    #{
        txn_id            => T#transaction.txn_id,
        idempotency_key   => T#transaction.idempotency_key,
        txn_type          => T#transaction.txn_type,
        status            => T#transaction.status,
        amount            => T#transaction.amount,
        currency          => T#transaction.currency,
        source_account_id => T#transaction.source_account_id,
        dest_account_id   => T#transaction.dest_account_id,
        description       => T#transaction.description,
        channel           => T#transaction.channel,
        created_at        => T#transaction.created_at,
        posted_at         => T#transaction.posted_at
    }.
