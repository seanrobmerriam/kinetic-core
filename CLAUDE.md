# AGENTS.md

### Current Development Phase: P4-S1

## Purpose

This file defines implementation standards for contributors and coding agents working in this repository.

Goals:

- Keep backend financial behavior correct and auditable.
- Keep frontend behavior accessible and maintainable.
- Keep documentation accurate and actionable.

## Development Guidelines

### General Workflow

1. Read relevant requirements before editing:
- `REQUIREMENTS.md`
- `DEVELOPMENT.md`

2. Check the "Curent Development Phase" at the top of this file; that is the subphase you will be working on., 

3. Create a new git worktree for the subphase you are going to work on; all work is to be done in the worktree, and then merged into the main branch via PR when done.

4. Update the line at the top of this file that says '### Current Development Phase: ' by adding the subphase after the one you just completed.


### Commit and PR Hygiene

- One logical change per commit.
- Include a clear summary and risk notes.
- Include verification evidence (commands run and outcomes).
- Do not merge with failing checks.

### Safety Rules

- No destructive data operations without explicit requirement.
- No silent fallback paths for financial operations.
- No TODO placeholders in delivered code.

## Erlang Best Practices

### OTP and Architecture

- Use OTP behaviors correctly:
- `application`, `supervisor`, and `gen_server` only when stateful processes are required.
- Keep pure business logic outside process modules when possible.

- Respect app boundaries:
- Domain logic belongs in the owning app (`cb_accounts`, `cb_loans`, etc).
- HTTP handlers in `cb_integration` should stay thin and delegate to domain modules.

### Types, Specs, and Error Contracts

- Add `-spec` for all exported functions.
- Prefer precise types over `term()` whenever possible.
- Use explicit return contracts:
- `{ok, Value}` or `{error, Reason}`

- Keep error atoms stable and reusable across handlers.

### Data and Transactions

- Wrap financial table mutations in `mnesia:transaction/1` or `mnesia:sync_transaction/1`.
- Avoid dirty Mnesia operations on financial paths.
- Keep mutation order deterministic and idempotent where applicable.

### Money and Arithmetic

- Represent money as integer minor units.
- Do not use floating-point arithmetic in monetary flows.
- Validate boundaries and overflow paths explicitly.

### Logging and Observability

- Use structured logs with enough context to trace a request.
- Never log secrets, credentials, or sensitive personal data.

### Erlang Verification Gate

Run from repository root:

```bash
rebar3 compile
rebar3 ct
rebar3 dialyzer
rebar3 proper
```

## Next.js Best Practices

### Stack and Scope

Dashboard is a Next.js app in `apps/cb_dashboard` using TypeScript, React, and Mantine.

### Component and State Patterns

- Use functional components and hooks.
- Keep components focused and composable.
- Avoid over-centralized client state; colocate state with feature boundaries.

### Data and API Integration

- Keep API calls typed and centralized in feature-specific API modules.
- Handle loading, empty, success, and error states explicitly.
- Do not swallow API errors; show actionable UI feedback.

### Accessibility (Required)

- Conform to WCAG 2.2 AA.
- All interactive elements must be keyboard operable.
- Provide visible focus states and sufficient contrast.
- Ensure correct accessible name, role, and state for controls.

### Styling and UI Consistency

- Reuse Mantine components and tokens before introducing custom patterns.
- Keep layout responsive across desktop and mobile breakpoints.
- Prefer clear visual hierarchy and predictable interaction patterns.

### Frontend Verification Gate

Run from `apps/cb_dashboard`:

```bash
npm ci
npm run lint
npm run build
```

## API and Integration Rules

- Update routing intentionally in `apps/cb_integration/src/cb_router.erl`.
- Keep auth expectations explicit for every new endpoint.
- Ensure request validation and error mapping are deterministic.
- Keep API docs and examples aligned with implemented routes.

## Documentation Rules

### When To Update Docs

Update documentation whenever one of the following changes:

- API routes, request fields, response fields, or auth behavior
- Runtime ports, startup steps, or compose services
- Domain behavior, workflow states, or operational constraints
- Testing commands or release criteria

### Documentation Quality Standard

All documentation updates must be:

- Accurate: matches current code and runtime behavior
- Specific: includes concrete commands, paths, and expected outcomes
- Minimal: avoids stale historical context unless explicitly useful
- Actionable: enables a new contributor to execute without guessing

### Required Docs To Keep In Sync

- `README.md` for setup, runtime, and API summary
- `REQUIREMENTS.md` for scope requirements
- `DEVELOPMENT.md` for phased execution plan
- Module-level READMEs under `apps/*/README.md` when module behavior changes

### Writing Rules

- Prefer short sections with clear headings.
- Prefer checklists and tables for operational steps.
- Avoid ambiguous terms like "soon", "later", or "as needed".
- Remove or replace outdated references instead of appending contradictory notes.

## Definition of Done

A change is complete only when all are true:

1. Code changes compile and pass relevant tests.
2. Backward compatibility impact is documented.
3. Operational risks are called out when applicable.
4. Documentation is updated and consistent with implementation.
5. No known failing checks are introduced by the change.
