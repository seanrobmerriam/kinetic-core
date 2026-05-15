%% @doc Automated API Key Rotation and Audit Trail
%%
%% Provides secrets management for partner API keys:
%% - `rotate_key/2` — atomically replaces the key hash with a fresh secret
%%   and writes an immutable audit event to `key_rotation_events`.
%% - `list_rotations/1` — fetches the full rotation history for a key.
%% - `list_pending_rotation/1` — returns keys whose hash has not been rotated
%%   within `ThresholdDays` days.
%%
%% Secrets are never stored.  The caller receives the new plain-text secret
%% once, at rotation time.  Subsequent authentication uses the stored SHA-256
%% hash via `cb_api_keys:authenticate_key/1`.
-module(cb_key_rotation).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([
    rotate_key/2,
    list_rotations/1,
    list_pending_rotation/1
]).

%% rotate_key/2 uses #api_key{_ = '_'} wildcard which upsets Dialyzer.
-dialyzer({nowarn_function, list_pending_rotation/1}).

%% @doc Rotate an API key secret.
%%
%% Generates a new cryptographic secret, updates the stored hash atomically,
%% and appends an audit event recording who performed the rotation and when.
%% Returns the new plain-text secret (shown once only).
-spec rotate_key(binary(), binary()) ->
    {ok, #{key_id := binary(), key_secret := binary(), rotation_id := binary(),
           rotated_at := timestamp_ms()}}
    | {error, not_found | database_error}.
rotate_key(KeyId, RotatedBy) when is_binary(KeyId), is_binary(RotatedBy) ->
    NewSecret  = base64:encode(crypto:strong_rand_bytes(32)),
    NewHash    = crypto:hash(sha256, NewSecret),
    Now        = erlang:system_time(millisecond),
    RotationId = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
    F = fun() ->
        case mnesia:read(api_keys, KeyId, write) of
            [K] ->
                Updated = K#api_key{key_hash = NewHash, updated_at = Now},
                ok = mnesia:write(api_keys, Updated, write),
                Event = #key_rotation_event{
                    event_id   = RotationId,
                    key_id     = KeyId,
                    rotated_by = RotatedBy,
                    rotated_at = Now
                },
                ok = mnesia:write(key_rotation_events, Event, write),
                {ok, #{
                    key_id      => KeyId,
                    key_secret  => NewSecret,
                    rotation_id => RotationId,
                    rotated_at  => Now
                }};
            [] ->
                {error, not_found}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, {ok, _} = Ok}     -> Ok;
        {atomic, {error, _} = Err} -> Err;
        {aborted, _Reason}         -> {error, database_error}
    end.

%% @doc List all rotation events for a given key, newest first.
-spec list_rotations(binary()) ->
    {ok, [#key_rotation_event{}]} | {error, database_error}.
list_rotations(KeyId) when is_binary(KeyId) ->
    F = fun() ->
        mnesia:index_read(key_rotation_events, KeyId, key_id)
    end,
    case mnesia:transaction(F) of
        {atomic, Events} ->
            Sorted = lists:sort(fun(A, B) ->
                A#key_rotation_event.rotated_at >= B#key_rotation_event.rotated_at
            end, Events),
            {ok, Sorted};
        {aborted, _Reason} ->
            {error, database_error}
    end.

%% @doc Return active keys whose last rotation (or creation) is older than
%% `ThresholdDays` days.  Keys that have never been rotated are included when
%% their `created_at` exceeds the threshold.
-spec list_pending_rotation(pos_integer()) ->
    {ok, [#{key_id := binary(), label := binary(), last_rotated_at := timestamp_ms() | never,
            days_since_rotation := non_neg_integer()}]}
    | {error, database_error}.
list_pending_rotation(ThresholdDays) when is_integer(ThresholdDays), ThresholdDays > 0 ->
    Now = erlang:system_time(millisecond),
    ThresholdMs = ThresholdDays * 24 * 60 * 60 * 1000,
    CutoffMs = Now - ThresholdMs,
    KeysF = fun() ->
        mnesia:select(api_keys, [{#api_key{status = active, _ = '_'}, [], ['$_']}])
    end,
    case mnesia:transaction(KeysF) of
        {atomic, Keys} ->
            Pending = lists:filtermap(fun(K) ->
                KeyId = K#api_key.key_id,
                LastRotated = case latest_rotation_time(KeyId) of
                    {ok, T}  -> T;
                    not_found -> K#api_key.created_at
                end,
                case LastRotated =< CutoffMs of
                    true ->
                        DaysSince = (Now - LastRotated) div (24 * 60 * 60 * 1000),
                        {true, #{
                            key_id             => KeyId,
                            label              => K#api_key.label,
                            last_rotated_at    => LastRotated,
                            days_since_rotation => DaysSince
                        }};
                    false ->
                        false
                end
            end, Keys),
            {ok, Pending};
        {aborted, _Reason} ->
            {error, database_error}
    end.

%% Internal: return the timestamp of the most recent rotation event for a key,
%% or `not_found` if none exists.
-spec latest_rotation_time(binary()) -> {ok, timestamp_ms()} | not_found.
latest_rotation_time(KeyId) ->
    F = fun() -> mnesia:index_read(key_rotation_events, KeyId, key_id) end,
    case mnesia:transaction(F) of
        {atomic, []} ->
            not_found;
        {atomic, Events} ->
            Latest = lists:max([E#key_rotation_event.rotated_at || E <- Events]),
            {ok, Latest};
        {aborted, _} ->
            not_found
    end.
