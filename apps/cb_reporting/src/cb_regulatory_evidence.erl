%% @doc Regulatory evidence capture and signed audit export (TASK-095).
%%
%% This module builds signed evidence bundles for CSV exports, persists
%% metadata in the `report_export` table, and supports later verification.
-module(cb_regulatory_evidence).

-export([
    generate/3,
    list_exports/0,
    get_export/1,
    verify_export/1
]).

-spec generate(binary(), map(), binary()) ->
    {ok, map()} | {error, unsupported_resource | database_error | term()}.
generate(ResourceBin, Filters, RequestedBy)
        when is_binary(ResourceBin), is_map(Filters), is_binary(RequestedBy) ->
    case resource_atom(ResourceBin) of
        {ok, Resource} ->
            case cb_exports:export_resource(Resource, Filters) of
                {ok, CsvBin, ContentType} ->
                    build_and_store(ResourceBin, Filters, RequestedBy, CsvBin, ContentType);
                {error, Reason} ->
                    {error, Reason}
            end;
        {error, _} = Err ->
            Err
    end.

-spec list_exports() -> {ok, [map()]} | {error, database_error}.
list_exports() ->
    F = fun() -> mnesia:index_read(report_export, <<"regulatory_evidence">>, export_type) end,
    case mnesia:transaction(F) of
        {atomic, Rows} ->
            Sorted = lists:sort(fun(A, B) ->
                generated_at(A) >= generated_at(B)
            end, Rows),
            {ok, [row_to_map(R) || R <- Sorted]};
        {aborted, _} ->
            {error, database_error}
    end.

-spec get_export(binary()) -> {ok, map()} | {error, not_found | database_error}.
get_export(ExportId) when is_binary(ExportId) ->
    F = fun() -> mnesia:read(report_export, ExportId) end,
    case mnesia:transaction(F) of
        {atomic, [Row]} ->
            {ok, row_to_map(Row)};
        {atomic, []} ->
            {error, not_found};
        {aborted, _} ->
            {error, database_error}
    end.

-spec verify_export(binary()) ->
    {ok, #{verified := boolean(), export_id := binary(), signature := binary(),
           expected_signature := binary(), payload_hash := binary()}}
    | {error, not_found | database_error | invalid_export_payload}.
verify_export(ExportId) when is_binary(ExportId) ->
    case get_export(ExportId) of
        {ok, Export} ->
            Params = maps:get(parameters, Export, #{}),
            Signature = maps:get(signature, Params, undefined),
            case Signature of
                undefined ->
                    {error, invalid_export_payload};
                _ ->
                    Expected = signature_for(
                        maps:get(export_id, Export),
                        maps:get(resource, Params, <<>>),
                        maps:get(requested_by, Params, <<>>),
                        maps:get(generated_at, Params, 0),
                        maps:get(payload_hash, Params, <<>>),
                        maps:get(filters_hash, Params, <<>>),
                        maps:get(chain_head_hash, Params, <<>>),
                        maps:get(chain_verified, Params, false),
                        maps:get(payload_base64, Params, <<>>)
                    ),
                    {ok, #{
                        verified => (Expected =:= Signature),
                        export_id => ExportId,
                        signature => Signature,
                        expected_signature => Expected,
                        payload_hash => maps:get(payload_hash, Params, <<>>)
                    }}
            end;
        Err ->
            Err
    end.

build_and_store(ResourceBin, Filters, RequestedBy, CsvBin, ContentType) ->
    ExportId = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
    Now = erlang:system_time(millisecond),
    PayloadBase64 = base64:encode(CsvBin),
    PayloadHash = sha256_hex(CsvBin),
    FiltersHash = sha256_hex(term_to_binary(lists:sort(maps:to_list(Filters)))),
    {ChainSeq, ChainHash, ChainVerified, ChainVerifyError} = chain_snapshot(),
    Signature = signature_for(
        ExportId,
        ResourceBin,
        RequestedBy,
        Now,
        PayloadHash,
        FiltersHash,
        ChainHash,
        ChainVerified,
        PayloadBase64
    ),
    KeyId = application:get_env(cb_reporting, evidence_signing_key_id, <<"local-dev-1">>),
    Params = #{
        resource => ResourceBin,
        format => <<"csv">>,
        content_type => ContentType,
        requested_by => RequestedBy,
        filters => Filters,
        filters_hash => FiltersHash,
        payload_base64 => PayloadBase64,
        payload_hash => PayloadHash,
        chain_head_sequence => ChainSeq,
        chain_head_hash => ChainHash,
        chain_verified => ChainVerified,
        chain_verify_error => ChainVerifyError,
        generated_at => Now,
        signature_alg => <<"hmac-sha256">>,
        signature_key_id => KeyId,
        signature => Signature
    },
    Row = {report_export, ExportId, <<"regulatory_evidence">>, Params,
           completed, Now, Now},
    F = fun() -> mnesia:write(report_export, Row, write) end,
    case mnesia:transaction(F) of
        {atomic, ok} ->
            {ok, #{
                export_id => ExportId,
                export_type => <<"regulatory_evidence">>,
                status => completed,
                generated_at => Now,
                created_at => Now,
                parameters => Params
            }};
        {aborted, _Reason} ->
            {error, database_error}
    end.

resource_atom(<<"parties">>) -> {ok, parties};
resource_atom(<<"accounts">>) -> {ok, accounts};
resource_atom(<<"transactions">>) -> {ok, transactions};
resource_atom(<<"ledger">>) -> {ok, ledger};
resource_atom(<<"events">>) -> {ok, events};
resource_atom(_) -> {error, unsupported_resource}.

chain_snapshot() ->
    {HeadSeq, HeadHash} = case cb_audit_chain:head() of
        {ok, H} ->
            {maps:get(sequence, link_map(H), 0), maps:get(link_hash, link_map(H), <<>>)};
        none ->
            {0, <<>>}
    end,
    case HeadSeq of
        0 ->
            {0, <<>>, true, undefined};
        _ ->
            case cb_audit_chain:verify_chain() of
                {ok, _} -> {HeadSeq, HeadHash, true, undefined};
                {error, VerifyError} -> {HeadSeq, HeadHash, false, VerifyError}
            end
    end.

link_map(H) ->
    #{
        sequence => element(3, H),
        link_hash => element(6, H)
    }.

signature_for(ExportId, Resource, RequestedBy, GeneratedAt, PayloadHash,
              FiltersHash, ChainHash, ChainVerified, PayloadBase64) ->
    Material = signing_material(ExportId, Resource, RequestedBy, GeneratedAt,
                                PayloadHash, FiltersHash, ChainHash,
                                ChainVerified, PayloadBase64),
    Secret = application:get_env(cb_reporting, evidence_signing_secret,
                                 <<"dev-evidence-signing-secret">>),
    hmac_sha256_hex(Secret, Material).

signing_material(ExportId, Resource, RequestedBy, GeneratedAt, PayloadHash,
                 FiltersHash, ChainHash, ChainVerified, PayloadBase64) ->
    VerifiedBin = case ChainVerified of true -> <<"true">>; false -> <<"false">> end,
    iolist_to_binary([
        ExportId, <<"|">>,
        Resource, <<"|">>,
        RequestedBy, <<"|">>,
        integer_to_binary(GeneratedAt), <<"|">>,
        PayloadHash, <<"|">>,
        FiltersHash, <<"|">>,
        ChainHash, <<"|">>,
        VerifiedBin, <<"|">>,
        PayloadBase64
    ]).

hmac_sha256_hex(Key, Data) ->
    Mac = crypto:mac(hmac, sha256, Key, Data),
    hex(Mac).

sha256_hex(Data) ->
    hex(crypto:hash(sha256, Data)).

hex(Bin) ->
    iolist_to_binary([io_lib:format("~2.16.0b", [B]) || <<B>> <= Bin]).

generated_at({report_export, _Id, _Type, _Params, _Status, GeneratedAt, _CreatedAt}) ->
    GeneratedAt.

row_to_map({report_export, ExportId, ExportType, Params, Status, GeneratedAt, CreatedAt}) ->
    #{
        export_id => ExportId,
        export_type => ExportType,
        parameters => Params,
        status => Status,
        generated_at => GeneratedAt,
        created_at => CreatedAt
    }.
