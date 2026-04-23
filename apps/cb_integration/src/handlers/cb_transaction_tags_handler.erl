%% @doc Handler for GET|PUT /api/v1/transactions/:txn_id/tags
%%
%% GET  – returns the current category and tag list for a transaction.
%%        Returns 404 if no tags have been set yet.
%%
%% PUT  – upserts the category and tag list for a transaction.
%%        The request body must be a JSON object:
%%          { "category": "payroll", "tags": ["monthly", "q1"] }
%%        Both fields are optional; omitting a field leaves it unchanged on
%%        update, or sets it to undefined / [] on first write.
-module(cb_transaction_tags_handler).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    TxnId  = cowboy_req:binding(txn_id, Req),
    handle(Method, TxnId, Req, State).

-dialyzer({nowarn_function, handle/4}).
handle(<<"GET">>, TxnId, Req, State) ->
    case get_tags(TxnId) of
        {ok, TagRecord} ->
            Resp = tags_to_json(TagRecord),
            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
            Req2 = cowboy_req:reply(200, Headers, jsone:encode(Resp), Req),
            {ok, Req2, State};
        {error, not_found} ->
            {Status, ErrorAtom, Message} = cb_http_errors:to_response(transaction_tag_not_found),
            Resp = #{error => ErrorAtom, message => Message},
            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
            Req2 = cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req),
            {ok, Req2, State}
    end;

handle(<<"PUT">>, TxnId, Req, State) ->
    case cowboy_req:read_body(Req) of
        {ok, Body, Req2} ->
            case jsone:decode(Body, [{object_format, map}, {keys, attempt_atom}]) of
                Parsed when is_map(Parsed) ->
                    Category = maps:get(category, Parsed, undefined),
                    Tags     = maps:get(tags,     Parsed, []),
                    case upsert_tags(TxnId, Category, Tags) of
                        {ok, TagRecord} ->
                            Resp = tags_to_json(TagRecord),
                            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
                            Req3 = cowboy_req:reply(200, Headers, jsone:encode(Resp), Req2),
                            {ok, Req3, State};
                        {error, Reason} ->
                            {Status, ErrorAtom, Message} = cb_http_errors:to_response(Reason),
                            Resp = #{error => ErrorAtom, message => Message},
                            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
                            Req3 = cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req2),
                            {ok, Req3, State}
                    end;
                _ ->
                    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
                    Req3 = cowboy_req:reply(400, Headers, <<"{\"error\": \"invalid_request_body\"}">>, Req2),
                    {ok, Req3, State}
            end;
        {more, _Body, Req2} ->
            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
            Req3 = cowboy_req:reply(413, Headers, <<"{\"error\": \"request_entity_too_large\"}">>, Req2),
            {ok, Req3, State}
    end;

handle(<<"OPTIONS">>, _TxnId, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};

handle(_, _TxnId, Req, State) ->
    {_Code405, _Hdrs405, _Body405} = cb_http_errors:to_response_with_metrics(method_not_allowed),
    Req2 = cowboy_req:reply(_Code405, _Hdrs405, _Body405, Req),
    {ok, Req2, State}.

%% @private Read tags for a transaction from Mnesia.
-dialyzer({nowarn_function, get_tags/1}).
-spec get_tags(binary()) -> {ok, #transaction_tag{}} | {error, not_found}.
get_tags(TxnId) ->
    case mnesia:dirty_index_read(transaction_tag, TxnId, txn_id) of
        [Tag | _] -> {ok, Tag};
        []        -> {error, not_found}
    end.

%% @private Upsert tags for a transaction.
-dialyzer({nowarn_function, upsert_tags/3}).
-spec upsert_tags(binary(), binary() | undefined, [binary()]) ->
    {ok, #transaction_tag{}} | {error, atom()}.
upsert_tags(TxnId, Category, Tags) ->
    Now = erlang:system_time(millisecond),
    F = fun() ->
        TagRecord = case mnesia:index_read(transaction_tag, TxnId, txn_id) of
            [Existing] ->
                Existing#transaction_tag{
                    category   = Category,
                    tags       = Tags,
                    updated_at = Now
                };
            [] ->
                TagId = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
                #transaction_tag{
                    tag_id     = TagId,
                    txn_id     = TxnId,
                    category   = Category,
                    tags       = Tags,
                    created_at = Now,
                    updated_at = Now
                }
        end,
        mnesia:write(TagRecord),
        {ok, TagRecord}
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, _}     -> {error, database_error}
    end.

tags_to_json(T) ->
    #{
        tag_id     => T#transaction_tag.tag_id,
        txn_id     => T#transaction_tag.txn_id,
        category   => T#transaction_tag.category,
        tags       => T#transaction_tag.tags,
        created_at => T#transaction_tag.created_at,
        updated_at => T#transaction_tag.updated_at
    }.
