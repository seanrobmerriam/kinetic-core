%% @doc Identity Verification Orchestration.
%%
%% Submits identity verification requests to external providers and
%% manages retry and timeout logic for the verification lifecycle.
%%
%% == Check Lifecycle ==
%%
%% ```
%% pending -> submitted -> passed
%%                      -> failed
%%         -> timed_out
%% ```
%%
%% == Retry Strategy ==
%%
%% Transient failures (provider unavailable) are retried up to max_retries
%% times. Permanent failures (identity mismatch) are not retried.
%%
%% == Provider Stubs ==
%%
%% In the prototype, providers are simulated. The `provider_ref' field
%% stores a generated reference that a real integration would use to
%% poll or receive callbacks.
-module(cb_idv).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([
    initiate_check/3,
    get_check/1,
    list_for_party/1,
    submit_result/3,
    retry_check/1
]).

-define(DEFAULT_MAX_RETRIES, 3).
-define(DEFAULT_TTL_MS, 86_400_000). %% 24 hours

%% @doc Initiate a new identity verification check for a party.
%%
%% Creates the check record and simulates submission to the provider.
-spec initiate_check(uuid(), idv_provider(), map()) ->
    {ok, #idv_check{}} | {error, not_found | atom()}.
initiate_check(PartyId, Provider, Opts) ->
    case mnesia:dirty_read(party, PartyId) of
        [] ->
            {error, not_found};
        [_Party] ->
            Now = erlang:system_time(millisecond),
            MaxRetries = maps:get(max_retries, Opts, ?DEFAULT_MAX_RETRIES),
            TTL = maps:get(ttl_ms, Opts, ?DEFAULT_TTL_MS),
            CheckId = uuid:get_v4_urandom(),
            ProviderRef = simulate_submit(Provider, CheckId),
            Check = #idv_check{
                check_id     = CheckId,
                party_id     = PartyId,
                provider     = Provider,
                status       = pending,
                retry_count  = 0,
                max_retries  = MaxRetries,
                provider_ref = ProviderRef,
                result_data  = #{},
                requested_at = Now,
                expires_at   = Now + TTL,
                completed_at = undefined,
                created_at   = Now,
                updated_at   = Now
            },
            F = fun() -> mnesia:write(idv_check, Check, write), Check end,
            case mnesia:transaction(F) of
                {atomic, C} -> {ok, C};
                {aborted, Reason} -> {error, Reason}
            end
    end.

%% @doc Retrieve an identity verification check by its ID.
-spec get_check(uuid()) -> {ok, #idv_check{}} | {error, not_found}.
get_check(CheckId) ->
    case mnesia:dirty_read(idv_check, CheckId) of
        [] -> {error, not_found};
        [C] -> {ok, C}
    end.

%% @doc List all identity checks for a party.
-spec list_for_party(uuid()) -> {ok, [#idv_check{}]}.
list_for_party(PartyId) ->
    Checks = mnesia:dirty_index_read(idv_check, PartyId, party_id),
    {ok, Checks}.

%% @doc Submit a verification result (passed or failed) for a check.
%%
%% Typically called from a provider callback or polling job.
-spec submit_result(uuid(), passed | failed, map()) ->
    {ok, #idv_check{}} | {error, atom()}.
submit_result(CheckId, Result, ResultData)
        when Result =:= passed; Result =:= failed ->
    F = fun() ->
        case mnesia:read(idv_check, CheckId, write) of
            [] ->
                {error, not_found};
            [C] when C#idv_check.status =/= pending,
                     C#idv_check.status =/= submitted ->
                {error, invalid_idv_check};
            [C] ->
                Now = erlang:system_time(millisecond),
                C2 = C#idv_check{
                    status       = Result,
                    result_data  = ResultData,
                    completed_at = Now,
                    updated_at   = Now
                },
                mnesia:write(idv_check, C2, write),
                C2
        end
    end,
    case mnesia:transaction(F) of
        {atomic, {error, _} = Err} -> Err;
        {atomic, C}                -> {ok, C};
        {aborted, Reason}          -> {error, Reason}
    end;
submit_result(_CheckId, _Result, _ResultData) ->
    {error, invalid_idv_check}.

%% @doc Retry a failed check if retries remain.
-spec retry_check(uuid()) -> {ok, #idv_check{}} | {error, atom()}.
retry_check(CheckId) ->
    F = fun() ->
        case mnesia:read(idv_check, CheckId, write) of
            [] ->
                {error, not_found};
            [C] when C#idv_check.status =/= failed ->
                {error, invalid_idv_check};
            [C] when C#idv_check.retry_count >= C#idv_check.max_retries ->
                {error, max_retries_exceeded};
            [C] ->
                Now = erlang:system_time(millisecond),
                NewRef = simulate_submit(C#idv_check.provider, CheckId),
                C2 = C#idv_check{
                    status       = pending,
                    retry_count  = C#idv_check.retry_count + 1,
                    provider_ref = NewRef,
                    result_data  = #{},
                    updated_at   = Now
                },
                mnesia:write(idv_check, C2, write),
                C2
        end
    end,
    case mnesia:transaction(F) of
        {atomic, {error, _} = Err} -> Err;
        {atomic, C}                -> {ok, C};
        {aborted, Reason}          -> {error, Reason}
    end.

%% Internal

-spec simulate_submit(idv_provider(), uuid()) -> binary().
simulate_submit(Provider, CheckId) ->
    ProviderBin = atom_to_binary(Provider, utf8),
    <<ProviderBin/binary, $-, CheckId/binary>>.
