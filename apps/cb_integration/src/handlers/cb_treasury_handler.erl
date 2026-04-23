%% @doc HTTP handler for Treasury Liquidity API (TASK-062)
%%
%% Routes:
%%   POST   /api/v1/treasury/positions           — open_position
%%   GET    /api/v1/treasury/positions           — list_positions (query: account_id)
%%   GET    /api/v1/treasury/positions/:id       — get_position
%%   POST   /api/v1/treasury/positions/:id/encumber — encumber
%%   POST   /api/v1/treasury/positions/:id/release  — release
%%   DELETE /api/v1/treasury/positions/:id       — close_position
%%   POST   /api/v1/treasury/forecasts           — record_forecast
%%   GET    /api/v1/treasury/forecasts           — get_forecasts (query: account_id,currency)
%%   POST   /api/v1/treasury/placements          — place_interbank
%%   DELETE /api/v1/treasury/placements/:id      — mature_placement
-module(cb_treasury_handler).

-include("../../cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

init(Req0, State) ->
    Method  = cowboy_req:method(Req0),
    PathInfo = cowboy_req:path_info(Req0),
    {ok, Req} = handle(Method, PathInfo, Req0),
    {ok, Req, State}.

handle(<<"POST">>, undefined, Req0) ->
    route_post(cowboy_req:path(Req0), Req0);
handle(<<"POST">>, [], Req0) ->
    route_post(cowboy_req:path(Req0), Req0);
handle(<<"GET">>, undefined, Req0) ->
    route_get(cowboy_req:path(Req0), Req0);
handle(<<"GET">>, [], Req0) ->
    route_get(cowboy_req:path(Req0), Req0);
handle(<<"GET">>, [Id], Req0) ->
    route_get_id(cowboy_req:path(Req0), Id, Req0);
handle(<<"POST">>, [Id, Action], Req0) ->
    route_post_action(cowboy_req:path(Req0), Id, Action, Req0);
handle(<<"DELETE">>, [Id], Req0) ->
    route_delete(cowboy_req:path(Req0), Id, Req0);
handle(_, _, Req0) ->
    cb_http_util:reply_error(405, <<"method_not_allowed">>, Req0).

route_post(Path, Req0) ->
    case binary:match(Path, <<"/forecasts">>) of
        {_, _} -> handle_record_forecast(Req0);
        nomatch ->
            case binary:match(Path, <<"/placements">>) of
                {_, _} -> handle_place_interbank(Req0);
                nomatch -> handle_open_position(Req0)
            end
    end.

route_get(Path, Req0) ->
    case binary:match(Path, <<"/forecasts">>) of
        {_, _} -> handle_get_forecasts(Req0);
        nomatch -> handle_list_positions(Req0)
    end.

route_get_id(_Path, Id, Req0) ->
    handle_get_position(Id, Req0).

route_post_action(_Path, Id, <<"encumber">>, Req0) ->
    handle_encumber(Id, Req0);
route_post_action(_Path, Id, <<"release">>, Req0) ->
    handle_release(Id, Req0);
route_post_action(_Path, _Id, _Action, Req0) ->
    cb_http_util:reply_error(404, <<"not_found">>, Req0).

route_delete(Path, Id, Req0) ->
    case binary:match(Path, <<"/placements">>) of
        {_, _} -> handle_mature_placement(Id, Req0);
        nomatch -> handle_close_position(Id, Req0)
    end.

handle_open_position(Req0) ->
    {ok, Body, Req1} = cowboy_req:read_body(Req0),
    Params = cb_http_util:decode_json(Body),
    case cb_treasury:open_position(Params) of
        {ok, Pos} ->
            cb_http_util:reply_json(201, position_to_map(Pos), Req1);
        {error, Reason} ->
            cb_http_util:reply_error(422, Reason, Req1)
    end.

handle_get_position(PositionId, Req0) ->
    case cb_treasury:get_position(PositionId) of
        {ok, Pos} ->
            cb_http_util:reply_json(200, position_to_map(Pos), Req0);
        {error, not_found} ->
            cb_http_util:reply_error(404, <<"not_found">>, Req0)
    end.

handle_list_positions(Req0) ->
    QS      = cowboy_req:parse_qs(Req0),
    AccountId = proplists:get_value(<<"account_id">>, QS, undefined),
    Positions = cb_treasury:list_positions(AccountId),
    cb_http_util:reply_json(200, [position_to_map(P) || P <- Positions], Req0).

handle_encumber(PositionId, Req0) ->
    {ok, Body, Req1} = cowboy_req:read_body(Req0),
    Params = cb_http_util:decode_json(Body),
    Amount = maps:get(<<"amount">>, Params),
    Reason = maps:get(<<"reason">>, Params, <<>>),
    case cb_treasury:encumber(PositionId, Amount, Reason) of
        {ok, Pos} ->
            cb_http_util:reply_json(200, position_to_map(Pos), Req1);
        {error, R} ->
            cb_http_util:reply_error(422, R, Req1)
    end.

handle_release(PositionId, Req0) ->
    {ok, Body, Req1} = cowboy_req:read_body(Req0),
    Params = cb_http_util:decode_json(Body),
    Amount = maps:get(<<"amount">>, Params),
    Reason = maps:get(<<"reason">>, Params, <<>>),
    case cb_treasury:release(PositionId, Amount, Reason) of
        {ok, Pos} ->
            cb_http_util:reply_json(200, position_to_map(Pos), Req1);
        {error, R} ->
            cb_http_util:reply_error(422, R, Req1)
    end.

handle_close_position(PositionId, Req0) ->
    case cb_treasury:close_position(PositionId) of
        ok             -> cb_http_util:reply_json(200, #{status => <<"closed">>}, Req0);
        {error, Reason} -> cb_http_util:reply_error(422, Reason, Req0)
    end.

handle_record_forecast(Req0) ->
    {ok, Body, Req1} = cowboy_req:read_body(Req0),
    Params = cb_http_util:decode_json(Body),
    case cb_treasury:record_forecast(Params) of
        {ok, FC} ->
            cb_http_util:reply_json(201, forecast_to_map(FC), Req1);
        {error, Reason} ->
            cb_http_util:reply_error(422, Reason, Req1)
    end.

handle_get_forecasts(Req0) ->
    QS        = cowboy_req:parse_qs(Req0),
    AccountId = proplists:get_value(<<"account_id">>, QS, undefined),
    Currency  = binary_to_existing_atom(
                    proplists:get_value(<<"currency">>, QS, <<"USD">>), utf8),
    Forecasts = cb_treasury:get_forecasts(AccountId, Currency),
    cb_http_util:reply_json(200, [forecast_to_map(F) || F <- Forecasts], Req0).

handle_place_interbank(Req0) ->
    {ok, Body, Req1} = cowboy_req:read_body(Req0),
    Params    = cb_http_util:decode_json(Body),
    AccountId = maps:get(<<"account_id">>, Params),
    Currency  = binary_to_existing_atom(maps:get(<<"currency">>, Params), utf8),
    Amount    = maps:get(<<"amount">>, Params),
    Maturity  = maps:get(<<"maturity_at">>, Params),
    case cb_treasury:place_interbank(AccountId, Currency, Amount, Maturity) of
        {ok, Pos} ->
            cb_http_util:reply_json(201, position_to_map(Pos), Req1);
        {error, Reason} ->
            cb_http_util:reply_error(422, Reason, Req1)
    end.

handle_mature_placement(PositionId, Req0) ->
    case cb_treasury:mature_placement(PositionId) of
        ok              -> cb_http_util:reply_json(200, #{status => <<"matured">>}, Req0);
        {error, Reason} -> cb_http_util:reply_error(422, Reason, Req0)
    end.

%%====================================================================
%% Serialization
%%====================================================================

position_to_map(#treasury_position{
    position_id = Id, account_id = AccountId, source_type = Src,
    currency = Ccy, available_amount = Avail, encumbered_amount = Enc,
    status = Status, maturity_at = Maturity, created_at = CreatedAt, updated_at = UpdatedAt
}) ->
    #{
        position_id       => Id,
        account_id        => AccountId,
        source_type       => Src,
        currency          => Ccy,
        available_amount  => Avail,
        encumbered_amount => Enc,
        status            => Status,
        maturity_at       => Maturity,
        created_at        => CreatedAt,
        updated_at        => UpdatedAt
    }.

forecast_to_map(#cash_forecast{
    forecast_id = Id, account_id = AccountId, currency = Ccy,
    forecast_date = FD, inflow_amount = In, outflow_amount = Out,
    net_amount = Net, created_at = CreatedAt
}) ->
    #{
        forecast_id    => Id,
        account_id     => AccountId,
        currency       => Ccy,
        forecast_date  => FD,
        inflow_amount  => In,
        outflow_amount => Out,
        net_amount     => Net,
        created_at     => CreatedAt
    }.
