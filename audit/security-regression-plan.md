# Security Regression Plan (TASK-097)

Date: 2026-05-15
Phase: P6-S2 Security Hardening
Task: TASK-097 (Planning Started)
Inputs:

- `audit/threat-model-review.md`
- `audit/endpoint-inventory.md`
- `apps/cb_integration/src/cb_router.erl`
- `apps/cb_integration/src/cb_auth_middleware.erl`

## 1. Objective

Build a repeatable security regression suite with OWASP Top 10 coverage for exposed API surfaces, and gate merges on critical and high severity findings.

## 2. Test Scope

- In-scope: all authenticated and public HTTP API endpoints in `cb_integration`.
- In-scope auth modes: session bearer token, partner API key, OAuth bearer token.
- In-scope controls: authentication, authorization (RBAC), input validation, rate limiting, error handling, and data exposure boundaries.
- Out-of-scope for initial iteration: browser-only UI concerns, third-party infra controls outside this repository.

## 3. OWASP Coverage Matrix

| OWASP 2021 | Category | Regression Focus | Representative Endpoint Families |
|---|---|---|---|
| A01 | Broken Access Control | Cross-role and cross-resource authorization | `/api/v1/api-keys`, `/api/v1/channel-limits`, `/api/v1/channel-features`, `/api/v1/cluster`, `/api/v1/recovery` |
| A02 | Cryptographic Failures | Token handling, secret exposure in responses/logs | `/api/v1/auth/*`, `/api/v1/oauth/token`, webhook/config endpoints |
| A03 | Injection | JSON/body/path/query injection resistance | transaction endpoints, export/reporting endpoints, search/filter endpoints |
| A04 | Insecure Design | Abuse cases and business-logic bypass attempts | payments, reversals, retries, compliance transitions |
| A05 | Security Misconfiguration | Public endpoint hardening, CORS, headers, method handling | `/health`, `/metrics`, `/api/v1/openapi.json`, CORS preflight behavior |
| A06 | Vulnerable Components | Dependency risk and known-vuln package checks | Erlang deps via rebar, Node deps via npm lockfiles |
| A07 | Identification and Authentication Failures | Invalid token replay, session revocation, auth bypass | `/api/v1/auth/login`, `/api/v1/auth/me`, bearer-protected APIs |
| A08 | Software and Data Integrity Failures | Audit/event integrity and replay safety controls | `/api/v1/events/*`, `/api/v1/contracts/*`, `/api/v1/audit/chain/*` |
| A09 | Security Logging and Monitoring Failures | Security event observability and actor attribution | all protected endpoints and failure paths |
| A10 | SSRF | Outbound callback and connector URL handling | `/api/v1/webhooks`, marketplace/connectors routes |

## 4. Initial Regression Test Set

### A01 Broken Access Control

- Verify `read_only` cannot perform any write requests.
- Verify `operations` is blocked from admin-only control-plane boundaries.
- Verify `admin` succeeds on admin-only boundaries.
- Verify unauthorized requests return 401 and never 2xx/3xx.

### A03 Injection

- JSON parser abuse payloads return safe 4xx errors.
- SQL-like, script-like, and template-like strings in path/query/body do not execute and do not leak internals.
- Malformed pagination/filter params return validation errors.

### A05 Security Misconfiguration

- CORS behavior validated for allowed/denied origins by environment policy.
- Verify unsupported methods consistently return 405.
- Verify public endpoints do not expose sensitive internals.

### A07 Identification and Authentication Failures

- Expired/revoked session tokens denied.
- Invalid API keys denied.
- Invalid OAuth token denied.
- No privilege gain from malformed or unknown role claims.

### A09 Logging and Monitoring

- Sensitive fields (passwords, key secrets, token values) absent from logs.
- Authentication failures, forbidden decisions, and rate-limit denials produce auditable events.

### A10 SSRF

- Webhook URL validation rejects private-link-local loopback destinations.
- Connector configuration rejects unsafe callback and metadata URLs.

## 5. Test Harness and Execution Strategy

Execution layers:

- Erlang CT for handler/middleware behavior close to implementation.
- Node-based black-box API security tests for negative/adversarial request patterns.

Planned artifacts:

- `apps/cb_integration/test/cb_security_regression_SUITE.erl`
- `test/security-regression.js`

Proposed npm scripts:

- `npm run test:security:api` -> runs Node black-box suite
- `npm run test:security:ct` -> runs focused CT suite
- `npm run test:security` -> aggregates both

## 6. Severity and Merge Gates

- Critical: merge-blocking.
- High: merge-blocking unless explicitly waived with risk approval.
- Medium: allowed with tracked remediation issue and owner.
- Low: backlog with SLA.

CI gate rule for TASK-097 completion:

- No unresolved Critical/High failures in `test:security` pipeline.

## 7. Implementation Sequence

1. Create CT suite skeleton and add A01 RBAC regression cases first.
2. Add Node black-box suite for malformed input and auth abuse cases (A03, A07).
3. Add CORS/method/config tests (A05).
4. Add webhook and connector SSRF validation tests (A10).
5. Add logging assertions for sensitive-data suppression and security event coverage (A09).
6. Wire scripts into CI and enforce gating thresholds.

## 8. Traceability to Threat Model

The following risk themes from `audit/threat-model-review.md` are directly covered by this plan:

- Coarse authorization model -> A01 RBAC regressions.
- Forwarded-header and public endpoint abuse risk -> A05/A07 hardening tests.
- Input sanitization gaps -> A03 injection regressions.
- Security telemetry gaps -> A09 logging regressions.
- Webhook and integration callback exposure -> A10 SSRF regressions.
