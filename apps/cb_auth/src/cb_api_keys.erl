%% @doc Partner API Key Management
%%
%% Provides lifecycle management for partner API keys used as an alternative
%% to session tokens for programmatic access.
%%
%% Key secrets are never stored. Only the SHA-256 hash is persisted.
%% The full base64-encoded key is returned once at creation time.
-module(cb_api_keys).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([
    create_key/4,
    get_key_by_id/1,
    authenticate_key/1,
    list_keys/0,
    revoke_key/1,
    delete_key/1
]).

%% Mnesia wildcard patterns in match specs produce false-positive Dialyzer
%% "no local return" / "record construction violation" warnings because
%% the #api_key{_ = '_'} placeholder assigns atom '_' to all typed fields.
-dialyzer({nowarn_function, list_keys/0}).
%% create_key/4 spec uses timestamp_ms() type alias which Dialyzer resolves
%% to non_neg_integer() — the spec is intentionally broad for public API.
-dialyzer({nowarn_function, create_key/4}).

-spec create_key(binary(), binary(), admin | operations | read_only, pos_integer()) ->
    {ok, #{key_id := binary(), key_secret := binary(), label := binary(),
           partner_id := binary(), role := admin | operations | read_only,
           status := active, rate_limit_per_min := pos_integer(),
           expires_at := never, created_at := timestamp_ms(),
           updated_at := timestamp_ms()}}
    | {error, database_error}.
create_key(Label, PartnerId, Role, RateLimitPerMin)
        when is_binary(Label), is_binary(PartnerId),
             (Role =:= admin orelse Role =:= operations orelse Role =:= read_only),
             is_integer(RateLimitPerMin), RateLimitPerMin > 0 ->
    KeySecret = base64:encode(crypto:strong_rand_bytes(32)),
    KeyHash   = crypto:hash(sha256, KeySecret),
    Now       = erlang:system_time(millisecond),
    KeyId     = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
    Record    = #api_key{
        key_id             = KeyId,
        key_hash           = KeyHash,
        label              = Label,
        partner_id         = PartnerId,
        role               = Role,
        status             = active,
        rate_limit_per_min = RateLimitPerMin,
        expires_at         = never,
        created_at         = Now,
        updated_at         = Now
    },
    F = fun() -> mnesia:write(api_keys, Record, write) end,
    case mnesia:transaction(F) of
        {atomic, ok} ->
            {ok, #{
                key_id             => KeyId,
                key_secret         => KeySecret,
                label              => Label,
                partner_id         => PartnerId,
                role               => Role,
                status             => active,
                rate_limit_per_min => RateLimitPerMin,
                expires_at         => never,
                created_at         => Now,
                updated_at         => Now
            }};
        {aborted, _Reason} ->
            {error, database_error}
    end.

-spec get_key_by_id(binary()) -> {ok, #api_key{}} | {error, not_found | database_error}.
get_key_by_id(KeyId) when is_binary(KeyId) ->
    F = fun() -> mnesia:read(api_keys, KeyId) end,
    case mnesia:transaction(F) of
        {atomic, [Record]} -> {ok, Record};
        {atomic, []}       -> {error, not_found};
        {aborted, _Reason} -> {error, database_error}
    end.

-spec authenticate_key(binary()) ->
    {ok, #{key_id := binary(), label := binary(), partner_id := binary(),
           role := admin | operations | read_only, status := active,
           rate_limit_per_min := pos_integer(),
           expires_at := never | timestamp_ms(),
           created_at := timestamp_ms(), updated_at := timestamp_ms()}}
    | {error, unauthorized}.
authenticate_key(RawToken) when is_binary(RawToken) ->
    KeyHash = crypto:hash(sha256, RawToken),
    F = fun() -> mnesia:index_read(api_keys, KeyHash, key_hash) end,
    case mnesia:transaction(F) of
        {atomic, [#api_key{status = active} = K]} ->
            Now = erlang:system_time(millisecond),
            Expired = case K#api_key.expires_at of
                never     -> false;
                ExpiresAt -> ExpiresAt =< Now
            end,
            case Expired of
                true  -> {error, unauthorized};
                false ->
                    {ok, #{
                        key_id             => K#api_key.key_id,
                        label              => K#api_key.label,
                        partner_id         => K#api_key.partner_id,
                        role               => K#api_key.role,
                        status             => K#api_key.status,
                        rate_limit_per_min => K#api_key.rate_limit_per_min,
                        expires_at         => K#api_key.expires_at,
                        created_at         => K#api_key.created_at,
                        updated_at         => K#api_key.updated_at
                    }}
            end;
        {atomic, _} ->
            {error, unauthorized};
        {aborted, _} ->
            {error, unauthorized}
    end.

-spec list_keys() -> {ok, [#api_key{}]} | {error, database_error}.
list_keys() ->
    F = fun() ->
        mnesia:select(api_keys, [{#api_key{_ = '_'}, [], ['$_']}])
    end,
    case mnesia:transaction(F) of
        {atomic, Keys}     -> {ok, Keys};
        {aborted, _Reason} -> {error, database_error}
    end.

-spec revoke_key(binary()) -> ok | {error, not_found | database_error}.
revoke_key(KeyId) when is_binary(KeyId) ->
    Now = erlang:system_time(millisecond),
    F = fun() ->
        case mnesia:read(api_keys, KeyId, write) of
            [K] ->
                Updated = K#api_key{status = revoked, updated_at = Now},
                mnesia:write(api_keys, Updated, write);
            [] ->
                {error, not_found}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, ok}               -> ok;
        {atomic, {error, _} = Err} -> Err;
        {aborted, _Reason}         -> {error, database_error}
    end.

-spec delete_key(binary()) -> ok | {error, not_found | database_error}.
delete_key(KeyId) when is_binary(KeyId) ->
    F = fun() ->
        case mnesia:read(api_keys, KeyId) of
            [_] -> mnesia:delete(api_keys, KeyId, write);
            []  -> {error, not_found}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, ok}               -> ok;
        {atomic, {error, _} = Err} -> Err;
        {aborted, _Reason}         -> {error, database_error}
    end.
