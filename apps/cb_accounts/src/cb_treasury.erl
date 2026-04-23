%% @doc Treasury Liquidity and Cash Management (TASK-062)
%%
%% Manages liquidity positions, funding sources, cash flow forecasts,
%% and interbank placements for treasury operations.
%%
%% == Capabilities ==
%% <ul>
%%   <li>Create and manage treasury liquidity positions by source type</li>
%%   <li>Reserve (encumber) and release portions of a position</li>
%%   <li>Record cash flow forecasts for a given account and value date</li>
%%   <li>Interbank placement: open a term placement and close it at maturity</li>
%% </ul>
-module(cb_treasury).

-compile({parse_transform, ms_transform}).

-include("../../cb_ledger/include/cb_ledger.hrl").

-export([
    open_position/1,
    get_position/1,
    list_positions/1,
    encumber/3,
    release/3,
    close_position/1,
    record_forecast/1,
    get_forecasts/2,
    place_interbank/4,
    mature_placement/1
]).

-spec open_position(map()) -> {ok, #treasury_position{}} | {error, term()}.
open_position(Params) ->
    AccountId = maps:get(account_id, Params),
    SourceType = maps:get(source_type, Params),
    Currency   = maps:get(currency, Params),
    Amount     = maps:get(available_amount, Params),
    MaturityAt = maps:get(maturity_at, Params, undefined),
    Now = erlang:system_time(millisecond),
    Pos = #treasury_position{
        position_id       = uuid:get_v4(),
        account_id        = AccountId,
        source_type       = SourceType,
        currency          = Currency,
        available_amount  = Amount,
        encumbered_amount = 0,
        status            = active,
        maturity_at       = MaturityAt,
        created_at        = Now,
        updated_at        = Now
    },
    case mnesia:transaction(fun() -> mnesia:write(Pos) end) of
        {atomic, ok} -> {ok, Pos};
        {aborted, Reason} -> {error, Reason}
    end.

-spec get_position(uuid()) -> {ok, #treasury_position{}} | {error, not_found}.
get_position(PositionId) ->
    case mnesia:dirty_read(treasury_position, PositionId) of
        [Pos] -> {ok, Pos};
        []    -> {error, not_found}
    end.

-spec list_positions(uuid()) -> [#treasury_position{}].
list_positions(AccountId) ->
    MatchSpec = ets:fun2ms(fun(P = #treasury_position{account_id = A}) when A =:= AccountId -> P end),
    mnesia:dirty_select(treasury_position, MatchSpec).

-spec encumber(uuid(), amount(), binary()) -> {ok, #treasury_position{}} | {error, term()}.
encumber(PositionId, Amount, _Reason) when Amount > 0 ->
    F = fun() ->
        case mnesia:wread({treasury_position, PositionId}) of
            [Pos] ->
                Free = Pos#treasury_position.available_amount,
                if Free < Amount ->
                    mnesia:abort(insufficient_available);
                true ->
                    Now = erlang:system_time(millisecond),
                    Updated = Pos#treasury_position{
                        available_amount  = Free - Amount,
                        encumbered_amount = Pos#treasury_position.encumbered_amount + Amount,
                        updated_at        = Now
                    },
                    mnesia:write(Updated),
                    Updated
                end;
            [] -> mnesia:abort(not_found)
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Updated} -> {ok, Updated};
        {aborted, Reason} -> {error, Reason}
    end;
encumber(_PositionId, Amount, _Reason) when Amount =< 0 ->
    {error, invalid_amount}.

-spec release(uuid(), amount(), binary()) -> {ok, #treasury_position{}} | {error, term()}.
release(PositionId, Amount, _Reason) when Amount > 0 ->
    F = fun() ->
        case mnesia:wread({treasury_position, PositionId}) of
            [Pos] ->
                Enc = Pos#treasury_position.encumbered_amount,
                if Enc < Amount ->
                    mnesia:abort(insufficient_encumbered);
                true ->
                    Now = erlang:system_time(millisecond),
                    Updated = Pos#treasury_position{
                        available_amount  = Pos#treasury_position.available_amount + Amount,
                        encumbered_amount = Enc - Amount,
                        updated_at        = Now
                    },
                    mnesia:write(Updated),
                    Updated
                end;
            [] -> mnesia:abort(not_found)
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Updated} -> {ok, Updated};
        {aborted, Reason} -> {error, Reason}
    end;
release(_PositionId, Amount, _Reason) when Amount =< 0 ->
    {error, invalid_amount}.

-spec close_position(uuid()) -> ok | {error, term()}.
close_position(PositionId) ->
    F = fun() ->
        case mnesia:wread({treasury_position, PositionId}) of
            [Pos] ->
                Now = erlang:system_time(millisecond),
                mnesia:write(Pos#treasury_position{status = closed, updated_at = Now});
            [] -> mnesia:abort(not_found)
        end
    end,
    case mnesia:transaction(F) of
        {atomic, ok}      -> ok;
        {aborted, Reason} -> {error, Reason}
    end.

-spec record_forecast(map()) -> {ok, #cash_forecast{}} | {error, term()}.
record_forecast(Params) ->
    AccountId    = maps:get(account_id, Params),
    Currency     = maps:get(currency, Params),
    ForecastDate = maps:get(forecast_date, Params),
    Inflow       = maps:get(inflow_amount, Params, 0),
    Outflow      = maps:get(outflow_amount, Params, 0),
    Now = erlang:system_time(millisecond),
    FC = #cash_forecast{
        forecast_id    = uuid:get_v4(),
        account_id     = AccountId,
        currency       = Currency,
        forecast_date  = ForecastDate,
        inflow_amount  = Inflow,
        outflow_amount = Outflow,
        net_amount     = Inflow - Outflow,
        created_at     = Now
    },
    case mnesia:transaction(fun() -> mnesia:write(FC) end) of
        {atomic, ok} -> {ok, FC};
        {aborted, Reason} -> {error, Reason}
    end.

-spec get_forecasts(uuid(), currency()) -> [#cash_forecast{}].
get_forecasts(AccountId, Currency) ->
    MatchSpec = ets:fun2ms(fun(F = #cash_forecast{account_id = A, currency = C})
                               when A =:= AccountId, C =:= Currency -> F end),
    mnesia:dirty_select(cash_forecast, MatchSpec).

%% @doc Open an interbank placement by creating a position with source_type=interbank.
-spec place_interbank(uuid(), currency(), amount(), timestamp_ms()) ->
    {ok, #treasury_position{}} | {error, term()}.
place_interbank(AccountId, Currency, Amount, MaturityAt) ->
    open_position(#{
        account_id       => AccountId,
        source_type      => interbank,
        currency         => Currency,
        available_amount => Amount,
        maturity_at      => MaturityAt
    }).

%% @doc Close a matured interbank placement position.
-spec mature_placement(uuid()) -> ok | {error, term()}.
mature_placement(PositionId) ->
    close_position(PositionId).
