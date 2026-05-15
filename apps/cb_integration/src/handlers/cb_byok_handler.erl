%% @doc HTTP handler for BYOK key management and crypto operations (TASK-080).
%%
%% Routes:
%%   POST /api/v1/insights/byok/keys
%%     body: {owner, key_material_b64, algorithm}
%%   GET  /api/v1/insights/byok/keys?owner=...
%%   GET  /api/v1/insights/byok/keys/:id
%%   POST /api/v1/insights/byok/keys/:id/:action
%%     action in [activate, rotate, revoke, encrypt, decrypt]
%%     for rotate/revoke body: {accessor}
%%     for encrypt body: {plaintext_b64, accessor, purpose}
%%     for decrypt body: {iv_b64, ciphertext_b64, tag_b64, accessor, purpose}
%%   GET  /api/v1/insights/byok/keys/:id/access-log
-module(cb_byok_handler).
-include_lib("cb_ledger/include/cb_ledger.hrl").
-include_lib("cb_insights/include/cb_insights.hrl").

-export([init/2]).

init(Req, State) ->
    Method = cowboy_req:method(Req),
    Id     = cowboy_req:binding(id, Req),
    Action = cowboy_req:binding(action, Req),
    handle(Method, Id, Action, Req, State).

handle(<<"POST">>, undefined, undefined, Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(Body, [{keys, atom}]) of
        {ok, #{owner := O, key_material_b64 := KB64, algorithm := A}, _}
                when is_binary(O), is_binary(KB64), is_binary(A) ->
            try base64:decode(KB64) of
                Key ->
                    case cb_byok:register_key(O, Key, A) of
                        {ok, Id}        -> reply(201, #{key_id => Id}, Req2, State);
                        {error, Reason} -> error_reply(400, Reason, Req2, State)
                    end
            catch _:_ ->
                error_reply(400, <<"Invalid base64 key_material">>, Req2, State)
            end;
        _ ->
            error_reply(400, <<"Missing required fields">>, Req2, State)
    end;

handle(<<"GET">>, undefined, undefined, Req, State) ->
    Qs = cowboy_req:parse_qs(Req),
    case proplists:get_value(<<"owner">>, Qs) of
        undefined ->
            error_reply(400, <<"Missing owner parameter">>, Req, State);
        Owner ->
            Ks = cb_byok:list_keys(Owner),
            reply(200, #{keys => [key_to_map(K) || K <- Ks]}, Req, State)
    end;

handle(<<"GET">>, Id, undefined, Req, State) ->
    case cb_byok:get_key(Id) of
        {ok, K}            -> reply(200, key_to_map(K), Req, State);
        {error, not_found} -> error_reply(404, <<"Key not found">>, Req, State)
    end;

handle(<<"POST">>, Id, <<"activate">>, Req, State) ->
    case cb_byok:activate(Id) of
        ok                          -> reply(200, #{status => active}, Req, State);
        {error, not_found}          -> error_reply(404, <<"Key not found">>, Req, State);
        {error, invalid_transition} -> error_reply(409, <<"Invalid transition">>, Req, State)
    end;

handle(<<"POST">>, Id, Action, Req, State)
        when Action =:= <<"rotate">>; Action =:= <<"revoke">> ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(Body, [{keys, atom}]) of
        {ok, #{accessor := Who}, _} when is_binary(Who) ->
            Result = case Action of
                <<"rotate">> -> cb_byok:rotate(Id, Who);
                <<"revoke">> -> cb_byok:revoke(Id, Who)
            end,
            handle_status_result(Result, Req2, State);
        _ ->
            error_reply(400, <<"Missing accessor">>, Req2, State)
    end;

handle(<<"POST">>, Id, <<"encrypt">>, Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(Body, [{keys, atom}]) of
        {ok, #{plaintext_b64 := PB, accessor := Who, purpose := P}, _} ->
            try base64:decode(PB) of
                Plain ->
                    case cb_byok:encrypt(Id, Plain, Who, P) of
                        {ok, #{iv := IV, ciphertext := C, tag := T}} ->
                            reply(200,
                                  #{iv_b64         => base64:encode(IV),
                                    ciphertext_b64 => base64:encode(C),
                                    tag_b64        => base64:encode(T)},
                                  Req2, State);
                        {error, Reason} ->
                            error_reply(403, Reason, Req2, State)
                    end
            catch _:_ ->
                error_reply(400, <<"Invalid base64 plaintext">>, Req2, State)
            end;
        _ ->
            error_reply(400, <<"Missing required fields">>, Req2, State)
    end;

handle(<<"POST">>, Id, <<"decrypt">>, Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(Body, [{keys, atom}]) of
        {ok, #{iv_b64 := IVB, ciphertext_b64 := CB,
               tag_b64 := TB, accessor := Who, purpose := P}, _} ->
            try {base64:decode(IVB), base64:decode(CB), base64:decode(TB)} of
                {IV, Cipher, Tag} ->
                    Env = #{iv => IV, ciphertext => Cipher, tag => Tag},
                    case cb_byok:decrypt(Id, Env, Who, P) of
                        {ok, Plain} ->
                            reply(200,
                                  #{plaintext_b64 => base64:encode(Plain)},
                                  Req2, State);
                        {error, Reason} ->
                            error_reply(403, Reason, Req2, State)
                    end
            catch _:_ ->
                error_reply(400, <<"Invalid base64 envelope">>, Req2, State)
            end;
        _ ->
            error_reply(400, <<"Missing required fields">>, Req2, State)
    end;

handle(<<"GET">>, Id, <<"access-log">>, Req, State) ->
    Logs = cb_byok:list_access_log(Id),
    reply(200, #{logs => [log_to_map(L) || L <- Logs]}, Req, State);

handle(_, _, _, Req, State) ->
    error_reply(405, <<"Method not allowed">>, Req, State).

handle_status_result(ok, Req, State) ->
    reply(200, #{status => ok}, Req, State);
handle_status_result({error, not_found}, Req, State) ->
    error_reply(404, <<"Key not found">>, Req, State);
handle_status_result({error, invalid_transition}, Req, State) ->
    error_reply(409, <<"Invalid transition">>, Req, State);
handle_status_result({error, Reason}, Req, State) ->
    error_reply(400, Reason, Req, State).

key_to_map(K) ->
    %% Never expose wrapped material via API
    #{key_id     => K#byok_key.key_id,
      owner      => K#byok_key.owner,
      algorithm  => K#byok_key.algorithm,
      status     => K#byok_key.status,
      created_at => K#byok_key.created_at,
      rotated_at => K#byok_key.rotated_at,
      revoked_at => K#byok_key.revoked_at}.

log_to_map(L) ->
    #{access_id   => L#byok_access_log.access_id,
      key_id      => L#byok_access_log.key_id,
      accessor    => L#byok_access_log.accessor,
      purpose     => L#byok_access_log.purpose,
      operation   => L#byok_access_log.operation,
      decision    => L#byok_access_log.decision,
      reason      => L#byok_access_log.reason,
      accessed_at => L#byok_access_log.accessed_at}.

reply(Code, Body, Req, State) ->
    R = cowboy_req:reply(Code, headers(), jsone:encode(Body), Req),
    {ok, R, State}.

headers() ->
    #{<<"content-type">> => <<"application/json">>}.

error_reply(Code, Reason, Req, State) when is_atom(Reason) ->
    error_reply(Code, atom_to_binary(Reason, utf8), Req, State);
error_reply(Code, Reason, Req, State) ->
    R = cowboy_req:reply(Code, headers(),
            jsone:encode(#{error => Reason}), Req),
    {ok, R, State}.
