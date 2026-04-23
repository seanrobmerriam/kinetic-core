%% @doc Centralised request validation helpers.
%%
%% Provides reusable typed validators for common field types found in
%% IronLedger API requests. All validators return `{ok, Value}' on
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
    currency/1
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
