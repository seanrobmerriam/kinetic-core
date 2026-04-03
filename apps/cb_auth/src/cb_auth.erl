-module(cb_auth).

-export([create_user/3, get_user/1, authenticate/2]).

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

password_hash(Password) ->
    crypto:hash(sha256, Password).
