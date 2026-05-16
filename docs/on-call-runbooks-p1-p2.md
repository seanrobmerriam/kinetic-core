# P1 and P2 On-Call Runbooks

This document defines the first-response runbooks for all Phase 1 and Phase 2 capabilities in Kinetic Core.

Scope covered:

- Phase 1: API surface expansion, developer experience, internationalization, and FX maturity.
- Phase 2: compliance and AML controls, omnichannel consistency, and product factory flows.

Use this document together with:

- `GET /health`
- `GET /metrics`
- `GET /api/v1/operations/slo`
- `GET /api/v1/operations/logs`
- `GET /api/v1/openapi.json`

## On-Call Defaults

Apply these steps before a scenario-specific response:

1. Confirm whether the incident is still active using `/health`, `/metrics`, SLO snapshot, and structured logs.
2. Capture blast radius: affected endpoint, party segment, channel, product, provider, and start time.
3. Stop unsafe write actions when data correctness is uncertain. Prefer read-only investigation over speculative retries.
4. Preserve evidence: correlation IDs, API key IDs, session IDs, affected resource IDs, and export or workflow identifiers.
5. Escalate immediately if customer balances, ledger integrity, SAR evidence, or KYC decisions look incorrect.

## Severity Guide

Use these priorities for all scenarios below:

- `P1`: live customer-impacting outage, incorrect financial state, broken compliance control, or unsafe auth boundary.
- `P2`: degraded but partially functioning service, delayed processing, fallback activated, or limited-scope admin issue.

## Quick Commands

```bash
curl -s http://localhost:18081/health
curl -s http://localhost:18081/metrics
curl -s -H "Authorization: Bearer $TOKEN" http://localhost:18081/api/v1/operations/slo
curl -s -H "Authorization: Bearer $TOKEN" "http://localhost:18081/api/v1/operations/logs?limit=100"
curl -s http://localhost:18081/api/v1/openapi.json
rebar3 ct --suite apps/cb_integration/test/cb_api_baseline_SUITE.erl
rebar3 ct --suite apps/cb_integration/test/cb_auth_integration_SUITE.erl
rebar3 ct --suite apps/cb_integration/test/cb_slo_policies_SUITE.erl
```

## Scenario Matrix

| Runbook ID | Phase tasks covered | Primary surface |
| --- | --- | --- |
| RB-P1-API-01 | TASK-026, TASK-027 | REST API and composite reads |
| RB-P1-DX-02 | TASK-028, TASK-032 | SDK generation and usage analytics |
| RB-P1-AUTH-03 | TASK-029 | Partner API keys and throttling |
| RB-P1-QUERY-04 | TASK-030, TASK-033 | GraphQL and deprecation warnings |
| RB-P1-WEBHOOK-05 | TASK-031 | Webhook lifecycle management |
| RB-P1-FX-06 | TASK-034 | External FX provider fallback |
| RB-P1-I18N-07 | TASK-035, TASK-036, TASK-037 | Locale, RTL, and communication templates |
| RB-P2-COMP-08 | TASK-038, TASK-039 | KYC workflows and IDV orchestration |
| RB-P2-AML-09 | TASK-040, TASK-041 | AML queue, cases, and SAR reports |
| RB-P2-OMNI-10 | TASK-042, TASK-043 | Channel context and session sync |
| RB-P2-OMNI-11 | TASK-044, TASK-045 | Feature flags, limits, and notifications |
| RB-P2-PROD-12 | TASK-046, TASK-047, TASK-048, TASK-049 | Product catalogs and repayment schedules |

## RB-P1-API-01: REST or Composite Read Failures

Applies to:

- OpenAPI drift
- composite party or account read failures
- 404 or 500 spikes on high-value read endpoints

Symptoms:

- client SDKs fail on previously valid payloads
- `GET /api/v1/openapi.json` differs from handler behavior
- composite read endpoints return partial or empty results while base resources still exist

Immediate actions:

1. Check `GET /api/v1/openapi.json` and compare with the failing endpoint.
2. Search structured logs by path and correlation ID for request parsing or downstream read failures.
3. Confirm base entities exist through direct REST reads before escalating as a storage issue.

Diagnosis:

- If base reads work but composite reads fail, inspect aggregation handler behavior first.
- If OpenAPI drift is the only failure, treat it as a documentation and SDK compatibility incident, not a data incident.
- If 5xx occurs on both base and composite reads, move to platform or Mnesia investigation.

Recovery:

- Prefer restoring backward-compatible response fields before changing clients.
- Regenerate SDKs only after confirming OpenAPI matches runtime behavior.
- If a release introduced incompatible response shape, roll back that API change set.

Escalate when:

- clients cannot deserialize current production responses
- read paths expose missing or cross-customer data

## RB-P1-DX-02: SDK or API Usage Report Pipeline Failure

Applies to:

- SDK generation pipeline breakage
- missing API usage analytics or incorrect developer-facing usage reports

Symptoms:

- generated SDK artifacts are absent, stale, or fail build
- API usage reports flatline while traffic is still present

Immediate actions:

1. Verify `./scripts/generate-sdks.sh` still runs against current OpenAPI.
2. Confirm usage events are still being written and reported.
3. Search logs for export, generation, or usage-recording errors.

Recovery:

- Regenerate SDKs from the current committed OpenAPI source of truth.
- If analytics ingestion failed, restore event recording before backfilling reports.
- Mark dashboards as stale if report data is incomplete.

Escalate when:

- partner integrations are blocked by broken published SDKs
- usage analytics is required for contractual throttling or billing review

## RB-P1-AUTH-03: Partner API Key or Throttling Failure

Applies to:

- invalid API key authentication outcomes
- unintended revocation effects
- throttling misconfiguration or abusive traffic bypass

Symptoms:

- healthy keys start returning `401` or `403`
- traffic exceeds expected rate limits without `429`
- legitimate partner traffic is rate-limited after a config change

Immediate actions:

1. Confirm whether failures are isolated to one partner key or all keys.
2. Inspect auth middleware logs and API usage events.
3. Check recent key rotation or rate-limit policy changes.

Recovery:

- Restore the last known-good key metadata or rate limit value.
- If a rotation caused widespread failure, revert to the previously active key state if policy allows.
- If abuse bypasses throttling, tighten limits and preserve evidence for follow-up.

Escalate when:

- multiple partners are locked out
- unauthorized traffic is accepted through an auth boundary

## RB-P1-QUERY-04: GraphQL Gateway or Deprecation Warning Failure

Applies to:

- GraphQL read failures
- missing deprecation notices or broken migration warning behavior

Symptoms:

- GraphQL errors on previously valid read queries
- deprecated REST paths no longer emit warnings
- warning headers or payload metadata disappear after release

Immediate actions:

1. Reproduce the failing query against GraphQL and equivalent REST reads.
2. Confirm whether the issue is schema drift, resolver failure, or auth behavior.
3. Check deprecation middleware and release notes for removed warnings.

Recovery:

- Restore resolver compatibility before expanding schema.
- Re-enable deprecation warnings before removing old paths from client guidance.
- If only the warning channel broke, keep deprecated endpoints available until repaired.

Escalate when:

- GraphQL returns inconsistent customer data compared with REST
- deprecated endpoints were removed without a migration path

## RB-P1-WEBHOOK-05: Webhook Lifecycle or Delivery Failure

Applies to:

- subscription create or update failure
- delivery backlog, repeated retries, or callback rejection

Symptoms:

- new subscriptions cannot be created
- webhook delivery attempts pile up or remain in retry state
- partner callbacks return persistent `4xx` or `5xx`

Immediate actions:

1. Inspect webhook subscription and delivery state.
2. Separate control-plane errors from downstream partner endpoint failures.
3. Confirm the affected event types and whether outbox growth is increasing.

Recovery:

- Pause only the failing subscription or callback destination when possible.
- Preserve undelivered events for replay instead of dropping them.
- If the callback contract changed, restore compatibility or coordinate a partner-side rollback.

Escalate when:

- regulatory or transaction state-change notifications are not leaving the outbox
- retries threaten system stability or exhaust resources

## RB-P1-FX-06: External FX Provider Degradation or Fallback Failure

Applies to:

- primary FX provider outage
- stale fallback rates
- currency conversion errors or missing quotes

Symptoms:

- quote retrieval latency spikes or requests fail
- fallback path activates but returns stale or unsupported rates
- cross-currency flows stop while same-currency flows remain healthy

Immediate actions:

1. Confirm whether primary provider errors are upstream or local integration issues.
2. Check fallback activation in logs and current effective rate timestamps.
3. Stop cross-currency write flows if quote freshness cannot be trusted.

Recovery:

- Use configured fallback only within allowed freshness bounds.
- If freshness bounds are exceeded, fail closed and communicate partial service degradation.
- After provider recovery, confirm rates normalize before reopening blocked flows.

Escalate when:

- stale FX rates may have been applied to booked transactions
- fallback path is unavailable and cross-currency processing is business-critical

## RB-P1-I18N-07: Locale, RTL, or Template Rendering Failure

Applies to:

- locale formatting regressions
- RTL layout breakage
- communication template mismatch by locale or jurisdiction

Symptoms:

- wrong date, number, or currency formatting in API or UI output
- RTL pages render unusably
- notification or document templates appear in the wrong locale or omit jurisdiction flags

Immediate actions:

1. Confirm whether the issue is rendering-only or the wrong locale decision upstream.
2. Compare affected locale output with default locale behavior.
3. Preserve examples of incorrect templates and rendered payloads.

Recovery:

- Revert broken locale-pack or template changes before editing customer data.
- If only one locale is affected, scope mitigation to that locale instead of disabling all communication flows.
- If jurisdictional content is wrong, pause outbound notices for that locale until corrected.

Escalate when:

- customer notices contain incorrect regulatory language
- locale bugs produce incorrect monetary display that could mislead customers

## RB-P2-COMP-08: KYC Workflow or IDV Orchestration Failure

Applies to:

- workflow transition failure
- stuck or duplicated KYC steps
- IDV timeout or retry loop exhaustion

Symptoms:

- parties remain indefinitely in `pending` or `in_progress`
- IDV checks time out or exceed retry limits
- workflow state and step state disagree

Immediate actions:

1. Identify whether failure is at workflow state transition, step execution, or provider orchestration.
2. Check affected party count and whether one provider or one workflow version is common.
3. Preserve party IDs, workflow IDs, check IDs, and provider references.

Recovery:

- Resume from the last valid workflow state when safe; do not skip required review steps silently.
- If the external IDV provider is unstable, route to manual review or approved retry policy.
- Block automatic approval if verification evidence is incomplete.

Escalate when:

- verified status may have been granted without evidence
- onboarding is globally blocked or high-value segments cannot be reviewed

## RB-P2-AML-09: AML Queue, Case, or SAR Workflow Failure

Applies to:

- suspicious activity alerts not being raised
- case queue backlog or assignment failure
- SAR generation or filing artifact failure

Symptoms:

- AML queue volume drops to zero during active traffic
- alerts exist but cases are not created or updated
- SAR exports fail, are incomplete, or cannot be retrieved

Immediate actions:

1. Confirm whether rule evaluation, queue persistence, or report generation is failing.
2. Inspect recent AML rule changes and structured logs around suspicious activity handling.
3. Preserve alert IDs, case IDs, and SAR report identifiers.

Recovery:

- Restore rule evaluation first if new suspicious activity is being missed.
- Manually hold affected cases if automation cannot safely escalate them.
- Re-run SAR generation only after confirming the underlying case data is complete.

Escalate when:

- suspicious activity may be bypassing required controls
- SAR evidence or generated reports may be incomplete or altered

## RB-P2-OMNI-10: Channel Context or Session Synchronization Failure

Applies to:

- missing unified customer context across channels
- failed invalidate-all behavior
- stale session state across web, mobile, branch, or ATM

Symptoms:

- party context differs by channel for the same customer
- invalidated sessions remain active on one channel
- login or logout behavior is inconsistent across channels

Immediate actions:

1. Confirm whether context propagation or session synchronization is the failing layer.
2. Compare the same party across two affected channels.
3. Preserve party ID, session IDs, and channel type for each inconsistent result.

Recovery:

- Prefer forced session invalidation over partial patching when state is inconsistent.
- Rebuild or refresh channel context from the source record instead of mutating only one channel copy.
- If ATM or branch channels diverge, notify operations teams before reopening write flows.

Escalate when:

- a revoked or invalidated session remains active
- customer identity or entitlement differs by channel

## RB-P2-OMNI-11: Channel Limits, Feature Flags, or Notification Routing Failure

Applies to:

- wrong channel limit enforcement
- feature flags unexpectedly disabled or enabled
- notification routing or preference misapplication

Symptoms:

- allowed transactions are blocked or blocked transactions succeed
- channel-specific features disappear after config changes
- notifications go to the wrong channel or ignore preferences

Immediate actions:

1. Determine whether the issue is config storage, policy lookup, or runtime evaluation.
2. Compare current config with the last known-good operational values.
3. Preserve channel, party, feature name, limit values, and event type.

Recovery:

- Revert misconfigured flags or limits to known-good values.
- If notification routing is wrong, stop affected outbound dispatch for that event type until corrected.
- If limit enforcement is unsafe, fail closed on the affected channel until policy is restored.

Escalate when:

- financial limits are bypassed
- sensitive notifications are sent to the wrong destination

## RB-P2-PROD-12: Product Catalog, Launch, Eligibility, or Schedule Failure

Applies to:

- product version mismatch
- deposit or loan product launch failure
- eligibility or pricing miscalculation
- repayment schedule generation error

Symptoms:

- product state is inconsistent between catalog and creation flows
- customers cannot open expected products after launch
- loan schedules differ across repeated deterministic calculations
- pricing or eligibility outcomes change without config intent

Immediate actions:

1. Identify whether the issue is product definition versioning, activation state, or schedule generation.
2. Compare current product attributes with the prior active version.
3. Preserve product IDs, loan IDs, and generated repayment artifacts.

Recovery:

- Roll back to the prior product version if pricing or eligibility is wrong.
- Stop new originations on affected products while preserving read access.
- Recompute repayment schedules only after confirming the deterministic engine inputs are correct.

Escalate when:

- customers may have been offered or booked against incorrect terms
- repayment schedules or pricing are non-deterministic across identical inputs

## Escalation Targets

Escalate to the owning team based on the incident domain:

- `cb_integration`: API, OpenAPI, GraphQL, webhooks, deprecation, operations endpoints
- `cb_auth`: sessions, API keys, OAuth, role enforcement
- `cb_currency`: FX providers, exchange rates, locale-aware currency formatting
- `cb_compliance`: KYC, IDV, AML, SAR flows
- `cb_channels`: context propagation, session sync, limits, flags, notifications
- `cb_savings_products` and `cb_loans`: product catalogs and repayment calculations

## Evidence Checklist

Include these in the incident ticket before handoff:

- incident start time and current status
- severity (`P1` or `P2`)
- failing endpoint, workflow, or product ID
- correlation IDs and example request paths
- affected party IDs, account IDs, loan IDs, or report IDs
- current SLO snapshot and relevant structured log excerpts
- mitigation already applied
- explicit rollback risk if a code or config revert is proposed