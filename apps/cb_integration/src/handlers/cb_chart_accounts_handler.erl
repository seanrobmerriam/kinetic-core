%% @doc Chart of Accounts HTTP Handler
%%
%% Handles the following endpoints:
%%
%%   GET  /api/v1/ledger/chart-of-accounts          - list all accounts
%%   GET  /api/v1/ledger/chart-of-accounts/:code    - get one account
%%   POST /api/v1/ledger/chart-of-accounts          - create an account
%%   OPTIONS                                         - CORS preflight
%%
%% The chart of accounts defines the GL hierarchy (asset, liability, equity,
%% revenue, expense) and is the foundation for trial balance and GL reporting.
-module(cb_chart_accounts_handler).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    Code   = cowboy_req:binding(code, Req),
    handle(Method, Code, Req, State).

handle(<<"GET">>, undefined, Req, State) ->
    case cb_ledger:get_chart_accounts() of
        {ok, Accounts} ->
            Items = [chart_account_to_json(A) || A <- Accounts],
            Resp  = #{items => Items, total => length(Items)},
            reply(200, Resp, Req, State);
        {error, Reason} ->
            error_reply(Reason, Req, State)
    end;

handle(<<"GET">>, Code, Req, State) ->
    case cb_ledger:get_chart_account(Code) of
        {ok, Account} ->
            reply(200, chart_account_to_json(Account), Req, State);
        {error, Reason} ->
            error_reply(Reason, Req, State)
    end;

handle(<<"POST">>, undefined, Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:decode(Body, [{object_format, map}]) of
        #{<<"code">> := Code, <<"name">> := Name, <<"account_type">> := TypeBin} = Params ->
            Type       = binary_to_existing_atom(TypeBin, utf8),
            ParentCode = maps:get(<<"parent_code">>, Params, undefined),
            case cb_ledger:create_chart_account(Code, Name, Type, ParentCode) of
                {ok, Account} ->
                    reply(201, chart_account_to_json(Account), Req2, State);
                {error, Reason} ->
                    error_reply(Reason, Req2, State)
            end;
        _ ->
            reply(400, #{error => bad_request, message => <<"Missing required fields: code, name, account_type">>}, Req2, State)
    end;

handle(<<"OPTIONS">>, _Code, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};

handle(_, _Code, Req, State) ->
    reply(405, #{error => method_not_allowed, message => <<"Method not allowed">>}, Req, State).

%% =============================================================================
%% Internal helpers
%% =============================================================================

reply(Status, Body, Req, State) ->
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    Req2 = cowboy_req:reply(Status, Headers, jsone:encode(Body), Req),
    {ok, Req2, State}.

error_reply(Reason, Req, State) ->
    {Status, ErrorAtom, Message} = cb_http_errors:to_response(Reason),
    reply(Status, #{error => ErrorAtom, message => Message}, Req, State).

chart_account_to_json(A) ->
    #{
        code         => A#chart_account.code,
        name         => A#chart_account.name,
        account_type => A#chart_account.account_type,
        parent_code  => A#chart_account.parent_code,
        status       => A#chart_account.status,
        created_at   => A#chart_account.created_at,
        updated_at   => A#chart_account.updated_at
    }.
