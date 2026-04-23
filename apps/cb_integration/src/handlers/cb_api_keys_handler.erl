%% @doc Partner API Keys Handler
%%
%% Handler for the `/api/v1/api-keys` endpoints.
%%
%% <h2>REST API Endpoints</h2>
%%
%% <ul>
%%   <li><b>GET /api/v1/api-keys</b> - List all API keys (admin only)</li>
%%   <li><b>POST /api/v1/api-keys</b> - Create a new API key (admin only)</li>
%%   <li><b>GET /api/v1/api-keys/:key_id</b> - Get key details (admin only)</li>
%%   <li><b>DELETE /api/v1/api-keys/:key_id</b> - Revoke a key (admin only)</li>
%% </ul>
%%
%% The key_secret is returned once at creation time and never stored.
-module(cb_api_keys_handler).

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

handle(<<"GET">>, undefined, Req, State) ->
    case cb_api_keys:list_keys() of
        {ok, Keys} ->
            Items = [key_to_json(K) || K <- Keys],
            json_reply(200, #{items => Items, total => length(Items)}, Req, State);
        {error, Reason} ->
            reply_error(Reason, Req, State)
    end;

handle(<<"POST">>, undefined, Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(Body) of
        {ok, Decoded, _} ->
            Label     = maps:get(<<"label">>, Decoded, undefined),
            PartnerId = maps:get(<<"partner_id">>, Decoded, undefined),
            RoleStr   = maps:get(<<"role">>, Decoded, undefined),
            RateLimit = maps:get(<<"rate_limit_per_min">>, Decoded, undefined),
            case {Label, PartnerId, RoleStr, RateLimit} of
                {L, P, R, RL}
                        when is_binary(L), is_binary(P), is_binary(R),
                             is_integer(RL), RL > 0 ->
                    Role = binary_to_role(R),
                    case Role of
                        unknown ->
                            reply_error(missing_required_field, Req2, State);
                        ValidRole ->
                            case cb_api_keys:create_key(L, P, ValidRole, RL) of
                                {ok, KeyMeta} ->
                                    json_reply(201, KeyMeta, Req2, State);
                                {error, Reason} ->
                                    reply_error(Reason, Req2, State)
                            end
                    end;
                _ ->
                    reply_error(missing_required_field, Req2, State)
            end;
        _ ->
            reply_error(invalid_json, Req2, State)
    end;

handle(<<"GET">>, KeyId, Req, State) when KeyId =/= undefined ->
    case cb_api_keys:get_key_by_id(KeyId) of
        {ok, Key}       -> json_reply(200, key_to_json(Key), Req, State);
        {error, Reason} -> reply_error(Reason, Req, State)
    end;

handle(<<"DELETE">>, KeyId, Req, State) when KeyId =/= undefined ->
    case cb_api_keys:revoke_key(KeyId) of
        ok              -> json_reply(200, #{status => <<"revoked">>}, Req, State);
        {error, Reason} -> reply_error(Reason, Req, State)
    end;

handle(<<"OPTIONS">>, _KeyId, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};

handle(_, _KeyId, Req, State) ->
    {_Code405, _Hdrs405, _Body405} = cb_http_errors:to_response_with_metrics(method_not_allowed),
    Req2 = cowboy_req:reply(_Code405, _Hdrs405, _Body405, Req),
    {ok, Req2, State}.

%% =============================================================================
%% Internal Helpers
%% =============================================================================

require_admin(Req, State) ->
    Session = erlang:get(auth_session),
    Role = case Session of
        undefined -> undefined;
        S when is_map(S) -> maps:get(role, S, undefined);
        _ -> undefined
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

key_to_json(K) ->
    #{
        key_id             => K#api_key.key_id,
        label              => K#api_key.label,
        partner_id         => K#api_key.partner_id,
        role               => K#api_key.role,
        status             => K#api_key.status,
        rate_limit_per_min => K#api_key.rate_limit_per_min,
        expires_at         => expires_at_val(K#api_key.expires_at),
        created_at         => K#api_key.created_at,
        updated_at         => K#api_key.updated_at
    }.

expires_at_val(never) -> null;
expires_at_val(V)     -> V.

binary_to_role(<<"admin">>)      -> admin;
binary_to_role(<<"operations">>) -> operations;
binary_to_role(<<"read_only">>)  -> read_only;
binary_to_role(_)                -> unknown.
