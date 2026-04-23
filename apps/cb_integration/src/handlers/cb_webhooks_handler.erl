%% @doc Webhooks Handler
%%
%% Handler for the `/api/v1/webhooks` and `/api/v1/webhooks/:subscription_id` endpoints.
%%
%% <h2>REST API Endpoints</h2>
%%
%% <ul>
%%   <li><b>GET /api/v1/webhooks</b> - List all webhook subscriptions</li>
%%   <li><b>GET /api/v1/webhooks/:subscription_id</b> - Get a single subscription</li>
%%   <li><b>POST /api/v1/webhooks</b> - Create a webhook subscription</li>
%%   <li><b>PATCH /api/v1/webhooks/:subscription_id</b> - Update a subscription</li>
%%   <li><b>DELETE /api/v1/webhooks/:subscription_id</b> - Delete a webhook subscription</li>
%% </ul>
%%
%% @see cb_webhooks
-module(cb_webhooks_handler).

-include_lib("cb_events/include/cb_events.hrl").

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    handle(Method, Req, State).

handle(<<"GET">>, Req, State) ->
    case cowboy_req:binding(subscription_id, Req) of
        undefined ->
            list_subscriptions(Req, State);
        SubscriptionId ->
            get_subscription(SubscriptionId, Req, State)
    end;

handle(<<"POST">>, Req, State) ->
    create_subscription(Req, State);

handle(<<"PATCH">>, Req, State) ->
    case cowboy_req:binding(subscription_id, Req) of
        undefined ->
            not_found(Req, State);
        SubscriptionId ->
            update_subscription(SubscriptionId, Req, State)
    end;

handle(<<"DELETE">>, Req, State) ->
    case cowboy_req:binding(subscription_id, Req) of
        undefined ->
            not_found(Req, State);
        SubscriptionId ->
            delete_subscription(SubscriptionId, Req, State)
    end;

handle(<<"OPTIONS">>, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};

handle(_, Req, State) ->
    {Code, Hdrs, RespBody} = cb_http_errors:to_response_with_metrics(method_not_allowed),
    Req2 = cowboy_req:reply(Code, Hdrs, RespBody, Req),
    {ok, Req2, State}.

list_subscriptions(Req, State) ->
    Subs = cb_webhooks:list_subscriptions(),
    Resp = lists:map(fun sub_to_map/1, Subs),
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    Req2 = cowboy_req:reply(200, Headers, jsone:encode(Resp), Req),
    {ok, Req2, State}.

get_subscription(SubscriptionId, Req, State) ->
    case cb_webhooks:get_subscription(SubscriptionId) of
        {ok, Sub} ->
            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
            Req2 = cowboy_req:reply(200, Headers, jsone:encode(sub_to_map(Sub)), Req),
            {ok, Req2, State};
        {error, not_found} ->
            not_found(Req, State)
    end.

create_subscription(Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(Body) of
        {ok, Json, _} ->
            EventType = maps:get(<<"event_type">>, Json, undefined),
            CallbackUrl = maps:get(<<"callback_url">>, Json, undefined),
            case {EventType, CallbackUrl} of
                {undefined, _} ->
                    {Status, ErrorAtom, Message} = cb_http_errors:to_response(missing_required_field),
                    Resp = #{error => ErrorAtom, message => Message},
                    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
                    Req3 = cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req2),
                    {ok, Req3, State};
                {_, undefined} ->
                    {Status, ErrorAtom, Message} = cb_http_errors:to_response(missing_required_field),
                    Resp = #{error => ErrorAtom, message => Message},
                    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
                    Req3 = cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req2),
                    {ok, Req3, State};
                _ ->
                    case cb_webhooks:create_subscription(CallbackUrl, EventType) of
                        {ok, Sub} ->
                            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
                            Req3 = cowboy_req:reply(201, Headers, jsone:encode(sub_to_map_with_secret(Sub)), Req2),
                            {ok, Req3, State};
                        {error, Reason} ->
                            {Status, ErrorAtom, Message} = cb_http_errors:to_response(Reason),
                            Resp = #{error => ErrorAtom, message => Message},
                            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
                            Req3 = cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req2),
                            {ok, Req3, State}
                    end
            end;
        _ ->
            {Status, ErrorAtom, Message} = cb_http_errors:to_response(invalid_json),
            Resp = #{error => ErrorAtom, message => Message},
            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
            Req3 = cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req2),
            {ok, Req3, State}
    end.

update_subscription(SubscriptionId, Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(Body) of
        {ok, Json, _} when is_map(Json) ->
            case cb_webhooks:update_subscription(SubscriptionId, Json) of
                {ok, Sub} ->
                    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
                    Req3 = cowboy_req:reply(200, Headers, jsone:encode(sub_to_map(Sub)), Req2),
                    {ok, Req3, State};
                {error, not_found} ->
                    not_found(Req2, State);
                {error, Reason} ->
                    {Status, ErrorAtom, Message} = cb_http_errors:to_response(Reason),
                    Resp = #{error => ErrorAtom, message => Message},
                    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
                    Req3 = cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req2),
                    {ok, Req3, State}
            end;
        _ ->
            {Status, ErrorAtom, Message} = cb_http_errors:to_response(invalid_json),
            Resp = #{error => ErrorAtom, message => Message},
            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
            Req3 = cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req2),
            {ok, Req3, State}
    end.

delete_subscription(SubscriptionId, Req, State) ->
    case cb_webhooks:delete_subscription(SubscriptionId) of
        ok ->
            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
            Req2 = cowboy_req:reply(204, Headers, <<>>, Req),
            {ok, Req2, State};
        {error, Reason} ->
            {Status, ErrorAtom, Message} = cb_http_errors:to_response(Reason),
            Resp = #{error => ErrorAtom, message => Message},
            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
            Req2 = cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req),
            {ok, Req2, State}
    end.

not_found(Req, State) ->
    {Code, Hdrs, RespBody} = cb_http_errors:to_response(not_found),
    Req2 = cowboy_req:reply(Code, Hdrs, RespBody, Req),
    {ok, Req2, State}.

sub_to_map(Sub) ->
    #{
        subscription_id => Sub#webhook_subscription.subscription_id,
        event_type      => Sub#webhook_subscription.event_type,
        callback_url    => Sub#webhook_subscription.callback_url,
        status          => Sub#webhook_subscription.status,
        created_at      => Sub#webhook_subscription.created_at,
        updated_at      => Sub#webhook_subscription.updated_at
    }.

sub_to_map_with_secret(Sub) ->
    (sub_to_map(Sub))#{hmac_secret => Sub#webhook_subscription.hmac_secret}.

