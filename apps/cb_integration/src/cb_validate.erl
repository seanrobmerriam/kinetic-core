%% @doc Centralised request validation helpers.
%%
%% Provides reusable typed validators for common field types found in
%% Kinetic Core API requests. All validators return `{ok, Value}' on
%% success or `{error, Reason}' where `Reason' is an atom accepted by
%% `cb_http_errors:to_response/1'.
-module(cb_validate).

-export([
    required_binary/2,
    optional_binary/3,
    required_integer/2,
    optional_integer/3,
    uuid/1,
    amount/1,
    currency/1,
    safe_text/2,
    bounded_binary/3,
    safe_path_param/1,
    integer_param/3
]).

%% @doc Extract a required binary field from a JSON map.
-spec required_binary(binary(), map()) ->
    {ok, binary()} | {error, missing_required_field}.
required_binary(Key, Map) ->
    case maps:get(Key, Map, undefined) of
        undefined           -> {error, missing_required_field};
        V when is_binary(V) -> {ok, V};
        _                   -> {error, missing_required_field}
    end.

%% @doc Extract an optional binary field, returning `Default' when absent.
-spec optional_binary(binary(), map(), binary()) -> binary().
optional_binary(Key, Map, Default) ->
    case maps:get(Key, Map, Default) of
        V when is_binary(V) -> V;
        _                   -> Default
    end.

%% @doc Extract a required integer field from a JSON map.
-spec required_integer(binary(), map()) ->
    {ok, integer()} | {error, missing_required_field | invalid_amount}.
required_integer(Key, Map) ->
    case maps:get(Key, Map, undefined) of
        undefined            -> {error, missing_required_field};
        V when is_integer(V) -> {ok, V};
        _                    -> {error, invalid_amount}
    end.

%% @doc Extract an optional integer field, returning `Default' when absent.
-spec optional_integer(binary(), map(), integer()) -> integer().
optional_integer(Key, Map, Default) ->
    case maps:get(Key, Map, Default) of
        V when is_integer(V) -> V;
        _                    -> Default
    end.

%% @doc Parse an integer from a query-string proplist.
%% Returns `{error, invalid_query_param}' for non-integer strings,
%% and `{ok, Default}' when the key is absent.
-spec integer_param(binary(), proplists:proplist(), integer()) ->
    {ok, integer()} | {error, invalid_query_param}.
integer_param(Key, Qs, Default) ->
    case proplists:get_value(Key, Qs, undefined) of
        undefined -> {ok, Default};
        V when is_binary(V) ->
            try {ok, binary_to_integer(V)}
            catch _:_ -> {error, invalid_query_param}
            end
    end.

%% @doc Validate a UUID v4 string in standard 8-4-4-4-12 hyphenated format.
-spec uuid(binary()) -> ok | {error, invalid_uuid}.
uuid(V) when is_binary(V), byte_size(V) =:= 36 ->
    Pat = <<"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$">>,
    case re:run(V, Pat, [{capture, none}]) of
        match   -> ok;
        nomatch -> {error, invalid_uuid}
    end;
uuid(_) -> {error, invalid_uuid}.

%% @doc Validate a monetary amount expressed in integer minor units.
%%
%% Accepts positive integers up to 999_999_999_999 (prototype ceiling).
-spec amount(integer()) ->
    ok | {error, invalid_amount | zero_amount | amount_overflow}.
amount(V) when is_integer(V), V > 0, V =< 999_999_999_999 -> ok;
amount(V) when is_integer(V), V =:= 0                      -> {error, zero_amount};
amount(V) when is_integer(V), V < 0                        -> {error, invalid_amount};
amount(V) when is_integer(V)                               -> {error, amount_overflow};
amount(_)                                                   -> {error, invalid_amount}.

%% @doc Validate an ISO 4217 currency code.
%%
%% Accepts any upper-case 3-letter alphabetic code. Specific unsupported
%% currencies are rejected downstream by the domain layer.
-spec currency(binary()) -> ok | {error, invalid_currency}.
currency(V) when is_binary(V), byte_size(V) =:= 3 ->
    case re:run(V, <<"^[A-Z]{3}$">>, [{capture, none}]) of
        match   -> ok;
        nomatch -> {error, invalid_currency}
    end;
currency(_) -> {error, invalid_currency}.

%% @doc Validate that a binary value is safe for storage and display.
%%
%% Accepts binaries that are:
%% - At most MaxBytes bytes long.
%% - Valid UTF-8.
%% - Free of null bytes (0x00) and ASCII control characters (0x01–0x1F, 0x7F).
-spec safe_text(binary(), pos_integer()) ->
    {ok, binary()} | {error, invalid_text | field_too_large}.
safe_text(V, MaxBytes) when is_binary(V), byte_size(V) =< MaxBytes ->
    case has_unsafe_bytes(V) of
        true  -> {error, invalid_text};
        false ->
            case unicode:characters_to_binary(V, utf8, utf8) of
                V -> {ok, V};
                _ -> {error, invalid_text}
            end
    end;
safe_text(V, _MaxBytes) when is_binary(V) ->
    {error, field_too_large};
safe_text(_, _) ->
    {error, invalid_text}.

%% @doc Extract a required binary field and validate it with safe_text/2.
-spec bounded_binary(binary(), map(), pos_integer()) ->
    {ok, binary()} | {error, missing_required_field | invalid_text | field_too_large}.
bounded_binary(Key, Map, MaxBytes) ->
    case required_binary(Key, Map) of
        {ok, V}  -> safe_text(V, MaxBytes);
        Err      -> Err
    end.

%% @doc Validate a path-binding value is safe (no null bytes, max 256 bytes).
-spec safe_path_param(binary()) ->
    {ok, binary()} | {error, invalid_path_param}.
safe_path_param(V) when is_binary(V), byte_size(V) =< 256 ->
    case has_null_byte(V) of
        true  -> {error, invalid_path_param};
        false -> {ok, V}
    end;
safe_path_param(V) when is_binary(V) ->
    {error, invalid_path_param};
safe_path_param(_) ->
    {error, invalid_path_param}.

%% @private Return true if binary contains a null byte (0x00).
-spec has_null_byte(binary()) -> boolean().
has_null_byte(B) -> binary:match(B, <<0>>) =/= nomatch.

%% @private Return true if binary contains a null byte or an ASCII control character.
-spec has_unsafe_bytes(binary()) -> boolean().
has_unsafe_bytes(B) ->
    lists:any(fun(Byte) -> Byte =:= 0 orelse (Byte >= 1 andalso Byte =< 31) orelse Byte =:= 127 end,
              binary:bin_to_list(B)).
