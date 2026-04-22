%% @doc API Usage Tracking
%%
%% Records per-API-key request events for usage reporting.
%% Called by `cb_auth_middleware' after a successful API key authentication.
%%
%% Writes are best-effort (non-blocking spawn); a failed write does not
%% affect the in-flight request.
-module(cb_api_usage).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([record_request/3, get_usage_for_key/1]).

%% @doc Asynchronously record a single API request event.
%%
%% @param KeyId   The authenticated API key ID.
%% @param Method  The HTTP method (e.g. `<<"GET">>').
%% @param Path    The request path (e.g. `<<"/api/v1/accounts">>').
-spec record_request(binary(), binary(), binary()) -> ok.
record_request(KeyId, Method, Path) ->
    EventId = list_to_binary(uuid:get_v4_urandom()),
    Now     = erlang:system_time(millisecond),
    Event   = #api_usage_event{
        event_id    = EventId,
        key_id      = KeyId,
        method      = Method,
        path        = Path,
        recorded_at = Now
    },
    spawn(fun() ->
        mnesia:dirty_write(Event)
    end),
    ok.

%% @doc Return all recorded usage events for the given API key, newest first.
%%
%% @param KeyId The API key ID to look up.
-spec get_usage_for_key(binary()) -> [#api_usage_event{}].
get_usage_for_key(KeyId) ->
    F = fun() ->
        mnesia:index_read(api_usage_event, KeyId, key_id)
    end,
    Events = case mnesia:transaction(F) of
        {atomic, E}  -> E;
        {aborted, _} -> []
    end,
    lists:sort(
        fun(A, B) -> A#api_usage_event.recorded_at >= B#api_usage_event.recorded_at end,
        Events
    ).
