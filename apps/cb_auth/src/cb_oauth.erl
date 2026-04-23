%% @doc OAuth 2.0 client_credentials grant — domain logic.
%%
%% Implements the `client_credentials' grant type from RFC 6749 Section 4.4
%% for machine-to-machine API access.
%%
%% <h2>Tables</h2>
%%
%% <ul>
%%   <li>`oauth_client' — registered API clients with hashed client secret</li>
%%   <li>`oauth_token'  — active bearer tokens (TTL: 3600 s)</li>
%% </ul>
%%
%% Client secrets are stored as raw SHA-256 hashes (prototype-grade).
%% A production deployment should use bcrypt or Argon2.
-module(cb_oauth).

-export([issue_token/2, validate_token/1]).

-define(TOKEN_TTL_S, 3600).

-record(oauth_client, {
    client_id          :: binary(),
    client_secret_hash :: binary(),
    name               :: binary(),
    scope              :: binary(),
    role               :: atom(),
    status             :: active | inactive,
    created_at         :: integer(),
    updated_at         :: integer()
}).

-record(oauth_token, {
    token      :: binary(),
    client_id  :: binary(),
    scope      :: binary(),
    role       :: atom(),
    expires_at :: integer(),
    created_at :: integer()
}).

%% @doc Issue an access token for a valid client_credentials request.
%%
%% Verifies `ClientId' exists and `ClientSecret' matches the stored hash.
%% Returns `{ok, Token, ExpiresIn}' on success.
-spec issue_token(binary(), binary()) ->
    {ok, binary(), pos_integer()} |
    {error, oauth_invalid_client | oauth_invalid_grant}.
issue_token(ClientId, ClientSecret)
        when is_binary(ClientId), is_binary(ClientSecret) ->
    case mnesia:dirty_read(oauth_client, ClientId) of
        [#oauth_client{client_secret_hash = Hash, role = Role,
                       status = active}] ->
            case Hash =:= hash_secret(ClientSecret) of
                false ->
                    {error, oauth_invalid_client};
                true ->
                    Token  = base64:encode(crypto:strong_rand_bytes(32)),
                    Now    = erlang:system_time(second),
                    Record = #oauth_token{
                        token      = Token,
                        client_id  = ClientId,
                        scope      = <<"api">>,
                        role       = Role,
                        expires_at = Now + ?TOKEN_TTL_S,
                        created_at = Now
                    },
                    case mnesia:transaction(fun() -> mnesia:write(Record) end) of
                        {atomic, ok} -> {ok, Token, ?TOKEN_TTL_S};
                        {aborted, _} -> {error, oauth_invalid_client}
                    end
            end;
        [#oauth_client{status = inactive}] ->
            {error, oauth_invalid_client};
        [] ->
            {error, oauth_invalid_client}
    end;
issue_token(_, _) ->
    {error, oauth_invalid_grant}.

%% @doc Validate a bearer token issued by this module.
%%
%% Returns an auth context map on success, or `{error, unauthorized}' when the
%% token is missing, expired, or unknown.
-spec validate_token(binary()) ->
    {ok, #{role := atom(), client_id := binary(), scope := binary()}} |
    {error, unauthorized}.
validate_token(Token) when is_binary(Token) ->
    Now = erlang:system_time(second),
    case mnesia:dirty_read(oauth_token, Token) of
        [#oauth_token{expires_at = Exp, role = Role,
                      client_id = CId, scope = Scope}]
                when Exp > Now ->
            {ok, #{role => Role, client_id => CId, scope => Scope}};
        _ ->
            {error, unauthorized}
    end;
validate_token(_) ->
    {error, unauthorized}.

hash_secret(Secret) ->
    crypto:hash(sha256, Secret).
