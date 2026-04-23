%% @doc HTTP handler for connector version history and rollback.
%%
%% Routes:
%%   POST /api/v1/marketplace/connectors/:id/snapshot     — take version snapshot
%%   GET  /api/v1/marketplace/connectors/:id/versions     — list versions
%%   GET  /api/v1/marketplace/connectors/:id/versions/:vid — get version
%%   POST /api/v1/marketplace/connectors/:id/versions/:vid/rollback — rollback
-module(cb_connector_versions_handler).
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

init(Req, State) ->
    Method    = cowboy_req:method(Req),
    ConnId    = cowboy_req:binding(connector_id, Req),
    VersionId = cowboy_req:binding(version_id, Req),
    Action    = cowboy_req:binding(action, Req),
    handle(Method, ConnId, VersionId, Action, Req, State).

%% Snapshot: POST /connectors/:id/snapshot
handle(<<"POST">>, ConnId, undefined, <<"snapshot">>, Req, State) ->
    case cb_connector_versions:snapshot_version(ConnId) of
        {ok, V} ->
            Req2 = cowboy_req:reply(201, headers(), jsone:encode(version_to_map(V)), Req),
            {ok, Req2, State};
        {error, not_found} ->
            error_reply(404, <<"not_found">>, Req, State);
        {error, Reason} ->
            error_reply(500, Reason, Req, State)
    end;

%% List versions: GET /connectors/:id/versions
handle(<<"GET">>, ConnId, undefined, undefined, Req, State) ->
    Versions = cb_connector_versions:list_versions(ConnId),
    Req2 = cowboy_req:reply(200, headers(),
               jsone:encode(#{versions => [version_to_map(V) || V <- Versions]}), Req),
    {ok, Req2, State};

%% Get version: GET /connectors/:id/versions/:vid
handle(<<"GET">>, _ConnId, VersionId, undefined, Req, State) ->
    case cb_connector_versions:get_version(VersionId) of
        {ok, V} ->
            Req2 = cowboy_req:reply(200, headers(), jsone:encode(version_to_map(V)), Req),
            {ok, Req2, State};
        {error, not_found} ->
            error_reply(404, <<"not_found">>, Req, State)
    end;

%% Rollback: POST /connectors/:id/versions/:vid/rollback
handle(<<"POST">>, ConnId, VersionId, <<"rollback">>, Req, State) ->
    case cb_connector_versions:rollback(ConnId, VersionId) of
        {ok, Connector} ->
            Req2 = cowboy_req:reply(200, headers(),
                       jsone:encode(connector_to_map(Connector)), Req),
            {ok, Req2, State};
        {error, connector_not_found} ->
            error_reply(404, <<"connector_not_found">>, Req, State);
        {error, version_not_found} ->
            error_reply(404, <<"version_not_found">>, Req, State);
        {error, version_connector_mismatch} ->
            error_reply(422, <<"version does not belong to this connector">>, Req, State);
        {error, Reason} ->
            error_reply(500, Reason, Req, State)
    end;

handle(_, _, _, _, Req, State) ->
    Req2 = cowboy_req:reply(405, headers(), <<>>, Req),
    {ok, Req2, State}.

version_to_map(#connector_version{
    version_id      = Id,
    connector_id    = ConnId,
    version         = Version,
    module          = Module,
    capabilities    = Caps,
    config_snapshot = Snapshot,
    is_active       = Active,
    created_at      = CreAt,
    rolled_back_at  = RolledAt
}) ->
    #{
        version_id      => Id,
        connector_id    => ConnId,
        version         => Version,
        module          => atom_to_binary(Module, utf8),
        capabilities    => Caps,
        config_snapshot => Snapshot,
        is_active       => Active,
        created_at      => CreAt,
        rolled_back_at  => RolledAt
    }.

connector_to_map(#connector_definition{
    connector_id  = Id, name = Name, type = Type, module = Module,
    status = Status, version = Version, capabilities = Caps,
    config_schema = Schema, description = Desc,
    created_at = CreAt, updated_at = UpdAt
}) ->
    #{
        connector_id  => Id,
        name          => Name,
        type          => Type,
        module        => atom_to_binary(Module, utf8),
        status        => Status,
        version       => Version,
        capabilities  => Caps,
        config_schema => Schema,
        description   => Desc,
        created_at    => CreAt,
        updated_at    => UpdAt
    }.

error_reply(Code, Reason, Req, State) ->
    Msg = if is_binary(Reason) -> Reason; true -> iolist_to_binary(io_lib:format("~p", [Reason])) end,
    Req2 = cowboy_req:reply(Code, headers(), jsone:encode(#{error => Msg}), Req),
    {ok, Req2, State}.

headers() ->
    maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()).
