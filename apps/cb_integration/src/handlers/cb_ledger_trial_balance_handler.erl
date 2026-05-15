%% @doc Trial Balance HTTP Handler
%%
%% Endpoints:
%%   GET /api/v1/ledger/trial-balance
%%     - ?currency=USD&as_of_date=YYYY-MM-DD : per-account breakdown (new)
%%     - ?currency=USD                    : aggregate totals (legacy)
%%
%% Per-account response:
%%   { accounts: [{account_id, account_name, currency,
%%                 debit_balance_minor, credit_balance_minor}],
%%     generated_at }
%%
%% Legacy response:
%%   { currency, total_debits, total_credits, balanced, as_of }
%%
-module(cb_ledger_trial_balance_handler).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    handle(Method, Req, State).

handle(<<"GET">>, Req, State) ->
    Qs = cowboy_req:parse_qs(Req),
    Currency = proplists:get_value(<<"currency">>, Qs),
    case Currency of
        undefined ->
            reply(400, #{error => bad_request,
                         message => <<"Query parameter 'currency' is required">>}, Req, State);
        CurrencyBin ->
            CurrencyAtom = binary_to_existing_atom(CurrencyBin, utf8),
            AsOfDate = case proplists:get_value(<<"as_of_date">>, Qs) of
                undefined -> undefined;
                DateBin   -> parse_date(DateBin)
            end,
            %% Use per-account breakdown when as_of_date is provided,
            %% otherwise fall back to aggregate totals for backward compat.
            case AsOfDate of
                undefined ->
                    %% Legacy aggregate response
                    case cb_ledger:get_trial_balance(CurrencyAtom) of
                        {ok, Result} ->
                            reply(200, Result, Req, State);
                        {error, Reason} ->
                            error_reply(Reason, Req, State)
                    end;
                Date when is_tuple(Date) ->
                    case cb_trial_balance:generate(CurrencyAtom, #{as_of_date => Date}) of
                        {ok, Result} ->
                            reply(200, Result, Req, State);
                        {error, Reason} ->
                            error_reply(Reason, Req, State)
                    end
            end
    end;

handle(<<"OPTIONS">>, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};

handle(_, Req, State) ->
    reply(405, #{error => method_not_allowed, message => <<"Method not allowed">>}, Req, State).

%% @private Parse YYYY-MM-DD to calendar:date().
parse_date(Bin) when is_binary(Bin) ->
    parse_date(binary_to_list(Bin));
parse_date(Str) when is_list(Str) ->
    case string:split(Str, "-") of
        [YStr, MStr, DStr] ->
            {list_to_integer(YStr), list_to_integer(MStr), list_to_integer(DStr)};
        _ ->
            undefined
    end;
parse_date(_) ->
    undefined.

reply(Status, Body, Req, State) ->
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    Req2 = cowboy_req:reply(Status, Headers, jsone:encode(Body), Req),
    {ok, Req2, State}.

error_reply(Reason, Req, State) ->
    {Status, ErrorAtom, Message} = cb_http_errors:to_response(Reason),
    reply(Status, #{error => ErrorAtom, message => Message}, Req, State).
