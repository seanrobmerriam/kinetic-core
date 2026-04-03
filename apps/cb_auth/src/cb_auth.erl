-module(cb_auth).

-export([
    create_user/3,
    get_user/1,
    authenticate/2,
    create_session/1,
    get_session/1,
    delete_session/1
]).

-define(SESSION_TTL_MS, 24 * 60 * 60 * 1000).

-spec create_user(binary(), binary(), admin | operations | read_only) ->
    {ok, binary()} | {error, email_already_exists | database_error}.
create_user(Email, Password, Role)
        when is_binary(Email), is_binary(Password),
             (Role =:= admin orelse Role =:= operations orelse Role =:= read_only) ->
    F = fun() ->
        case mnesia:index_read(auth_user, Email, email) of
            [] ->
                Now = erlang:system_time(millisecond),
                UserId = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
                PasswordHash = password_hash(Password),
                ok = mnesia:write(
                    {auth_user, UserId, Email, PasswordHash, Role, active, Now, Now}
                ),
                {ok, UserId};
            [_Existing] ->
                {error, email_already_exists}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, _Reason} -> {error, database_error}
    end.

-spec get_user(binary()) -> {ok, map()} | {error, user_not_found | database_error}.
get_user(UserId) when is_binary(UserId) ->
    F = fun() ->
        case mnesia:read(auth_user, UserId) of
            [{auth_user, Id, Email, _PasswordHash, Role, Status, CreatedAt, UpdatedAt}] ->
                {ok, #{
                    user_id => Id,
                    email => Email,
                    role => Role,
                    status => Status,
                    created_at => CreatedAt,
                    updated_at => UpdatedAt
                }};
            [] ->
                {error, user_not_found}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, _Reason} -> {error, database_error}
    end.

-spec authenticate(binary(), binary()) -> {ok, map()} | {error, invalid_credentials | database_error}.
authenticate(Email, Password) when is_binary(Email), is_binary(Password) ->
    F = fun() ->
        case mnesia:index_read(auth_user, Email, email) of
            [{auth_user, Id, StoredEmail, PasswordHash, Role, Status, CreatedAt, UpdatedAt}] ->
                case password_hash(Password) =:= PasswordHash of
                    true ->
                        {ok, #{
                            user_id => Id,
                            email => StoredEmail,
                            role => Role,
                            status => Status,
                            created_at => CreatedAt,
                            updated_at => UpdatedAt
                        }};
                    false ->
                        {error, invalid_credentials}
                end;
            [] ->
                {error, invalid_credentials}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, _Reason} -> {error, database_error}
    end.

-spec create_session(binary()) -> {ok, map()} | {error, user_not_found | database_error}.
create_session(UserId) when is_binary(UserId) ->
    F = fun() ->
        case mnesia:read(auth_user, UserId) of
            [{auth_user, Id, Email, _PasswordHash, Role, Status, _CreatedAt, _UpdatedAt}] ->
                Now = erlang:system_time(millisecond),
                SessionId = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
                ExpiresAt = Now + ?SESSION_TTL_MS,
                ok = mnesia:write({auth_session, SessionId, Id, active, ExpiresAt, Now, Now}),
                {ok, #{
                    session_id => SessionId,
                    user_id => Id,
                    email => Email,
                    role => Role,
                    status => Status,
                    expires_at => ExpiresAt
                }};
            [] ->
                {error, user_not_found}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, _Reason} -> {error, database_error}
    end.

-spec get_session(binary()) -> {ok, map()} | {error, unauthorized | database_error}.
get_session(SessionId) when is_binary(SessionId) ->
    Now = erlang:system_time(millisecond),
    F = fun() ->
        case mnesia:read(auth_session, SessionId) of
            [{auth_session, Id, UserId, active, ExpiresAt, CreatedAt, UpdatedAt}] when ExpiresAt > Now ->
                case mnesia:read(auth_user, UserId) of
                    [{auth_user, _, Email, _PasswordHash, Role, Status, _UserCreatedAt, _UserUpdatedAt}] ->
                        {ok, #{
                            session_id => Id,
                            user_id => UserId,
                            email => Email,
                            role => Role,
                            status => Status,
                            expires_at => ExpiresAt,
                            created_at => CreatedAt,
                            updated_at => UpdatedAt
                        }};
                    [] ->
                        {error, unauthorized}
                end;
            [{auth_session, _Id, _UserId, _Status, _ExpiresAt, _CreatedAt, _UpdatedAt}] ->
                {error, unauthorized};
            [] ->
                {error, unauthorized}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, _Reason} -> {error, database_error}
    end.

-spec delete_session(binary()) -> ok | {error, unauthorized | database_error}.
delete_session(SessionId) when is_binary(SessionId) ->
    F = fun() ->
        case mnesia:read(auth_session, SessionId, write) of
            [{auth_session, Id, UserId, _Status, ExpiresAt, CreatedAt, _UpdatedAt}] ->
                Now = erlang:system_time(millisecond),
                ok = mnesia:write({auth_session, Id, UserId, revoked, ExpiresAt, CreatedAt, Now}),
                ok;
            [] ->
                {error, unauthorized}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, _Reason} -> {error, database_error}
    end.

password_hash(Password) ->
    crypto:hash(sha256, Password).
