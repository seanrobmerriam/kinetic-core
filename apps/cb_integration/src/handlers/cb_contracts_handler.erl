%% @doc Contract definition endpoints.
%%
%% Routes:
%%   GET  /api/v1/contracts
%%   POST /api/v1/contracts
%%   GET  /api/v1/contracts/:contract_id
-module(cb_contracts_handler).

-include_lib("cb_contracts/include/cb_contracts.hrl").

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    ContractId = cowboy_req:binding(contract_id, Req, undefined),
    handle(Method, ContractId, Req, State).

handle(<<"GET">>, undefined, Req, State) ->
    Contracts = cb_contracts:list_contracts(),
    Body = #{items => [contract_to_map(C) || C <- Contracts], total => length(Contracts)},
    json_reply(200, Body, Req, State);

handle(<<"POST">>, undefined, Req, State) ->
    {ok, BodyBin, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(BodyBin) of
        {ok, Json, _} when is_map(Json) ->
            Attrs = #{contract_id => maps:get(<<"contract_id">>, Json, undefined),
                      name => maps:get(<<"name">>, Json, undefined),
                      domain => maps:get(<<"domain">>, Json, <<"general">>),
                      owner_role => maps:get(<<"owner_role">>, Json, <<"product_admin">>)},
            case cb_contracts:create_contract(Attrs) of
                {ok, Contract} ->
                    json_reply(201, contract_to_map(Contract), Req2, State);
                {error, Reason} ->
                    reply_error(Reason, Req2, State)
            end;
        _ ->
            reply_error(invalid_json, Req2, State)
    end;

handle(<<"GET">>, ContractId, Req, State) when ContractId =/= undefined ->
    case cb_contracts:get_contract(ContractId) of
        {ok, Contract} ->
            Versions = cb_contracts:list_versions(ContractId),
            Migrations = cb_contracts:list_migrations(ContractId),
            Body = (contract_to_map(Contract))#{
                versions => [version_to_map(V) || V <- Versions],
                migrations => [migration_to_map(M) || M <- Migrations]
            },
            json_reply(200, Body, Req, State);
        {error, Reason} ->
            reply_error(Reason, Req, State)
    end;

handle(<<"OPTIONS">>, _ContractId, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};

handle(_, _ContractId, Req, State) ->
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
