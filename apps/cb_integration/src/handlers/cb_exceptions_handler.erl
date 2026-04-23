%% @doc Exception Queue HTTP Handler
%%
%% Handles the exception queue management API:
%% - GET /api/v1/exceptions - list pending exception items
%% - GET /api/v1/exceptions/:item_id - get a single exception item
%% - POST /api/v1/exceptions/:item_id/resolve - resolve an exception item
-module(cb_exceptions_handler).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    handle(Method, Req, State).

handle(<<"GET">>, Req, State) ->
    case cowboy_req:binding(item_id, Req) of
        undefined ->
            list_pending(Req, State);
        ItemId ->
            get_item(ItemId, Req, State)
    end;

handle(<<"POST">>, Req, State) ->
    case cowboy_req:binding(item_id, Req) of
        undefined ->
            not_found(Req, State);
        ItemId ->
            Path = cowboy_req:path(Req),
            Parts = binary:split(Path, <<"/">>, [global]),
            case Parts of
                [_, <<"api">>, <<"v1">>, <<"exceptions">>, ItemId, <<"resolve">>] ->
                    resolve_item(ItemId, Req, State);
                _ ->
                    not_found(Req, State)
            end
    end;

handle(<<"OPTIONS">>, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};

handle(_, Req, State) ->
    {_Code405, _Hdrs405, _Body405} = cb_http_errors:to_response_with_metrics(method_not_allowed),
    Req2 = cowboy_req:reply(_Code405, _Hdrs405, _Body405, Req),
    {ok, Req2, State}.

list_pending(Req, State) ->
    Items = cb_exception_queue:list_pending(),
    Resp = [item_to_json(I) || I <- Items],
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    Req2 = cowboy_req:reply(200, Headers, jsone:encode(Resp), Req),
    {ok, Req2, State}.

get_item(ItemId, Req, State) ->
    case cb_exception_queue:get_item(ItemId) of
        {ok, Item} ->
            Resp = item_to_json(Item),
            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
            Req2 = cowboy_req:reply(200, Headers, jsone:encode(Resp), Req),
            {ok, Req2, State};
        {error, Reason} ->
            {Status, ErrorAtom, Message} = cb_http_errors:to_response(Reason),
            Resp = #{error => ErrorAtom, message => Message},
            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
            Req2 = cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req),
            {ok, Req2, State}
    end.

resolve_item(ItemId, Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(Body) of
        {ok, #{
            <<"resolution">> := ResolutionBin,
            <<"notes">>      := Notes
        }, _} ->
            Resolution = binary_to_existing_atom(ResolutionBin, utf8),
            case cb_exception_queue:resolve(ItemId, Resolution, Notes) of
                {ok, Item} ->
                    Resp = item_to_json(Item),
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
            {Status, ErrorAtom, Message} = cb_http_errors:to_response(missing_required_field),
            Resp = #{error => ErrorAtom, message => Message},
            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
            Req3 = cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req2),
            {ok, Req3, State}
    end.

not_found(Req, State) ->
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    Req2 = cowboy_req:reply(404, Headers, <<"{\"error\": \"not_found\"}">>, Req),
    {ok, Req2, State}.

item_to_json(Item) ->
    #{
        item_id          => Item#exception_item.item_id,
        payment_id       => Item#exception_item.payment_id,
        reason           => Item#exception_item.reason,
        status           => Item#exception_item.status,
        resolution       => Item#exception_item.resolution,
        resolved_by      => Item#exception_item.resolved_by,
        resolution_notes => Item#exception_item.resolution_notes,
        created_at       => Item#exception_item.created_at,
        updated_at       => Item#exception_item.updated_at
    }.
