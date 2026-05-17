# Users, Roles, and Permissions Implementation Plan

## Purpose
Implement working Admin dashboard sections for Users, Roles, and Permissions with backend APIs, RBAC enforcement, auditability, and CI verification.

## Implementation Status
- Started: 2026-05-17
- Completed in this change:
  - RBAC-010: Added Mnesia tables `auth_role`, `auth_permission`, `auth_role_permission`, `auth_user_role` with lookup indexes.
  - RBAC-011: Added RBAC record and type definitions in shared ledger header.
  - RBAC-012 (initial): Added `cb_rbac` transactional domain service for roles, permissions, assignments, and effective permission computation.
  - RBAC-013 (partial): Added idempotent startup seeding for built-in roles, permission catalog, and baseline grants.
  - RBAC-020: Added router entries for Users, Roles, and Permissions APIs.
  - RBAC-021 (initial): Implemented users handler endpoints for list/create/get/patch and role assignment/unassignment.
  - RBAC-022 (initial): Implemented roles handler endpoints for list/create/patch and role permission get/replace.
  - RBAC-023: Implemented permissions catalog endpoint with grouped output.
  - RBAC-024: Enriched login and me payloads with effective roles and permissions.
  - RBAC-002: Added OpenAPI schemas and paths for users, roles, and permissions endpoints. Schemas include RbacUser (with roles array of strings, permissions array of strings), RbacUserList, RbacRole, RbacRoleList, RbacRolePermissionKeys, and RbacPermission. API paths documented for users CRUD, roles CRUD, role permissions get/replace, and permissions catalog.
  - RBAC-030/RBAC-031: Added permission-key evaluation in auth middleware with `rbac_enforced` observe/enforce toggle, structured denial telemetry fields, and dual-mode integration tests.
  - RBAC-040/RBAC-041/RBAC-042/RBAC-043 (initial): Added typed frontend admin API client and implemented initial `/users`, `/roles`, `/permissions` pages wired to backend endpoints.
  - RBAC-044 (initial): Added frontend permission helpers, admin tab visibility guards, admin sidebar filtering by required permission, and route-level redirect guards for `/users`, `/roles`, and `/permissions`.
  - RBAC-051: Added frontend Jest RBAC guard coverage plus CI wiring in frontend and integration workflows for RBAC route and endpoint compatibility checks.
  - RBAC-052 (partial): Added runbook procedures for enabling RBAC enforcement and emergency rollback.

## Current Baseline
- Admin nav links exist in dashboard sidebar: `/users`, `/roles`, `/permissions`.
- Those routes do not yet exist in dashboard app.
- Backend auth currently supports coarse role values (`admin`, `operations`, `read_only`) and session auth.
- Authorization is currently path and method based in middleware, not permission-key based.

## Guiding Principles
- Keep existing login and session behavior stable while RBAC is introduced.
- Add RBAC incrementally behind a feature flag.
- Preserve deterministic error responses and audit every write action.
- Avoid breaking existing role-based protections until RBAC enforcement is validated.

## Phase 0: Design Freeze

### RBAC-001 Permission Taxonomy and Role Policy
**Scope**
- Define stable permission keys (for example: `user.read`, `user.write`, `role.read`, `role.write`, `permission.read`).
- Define built-in roles and mutability rules.

**Files**
- `REQUIREMENTS.md`
- `DEVELOPMENT.md`

**Acceptance Criteria**
- Permission namespace and naming convention approved.
- Built-in role behavior documented (immutable or partially immutable).
- Custom role behavior documented.

**Verification**
- Stakeholder sign-off on documented model.

### RBAC-002 API Contract and Error Model
**Scope**
- Define request and response contracts for Users, Roles, Permissions endpoints.
- Define deterministic error responses for validation and authorization failures.

**Files**
- `README.md`
- `apps/cb_integration/src/cb_http_errors.erl`
- `apps/cb_integration/src/handlers/cb_openapi_handler.erl`

**Acceptance Criteria**
- API contract written and versioned.
- Error payload shape is consistent across endpoints.

**Verification**
- OpenAPI output includes new resources and schemas.

## Phase 1: Backend Data Layer

### RBAC-010 Add RBAC Tables to Schema
**Scope**
Add Mnesia tables:
- `auth_role`
- `auth_permission`
- `auth_role_permission`
- `auth_user_role`

**Files**
- `apps/cb_integration/src/cb_schema.erl`

**Acceptance Criteria**
- Tables exist with indexes for common lookups (`user_id`, `role_id`, `permission_key`, status).

**Verification**
- `rebar3 ct` passes schema/runtime suites.

### RBAC-011 Add RBAC Types and Records
**Scope**
- Add type and record definitions for role and permission entities.

**Files**
- `apps/cb_ledger/include/cb_ledger.hrl`

**Acceptance Criteria**
- Types compile and align with schema attributes.

**Verification**
- `rebar3 compile` passes.

### RBAC-012 Implement RBAC Domain Service
**Scope**
Create RBAC domain operations:
- list, create, update roles
- grant and revoke role permissions
- assign and unassign user roles
- compute effective permissions for a user

**Files**
- `apps/cb_auth/src/cb_rbac.erl` (new)
- `apps/cb_auth/src/cb_auth_sup.erl`
- `apps/cb_auth/src/cb_auth_app.erl`

**Acceptance Criteria**
- All operations are transactional and return explicit `{ok, Value}` or `{error, Reason}`.

**Verification**
- Unit and integration tests for each operation.

### RBAC-013 Seed Built-In Roles and Permissions
**Scope**
- Seed default roles and permission catalog at startup.
- Ensure idempotent seeding.

**Files**
- `apps/cb_integration/src/cb_integration_app.erl`
- `config/sys.config`

**Acceptance Criteria**
- Repeated startups do not create duplicates.

**Verification**
- Restart app twice and validate seed consistency.

## Phase 2: API Surface

### RBAC-020 Add Router Entries
**Scope**
Add routes for:
- Users
- Roles
- Permissions

**Files**
- `apps/cb_integration/src/cb_router.erl`

**Acceptance Criteria**
- Endpoints dispatch to correct handlers.

**Verification**
- API baseline tests updated and passing.

### RBAC-021 Implement Users Handler
**Scope**
- `GET /api/v1/users`
- `POST /api/v1/users`
- `GET /api/v1/users/:user_id`
- `PATCH /api/v1/users/:user_id`
- `POST /api/v1/users/:user_id/roles`
- `DELETE /api/v1/users/:user_id/roles/:role_id`

**Files**
- `apps/cb_integration/src/handlers/cb_users_handler.erl` (new)

**Acceptance Criteria**
- Validation is strict and deterministic.
- Mutations produce audit entries.

**Verification**
- CT happy path and failure path coverage.

### RBAC-022 Implement Roles Handler
**Scope**
- `GET /api/v1/roles`
- `POST /api/v1/roles`
- `PATCH /api/v1/roles/:role_id`
- `GET /api/v1/roles/:role_id/permissions`
- `PUT /api/v1/roles/:role_id/permissions`

**Files**
- `apps/cb_integration/src/handlers/cb_roles_handler.erl` (new)

**Acceptance Criteria**
- System roles are protected from destructive edits.

**Verification**
- CT includes forbidden checks for protected roles.

### RBAC-023 Implement Permissions Handler
**Scope**
- `GET /api/v1/permissions` (catalog)

**Files**
- `apps/cb_integration/src/handlers/cb_permissions_handler.erl` (new)

**Acceptance Criteria**
- Returns stable, grouped permission data.

**Verification**
- Contract test validates schema and ordering.

### RBAC-024 Enrich Auth Payloads
**Scope**
- Include user roles and effective permissions in auth payloads.

**Files**
- `apps/cb_integration/src/handlers/cb_login_handler.erl`
- `apps/cb_integration/src/handlers/cb_me_handler.erl`

**Acceptance Criteria**
- Dashboard can render capability-aware UI without extra startup calls.

**Verification**
- Auth integration tests assert enriched payload structure.

## Phase 3: Authorization Migration

### RBAC-030 Permission Mapping and Fallback
**Scope**
- Add route and method to permission-key mapping.
- Maintain fallback to current role checks when mapping is absent.

**Files**
- `apps/cb_integration/src/cb_auth_middleware.erl`

**Acceptance Criteria**
- No behavior regressions with feature flag off.

**Verification**
- Security regression suite passes in fallback mode.

### RBAC-031 Feature Flag for Enforcement
**Scope**
- Add `rbac_enforced` toggle.
- Support observe mode and enforce mode.

**Files**
- `config/sys.config`
- `apps/cb_integration/src/cb_integration_app.erl`

**Acceptance Criteria**
- Observe mode logs would-deny decisions.
- Enforce mode returns `forbidden` consistently.

**Verification**
- Tests cover both modes.

### RBAC-032 Denial Telemetry and Audit Enrichment
**Scope**
- Structured logs for authorization denials with required permission and user context.

**Files**
- `apps/cb_integration/src/cb_log_middleware.erl`
- `apps/cb_integration/src/cb_structured_logs.erl`

**Acceptance Criteria**
- Denials are traceable in operations logs.

**Verification**
- Logs endpoint exposes RBAC denial fields.

## Phase 4: Dashboard Implementation

### RBAC-040 Add Admin API Client and Types
**Scope**
- Add typed frontend API client for users, roles, permissions.

**Files**
- `apps/cb_dashboard/src/lib/api/admin.ts` (new)
- `apps/cb_dashboard/src/lib/types.ts`
- `apps/cb_dashboard/src/lib/api.ts` (if shared helpers are needed)

**Acceptance Criteria**
- Frontend compiles with strict types for RBAC resources.

**Verification**
- `npm run build` passes.

### RBAC-041 Implement Users Page
**Scope**
- Build `/users` page with list, search, create, status actions, role assignments.

**Files**
- `apps/cb_dashboard/src/app/(app)/users/page.tsx` (new)

**Acceptance Criteria**
- Admin can create and manage users and role memberships end-to-end.

**Verification**
- Manual flow and UI error state validation.

### RBAC-042 Implement Roles Page
**Scope**
- Build `/roles` page with role list, create/edit custom roles, and permission assignment.

**Files**
- `apps/cb_dashboard/src/app/(app)/roles/page.tsx` (new)

**Acceptance Criteria**
- System roles show protected controls.
- Custom role editing works.

**Verification**
- Mutation tests and manual checks.

### RBAC-043 Implement Permissions Page
**Scope**
- Build `/permissions` page showing catalog grouped by resource and role coverage.

**Files**
- `apps/cb_dashboard/src/app/(app)/permissions/page.tsx` (new)

**Acceptance Criteria**
- Permission inventory is readable and linked to role assignments.

**Verification**
- UI reflects updates immediately after role-permission save.

### RBAC-044 Extend Frontend Auth State and Guards
**Scope**
- Store and use effective permissions in auth state.
- Conditionally hide or disable unauthorized UI actions.

**Files**
- `apps/cb_dashboard/src/lib/auth.tsx`
- `apps/cb_dashboard/src/components/Sidebar.tsx`
- `apps/cb_dashboard/src/components/Header.tsx`

**Acceptance Criteria**
- Non-admin users cannot access restricted admin operations in UI.

**Verification**
- Validate behavior with `admin`, `operations`, and `read_only` accounts.

## Phase 5: Tests, CI, and Docs

### RBAC-050 Backend Integration and Security Tests
**Scope**
- Add CT coverage for RBAC CRUD, role assignment, and allow/deny matrix.

**Files**
- `apps/cb_integration/test/cb_auth_integration_SUITE.erl` (12 new tests added)

**Acceptance Criteria**
- Permission checks validated for all critical endpoints.

**Verification**
- `rebar3 ct` ✅ All 20 tests passing

**Completed**: 2026-01-17. Added 12 new CT tests covering:
- `create_role_succeeds`, `create_role_duplicate_key_fails`
- `update_role_succeeds`, `update_system_role_fails`
- `delete_role_succeeds` (verify via list, no DELETE endpoint exists)
- `assign_user_role_succeeds`, `unassign_user_role_succeeds`
- `effective_permissions_accumulates`
- `enforce_mode_admin_all_rbac_endpoints`, `enforce_mode_readonly_denied_user_write`, `enforce_mode_readonly_denied_role_write`, `enforce_mode_empty_role_user_denied`

### RBAC-051 Frontend and CI Gates
**Scope**
- Ensure CI validates RBAC frontend and API compatibility.

**Files**
- `.github/workflows/ci-integration.yml`
- `apps/cb_dashboard/package.json`

**Acceptance Criteria**
- CI fails on RBAC type or lint regressions.

**Verification**
- `npm run lint`
- `npm run build`

### RBAC-052 Documentation and Runbooks
**Scope**
- Update setup, role model, permissions model, and rollback instructions.

**Files**
- `README.md`
- `DEVELOPMENT.md`
- `docs/on-call-runbooks-p1-p2.md`

**Acceptance Criteria**
- Operators can enable, observe, and roll back RBAC enforcement safely.

**Verification**
- Runbook walkthrough review.

## Recommended Rollout Sequence
1. Complete Phase 0 through Phase 2.
2. Deploy Phase 3 in observe mode (`rbac_enforced = false`).
3. Ship dashboard pages in Phase 4.
4. Enable enforcement only for Users/Roles/Permissions endpoints first.
5. Expand enforcement boundary after at least one stable cycle.

## Definition of Done
- Users, Roles, and Permissions links lead to working pages.
- Admin can create a user, assign a role, and observe access changes on next auth refresh.
- Unauthorized requests are denied with deterministic responses.
- All RBAC mutations are auditable.
- Verification gates pass:
  - `rebar3 compile`
  - `rebar3 ct`
  - `cd apps/cb_dashboard && npm run lint`
  - `cd apps/cb_dashboard && npm run build`

## Risk Register
- **Risk:** Privilege escalation by incorrect permission mapping.
  - **Mitigation:** Default deny for mapped endpoints and explicit tests per route.
- **Risk:** Backward compatibility break for existing role-only sessions.
  - **Mitigation:** Fallback role logic until full mapping is complete.
- **Risk:** Operational outage if enforcement enabled too early.
  - **Mitigation:** Observe mode, structured denial logs, gradual endpoint rollout.
- **Risk:** Editing system roles creates lockout.
  - **Mitigation:** Hard backend guardrails and protected UI controls.
