# TailAdmin-Style Dashboard Reskin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reskin the entire IronLedger dashboard and login page to a TailAdmin-like look while preserving existing behavior.

**Architecture:** Keep all Go/WASM behavior and IDs stable, and perform a presentation-layer refactor via CSS token and component overrides in the dashboard HTML stylesheet. Add minimal Go structural hooks only for theme toggle and login composition classes.

**Tech Stack:** Go WASM UI rendering, static HTML/CSS in `apps/cb_dashboard/dist/index.html`, Docker Compose runtime.

---

### Task 1: Add Theme Toggle and Login Layout Hooks

**Files:**
- Modify: `apps/cb_dashboard/app.go`
- Test: manual runtime smoke in browser

- [ ] **Step 1: Add theme helper functions and apply saved preference on app init**
- [ ] **Step 2: Add theme toggle button to header actions**
- [ ] **Step 3: Add TailAdmin-like login structure classes (`login-shell`, `login-hero`, `login-auth`, `login-card`) while keeping IDs and submit wiring unchanged**
- [ ] **Step 4: Build dashboard wasm**
Run: `cd apps/cb_dashboard && GOARCH=wasm GOOS=js go build -o dist/ironledger.wasm .`
Expected: exit code `0`

### Task 2: Apply TailAdmin-Like Global Design Tokens and Component Overrides

**Files:**
- Modify: `apps/cb_dashboard/dist/index.html`
- Test: visual checks across views

- [ ] **Step 1: Add a TailAdmin-style override block before `</style>`**
- [ ] **Step 2: Override shell components (`sidebar`, `main-header`, `content-area`)**
- [ ] **Step 3: Override shared primitives (`dashboard-card`, `data-table`, `btn`, `form-input`, `status-badge`, `alert`)**
- [ ] **Step 4: Add login-specific responsive styles for hero/auth split**
- [ ] **Step 5: Add dark-theme parity for key overrides**

### Task 3: Verify and Finalize

**Files:**
- Modify (if needed): `apps/cb_dashboard/dist/index.html`, `apps/cb_dashboard/app.go`

- [ ] **Step 1: Rebuild wasm**
Run: `cd apps/cb_dashboard && GOARCH=wasm GOOS=js go build -o dist/ironledger.wasm .`
Expected: exit code `0`

- [ ] **Step 2: Quick runtime smoke via compose logs and browser**
Checks:
- Login renders and submits
- Sidebar/header/tables/forms/cards show refreshed style
- Light default and dark toggle both render correctly

- [ ] **Step 3: Commit implementation changes**
Suggested message: `feat: TailAdmin-style dashboard and login reskin`
