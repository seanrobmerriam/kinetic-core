%% @doc TASK-080 — BYOK (bring-your-own-key) encryption path.
%%
%% Customer-supplied data encryption keys (DEKs) are wrapped at rest using a
%% platform master key encryption key (KEK) derived from application env.
%% Plaintext key material is never persisted.
%%
%% Crypto: AES-256-GCM for both the DEK wrap and payload encryption. Each
%% wrapped DEK stores its own IV. Each payload encryption returns a fresh
%% IV + auth tag with the ciphertext.
%%
%% Lifecycle: pending -> active -> rotated|revoked. Encrypt operations
%% require active status; decrypt is permitted while rotated (so previously
%% encrypted data can still be read).
-module(cb_byok).

-include_lib("cb_ledger/include/cb_ledger.hrl").
-include_lib("cb_insights/include/cb_insights.hrl").

-export([
    register_key/3,
    activate/1,
    rotate/2,
    revoke/2,
    get_key/1,
    list_keys/1,
    encrypt/4,
    decrypt/4,
    list_access_log/1
]).

-define(ALG, <<"AES-256-GCM">>).
-define(KEY_BYTES, 32).
-define(IV_BYTES,  12).

-type cipher_envelope() :: #{iv := binary(),
                             ciphertext := binary(),
                             tag := binary()}.

-spec register_key(binary(), binary(), binary()) ->
    {ok, uuid()} | {error, term()}.
register_key(Owner, KeyMaterial, Algorithm)
        when is_binary(Owner), is_binary(KeyMaterial), is_binary(Algorithm) ->
    case byte_size(KeyMaterial) of
        ?KEY_BYTES ->
            do_register(Owner, KeyMaterial, Algorithm);
        _ ->
            {error, invalid_key_length}
    end.

-spec activate(uuid()) -> ok | {error, not_found | invalid_transition}.
activate(KeyId) ->
    transition(KeyId, fun(K) ->
        case K#byok_key.status of
            pending -> {ok, K#byok_key{status = active}};
            _       -> {error, invalid_transition}
        end
    end).

-spec rotate(uuid(), binary()) -> ok | {error, term()}.
rotate(KeyId, Accessor) ->
    Result = mnesia:transaction(fun() ->
        case mnesia:read(byok_key, KeyId) of
            [] ->
                {error, not_found};
            [K] when K#byok_key.status =:= active ->
                mnesia:write(K#byok_key{
                    status     = rotated,
                    rotated_at = erlang:system_time(millisecond)}),
                ok;
            [_] ->
                {error, invalid_transition}
        end
    end),
    Outcome = case Result of
        {atomic, ok}    -> ok;
        {atomic, Other} -> Other;
        {aborted, R}    -> {error, R}
    end,
    log_access(KeyId, Accessor, <<"rotation">>, rotate, Outcome),
    Outcome.

-spec revoke(uuid(), binary()) -> ok | {error, term()}.
revoke(KeyId, Accessor) ->
    Result = mnesia:transaction(fun() ->
        case mnesia:read(byok_key, KeyId) of
            [] ->
                {error, not_found};
            [K] when K#byok_key.status =/= revoked ->
                mnesia:write(K#byok_key{
                    status     = revoked,
                    revoked_at = erlang:system_time(millisecond)}),
                ok;
            [_] ->
                {error, invalid_transition}
        end
    end),
    Outcome = case Result of
        {atomic, ok}    -> ok;
        {atomic, Other} -> Other;
        {aborted, R}    -> {error, R}
    end,
    log_access(KeyId, Accessor, <<"revocation">>, revoke, Outcome),
    Outcome.

-spec get_key(uuid()) -> {ok, #byok_key{}} | {error, not_found}.
get_key(KeyId) ->
    case mnesia:transaction(fun() -> mnesia:read(byok_key, KeyId) end) of
        {atomic, [K]} -> {ok, K};
        {atomic, []}  -> {error, not_found};
        {aborted, R}  -> {error, R}
    end.

-spec list_keys(binary()) -> [#byok_key{}].
list_keys(Owner) ->
    {atomic, Ks} = mnesia:transaction(
        fun() -> mnesia:match_object(#byok_key{owner = Owner, _ = '_'}) end),
    Ks.

-spec encrypt(uuid(), binary(), binary(), binary()) ->
    {ok, cipher_envelope()} | {error, term()}.
encrypt(KeyId, Plaintext, Accessor, Purpose) ->
    case authorize(KeyId, encrypt) of
        {ok, K} ->
            DEK = unwrap_dek(K),
            IV  = crypto:strong_rand_bytes(?IV_BYTES),
            {Cipher, Tag} = crypto:crypto_one_time_aead(
                aes_256_gcm, DEK, IV, Plaintext, <<>>, true),
            log_access(KeyId, Accessor, Purpose, encrypt, ok),
            {ok, #{iv => IV, ciphertext => Cipher, tag => Tag}};
        {error, Reason} ->
            log_access(KeyId, Accessor, Purpose, encrypt, {error, Reason}),
            {error, Reason}
    end.

-spec decrypt(uuid(), cipher_envelope(), binary(), binary()) ->
    {ok, binary()} | {error, term()}.
decrypt(KeyId, #{iv := IV, ciphertext := Cipher, tag := Tag}, Accessor, Purpose) ->
    case authorize(KeyId, decrypt) of
        {ok, K} ->
            DEK = unwrap_dek(K),
            try crypto:crypto_one_time_aead(
                    aes_256_gcm, DEK, IV, Cipher, <<>>, Tag, false) of
                Plain when is_binary(Plain) ->
                    log_access(KeyId, Accessor, Purpose, decrypt, ok),
                    {ok, Plain}
            catch
                _:_ ->
                    log_access(KeyId, Accessor, Purpose, decrypt,
                               {error, integrity_check_failed}),
                    {error, integrity_check_failed}
            end;
        {error, Reason} ->
            log_access(KeyId, Accessor, Purpose, decrypt, {error, Reason}),
            {error, Reason}
    end.

-spec list_access_log(uuid()) -> [#byok_access_log{}].
list_access_log(KeyId) ->
    {atomic, Logs} = mnesia:transaction(
        fun() ->
            mnesia:match_object(#byok_access_log{key_id = KeyId, _ = '_'})
        end),
    lists:sort(
        fun(A, B) -> A#byok_access_log.accessed_at >= B#byok_access_log.accessed_at end,
        Logs).

%% ---------- internal ----------

do_register(Owner, KeyMaterial, Algorithm) ->
    {WrappedDek, IV} = wrap_dek(KeyMaterial),
    Now = erlang:system_time(millisecond),
    K = #byok_key{
        key_id           = new_id(),
        owner            = Owner,
        algorithm        = Algorithm,
        wrapped_material = WrappedDek,
        iv               = IV,
        status           = pending,
        created_at       = Now,
        rotated_at       = undefined,
        revoked_at       = undefined
    },
    case mnesia:transaction(fun() -> mnesia:write(K) end) of
        {atomic, ok} -> {ok, K#byok_key.key_id};
        {aborted, R} -> {error, R}
    end.

transition(KeyId, Fun) ->
    Result = mnesia:transaction(fun() ->
        case mnesia:read(byok_key, KeyId) of
            []  -> {error, not_found};
            [K] ->
                case Fun(K) of
                    {ok, Updated} -> mnesia:write(Updated), ok;
                    {error, R}    -> {error, R}
                end
        end
    end),
    case Result of
        {atomic, ok}    -> ok;
        {atomic, Other} -> Other;
        {aborted, R}    -> {error, R}
    end.

authorize(KeyId, Op) ->
    case get_key(KeyId) of
        {error, not_found} -> {error, not_found};
        {ok, K} ->
            case {Op, K#byok_key.status} of
                {encrypt, active}   -> {ok, K};
                {decrypt, active}   -> {ok, K};
                {decrypt, rotated}  -> {ok, K};
                {_, _}              -> {error, key_not_active}
            end
    end.

%% Wrap a 32-byte DEK with the platform KEK using AES-256-GCM.
%% Returns {WrappedBlob, IV}. WrappedBlob is Ciphertext++Tag.
wrap_dek(DEK) ->
    KEK = master_kek(),
    IV  = crypto:strong_rand_bytes(?IV_BYTES),
    {Cipher, Tag} = crypto:crypto_one_time_aead(
        aes_256_gcm, KEK, IV, DEK, <<>>, true),
    {<<Cipher/binary, Tag/binary>>, IV}.

unwrap_dek(#byok_key{wrapped_material = Wrapped, iv = IV}) ->
    KEK = master_kek(),
    %% Last 16 bytes are the GCM tag.
    Size = byte_size(Wrapped) - 16,
    <<Cipher:Size/binary, Tag:16/binary>> = Wrapped,
    crypto:crypto_one_time_aead(
        aes_256_gcm, KEK, IV, Cipher, <<>>, Tag, false).

%% Master KEK is derived from application env. In production this would be
%% sourced from an HSM/KMS; here we expand a configured secret to 32 bytes
%% via SHA-256 so the key path is deterministic and testable.
master_kek() ->
    Secret = case application:get_env(cb_insights, master_kek_secret) of
        {ok, S} when is_binary(S) -> S;
        _ -> <<"ironledger-default-kek-do-not-use-in-prod">>
    end,
    crypto:hash(sha256, Secret).

log_access(KeyId, Accessor, Purpose, Op, Outcome) ->
    {Decision, Reason} = case Outcome of
        ok            -> {granted, undefined};
        {error, Why}  -> {denied, Why};
        _             -> {denied, unknown}
    end,
    Log = #byok_access_log{
        access_id   = new_id(),
        key_id      = KeyId,
        accessor    = Accessor,
        purpose     = Purpose,
        operation   = Op,
        decision    = Decision,
        reason      = Reason,
        accessed_at = erlang:system_time(millisecond)
    },
    mnesia:transaction(fun() -> mnesia:write(Log) end),
    ok.

new_id() ->
    uuid:uuid_to_string(uuid:get_v4(), binary_standard).
