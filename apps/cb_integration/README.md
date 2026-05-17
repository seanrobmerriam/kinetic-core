# cb_integration

HTTP API layer - Cowboy server, routing, handlers, CORS, and error handling.

## Module Overview

The cb_integration module provides the HTTP API layer for Kinetic Core using Cowboy. It handles routing, request/response processing, CORS, logging, and error handling.

## Components

### cb_router

Defines all HTTP routes and dispatches requests to appropriate handlers.

### cb_cors

Cross-Origin Resource Sharing configuration and middleware.

### cb_log_middleware

Request/response logging for audit and debugging.

### cb_http_errors

Standardized error response formatting.

## API Endpoints

### Health
- `GET /health` - System health check

### Operations
- `GET /api/v1/operations/slo` - SLO/SLA objective status and alert policy snapshot (operations/admin)
- `GET /api/v1/operations/logs` - Structured log search for on-call investigation (operations/admin)

## Operational Docs

- Repository runbooks: `docs/on-call-runbooks-p1-p2.md`

### Parties
- `POST /parties` - Create party
- `GET /parties/:id` - Get party
- `GET /parties` - List parties
- `PATCH /parties/:id/suspend` - Suspend party
- `PATCH /parties/:id/reactivate` - Reactivate party
- `DELETE /parties/:id` - Close party

### Accounts
- `POST /accounts` - Create account
- `GET /accounts/:id` - Get account
- `GET /parties/:party_id/accounts` - List party accounts
- `PATCH /accounts/:id/freeze` - Freeze account
- `PATCH /accounts/:id/unfreeze` - Unfreeze account
- `DELETE /accounts/:id` - Close account

### Transactions
- `POST /transactions/deposit` - Deposit funds
- `POST /transactions/withdraw` - Withdraw funds
- `POST /transactions/transfer` - Transfer funds
- `GET /accounts/:id/transactions` - Account transactions

### Loans
- `POST /loans/products` - Create loan product
- `GET /loans/products` - List loan products
- `POST /loans` - Disburse loan
- `GET /loans/:id` - Get loan
- `POST /loans/:id/repayments` - Make repayment

### Savings
- `POST /savings/products` - Create savings product
- `GET /savings/products` - List savings products

## Request/Response Format

### Request Headers
```
Content-Type: application/json
Accept: application/json
Idempotency-Key: (UUID for POST/PUT/PATCH requests)
```

### Success Response
```json
{
  "data": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "type": "account",
    "attributes": {
      "balance": 100000,
      "currency": "USD",
      "status": "active"
    }
  }
}
```

### Error Response
```json
{
  "error": "account_not_found",
  "message": "Account 550e8400-e29b-41d4-a716-446655440000 was not found"
}
```

## Error Codes

- `account_not_found` - Account doesn't exist
- `account_frozen` - Account is frozen
- `account_closed` - Account is closed
- `insufficient_funds` - Not enough balance
- `party_not_found` - Party doesn't exist
- `invalid_request` - Malformed request
- `duplicate_request` - Idempotency key already used

## See Also

- [Architecture](../docs/architecture.md)
- [HTTP Handlers](./handlers/README.md)
