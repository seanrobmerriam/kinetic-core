%% @doc Key Rotation Handler
%%
%% Handler for API key rotation and rotation-history endpoints.
%%
%% <h2>REST API Endpoints</h2>
%%
%% <ul>
%%   <li><b>POST /api/v1/api-keys/:key_id/rotate</b>
%%       — Rotate a key secret.  Returns the new plain-text secret once only.
%%       Admin-only (enforced by cb_auth_middleware).</li>
%%   <li><b>GET /api/v1/api-keys/:key_id/rotation-history</b>
%%       — List rotation audit events for a key. Admin-only.</li>
%%   <li><b>GET /api/v1/api-keys/rotation-pending?days=N</b>
%%       — List keys not rotated within N days (default 90). Admin-only.</li>
%% </ul>
-module(cb_api_key_rotation_handler).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    KeyId  = cowboy_req:binding(key_id, Req, undefined),
    case require_admin(Req, State) of
        {error, Reply} -> Reply;
        ok             -> handle(Method, KeyId, Req, State)
    end.

%% POST /api/v1/api-keys/:key_id/rotate
handle(<<"POST">>, KeyId, Req, State) when KeyId =/= undefined ->
    RotatedBy = caller_id(Req),
    case cb_key_rotation:rotate_key(KeyId, RotatedBy) of
        {ok, Result} ->
            json_reply(200, Result, Req, State);
        {error, Reason} ->
            reply_error(Reason, Req, State)
    end;

%% GET /api/v1/api-keys/:key_id/rotation-history
handle(<<"GET">>, KeyId, Req, State) when KeyId =/= undefined ->
    case cb_key_rotation:list_rotations(KeyId) of
        {ok, Events} ->
            Items = [event_to_json(E) || E <- Events],
            json_reply(200, #{items => Items, total => length(Items)}, Req, State);
        {error, Reason} ->
            reply_error(Reason, Req, State)
    end;

handle(<<"OPTIONS">>, _KeyId, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};

handle(_, _KeyId, Req, State) ->
    reply_error(method_not_allowed, Req, State).

%% =============================================================================
%% Internal Helpers
%% =============================================================================

%% Derive a stable caller identifier from the authenticated session.
caller_id(Req) ->
    Session = erlang:get(auth_session),
    case Session of
        S when is_map(S) ->
            KeyId = maps:get(key_id, S, undefined),
            case KeyId of
                undefined ->
                    <<"unknown">>;
                Id ->
                    Id
            end;
        _ ->
            %% Fall back to remote IP if session unavailable (should not happen
            %% after auth middleware, but be defensive).
            {Ip, _Port} = cowboy_req:peer(Req),
            list_to_binary(inet:ntoa(Ip))
    end.

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

event_to_json(E) ->
    #{
        event_id   => E#key_rotation_event.event_id,
        key_id     => E#key_rotation_event.key_id,
        rotated_by => E#key_rotation_event.rotated_by,
        rotated_at => E#key_rotation_event.rotated_at
    }.
