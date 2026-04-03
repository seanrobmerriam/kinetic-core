# Release 1.1 Handoff

## Current State

- Repo: `/Users/sean/workspace/projects/github.com/ironledger/ironledger`
- Branch: `main`
- `main` is ahead of `origin/main` by 6 commits
- Last merged release-1.1 work:
  - `eb0cdc6` `merge: scaffold 1.1 platform services`
  - `da77c84` `merge: add authenticated API sessions`
  - `3034e7c` `merge: add dashboard authentication flow`

## Uncommitted Working Tree

These changes exist locally and are not committed yet:

- [docker-compose.yml](/Users/sean/workspace/projects/github.com/ironledger/ironledger/docker-compose.yml)
  - Host API port changed from `8081` to `18081` to avoid collision with another local Docker stack.
- [README.md](/Users/sean/workspace/projects/github.com/ironledger/ironledger/README.md)
  - Docker Compose usage examples updated to point at `http://localhost:18081/api/v1`.

If the next agent wants to keep that change, it should be committed intentionally before more release work starts.

## What Is Already Implemented

### 1.1 Platform Baseline

- New OTP apps scaffolded and wired into the build:
  - `cb_auth`
  - `cb_approvals`
  - `cb_events`
  - `cb_reporting`
- Shared schema creation extended in [cb_schema.erl](/Users/sean/workspace/projects/github.com/ironledger/ironledger/apps/cb_integration/src/cb_schema.erl) for:
  - `auth_user`
  - `auth_session`
  - `audit_log`
  - `approval_request`
  - `approval_decision`
  - `event_outbox`
  - `webhook_subscription`
  - `webhook_delivery`
  - `report_statement`
  - `report_export`

### Auth Domain and HTTP

- [cb_auth.erl](/Users/sean/workspace/projects/github.com/ironledger/ironledger/apps/cb_auth/src/cb_auth.erl) supports:
  - `create_user/3`
  - `get_user/1`
  - `authenticate/2`
  - `create_session/1`
  - `get_session/1`
  - `delete_session/1`
  - `ensure_bootstrap_users/0`
- Password hashing is still minimal:
  - `crypto:hash(sha256, Password)`
- Session handoff from Cowboy middleware uses request process dictionary because this Cowboy version does not provide `cowboy_req:set_meta/3`.
- Auth routes are live in the integration layer:
  - `POST /api/v1/auth/login`
  - `POST /api/v1/auth/logout`
  - `GET /api/v1/auth/me`
- Auth middleware leaves `/health` and `/api/v1/auth/login` public and requires bearer auth everywhere else.

### Dashboard Auth

- Dashboard now has:
  - login screen
  - session bootstrap from `localStorage`
  - bearer token propagation in the shared fetch helper
  - logout action
  - automatic session clear on `401`
- Default bootstrap credentials are configured in [sys.config](/Users/sean/workspace/projects/github.com/ironledger/ironledger/config/sys.config):
  - email: `admin@example.com`
  - password: `secret-pass`

## Verified Work

These commands were run successfully during the last implementation pass:

```bash
cd apps/cb_dashboard
GOOS=js GOARCH=wasm go build -o dist/ironledger.wasm .
```

```bash
rebar3 ct --suite apps/cb_auth/test/cb_auth_SUITE.erl
```

```bash
rebar3 ct --suite apps/cb_integration/test/cb_auth_integration_SUITE.erl
```

## Known Outstanding Issue

The dashboard auth slice is merged, but the long Playwright dashboard flow is not stable yet.

### Current Symptom

- [test/dashboard-e2e.js](/Users/sean/workspace/projects/github.com/ironledger/ironledger/test/dashboard-e2e.js) was updated to:
  - log in first
  - support alternate host API URLs through `DASHBOARD_API_URL`
  - wait for `networkidle` after navigation and success banners
- The full browser flow still fails later in the sequence, most recently at:
  - waiting for `Savings product created`

### What Was Learned

- Auth itself is working:
  - login succeeds
  - protected `GET` routes succeed with the dashboard bearer token
- Isolated browser reproductions can successfully create:
  - a customer
  - a savings product
- The unstable behavior appears only in the long chained SPA flow.
- Most likely problem area:
  - async rerenders and follow-up fetches are replacing DOM nodes or racing form input in multi-step navigation.

## Recommended Next Task

Continue from Task 2 dashboard stabilization before moving deeper into Task 3.

Suggested next branch:

```bash
git checkout -b feature/release-1-1-dashboard-e2e-stability
```

Suggested immediate goal:

- make the dashboard E2E flow deterministic again under authenticated operation

Likely places to inspect:

- [test/dashboard-e2e.js](/Users/sean/workspace/projects/github.com/ironledger/ironledger/test/dashboard-e2e.js)
- [app.go](/Users/sean/workspace/projects/github.com/ironledger/ironledger/apps/cb_dashboard/app.go)
- [api.go](/Users/sean/workspace/projects/github.com/ironledger/ironledger/apps/cb_dashboard/api.go)
- [views.go](/Users/sean/workspace/projects/github.com/ironledger/ironledger/apps/cb_dashboard/views.go)

## Practical Notes For The Next Agent

- There is another local Docker project using host port `8081`.
- If the Compose port change is kept, use:
  - Dashboard: `http://localhost:8080`
  - API: `http://localhost:18081/api/v1`
- Internal runtime port inside the API container remains `8081`.
- There is no `docs/` tree in this workspace even though older README text referenced one earlier in the project review.

## Minimal Resume Checklist

1. Decide whether to commit the current `docker-compose.yml` and `README.md` port change.
2. Create a new feature branch from `main`.
3. Reproduce the browser flow with the new host API port if keeping the Compose change.
4. Stabilize the dashboard rerender/network timing issue in the full E2E flow.
5. Merge that slice before moving on to approvals and maker-checker work.
