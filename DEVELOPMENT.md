# Kinetic Core Development Plan

Document Version: 1.0  
Date: 2026-04-21  
Source: REQUIREMENTS.md

## 1. Purpose

This document converts the product requirements into an executable, phased development plan. It defines what to build in each phase, how to validate completion, and what dependencies must be satisfied before moving forward.

## 2. Planning Principles

- Build release-blocking core capabilities first.
- Keep each phase deployable and testable.
- Use API-first contracts and immutable auditability across all financial operations.
- Prefer additive schema changes and backward-compatible API evolution.
- Gate each phase with explicit exit criteria.

## 3. Program Structure

The roadmap is split into six phases:

- Phase 0: Release-Blocking Core Platform
- Phase 1: API and Internationalization Expansion
- Phase 2: Compliance, Channels, and Product Engine
- Phase 3: Automation and Ecosystem Integrations
- Phase 4: Enterprise Scale and Real-Time Core
- Phase 5: Intelligence and Programmable Products

## 3A. Subphase and Task Breakdown

This section breaks each phase into smaller execution units that can be scheduled as sprint work.

### Phase 0 Subphases and Tasks

#### P0-S1: Domain Foundations

- TASK-001 [DONE 2026-04-21]: Define customer aggregate model, lifecycle states, and validation schema.
- TASK-002 [DONE 2026-04-21]: Define account aggregate model, state machine, and account-party relationship rules.
- TASK-003 [DONE 2026-04-21]: Implement customer and account persistence contracts with versioning metadata.
- TASK-004 [DONE 2026-04-21]: Add customer search with pagination, sorting, and filter parameters.
- TASK-005 [DONE 2026-04-21]: Add duplicate detection and merge workflow design with audit events.

#### P0-S2: Ledger and Posting Core

- TASK-006 [DONE 2026-04-21]: Implement chart of accounts structure with account type hierarchy.
- TASK-007 [DONE 2026-04-21]: Implement immutable journal entry model for double-entry postings.
- TASK-008 [DONE 2026-04-21]: Implement ACID transaction posting pipeline with reversal support.
- TASK-009 [DONE 2026-04-21]: Add trial balance and general ledger query endpoints.
- TASK-010 [DONE 2026-04-21]: Add historical balance snapshot generation and retrieval.

#### P0-S3: Transaction Processing Baseline

- TASK-011 [DONE 2026-04-21]: Implement deposit workflows for cash, check, and transfer-in channels.
- TASK-012 [DONE 2026-04-21]: Implement withdrawal workflow with account state and limit checks.
- TASK-013 [DONE 2026-04-21]: Implement internal transfer workflow with same-currency guardrails.
- TASK-014 [DONE 2026-04-21]: Add transaction idempotency keys and conflict handling behavior.
- TASK-015 [DONE 2026-04-21]: Add transaction query capabilities by range, type, amount, and status.

#### P0-S4: API and Security Baseline

- TASK-016 [DONE 2026-04-21]: Publish OpenAPI baseline for release-blocking endpoints.
- TASK-017 [DONE 2026-04-21]: Implement request validation and standardized error envelope.
- TASK-018 [DONE 2026-04-21]: Implement API authentication and role-aware authorization guard.
- TASK-019 [DONE 2026-04-21]: Implement rate limiting and health or metrics endpoints.
- TASK-020 [DONE 2026-04-21]: Implement webhook event emission for transaction state changes.

#### P0-S5: Compliance, Currency, and Payments

- TASK-021 [DONE 2026-04-21]: Implement currency entity, precision rules, and conversion engine.
- TASK-022 [DONE 2026-04-21]: Implement exchange rate management with historical lookup support.
- TASK-023 [DONE 2026-04-21]: Implement KYC and risk tier state model with retention policy hooks.
- TASK-024 [DONE 2026-04-21]: Implement domestic payment initiation, status, cancel, and retry flows.
- TASK-025 [DONE 2026-04-21]: Implement exception queue and straight-through processing state machine.

#### P0-S6: Basic Omnichannel API Support

- TASK-026 [DONE]: Implement channel type enumeration and per-channel transaction limits with validation.
- TASK-027 [DONE]: Implement channel activity logging with party, channel, and action context.
- TASK-028 [DONE]: Implement unified party profile endpoint returning party, accounts, and recent transactions.
- TASK-029 [DONE]: Extend auth sessions with channel type; implement notification preference management.
- TASK-030 [DONE]: Implement ATM interface baseline with balance inquiry and withdrawal endpoints.

#### P0-S7: Dashboard Completion

- TASK-031 [DONE]: Add PaymentOrder, ExceptionItem, ChannelLimit, and ChannelActivity TypeScript types to dashboard.
- TASK-032 [DONE]: Implement Payment Orders dashboard page with initiation form, session order list, cancel, and retry.
- TASK-033 [DONE]: Implement Compliance dashboard page with Exception Queue tab and KYC Management tab.
- TASK-034 [DONE]: Implement Channels dashboard page with Channel Limits configuration tab and Activity Log tab.
- TASK-035 [DONE]: Update dashboard sidebar navigation with Payments, Compliance, and Channels entries.

#### P0-S8: Startup and Test Suite Green Gate [DONE]

- TASK-036 [DONE]: Fix `cb_webhooks:init/1` to tolerate already-started httpc profile across CT suites.
- TASK-037 [DONE]: Add `event_outbox` table to `cb_savings_products_SUITE`, `cb_loan_products_SUITE`, and `cb_interest_SUITE`.
- TASK-038 [DONE]: Add `party_audit` table to `cb_reporting_SUITE`, `cb_jobs_SUITE`, and `cb_interest_SUITE`.
- TASK-039 [DONE]: Add `event_outbox`, `webhook_subscription`, and `webhook_delivery` tables to `cb_jobs_SUITE`.
- TASK-040 [DONE]: Fix `cb_jobs_SUITE` `run_noop_job_ok` assertion — `webhook_retry` now returns `ok`, not `{ok, noop}`.
- TASK-041 [DONE]: Add missing Mnesia indices to `loan_products` (`[currency, status]`), `loan_accounts` (`[party_id, account_id, status]`), and `loan_repayments` (`[loan_id, status]`).
- TASK-042 [DONE]: Change `cb_auth_integration_SUITE` test port from 18081 (conflicts with OrbStack on dev machines) to 18083.

### Phase 1 Subphases and Tasks

#### P1-S1: API Surface Expansion

- TASK-026: Complete OpenAPI coverage for all existing platform endpoints.
- TASK-027: Implement composite customer and account read endpoints.
- TASK-028: Implement API SDK generation pipeline for Java, Python, Node.js, and .NET.
- TASK-029: Add partner API key lifecycle and throttling policy controls.

#### P1-S2: Query and Developer Experience

- TASK-030: Implement GraphQL gateway for high-value read scenarios.
- TASK-031: Implement webhook subscription lifecycle management APIs.
- TASK-032: Add API usage analytics and developer-facing usage reports.
- TASK-033: Add API deprecation lifecycle and migration warnings.

#### P1-S3: Internationalization and FX Maturity

- TASK-034: Integrate external FX provider interface and fallback strategy.
- TASK-035: Implement locale packs for date, number, and currency formatting.
- TASK-036: Implement RTL layout support for dashboard and documents.
- TASK-037: Add locale-aware communication templates and jurisdiction flags.

### Phase 2 Subphases and Tasks

#### P2-S1: Compliance and AML Controls

- TASK-038: Implement configurable KYC workflow builder and state transitions.
- TASK-039: Implement identity verification orchestration with retry and timeout rules.
- TASK-040: Implement AML rule authoring, suspicious activity queue, and case records.
- TASK-041: Implement SAR or regulatory report generation workflow.

#### P2-S2: Omnichannel Consistency

- TASK-042: Implement unified customer context propagation across channels.
- TASK-043: Implement cross-channel session synchronization and invalidation rules.
- TASK-044: Implement channel-specific feature flags and transaction limits.
- TASK-045: Implement omnichannel notification routing and preference management.

#### P2-S3: Product Factory

- TASK-046: Implement product definition model with versioned attributes.
- TASK-047: Implement deposit product catalog, launch flow, and lifecycle states.
- TASK-048: Implement loan product catalog with eligibility and pricing controls.
- TASK-049: Implement repayment schedule engine and deterministic calculation tests.

### Phase 3 Subphases and Tasks

#### P3-S1: STP Expansion and Exception Automation

- TASK-050: Implement rule-based routing for transaction decision paths.
- TASK-051: Integrate sanctions and fraud decision hooks into routing pipeline.
- TASK-052: Implement exception case management with SLA escalation.
- TASK-053: Add STP effectiveness dashboards and trend reporting.

#### P3-S2: Ecosystem and Connectors

- TASK-054: Implement connector abstraction and lifecycle contract.
- TASK-055: Implement AWS and Azure connector baseline packs.
- TASK-056: Implement partner onboarding workflow and compatibility checks.
- TASK-057: Implement connector versioning and rollback strategy.

#### P3-S3: Streaming and Advanced Payments

- TASK-058: Implement event schema registry and compatibility policy.
- TASK-059: Implement replay and backfill for streaming consumers.
- TASK-060: Implement SWIFT and ISO 20022 message processing pipeline.
- TASK-061: Implement settlement and reconciliation automation for payment rails.

### Phase 4 Subphases and Tasks

#### P4-S1: Enterprise Product Expansion

- TASK-062: Implement treasury capabilities and liquidity controls.
- TASK-063: Implement trade finance baseline workflows.
- TASK-064: Implement risk and capital calculation service interfaces.
- TASK-065: Implement cross-module reporting and data federation.

#### P4-S2: Real-Time Processing Scale

- TASK-066: Implement distributed transaction processing cluster design.
- TASK-067: Implement optimistic concurrency and conflict-resolution strategy.
- TASK-068: Implement horizontal scaling and capacity-triggered autoscaling rules.
- TASK-069: Implement failover and recovery orchestration tests.

#### P4-S3: Real-Time Ledger Hardening

- TASK-070: Implement sub-second ledger propagation and read freshness guarantees.
- TASK-071: Implement reconciliation automation and divergence alerting.
- TASK-072: Implement event replay-based ledger state recovery.
- TASK-073: Implement cryptographic audit-chain support for ledger history.

### Phase 5 Subphases and Tasks

#### P5-S1: Analytics Platform

- TASK-074: Implement analytics feature store and governed data pipelines.
- TASK-075: Implement customer segmentation and recommendation model services.
- TASK-076: Implement churn and anomaly prediction services with confidence scoring.
- TASK-077: Implement model monitoring, drift detection, and retraining triggers.

#### P5-S2: Conversational and Insight Delivery

- TASK-078: Implement natural-language analytics query gateway.
- TASK-079: Implement governed insight generation with role-aware access controls.
- TASK-080: Implement BYOK-backed encryption path for model data access.

#### P5-S3: Smart Contract Product Runtime

- TASK-081: Define smart contract DSL and execution safety constraints.
- TASK-082: Implement sandboxed contract execution environment.
- TASK-083: Implement contract deployment, versioning, and migration controls.
- TASK-084: Implement product variant experiments and audit replay support.

---

## Phase 0: Release-Blocking Core Platform

### Goal
Deliver the minimum viable, releasable banking platform.

### Workstreams

1. Customer and account management foundation
2. Real-time ledger foundation (double-entry, immutable events, reversals)
3. Basic transaction processing (deposit, withdrawal, transfer)
4. REST API foundation (OpenAPI, auth, validation, error standards)
5. Multi-currency core support
6. Basic compliance framework
7. Basic omnichannel API support
8. Vault payments basic integration
9. Straight-through processing foundation

### Concrete Deliverables

- Stable domain models for customer, account, transaction, ledger, currency.
- ACID-safe posting engine with idempotent transaction APIs.
- API platform layer with authentication, rate limits, health endpoints, and webhooks.
- Compliance baseline (KYC status, risk tiers, threshold rules, sanctions framework hooks).
- Payment initiation, status inquiry, cancellation, and retry.
- Exception queue plus workflow state machine for manual interventions.

### Exit Criteria

- All release-blocking APIs documented in OpenAPI and passing contract tests.
- Trial balance, GL reporting, and audit logs reconcile for all posted transactions.
- Idempotency enforced for all transaction endpoints.
- Compliance and monitoring alerts generated for configured threshold breaches.
- End-to-end flows validated:
  - Customer onboarding -> account opening -> deposit -> transfer -> withdrawal -> reporting

### Suggested Milestones

- P0-M1: Data models + ledger core
- P0-M2: Transaction APIs + idempotency + reversal workflows
- P0-M3: API platform hardening + compliance baseline
- P0-M4: Payments and STP foundation + release readiness gate

---

## Phase 1: API and Internationalization Expansion

### Goal
Expand integration reach and global readiness.

### Workstreams

1. Extensive REST API library
2. Multi-currency and multi-language support

### Concrete Deliverables

- Full endpoint coverage in OpenAPI plus API SDK generation.
- GraphQL gateway for flexible client queries.
- Partner API key lifecycle and analytics portal.
- Locale-aware formatting and resource translation framework.
- FX provider integration, historical rates, and configurable spreads.

### Exit Criteria

- SDKs generated and validated for Java, Python, Node.js, and .NET.
- GraphQL gateway covers defined high-value read scenarios.
- Localization support enabled for LTR and RTL with regression tests.
- Cross-currency operations pass reconciliation and historical-rate replay checks.

---

## Phase 2: Compliance, Channels, and Product Engine

### Goal
Move from baseline controls to production-grade policy and product configuration.

### Workstreams

1. Compliance and AML tooling
2. Omnichannel banking support
3. Loan and deposit product engine

### Concrete Deliverables

- Configurable KYC workflow builder and refresh scheduling.
- AML rule authoring, SAR workflow, and compliance dashboard.
- Unified channel context/session synchronization across web, mobile, branch, ATM.
- Configurable product catalog for deposits and loans with pricing, eligibility, lifecycle states.

### Exit Criteria

- KYC and AML workflows execute end-to-end with auditable decisions.
- Channel-specific limits and preferences are enforceable and tested.
- New product definitions are configurable without code changes.
- Loan/deposit product calculations pass deterministic test vectors.

---

## Phase 3: Automation and Ecosystem Integrations

### Goal
Increase operational efficiency and external connectivity.

### Workstreams

1. STP enhancement
2. Marketplace ecosystem
3. Vault data streaming
4. Vault payments expansion

### Concrete Deliverables

- Rule-driven routing, automated fraud and sanctions decision hooks, SLA escalation.
- Connector framework for cloud and partner integrations.
- Streaming backbone (event schema registry, replay/backfill, subscriber management).
- Expanded payment rail support (SWIFT, ISO 20022, clearing adapters, reconciliation).

### Exit Criteria

- STP rate and exception metrics visible and improving against baseline.
- Connector onboarding and version compatibility validation in place.
- Streaming replay succeeds for targeted recovery scenarios.
- Payment rail adapters pass conformance and reconciliation suites.

---

## Phase 4: Enterprise Scale and Real-Time Core

### Goal
Deliver high-throughput, high-availability enterprise banking capabilities.

### Workstreams

1. Universal banking coverage
2. Real-time transaction processing
3. Real-time ledger enhancements

### Concrete Deliverables

- Additional modules (treasury, trade finance, risk, wealth, capital, FTP).
- Distributed processing architecture with failover and autoscaling triggers.
- Sub-second ledger update propagation with state recovery and reconciliation automation.

### Exit Criteria

- Capacity benchmarks meet target TPS and latency objectives.
- Failover drills complete with controlled RTO/RPO thresholds.
- Cross-module transaction linkage and reporting verified.
- Ledger recovery from event replay validated under load.

---

## Phase 5: Intelligence and Programmable Products

### Goal
Add advanced intelligence and product programmability.

### Workstreams

1. AI-driven analytics and insights
2. Smart contract-based product engine

### Concrete Deliverables

- ML pipeline for segmentation, recommendations, churn, anomaly detection.
- Natural-language analytics query interface.
- Smart-contract runtime, deployment/versioning, and sandboxed execution.
- Product behavior experimentation via contract variants.

### Exit Criteria

- Model monitoring, drift tracking, and secure key handling in production.
- Smart-contract execution safety controls and full audit replay available.
- Contract version migrations validated without data loss.

---

## 4. Cross-Phase Engineering Tracks

These tracks run continuously across all phases.

1. Quality and testing
- Unit, integration, contract, and end-to-end suites for all new features.
- Performance, chaos, and recovery testing for critical paths.

2. Security and compliance
- Threat modeling, least-privilege access, secrets management, key rotation.
- Regulatory evidence capture and retention controls.

3. Observability and operations
- Metrics, tracing, structured logs, SLOs, and on-call runbooks.
- Automated rollback and incident response procedures.

4. Data governance and migration
- Schema versioning, migration tooling, backward compatibility policies.
- Data quality checks and lineage tracking.

---

## 5. Dependency Map

- Phase 0 is mandatory before all other phases.
- Phase 1 and Phase 2 can start in parallel after Phase 0 hardening is complete.
- Phase 3 depends on stable APIs from Phase 1 and control frameworks from Phase 2.
- Phase 4 depends on Phase 3 operational telemetry and integration maturity.
- Phase 5 depends on stable real-time data pipelines and governance controls from Phases 3 and 4.

---

## 6. Delivery Cadence and Governance

### Recommended Cadence

- Program increment length: 8 to 12 weeks per phase.
- Milestone checkpoints every 2 weeks.
- Gate review at end of each phase before advancing.

### Governance Model

- Architecture review board for cross-cutting decisions.
- API change control for versioning and deprecation approvals.
- Compliance review for KYC/AML/reporting workflow changes.
- Release review with evidence pack (tests, performance, security, runbooks).

---

## 7. Immediate Next Steps (Execution Start)

1. Confirm Phase 0 scope boundaries and success metrics.
2. Break Phase 0 into sprint-level backlog items per workstream.
3. Establish baseline non-functional targets:
- Throughput and latency
- Availability and recovery
- Auditability and compliance evidence
4. Stand up CI/CD quality gates:
- Contract tests
- Idempotency tests
- Financial reconciliation tests
- Security scans
5. Execute P0-M1 and begin weekly risk burndown reviews.

---

## 8. Risk Register (Initial)

- RISK-001: Ledger and idempotency defects can create financial inconsistency.
  - Mitigation: Mandatory reconciliation tests and immutable event audit checks.

- RISK-002: Compliance workflow gaps can block release approval.
  - Mitigation: Early compliance sign-off and threshold-rule simulation.

- RISK-003: API surface growth can create breaking-change pressure.
  - Mitigation: Strict versioning policy, contract tests, deprecation windows.

- RISK-004: Real-time and distributed scaling introduces operational complexity.
  - Mitigation: Incremental load testing, chaos drills, and staged rollouts.

- RISK-005: AI and smart-contract features can increase governance burden.
  - Mitigation: Delay to Phase 5 until observability, security, and data controls are mature.
