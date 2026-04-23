%% @doc HTTP handler for event schema registry (TASK-058).
%%
%% Routes:
%%   GET  /api/v1/events/schemas                     — list all event types
%%   GET  /api/v1/events/schemas/:event_type         — list versions for event_type
%%   GET  /api/v1/events/schemas/:event_type/:version — get specific version
%%   POST /api/v1/events/schemas                     — register a new schema version
-module(cb_event_schema_handler).
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

init(Req, State) ->
    Method    = cowboy_req:method(Req),
    EventType = cowboy_req:binding(event_type, Req),
    Version   = cowboy_req:binding(version, Req),
    handle(Method, EventType, Version, Req, State).

handle(<<"GET">>, undefined, undefined, Req, State) ->
    AllSchemas = mnesia:dirty_select(event_schema_version, [{'_', [], ['$_']}]),
    Types = lists:usort([S#event_schema_version.event_type || S <- AllSchemas]),
    Req2 = cowboy_req:reply(200, headers(),
               jsone:encode(#{event_types => Types}), Req),
    {ok, Req2, State};

handle(<<"GET">>, EventType, undefined, Req, State) ->
    Versions = cb_event_schema_registry:list_versions(EventType),
    Req2 = cowboy_req:reply(200, headers(),
               jsone:encode(#{versions => [schema_to_map(S) || S <- Versions]}), Req),
    {ok, Req2, State};

handle(<<"GET">>, EventType, VersionBin, Req, State) ->
    Version = binary_to_integer(VersionBin),
    case cb_event_schema_registry:get_schema(EventType, Version) of
        {ok, Schema} ->
            Req2 = cowboy_req:reply(200, headers(),
                       jsone:encode(schema_to_map(Schema)), Req),
            {ok, Req2, State};
        {error, not_found} ->
            error_reply(404, <<"Schema version not found">>, Req, State)
    end;

handle(<<"POST">>, undefined, undefined, Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(Body, [{keys, atom}]) of
        {ok, #{event_type := EventType, version := Version,
               schema := Schema} = P, _} ->
            Compat = case maps:get(compatibility, P, <<"backward">>) of
                <<"backward">> -> backward;
                <<"forward">>  -> forward;
                <<"full">>     -> full;
                <<"none">>     -> none;
                _              -> backward
            end,
            Params = #{event_type    => EventType,
                       version       => Version,
                       schema        => Schema,
                       compatibility => Compat},
            case cb_event_schema_registry:register(Params) of
                {ok, SchemaId} ->
                    Req3 = cowboy_req:reply(201, headers(),
                               jsone:encode(#{schema_id => SchemaId}), Req2),
                    {ok, Req3, State};
                {error, Reason} ->
                    error_reply(400, Reason, Req2, State)
            end;
        _ ->
            error_reply(400, <<"Missing required fields: event_type, version, schema">>,
                        Req2, State)
    end;

handle(_Method, _EventType, _Version, Req, State) ->
    error_reply(405, <<"Method not allowed">>, Req, State).

%%--------------------------------------------------------------------
%% Helpers
%%--------------------------------------------------------------------

schema_to_map(S) ->
    #{schema_id     => S#event_schema_version.schema_id,
      event_type    => S#event_schema_version.event_type,
      version       => S#event_schema_version.version,
      schema        => S#event_schema_version.schema,
      compatibility => S#event_schema_version.compatibility,
      created_at    => S#event_schema_version.created_at}.

headers() ->
    #{<<"content-type">> => <<"application/json">>}.

error_reply(Code, Reason, Req, State) when is_atom(Reason) ->
    error_reply(Code, atom_to_binary(Reason, utf8), Req, State);
error_reply(Code, Reason, Req, State) ->
    Req2 = cowboy_req:reply(Code, headers(),
               jsone:encode(#{error => Reason}), Req),
    {ok, Req2, State}.
