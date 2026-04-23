%% @doc Cowboy Middleware for API version enforcement.
%%
%% Reads the optional `X-API-Version' request header. If the header is absent
%% the request is treated as targeting `v1' (the current version). Any value
%% other than `v1' is rejected immediately with 400 `unsupported_api_version'.
%%
%% The accepted version is echoed back in an `X-API-Version: v1' response
%% header on every request so that clients can confirm the version in use.
-module(cb_version_middleware).
-behaviour(cowboy_middleware).

-export([execute/2]).

-spec execute(cowboy_req:req(), cowboy_middleware:env()) ->
    {ok, cowboy_req:req(), cowboy_middleware:env()} | {stop, cowboy_req:req()}.
execute(Req, Env) ->
    case cowboy_req:header(<<"x-api-version">>, Req, <<"v1">>) of
        <<"v1">> ->
            Req2 = cowboy_req:set_resp_header(<<"x-api-version">>, <<"v1">>, Req),
            {ok, Req2, Env};
        _Other ->
            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
            Resp = #{error => <<"unsupported_api_version">>,
                     message => <<"Unsupported API version. Supported versions: v1">>},
            {stop, cowboy_req:reply(400, Headers, jsone:encode(Resp), Req)}
    end.
