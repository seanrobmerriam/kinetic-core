%% @doc GraphQL HTTP handler
%%
%% Accepts GraphQL queries over HTTP:
%%
%% - `POST /api/graphql' — Execute a query.
%%   Body: `{"query": "{ party(id: \"...\") { id fullName } }"}' or plain query text.
%%   Response: `{"data": {...}, "errors": []}' (GraphQL spec response format).
%%
%% - `GET /api/graphql' — Return the GraphQL schema SDL for tooling/introspection.
%%   Response: `{"schema": "...SDL string..."}
%%
%% Authentication: all requests require a valid API key (same as other routes).
-module(cb_graphql_handler).

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    Req2 = handle(Method, Req),
    {ok, Req2, State}.

-spec handle(binary(), cowboy_req:req()) -> cowboy_req:req().
handle(<<"GET">>, Req) ->
    SDL = cb_graphql:schema_sdl(),
    Headers = maps:merge(
        #{<<"content-type">> => <<"application/json">>},
        cb_cors:headers()
    ),
    Body = jsone:encode(#{<<"schema">> => SDL}),
    cowboy_req:reply(200, Headers, Body, Req);

handle(<<"POST">>, Req) ->
    case cowboy_req:read_body(Req) of
        {ok, Body, Req2} ->
            execute_query(Body, Req2);
        {error, _Reason} ->
            reply_error(400, <<"invalid_body">>, <<"Failed to read request body">>, Req)
    end;

handle(<<"OPTIONS">>, Req) ->
    Headers = cb_cors:headers(),
    cowboy_req:reply(204, Headers, <<>>, Req);

handle(_Method, Req) ->
    reply_error(405, <<"method_not_allowed">>, <<"Use POST to execute queries">>, Req).

-spec execute_query(binary(), cowboy_req:req()) -> cowboy_req:req().
execute_query(Body, Req) ->
    QueryBin = extract_query(Body),
    case QueryBin of
        undefined ->
            reply_error(400, <<"bad_request">>, <<"Missing 'query' field">>, Req);
        <<>> ->
            reply_error(400, <<"bad_request">>, <<"Query must not be empty">>, Req);
        Q ->
            case cb_graphql:execute(Q) of
                {ok, Result} ->
                    Headers = maps:merge(
                        #{<<"content-type">> => <<"application/json">>},
                        cb_cors:headers()
                    ),
                    cowboy_req:reply(200, Headers, jsone:encode(Result), Req);
                {error, Errors} ->
                    Headers = maps:merge(
                        #{<<"content-type">> => <<"application/json">>},
                        cb_cors:headers()
                    ),
                    RespBody = jsone:encode(#{
                        <<"data">>   => null,
                        <<"errors">> => Errors
                    }),
                    cowboy_req:reply(200, Headers, RespBody, Req)
            end
    end.

%% Extract the query string from either a JSON body or a plain text body.
-spec extract_query(binary()) -> binary() | undefined.
extract_query(<<${, _/binary>> = Body) ->
    try
        case jsone:decode(Body) of
            #{<<"query">> := Q} when is_binary(Q) -> Q;
            _ -> undefined
        end
    catch _:_ ->
        undefined
    end;
extract_query(Body) when is_binary(Body), byte_size(Body) > 0 ->
    Body;
extract_query(_) ->
    undefined.

-spec reply_error(integer(), binary(), binary(), cowboy_req:req()) ->
    cowboy_req:req().
reply_error(Status, Code, Message, Req) ->
    Headers = maps:merge(
        #{<<"content-type">> => <<"application/json">>},
        cb_cors:headers()
    ),
    Body = jsone:encode(#{<<"error">> => Code, <<"message">> => Message}),
    cowboy_req:reply(Status, Headers, Body, Req).
