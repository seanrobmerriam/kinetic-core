%% @doc Risk and Capital Calculations (TASK-064)
%%
%% Computes exposure metrics, capital ratios, limit breach checks,
%% and risk tier classification for regulatory capital management.
%%
%% == Metrics supported ==
%% <ul>
%%   <li>credit_exposure  — gross counterparty credit risk (minor units)</li>
%%   <li>market_var       — value-at-risk estimate (basis points, 10000 = 100%)</li>
%%   <li>liquidity_lcr    — liquidity coverage ratio (basis points)</li>
%%   <li>capital_cet1     — CET1 capital ratio (basis points)</li>
%% </ul>
-module(cb_risk_capital).

-compile({parse_transform, ms_transform}).

-include("../../cb_ledger/include/cb_ledger.hrl").

-export([
    record_metric/1,
    get_metric/1,
    list_metrics/2,
    check_limit/3,
    current_breaches/0,
    allocate_buffer/1,
    get_buffer/1,
    list_buffers/0,
    release_buffer/1
]).

-spec record_metric(map()) -> {ok, #risk_metric{}} | {error, term()}.
record_metric(Params) ->
    Now = erlang:system_time(millisecond),
    LimitValue = maps:get(limit_value, Params, undefined),
    Value      = maps:get(value, Params),
    Breached   = LimitValue =/= undefined andalso Value > LimitValue,
    Metric = #risk_metric{
        metric_id   = uuid:get_v4(),
        account_id  = maps:get(account_id, Params, undefined),
        metric_type = maps:get(metric_type, Params),
        value       = Value,
        limit_value = LimitValue,
        breached    = Breached,
        measured_at = maps:get(measured_at, Params, Now),
        created_at  = Now
    },
    case mnesia:transaction(fun() -> mnesia:write(Metric) end) of
        {atomic, ok} -> {ok, Metric};
        {aborted, Reason} -> {error, Reason}
    end.

-spec get_metric(uuid()) -> {ok, #risk_metric{}} | {error, not_found}.
get_metric(MetricId) ->
    case mnesia:dirty_read(risk_metric, MetricId) of
        [M] -> {ok, M};
        []  -> {error, not_found}
    end.

-spec list_metrics(uuid() | undefined, risk_metric_type()) -> [#risk_metric{}].
list_metrics(undefined, MetricType) ->
    MatchSpec = ets:fun2ms(fun(M = #risk_metric{metric_type = T}) when T =:= MetricType -> M end),
    mnesia:dirty_select(risk_metric, MatchSpec);
list_metrics(AccountId, MetricType) ->
    MatchSpec = ets:fun2ms(fun(M = #risk_metric{account_id = A, metric_type = T})
                               when A =:= AccountId, T =:= MetricType -> M end),
    mnesia:dirty_select(risk_metric, MatchSpec).

%% @doc Check whether a given value breaches a limit for a metric type.
%%
%% Returns `{breach, Value, Limit}' if exceeded, or `ok' if within limit.
-spec check_limit(risk_metric_type(), integer(), integer()) ->
    ok | {breach, integer(), integer()}.
check_limit(_MetricType, Value, Limit) when Value > Limit ->
    {breach, Value, Limit};
check_limit(_MetricType, _Value, _Limit) ->
    ok.

%% @doc Return all risk metrics currently in breach.
-spec current_breaches() -> [#risk_metric{}].
current_breaches() ->
    MatchSpec = ets:fun2ms(fun(M = #risk_metric{breached = true}) -> M end),
    mnesia:dirty_select(risk_metric, MatchSpec).

-spec allocate_buffer(map()) -> {ok, #capital_buffer{}} | {error, term()}.
allocate_buffer(Params) ->
    Now = erlang:system_time(millisecond),
    Buffer = #capital_buffer{
        buffer_id    = uuid:get_v4(),
        buffer_type  = maps:get(buffer_type, Params),
        amount       = maps:get(amount, Params),
        currency     = maps:get(currency, Params),
        effective_at = maps:get(effective_at, Params, Now),
        updated_at   = Now
    },
    case mnesia:transaction(fun() -> mnesia:write(Buffer) end) of
        {atomic, ok} -> {ok, Buffer};
        {aborted, Reason} -> {error, Reason}
    end.

-spec get_buffer(uuid()) -> {ok, #capital_buffer{}} | {error, not_found}.
get_buffer(BufferId) ->
    case mnesia:dirty_read(capital_buffer, BufferId) of
        [B] -> {ok, B};
        []  -> {error, not_found}
    end.

-spec list_buffers() -> [#capital_buffer{}].
list_buffers() ->
    mnesia:dirty_select(capital_buffer, [{'_', [], ['$_']}]).

-spec release_buffer(uuid()) -> ok | {error, term()}.
release_buffer(BufferId) ->
    case mnesia:transaction(fun() -> mnesia:delete({capital_buffer, BufferId}) end) of
        {atomic, ok}      -> ok;
        {aborted, Reason} -> {error, Reason}
    end.
