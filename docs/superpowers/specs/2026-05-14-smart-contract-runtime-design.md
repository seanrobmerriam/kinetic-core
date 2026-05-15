# Smart Contract Runtime and DSL Design (P5-S3 TASK-081)

Date: 2026-05-14
Owner: GitHub Copilot
Status: Approved design draft for implementation

## 1. Objective

Define the v1 smart contract domain-specific language (DSL) and the execution safety constraints for product rule programmability.

This design fulfills P5-S3 TASK-081 and provides implementation-ready guidance for TASK-082 through TASK-084.

## 2. Scope

In scope:
- DSL v1 syntax and semantics
- Allowed data types and expression operators
- Contract execution lifecycle and deterministic behavior rules
- Runtime safety constraints (resource, side effects, authorization, replay)
- Stable validation and execution error contracts

Out of scope:
- Full sandbox implementation (TASK-082)
- Deployment and migration control APIs (TASK-083)
- Product experiments and replay tooling UI (TASK-084)

## 3. Design Principles

- Deterministic by default: same inputs produce same outputs.
- Financially safe: integer minor-unit money only, no floating-point math.
- Least privilege: contracts operate under explicit capability grants.
- Auditable: every decision and side effect emits structured audit evidence.
- Bounded execution: strict limits prevent untrusted code abuse.

## 4. DSL v1 Model

Contracts are data, not executable source text. The canonical representation is a validated map/JSON document.

### 4.1 Canonical shape

```json
{
  "contract_id": "product.loan.origination.v1",
  "dsl_version": "1.0",
  "name": "Loan Origination Eligibility",
  "status": "active",
  "trigger": {
    "event": "loan_application_submitted",
    "phase": "pre_validation"
  },
  "parameters": {
    "max_ltv_bps": 8000,
    "min_credit_score": 650
  },
  "rules": [
    {
      "id": "r1",
      "when": {
        "and": [
          {">": [{"var": "application.credit_score"}, {"param": "min_credit_score"}]},
          {"<=": [{"var": "application.ltv_bps"}, {"param": "max_ltv_bps"}]}
        ]
      },
      "then": [
        {"set": {"path": "decision.status", "value": "approved"}},
        {"emit": {"event": "contract.rule.approved", "severity": "info"}}
      ],
      "else": [
        {"set": {"path": "decision.status", "value": "manual_review"}},
        {"reject": {"reason": "eligibility_threshold_not_met"}}
      ]
    }
  ],
  "metadata": {
    "owner_role": "product_admin",
    "domain": "loans"
  }
}
```

### 4.2 Types

- `integer`: signed 64-bit integer
- `boolean`: `true` or `false`
- `string`: UTF-8, max 1024 bytes for scalar fields
- `date`: `YYYY-MM-DD`
- `datetime`: RFC3339 UTC timestamp
- `money_minor`: integer minor units only
- `currency`: ISO 4217 uppercase code
- `map` and `list`: bounded container types

Disallowed in v1:
- floating-point numeric types
- binary blobs
- arbitrary code fragments

### 4.3 Expression grammar (logical form)

- Comparison: `==`, `!=`, `<`, `<=`, `>`, `>=`
- Boolean: `and`, `or`, `not`
- Arithmetic: `+`, `-`, `*`, `div`, `mod` (integers only)
- Membership: `in`
- Accessors:
  - `{ "var": "path.to.input" }`
  - `{ "param": "parameter_name" }`

Built-ins (pure and deterministic):
- `abs`, `min`, `max`, `clamp`
- `days_between(date1, date2)`
- `currency_scale(currency)`

Forbidden built-ins:
- current wall-clock time access
- randomness
- network/filesystem/process access

### 4.4 Actions

Allowed actions in v1:
- `set`: set value in mutable decision context
- `reject`: terminate with domain error reason
- `emit`: emit internal domain event for audit/monitoring
- `enqueue_review`: route item to manual queue

Reserved for later versions:
- direct ledger posting
- external HTTP callbacks

## 5. Execution Lifecycle

1. Parse and schema-validate contract payload.
2. Static safety validation (limits, forbidden operators, capabilities).
3. Build deterministic execution plan.
4. Evaluate rules against immutable input context.
5. Apply allowed side effects in transactional envelope.
6. Persist execution trace and output decision.

Execution contract:
- Input: `#{contract, context, authz, request_id}`
- Output success: `{ok, DecisionMap, Trace}`
- Output failure: `{error, ReasonAtom, Trace}`

## 6. Safety Constraints (Mandatory)

### 6.1 Determinism

- No system clock reads during evaluation.
- No random number generation.
- No non-deterministic map iteration for rule ordering.
- Rule order is explicit and stable by list order.

### 6.2 Resource limits

- Max contract size: 128 KB
- Max rules per contract: 200
- Max expression depth: 16
- Max list size in evaluation context: 10,000
- Max execution steps per invocation: 50,000
- Max wall time per invocation: 50 ms (hard timeout)

Timeout or budget overrun returns `{error, execution_budget_exceeded, Trace}`.

### 6.3 Side-effect control

- Contracts cannot mutate input context.
- Side effects are whitelisted actions only.
- Side effects run after condition evaluation, in deterministic order.
- Any side-effect failure causes full rollback when running in transaction context.

### 6.4 Authorization and capability model

Required capability grants in contract metadata:
- `can_emit_event`
- `can_enqueue_review`
- `can_set_decision_fields`

Missing capability returns `{error, capability_denied, Trace}`.

### 6.5 Financial invariants

- Monetary values are integer minor units.
- Currency code must be present for any money field.
- Cross-currency arithmetic without explicit conversion is rejected.
- Overflow checks are mandatory for integer arithmetic.

### 6.6 Input and output schema safety

- Contract trigger defines required input schema.
- Unknown required fields fail fast at validation time.
- Decision output schema is versioned and strict.

## 7. Error Contract

Stable reason atoms for v1:
- `invalid_contract_schema`
- `unsupported_dsl_version`
- `forbidden_operator`
- `unknown_variable_path`
- `type_mismatch`
- `capability_denied`
- `execution_budget_exceeded`
- `contract_rejected`
- `side_effect_failed`

HTTP mappings are handled by integration layer in later tasks.

## 8. Audit and Replay Requirements

Each execution must persist:
- `execution_id`
- `contract_id`
- `contract_version`
- `input_hash`
- `decision_hash`
- `started_at`, `finished_at`, `duration_us`
- `result` (`ok` or `error`)
- `reason` (if error)
- `trace_steps` (bounded)

Replay rule:
- Replaying the same contract version with identical input and parameters must produce identical decision hash.

## 9. Versioning Baseline

Contract identity:
- logical id: `contract_id`
- immutable version: semantic version string

Compatibility policy:
- patch: non-breaking metadata/comment changes
- minor: additive fields/rules with backward-compatible output schema
- major: output schema changes or behavior-changing rule semantics

## 10. Implementation Handoff for TASK-082+

Create new app and modules:
- `apps/cb_contracts/src/cb_contracts.erl` (public API)
- `apps/cb_contracts/src/cb_contract_validator.erl` (schema and static safety validation)
- `apps/cb_contracts/src/cb_contract_eval.erl` (deterministic evaluator)
- `apps/cb_contracts/src/cb_contract_sandbox.erl` (execution budget and timeout guard)
- `apps/cb_contracts/src/cb_contract_audit.erl` (trace persistence)

Integration touchpoints:
- `apps/cb_integration/src/cb_router.erl` (future deployment and execute endpoints)
- `apps/cb_integration/src/cb_schema.erl` (contract and execution trace tables)

## 11. Acceptance Criteria for TASK-081

- DSL structure is fully specified and implementation-ready.
- Mandatory runtime safety constraints are defined with concrete limits.
- Error reasons are stable and suitable for API mapping.
- Audit and replay expectations are explicit and testable.
