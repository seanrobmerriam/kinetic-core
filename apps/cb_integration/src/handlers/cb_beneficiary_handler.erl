%% @doc Beneficiary Handler
%%
%% Handler for `/api/v1/beneficiaries` CRUD operations.
%%
%% <h2>REST API Endpoints</h2>
%%
%% <ul>
%%   <li><b>POST /api/v1/beneficiaries</b> — Create a new beneficiary</li>
%%   <li><b>GET /api/v1/beneficiaries</b> — List beneficiaries (optional ?party_id= filter)</li>
%%   <li><b>GET /api/v1/beneficiaries/:beneficiary_id</b> — Get a specific beneficiary</li>
%%   <li><b>PATCH /api/v1/beneficiaries/:beneficiary_id</b> — Update beneficiary</li>
%%   <li><b>DELETE /api/v1/beneficiaries/:beneficiary_id</b> — Soft-delete beneficiary</li>
%%   <li><b>OPTIONS</b> — CORS preflight</li>
%% </ul>
%%
-module(cb_beneficiary_handler).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    BeneficiaryId = cowboy_req:binding(beneficiary_id, Req),
    handle(Method, BeneficiaryId, Req, State).

%% POST /api/v1/beneficiaries — create a new beneficiary
handle(<<"POST">>, undefined, Req, State) ->
    case jsone:decode(Req) of
        {ok, Body, Req1} ->
            PartyId = maps:get(<<"party_id">>, Body),
            Name = maps:get(<<"name">>, Body),
            AccountNumber = maps:get(<<"account_number">>, Body),
            BankCode = maps:get(<<"bank_code">>, Body),
            CurrencyBin = maps:get(<<"currency">>, Body),
            Country = maps:get(<<"country">>, Body),
            case cb_validate:currency(CurrencyBin) of
                {error, CurrErr} ->
                    {ErrStatus, ErrAtom, ErrMsg} = cb_http_errors:to_response(CurrErr),
                    ErrResp = #{error => ErrAtom, message => ErrMsg},
                    ErrHeaders = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
                    Req2 = cowboy_req:reply(ErrStatus, ErrHeaders, jsone:encode(ErrResp), Req1),
                    {ok, Req2, State};
                ok ->
                    Currency = binary_to_existing_atom(CurrencyBin, utf8),
                    case cb_beneficiary:create_beneficiary(PartyId, Name, AccountNumber, BankCode, Currency, Country) of
                        {ok, Beneficiary} ->
                            Resp = beneficiary_to_json(Beneficiary),
                            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
                            Req2 = cowboy_req:reply(201, Headers, jsone:encode(Resp), Req1),
                            {ok, Req2, State};
                        {error, Reason} ->
                            {Status, ErrorAtom, Message} = cb_http_errors:to_response(Reason),
                            Resp = #{error => ErrorAtom, message => Message},
                            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
                            Req2 = cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req1),
                            {ok, Req2, State}
                    end
            end;
        {error, _} ->
            {Code, Hdrs, Body} = cb_http_errors:to_response_with_metrics(bad_request),
            Req2 = cowboy_req:reply(Code, Hdrs, Body, Req),
            {ok, Req2, State}
    end;

%% GET /api/v1/beneficiaries — list all (optionally filtered by party_id)
handle(<<"GET">>, undefined, Req, State) ->
    Qs = cowboy_req:parse_qs(Req),
    PartyId = proplists:get_value(<<"party_id">>, Qs, undefined),
    Beneficiaries = cb_beneficiary:list_beneficiaries(PartyId),
    Resp = [beneficiary_to_json(B) || B <- Beneficiaries],
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    Req2 = cowboy_req:reply(200, Headers, jsone:encode(Resp), Req),
    {ok, Req2, State};

%% GET /api/v1/beneficiaries/:beneficiary_id — get a specific beneficiary
handle(<<"GET">>, BeneficiaryId, Req, State) ->
    case cb_beneficiary:get_beneficiary(BeneficiaryId) of
        {ok, Beneficiary} ->
            Resp = beneficiary_to_json(Beneficiary),
            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
            Req2 = cowboy_req:reply(200, Headers, jsone:encode(Resp), Req),
            {ok, Req2, State};
        {error, Reason} ->
            {Status, ErrorAtom, Message} = cb_http_errors:to_response(Reason),
            Resp = #{error => ErrorAtom, message => Message},
            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
            Req2 = cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req),
            {ok, Req2, State}
    end;

%% PATCH /api/v1/beneficiaries/:beneficiary_id — update beneficiary
handle(<<"PATCH">>, BeneficiaryId, Req, State) ->
    case jsone:decode(Req) of
        {ok, Body, Req1} ->
            Updates = #{
                name           => maps:get(<<"name">>, Body, undefined),
                account_number => maps:get(<<"account_number">>, Body, undefined),
                bank_code      => maps:get(<<"bank_code">>, Body, undefined),
                currency       => case maps:get(<<"currency">>, Body, undefined) of
                    undefined -> undefined;
                    C -> binary_to_existing_atom(C, utf8)
                end,
                country        => maps:get(<<"country">>, Body, undefined),
                is_active      => maps:get(<<"is_active">>, Body, undefined)
            },
            UpdatesClean = maps:filter(fun(_, V) -> V =/= undefined end, Updates),
            case cb_beneficiary:update_beneficiary(BeneficiaryId, UpdatesClean) of
                {ok, Beneficiary} ->
                    Resp = beneficiary_to_json(Beneficiary),
                    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
                    Req2 = cowboy_req:reply(200, Headers, jsone:encode(Resp), Req1),
                    {ok, Req2, State};
                {error, Reason} ->
                    {Status, ErrorAtom, Message} = cb_http_errors:to_response(Reason),
                    Resp = #{error => ErrorAtom, message => Message},
                    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
                    Req2 = cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req1),
                    {ok, Req2, State}
            end;
        {error, _} ->
            {Code, Hdrs, Body} = cb_http_errors:to_response_with_metrics(bad_request),
            Req2 = cowboy_req:reply(Code, Hdrs, Body, Req),
            {ok, Req2, State}
    end;

%% DELETE /api/v1/beneficiaries/:beneficiary_id — soft-delete beneficiary
handle(<<"DELETE">>, BeneficiaryId, Req, State) ->
    case cb_beneficiary:delete_beneficiary(BeneficiaryId) of
        {ok, Beneficiary} ->
            Resp = beneficiary_to_json(Beneficiary),
            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
            Req2 = cowboy_req:reply(200, Headers, jsone:encode(Resp), Req),
            {ok, Req2, State};
        {error, Reason} ->
            {Status, ErrorAtom, Message} = cb_http_errors:to_response(Reason),
            Resp = #{error => ErrorAtom, message => Message},
            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
            Req2 = cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req),
            {ok, Req2, State}
    end;

handle(<<"OPTIONS">>, _BeneficiaryId, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};

handle(_, _BeneficiaryId, Req, State) ->
    {_Code405, _Hdrs405, _Body405} = cb_http_errors:to_response_with_metrics(method_not_allowed),
    Req2 = cowboy_req:reply(_Code405, _Hdrs405, _Body405, Req),
    {ok, Req2, State}.

beneficiary_to_json(B) ->
    #{
        beneficiary_id => B#beneficiary.beneficiary_id,
        party_id => B#beneficiary.party_id,
        name => B#beneficiary.name,
        account_number => B#beneficiary.account_number,
        bank_code => B#beneficiary.bank_code,
        currency => atom_to_binary(B#beneficiary.currency, utf8),
        country => B#beneficiary.country,
        is_active => B#beneficiary.is_active,
        created_at => B#beneficiary.created_at,
        updated_at => B#beneficiary.updated_at
    }.