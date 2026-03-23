---
title: IronLedger 1.1 Specification
version: 1.0
date_created: 2026-03-23
last_updated: 2026-03-23
owner: Sean
tags: [process, release, product, roadmap, 1.1]
---

# Introduction

This specification defines the target for IronLedger 1.1.

Version 1.0 made IronLedger deployable and usable. Version 1.1 should make IronLedger meaningfully more credible as a modern digital core by adding control surfaces, product configuration, eventing, and reporting.

## 1. Purpose & Scope

Purpose:

- Move IronLedger beyond a functional prototype release toward a controlled and extensible banking platform

Scope for 1.1:

- Authentication and authorization
- Maker-checker operational workflows
- Product factory improvements for fees, limits, and product versions
- Holds and richer balance states
- Eventing and webhooks
- Statements and exports
- Customer lifecycle and KYC status

Out of scope for 1.1:

- Trade finance
- Treasury
- Full card issuing
- Full AML screening suite
- Multi-node clustering
- Full enterprise data warehouse

## 2. 1.1 Product Goals

- **GOAL-001**: Add security and operator control to the 1.0 runtime
- **GOAL-002**: Make product behavior more configurable without code changes
- **GOAL-003**: Improve banking realism through holds, limits, and internal posting rules
- **GOAL-004**: Expose reliable events and reports for downstream integrations and operations
- **GOAL-005**: Add customer lifecycle controls needed for real-world banking operations

## 3. Requirements

- **REQ-001**: The 1.1 runtime shall require authenticated access for dashboard and API usage.
- **REQ-002**: The 1.1 runtime shall support role-based permissions for at least administrator, operations, and read-only users.
- **REQ-003**: High-risk operations shall support approval workflows.
- **REQ-004**: Account and product behavior shall support configurable fees, limits, and versions.
- **REQ-005**: The ledger model shall support funds holds and available balance calculations.
- **REQ-006**: The system shall expose outbound domain events or webhooks for major lifecycle changes.
- **REQ-007**: The dashboard shall expose statements, exports, and operational approvals.
- **REQ-008**: Party management shall support onboarding or KYC state, not just active or suspended lifecycle state.
- **REQ-009**: 1.1 shall preserve all 1.0 workflows.
- **REQ-010**: 1.1 shall continue to pass the full 1.0 technical gate plus any new auth or eventing tests added for 1.1.

## 4. Acceptance Criteria

- **AC-001**: A user cannot access the dashboard or write APIs without authentication.
- **AC-002**: Role-based permissions are enforced for administrative and operational actions.
- **AC-003**: At least one maker-checker workflow is completed end to end through the dashboard.
- **AC-004**: Savings or loan products can be configured with fees or limits without code changes.
- **AC-005**: A hold placed on an account affects available balance while preserving ledger balance.
- **AC-006**: At least one domain event or webhook is emitted for a posted transaction and a loan lifecycle event.
- **AC-007**: Account statements or exports are available from the dashboard.
- **AC-008**: Party records include onboarding or KYC state and that state is visible in the dashboard.

## 5. Release Positioning

Positioning for 1.1:

- 1.0 = deployable and feature-complete for the initial banking surface
- 1.1 = controlled, configurable, integration-ready banking platform

## 6. Related Documents

- [Core Banking Benchmark 2026](/home/sean/workspace/projects/ironledger/docs/core-banking-benchmark-2026.md)
- [IronLedger 1.0 Release Specification](/home/sean/workspace/projects/ironledger/spec/process-release-1-0.md)
- [IronLedger 1.0 Deliverable Plan](/home/sean/workspace/projects/ironledger/plan/feature-release-1-0.md)
