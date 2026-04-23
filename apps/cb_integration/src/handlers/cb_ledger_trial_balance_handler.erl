%% @doc Trial Balance HTTP Handler
%%
%% Endpoint:
%%   GET /api/v1/ledger/trial-balance?currency=USD
%%
%% Returns the sum of all debit entries and credit entries for the requested
%% currency, along with a `balanced' flag confirming they are equal.
%% A balanced trial balance is a prerequisite for correct financial statements.
%%
%% Query parameters:
%%   - currency (required): ISO 4217 code, e.g. USD
-module(cb_ledger_trial_balance_handler).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    handle(Method, Req, State).

handle(<<"GET">>, Req, State) ->
    Qs       = cowboy_req:parse_qs(Req),
    Currency = proplists:get_value(<<"currency">>, Qs),
    case Currency of
        undefined ->
            reply(400, #{error => bad_request,
                         message => <<"Query parameter 'currency' is required">>}, Req, State);
        CurrencyBin ->
            CurrencyAtom = binary_to_existing_atom(CurrencyBin, utf8),
            case cb_ledger:get_trial_balance(CurrencyAtom) of
                {ok, Result} ->
                    reply(200, Result, Req, State);
                {error, Reason} ->
                    error_reply(Reason, Req, State)
            end
    end;

handle(<<"OPTIONS">>, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};

handle(_, Req, State) ->
    reply(405, #{error => method_not_allowed, message => <<"Method not allowed">>}, Req, State).

reply(Status, Body, Req, State) ->
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    Req2 = cowboy_req:reply(Status, Headers, jsone:encode(Body), Req),
    {ok, Req2, State}.

error_reply(Reason, Req, State) ->
    {Status, ErrorAtom, Message} = cb_http_errors:to_response(Reason),
    reply(Status, #{error => ErrorAtom, message => Message}, Req, State).
