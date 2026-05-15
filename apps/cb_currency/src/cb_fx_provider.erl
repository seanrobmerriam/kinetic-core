%% @doc External FX Provider Interface and Fallback Strategy (P1-S3, TASK-034).
%%
%% Abstracts external FX rate provider integrations behind a uniform
%% fetch/refresh API. Multiple named providers can be registered; the
%% primary provider is tried first and, on failure, the fallback chain
%% is walked in order until a rate is obtained.
%%
%% == Provider Types ==
%%
%% Providers are identified by an atom name.  Two simulated types are
%% shipped out of the box:
%%
%%   * `stub'    — deterministic demo rates, always succeeds.
%%   * `mock_fail' — always returns {error, provider_unavailable};
%%                   useful for testing fallback behaviour.
%%
%% == Refresh Flow ==
%%
%% ```
%% refresh_all/0 → for each provider
%%                 → fetch_rate(Provider, From, To) for all tracked pairs
%%                 → cb_fx_rates:set_rate/3
%% ```
%%
%% == Fallback ==
%%
%% ```
%% fetch_with_fallback([primary|rest], From, To)
%%   → primary succeeds  → {ok, Rate}
%%   → primary fails     → fetch_with_fallback(rest, From, To)
%%   → all fail          → {error, no_provider_available}
%% ```
-module(cb_fx_provider).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([
    register_provider/3,
    list_providers/0,
    get_provider/1,
    set_provider_status/2,
    fetch_rate/3,
    fetch_with_fallback/3,
    refresh_all/0,
    set_primary/1
]).

%%--------------------------------------------------------------------
%% Provider registration (config + Mnesia)
%%--------------------------------------------------------------------

%% @doc Register an FX rate provider.
%%
%% `Name'     — unique atom key, e.g. `bloomberg', `open_exchange_rates'.
%% `Type'     — implementation type: `stub' | `mock_fail' | `http'.
%% `Config'   — map of provider-specific params (url, api_key, timeout_ms …).
-spec register_provider(binary(), atom(), map()) ->
    {ok, binary()} | {error, already_registered | term()}.
register_provider(Name, Type, Config) when is_binary(Name) ->
    case provider_exists(Name) of
        true  -> {error, already_registered};
        false ->
            ProviderId = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
            Now = erlang:system_time(millisecond),
            Row = #fx_provider{
                provider_id = ProviderId,
                name        = Name,
                type        = Type,
                config      = Config,
                status      = active,
                priority    = next_priority(),
                last_sync   = undefined,
                created_at  = Now
            },
            {atomic, ok} = mnesia:transaction(fun() -> mnesia:write(Row) end),
            {ok, ProviderId}
    end.

-spec list_providers() -> [#fx_provider{}].
list_providers() ->
    {atomic, Rows} = mnesia:transaction(fun() ->
        mnesia:foldl(fun(P, Acc) -> [P | Acc] end, [], fx_provider)
    end),
    lists:sort(fun(A, B) -> A#fx_provider.priority =< B#fx_provider.priority end, Rows).

-spec get_provider(binary()) -> {ok, #fx_provider{}} | {error, not_found}.
get_provider(ProviderId) ->
    case mnesia:dirty_read(fx_provider, ProviderId) of
        [P] -> {ok, P};
        []  -> {error, not_found}
    end.

-spec set_provider_status(binary(), active | disabled) ->
    ok | {error, not_found | term()}.
set_provider_status(ProviderId, Status) ->
    F = fun() ->
        case mnesia:read(fx_provider, ProviderId) of
            [P] -> mnesia:write(P#fx_provider{status = Status});
            []  -> {error, not_found}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, ok}                 -> ok;
        {atomic, {error, not_found}} -> {error, not_found};
        {aborted, Reason}            -> {error, Reason}
    end.

%% @doc Promote a provider to priority 1, shifting all others down.
-spec set_primary(binary()) -> ok | {error, not_found}.
set_primary(ProviderId) ->
    F = fun() ->
        case mnesia:read(fx_provider, ProviderId) of
            []  -> {error, not_found};
            [P] ->
                %% Increment every other provider's priority by 1
                All = mnesia:foldl(fun(Row, Acc) -> [Row | Acc] end, [], fx_provider),
                [mnesia:write(R#fx_provider{priority = R#fx_provider.priority + 1})
                 || R <- All, R#fx_provider.provider_id =/= ProviderId],
                mnesia:write(P#fx_provider{priority = 1}),
                ok
        end
    end,
    case mnesia:transaction(F) of
        {atomic, ok}                 -> ok;
        {atomic, {error, not_found}} -> {error, not_found};
        {aborted, Reason}            -> {error, Reason}
    end.

%%--------------------------------------------------------------------
%% Rate fetching
%%--------------------------------------------------------------------

%% @doc Fetch a rate from a specific provider.
%%
%% Returns {ok, RateMillionths} where rate_millionths follow the same
%% convention as `cb_fx_rates' (1_000_000 = 1.0).
-spec fetch_rate(binary(), currency(), currency()) ->
    {ok, pos_integer()} | {error, atom()}.
fetch_rate(ProviderId, From, To) when From =:= To ->
    _ = ProviderId,
    {error, same_currency};
fetch_rate(ProviderId, From, To) ->
    case mnesia:dirty_read(fx_provider, ProviderId) of
        []  -> {error, provider_not_found};
        [P] ->
            case P#fx_provider.status of
                disabled -> {error, provider_disabled};
                active   -> dispatch_fetch(P#fx_provider.type, P#fx_provider.config, From, To)
            end
    end.

%% @doc Try providers in priority order; return first success.
-spec fetch_with_fallback([binary()], currency(), currency()) ->
    {ok, pos_integer()} | {error, no_provider_available}.
fetch_with_fallback([], _From, _To) ->
    {error, no_provider_available};
fetch_with_fallback([ProviderId | Rest], From, To) ->
    case fetch_rate(ProviderId, From, To) of
        {ok, _Rate} = Ok -> Ok;
        {error, _}       -> fetch_with_fallback(Rest, From, To)
    end.

%% @doc Refresh all active providers and persist rates via cb_fx_rates.
%%
%% For each active provider, fetch rates for all tracked currency pairs
%% and store them.  Returns {ok, RefreshedCount} on success.
-spec refresh_all() -> {ok, non_neg_integer()}.
refresh_all() ->
    Providers = [P || P <- list_providers(), P#fx_provider.status =:= active],
    Pairs = all_currency_pairs(),
    Count = lists:foldl(fun(Provider, Acc) ->
        Now = erlang:system_time(millisecond),
        Fetched = lists:foldl(fun({From, To}, PairAcc) ->
            case dispatch_fetch(Provider#fx_provider.type, Provider#fx_provider.config, From, To) of
                {ok, Rate} ->
                    _ = cb_fx_rates:set_rate(From, To, Rate),
                    PairAcc + 1;
                {error, _} ->
                    PairAcc
            end
        end, 0, Pairs),
        F = fun() ->
            case mnesia:read(fx_provider, Provider#fx_provider.provider_id) of
                [P] -> mnesia:write(P#fx_provider{last_sync = Now});
                []  -> ok
            end
        end,
        {atomic, _} = mnesia:transaction(F),
        Acc + Fetched
    end, 0, Providers),
    {ok, Count}.

%%--------------------------------------------------------------------
%% Internal helpers
%%--------------------------------------------------------------------

dispatch_fetch(stub, _Config, From, To) ->
    %% Deterministic demo rates for all supported pairs.
    Rate = stub_rate(From, To),
    {ok, Rate};
dispatch_fetch(mock_fail, _Config, _From, _To) ->
    {error, provider_unavailable};
dispatch_fetch(http, Config, From, To) ->
    %% Real HTTP provider: POST to url with api_key.
    %% In the MVP, we simulate with stub rates.
    _ = maps:get(url, Config, undefined),
    _ = maps:get(api_key, Config, undefined),
    Rate = stub_rate(From, To),
    {ok, Rate};
dispatch_fetch(_UnknownType, _Config, _From, _To) ->
    {error, unsupported_provider_type}.

%% Deterministic demo rates (millionths, approximate real-world values).
stub_rate('USD', 'EUR') -> 920_000;
stub_rate('USD', 'GBP') -> 790_000;
stub_rate('USD', 'JPY') -> 149_500_000; %% 149.5
stub_rate('USD', 'CHF') -> 899_000;
stub_rate('USD', 'AUD') -> 1_540_000;
stub_rate('USD', 'CAD') -> 1_360_000;
stub_rate('USD', 'SGD') -> 1_340_000;
stub_rate('USD', 'HKD') -> 7_820_000;
stub_rate('USD', 'NZD') -> 1_620_000;
stub_rate('EUR', 'USD') -> 1_087_000;
stub_rate('EUR', 'GBP') -> 858_000;
stub_rate('GBP', 'USD') -> 1_265_000;
stub_rate('GBP', 'EUR') -> 1_166_000;
stub_rate(From, To)  ->
    %% Symmetric fallback: invert if reverse rate known.
    case stub_rate_safe(To, From) of
        {ok, Rev} -> invert_rate(Rev);
        error     -> 1_000_000 %% Assume parity for unknown pairs.
    end.

stub_rate_safe('USD', 'EUR') -> {ok, 920_000};
stub_rate_safe('USD', 'GBP') -> {ok, 790_000};
stub_rate_safe('USD', 'JPY') -> {ok, 149_500_000};
stub_rate_safe('EUR', 'USD') -> {ok, 1_087_000};
stub_rate_safe('GBP', 'USD') -> {ok, 1_265_000};
stub_rate_safe(_, _)          -> error.

invert_rate(R) when R > 0 -> round(1_000_000 * 1_000_000 / R);
invert_rate(_)              -> 1_000_000.

provider_exists(Name) ->
    All = mnesia:dirty_match_object(#fx_provider{
        provider_id = '_', name = Name, type = '_', config = '_',
        status = '_', priority = '_', last_sync = '_', created_at = '_'
    }),
    All =/= [].

next_priority() ->
    All = mnesia:dirty_match_object(#fx_provider{
        provider_id = '_', name = '_', type = '_', config = '_',
        status = '_', priority = '_', last_sync = '_', created_at = '_'
    }),
    case All of
        [] -> 1;
        _  -> lists:max([P#fx_provider.priority || P <- All]) + 1
    end.

all_currency_pairs() ->
    Currencies = ['USD','EUR','GBP','JPY','CHF','AUD','CAD','SGD','HKD','NZD'],
    [{F, T} || F <- Currencies, T <- Currencies, F =/= T].
