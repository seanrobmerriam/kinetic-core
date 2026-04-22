%% @doc Rate limiting middleware for Cowboy.
%%
%% Checks each incoming request against `cb_rate_limiter` using the
%% client's IP address as the bucket key.  Public paths (health, metrics,
%% openapi) are exempt.  On limit exceeded the middleware terminates the
%% pipeline and returns HTTP 429 with a `Retry-After: 60` header.
-module(cb_rate_limit_middleware).

-behaviour(cowboy_middleware).

-export([execute/2]).

-spec execute(cowboy_req:req(), cowboy_middleware:env()) ->
    {ok, cowboy_req:req(), cowboy_middleware:env()} | {stop, cowboy_req:req()}.
execute(Req, Env) ->
    Path = cowboy_req:path(Req),
    case is_exempt_path(Path) of
        true ->
            {ok, Req, Env};
        false ->
            Key = client_key(Req),
            case cb_rate_limiter:check_and_increment(Key) of
                allow ->
                    {ok, Req, Env};
                deny ->
                    {Status, ErrorAtom, Message} = cb_http_errors:to_response(rate_limit_exceeded),
                    Resp = #{error => ErrorAtom, message => Message},
                    Headers = maps:merge(
                        #{<<"content-type">>  => <<"application/json">>,
                          <<"retry-after">>   => <<"60">>},
                        cb_cors:headers()
                    ),
                    {stop, cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req)}
            end
    end.

%% Paths that bypass rate limiting.
is_exempt_path(<<"/health">>)              -> true;
is_exempt_path(<<"/metrics">>)             -> true;
is_exempt_path(<<"/api/v1/openapi.json">>) -> true;
is_exempt_path(_)                          -> false.

%% Use the forwarded IP when behind a proxy; fall back to peer address.
client_key(Req) ->
    case cowboy_req:header(<<"x-forwarded-for">>, Req) of
        undefined ->
            {PeerIP, _Port} = cowboy_req:peer(Req),
            list_to_binary(inet:ntoa(PeerIP));
        Forwarded ->
            %% Take only the first (leftmost) address.
            hd(binary:split(Forwarded, [<<",">>, <<" ">>], [global, trim_all]))
    end.
