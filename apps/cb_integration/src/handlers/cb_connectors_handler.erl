%% @doc HTTP handler for marketplace connector management.
%%
%% Routes:
%%   GET    /api/v1/marketplace/connectors        — list all connectors
%%   POST   /api/v1/marketplace/connectors        — register a connector
%%   GET    /api/v1/marketplace/connectors/:id    — get connector by ID
%%   PUT    /api/v1/marketplace/connectors/:id    — update connector metadata
%%   POST   /api/v1/marketplace/connectors/:id/enable    — enable connector
%%   POST   /api/v1/marketplace/connectors/:id/disable   — disable connector
%%   POST   /api/v1/marketplace/connectors/:id/deprecate — deprecate connector
-module(cb_connectors_handler).
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

init(Req, State) ->
    Method     = cowboy_req:method(Req),
    ConnId     = cowboy_req:binding(connector_id, Req),
    Action     = cowboy_req:binding(action, Req),
    handle(Method, ConnId, Action, Req, State).

%% List all
handle(<<"GET">>, undefined, undefined, Req, State) ->
    Connectors = cb_connectors:list(),
    Req2 = cowboy_req:reply(200, headers(),
               jsone:encode(#{connectors => [connector_to_map(C) || C <- Connectors]}), Req),
    {ok, Req2, State};

%% Register
handle(<<"POST">>, undefined, undefined, Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(Body, [{keys, atom}]) of
        {ok, #{name := Name, type := TypeBin, module := ModuleBin} = P, _} ->
            Type   = binary_to_existing_atom(TypeBin, utf8),
            Module = binary_to_atom(ModuleBin, utf8),
            Attrs  = #{
                name          => Name,
                type          => Type,
                module        => Module,
                version       => maps:get(version, P, <<"1.0.0">>),
                capabilities  => maps:get(capabilities, P, []),
                config_schema => maps:get(config_schema, P, #{}),
                description   => maps:get(description, P, <<>>)
            },
            case cb_connectors:register(Attrs) of
                {ok, Connector} ->
                    Req3 = cowboy_req:reply(201, headers(),
                               jsone:encode(connector_to_map(Connector)), Req2),
                    {ok, Req3, State};
                {error, Reason} ->
                    error_reply(500, Reason, Req2, State)
            end;
        _ ->
            error_reply(400, <<"Missing required fields: name, type, module">>, Req2, State)
    end;

%% Get by ID
handle(<<"GET">>, ConnId, undefined, Req, State) ->
    case cb_connectors:get(ConnId) of
        {ok, C} ->
            Req2 = cowboy_req:reply(200, headers(), jsone:encode(connector_to_map(C)), Req),
            {ok, Req2, State};
        {error, not_found} ->
            error_reply(404, <<"not_found">>, Req, State)
    end;

%% Update by ID
handle(<<"PUT">>, ConnId, undefined, Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(Body, [{keys, atom}]) of
        {ok, Updates, _} ->
            case cb_connectors:update(ConnId, Updates) of
                {ok, C} ->
                    Req3 = cowboy_req:reply(200, headers(),
                               jsone:encode(connector_to_map(C)), Req2),
                    {ok, Req3, State};
                {error, not_found} ->
                    error_reply(404, <<"not_found">>, Req2, State);
                {error, Reason} ->
                    error_reply(500, Reason, Req2, State)
            end;
        _ ->
            error_reply(400, <<"Invalid JSON">>, Req2, State)
    end;

%% Lifecycle actions
handle(<<"POST">>, ConnId, <<"enable">>, Req, State) ->
    lifecycle_action(fun cb_connectors:enable/1, ConnId, Req, State);
handle(<<"POST">>, ConnId, <<"disable">>, Req, State) ->
    lifecycle_action(fun cb_connectors:disable/1, ConnId, Req, State);
handle(<<"POST">>, ConnId, <<"deprecate">>, Req, State) ->
    lifecycle_action(fun cb_connectors:deprecate/1, ConnId, Req, State);

handle(_, _, _, Req, State) ->
    Req2 = cowboy_req:reply(405, headers(), <<>>, Req),
    {ok, Req2, State}.

lifecycle_action(Fun, ConnId, Req, State) ->
    case Fun(ConnId) of
        {ok, C} ->
            Req2 = cowboy_req:reply(200, headers(), jsone:encode(connector_to_map(C)), Req),
            {ok, Req2, State};
        {error, not_found} ->
            error_reply(404, <<"not_found">>, Req, State);
        {error, {invalid_transition, From, To}} ->
            Msg = iolist_to_binary(io_lib:format("Cannot transition from ~s to ~s", [From, To])),
            error_reply(422, Msg, Req, State);
        {error, Reason} ->
            error_reply(500, Reason, Req, State)
    end.

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
