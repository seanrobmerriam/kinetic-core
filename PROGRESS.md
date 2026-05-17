# GitHub Actions Migration Progress

## Read Phase

Status: ✅ complete

### 1) Existing workflow inventory

- .github/workflows/ci.yml

### 2) Existing workflow contents inspected

- Inspected: .github/workflows/ci.yml
- Workflow name: CI Quality Gate
- Triggers: push/pull_request on main, develop
- Jobs found: erlang, dashboard, mutation, integration

### 3) Workflow-level secrets references

- No `secrets.*` references found in existing workflow files.

### 4) Reusable workflow fragments / composite actions

- No composite actions found under .github/actions.

### 5) Repository structure confirmation (ls -1)

- agents
- apps
- audit
- _build
- CLAUDE.md
- config
- DEVELOPMENT.md
- docker-compose.yml
- Dockerfile.api
- docs
- LICENSE
- names.csv
- node_modules
- node_modules copy
- package.json
- package-lock.json
- README.md
- rebar.config
- REQUIREMENTS.md
- scripts
- sdk
- test

---

## Phase 1 - Delete

Status: ✅ complete

- Command run: remove all .yml/.yaml files under .github/workflows
- Verification: `find .github/workflows -type f | wc -l` => `0`

## Phase 2 - Scaffold

Status: ✅ complete

Created directories:

- .github/workflows
- .github/actions/setup-erlang
- .github/actions/setup-nextjs
- .github/actions/docker-build-push

`ls -R .github`:

```text
.github:
actions  workflows

.github/actions:
docker-build-push  setup-erlang  setup-nextjs

.github/actions/docker-build-push:

.github/actions/setup-erlang:

.github/actions/setup-nextjs:

.github/workflows:
```

## Phase 3 - Composite Actions ✅

Status: ✅ complete

Created:

- .github/actions/setup-erlang/action.yml
- .github/actions/setup-nextjs/action.yml
- .github/actions/docker-build-push/action.yml

Verification command executed:

```bash
for f in .github/actions/*/action.yml; do
	echo "--- $f ---"
	cat "$f"
done
```

Result: all three files present and content verified.

## Phase 4 - CI Workflows ✅

Status: ✅ complete

Created and verified workflow files:

- .github/workflows/ci-backend.yml
- .github/workflows/ci-frontend.yml
- .github/workflows/ci-integration.yml

Notes:

- Added integer-only money arithmetic guard to backend CI (`float64` detection gate).
- Common Test logs and PropEr logs configured for artifact upload with `if: always()`.

## Phase 5 - CD Workflows ✅

Status: ✅ complete

Created and verified workflow files:

- .github/workflows/cd-staging.yml
- .github/workflows/cd-production.yml

Notes:

- Production image builds publish only exact semver tags (no `latest` tag).
- Production deploy job targets `production` environment for manual approval control.

## Phase 6 - Security Workflow ✅

Status: ✅ complete

Created and verified workflow file:

- .github/workflows/security.yml

## Phase 7 - Verification ✅

Status: ✅ complete

### 1) Expected files existence check

All expected files present:

- ✅ .github/workflows/ci-backend.yml
- ✅ .github/workflows/ci-frontend.yml
- ✅ .github/workflows/ci-integration.yml
- ✅ .github/workflows/cd-staging.yml
- ✅ .github/workflows/cd-production.yml
- ✅ .github/workflows/security.yml
- ✅ .github/actions/setup-erlang/action.yml
- ✅ .github/actions/setup-nextjs/action.yml
- ✅ .github/actions/docker-build-push/action.yml

### 2) YAML syntax validation

All YAML files valid:

- ✅ valid: .github/workflows/ci-backend.yml
- ✅ valid: .github/workflows/ci-frontend.yml
- ✅ valid: .github/workflows/ci-integration.yml
- ✅ valid: .github/workflows/cd-staging.yml
- ✅ valid: .github/workflows/cd-production.yml
- ✅ valid: .github/workflows/security.yml
- ✅ valid: .github/actions/setup-erlang/action.yml
- ✅ valid: .github/actions/setup-nextjs/action.yml
- ✅ valid: .github/actions/docker-build-push/action.yml

### 3) Secret references found

- secrets.GITHUB_TOKEN
- secrets.PROD_HOST
- secrets.PROD_SSH_KEY
- secrets.PROD_USER
- secrets.STAGING_HOST
- secrets.STAGING_SSH_KEY
- secrets.STAGING_USER

### 4) Old workflow replacement count

- Total workflow files: 6 (expected: 6)
- ✅ Count correct

## Final Summary

| Phase | Description                        | Status |
|-------|------------------------------------|--------|
| 0     | Read existing workflows            | ✅     |
| 1     | Delete all old workflow files      | ✅     |
| 2     | Scaffold directory structure       | ✅     |
| 3     | Composite actions (3 files)        | ✅     |
| 4     | CI workflows (3 files)             | ✅     |
| 5     | CD workflows (2 files)             | ✅     |
| 6     | Security workflow (1 file)         | ✅     |
| 7     | Verification sweep                 | ✅     |

### Required GitHub Secrets

| Secret               | Used In                | Description                         |
|----------------------|------------------------|-------------------------------------|
| `STAGING_HOST`       | cd-staging             | Staging server IP/hostname          |
| `STAGING_USER`       | cd-staging             | SSH username for staging            |
| `STAGING_SSH_KEY`    | cd-staging             | Private SSH key (PEM) for staging   |
| `PROD_HOST`          | cd-production          | Production server IP/hostname       |
| `PROD_USER`          | cd-production          | SSH username for production         |
| `PROD_SSH_KEY`       | cd-production          | Private SSH key (PEM) for production|

> `GITHUB_TOKEN` is automatically provided by GitHub Actions - no manual setup needed.

### Branch & Tag Conventions

| Trigger                    | Workflow(s) fired                    |
|----------------------------|--------------------------------------|
| PR targeting any branch    | ci-backend, ci-frontend              |
| Push to `main`             | ci-backend, ci-frontend, ci-integration, cd-staging |
| Push tag `v*.*.*`          | cd-production                        |
| Every Monday 03:00 UTC     | security                             |
| Manual dispatch            | security                             |
