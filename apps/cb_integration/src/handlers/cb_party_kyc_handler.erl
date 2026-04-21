%% @doc Party KYC Handler
%%
%% Handler for the `/api/v1/parties/:party_id/kyc` endpoint.
%%
%% <h2>REST API Endpoints</h2>
%%
%% <ul>
%%   <li><b>GET /api/v1/parties/:party_id/kyc</b> - Get KYC state for a party</li>
%%   <li><b>PATCH /api/v1/parties/:party_id/kyc</b> - Update KYC status and notes</li>
%%   <li><b>POST /api/v1/parties/:party_id/kyc/docs</b> - Add a document reference</li>
%%   <li><b>OPTIONS /api/v1/parties/:party_id/kyc</b> - CORS preflight</li>
%% </ul>
%%
%% <h2>PATCH body</h2>
%%
%% <pre>
%% {
%%   "kyc_status": "pending" | "approved" | "rejected" | "not_started",
%%   "review_notes": "optional review notes"
%% }
%% </pre>
%%
%% <h2>POST /docs body</h2>
%%
%% <pre>
%% { "doc_ref": "s3://bucket/key" }
%% </pre>
%%
%% @see cb_party
-module(cb_party_kyc_handler).

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
            Resp = kyc_to_json(Party),
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

handle(<<"PATCH">>, PartyId, Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(Body) of
        {ok, Decoded, _} ->
            KycStatusBin = maps:get(<<"kyc_status">>, Decoded, undefined),
            Notes = maps:get(<<"review_notes">>, Decoded, undefined),
            case parse_kyc_status(KycStatusBin) of
                {ok, KycStatus} ->
                    case cb_party:update_kyc_status(PartyId, KycStatus, Notes) of
                        {ok, Party} ->
                            Resp = kyc_to_json(Party),
                            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
                            Req3 = cowboy_req:reply(200, Headers, jsone:encode(Resp), Req2),
                            {ok, Req3, State};
                        {error, Reason} ->
                            {Status, ErrorAtom, Msg} = cb_http_errors:to_response(Reason),
                            Resp = #{error => ErrorAtom, message => Msg},
                            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
                            Req3 = cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req2),
                            {ok, Req3, State}
                    end;
                {error, _} ->
                    {Status, ErrorAtom, Msg} = cb_http_errors:to_response(invalid_kyc_status),
                    Resp = #{error => ErrorAtom, message => Msg},
                    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
                    Req3 = cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req2),
                    {ok, Req3, State}
            end;
        _ ->
            {Status, ErrorAtom, Msg} = cb_http_errors:to_response(missing_required_field),
            Resp = #{error => ErrorAtom, message => Msg},
            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
            Req3 = cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req2),
            {ok, Req3, State}
    end;

handle(<<"POST">>, PartyId, Req, State) ->
    %% POST .../kyc/docs - handled by path binding; here we add doc ref
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(Body) of
        {ok, #{<<"doc_ref">> := DocRef}, _} when is_binary(DocRef) ->
            case cb_party:add_doc_ref(PartyId, DocRef) of
                {ok, Party} ->
                    Resp = kyc_to_json(Party),
                    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
                    Req3 = cowboy_req:reply(200, Headers, jsone:encode(Resp), Req2),
                    {ok, Req3, State};
                {error, Reason} ->
                    {Status, ErrorAtom, Msg} = cb_http_errors:to_response(Reason),
                    Resp = #{error => ErrorAtom, message => Msg},
                    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
                    Req3 = cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req2),
                    {ok, Req3, State}
            end;
        _ ->
            {Status, ErrorAtom, Msg} = cb_http_errors:to_response(missing_required_field),
            Resp = #{error => ErrorAtom, message => Msg},
            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
            Req3 = cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req2),
            {ok, Req3, State}
    end;

handle(<<"OPTIONS">>, _PartyId, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};

handle(_, _PartyId, Req, State) ->
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    Req2 = cowboy_req:reply(405, Headers, <<"{\"error\": \"method_not_allowed\"}">>, Req),
    {ok, Req2, State}.

%% Internal helpers

kyc_to_json(Party) ->
    #{
        party_id => Party#party.party_id,
        kyc_status => Party#party.kyc_status,
        onboarding_status => Party#party.onboarding_status,
        review_notes => Party#party.review_notes,
        doc_refs => Party#party.doc_refs,
        updated_at => Party#party.updated_at
    }.

parse_kyc_status(<<"not_started">>) -> {ok, not_started};
parse_kyc_status(<<"pending">>)     -> {ok, pending};
parse_kyc_status(<<"approved">>)    -> {ok, approved};
parse_kyc_status(<<"rejected">>)    -> {ok, rejected};
parse_kyc_status(_)                 -> {error, invalid_kyc_status}.
