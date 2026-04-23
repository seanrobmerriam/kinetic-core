%% @doc HTTP handler: GET /v1/stp/metrics
%%
%% Returns STP pipeline statistics useful for the operations dashboard.
-module(cb_stp_metrics_handler).
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

init(Req, State) ->
    Method = cowboy_req:method(Req),
    handle(Method, Req, State).

handle(<<"GET">>, Req, State) ->
    Rate       = cb_stp_metrics:stp_rate(),
    Reasons    = cb_stp_metrics:exception_reasons(),
    Compliance = cb_stp_metrics:sla_compliance(),
    Payload = #{
        stp_rate          => Rate,
        exception_reasons => [#{reason => R, count => C} || {R, C} <- Reasons],
        sla_compliance    => Compliance
    },
    Req2 = cowboy_req:reply(200, headers(), jsone:encode(Payload), Req),
    {ok, Req2, State};

handle(_, Req, State) ->
    Req2 = cowboy_req:reply(405, headers(), <<>>, Req),
    {ok, Req2, State}.

headers() ->
    maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()).
