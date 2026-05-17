-module(cb_permissions_handler).

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    case Method of
        <<"GET">> ->
            case cb_rbac:list_permissions() of
                {ok, Permissions} ->
                    json_reply(200, #{items => group_by_resource(Permissions), total => length(Permissions)}, Req, State);
                {error, Reason} ->
                    error_reply(Reason, Req, State)
            end;
        <<"OPTIONS">> ->
            Req2 = cb_cors:reply_preflight(Req),
            {ok, Req2, State};
        _ ->
            {_Code405, _Hdrs405, _Body405} = cb_http_errors:to_response_with_metrics(method_not_allowed),
            Req2 = cowboy_req:reply(_Code405, _Hdrs405, _Body405, Req),
            {ok, Req2, State}
    end.

group_by_resource(Permissions) ->
    Sorted = lists:sort(
        fun(A, B) ->
            {maps:get(resource, A), maps:get(permission_key, A)} =<
            {maps:get(resource, B), maps:get(permission_key, B)}
        end,
        Permissions
    ),
    maps:fold(
        fun(Resource, Items, Acc) ->
            Acc ++ [#{resource => Resource, permissions => Items}]
        end,
        [],
        lists:foldl(
            fun(Item, Acc) ->
                Resource = maps:get(resource, Item),
                Existing = maps:get(Resource, Acc, []),
                Acc#{Resource => Existing ++ [Item]}
            end,
            #{},
            Sorted
        )
    ).

error_reply(Reason, Req, State) ->
    {Status, ErrorAtom, Message} = cb_http_errors:to_response(Reason),
    Resp = #{error => ErrorAtom, message => Message},
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    Req2 = cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req),
    {ok, Req2, State}.

json_reply(Status, Body, Req, State) ->
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    Req2 = cowboy_req:reply(Status, Headers, jsone:encode(Body), Req),
    {ok, Req2, State}.
