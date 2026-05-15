%% @doc Health Check Handler
%%
%% Provides a health check endpoint that verifies multiple backend services.
%% Returns 200 when all checks pass, 503 when any critical check fails.
%%
%% Checks performed:
%% - Mnesia database connectivity
%% - cb_ledger (ledger_entry table)
%% - cb_payments (transaction table)
%% - cb_auth (auth_session table)
%% - cb_events (event_outbox table)
%%
%% @see cb_router
-module(cb_health_handler).

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    handle(Method, Req, State).

handle(<<"GET">>, Req, State) ->
    Checks = [
        check_mnesia(),
        check_ledger(),
        check_payments(),
        check_auth(),
        check_events()
    ],

    OverallStatus = aggregate_status(Checks),
    Response = #{
        status => OverallStatus,
        checks => [#{service => C#service, status => C#status, latency_ms => C#latency_ms}
                   || C <- Checks]
    },

    StatusCode = case OverallStatus of
        ok -> 200;
        degraded -> 200;
        unhealthy -> 503
    end,

    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    Req2 = cowboy_req:reply(StatusCode, Headers, jsone:encode(Response), Req),
    {ok, Req2, State};

handle(<<"OPTIONS">>, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};

handle(_, Req, State) ->
    {Code405, Hdrs405, Body405} = cb_http_errors:to_response_with_metrics(method_not_allowed),
    Req2 = cowboy_req:reply(Code405, Hdrs405, Body405, Req),
    {ok, Req2, State}.

%% @private Perform a Mnesia health check
check_mnesia() ->
    Start = os:system_time(millisecond),
    Result = case mnesia:system_info(is_running) of
        yes ->
            case mnesia:system_info(tables) of
                Tabs when length(Tabs) > 10 -> ok;
                _ -> degraded
            end;
        _ ->
            unhealthy
    end,
    #service = <<"mnesia">>,
    #status = Result,
    #latency_ms = os:system_time(millisecond) - Start.

%% @private Perform a cb_ledger health check
check_ledger() ->
    Start = os:system_time(millisecond),
    Result = try
        F = fun() -> mnesia:table_info(ledger_entry, size) end,
        {atomic, Size} = mnesia:transaction(F),
        case is_integer(Size) of
            true -> ok;
            false -> degraded
        end
    catch
        _:_ -> unhealthy
    end,
    #service = <<"cb_ledger">>,
    #status = Result,
    #latency_ms = os:system_time(millisecond) - Start.

%% @private Perform a cb_payments health check
check_payments() ->
    Start = os:system_time(millisecond),
    Result = try
        F = fun() -> mnesia:table_info(transaction, size) end,
        {atomic, Size} = mnesia:transaction(F),
        case is_integer(Size) of
            true -> ok;
            false -> degraded
        end
    catch
        _:_ -> unhealthy
    end,
    #service = <<"cb_payments">>,
    #status = Result,
    #latency_ms = os:system_time(millisecond) - Start.

%% @private Perform a cb_auth health check
check_auth() ->
    Start = os:system_time(millisecond),
    Result = try
        F = fun() -> mnesia:table_info(auth_session, size) end,
        {atomic, _} = mnesia:transaction(F),
        ok
    catch
        _:_ -> unhealthy
    end,
    #service = <<"cb_auth">>,
    #status = Result,
    #latency_ms = os:system_time(millisecond) - Start.

%% @private Perform a cb_events health check
check_events() ->
    Start = os:system_time(millisecond),
    Result = try
        F = fun() -> mnesia:table_info(event_outbox, size) end,
        {atomic, _} = mnesia:transaction(F),
        ok
    catch
        _:_ -> unhealthy
    end,
    #service = <<"cb_events">>,
    #status = Result,
    #latency_ms = os:system_time(millisecond) - Start.

%% @private Aggregate individual check statuses into an overall status
aggregate_status(Checks) ->
    Statuses = [C#status || C <- Checks],
    case lists:member(unhealthy, Statuses) of
        true -> unhealthy;
        false ->
            case lists:member(degraded, Statuses) of
                true -> degraded;
                false -> ok
            end
    end.
