%% @doc Webhook Deliveries Handler
%%
%% GET /api/v1/webhooks/:subscription_id/deliveries
%%
%% Returns a list of delivery attempts for the given subscription, newest first.
-module(cb_webhook_deliveries_handler).

-export([init/2]).

-include_lib("cb_events/include/cb_events.hrl").

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    handle(Method, Req, State).

handle(<<"GET">>, Req, State) ->
    SubscriptionId = cowboy_req:binding(subscription_id, Req),
    Deliveries = cb_webhooks:list_deliveries_for_subscription(SubscriptionId),
    Resp = lists:map(fun delivery_to_map/1, Deliveries),
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    Req2 = cowboy_req:reply(200, Headers, jsone:encode(Resp), Req),
    {ok, Req2, State};

handle(<<"OPTIONS">>, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};

handle(_, Req, State) ->
    {_Code405, _Hdrs405, _Body405} = cb_http_errors:to_response_with_metrics(method_not_allowed),
    Req2 = cowboy_req:reply(_Code405, _Hdrs405, _Body405, Req),
    {ok, Req2, State}.

delivery_to_map(D) ->
    #{
        delivery_id     => D#webhook_delivery.delivery_id,
        subscription_id => D#webhook_delivery.subscription_id,
        event_id        => D#webhook_delivery.event_id,
        attempt_status  => D#webhook_delivery.attempt_status,
        response_code   => D#webhook_delivery.response_code,
        created_at      => D#webhook_delivery.created_at,
        updated_at      => D#webhook_delivery.updated_at
    }.
