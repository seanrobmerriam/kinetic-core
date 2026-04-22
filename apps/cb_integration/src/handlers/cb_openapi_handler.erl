%% @doc OpenAPI Specification Handler
%%
%% Serves the OpenAPI 3.0 specification for the IronLedger API at
%% GET /api/v1/openapi.json.  The spec covers the release-blocking
%% (Phase 0) endpoints and is generated inline from the route table.
%%
%% This endpoint is public (no authentication required) so that API
%% consumers and developer tools can discover the spec without credentials.
-module(cb_openapi_handler).

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    handle(Method, Req, State).

handle(<<"GET">>, Req, State) ->
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    Req2 = cowboy_req:reply(200, Headers, jsone:encode(spec()), Req),
    {ok, Req2, State};
handle(<<"OPTIONS">>, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};
handle(_, Req, State) ->
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    Req2 = cowboy_req:reply(405, Headers, <<"{\"error\":\"method_not_allowed\"}">>, Req),
    {ok, Req2, State}.

%% Build the OpenAPI 3.0.3 specification document.
spec() ->
    #{
        <<"openapi">> => <<"3.0.3">>,
        <<"info">> => #{
            <<"title">>       => <<"IronLedger Core Banking API">>,
            <<"version">>     => <<"0.1.0">>,
            <<"description">> => <<"Release-blocking REST API for the Kinetic Core banking platform.">>
        },
        <<"servers">> => [#{<<"url">> => <<"/api/v1">>}],
        <<"security">> => [#{<<"bearerAuth">> => []}],
        <<"components">> => #{
            <<"securitySchemes">> => #{
                <<"bearerAuth">> => #{
                    <<"type">>   => <<"http">>,
                    <<"scheme">> => <<"bearer">>
                }
            },
            <<"schemas">> => schemas()
        },
        <<"paths">> => paths()
    }.

schemas() ->
    #{
        <<"Error">> => #{
            <<"type">> => <<"object">>,
            <<"required">> => [<<"error">>, <<"message">>],
            <<"properties">> => #{
                <<"error">>   => #{<<"type">> => <<"string">>},
                <<"message">> => #{<<"type">> => <<"string">>}
            }
        },
        <<"Party">> => #{
            <<"type">> => <<"object">>,
            <<"properties">> => #{
                <<"party_id">>          => #{<<"type">> => <<"string">>, <<"format">> => <<"uuid">>},
                <<"name">>              => #{<<"type">> => <<"string">>},
                <<"email">>             => #{<<"type">> => <<"string">>, <<"format">> => <<"email">>},
                <<"status">>            => #{<<"type">> => <<"string">>},
                <<"kyc_status">>        => #{<<"type">> => <<"string">>},
                <<"onboarding_status">> => #{<<"type">> => <<"string">>},
                <<"created_at">>        => #{<<"type">> => <<"integer">>},
                <<"updated_at">>        => #{<<"type">> => <<"integer">>}
            }
        },
        <<"Account">> => #{
            <<"type">> => <<"object">>,
            <<"properties">> => #{
                <<"account_id">> => #{<<"type">> => <<"string">>, <<"format">> => <<"uuid">>},
                <<"party_id">>   => #{<<"type">> => <<"string">>, <<"format">> => <<"uuid">>},
                <<"name">>       => #{<<"type">> => <<"string">>},
                <<"currency">>   => #{<<"type">> => <<"string">>},
                <<"balance">>    => #{<<"type">> => <<"integer">>},
                <<"status">>     => #{<<"type">> => <<"string">>},
                <<"created_at">> => #{<<"type">> => <<"integer">>},
                <<"updated_at">> => #{<<"type">> => <<"integer">>}
            }
        },
        <<"Transaction">> => #{
            <<"type">> => <<"object">>,
            <<"properties">> => #{
                <<"txn_id">>            => #{<<"type">> => <<"string">>, <<"format">> => <<"uuid">>},
                <<"idempotency_key">>   => #{<<"type">> => <<"string">>},
                <<"txn_type">>          => #{<<"type">> => <<"string">>},
                <<"status">>            => #{<<"type">> => <<"string">>},
                <<"amount">>            => #{<<"type">> => <<"integer">>},
                <<"currency">>          => #{<<"type">> => <<"string">>},
                <<"source_account_id">> => #{<<"type">> => <<"string">>},
                <<"dest_account_id">>   => #{<<"type">> => <<"string">>},
                <<"description">>       => #{<<"type">> => <<"string">>},
                <<"channel">>           => #{<<"type">> => <<"string">>},
                <<"created_at">>        => #{<<"type">> => <<"integer">>},
                <<"posted_at">>         => #{<<"type">> => <<"integer">>}
            }
        }
    }.

paths() ->
    #{
        <<"/health">> => #{
            <<"get">> => #{
                <<"summary">>  => <<"Health check">>,
                <<"security">> => [],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Service is healthy">>}
                }
            }
        },
        <<"/api/v1/auth/login">> => #{
            <<"post">> => #{
                <<"summary">>  => <<"Authenticate and create session">>,
                <<"security">> => [],
                <<"requestBody">> => #{
                    <<"required">> => true,
                    <<"content">> => #{
                        <<"application/json">> => #{
                            <<"schema">> => #{
                                <<"type">> => <<"object">>,
                                <<"required">> => [<<"email">>, <<"password">>],
                                <<"properties">> => #{
                                    <<"email">>    => #{<<"type">> => <<"string">>},
                                    <<"password">> => #{<<"type">> => <<"string">>}
                                }
                            }
                        }
                    }
                },
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Session created">>},
                    <<"401">> => error_response()
                }
            }
        },
        <<"/api/v1/auth/logout">> => #{
            <<"post">> => #{
                <<"summary">> => <<"Invalidate current session">>,
                <<"responses">> => #{
                    <<"204">> => #{<<"description">> => <<"Session invalidated">>},
                    <<"401">> => error_response()
                }
            }
        },
        <<"/api/v1/auth/me">> => #{
            <<"get">> => #{
                <<"summary">> => <<"Get current authenticated user">>,
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Current user">>,
                                  <<"content">> => json_content(<<"object">>)},
                    <<"401">> => error_response()
                }
            }
        },
        <<"/api/v1/parties">> => #{
            <<"get">> => #{
                <<"summary">> => <<"List parties">>,
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"List of parties">>}
                }
            },
            <<"post">> => #{
                <<"summary">> => <<"Create a party">>,
                <<"responses">> => #{
                    <<"201">> => #{<<"description">> => <<"Party created">>},
                    <<"422">> => error_response()
                }
            }
        },
        <<"/api/v1/parties/{party_id}">> => #{
            <<"get">> => #{
                <<"summary">> => <<"Get a party by ID">>,
                <<"parameters">> => [path_param(<<"party_id">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Party record">>,
                                  <<"content">> => json_ref(<<"Party">>)},
                    <<"404">> => error_response()
                }
            }
        },
        <<"/api/v1/accounts">> => #{
            <<"get">> => #{
                <<"summary">> => <<"List accounts">>,
                <<"responses">> => #{<<"200">> => #{<<"description">> => <<"List of accounts">>}}
            }
        },
        <<"/api/v1/accounts/{account_id}">> => #{
            <<"get">> => #{
                <<"summary">> => <<"Get an account by ID">>,
                <<"parameters">> => [path_param(<<"account_id">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Account record">>,
                                  <<"content">> => json_ref(<<"Account">>)},
                    <<"404">> => error_response()
                }
            }
        },
        <<"/api/v1/accounts/{account_id}/balance">> => #{
            <<"get">> => #{
                <<"summary">> => <<"Get account balance">>,
                <<"parameters">> => [path_param(<<"account_id">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Balance information">>},
                    <<"404">> => error_response()
                }
            }
        },
        <<"/api/v1/transactions/deposit">> => #{
            <<"post">> => #{
                <<"summary">> => <<"Deposit funds into an account">>,
                <<"requestBody">> => #{
                    <<"required">> => true,
                    <<"content">> => #{
                        <<"application/json">> => #{
                            <<"schema">> => #{
                                <<"type">> => <<"object">>,
                                <<"required">> => [<<"idempotency_key">>, <<"dest_account_id">>,
                                                   <<"amount">>, <<"currency">>, <<"description">>],
                                <<"properties">> => #{
                                    <<"idempotency_key">>  => #{<<"type">> => <<"string">>},
                                    <<"dest_account_id">>  => #{<<"type">> => <<"string">>, <<"format">> => <<"uuid">>},
                                    <<"amount">>           => #{<<"type">> => <<"integer">>, <<"minimum">> => 1},
                                    <<"currency">>         => #{<<"type">> => <<"string">>},
                                    <<"description">>      => #{<<"type">> => <<"string">>},
                                    <<"channel">>          => #{<<"type">> => <<"string">>,
                                                                <<"enum">> => [<<"cash">>, <<"check">>, <<"transfer_in">>]}
                                }
                            }
                        }
                    }
                },
                <<"responses">> => #{
                    <<"201">> => #{<<"description">> => <<"Deposit posted">>,
                                  <<"content">> => json_ref(<<"Transaction">>)},
                    <<"402">> => error_response(),
                    <<"409">> => error_response(),
                    <<"422">> => error_response()
                }
            }
        },
        <<"/api/v1/transactions/transfer">> => #{
            <<"post">> => #{
                <<"summary">> => <<"Transfer funds between accounts (same currency)">>,
                <<"requestBody">> => #{
                    <<"required">> => true,
                    <<"content">> => #{
                        <<"application/json">> => #{
                            <<"schema">> => #{
                                <<"type">> => <<"object">>,
                                <<"required">> => [<<"idempotency_key">>, <<"source_account_id">>,
                                                   <<"dest_account_id">>, <<"amount">>,
                                                   <<"currency">>, <<"description">>]
                            }
                        }
                    }
                },
                <<"responses">> => #{
                    <<"201">> => #{<<"description">> => <<"Transfer posted">>},
                    <<"402">> => error_response(),
                    <<"409">> => error_response(),
                    <<"422">> => error_response()
                }
            }
        },
        <<"/api/v1/transactions/withdraw">> => #{
            <<"post">> => #{
                <<"summary">> => <<"Withdraw funds from an account">>,
                <<"requestBody">> => #{
                    <<"required">> => true,
                    <<"content">> => #{
                        <<"application/json">> => #{
                            <<"schema">> => #{
                                <<"type">> => <<"object">>,
                                <<"required">> => [<<"idempotency_key">>, <<"source_account_id">>,
                                                   <<"amount">>, <<"currency">>, <<"description">>]
                            }
                        }
                    }
                },
                <<"responses">> => #{
                    <<"201">> => #{<<"description">> => <<"Withdrawal posted">>},
                    <<"402">> => error_response(),
                    <<"409">> => error_response(),
                    <<"422">> => error_response()
                }
            }
        },
        <<"/api/v1/transactions/{txn_id}">> => #{
            <<"get">> => #{
                <<"summary">> => <<"Get a transaction by ID">>,
                <<"parameters">> => [path_param(<<"txn_id">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Transaction record">>,
                                  <<"content">> => json_ref(<<"Transaction">>)},
                    <<"404">> => error_response()
                }
            }
        },
        <<"/api/v1/transactions/{txn_id}/reverse">> => #{
            <<"post">> => #{
                <<"summary">> => <<"Reverse a posted transaction">>,
                <<"parameters">> => [path_param(<<"txn_id">>)],
                <<"responses">> => #{
                    <<"201">> => #{<<"description">> => <<"Reversal posted">>},
                    <<"404">> => error_response(),
                    <<"409">> => error_response()
                }
            }
        },
        <<"/metrics">> => #{
            <<"get">> => #{
                <<"summary">>  => <<"Erlang VM and application metrics">>,
                <<"security">> => [],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Metrics data">>,
                                  <<"content">> => json_content(<<"object">>)}
                }
            }
        },
        <<"/api/v1/openapi.json">> => #{
            <<"get">> => #{
                <<"summary">>  => <<"This OpenAPI specification">>,
                <<"security">> => [],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"OpenAPI 3.0 spec">>}
                }
            }
        }
    }.

error_response() ->
    #{<<"description">> => <<"Error">>,
      <<"content">> => #{
          <<"application/json">> => #{
              <<"schema">> => #{<<"$ref">> => <<"#/components/schemas/Error">>}
          }
      }}.

json_content(Type) ->
    #{<<"application/json">> => #{<<"schema">> => #{<<"type">> => Type}}}.

json_ref(SchemaName) ->
    #{<<"application/json">> => #{
        <<"schema">> => #{<<"$ref">> => <<"#/components/schemas/", SchemaName/binary>>}
    }}.

path_param(Name) ->
    #{<<"name">> => Name, <<"in">> => <<"path">>, <<"required">> => true,
      <<"schema">> => #{<<"type">> => <<"string">>}}.
