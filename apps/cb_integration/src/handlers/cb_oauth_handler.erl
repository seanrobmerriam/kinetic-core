%% @doc HTTP handler for POST /api/v1/oauth/token (client_credentials grant).
%%
%% Accepts `application/json' bodies with the following shape:
%% ```json
%% {
%%   "grant_type": "client_credentials",
%%   "client_id": "...",
%%   "client_secret": "..."
%% }
%% '''
%%
%% Returns an RFC 6749-compliant token response or a standard error.
-module(cb_oauth_handler).
-behaviour(cowboy_handler).

-export([init/2]).

-spec init(cowboy_req:req(), term()) -> {ok, cowboy_req:req(), term()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    Req2 = handle(Method, Req),
    {ok, Req2, State}.

handle(<<"POST">>, Req) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:decode(Body, [{object_format, map}, {keys, attempt_atom}]) of
        #{grant_type := <<"client_credentials">>,
          client_id := ClientId,
          client_secret := ClientSecret} ->
            issue(ClientId, ClientSecret, Req2);
        #{grant_type := _} ->
            {Code, Hdrs, RespBody} = cb_http_errors:to_response(oauth_invalid_grant),
            cowboy_req:reply(Code, Hdrs, RespBody, Req2);
        _ ->
            {Code, Hdrs, RespBody} = cb_http_errors:to_response(missing_required_field),
            cowboy_req:reply(Code, Hdrs, RespBody, Req2)
    end;
handle(_, Req) ->
    {Code, Hdrs, RespBody} = cb_http_errors:to_response_with_metrics(method_not_allowed),
    cowboy_req:reply(Code, Hdrs, RespBody, Req).

issue(ClientId, ClientSecret, Req) ->
    case cb_oauth:issue_token(ClientId, ClientSecret) of
        {ok, Token, ExpiresIn} ->
            Resp = #{access_token => Token,
                     token_type   => <<"Bearer">>,
                     expires_in   => ExpiresIn},
            cowboy_req:reply(200, #{<<"content-type">> => <<"application/json">>},
                             jsone:encode(Resp), Req);
        {error, Reason} ->
            {Code, Hdrs, RespBody} = cb_http_errors:to_response(Reason),
            cowboy_req:reply(Code, Hdrs, RespBody, Req)
    end.
