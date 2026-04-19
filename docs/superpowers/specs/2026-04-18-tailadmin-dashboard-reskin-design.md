# TailAdmin-Style Dashboard Reskin Design

Date: 2026-04-18
Owner: GitHub Copilot
Status: Draft for user review

## 1. Objective

Reskin the entire IronLedger dashboard UI (including login) to closely match the TailAdmin visual style while preserving all existing application behavior and API interactions.

## 2. Scope

In scope:
- Full authenticated dashboard shell and all dashboard screens
- Login screen visual redesign
- Light theme as default
- Optional dark theme retained and polished
- Consistent TailAdmin-like layout, spacing, components, and interaction states

Out of scope:
- Business logic changes
- API contract or payload changes
- Workflow changes (navigation and feature behavior remain intact)

## 3. Confirmed Product Decisions

- Coverage: Entire dashboard (not a subset)
- Theme strategy: Light default with optional dark mode
- Visual direction: Close TailAdmin match (layout and styling)
- Login page: Included in this pass

## 4. Design Direction

### 4.1 Visual System

- Palette: TailAdmin-like neutral base with blue primary accents and semantic status colors
- Surfaces: Soft border-first cards with subtle elevation and modern radii
- Typography: Existing bundled font stack retained, with adjusted sizing/weight hierarchy
- Spacing: Strict 8px rhythm with consistent internal padding across cards and forms
- Motion: Light, purposeful transitions for hover/focus/active states

### 4.2 Layout Model

- Fixed sidebar on desktop, sticky top header, scrollable content area
- Uniform content gutters and vertical rhythm between sections
- Responsive collapse/wrapping behavior for tablet and mobile

### 4.3 Component Styling Model

- Buttons: unified primary/secondary/ghost styles
- Inputs/selects/textareas: consistent border, focus ring, and helper/error patterns
- Cards: shared shell for summary blocks, forms, tables, and detail sections
- Tables: compact rows, clear header hierarchy, semantic status badges
- Alerts/empty/loading: consistent visual language and spacing

## 5. Screen-by-Screen Design Mapping

### 5.1 Login

- Desktop split composition (context panel + auth card)
- Mobile stacked single-column layout
- TailAdmin-like auth card styling and field states

### 5.2 App Shell

- Sidebar: stronger contrast, grouped sections, active route pill
- Header: sticky bar with title/actions and balanced spacing

### 5.3 Core Views

Applied to all current views:
- Dashboard Home
- Customers
- Accounts
- Account Detail
- Transactions
- Ledger
- Products
- Loans
- Transfer and operational forms

Each view adopts:
- Consistent card and toolbar structure
- TailAdmin-like table/forms/filters
- Shared spacing and typography rules

## 6. Implementation Strategy

Primary file targets:
- `apps/cb_dashboard/dist/index.html` (global design tokens + component CSS)

Secondary file targets (only if structural class hooks are needed):
- `apps/cb_dashboard/app.go`
- `apps/cb_dashboard/views.go`

No intended behavior change file:
- `apps/cb_dashboard/api.go`

Sequence:
1. Update design tokens and base primitives
2. Reskin shell (sidebar, header, content wrapper)
3. Reskin shared components (cards/buttons/forms/tables/badges/alerts)
4. Apply login-specific layout and polish
5. Normalize all screen-level layouts
6. Tune responsive and dark-mode states

## 7. Risk and Compatibility Controls

- Preserve all existing DOM ids used by event listeners
- Keep JS/WASM behavior and handlers unchanged
- Prefer additive class refinements over structural rewrites
- Validate each major styling phase in both light and dark themes

## 8. Verification Plan

Build verification:
- WASM build from `apps/cb_dashboard` must succeed

UI verification:
- Login flow works end-to-end after restyle
- Navigation and actions continue functioning on all pages
- Tables/forms/cards render consistently
- Responsive behavior remains usable on desktop/tablet/mobile
- Dark mode remains readable and visually coherent

## 9. Acceptance Criteria

This work is complete when:
- Entire dashboard and login page are visually aligned with a TailAdmin-like look
- No functional regressions are introduced
- Light and dark themes are both polished and usable
- WASM build passes and manual smoke checks pass
