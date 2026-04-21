%% @doc Parties (Customers) Handler
%%
%% Handler for the `/api/v1/parties` endpoint which manages customer/party records.
%%
%% <h2>What is a Party?</h2>
%%
%% In core banking terminology, a "party" represents a customer - the legal entity
%% that owns accounts and conducts transactions. A party can be:
%% <ul>
%%   <li>An individual person</li>
%%   <li>A corporation or business entity</li>
%%   <li>A government agency</li>
%% </ul>
%%
%% <h2>REST API Endpoints</h2>
%%
%% <ul>
%%   <li><b>GET /api/v1/parties</b> - List all parties with pagination</li>
%%   <li><b>POST /api/v1/parties</b> - Create a new party</li>
%%   <li><b>OPTIONS /api/v1/parties</b> - CORS preflight</li>
%% </ul>
%%
%% <h2>GET - List Parties</h2>
%%
%% Returns a paginated list of parties. Query parameters:
%% <ul>
%%   <li><code>page</code> - Page number (default: 1)</li>
%%   <li><code>page_size</code> - Items per page (default: 20)</li>
%% </ul>
%%
%% <h2>POST - Create Party</h2>
%%
%% Creates a new party. Required fields:
%% <ul>
%%   <li><code>full_name</code> - Full legal name of the party</li>
%%   <li><code>email</code> - Contact email address</li>
%% </ul>
%%
%% On success, returns 201 Created with party details.
%%
%% @see cb_party
-module(cb_parties_handler).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    handle(Method, Req, State).

handle(<<"POST">>, Req, State) ->
    %% Create party
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(Body) of
        {ok, #{<<"full_name">> := FullName, <<"email">> := Email}, _} ->
            case cb_party:create_party(FullName, Email) of
                {ok, Party} ->
                    Resp = party_to_json(Party),
                    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
                    Req3 = cowboy_req:reply(201, Headers, jsone:encode(Resp), Req2),
                    {ok, Req3, State};
                {error, Reason} ->
                    {Status, ErrorAtom, Message} = cb_http_errors:to_response(Reason),
                    Resp = #{error => ErrorAtom, message => Message},
                    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
                    Req3 = cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req2),
                    {ok, Req3, State}
            end;
        _ ->
            {Status, ErrorAtom, Message} = cb_http_errors:to_response(missing_required_field),
            Resp = #{error => ErrorAtom, message => Message},
            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
            Req3 = cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req2),
            {ok, Req3, State}
    end;

handle(<<"GET">>, Req, State) ->
    %% List parties
    Qs = cowboy_req:parse_qs(Req),
    Page = binary_to_integer(proplists:get_value(<<"page">>, Qs, <<"1">>)),
    PageSize = binary_to_integer(proplists:get_value(<<"page_size">>, Qs, <<"20">>)),
    case cb_party:list_parties(Page, PageSize) of
        {ok, Result} ->
            Resp = #{
                items => [party_to_json(P) || P <- maps:get(items, Result)],
                total => maps:get(total, Result),
                page => maps:get(page, Result),
                page_size => maps:get(page_size, Result)
            },
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

handle(<<"OPTIONS">>, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};

handle(_, Req, State) ->
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    Req2 = cowboy_req:reply(405, Headers, <<"{\"error\": \"method_not_allowed\"}">>, Req),
    {ok, Req2, State}.

party_to_json(Party) ->
    #{
        party_id => Party#party.party_id,
        full_name => Party#party.full_name,
        email => Party#party.email,
        status => Party#party.status,
        kyc_status => Party#party.kyc_status,
        onboarding_status => Party#party.onboarding_status,
        review_notes => Party#party.review_notes,
        doc_refs => Party#party.doc_refs,
        created_at => Party#party.created_at,
        updated_at => Party#party.updated_at
    }.
