%% @doc Contract version lifecycle endpoints.
%%
%% Routes:
%%   GET  /api/v1/contracts/:contract_id/versions
%%   POST /api/v1/contracts/:contract_id/versions
%%   GET  /api/v1/contracts/:contract_id/versions/:version
%%   POST /api/v1/contracts/:contract_id/versions/:version/activate
%%   POST /api/v1/contracts/:contract_id/versions/:version/migrate
-module(cb_contract_versions_handler).

-include_lib("cb_contracts/include/cb_contracts.hrl").

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    ContractId = cowboy_req:binding(contract_id, Req, undefined),
    Version = cowboy_req:binding(version, Req, undefined),
    Action = cowboy_req:binding(action, Req, undefined),
    handle(Method, ContractId, Version, Action, Req, State).

handle(<<"GET">>, ContractId, undefined, undefined, Req, State) ->
    Versions = cb_contracts:list_versions(ContractId),
    Body = #{items => [version_to_map(V) || V <- Versions], total => length(Versions)},
    json_reply(200, Body, Req, State);

handle(<<"POST">>, ContractId, undefined, undefined, Req, State) ->
    {ok, BodyBin, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(BodyBin) of
        {ok, Json, _} when is_map(Json) ->
            Version = maps:get(<<"version">>, Json, undefined),
            Payload = maps:get(<<"contract_payload">>, Json, #{}),
            CreatedBy = maps:get(<<"created_by">>, Json, undefined),
            case cb_contracts:deploy_version(ContractId, Version, Payload, CreatedBy) of
                {ok, VersionRec} ->
                    json_reply(201, version_to_map(VersionRec), Req2, State);
                {error, Reason} ->
                    reply_error(Reason, Req2, State)
            end;
        _ ->
            reply_error(invalid_json, Req2, State)
    end;

handle(<<"GET">>, ContractId, Version, undefined, Req, State) ->
    case cb_contracts:get_version(ContractId, Version) of
        {ok, VersionRec} ->
            json_reply(200, version_to_map(VersionRec), Req, State);
        {error, Reason} ->
            reply_error(Reason, Req, State)
    end;

handle(<<"POST">>, ContractId, Version, <<"activate">>, Req, State) ->
    case cb_contracts:activate_version(ContractId, Version) of
        {ok, Contract} ->
            json_reply(200, contract_to_map(Contract), Req, State);
        {error, Reason} ->
            reply_error(Reason, Req, State)
    end;

handle(<<"POST">>, ContractId, ToVersion, <<"migrate">>, Req, State) ->
    {ok, BodyBin, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(BodyBin) of
        {ok, Json, _} when is_map(Json) ->
            FromVersion = maps:get(<<"from_version">>, Json, undefined),
            Strategy = parse_strategy(maps:get(<<"strategy">>, Json, <<"compatible">>)),
            Notes = maps:get(<<"notes">>, Json, undefined),
            CreatedBy = maps:get(<<"created_by">>, Json, undefined),
            case cb_contracts:create_migration(
              ContractId, FromVersion, ToVersion, Strategy, Notes, CreatedBy) of
                {ok, Migration} ->
                    json_reply(201, migration_to_map(Migration), Req2, State);
                {error, Reason} ->
                    reply_error(Reason, Req2, State)
            end;
        _ ->
            reply_error(invalid_json, Req2, State)
    end;

handle(<<"POST">>, ContractId, Version, <<"execute">>, Req, State) ->
    {ok, BodyBin, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(BodyBin) of
        {ok, Json, _} when is_map(Json) ->
            Context = maps:get(<<"context">>, Json, #{}),
            Authz = normalize_authz(maps:get(<<"authz">>, Json, #{})),
            case cb_contracts:get_version(ContractId, Version) of
                {ok, VersionRec} ->
                    Payload0 = VersionRec#contract_version.contract_payload,
                    Payload = Payload0#{contract_id => ContractId, version => Version},
                    case cb_contracts:execute(Payload, Context, Authz) of
                        {ok, Decision, Trace} ->
                            json_reply(200, #{result => ok,
                                              decision => Decision,
                                              trace => Trace}, Req2, State);
                        {error, Reason, Trace} ->
                            json_reply(422, #{result => error,
                                              reason => Reason,
                                              trace => Trace}, Req2, State)
                    end;
                {error, Reason} ->
                    reply_error(Reason, Req2, State)
            end;
        _ ->
            reply_error(invalid_json, Req2, State)
    end;

handle(<<"OPTIONS">>, _ContractId, _Version, _Action, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};

handle(_, _ContractId, _Version, _Action, Req, State) ->
    {Code, Hdrs, RespBody} = cb_http_errors:to_response_with_metrics(method_not_allowed),
    Req2 = cowboy_req:reply(Code, Hdrs, RespBody, Req),
    {ok, Req2, State}.

reply_error(Reason, Req, State) ->
    {Status, ErrorAtom, Message} = cb_http_errors:to_response(Reason),
    json_reply(Status, #{error => ErrorAtom, message => Message}, Req, State).

json_reply(Status, Body, Req, State) ->
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    Req2 = cowboy_req:reply(Status, Headers, jsone:encode(Body), Req),
    {ok, Req2, State}.

parse_strategy(<<"transform">>) -> transform;
parse_strategy(<<"manual">>) -> manual;
parse_strategy(_) -> compatible.

normalize_authz(Authz) when is_map(Authz) ->
    Caps0 = maps:get(<<"capabilities">>, Authz, maps:get(capabilities, Authz, [])),
    Caps1 = normalize_capabilities(Caps0),
    Timeout = maps:get(<<"timeout_ms">>, Authz, maps:get(timeout_ms, Authz, 50)),
    ReqId = maps:get(<<"request_id">>, Authz, maps:get(request_id, Authz, undefined)),
    #{capabilities => Caps1, timeout_ms => Timeout, request_id => ReqId};
normalize_authz(_) ->
    #{capabilities => [can_emit_event, can_enqueue_review, can_set_decision_fields],
      timeout_ms => 50,
      request_id => undefined}.

normalize_capabilities(Caps) when is_list(Caps) ->
    [normalize_capability(C) || C <- Caps, normalize_capability(C) =/= undefined];
normalize_capabilities(_) ->
    [can_emit_event, can_enqueue_review, can_set_decision_fields].

normalize_capability(<<"can_emit_event">>) -> can_emit_event;
normalize_capability(<<"can_enqueue_review">>) -> can_enqueue_review;
normalize_capability(<<"can_set_decision_fields">>) -> can_set_decision_fields;
normalize_capability(can_emit_event) -> can_emit_event;
normalize_capability(can_enqueue_review) -> can_enqueue_review;
normalize_capability(can_set_decision_fields) -> can_set_decision_fields;
normalize_capability(_) -> undefined.

contract_to_map(#contract_definition{
    contract_id = ContractId,
    name = Name,
    domain = Domain,
    owner_role = OwnerRole,
    status = Status,
    active_version = ActiveVersion,
    created_at = CreatedAt,
    updated_at = UpdatedAt
}) ->
    #{contract_id => ContractId,
      name => Name,
      domain => Domain,
      owner_role => OwnerRole,
      status => Status,
      active_version => ActiveVersion,
      created_at => CreatedAt,
      updated_at => UpdatedAt}.

version_to_map(#contract_version{
    version_id = VersionId,
    contract_id = ContractId,
    version = Version,
    dsl_version = DslVersion,
    status = Status,
    contract_payload = Payload,
    checksum = Checksum,
    created_by = CreatedBy,
    created_at = CreatedAt,
    updated_at = UpdatedAt,
    migration_from = MigrationFrom
}) ->
    #{version_id => VersionId,
      contract_id => ContractId,
      version => Version,
      dsl_version => DslVersion,
      status => Status,
      contract_payload => Payload,
      checksum => Checksum,
      created_by => CreatedBy,
      created_at => CreatedAt,
      updated_at => UpdatedAt,
      migration_from => MigrationFrom}.

migration_to_map(#contract_migration{
    migration_id = MigrationId,
    contract_id = ContractId,
    from_version = FromVersion,
    to_version = ToVersion,
    strategy = Strategy,
    notes = Notes,
    created_by = CreatedBy,
    created_at = CreatedAt
}) ->
    #{migration_id => MigrationId,
      contract_id => ContractId,
      from_version => FromVersion,
      to_version => ToVersion,
      strategy => Strategy,
      notes => Notes,
      created_by => CreatedBy,
      created_at => CreatedAt}.
