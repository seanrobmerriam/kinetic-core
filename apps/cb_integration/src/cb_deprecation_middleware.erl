%% @doc Deprecation Middleware
%%
%% Cowboy middleware that injects `Deprecation' and `Sunset' response headers
%% for any request that targets a path listed in `cb_deprecation'.
%%
%% Position in the chain: after `cb_auth_middleware', before `cowboy_handler'.
%% This ensures deprecated-path warnings are emitted even for authenticated
%% requests without altering the response body or status code.
-module(cb_deprecation_middleware).

-behaviour(cowboy_middleware).

-export([execute/2]).

-spec execute(cowboy_req:req(), cowboy_middleware:env()) ->
    {ok, cowboy_req:req(), cowboy_middleware:env()} | {stop, cowboy_req:req()}.
execute(Req, Env) ->
    Path = cowboy_req:path(Req),
    case cb_deprecation:is_deprecated(Path) of
        false ->
            {ok, Req, Env};
        {true, Entry} ->
            Sunset = maps:get(sunset_date, Entry),
            Req2 = cowboy_req:set_resp_header(<<"deprecation">>, <<"true">>, Req),
            Req3 = cowboy_req:set_resp_header(<<"sunset">>, Sunset, Req2),
            {ok, Req3, Env}
    end.
