%% @doc OpenAPI Specification Handler
%%
%% Serves the OpenAPI 3.0 specification for the Kinetic Core API at
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
    {_Code405, _Hdrs405, _Body405} = cb_http_errors:to_response_with_metrics(method_not_allowed),
    Req2 = cowboy_req:reply(_Code405, _Hdrs405, _Body405, Req),
    {ok, Req2, State}.

%% Build the OpenAPI 3.0.3 specification document.
spec() ->
    #{
        <<"openapi">> => <<"3.0.3">>,
        <<"info">> => #{
            <<"title">>       => <<"Kinetic Core Core Banking API">>,
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
        <<"RbacUser">> => #{
            <<"type">> => <<"object">>,
            <<"properties">> => #{
                <<"user_id">> => #{<<"type">> => <<"string">>, <<"format">> => <<"uuid">>},
                <<"email">> => #{<<"type">> => <<"string">>},
                <<"role">> => #{<<"type">> => <<"string">>},
                <<"status">> => #{<<"type">> => <<"string">>},
                <<"created_at">> => #{<<"type">> => <<"integer">>},
                <<"updated_at">> => #{<<"type">> => <<"integer">>},
                <<"roles">> => #{<<"type">> => <<"array">>, <<"items">> => #{<<"type">> => <<"string">>}},
                <<"permissions">> => #{<<"type">> => <<"array">>, <<"items">> => #{<<"type">> => <<"string">>}},
                <<"effective">> => #{<<"type">> => <<"object">>}
            }
        },
        <<"RbacUserList">> => #{
            <<"type">> => <<"object">>,
            <<"properties">> => #{
                <<"items">> => #{<<"type">> => <<"array">>, <<"items">> => #{<<"$ref">> => <<"#/components/schemas/RbacUser">>}},
                <<"total">> => #{<<"type">> => <<"integer">>}
            }
        },
        <<"RbacRolePermissionKeys">> => #{
            <<"type">> => <<"object">>,
            <<"properties">> => #{
                <<"role_id">> => #{<<"type">> => <<"string">>, <<"format">> => <<"uuid">>},
                <<"permission_keys">> => #{<<"type">> => <<"array">>, <<"items">> => #{<<"type">> => <<"string">>}}
            }
        },
        <<"RbacRoleList">> => #{
            <<"type">> => <<"object">>,
            <<"properties">> => #{
                <<"items">> => #{<<"type">> => <<"array">>, <<"items">> => #{<<"$ref">> => <<"#/components/schemas/RbacRole">>}},
                <<"total">> => #{<<"type">> => <<"integer">>}
            }
        },
        <<"RbacPermission">> => #{
            <<"type">> => <<"object">>,
            <<"properties">> => #{
                <<"permission_id">> => #{<<"type">> => <<"string">>, <<"format">> => <<"uuid">>},
                <<"permission_key">> => #{<<"type">> => <<"string">>},
                <<"resource">> => #{<<"type">> => <<"string">>},
                <<"action">> => #{<<"type">> => <<"string">>},
                <<"description">> => #{<<"type">> => <<"string">>},
                <<"status">> => #{<<"type">> => <<"string">>},
                <<"created_at">> => #{<<"type">> => <<"integer">>},
                <<"updated_at">> => #{<<"type">> => <<"integer">>}
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
        },
        <<"LedgerEntry">> => #{
            <<"type">> => <<"object">>,
            <<"properties">> => #{
                <<"entry_id">>   => #{<<"type">> => <<"string">>, <<"format">> => <<"uuid">>},
                <<"txn_id">>     => #{<<"type">> => <<"string">>, <<"format">> => <<"uuid">>},
                <<"account_id">> => #{<<"type">> => <<"string">>, <<"format">> => <<"uuid">>},
                <<"entry_type">> => #{<<"type">> => <<"string">>, <<"enum">> => [<<"debit">>, <<"credit">>]},
                <<"amount">>     => #{<<"type">> => <<"integer">>},
                <<"currency">>   => #{<<"type">> => <<"string">>},
                <<"description">> => #{<<"type">> => <<"string">>},
                <<"posted_at">>  => #{<<"type">> => <<"integer">>}
            }
        },
        <<"AccountHold">> => #{
            <<"type">> => <<"object">>,
            <<"properties">> => #{
                <<"hold_id">>     => #{<<"type">> => <<"string">>, <<"format">> => <<"uuid">>},
                <<"account_id">>  => #{<<"type">> => <<"string">>, <<"format">> => <<"uuid">>},
                <<"amount">>      => #{<<"type">> => <<"integer">>},
                <<"reason">>      => #{<<"type">> => <<"string">>},
                <<"status">>      => #{<<"type">> => <<"string">>, <<"enum">> => [<<"active">>, <<"released">>, <<"expired">>]},
                <<"placed_at">>   => #{<<"type">> => <<"integer">>},
                <<"released_at">> => #{<<"type">> => <<"integer">>},
                <<"expires_at">>  => #{<<"type">> => <<"integer">>}
            }
        },
        <<"SavingsProduct">> => #{
            <<"type">> => <<"object">>,
            <<"properties">> => #{
                <<"product_id">>         => #{<<"type">> => <<"string">>, <<"format">> => <<"uuid">>},
                <<"name">>               => #{<<"type">> => <<"string">>},
                <<"description">>        => #{<<"type">> => <<"string">>},
                <<"currency">>           => #{<<"type">> => <<"string">>},
                <<"interest_rate">>      => #{<<"type">> => <<"integer">>},
                <<"interest_type">>      => #{<<"type">> => <<"string">>},
                <<"compounding_period">> => #{<<"type">> => <<"string">>},
                <<"minimum_balance">>    => #{<<"type">> => <<"integer">>},
                <<"status">>             => #{<<"type">> => <<"string">>},
                <<"created_at">>         => #{<<"type">> => <<"integer">>},
                <<"updated_at">>         => #{<<"type">> => <<"integer">>}
            }
        },
        <<"LoanProduct">> => #{
            <<"type">> => <<"object">>,
            <<"properties">> => #{
                <<"product_id">>       => #{<<"type">> => <<"string">>, <<"format">> => <<"uuid">>},
                <<"name">>             => #{<<"type">> => <<"string">>},
                <<"description">>      => #{<<"type">> => <<"string">>},
                <<"currency">>         => #{<<"type">> => <<"string">>},
                <<"min_amount">>       => #{<<"type">> => <<"integer">>},
                <<"max_amount">>       => #{<<"type">> => <<"integer">>},
                <<"min_term_months">>  => #{<<"type">> => <<"integer">>},
                <<"max_term_months">>  => #{<<"type">> => <<"integer">>},
                <<"interest_rate">>    => #{<<"type">> => <<"integer">>},
                <<"interest_type">>    => #{<<"type">> => <<"string">>},
                <<"status">>           => #{<<"type">> => <<"string">>},
                <<"created_at">>       => #{<<"type">> => <<"integer">>},
                <<"updated_at">>       => #{<<"type">> => <<"integer">>}
            }
        },
        <<"Loan">> => #{
            <<"type">> => <<"object">>,
            <<"properties">> => #{
                <<"loan_id">>             => #{<<"type">> => <<"string">>, <<"format">> => <<"uuid">>},
                <<"product_id">>          => #{<<"type">> => <<"string">>, <<"format">> => <<"uuid">>},
                <<"party_id">>            => #{<<"type">> => <<"string">>, <<"format">> => <<"uuid">>},
                <<"account_id">>          => #{<<"type">> => <<"string">>, <<"format">> => <<"uuid">>},
                <<"principal">>           => #{<<"type">> => <<"integer">>},
                <<"currency">>            => #{<<"type">> => <<"string">>},
                <<"interest_rate">>       => #{<<"type">> => <<"integer">>},
                <<"term_months">>         => #{<<"type">> => <<"integer">>},
                <<"monthly_payment">>     => #{<<"type">> => <<"integer">>},
                <<"outstanding_balance">> => #{<<"type">> => <<"integer">>},
                <<"status">>              => #{<<"type">> => <<"string">>},
                <<"disbursed_at">>        => #{<<"type">> => <<"integer">>},
                <<"created_at">>          => #{<<"type">> => <<"integer">>},
                <<"updated_at">>          => #{<<"type">> => <<"integer">>}
            }
        },
        <<"LoanRepayment">> => #{
            <<"type">> => <<"object">>,
            <<"properties">> => #{
                <<"repayment_id">>       => #{<<"type">> => <<"string">>, <<"format">> => <<"uuid">>},
                <<"loan_id">>            => #{<<"type">> => <<"string">>, <<"format">> => <<"uuid">>},
                <<"amount">>             => #{<<"type">> => <<"integer">>},
                <<"principal_portion">>  => #{<<"type">> => <<"integer">>},
                <<"interest_portion">>   => #{<<"type">> => <<"integer">>},
                <<"penalty">>            => #{<<"type">> => <<"integer">>},
                <<"due_date">>           => #{<<"type">> => <<"integer">>},
                <<"paid_at">>            => #{<<"type">> => <<"integer">>},
                <<"status">>             => #{<<"type">> => <<"string">>},
                <<"created_at">>         => #{<<"type">> => <<"integer">>}
            }
        },
        <<"PaymentOrder">> => #{
            <<"type">> => <<"object">>,
            <<"properties">> => #{
                <<"payment_id">>        => #{<<"type">> => <<"string">>, <<"format">> => <<"uuid">>},
                <<"idempotency_key">>   => #{<<"type">> => <<"string">>},
                <<"party_id">>          => #{<<"type">> => <<"string">>, <<"format">> => <<"uuid">>},
                <<"source_account_id">> => #{<<"type">> => <<"string">>, <<"format">> => <<"uuid">>},
                <<"dest_account_id">>   => #{<<"type">> => <<"string">>, <<"format">> => <<"uuid">>},
                <<"amount">>            => #{<<"type">> => <<"integer">>},
                <<"currency">>          => #{<<"type">> => <<"string">>},
                <<"description">>       => #{<<"type">> => <<"string">>},
                <<"status">>            => #{<<"type">> => <<"string">>},
                <<"stp_decision">>      => #{<<"type">> => <<"string">>},
                <<"failure_reason">>    => #{<<"type">> => <<"string">>},
                <<"retry_count">>       => #{<<"type">> => <<"integer">>},
                <<"created_at">>        => #{<<"type">> => <<"integer">>},
                <<"updated_at">>        => #{<<"type">> => <<"integer">>}
            }
        },
        <<"ExceptionItem">> => #{
            <<"type">> => <<"object">>,
            <<"properties">> => #{
                <<"item_id">>          => #{<<"type">> => <<"string">>, <<"format">> => <<"uuid">>},
                <<"payment_id">>       => #{<<"type">> => <<"string">>, <<"format">> => <<"uuid">>},
                <<"reason">>           => #{<<"type">> => <<"string">>},
                <<"status">>           => #{<<"type">> => <<"string">>},
                <<"resolution">>       => #{<<"type">> => <<"string">>},
                <<"resolved_by">>      => #{<<"type">> => <<"string">>},
                <<"resolution_notes">> => #{<<"type">> => <<"string">>},
                <<"created_at">>       => #{<<"type">> => <<"integer">>},
                <<"updated_at">>       => #{<<"type">> => <<"integer">>}
            }
        },
        <<"ChannelLimit">> => #{
            <<"type">> => <<"object">>,
            <<"properties">> => #{
                <<"limit_key">> => #{
                    <<"type">> => <<"object">>,
                    <<"properties">> => #{
                        <<"channel">>  => #{<<"type">> => <<"string">>},
                        <<"currency">> => #{<<"type">> => <<"string">>}
                    }
                },
                <<"daily_limit">>   => #{<<"type">> => <<"integer">>},
                <<"per_txn_limit">> => #{<<"type">> => <<"integer">>},
                <<"updated_at">>    => #{<<"type">> => <<"integer">>}
            }
        },
        <<"ChannelActivity">> => #{
            <<"type">> => <<"object">>,
            <<"properties">> => #{
                <<"log_id">>      => #{<<"type">> => <<"string">>, <<"format">> => <<"uuid">>},
                <<"channel">>     => #{<<"type">> => <<"string">>},
                <<"party_id">>    => #{<<"type">> => <<"string">>, <<"format">> => <<"uuid">>},
                <<"action">>      => #{<<"type">> => <<"string">>},
                <<"endpoint">>    => #{<<"type">> => <<"string">>},
                <<"status_code">> => #{<<"type">> => <<"integer">>},
                <<"created_at">>  => #{<<"type">> => <<"integer">>}
            }
        },
        <<"NotificationPreference">> => #{
            <<"type">> => <<"object">>,
            <<"properties">> => #{
                <<"pref_id">>     => #{<<"type">> => <<"string">>, <<"format">> => <<"uuid">>},
                <<"party_id">>    => #{<<"type">> => <<"string">>, <<"format">> => <<"uuid">>},
                <<"channel">>     => #{<<"type">> => <<"string">>},
                <<"event_types">> => #{<<"type">> => <<"array">>, <<"items">> => #{<<"type">> => <<"string">>}},
                <<"enabled">>     => #{<<"type">> => <<"boolean">>},
                <<"updated_at">>  => #{<<"type">> => <<"integer">>}
            }
        },
        <<"DomainEvent">> => #{
            <<"type">> => <<"object">>,
            <<"properties">> => #{
                <<"event_id">>   => #{<<"type">> => <<"string">>, <<"format">> => <<"uuid">>},
                <<"event_type">> => #{<<"type">> => <<"string">>},
                <<"payload">>    => #{<<"type">> => <<"object">>},
                <<"status">>     => #{<<"type">> => <<"string">>},
                <<"created_at">> => #{<<"type">> => <<"integer">>},
                <<"updated_at">> => #{<<"type">> => <<"integer">>}
            }
        },
        <<"WebhookSubscription">> => #{
            <<"type">> => <<"object">>,
            <<"properties">> => #{
                <<"subscription_id">> => #{<<"type">> => <<"string">>, <<"format">> => <<"uuid">>},
                <<"event_type">>      => #{<<"type">> => <<"string">>},
                <<"callback_url">>    => #{<<"type">> => <<"string">>, <<"format">> => <<"uri">>},
                <<"status">>          => #{<<"type">> => <<"string">>},
                <<"created_at">>      => #{<<"type">> => <<"integer">>},
                <<"updated_at">>      => #{<<"type">> => <<"integer">>}
            }
        },
        <<"ApiKey">> => #{
            <<"type">> => <<"object">>,
            <<"properties">> => #{
                <<"key_id">>             => #{<<"type">> => <<"string">>, <<"format">> => <<"uuid">>},
                <<"label">>              => #{<<"type">> => <<"string">>},
                <<"partner_id">>         => #{<<"type">> => <<"string">>},
                <<"role">>               => #{<<"type">> => <<"string">>, <<"enum">> => [<<"admin">>, <<"operations">>, <<"read_only">>]},
                <<"status">>             => #{<<"type">> => <<"string">>, <<"enum">> => [<<"active">>, <<"revoked">>]},
                <<"rate_limit_per_min">> => #{<<"type">> => <<"integer">>},
                <<"expires_at">>         => #{<<"type">> => <<"integer">>},
                <<"created_at">>         => #{<<"type">> => <<"integer">>},
                <<"updated_at">>         => #{<<"type">> => <<"integer">>}
            }
        },
        <<"OAuthToken">> => #{
            <<"type">> => <<"object">>,
            <<"properties">> => #{
                <<"access_token">> => #{<<"type">> => <<"string">>},
                <<"token_type">>   => #{<<"type">> => <<"string">>, <<"example">> => <<"Bearer">>},
                <<"expires_in">>   => #{<<"type">> => <<"integer">>, <<"description">> => <<"Seconds until expiry">>}
            },
            <<"required">> => [<<"access_token">>, <<"token_type">>, <<"expires_in">>]
        },
        <<"WebhookDelivery">> => #{
            <<"type">> => <<"object">>,
            <<"properties">> => #{
                <<"delivery_id">>      => #{<<"type">> => <<"string">>, <<"format">> => <<"uuid">>},
                <<"subscription_id">>  => #{<<"type">> => <<"string">>, <<"format">> => <<"uuid">>},
                <<"event_id">>         => #{<<"type">> => <<"string">>, <<"format">> => <<"uuid">>},
                <<"attempt_status">>   => #{<<"type">> => <<"string">>, <<"enum">> => [<<"success">>, <<"failed">>, <<"pending">>]},
                <<"response_code">>    => #{<<"type">> => <<"integer">>},
                <<"created_at">>       => #{<<"type">> => <<"integer">>},
                <<"updated_at">>       => #{<<"type">> => <<"integer">>}
            }
        },
        <<"ApiKeyUsage">> => #{
            <<"type">> => <<"object">>,
            <<"properties">> => #{
                <<"key_id">>     => #{<<"type">> => <<"string">>, <<"format">> => <<"uuid">>},
                <<"method">>     => #{<<"type">> => <<"string">>},
                <<"path">>       => #{<<"type">> => <<"string">>},
                <<"recorded_at">> => #{<<"type">> => <<"integer">>}
            }
        },
        <<"Contract">> => #{
            <<"type">> => <<"object">>,
            <<"properties">> => #{
                <<"contract_id">>   => #{<<"type">> => <<"string">>},
                <<"name">>          => #{<<"type">> => <<"string">>},
                <<"domain">>        => #{<<"type">> => <<"string">>},
                <<"owner_role">>    => #{<<"type">> => <<"string">>},
                <<"status">>        => #{<<"type">> => <<"string">>, <<"enum">> => [<<"active">>, <<"inactive">>, <<"deprecated">>]},
                <<"active_version">> => #{<<"type">> => <<"string">>},
                <<"created_at">>    => #{<<"type">> => <<"integer">>},
                <<"updated_at">>    => #{<<"type">> => <<"integer">>}
            }
        },
        <<"ContractVersion">> => #{
            <<"type">> => <<"object">>,
            <<"properties">> => #{
                <<"version_id">>      => #{<<"type">> => <<"string">>},
                <<"contract_id">>     => #{<<"type">> => <<"string">>},
                <<"version">>         => #{<<"type">> => <<"string">>},
                <<"dsl_version">>     => #{<<"type">> => <<"string">>},
                <<"status">>          => #{<<"type">> => <<"string">>, <<"enum">> => [<<"draft">>, <<"active">>, <<"deprecated">>]},
                <<"contract_payload">> => #{<<"type">> => <<"object">>},
                <<"checksum">>        => #{<<"type">> => <<"string">>},
                <<"created_by">>      => #{<<"type">> => <<"string">>},
                <<"created_at">>      => #{<<"type">> => <<"integer">>},
                <<"updated_at">>      => #{<<"type">> => <<"integer">>},
                <<"migration_from">>  => #{<<"type">> => <<"string">>}
            }
        },
        <<"ContractMigration">> => #{
            <<"type">> => <<"object">>,
            <<"properties">> => #{
                <<"migration_id">>  => #{<<"type">> => <<"string">>},
                <<"contract_id">>   => #{<<"type">> => <<"string">>},
                <<"from_version">>  => #{<<"type">> => <<"string">>},
                <<"to_version">>    => #{<<"type">> => <<"string">>},
                <<"strategy">>      => #{<<"type">> => <<"string">>, <<"enum">> => [<<"compatible">>, <<"transform">>, <<"manual">>]},
                <<"notes">>         => #{<<"type">> => <<"string">>},
                <<"created_by">>    => #{<<"type">> => <<"string">>},
                <<"created_at">>    => #{<<"type">> => <<"integer">>}
            }
        },
        <<"ContractExperiment">> => #{
            <<"type">> => <<"object">>,
            <<"properties">> => #{
                <<"experiment_id">>   => #{<<"type">> => <<"string">>},
                <<"contract_id">>     => #{<<"type">> => <<"string">>},
                <<"name">>            => #{<<"type">> => <<"string">>},
                <<"status">>          => #{<<"type">> => <<"string">>, <<"enum">> => [<<"draft">>, <<"active">>, <<"stopped">>]},
                <<"variants">>        => #{<<"type">> => <<"array">>, <<"items">> => #{<<"type">> => <<"object">>}},
                <<"allocation_seed">> => #{<<"type">> => <<"string">>},
                <<"created_by">>      => #{<<"type">> => <<"string">>},
                <<"created_at">>      => #{<<"type">> => <<"integer">>},
                <<"updated_at">>      => #{<<"type">> => <<"integer">>}
            }
        },
        <<"ContractExecutionTrace">> => #{
            <<"type">> => <<"object">>,
            <<"properties">> => #{
                <<"execution_id">>     => #{<<"type">> => <<"string">>},
                <<"contract_id">>      => #{<<"type">> => <<"string">>},
                <<"contract_version">> => #{<<"type">> => <<"string">>},
                <<"request_id">>       => #{<<"type">> => <<"string">>},
                <<"input_hash">>       => #{<<"type">> => <<"string">>},
                <<"decision_hash">>    => #{<<"type">> => <<"string">>},
                <<"result">>           => #{<<"type">> => <<"string">>, <<"enum">> => [<<"running">>, <<"ok">>, <<"error">>]},
                <<"reason">>           => #{<<"type">> => <<"string">>},
                <<"started_at_us">>    => #{<<"type">> => <<"integer">>},
                <<"finished_at_us">>   => #{<<"type">> => <<"integer">>},
                <<"duration_us">>      => #{<<"type">> => <<"integer">>},
                <<"context_snapshot">> => #{<<"type">> => <<"object">>},
                <<"decision_snapshot">> => #{<<"type">> => <<"object">>},
                <<"created_at">>       => #{<<"type">> => <<"integer">>}
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
        <<"/api/v1/users">> => #{
            <<"get">> => #{
                <<"summary">> => <<"List users">>,
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"List of users">>,
                                  <<"content">> => json_ref(<<"RbacUserList">>)},
                    <<"403">> => error_response()
                }
            },
            <<"post">> => #{
                <<"summary">> => <<"Create user">>,
                <<"requestBody">> => #{
                    <<"required">> => true,
                    <<"content">> => #{
                        <<"application/json">> => #{
                            <<"schema">> => #{
                                <<"type">> => <<"object">>,
                                <<"required">> => [<<"email">>, <<"password">>, <<"role">>],
                                <<"properties">> => #{
                                    <<"email">> => #{<<"type">> => <<"string">>},
                                    <<"password">> => #{<<"type">> => <<"string">>},
                                    <<"role">> => #{<<"type">> => <<"string">>, <<"enum">> => [<<"admin">>, <<"operations">>, <<"read_only">>]}
                                }
                            }
                        }
                    }
                },
                <<"responses">> => #{
                    <<"201">> => #{<<"description">> => <<"User created">>,
                                  <<"content">> => json_ref(<<"RbacUser">>)},
                    <<"409">> => error_response(),
                    <<"422">> => error_response()
                }
            }
        },
        <<"/api/v1/users/{user_id}">> => #{
            <<"get">> => #{
                <<"summary">> => <<"Get user by ID">>,
                <<"parameters">> => [path_param(<<"user_id">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"User detail">>,
                                  <<"content">> => json_ref(<<"RbacUser">>)},
                    <<"404">> => error_response()
                }
            },
            <<"patch">> => #{
                <<"summary">> => <<"Update user">>,
                <<"parameters">> => [path_param(<<"user_id">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"User updated">>,
                                  <<"content">> => json_ref(<<"RbacUser">>)},
                    <<"404">> => error_response(),
                    <<"422">> => error_response()
                }
            }
        },
        <<"/api/v1/users/{user_id}/roles">> => #{
            <<"post">> => #{
                <<"summary">> => <<"Assign role to user">>,
                <<"parameters">> => [path_param(<<"user_id">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Role assigned">>},
                    <<"404">> => error_response(),
                    <<"422">> => error_response()
                }
            }
        },
        <<"/api/v1/users/{user_id}/roles/{role_id}">> => #{
            <<"delete">> => #{
                <<"summary">> => <<"Unassign role from user">>,
                <<"parameters">> => [path_param(<<"user_id">>), path_param(<<"role_id">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Role unassigned">>},
                    <<"404">> => error_response()
                }
            }
        },
        <<"/api/v1/roles">> => #{
            <<"get">> => #{
                <<"summary">> => <<"List roles">>,
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"List of roles">>,
                                  <<"content">> => json_ref(<<"RbacRoleList">>)}
                }
            },
            <<"post">> => #{
                <<"summary">> => <<"Create role">>,
                <<"responses">> => #{
                    <<"201">> => #{<<"description">> => <<"Role created">>,
                                  <<"content">> => json_ref(<<"RbacRole">>)},
                    <<"409">> => error_response(),
                    <<"422">> => error_response()
                }
            }
        },
        <<"/api/v1/roles/{role_id}">> => #{
            <<"patch">> => #{
                <<"summary">> => <<"Update role">>,
                <<"parameters">> => [path_param(<<"role_id">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Role updated">>,
                                  <<"content">> => json_ref(<<"RbacRole">>)},
                    <<"404">> => error_response(),
                    <<"409">> => error_response(),
                    <<"422">> => error_response()
                }
            }
        },
        <<"/api/v1/roles/{role_id}/permissions">> => #{
            <<"get">> => #{
                <<"summary">> => <<"List role permission keys">>,
                <<"parameters">> => [path_param(<<"role_id">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Role permission keys">>,
                                  <<"content">> => json_content(<<"object">>)},
                    <<"404">> => error_response()
                }
            },
            <<"put">> => #{
                <<"summary">> => <<"Replace role permissions">>,
                <<"parameters">> => [path_param(<<"role_id">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Role permissions updated">>},
                    <<"404">> => error_response(),
                    <<"422">> => error_response()
                }
            }
        },
        <<"/api/v1/permissions">> => #{
            <<"get">> => #{
                <<"summary">> => <<"Permission catalog">>,
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Grouped permissions">>,
                                  <<"content">> => json_content(<<"object">>)}
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
        <<"/api/v1/parties/{party_id}/suspend">> => #{
            <<"post">> => #{
                <<"summary">> => <<"Suspend a party">>,
                <<"parameters">> => [path_param(<<"party_id">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Party suspended">>,
                                  <<"content">> => json_ref(<<"Party">>)},
                    <<"404">> => error_response(),
                    <<"409">> => error_response()
                }
            }
        },
        <<"/api/v1/parties/{party_id}/reactivate">> => #{
            <<"post">> => #{
                <<"summary">> => <<"Reactivate a suspended party">>,
                <<"parameters">> => [path_param(<<"party_id">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Party reactivated">>,
                                  <<"content">> => json_ref(<<"Party">>)},
                    <<"404">> => error_response(),
                    <<"409">> => error_response()
                }
            }
        },
        <<"/api/v1/parties/{party_id}/close">> => #{
            <<"post">> => #{
                <<"summary">> => <<"Close a party">>,
                <<"parameters">> => [path_param(<<"party_id">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Party closed">>,
                                  <<"content">> => json_ref(<<"Party">>)},
                    <<"404">> => error_response(),
                    <<"409">> => error_response()
                }
            }
        },
        <<"/api/v1/parties/{party_id}/kyc">> => #{
            <<"get">> => #{
                <<"summary">> => <<"Get KYC status for a party">>,
                <<"parameters">> => [path_param(<<"party_id">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"KYC record">>,
                                  <<"content">> => json_content(<<"object">>)},
                    <<"404">> => error_response()
                }
            },
            <<"put">> => #{
                <<"summary">> => <<"Update KYC status for a party">>,
                <<"parameters">> => [path_param(<<"party_id">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"KYC updated">>,
                                  <<"content">> => json_ref(<<"Party">>)},
                    <<"404">> => error_response(),
                    <<"422">> => error_response()
                }
            }
        },
        <<"/api/v1/parties/{party_id}/accounts">> => #{
            <<"get">> => #{
                <<"summary">> => <<"List accounts for a party">>,
                <<"parameters">> => [path_param(<<"party_id">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Party accounts">>},
                    <<"404">> => error_response()
                }
            }
        },
        <<"/api/v1/parties/{party_id}/profile">> => #{
            <<"get">> => #{
                <<"summary">> => <<"Get composite party profile">>,
                <<"parameters">> => [path_param(<<"party_id">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Party profile with accounts and recent transactions">>,
                                  <<"content">> => json_content(<<"object">>)},
                    <<"404">> => error_response()
                }
            }
        },
        <<"/api/v1/parties/{party_id}/notification-preferences">> => #{
            <<"get">> => #{
                <<"summary">> => <<"Get notification preferences for a party">>,
                <<"parameters">> => [path_param(<<"party_id">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Notification preferences">>}
                }
            },
            <<"put">> => #{
                <<"summary">> => <<"Update notification preferences for a party">>,
                <<"parameters">> => [path_param(<<"party_id">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Preferences updated">>,
                                  <<"content">> => json_ref(<<"NotificationPreference">>)},
                    <<"422">> => error_response()
                }
            }
        },
        <<"/api/v1/accounts">> => #{
            <<"get">> => #{
                <<"summary">> => <<"List accounts">>,
                <<"responses">> => #{<<"200">> => #{<<"description">> => <<"List of accounts">>}}
            },
            <<"post">> => #{
                <<"summary">> => <<"Create an account">>,
                <<"responses">> => #{
                    <<"201">> => #{<<"description">> => <<"Account created">>,
                                  <<"content">> => json_ref(<<"Account">>)},
                    <<"422">> => error_response()
                }
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
            },
            <<"put">> => #{
                <<"summary">> => <<"Update an account">>,
                <<"parameters">> => [path_param(<<"account_id">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Account updated">>,
                                  <<"content">> => json_ref(<<"Account">>)},
                    <<"404">> => error_response(),
                    <<"422">> => error_response()
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
        <<"/api/v1/accounts/{account_id}/transactions">> => #{
            <<"get">> => #{
                <<"summary">> => <<"List transactions for an account">>,
                <<"parameters">> => [path_param(<<"account_id">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Account transactions">>},
                    <<"404">> => error_response()
                }
            }
        },
        <<"/api/v1/accounts/{account_id}/holds">> => #{
            <<"get">> => #{
                <<"summary">> => <<"List holds on an account">>,
                <<"parameters">> => [path_param(<<"account_id">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Account holds">>},
                    <<"404">> => error_response()
                }
            },
            <<"post">> => #{
                <<"summary">> => <<"Place a hold on an account">>,
                <<"parameters">> => [path_param(<<"account_id">>)],
                <<"responses">> => #{
                    <<"201">> => #{<<"description">> => <<"Hold placed">>,
                                  <<"content">> => json_ref(<<"AccountHold">>)},
                    <<"404">> => error_response(),
                    <<"422">> => error_response()
                }
            }
        },
        <<"/api/v1/accounts/{account_id}/holds/{hold_id}">> => #{
            <<"delete">> => #{
                <<"summary">> => <<"Release a hold">>,
                <<"parameters">> => [path_param(<<"account_id">>), path_param(<<"hold_id">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Hold released">>},
                    <<"404">> => error_response()
                }
            }
        },
        <<"/api/v1/accounts/{account_id}/freeze">> => #{
            <<"post">> => #{
                <<"summary">> => <<"Freeze an account">>,
                <<"parameters">> => [path_param(<<"account_id">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Account frozen">>,
                                  <<"content">> => json_ref(<<"Account">>)},
                    <<"404">> => error_response(),
                    <<"409">> => error_response()
                }
            }
        },
        <<"/api/v1/accounts/{account_id}/unfreeze">> => #{
            <<"post">> => #{
                <<"summary">> => <<"Unfreeze an account">>,
                <<"parameters">> => [path_param(<<"account_id">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Account unfrozen">>,
                                  <<"content">> => json_ref(<<"Account">>)},
                    <<"404">> => error_response(),
                    <<"409">> => error_response()
                }
            }
        },
        <<"/api/v1/accounts/{account_id}/close">> => #{
            <<"post">> => #{
                <<"summary">> => <<"Close an account">>,
                <<"parameters">> => [path_param(<<"account_id">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Account closed">>,
                                  <<"content">> => json_ref(<<"Account">>)},
                    <<"404">> => error_response(),
                    <<"409">> => error_response()
                }
            }
        },
        <<"/api/v1/accounts/{account_id}/entries">> => #{
            <<"get">> => #{
                <<"summary">> => <<"List ledger entries for an account">>,
                <<"parameters">> => [path_param(<<"account_id">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Ledger entries">>},
                    <<"404">> => error_response()
                }
            }
        },
        <<"/api/v1/accounts/{account_id}/statement">> => #{
            <<"get">> => #{
                <<"summary">> => <<"Get account statement">>,
                <<"parameters">> => [path_param(<<"account_id">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Account statement">>},
                    <<"404">> => error_response()
                }
            }
        },
        <<"/api/v1/accounts/{account_id}/summary">> => #{
            <<"get">> => #{
                <<"summary">> => <<"Get composite account summary">>,
                <<"parameters">> => [path_param(<<"account_id">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Account summary with recent transactions and active holds">>,
                                  <<"content">> => json_content(<<"object">>)},
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
        <<"/api/v1/transactions/adjustment">> => #{
            <<"post">> => #{
                <<"summary">> => <<"Post a manual adjustment transaction">>,
                <<"responses">> => #{
                    <<"201">> => #{<<"description">> => <<"Adjustment posted">>,
                                  <<"content">> => json_ref(<<"Transaction">>)},
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
        <<"/api/v1/transactions/{txn_id}/entries">> => #{
            <<"get">> => #{
                <<"summary">> => <<"List ledger entries for a transaction">>,
                <<"parameters">> => [path_param(<<"txn_id">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Ledger entries for transaction">>},
                    <<"404">> => error_response()
                }
            }
        },
        <<"/api/v1/stats">> => #{
            <<"get">> => #{
                <<"summary">> => <<"Get platform statistics">>,
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Platform stats">>,
                                  <<"content">> => json_content(<<"object">>)}
                }
            }
        },
        <<"/api/v1/savings-products">> => #{
            <<"get">> => #{
                <<"summary">> => <<"List savings products">>,
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"List of savings products">>}
                }
            },
            <<"post">> => #{
                <<"summary">> => <<"Create a savings product">>,
                <<"responses">> => #{
                    <<"201">> => #{<<"description">> => <<"Savings product created">>,
                                  <<"content">> => json_ref(<<"SavingsProduct">>)},
                    <<"422">> => error_response()
                }
            }
        },
        <<"/api/v1/savings-products/{product_id}">> => #{
            <<"get">> => #{
                <<"summary">> => <<"Get a savings product by ID">>,
                <<"parameters">> => [path_param(<<"product_id">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Savings product">>,
                                  <<"content">> => json_ref(<<"SavingsProduct">>)},
                    <<"404">> => error_response()
                }
            },
            <<"put">> => #{
                <<"summary">> => <<"Update a savings product">>,
                <<"parameters">> => [path_param(<<"product_id">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Savings product updated">>,
                                  <<"content">> => json_ref(<<"SavingsProduct">>)},
                    <<"404">> => error_response(),
                    <<"422">> => error_response()
                }
            }
        },
        <<"/api/v1/savings-products/{product_id}/activate">> => #{
            <<"post">> => #{
                <<"summary">> => <<"Activate a savings product">>,
                <<"parameters">> => [path_param(<<"product_id">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Product activated">>,
                                  <<"content">> => json_ref(<<"SavingsProduct">>)},
                    <<"404">> => error_response(),
                    <<"409">> => error_response()
                }
            }
        },
        <<"/api/v1/savings-products/{product_id}/deactivate">> => #{
            <<"post">> => #{
                <<"summary">> => <<"Deactivate a savings product">>,
                <<"parameters">> => [path_param(<<"product_id">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Product deactivated">>,
                                  <<"content">> => json_ref(<<"SavingsProduct">>)},
                    <<"404">> => error_response(),
                    <<"409">> => error_response()
                }
            }
        },
        <<"/api/v1/loan-products">> => #{
            <<"get">> => #{
                <<"summary">> => <<"List loan products">>,
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"List of loan products">>}
                }
            },
            <<"post">> => #{
                <<"summary">> => <<"Create a loan product">>,
                <<"responses">> => #{
                    <<"201">> => #{<<"description">> => <<"Loan product created">>,
                                  <<"content">> => json_ref(<<"LoanProduct">>)},
                    <<"422">> => error_response()
                }
            }
        },
        <<"/api/v1/loan-products/{product_id}">> => #{
            <<"get">> => #{
                <<"summary">> => <<"Get a loan product by ID">>,
                <<"parameters">> => [path_param(<<"product_id">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Loan product">>,
                                  <<"content">> => json_ref(<<"LoanProduct">>)},
                    <<"404">> => error_response()
                }
            },
            <<"put">> => #{
                <<"summary">> => <<"Update a loan product">>,
                <<"parameters">> => [path_param(<<"product_id">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Loan product updated">>,
                                  <<"content">> => json_ref(<<"LoanProduct">>)},
                    <<"404">> => error_response(),
                    <<"422">> => error_response()
                }
            }
        },
        <<"/api/v1/loan-products/{product_id}/activate">> => #{
            <<"post">> => #{
                <<"summary">> => <<"Activate a loan product">>,
                <<"parameters">> => [path_param(<<"product_id">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Loan product activated">>,
                                  <<"content">> => json_ref(<<"LoanProduct">>)},
                    <<"404">> => error_response(),
                    <<"409">> => error_response()
                }
            }
        },
        <<"/api/v1/loan-products/{product_id}/deactivate">> => #{
            <<"post">> => #{
                <<"summary">> => <<"Deactivate a loan product">>,
                <<"parameters">> => [path_param(<<"product_id">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Loan product deactivated">>,
                                  <<"content">> => json_ref(<<"LoanProduct">>)},
                    <<"404">> => error_response(),
                    <<"409">> => error_response()
                }
            }
        },
        <<"/api/v1/loans">> => #{
            <<"get">> => #{
                <<"summary">> => <<"List loans">>,
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"List of loans">>}
                }
            },
            <<"post">> => #{
                <<"summary">> => <<"Create a loan">>,
                <<"responses">> => #{
                    <<"201">> => #{<<"description">> => <<"Loan created">>,
                                  <<"content">> => json_ref(<<"Loan">>)},
                    <<"422">> => error_response()
                }
            }
        },
        <<"/api/v1/loans/{loan_id}">> => #{
            <<"get">> => #{
                <<"summary">> => <<"Get a loan by ID">>,
                <<"parameters">> => [path_param(<<"loan_id">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Loan record">>,
                                  <<"content">> => json_ref(<<"Loan">>)},
                    <<"404">> => error_response()
                }
            }
        },
        <<"/api/v1/loans/{loan_id}/approve">> => #{
            <<"post">> => #{
                <<"summary">> => <<"Approve a loan">>,
                <<"parameters">> => [path_param(<<"loan_id">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Loan approved">>,
                                  <<"content">> => json_ref(<<"Loan">>)},
                    <<"404">> => error_response(),
                    <<"409">> => error_response()
                }
            }
        },
        <<"/api/v1/loans/{loan_id}/disburse">> => #{
            <<"post">> => #{
                <<"summary">> => <<"Disburse a loan">>,
                <<"parameters">> => [path_param(<<"loan_id">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Loan disbursed">>,
                                  <<"content">> => json_ref(<<"Loan">>)},
                    <<"404">> => error_response(),
                    <<"409">> => error_response()
                }
            }
        },
        <<"/api/v1/loans/{loan_id}/repayments">> => #{
            <<"get">> => #{
                <<"summary">> => <<"List repayments for a loan">>,
                <<"parameters">> => [path_param(<<"loan_id">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Loan repayments">>},
                    <<"404">> => error_response()
                }
            },
            <<"post">> => #{
                <<"summary">> => <<"Record a loan repayment">>,
                <<"parameters">> => [path_param(<<"loan_id">>)],
                <<"responses">> => #{
                    <<"201">> => #{<<"description">> => <<"Repayment recorded">>,
                                  <<"content">> => json_ref(<<"LoanRepayment">>)},
                    <<"404">> => error_response(),
                    <<"422">> => error_response()
                }
            }
        },
        <<"/api/v1/events">> => #{
            <<"get">> => #{
                <<"summary">> => <<"List domain events">>,
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"List of events">>}
                }
            },
            <<"post">> => #{
                <<"summary">> => <<"Publish a domain event">>,
                <<"responses">> => #{
                    <<"201">> => #{<<"description">> => <<"Event published">>,
                                  <<"content">> => json_ref(<<"DomainEvent">>)},
                    <<"422">> => error_response()
                }
            }
        },
        <<"/api/v1/events/{event_id}">> => #{
            <<"get">> => #{
                <<"summary">> => <<"Get a domain event by ID">>,
                <<"parameters">> => [path_param(<<"event_id">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Domain event">>,
                                  <<"content">> => json_ref(<<"DomainEvent">>)},
                    <<"404">> => error_response()
                }
            }
        },
        <<"/api/v1/events/{event_id}/replay">> => #{
            <<"post">> => #{
                <<"summary">> => <<"Replay a domain event">>,
                <<"parameters">> => [path_param(<<"event_id">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Event replayed">>},
                    <<"404">> => error_response()
                }
            }
        },
        <<"/api/v1/webhooks">> => #{
            <<"get">> => #{
                <<"summary">> => <<"List webhook subscriptions">>,
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"List of webhook subscriptions">>}
                }
            },
            <<"post">> => #{
                <<"summary">> => <<"Create a webhook subscription">>,
                <<"responses">> => #{
                    <<"201">> => #{<<"description">> => <<"Subscription created">>,
                                  <<"content">> => json_ref(<<"WebhookSubscription">>)},
                    <<"422">> => error_response()
                }
            }
        },
        <<"/api/v1/webhooks/{subscription_id}">> => #{
            <<"get">> => #{
                <<"summary">> => <<"Get a webhook subscription">>,
                <<"parameters">> => [path_param(<<"subscription_id">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Webhook subscription">>,
                                  <<"content">> => json_ref(<<"WebhookSubscription">>)},
                    <<"404">> => error_response()
                }
            },
            <<"patch">> => #{
                <<"summary">> => <<"Update a webhook subscription">>,
                <<"parameters">> => [path_param(<<"subscription_id">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Subscription updated">>,
                                  <<"content">> => json_ref(<<"WebhookSubscription">>)},
                    <<"404">> => error_response(),
                    <<"422">> => error_response()
                }
            },
            <<"delete">> => #{
                <<"summary">> => <<"Delete a webhook subscription">>,
                <<"parameters">> => [path_param(<<"subscription_id">>)],
                <<"responses">> => #{
                    <<"204">> => #{<<"description">> => <<"Subscription deleted">>},
                    <<"404">> => error_response()
                }
            }
        },
        <<"/api/v1/export/{resource}">> => #{
            <<"get">> => #{
                <<"summary">> => <<"Export a resource as CSV">>,
                <<"parameters">> => [path_param(<<"resource">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"CSV export">>},
                    <<"404">> => error_response()
                }
            }
        },
        <<"/api/v1/payment-orders">> => #{
            <<"get">> => #{
                <<"summary">> => <<"List payment orders">>,
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"List of payment orders">>}
                }
            },
            <<"post">> => #{
                <<"summary">> => <<"Create a payment order">>,
                <<"responses">> => #{
                    <<"201">> => #{<<"description">> => <<"Payment order created">>,
                                  <<"content">> => json_ref(<<"PaymentOrder">>)},
                    <<"409">> => error_response(),
                    <<"422">> => error_response()
                }
            }
        },
        <<"/api/v1/payment-orders/{payment_id}">> => #{
            <<"get">> => #{
                <<"summary">> => <<"Get a payment order by ID">>,
                <<"parameters">> => [path_param(<<"payment_id">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Payment order">>,
                                  <<"content">> => json_ref(<<"PaymentOrder">>)},
                    <<"404">> => error_response()
                }
            }
        },
        <<"/api/v1/payment-orders/{payment_id}/cancel">> => #{
            <<"post">> => #{
                <<"summary">> => <<"Cancel a payment order">>,
                <<"parameters">> => [path_param(<<"payment_id">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Payment order cancelled">>,
                                  <<"content">> => json_ref(<<"PaymentOrder">>)},
                    <<"404">> => error_response(),
                    <<"409">> => error_response()
                }
            }
        },
        <<"/api/v1/payment-orders/{payment_id}/retry">> => #{
            <<"post">> => #{
                <<"summary">> => <<"Retry a failed payment order">>,
                <<"parameters">> => [path_param(<<"payment_id">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Payment order retried">>,
                                  <<"content">> => json_ref(<<"PaymentOrder">>)},
                    <<"404">> => error_response(),
                    <<"409">> => error_response()
                }
            }
        },
        <<"/api/v1/exceptions">> => #{
            <<"get">> => #{
                <<"summary">> => <<"List exception items">>,
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"List of exception items">>}
                }
            }
        },
        <<"/api/v1/exceptions/{item_id}">> => #{
            <<"get">> => #{
                <<"summary">> => <<"Get an exception item by ID">>,
                <<"parameters">> => [path_param(<<"item_id">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Exception item">>,
                                  <<"content">> => json_ref(<<"ExceptionItem">>)},
                    <<"404">> => error_response()
                }
            }
        },
        <<"/api/v1/exceptions/{item_id}/resolve">> => #{
            <<"post">> => #{
                <<"summary">> => <<"Resolve an exception item">>,
                <<"parameters">> => [path_param(<<"item_id">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Exception item resolved">>,
                                  <<"content">> => json_ref(<<"ExceptionItem">>)},
                    <<"404">> => error_response(),
                    <<"409">> => error_response()
                }
            }
        },
        <<"/api/v1/channel-limits">> => #{
            <<"get">> => #{
                <<"summary">> => <<"List channel limits">>,
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"List of channel limits">>}
                }
            },
            <<"put">> => #{
                <<"summary">> => <<"Set channel limit">>,
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Channel limit updated">>,
                                  <<"content">> => json_ref(<<"ChannelLimit">>)},
                    <<"422">> => error_response()
                }
            }
        },
        <<"/api/v1/channel-limits/{channel}">> => #{
            <<"get">> => #{
                <<"summary">> => <<"Get limits for a specific channel">>,
                <<"parameters">> => [path_param(<<"channel">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Channel limits">>,
                                  <<"content">> => json_ref(<<"ChannelLimit">>)},
                    <<"404">> => error_response()
                }
            },
            <<"put">> => #{
                <<"summary">> => <<"Update limits for a specific channel">>,
                <<"parameters">> => [path_param(<<"channel">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Channel limits updated">>,
                                  <<"content">> => json_ref(<<"ChannelLimit">>)},
                    <<"422">> => error_response()
                }
            }
        },
        <<"/api/v1/channel-activity">> => #{
            <<"get">> => #{
                <<"summary">> => <<"List channel activity log entries">>,
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Channel activity log">>}
                }
            }
        },
        <<"/api/v1/atm/inquiry">> => #{
            <<"get">> => #{
                <<"summary">> => <<"ATM balance inquiry">>,
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Balance inquiry result">>,
                                  <<"content">> => json_content(<<"object">>)},
                    <<"401">> => error_response(),
                    <<"404">> => error_response()
                }
            }
        },
        <<"/api/v1/atm/withdraw">> => #{
            <<"post">> => #{
                <<"summary">> => <<"ATM cash withdrawal">>,
                <<"responses">> => #{
                    <<"201">> => #{<<"description">> => <<"ATM withdrawal posted">>,
                                  <<"content">> => json_ref(<<"Transaction">>)},
                    <<"402">> => error_response(),
                    <<"409">> => error_response(),
                    <<"422">> => error_response()
                }
            }
        },
        <<"/api/v1/dev/mock-import">> => #{
            <<"post">> => #{
                <<"summary">> => <<"Import mock data (development only)">>,
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Mock data imported">>}
                }
            }
        },
        <<"/api/v1/api-keys">> => #{
            <<"get">> => #{
                <<"summary">> => <<"List API keys (admin only)">>,
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"List of API keys">>},
                    <<"403">> => error_response()
                }
            },
            <<"post">> => #{
                <<"summary">> => <<"Create an API key (admin only)">>,
                <<"responses">> => #{
                    <<"201">> => #{<<"description">> => <<"API key created — secret returned once">>,
                                  <<"content">> => json_ref(<<"ApiKey">>)},
                    <<"403">> => error_response(),
                    <<"422">> => error_response()
                }
            }
        },
        <<"/api/v1/api-keys/{key_id}">> => #{
            <<"get">> => #{
                <<"summary">> => <<"Get an API key by ID (admin only)">>,
                <<"parameters">> => [path_param(<<"key_id">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"API key">>,
                                  <<"content">> => json_ref(<<"ApiKey">>)},
                    <<"403">> => error_response(),
                    <<"404">> => error_response()
                }
            },
            <<"delete">> => #{
                <<"summary">> => <<"Revoke an API key (admin only)">>,
                <<"parameters">> => [path_param(<<"key_id">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"API key revoked">>},
                    <<"403">> => error_response(),
                    <<"404">> => error_response()
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
        <<"/api/v1/operations/slo">> => #{
            <<"get">> => #{
                <<"summary">> => <<"SLO/SLA objective status and alert policy snapshot">>,
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"SLO policy snapshot">>,
                                  <<"content">> => json_content(<<"object">>)},
                    <<"401">> => error_response(),
                    <<"403">> => error_response()
                }
            }
        },
        <<"/api/v1/operations/logs">> => #{
            <<"get">> => #{
                <<"summary">> => <<"Search aggregated structured logs">>,
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Structured log search results">>,
                                  <<"content">> => json_content(<<"object">>)},
                    <<"401">> => error_response(),
                    <<"403">> => error_response()
                }
            }
        },
        <<"/api/v1/operations/logs/export">> => #{
            <<"get">> => #{
                <<"summary">> => <<"Export structured logs as CSV">>,
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Structured log CSV export">>},
                    <<"401">> => error_response(),
                    <<"403">> => error_response()
                }
            }
        },
        <<"/api/v1/operations/logs/retention">> => #{
            <<"get">> => #{
                <<"summary">> => <<"Get structured log retention policy">>,
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Structured log retention policy">>,
                                  <<"content">> => json_content(<<"object">>)},
                    <<"401">> => error_response(),
                    <<"403">> => error_response()
                }
            },
            <<"post">> => #{
                <<"summary">> => <<"Set structured log retention policy">>,
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Updated structured log retention policy">>,
                                  <<"content">> => json_content(<<"object">>)},
                    <<"401">> => error_response(),
                    <<"403">> => error_response(),
                    <<"422">> => error_response()
                }
            }
        },
        <<"/api/v1/operations/logs/retention/apply">> => #{
            <<"post">> => #{
                <<"summary">> => <<"Apply structured log retention policy">>,
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Structured log retention execution result">>,
                                  <<"content">> => json_content(<<"object">>)},
                    <<"401">> => error_response(),
                    <<"403">> => error_response()
                }
            }
        },
        <<"/api/v1/operations/incidents">> => #{
            <<"get">> => #{
                <<"summary">> => <<"List operational incidents with escalation state">>,
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Incident list">>,
                                  <<"content">> => json_content(<<"object">>)},
                    <<"401">> => error_response(),
                    <<"403">> => error_response()
                }
            }
        },
        <<"/api/v1/operations/incidents/sync">> => #{
            <<"post">> => #{
                <<"summary">> => <<"Sync incidents from current SLO alert state">>,
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Incident sync result">>,
                                  <<"content">> => json_content(<<"object">>)},
                    <<"401">> => error_response(),
                    <<"403">> => error_response()
                }
            }
        },
        <<"/api/v1/operations/incidents/templates">> => #{
            <<"get">> => #{
                <<"summary">> => <<"List post-mortem templates by severity">>,
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Post-mortem templates">>,
                                  <<"content">> => json_content(<<"object">>)},
                    <<"401">> => error_response(),
                    <<"403">> => error_response()
                }
            }
        },
        <<"/api/v1/operations/incidents/{incident_id}/{action}">> => #{
            <<"post">> => #{
                <<"summary">> => <<"Acknowledge or resolve an operational incident">>,
                <<"parameters">> => [path_param(<<"incident_id">>), path_param(<<"action">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Updated incident">>,
                                  <<"content">> => json_content(<<"object">>)},
                    <<"401">> => error_response(),
                    <<"403">> => error_response(),
                    <<"404">> => error_response(),
                    <<"409">> => error_response()
                }
            }
        },
        <<"/api/v1/operations/schema-migrations">> => #{
            <<"get">> => #{
                <<"summary">> => <<"Get schema migration status and recent history">>,
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Schema migration status">>,
                                  <<"content">> => json_content(<<"object">>)},
                    <<"401">> => error_response(),
                    <<"403">> => error_response()
                }
            }
        },
        <<"/api/v1/operations/schema-migrations/apply">> => #{
            <<"post">> => #{
                <<"summary">> => <<"Apply schema migrations up to target version">>,
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Schema migration apply result">>,
                                  <<"content">> => json_content(<<"object">>)},
                    <<"401">> => error_response(),
                    <<"403">> => error_response(),
                    <<"409">> => error_response(),
                    <<"422">> => error_response()
                }
            }
        },
        <<"/api/v1/operations/schema-migrations/rollback">> => #{
            <<"post">> => #{
                <<"summary">> => <<"Rollback schema to a target version">>,
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Schema migration rollback result">>,
                                  <<"content">> => json_content(<<"object">>)},
                    <<"401">> => error_response(),
                    <<"403">> => error_response(),
                    <<"409">> => error_response(),
                    <<"422">> => error_response()
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
        },
        <<"/api/v1/transactions">> => #{
            <<"get">> => #{
                <<"summary">>  => <<"List all transactions">>,
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Transaction list">>}
                }
            }
        },
        <<"/api/v1/transactions/{txn_id}/receipt">> => #{
            <<"get">> => #{
                <<"summary">>    => <<"Get transaction receipt">>,
                <<"parameters">> => [path_param(<<"txn_id">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Transaction receipt">>},
                    <<"404">> => error_response()
                }
            }
        },
        <<"/api/v1/transactions/{txn_id}/tags">> => #{
            <<"get">> => #{
                <<"summary">>    => <<"Get tags for a transaction">>,
                <<"parameters">> => [path_param(<<"txn_id">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Transaction tags">>},
                    <<"404">> => error_response()
                }
            }
        },
        <<"/api/v1/ledger/entries/latest">> => #{
            <<"get">> => #{
                <<"summary">>  => <<"Get latest ledger entries">>,
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Latest ledger entries">>}
                }
            }
        },
        <<"/api/v1/ledger/trial-balance">> => #{
            <<"get">> => #{
                <<"summary">>  => <<"Get trial balance">>,
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Trial balance report">>}
                }
            }
        },
        <<"/api/v1/ledger/general-ledger">> => #{
            <<"get">> => #{
                <<"summary">>  => <<"Get general ledger">>,
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"General ledger entries">>}
                }
            }
        },
        <<"/api/v1/ledger/chart-of-accounts">> => #{
            <<"get">> => #{
                <<"summary">>  => <<"List chart of accounts">>,
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Chart of accounts">>}
                }
            }
        },
        <<"/api/v1/ledger/chart-of-accounts/{code}">> => #{
            <<"get">> => #{
                <<"summary">>    => <<"Get a specific chart of accounts entry">>,
                <<"parameters">> => [path_param(<<"code">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Chart of accounts entry">>},
                    <<"404">> => error_response()
                }
            }
        },
        <<"/api/v1/accounts/{account_id}/snapshots">> => #{
            <<"get">> => #{
                <<"summary">>    => <<"Get balance snapshots for an account">>,
                <<"parameters">> => [path_param(<<"account_id">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Balance snapshots">>},
                    <<"404">> => error_response()
                }
            }
        },
        <<"/api/v1/webhooks/{subscription_id}/deliveries">> => #{
            <<"get">> => #{
                <<"summary">>    => <<"List delivery attempts for a webhook subscription">>,
                <<"parameters">> => [path_param(<<"subscription_id">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Delivery attempts">>,
                                  <<"content">> => json_ref(<<"WebhookDelivery">>)},
                    <<"404">> => error_response()
                }
            }
        },
        <<"/api/v1/api-keys/{key_id}/usage">> => #{
            <<"get">> => #{
                <<"summary">>    => <<"Get usage records for an API key">>,
                <<"parameters">> => [path_param(<<"key_id">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"API key usage records">>,
                                  <<"content">> => json_ref(<<"ApiKeyUsage">>)},
                    <<"404">> => error_response()
                }
            }
        },
        <<"/api/v1/deprecations">> => #{
            <<"get">> => #{
                <<"summary">>  => <<"List deprecated API notices">>,
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Deprecation notices">>}
                }
            }
        },
        <<"/api/graphql">> => #{
            <<"post">> => #{
                <<"summary">>  => <<"GraphQL endpoint">>,
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"GraphQL response">>}
                }
            }
        },
        <<"/api/v1/oauth/token">> => #{
            <<"post">> => #{
                <<"summary">>  => <<"Issue OAuth 2.0 access token (client_credentials)">>,
                <<"security">> => [],
                <<"requestBody">> => #{
                    <<"required">> => true,
                    <<"content">> => #{
                        <<"application/x-www-form-urlencoded">> => #{
                            <<"schema">> => #{
                                <<"type">> => <<"object">>,
                                <<"required">> => [<<"grant_type">>, <<"client_id">>, <<"client_secret">>],
                                <<"properties">> => #{
                                    <<"grant_type">>    => #{<<"type">> => <<"string">>, <<"enum">> => [<<"client_credentials">>]},
                                    <<"client_id">>     => #{<<"type">> => <<"string">>},
                                    <<"client_secret">> => #{<<"type">> => <<"string">>}
                                }
                            }
                        }
                    }
                },
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Access token issued">>,
                                  <<"content">> => json_ref(<<"OAuthToken">>)},
                    <<"400">> => error_response(),
                    <<"401">> => error_response()
                }
            }
        },
        <<"/api/v1/contracts">> => #{
            <<"get">> => #{
                <<"summary">> => <<"List all contracts">>,
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"List of contracts">>,
                                  <<"content">> => json_content(<<"object">>)},
                    <<"401">> => error_response()
                }
            },
            <<"post">> => #{
                <<"summary">> => <<"Create a new contract">>,
                <<"requestBody">> => #{
                    <<"required">> => true,
                    <<"content">> => json_content(<<"object">>)
                },
                <<"responses">> => #{
                    <<"201">> => #{<<"description">> => <<"Contract created">>,
                                  <<"content">> => json_ref(<<"Contract">>)},
                    <<"422">> => error_response(),
                    <<"401">> => error_response()
                }
            }
        },
        <<"/api/v1/contracts/:contract_id">> => #{
            <<"get">> => #{
                <<"summary">> => <<"Get contract by ID">>,
                <<"parameters">> => [path_param(<<"contract_id">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Contract details">>,
                                  <<"content">> => json_ref(<<"Contract">>)},
                    <<"404">> => error_response(),
                    <<"401">> => error_response()
                }
            }
        },
        <<"/api/v1/contracts/:contract_id/versions">> => #{
            <<"get">> => #{
                <<"summary">> => <<"List contract versions">>,
                <<"parameters">> => [path_param(<<"contract_id">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"List of contract versions">>},
                    <<"404">> => error_response(),
                    <<"401">> => error_response()
                }
            },
            <<"post">> => #{
                <<"summary">> => <<"Deploy a new contract version">>,
                <<"parameters">> => [path_param(<<"contract_id">>)],
                <<"requestBody">> => #{
                    <<"required">> => true,
                    <<"content">> => json_content(<<"object">>)
                },
                <<"responses">> => #{
                    <<"201">> => #{<<"description">> => <<"Version deployed">>,
                                  <<"content">> => json_ref(<<"ContractVersion">>)},
                    <<"422">> => error_response(),
                    <<"401">> => error_response()
                }
            }
        },
        <<"/api/v1/contracts/:contract_id/versions/:version">> => #{
            <<"get">> => #{
                <<"summary">> => <<"Get specific contract version">>,
                <<"parameters">> => [path_param(<<"contract_id">>), path_param(<<"version">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Contract version">>,
                                  <<"content">> => json_ref(<<"ContractVersion">>)},
                    <<"404">> => error_response(),
                    <<"401">> => error_response()
                }
            }
        },
        <<"/api/v1/contracts/:contract_id/versions/:version/activate">> => #{
            <<"post">> => #{
                <<"summary">> => <<"Activate a contract version">>,
                <<"parameters">> => [path_param(<<"contract_id">>), path_param(<<"version">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Version activated">>,
                                  <<"content">> => json_ref(<<"Contract">>)},
                    <<"404">> => error_response(),
                    <<"422">> => error_response(),
                    <<"401">> => error_response()
                }
            }
        },
        <<"/api/v1/contracts/:contract_id/versions/:version/migrate">> => #{
            <<"post">> => #{
                <<"summary">> => <<"Create a migration from one version to another">>,
                <<"parameters">> => [path_param(<<"contract_id">>), path_param(<<"version">>)],
                <<"requestBody">> => #{
                    <<"required">> => true,
                    <<"content">> => json_content(<<"object">>)
                },
                <<"responses">> => #{
                    <<"201">> => #{<<"description">> => <<"Migration created">>,
                                  <<"content">> => json_ref(<<"ContractMigration">>)},
                    <<"404">> => error_response(),
                    <<"422">> => error_response(),
                    <<"401">> => error_response()
                }
            }
        },
        <<"/api/v1/contracts/:contract_id/versions/:version/execute">> => #{
            <<"post">> => #{
                <<"summary">> => <<"Execute a contract version and persist trace">>,
                <<"parameters">> => [path_param(<<"contract_id">>), path_param(<<"version">>)],
                <<"requestBody">> => #{
                    <<"required">> => true,
                    <<"content">> => json_content(<<"object">>)
                },
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Execution completed">>,
                                  <<"content">> => json_content(<<"object">>)},
                    <<"404">> => error_response(),
                    <<"422">> => error_response(),
                    <<"401">> => error_response()
                }
            }
        },
        <<"/api/v1/contracts/:contract_id/experiments">> => #{
            <<"get">> => #{
                <<"summary">> => <<"List variant experiments for a contract">>,
                <<"parameters">> => [path_param(<<"contract_id">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"List of experiments">>},
                    <<"401">> => error_response()
                }
            },
            <<"post">> => #{
                <<"summary">> => <<"Create a new variant experiment">>,
                <<"parameters">> => [path_param(<<"contract_id">>)],
                <<"requestBody">> => #{
                    <<"required">> => true,
                    <<"content">> => json_content(<<"object">>)
                },
                <<"responses">> => #{
                    <<"201">> => #{<<"description">> => <<"Experiment created">>,
                                  <<"content">> => json_ref(<<"ContractExperiment">>)},
                    <<"422">> => error_response(),
                    <<"401">> => error_response()
                }
            }
        },
        <<"/api/v1/contracts/:contract_id/experiments/:experiment_id">> => #{
            <<"get">> => #{
                <<"summary">> => <<"Get experiment details">>,
                <<"parameters">> => [path_param(<<"contract_id">>), path_param(<<"experiment_id">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Experiment details">>,
                                  <<"content">> => json_ref(<<"ContractExperiment">>)},
                    <<"404">> => error_response(),
                    <<"401">> => error_response()
                }
            }
        },
        <<"/api/v1/contracts/:contract_id/experiments/:experiment_id/activate">> => #{
            <<"post">> => #{
                <<"summary">> => <<"Activate an experiment">>,
                <<"parameters">> => [path_param(<<"contract_id">>), path_param(<<"experiment_id">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Experiment activated">>,
                                  <<"content">> => json_ref(<<"ContractExperiment">>)},
                    <<"404">> => error_response(),
                    <<"422">> => error_response(),
                    <<"401">> => error_response()
                }
            }
        },
        <<"/api/v1/contracts/:contract_id/experiments/:experiment_id/stop">> => #{
            <<"post">> => #{
                <<"summary">> => <<"Stop an experiment">>,
                <<"parameters">> => [path_param(<<"contract_id">>), path_param(<<"experiment_id">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Experiment stopped">>,
                                  <<"content">> => json_ref(<<"ContractExperiment">>)},
                    <<"404">> => error_response(),
                    <<"422">> => error_response(),
                    <<"401">> => error_response()
                }
            }
        },
        <<"/api/v1/contracts/:contract_id/experiments/:experiment_id/assign">> => #{
            <<"post">> => #{
                <<"summary">> => <<"Assign a subject to a contract variant">>,
                <<"parameters">> => [path_param(<<"contract_id">>), path_param(<<"experiment_id">>)],
                <<"requestBody">> => #{
                    <<"required">> => true,
                    <<"content">> => json_content(<<"object">>)
                },
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Variant assigned">>,
                                  <<"content">> => json_content(<<"object">>)},
                    <<"404">> => error_response(),
                    <<"422">> => error_response(),
                    <<"401">> => error_response()
                }
            }
        },
        <<"/api/v1/contracts/executions/:execution_id">> => #{
            <<"get">> => #{
                <<"summary">> => <<"Get execution trace">>,
                <<"parameters">> => [path_param(<<"execution_id">>)],
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Execution trace">>,
                                  <<"content">> => json_ref(<<"ContractExecutionTrace">>)},
                    <<"404">> => error_response(),
                    <<"401">> => error_response()
                }
            }
        },
        <<"/api/v1/contracts/executions/:execution_id/replay">> => #{
            <<"post">> => #{
                <<"summary">> => <<"Replay an execution with optional context override">>,
                <<"parameters">> => [path_param(<<"execution_id">>)],
                <<"requestBody">> => #{
                    <<"required">> => false,
                    <<"content">> => json_content(<<"object">>)
                },
                <<"responses">> => #{
                    <<"200">> => #{<<"description">> => <<"Replay result">>,
                                  <<"content">> => json_content(<<"object">>)},
                    <<"404">> => error_response(),
                    <<"422">> => error_response(),
                    <<"401">> => error_response()
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
