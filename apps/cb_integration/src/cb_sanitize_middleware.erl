%% @doc Request input sanitization middleware.
%%
%% Enforces request-level safety constraints for all incoming HTTP requests
%% before any handler executes. Three categories of checks are applied:
%%
%% <h2>Body size (POST/PUT/PATCH)</h2>
%%
%% If the `content-length' header is present and its declared value exceeds
%% {@link max_body_bytes/0}, the request is immediately rejected with 413.
%% This prevents large-body abuse before the handler allocates memory to
%% read the body. Requests without a Content-Length header (chunked
%% transfer encoding) are not rejected here; handlers use bounded
%% `cowboy_req:read_body/2' to cap actual reads.
%%
%% <h2>Content-Type (POST/PUT/PATCH)</h2>
%%
%% Write requests must declare `content-type: application/json'. Requests
%% with a missing or non-JSON Content-Type are rejected with 415. This
%% prevents handler logic from running against unexpected payload formats
%% such as `multipart/form-data' or `text/plain'.
%%
%% <h2>Query-string parameter values</h2>
%%
%% All query-string values are validated:
%%
%% <ul>
%%   <li>Each value must be at most {@link max_qs_value_bytes/0} bytes.</li>
%%   <li>No value may contain a null byte (0x00).</li>
%% </ul>
%%
%% Violations produce a 400 Bad Request response.
%%
%% OPTIONS requests bypass all checks to allow CORS preflight handling.
%%
%% @see cb_sanitize_middleware:execute/2
-module(cb_sanitize_middleware).
-behaviour(cowboy_middleware).

-export([execute/2]).

-define(MAX_BODY_BYTES, 65536).       %% 64 KiB
-define(MAX_QS_VALUE_BYTES, 512).

-spec execute(cowboy_req:req(), cowboy_middleware:env()) ->
    {ok, cowboy_req:req(), cowboy_middleware:env()} | {stop, cowboy_req:req()}.
execute(Req, Env) ->
    Method = cowboy_req:method(Req),
    case Method of
        <<"OPTIONS">> ->
            {ok, Req, Env};
        _ ->
            case check_query_string(Req) of
                ok ->
                    case is_write_method(Method) of
                        true  -> check_write_request(Req, Env);
                        false -> {ok, Req, Env}
                    end;
                {error, Reason} ->
                    reject(Reason, Req)
            end
    end.

%% -------------------------------------------------------------------------
%% Internal
%% -------------------------------------------------------------------------

is_write_method(<<"POST">>)  -> true;
is_write_method(<<"PUT">>)   -> true;
is_write_method(<<"PATCH">>) -> true;
is_write_method(_)           -> false.

check_write_request(Req, Env) ->
    case check_content_type(Req) of
        ok ->
            case check_content_length(Req) of
                ok     -> {ok, Req, Env};
                {error, Reason} -> reject(Reason, Req)
            end;
        {error, Reason} ->
            reject(Reason, Req)
    end.

%% @private Ensure Content-Type is application/json for write methods.
check_content_type(Req) ->
    case cowboy_req:header(<<"content-type">>, Req, undefined) of
        undefined ->
            {error, unsupported_media_type};
        CT ->
            %% Accept "application/json" with optional parameters, e.g.
            %% "application/json; charset=utf-8".
            case is_json_content_type(CT) of
                true  -> ok;
                false -> {error, unsupported_media_type}
            end
    end.

is_json_content_type(CT) ->
    %% Normalise to lowercase and strip optional parameters.
    Lower = string:lowercase(binary_to_list(CT)),
    Stripped = hd(string:tokens(Lower, ";")),
    Trimmed = string:trim(Stripped),
    Trimmed =:= "application/json".

%% @private Check declared Content-Length does not exceed the cap.
check_content_length(Req) ->
    case cowboy_req:header(<<"content-length">>, Req, undefined) of
        undefined ->
            %% Chunked or no body — allow through; handler is responsible.
            ok;
        CLBin ->
            try binary_to_integer(CLBin) of
                CL when CL > ?MAX_BODY_BYTES -> {error, request_too_large};
                _  -> ok
            catch _:_ ->
                %% Malformed Content-Length header; let Cowboy handle it.
                ok
            end
    end.

%% @private Validate all query-string values are within bounds and safe.
check_query_string(Req) ->
    QS = cowboy_req:parse_qs(Req),
    check_qs_values(QS).

check_qs_values([]) -> ok;
check_qs_values([{_Key, true} | Rest]) ->
    %% Boolean flag (no value) — safe.
    check_qs_values(Rest);
check_qs_values([{_Key, Val} | Rest]) when is_binary(Val) ->
    case byte_size(Val) > ?MAX_QS_VALUE_BYTES of
        true ->
            {error, invalid_query_param};
        false ->
            case binary:match(Val, <<0>>) of
                nomatch -> check_qs_values(Rest);
                _       -> {error, invalid_query_param}
            end
    end;
check_qs_values([_ | Rest]) ->
    check_qs_values(Rest).

%% @private Send an error response and stop the middleware chain.
-spec reject(atom(), cowboy_req:req()) -> {stop, cowboy_req:req()}.
reject(Reason, Req) ->
    {Code, ErrorAtom, Message} = cb_http_errors:to_response(Reason),
    Body = jsone:encode(#{error => ErrorAtom, message => Message}),
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    Req2 = cowboy_req:reply(Code, Headers, Body, Req),
    {stop, Req2}.
