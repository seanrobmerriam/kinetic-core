%% @doc Account Holds Handler
%%
%% Handler for the `/api/v1/accounts/:account_id/holds` endpoints.
%%
%% <h2>REST API Endpoints</h2>
%%
%% <ul>
%%   <li><b>GET /api/v1/accounts/:account_id/holds</b> - List all holds for an account</li>
%%   <li><b>POST /api/v1/accounts/:account_id/holds</b> - Place a new hold on an account</li>
%%   <li><b>DELETE /api/v1/accounts/:account_id/holds/:hold_id</b> - Release a hold</li>
%%   <li><b>OPTIONS ...</b> - CORS preflight</li>
%% </ul>
%%
%% @see cb_account_holds
-module(cb_account_holds_handler).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method    = cowboy_req:method(Req),
    AccountId = cowboy_req:binding(account_id, Req),
    HoldId    = cowboy_req:binding(hold_id, Req, undefined),
    handle(Method, AccountId, HoldId, Req, State).

%% GET /api/v1/accounts/:account_id/holds
handle(<<"GET">>, AccountId, _HoldId, Req, State) ->
    case cb_account_holds:list_holds(AccountId) of
        {ok, Holds} ->
            Items = [hold_to_json(H) || H <- Holds],
            Resp  = #{items => Items, total => length(Items)},
            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
            Req2 = cowboy_req:reply(200, Headers, jsone:encode(Resp), Req),
            {ok, Req2, State};
        {error, Reason} ->
            reply_error(Reason, Req, State)
    end;

%% POST /api/v1/accounts/:account_id/holds
handle(<<"POST">>, AccountId, _HoldId, Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(Body) of
        {ok, Decoded, _} ->
            Amount    = maps:get(<<"amount">>, Decoded, undefined),
            Reason    = maps:get(<<"reason">>, Decoded, undefined),
            ExpiresAt = maps:get(<<"expires_at">>, Decoded, undefined),
            case {Amount, Reason} of
                {undefined, _} ->
                    reply_error(missing_required_field, Req2, State);
                {_, undefined} ->
                    reply_error(missing_required_field, Req2, State);
                {A, R} when is_integer(A), is_binary(R) ->
                    case cb_account_holds:place_hold(AccountId, A, R, ExpiresAt) of
                        {ok, Hold} ->
                            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
                            Req3 = cowboy_req:reply(201, Headers, jsone:encode(hold_to_json(Hold)), Req2),
                            {ok, Req3, State};
                        {error, HoldError} ->
                            reply_error(HoldError, Req2, State)
                    end;
                _ ->
                    reply_error(missing_required_field, Req2, State)
            end;
        _ ->
            reply_error(invalid_json, Req2, State)
    end;

%% DELETE /api/v1/accounts/:account_id/holds/:hold_id
handle(<<"DELETE">>, _AccountId, HoldId, Req, State) when HoldId =/= undefined ->
    case cb_account_holds:release_hold(HoldId) of
        {ok, Hold} ->
            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
            Req2 = cowboy_req:reply(200, Headers, jsone:encode(hold_to_json(Hold)), Req),
            {ok, Req2, State};
        {error, Reason} ->
            reply_error(Reason, Req, State)
    end;

handle(<<"DELETE">>, _AccountId, undefined, Req, State) ->
    reply_error(missing_required_field, Req, State);

handle(<<"OPTIONS">>, _AccountId, _HoldId, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};

handle(_Method, _AccountId, _HoldId, Req, State) ->
    {_Code405, _Hdrs405, _Body405} = cb_http_errors:to_response_with_metrics(method_not_allowed),
    Req2 = cowboy_req:reply(_Code405, _Hdrs405, _Body405, Req),
    {ok, Req2, State}.

%% =============================================================================
%% Internal Helpers
%% =============================================================================

reply_error(Reason, Req, State) ->
    {Status, ErrorAtom, Message} = cb_http_errors:to_response(Reason),
    Resp    = #{error => ErrorAtom, message => Message},
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    Req2    = cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req),
    {ok, Req2, State}.

hold_to_json(Hold) ->
    Base = #{
        hold_id    => Hold#account_hold.hold_id,
        account_id => Hold#account_hold.account_id,
        amount     => Hold#account_hold.amount,
        reason     => Hold#account_hold.reason,
        status     => Hold#account_hold.status,
        placed_at  => Hold#account_hold.placed_at
    },
    Base1 = case Hold#account_hold.released_at of
        undefined -> Base;
        RelAt     -> Base#{released_at => RelAt}
    end,
    case Hold#account_hold.expires_at of
        undefined -> Base1;
        ExpAt     -> Base1#{expires_at => ExpAt}
    end.
