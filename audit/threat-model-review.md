# Threat Model Review - API Surface

Date: 2026-05-15
Phase: P6-S2 Security Hardening
Task: TASK-092
Status: Completed

## 1. Scope

This review covers all HTTP API surfaces exposed by `cb_integration` and routed via Cowboy.

Primary evidence:

- `apps/cb_integration/src/cb_router.erl`
- `apps/cb_integration/src/cb_integration_app.erl`
- `apps/cb_integration/src/cb_auth_middleware.erl`
- `apps/cb_integration/src/cb_rate_limit_middleware.erl`
- `apps/cb_integration/src/cb_rate_limiter.erl`
- `apps/cb_integration/src/cb_cors_middleware.erl`
- `apps/cb_integration/src/cb_log_middleware.erl`
- `audit/endpoint-inventory.md`

## 2. Method

- Threat modeling approach: STRIDE over API and trust boundaries.
- Surface enumeration source of truth: `cb_router:dispatch/0`.
- Control verification source of truth: middleware chain and auth/rate-limit middleware behavior.
- Severity model: High, Medium, Low based on exploitability and business impact for financial operations.

## 3. API Surface Summary

- Total declared route entries in router: 243
- API v1 route entries: 240
- Public unauthenticated paths enforced by auth middleware:
  - `/health`
  - `/api/v1/auth/login`
  - `/api/v1/oauth/token`
  - `/api/v1/openapi.json`
  - `/metrics`
- All other routed paths require Bearer auth (session, partner API key, or OAuth token).

## 4. Trust Boundaries and Assets

Trust boundaries:

- Internet client -> HTTP API listener (Cowboy)
- Middleware chain -> handler business logic
- Handler layer -> domain apps and Mnesia persistence
- Outbound integrations (webhooks, partner APIs, provider connectors)

Critical assets:

- Monetary value and posting integrity (accounts, ledger, transactions, settlements)
- Identity and authorization context (sessions, API keys, OAuth tokens)
- PII and compliance artifacts (KYC, IDV, AML, SAR, exports)
- Audit and event immutability (domain events, replay, audit chain)
- Operational integrity (rate limiting, recovery, scaling, cluster operations)

## 5. Existing Security Controls (Observed)

- Authentication middleware enforced for non-public paths.
- Write restriction for `read_only` role on `POST/PUT/PATCH/DELETE` methods.
- Rate limiting middleware with global bucket and optional API-key-specific bucket.
- Version header enforcement (`x-api-version` must be `v1`).
- Standardized JSON error responses.
- API deprecation headers middleware.

## 6. Threats and Mitigations (STRIDE)

| STRIDE | Threat | Affected Surface | Severity | Current Mitigations | Additional Mitigation Actions |
|---|---|---|---|---|---|
| Spoofing | Credential/token theft and replay against high-value write endpoints | All authenticated write paths | High | Bearer auth + read-only write blocking | Short-lived tokens, token binding where possible, stronger session invalidation telemetry, anomaly detection for token reuse across IP/device |
| Spoofing | Forged client identity for rate-limit bypass via `x-forwarded-for` when proxy chain is not trusted | All rate-limited paths | High | IP-based rate limiting | Trust-proxy allowlist, canonical client-IP extraction, signed edge headers, fallback to socket peer if proxy not trusted |
| Tampering | Unauthorized mutation of financial/compliance state due to coarse RBAC model | Broad write APIs (accounts, payments, loans, AML, contracts, treasury) | High | `read_only` cannot write | Enforce fine-grained RBAC per endpoint + action + resource ownership; deny-by-default policy |
| Tampering | Payload-level data tampering/injection through insufficient input constraints | JSON request bodies and path params across handlers | High | Handler-level validation exists but is not centrally enforced for all handlers | Central schema validation gateway, strict allowlists, canonicalization, injection regression tests |
| Repudiation | Weak non-repudiation from request logs missing actor and response status in middleware | All APIs | Medium | Request method/path logged | Include actor/session/api_key_id, correlation id, status code, result class, and stable audit event id |
| Information Disclosure | Excessive data exposure through exports/statements/events endpoints and broad read access | `/export`, statements, events, usage, analytics, reporting APIs | High | Auth required on non-public paths | Data classification policy, field-level authorization/redaction, export scoping, privacy test cases |
| Information Disclosure | Overly permissive CORS policy (`*`) with credential-bearing client patterns | Browser-based clients calling API | Medium | CORS middleware active | Restrict origins by environment, explicit allowlists, review `authorization` header exposure rules |
| Denial of Service | Endpoint abuse on expensive operations (search, exports, replay, analytics, contracts, reconciliation) | Heavy read/write paths | High | Global/IP rate limiting | Endpoint-tier quotas, concurrency caps, pagination hard limits, backpressure, circuit breaking |
| Denial of Service | Unauthenticated endpoint pressure (`/metrics`, `/openapi.json`, `/health`, auth token/login) | Public endpoints | Medium | Some paths exempt from rate limit | Rate-limit public endpoints at edge, cache static specs, anti-automation on auth endpoints |
| Elevation of Privilege | Privilege escalation through broad role semantics and missing per-resource checks | Admin-style APIs (keys, workflows, AML, connectors, cluster, recovery, contracts) | High | Basic role check only (`read_only` vs others) | Role matrix with explicit capability sets, resource tenancy checks, policy-as-code tests |

## 7. High-Risk Findings and Required Follow-Ups

1. Fine-grained authorization is not consistently enforced; current model is too coarse for production banking.
2. Rate limiting depends on potentially spoofable forwarded headers without explicit trusted-proxy policy.
3. CORS is overly permissive for production operation.
4. Security telemetry lacks full actor and outcome context for forensic-grade investigations.
5. Public and expensive endpoints need stronger anti-automation and workload protection.

These findings map directly to remaining P6-S2 tasks:

- TASK-093: least-privilege RBAC enforcement.
- TASK-094: secrets management and key rotation.
- TASK-095: signed regulatory evidence and audit export pipeline.
- TASK-096: input sanitization and injection prevention.
- TASK-097: OWASP Top 10 security regression suite.

## 8. Control Gaps by Priority

P0 (immediate before broad external exposure):

- Implement resource-scoped RBAC and deny-by-default authorization checks.
- Lock down trusted proxy handling for client identity and rate limit keys.
- Restrict CORS origins per environment.

P1:

- Add endpoint risk tiers with per-tier quotas and concurrency limits.
- Add correlation IDs and actor-level audit metadata across all request logs.
- Add data minimization and redaction rules for export/reporting surfaces.

P2:

- Harden auth endpoints with adaptive throttling and suspicious pattern detection.
- Add threat-informed attack simulation cases into CI security regression gates.

## 9. Documentation Notes

- `audit/endpoint-inventory.md` currently undercounts and omits newer routes relative to `cb_router.erl`; update this inventory in a follow-up to keep audit evidence in sync.

## 10. Exit Statement for TASK-092

Threat model review for exposed API surfaces is complete and documented in this file, with concrete mitigation actions and priority sequencing for the remaining P6-S2 security hardening tasks.
