-module(cb_auth_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1, init_per_testcase/2]).
-export([
    create_user_and_authenticate_ok/1,
    duplicate_email_rejected/1,
    invalid_password_rejected/1
]).

all() ->
    [
        create_user_and_authenticate_ok,
        duplicate_email_rejected,
        invalid_password_rejected
    ].

init_per_suite(Config) ->
    mnesia:start(),
    cb_schema:create_tables(),
    {ok, _} = application:ensure_all_started(cb_auth),
    Config.

end_per_suite(_Config) ->
    ok = application:stop(cb_auth),
    mnesia:stop(),
    mnesia:delete_schema([node()]),
    ok.

init_per_testcase(_TestCase, Config) ->
    lists:foreach(
        fun(Table) -> mnesia:clear_table(Table) end,
        [auth_user, auth_session, audit_log]
    ),
    Config.

create_user_and_authenticate_ok(_Config) ->
    {ok, UserId} = cb_auth:create_user(
        <<"admin@example.com">>,
        <<"s3cret-pass">>,
        admin
    ),
    {ok, User} = cb_auth:get_user(UserId),
    ?assertEqual(<<"admin@example.com">>, maps:get(email, User)),
    ?assertEqual(admin, maps:get(role, User)),
    ?assertMatch({ok, _}, cb_auth:authenticate(<<"admin@example.com">>, <<"s3cret-pass">>)),
    ok.

duplicate_email_rejected(_Config) ->
    {ok, _} = cb_auth:create_user(<<"ops@example.com">>, <<"pw-1">>, operations),
    ?assertEqual(
        {error, email_already_exists},
        cb_auth:create_user(<<"ops@example.com">>, <<"pw-2">>, read_only)
    ).

invalid_password_rejected(_Config) ->
    {ok, _} = cb_auth:create_user(<<"viewer@example.com">>, <<"correct-password">>, read_only),
    ?assertEqual(
        {error, invalid_credentials},
        cb_auth:authenticate(<<"viewer@example.com">>, <<"wrong-password">>)
    ).
