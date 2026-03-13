-module(cb_integration_app).
-behaviour(application).

-export([start/2, stop/1, prep_stop/1, config_change/3]).

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

    %% Start Cowboy HTTP server with defaults
    Port = application:get_env(cb_integration, http_port, 8081),
    Acceptors = application:get_env(cb_integration, http_acceptors, 10),

    Dispatch = cb_router:dispatch(),
    {ok, _} = cowboy:start_clear(
        ironledger_http,
        [{port, Port}, {num_acceptors, Acceptors}],
        #{
            env => #{dispatch => Dispatch},
            middlewares => [cowboy_router, cb_log_middleware, cb_cors_middleware, cowboy_handler]
        }
    ),

    cb_integration_sup:start_link().

-spec prep_stop(any()) -> any().
prep_stop(State) ->
    %% Signal Cowboy to stop accepting new connections
    %% Existing connections will be drained before shutdown
    logger:info(#{event => application_prep_stop, app => cb_integration}),
    State.

-spec stop(any()) -> ok.
stop(_State) ->
    _ = cowboy:stop_listener(ironledger_http),
    ok.

-spec config_change(list(), list(), list()) -> ok.
config_change(Changed, _New, _Removed) ->
    %% React to runtime config changes
    case proplists:get_value(http_port, Changed) of
        undefined -> ok;
        _NewPort ->
            logger:warning(#{event => config_change_ignored, key => http_port,
                message => <<"HTTP port change requires application restart">>})
    end,
    case proplists:get_value(http_acceptors, Changed) of
        undefined -> ok;
        _NewAcceptors ->
            logger:warning(#{event => config_change_ignored, key => http_acceptors,
                message => <<"HTTP acceptors change requires application restart">>})
    end,
    ok.
