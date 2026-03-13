-module(cb_integration_app).
-behaviour(application).

-export([start/2, stop/1]).

-spec start(normal, any()) -> {ok, pid()} | {error, any()}.
start(_StartType, _StartArgs) ->
    %% Create Mnesia schema and start Mnesia
    case mnesia:create_schema([node()]) of
        ok -> ok;
        {error, {_, {already_exists, _}}} -> ok
    end,
    ok = mnesia:start(),

    %% Create tables
    ok = cb_schema:create_tables(),

    %% Start Cowboy HTTP server
    {ok, Port} = application:get_env(cb_integration, http_port),
    {ok, Acceptors} = application:get_env(cb_integration, http_acceptors),

    Dispatch = cb_router:dispatch(),
    {ok, _} = cowboy:start_clear(
        ironledger_http,
        [{port, Port}, {num_acceptors, Acceptors}],
        #{env => #{dispatch => Dispatch}}
    ),

    cb_integration_sup:start_link().

-spec stop(any()) -> ok.
stop(_State) ->
    cowboy:stop_listener(ironledger_http),
    ok.
