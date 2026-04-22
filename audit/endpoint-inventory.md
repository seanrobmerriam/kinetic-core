# Endpoint Inventory

**Source of truth:** `apps/cb_integration/src/cb_router.erl` (lines 70–200) cross-referenced with
each handler module under `apps/cb_integration/src/handlers/`.

**Discovery method:** Read every `{Path, Handler, []}` entry in `cb_router:dispatch/0`, then for
each handler module enumerated the `handle(<<"METHOD">>, ...)` clauses to determine which HTTP
verbs the handler actually services. `OPTIONS` (CORS preflight) is excluded from the table — it is
implemented by every handler and not relevant to coverage.

**Authentication:** Auth is enforced by `cb_auth_middleware` based on path; only `/health`,
`/api/v1/auth/login`, `/metrics`, `/api/v1/openapi.json`, and `/api/graphql` (introspection) are
unauthenticated. All other endpoints require a Bearer session token. Role-based authorization is
not yet enforced at the handler level.

**Total endpoints discovered:** 78 (counting each verb on each path as one endpoint).

---

## Health & Auth

| Method | Path | Handler | File:Line | Auth | Notes |
|---|---|---|---|---|---|
| GET    | `/health`                  | `cb_health_handler`  | router.erl:74 | no  | Liveness probe |
| POST   | `/api/v1/auth/login`       | `cb_login_handler`   | router.erl:77 | no  | Returns `session_id` + `user` |
| POST   | `/api/v1/auth/logout`      | `cb_logout_handler`  | router.erl:78 | yes | Invalidates session |
| GET    | `/api/v1/auth/me`          | `cb_me_handler`      | router.erl:79 | yes | Current user profile |

## Parties (customers)

| Method | Path | Handler | Notes |
|---|---|---|---|
| GET    | `/api/v1/parties`                                  | `cb_parties_handler`           | List all parties |
| POST   | `/api/v1/parties`                                  | `cb_parties_handler`           | Create party |
| GET    | `/api/v1/parties/:party_id`                        | `cb_party_handler`             | Party detail |
| POST   | `/api/v1/parties/:party_id/suspend`                | `cb_party_suspend_handler`     | Suspend party |
| POST   | `/api/v1/parties/:party_id/reactivate`             | `cb_party_reactivate_handler`  | Reactivate suspended party |
| POST   | `/api/v1/parties/:party_id/close`                  | `cb_party_close_handler`       | Close party |
| GET    | `/api/v1/parties/:party_id/kyc`                    | `cb_party_kyc_handler`         | Get KYC state |
| PATCH  | `/api/v1/parties/:party_id/kyc`                    | `cb_party_kyc_handler`         | Update KYC status / notes |
| POST   | `/api/v1/parties/:party_id/kyc`                    | `cb_party_kyc_handler`         | Add KYC `doc_ref` |
| GET    | `/api/v1/parties/:party_id/accounts`               | `cb_party_accounts_handler`    | Accounts owned by party |
| GET    | `/api/v1/parties/:party_id/profile`                | `cb_party_profile_handler`     | Unified omnichannel profile |
| GET    | `/api/v1/parties/:party_id/notification-preferences` | `cb_notification_prefs_handler` | Read prefs |
| PUT    | `/api/v1/parties/:party_id/notification-preferences` | `cb_notification_prefs_handler` | Replace prefs |

## Accounts

| Method | Path | Handler | Notes |
|---|---|---|---|
| GET    | `/api/v1/accounts`                                | `cb_accounts_list_handler`        | List accounts |
| POST   | `/api/v1/accounts`                                | `cb_accounts_list_handler`        | Create account |
| GET    | `/api/v1/stats`                                   | `cb_stats_handler`                | Aggregate dashboard stats |
| GET    | `/api/v1/accounts/:account_id`                    | `cb_account_handler`              | Account detail |
| GET    | `/api/v1/accounts/:account_id/transactions`       | `cb_account_transactions_handler` | Account transactions |
| GET    | `/api/v1/accounts/:account_id/balance`            | `cb_account_balance_handler`      | Current balance |
| GET    | `/api/v1/accounts/:account_id/summary`            | `cb_account_summary_handler`      | Aggregate summary |
| GET    | `/api/v1/accounts/:account_id/holds`              | `cb_account_holds_handler`        | List holds |
| POST   | `/api/v1/accounts/:account_id/holds`              | `cb_account_holds_handler`        | Place hold |
| DELETE | `/api/v1/accounts/:account_id/holds/:hold_id`     | `cb_account_holds_handler`        | Release hold |
| POST   | `/api/v1/accounts/:account_id/freeze`             | `cb_account_freeze_handler`       | Freeze account |
| POST   | `/api/v1/accounts/:account_id/unfreeze`           | `cb_account_unfreeze_handler`     | Unfreeze account |
| POST   | `/api/v1/accounts/:account_id/close`              | `cb_account_close_handler`        | Close account |
| GET    | `/api/v1/accounts/:account_id/entries`            | `cb_account_entries_handler`      | Ledger entries for account |
| GET    | `/api/v1/accounts/:account_id/statement`          | `cb_statements_handler`           | Generate statement |

## Transactions

| Method | Path | Handler | Notes |
|---|---|---|---|
| POST   | `/api/v1/transactions/transfer`              | `cb_transaction_transfer_handler`   | Transfer between accounts |
| POST   | `/api/v1/transactions/deposit`               | `cb_transaction_deposit_handler`    | Cash/external deposit |
| POST   | `/api/v1/transactions/withdraw`              | `cb_transaction_withdraw_handler`   | Cash/external withdrawal |
| POST   | `/api/v1/transactions/adjustment`            | `cb_transaction_adjustment_handler` | Manual ledger adjustment |
| GET    | `/api/v1/transactions/:txn_id`               | `cb_transaction_handler`            | Transaction detail |
| POST   | `/api/v1/transactions/:txn_id/reverse`       | `cb_transaction_reverse_handler`    | Reverse transaction |
| GET    | `/api/v1/transactions/:txn_id/entries`       | `cb_transaction_entries_handler`    | Ledger entries for txn |

## Ledger

| Method | Path | Handler | Notes |
|---|---|---|---|
| GET    | `/api/v1/ledger/entries/latest`              | `cb_ledger_latest_handler` | Recent entries (paginated by `limit`) |

## Savings products

| Method | Path | Handler | Notes |
|---|---|---|---|
| GET    | `/api/v1/savings-products`                                | `cb_savings_products_handler` | List savings products |
| POST   | `/api/v1/savings-products`                                | `cb_savings_products_handler` | Create savings product |
| GET    | `/api/v1/savings-products/:product_id`                    | `cb_savings_products_handler` | Detail (handler dispatches by binding) |
| POST   | `/api/v1/savings-products/:product_id/activate`           | `cb_savings_products_handler` | Activate product |
| POST   | `/api/v1/savings-products/:product_id/deactivate`         | `cb_savings_products_handler` | Deactivate product |

## Loan products

| Method | Path | Handler | Notes |
|---|---|---|---|
| GET    | `/api/v1/loan-products`                                   | `cb_loan_products_handler` | List loan products |
| POST   | `/api/v1/loan-products`                                   | `cb_loan_products_handler` | Create loan product |
| GET    | `/api/v1/loan-products/:product_id`                       | `cb_loan_products_handler` | Detail |
| POST   | `/api/v1/loan-products/:product_id/activate`              | `cb_loan_products_handler` | Activate product |
| POST   | `/api/v1/loan-products/:product_id/deactivate`            | `cb_loan_products_handler` | Deactivate product |

## Loans

| Method | Path | Handler | Notes |
|---|---|---|---|
| GET    | `/api/v1/loans`                                | `cb_loans_handler`            | List loans (`?party_id=` filter supported) |
| POST   | `/api/v1/loans`                                | `cb_loans_handler`            | Originate loan |
| GET    | `/api/v1/loans/:loan_id`                       | `cb_loans_handler`            | Loan detail |
| POST   | `/api/v1/loans/:loan_id/approve`               | `cb_loans_handler`            | Approve loan |
| POST   | `/api/v1/loans/:loan_id/disburse`              | `cb_loans_handler`            | Disburse approved loan |
| GET    | `/api/v1/loans/:loan_id/repayments`            | `cb_loan_repayments_handler`  | List repayments |
| POST   | `/api/v1/loans/:loan_id/repayments`            | `cb_loan_repayments_handler`  | Record repayment |

## Domain events

| Method | Path | Handler | Notes |
|---|---|---|---|
| GET    | `/api/v1/events`                                | `cb_events_handler` | List domain events |
| POST   | `/api/v1/events`                                | `cb_events_handler` | Append event (admin / replay) |
| GET    | `/api/v1/events/:event_id`                      | `cb_events_handler` | Event detail |
| POST   | `/api/v1/events/:event_id/replay`               | `cb_events_handler` | Re-emit event |

## Webhooks

| Method | Path | Handler | Notes |
|---|---|---|---|
| GET    | `/api/v1/webhooks`                                       | `cb_webhooks_handler`            | List subscriptions |
| POST   | `/api/v1/webhooks`                                       | `cb_webhooks_handler`            | Create subscription |
| PATCH  | `/api/v1/webhooks/:subscription_id`                      | `cb_webhooks_handler`            | Update subscription |
| DELETE | `/api/v1/webhooks/:subscription_id`                      | `cb_webhooks_handler`            | Delete subscription |
| GET    | `/api/v1/webhooks/:subscription_id/deliveries`           | `cb_webhook_deliveries_handler`  | Delivery attempts log |

## Statements & Exports

| Method | Path | Handler | Notes |
|---|---|---|---|
| GET    | `/api/v1/accounts/:account_id/statement`        | `cb_statements_handler` | Statement (CSV/JSON via `?format=`) |
| GET    | `/api/v1/export/:resource`                      | `cb_exports_handler`    | Bulk CSV export by resource name |

## Payment orders

| Method | Path | Handler | Notes |
|---|---|---|---|
| GET    | `/api/v1/payment-orders`                                  | `cb_payment_orders_handler` | List orders |
| POST   | `/api/v1/payment-orders`                                  | `cb_payment_orders_handler` | Initiate payment (idempotent) |
| GET    | `/api/v1/payment-orders/:payment_id`                      | `cb_payment_orders_handler` | Order detail |
| POST   | `/api/v1/payment-orders/:payment_id/cancel`               | `cb_payment_orders_handler` | Cancel order |
| POST   | `/api/v1/payment-orders/:payment_id/retry`                | `cb_payment_orders_handler` | Retry failed order |

## Exception queue

| Method | Path | Handler | Notes |
|---|---|---|---|
| GET    | `/api/v1/exceptions`                            | `cb_exceptions_handler` | List exception items |
| POST   | `/api/v1/exceptions`                            | `cb_exceptions_handler` | Enqueue exception (system) |
| GET    | `/api/v1/exceptions/:item_id`                   | `cb_exceptions_handler` | Detail |
| POST   | `/api/v1/exceptions/:item_id/resolve`           | `cb_exceptions_handler` | Resolve with note |

## Omnichannel

| Method | Path | Handler | Notes |
|---|---|---|---|
| GET    | `/api/v1/channel-limits`                        | `cb_channel_limits_handler`   | Limits across all channels |
| GET    | `/api/v1/channel-limits/:channel`               | `cb_channel_limits_handler`   | Limit for one channel |
| PUT    | `/api/v1/channel-limits/:channel`               | `cb_channel_limits_handler`   | Update channel limit |
| GET    | `/api/v1/channel-activity`                      | `cb_channel_activity_handler` | Activity log (filterable) |

## Partner API keys

| Method | Path | Handler | Notes |
|---|---|---|---|
| GET    | `/api/v1/api-keys`                              | `cb_api_keys_handler`   | List partner keys |
| POST   | `/api/v1/api-keys`                              | `cb_api_keys_handler`   | Issue new key |
| GET    | `/api/v1/api-keys/:key_id`                      | `cb_api_keys_handler`   | Key metadata |
| DELETE | `/api/v1/api-keys/:key_id`                      | `cb_api_keys_handler`   | Revoke key |
| GET    | `/api/v1/api-keys/:key_id/usage`                | `cb_api_usage_handler`  | Usage events |

## API meta

| Method | Path | Handler | Notes |
|---|---|---|---|
| GET    | `/api/v1/openapi.json`                          | `cb_openapi_handler`   | OpenAPI spec |
| GET    | `/api/v1/deprecations`                          | `cb_deprecation_handler` | Deprecation notices |
| GET    | `/metrics`                                      | `cb_metrics_handler`   | Prometheus metrics |
| GET    | `/api/graphql`                                  | `cb_graphql_handler`   | GraphiQL / introspection |
| POST   | `/api/graphql`                                  | `cb_graphql_handler`   | GraphQL queries/mutations |

## Dev tools

| Method | Path | Handler | Notes |
|---|---|---|---|
| GET    | `/api/v1/dev/mock-import`                       | `cb_dev_mock_import_handler` | Read import flag |
| POST   | `/api/v1/dev/mock-import`                       | `cb_dev_mock_import_handler` | Import demo data |

## ATM

| Method | Path | Handler | Notes |
|---|---|---|---|
| POST   | `/api/v1/atm/inquiry`                           | `cb_atm_handler` | Balance inquiry |
| POST   | `/api/v1/atm/withdraw`                          | `cb_atm_handler` | ATM withdrawal |

---

## CRUD Matrix Summary

```
Resource          C  R-list  R-one  U  Status-actions  Sub-resources
--------------------------------------------------------------------------------
Parties           ✓  ✓       ✓      –  suspend/reactivate/close
                                       kyc PATCH/POST
                                       notification-prefs PUT
                                       sub: accounts, profile

Accounts          ✓  ✓       ✓      –  freeze/unfreeze/close/holds(POST/DELETE)
                                       sub: transactions, balance, summary,
                                            holds, entries, statement

Transactions      –  –       ✓      –  reverse
                  (writes via /transactions/{transfer,deposit,withdraw,adjustment})
                                       sub: entries

Ledger            –  ✓ (latest only)        –

Savings products  ✓  ✓       ✓      –  activate/deactivate
Loan products     ✓  ✓       ✓      –  activate/deactivate

Loans             ✓  ✓       ✓      –  approve/disburse
                                       sub: repayments (GET/POST)

Events            ✓  ✓       ✓      –  replay
Webhooks          ✓  ✓       –     PATCH/DELETE
                                       sub: deliveries
Payment orders    ✓  ✓       ✓      –  cancel/retry
Exceptions        ✓  ✓       ✓      –  resolve

Channel limits    –  ✓       ✓     PUT (per-channel)
Channel activity  –  ✓ (filtered)            –

API keys          ✓  ✓       ✓     DELETE  sub: usage
Deprecations      –  ✓       –      –
Stats             –  ✓ (single)     –
ATM               –  –       –     POST inquiry/withdraw
GraphQL           –  ✓ (introspection)      POST queries
Dev mock          –  ✓       –     POST import
```
