%% @doc Single Party (Customer) Handler
%%
%% Handler for the `/api/v1/parties/:party_id` endpoint for individual party operations.
%%
%% <h2>REST API Endpoints</h2>
%%
%% <ul>
%%   <li><b>GET /api/v1/parties/:party_id</b> - Get party details</li>
%%   <li><b>OPTIONS /api/v1/parties/:party_id</b> - CORS preflight</li>
%% </ul>
%%
%% <h2>GET - Get Party</h2>
%%
%% Retrieves detailed information about a specific party by their ID.
%% The party_id is extracted from the URL path binding.
%%
%% Response includes:
%% <ul>
%%   <li>party_id - Unique identifier</li>
%%   <li>full_name - Party's full legal name</li>
%%   <li>email - Contact email</li>
%%   <li>status - Party status (active, suspended, closed)</li>
%%   <li>created_at - Creation timestamp</li>
%%   <li>updated_at - Last modification timestamp</li>
%% </ul>
%%
%% @see cb_party
%% @see cb_parties_handler
-module(cb_party_handler).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    PartyId = cowboy_req:binding(party_id, Req),
    handle(Method, PartyId, Req, State).

handle(<<"GET">>, PartyId, Req, State) ->
    case cb_party:get_party(PartyId) of
        {ok, Party} ->
            Resp = party_to_json(Party),
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

handle(<<"OPTIONS">>, _PartyId, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};

handle(_, _PartyId, Req, State) ->
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
        address => address_to_json(Party#party.address),
        created_at => Party#party.created_at,
        updated_at => Party#party.updated_at
    }.

address_to_json(undefined) -> null;
address_to_json(Addr) ->
    #{
        line1       => maps:get(line1,       Addr, null),
        line2       => maps:get(line2,       Addr, null),
        city        => maps:get(city,        Addr, null),
        state       => maps:get(state,       Addr, null),
        postal_code => maps:get(postal_code, Addr, null),
        country     => maps:get(country,     Addr, null)
    }.
