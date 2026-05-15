%% @doc Pending Key Rotation Handler
%%
%% <h2>REST API Endpoint</h2>
%%
%% <ul>
%%   <li><b>GET /api/v1/api-keys/rotation-pending?days=N</b>
%%       — List active API keys not rotated within N days (default 90).
%%       Admin-only (enforced by cb_auth_middleware).</li>
%% </ul>
-module(cb_rotation_pending_handler).

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    case require_admin(Req, State) of
        {error, Reply} -> Reply;
        ok             -> handle(Method, Req, State)
    end.

handle(<<"GET">>, Req, State) ->
    DaysParam = cowboy_req:match_qs([{days, [], <<"90">>}], Req),
    Days = case maps:get(days, DaysParam, <<"90">>) of
        V when is_binary(V) ->
            try binary_to_integer(V) catch _:_ -> 90 end;
        _ ->
            90
    end,
    ThresholdDays = max(1, Days),
    case cb_key_rotation:list_pending_rotation(ThresholdDays) of
        {ok, Items} ->
            json_reply(200, #{items => Items, total => length(Items),
                              threshold_days => ThresholdDays}, Req, State);
        {error, Reason} ->
            reply_error(Reason, Req, State)
    end;

handle(<<"OPTIONS">>, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};

handle(_, Req, State) ->
    reply_error(method_not_allowed, Req, State).

%% =============================================================================
%% Internal Helpers
%% =============================================================================

require_admin(Req, State) ->
    Session = erlang:get(auth_session),
    Role = case Session of
        undefined        -> undefined;
        S when is_map(S) -> maps:get(role, S, undefined);
        _                -> undefined
    end,
    case Role of
        admin -> ok;
        _ ->
            {Status, ErrorAtom, Message} = cb_http_errors:to_response(forbidden),
            Resp = #{error => ErrorAtom, message => Message},
            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
            Req2 = cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req),
            {error, {ok, Req2, State}}
    end.

reply_error(Reason, Req, State) ->
    {Status, ErrorAtom, Message} = cb_http_errors:to_response(Reason),
    json_reply(Status, #{error => ErrorAtom, message => Message}, Req, State).

json_reply(Status, Body, Req, State) ->
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    Req2 = cowboy_req:reply(Status, Headers, jsone:encode(Body), Req),
    {ok, Req2, State}.
