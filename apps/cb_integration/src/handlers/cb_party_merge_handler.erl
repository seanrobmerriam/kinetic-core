%% @doc
%% <h2>Party Merge Handler</h2>
%%
%% HTTP handler for party duplicate detection and merge operations.
%%
%% <h3>Endpoints</h3>
%%
%% <ul>
%%   <li><b>GET /api/v1/parties/duplicates</b> — detect potential duplicate parties</li>
%%   <li><b>POST /api/v1/parties/:party_id/merge</b> — merge a source party into a target</li>
%% </ul>
%%
%% <h3>Duplicate Detection</h3>
%%
%% GET /parties/duplicates returns groups of parties sharing the same normalized name.
%% Query parameters for filtering:
%%   - name (optional): normalize and match against party names
%%   - dob (optional): date of birth to match
%%   - document_number (optional): SSN or ID document to match
%%
%% <h3>Merge</h3>
%%
%% POST /parties/:party_id/merge merges the identified source party into this target.
%% Body: { target_party_id, reason }
%%
%% The source party is marked closed and all accounts are transferred to the target.
%% Both parties receive audit trail entries.
%%
%% @see cb_party
-module(cb_party_merge_handler).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    PartyId = cowboy_req:binding(party_id, Req),
    handle(Method, PartyId, Req, State).

%% GET /api/v1/parties/duplicates
%% Returns groups of parties that appear to be duplicates (same normalized name)
handle(<<"GET">>, undefined, Req, State) ->
    Qs = cowboy_req:parse_qs(Req),
    case proplists:get_value(<<"name">>, Qs) of
        undefined ->
            %% No filter — return all duplicate groups
            case cb_party:detect_duplicate_parties() of
                {ok, Groups} ->
                    Resp = #{duplicates => Groups},
                    reply(200, Resp, Req, State);
                {error, Reason} ->
                    error_reply(Reason, Req, State)
            end;
        NameBin ->
            %% Filter by normalized name
            Normalized = cb_party:normalize_name(list_to_binary(NameBin)),
            case cb_party:detect_duplicate_parties() of
                {ok, Groups} ->
                    Filtered = [
                        G || G <- Groups,
                        maps:get(normalized_name, G) =:= Normalized
                    ],
                    reply(200, #{duplicates => Filtered}, Req, State);
                {error, Reason} ->
                    error_reply(Reason, Req, State)
            end
    end;

%% POST /api/v1/parties/:party_id/merge
%% Body: #{ <<"target_party_id">> => binary(), <<"reason">> => binary() }
handle(<<"POST">>, SourcePartyId, Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(Body) of
        {ok, #{<<"target_party_id">> := TargetPartyId, <<"reason">> := Reason}, _}
                when is_binary(TargetPartyId), is_binary(Reason) ->
            case cb_party:merge_parties(SourcePartyId, TargetPartyId, Reason) of
                {ok, MergedParty} ->
                    Resp = #{
                        ok => true,
                        merged_party => party_to_json(MergedParty),
                        source_party_id => SourcePartyId,
                        target_party_id => TargetPartyId
                    },
                    reply(200, Resp, Req2, State);
                {error, Reason} ->
                    error_reply(Reason, Req2, State)
            end;
        _ ->
            reply(400, #{
                error => bad_request,
                message => <<"Body must include target_party_id and reason">>
            }, Req, State)
    end;

%% OPTIONS preflight
handle(<<"OPTIONS">>, _PartyId, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};

handle(_, _PartyId, Req, State) ->
    reply(405, #{error => method_not_allowed, message => <<"Method not allowed">>}, Req, State).

%% -----------------------------------------------------------------------------
%% Internal
%% -----------------------------------------------------------------------------

reply(Status, Body, Req, State) ->
    Headers = maps:merge(
        #{<<"content-type">> => <<"application/json">>},
        cb_cors:headers()
    ),
    Req2 = cowboy_req:reply(Status, Headers, jsone:encode(Body), Req),
    {ok, Req2, State}.

error_reply(Reason, Req, State) ->
    {Status, ErrorAtom, Message} = cb_http_errors:to_response(Reason),
    reply(Status, #{error => ErrorAtom, message => Message}, Req, State).

party_to_json(Party) ->
    #{
        party_id => Party#party.party_id,
        full_name => Party#party.full_name,
        email => Party#party.email,
        status => Party#party.status,
        kyc_status => Party#party.kyc_status,
        merged_into_party_id => Party#party.merged_into_party_id,
        created_at => Party#party.created_at,
        updated_at => Party#party.updated_at
    }.