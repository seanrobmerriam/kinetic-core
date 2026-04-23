%% @doc Health Check Handler
%%
%% Provides a health check endpoint that verifies the Mnesia database is running.
%% Returns 200 when healthy, 503 when degraded.
%%
%% @see cb_router
-module(cb_health_handler).

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    {Code, Body} = case mnesia:system_info(is_running) of
        yes ->
            {200, jsone:encode(#{status => <<"ok">>,
                                 checks => #{mnesia => <<"ok">>}})};
        _ ->
            {503, jsone:encode(#{status  => <<"degraded">>,
                                 checks  => #{mnesia => <<"down">>}})}
    end,
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    Req2 = cowboy_req:reply(Code, Headers, Body, Req),
    {ok, Req2, State}.
