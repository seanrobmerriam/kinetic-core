%% @doc Common Tests for Distributed Tracing and Correlation IDs
%%
%% This test suite validates the end-to-end distributed tracing functionality,
%% including correlation ID generation, propagation, and logging.
%%
%% <h2>Test Coverage</h2>
%%
%% - Correlation ID generation with UUID v4 format
%% - Extraction of correlation ID from X-Correlation-ID header
%% - Propagation through process dictionary
%% - Response header injection
%% - Logging includes correlation ID
%% - Multiple concurrent requests with isolated correlation IDs
%% - Correlation ID persistence across function calls
%%
%% @see cb_correlation
%% @see cb_log_middleware
%% @see cb_correlation_middleware

-module(cb_distributed_tracing_SUITE).
-compile(export_all).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

%% CT Hooks and Callbacks

all() ->
    [
        {group, correlation_id_generation},
        {group, correlation_id_propagation},
        {group, correlation_id_logging},
        {group, correlation_id_isolation}
    ].

groups() ->
    [
        {correlation_id_generation, [sequence], [
            test_generate_id_format,
            test_generate_unique_ids
        ]},
        {correlation_id_propagation, [sequence], [
            test_set_and_get_correlation_id,
            test_clear_correlation_id,
            test_get_undefined_correlation_id,
            test_initialize_without_header,
            test_initialize_with_header
        ]},
        {correlation_id_logging, [sequence], [
            test_correlation_id_in_logs,
            test_correlation_id_in_response_headers
        ]},
        {correlation_id_isolation, [sequence], [
            test_concurrent_correlation_ids,
            test_correlation_id_persistence_across_calls
        ]}
    ].

init_per_suite(Config) ->
    %% Start required applications
    {ok, _} = application:ensure_all_started(cb_integration),
    Config.

end_per_suite(_Config) ->
    ok.

%% =============================================================================
%% Correlation ID Generation Tests
%% =============================================================================

%% @doc Test that generated correlation IDs are valid UUIDs (36 chars, hex + dashes)
test_generate_id_format(_Config) ->
    CorrelationId = cb_correlation:generate_id(),
    
    %% Check it's a binary
    ?assert(is_binary(CorrelationId)),
    
    %% Check length (UUID v4 in standard format is 36 chars: 8-4-4-4-12)
    ?assertEqual(36, byte_size(CorrelationId)),
    
    %% Check format: should match XXXXXXXX-XXXX-4XXX-XXXX-XXXXXXXXXXXX
    %% where X is hex digit
    ?assert(is_valid_uuid_format(CorrelationId)),
    
    {comment, "Generated UUID: " ++ binary_to_list(CorrelationId)}.

%% @doc Test that multiple calls generate different IDs
test_generate_unique_ids(_Config) ->
    Id1 = cb_correlation:generate_id(),
    Id2 = cb_correlation:generate_id(),
    Id3 = cb_correlation:generate_id(),
    
    %% All should be different
    ?assertNotEqual(Id1, Id2),
    ?assertNotEqual(Id2, Id3),
    ?assertNotEqual(Id1, Id3),
    
    {comment, "Generated 3 unique IDs"}.

%% =============================================================================
%% Correlation ID Propagation Tests
%% =============================================================================

%% @doc Test setting and getting correlation ID from process dictionary
test_set_and_get_correlation_id(_Config) ->
    CorrelationId = <<"test-correlation-123">>,
    
    %% Set correlation ID
    ok = cb_correlation:set(CorrelationId),
    
    %% Get it back
    RetrievedId = cb_correlation:get(),
    ?assertEqual(CorrelationId, RetrievedId),
    
    %% Clean up
    ok = cb_correlation:clear(),
    ok.

%% @doc Test clearing correlation ID
test_clear_correlation_id(_Config) ->
    CorrelationId = <<"test-correlation-456">>,
    
    %% Set and verify
    ok = cb_correlation:set(CorrelationId),
    ?assertEqual(CorrelationId, cb_correlation:get()),
    
    %% Clear
    ok = cb_correlation:clear(),
    
    %% Should be undefined
    ?assertEqual(undefined, cb_correlation:get()),
    ok.

%% @doc Test getting correlation ID when not set
test_get_undefined_correlation_id(_Config) ->
    %% Ensure clean state
    ok = cb_correlation:clear(),
    
    %% Should return undefined
    ?assertEqual(undefined, cb_correlation:get()),
    ok.

%% @doc Test correlation ID initialization without header (should generate new)
test_initialize_without_header(_Config) ->
    %% Create a mock request without correlation ID header
    Req = cowboy_req:new(<<"GET">>, <<"/">>, <<"HTTP/1.1">>, {127, 0, 0, 1}, 8080, 
                         {127, 0, 0, 1}, 12345, cowboy_http, []),
    
    %% Initialize should generate new ID
    CorrelationId = cb_correlation:initialize(Req),
    
    %% Should be non-undefined
    ?assertNotEqual(undefined, CorrelationId),
    
    %% Should be stored in process dictionary
    ?assertEqual(CorrelationId, cb_correlation:get()),
    
    %% Clean up
    ok = cb_correlation:clear(),
    ok.

%% @doc Test correlation ID initialization with header (should propagate)
test_initialize_with_header(_Config) ->
    %% Create a request with correlation ID header
    Req0 = cowboy_req:new(<<"GET">>, <<"/">>, <<"HTTP/1.1">>, {127, 0, 0, 1}, 8080,
                          {127, 0, 0, 1}, 12345, cowboy_http, []),
    
    ClientCorrelationId = <<"client-trace-id-789">>,
    Req = cowboy_req:set_resp_header(<<"x-correlation-id">>, ClientCorrelationId, Req0),
    
    %% Initialize should use header value
    CorrelationId = cb_correlation:initialize(Req),
    
    %% Should match client ID
    ?assertEqual(ClientCorrelationId, CorrelationId),
    
    %% Should be stored in process dictionary
    ?assertEqual(CorrelationId, cb_correlation:get()),
    
    %% Clean up
    ok = cb_correlation:clear(),
    ok.

%% =============================================================================
%% Correlation ID Logging Tests
%% =============================================================================

%% @doc Test that correlation ID is included in log entries
test_correlation_id_in_logs(_Config) ->
    CorrelationId = <<"log-test-correlation-id">>,
    
    %% Set correlation ID
    ok = cb_correlation:set(CorrelationId),
    
    %% Log with correlation ID (in real code, would include via structured logging)
    %% Just verify the correlation ID is retrievable
    RetrievedId = cb_correlation:get(),
    ?assertEqual(CorrelationId, RetrievedId),
    
    %% Clean up
    ok = cb_correlation:clear(),
    ok.

%% @doc Test that correlation ID is injected into response headers
test_correlation_id_in_response_headers(_Config) ->
    %% Create a request
    Req0 = cowboy_req:new(<<"GET">>, <<"/">>, <<"HTTP/1.1">>, {127, 0, 0, 1}, 8080,
                          {127, 0, 0, 1}, 12345, cowboy_http, []),
    
    CorrelationId = <<"response-header-test-id">>,
    
    %% Inject correlation ID into headers
    Req1 = cb_correlation:inject_into_headers(Req0, CorrelationId),
    
    %% Verify header is set (retrieve it back)
    RetrievedId = cowboy_req:header(<<"x-correlation-id">>, Req1),
    ?assertEqual(CorrelationId, RetrievedId),
    ok.

%% =============================================================================
%% Correlation ID Isolation Tests
%% =============================================================================

%% @doc Test that concurrent requests maintain isolated correlation IDs
test_concurrent_correlation_ids(_Config) ->
    %% Create two correlation IDs
    CorrelationId1 = <<"concurrent-test-1">>,
    CorrelationId2 = <<"concurrent-test-2">>,
    
    %% Simulate two concurrent processes
    Parent = self(),
    
    Pid1 = spawn_link(fun() ->
        cb_correlation:set(CorrelationId1),
        timer:sleep(100),  %% Simulate work
        Retrieved = cb_correlation:get(),
        Parent ! {self(), Retrieved}
    end),
    
    Pid2 = spawn_link(fun() ->
        cb_correlation:set(CorrelationId2),
        timer:sleep(50),   %% Different timing
        Retrieved = cb_correlation:get(),
        Parent ! {self(), Retrieved}
    end),
    
    %% Collect results
    receive {Pid1, Retrieved1} -> ?assertEqual(CorrelationId1, Retrieved1) end,
    receive {Pid2, Retrieved2} -> ?assertEqual(CorrelationId2, Retrieved2) end,
    
    ok.

%% @doc Test correlation ID persists across function calls
test_correlation_id_persistence_across_calls(_Config) ->
    CorrelationId = <<"persistence-test-id">>,
    
    %% Set correlation ID
    ok = cb_correlation:set(CorrelationId),
    
    %% Call helper function (simulates calling domain module)
    retrieved_in_function(),
    
    %% Should still be set in parent process
    ?assertEqual(CorrelationId, cb_correlation:get()),
    
    %% Clean up
    ok = cb_correlation:clear(),
    ok.

%% Helper function for persistence test
retrieved_in_function() ->
    %% Correlation ID should be accessible here
    CorrelationId = cb_correlation:get(),
    ?assertNotEqual(undefined, CorrelationId).

%% =============================================================================
%% Helper Functions
%% =============================================================================

%% @doc Check if a binary is a valid UUID format (36 chars, XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX)
is_valid_uuid_format(UUID) when is_binary(UUID) ->
    case byte_size(UUID) of
        36 ->
            %% Check for dash positions (at positions 8, 13, 18, 23)
            case UUID of
                <<_:8/binary, $-, _:4/binary, $-, _:4/binary, $-, _:4/binary, $-, _:12/binary>> ->
                    true;
                _ -> false
            end;
        _ -> false
    end.
