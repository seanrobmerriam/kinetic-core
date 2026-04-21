# TailAdmin Dashboard Reskin — Implementation Plan

**Spec**: `docs/superpowers/specs/2026-04-18-tailadmin-dashboard-reskin-design.md`
**Status**: ✅ Complete

---

## Approach

The dashboard uses a Go WASM architecture where Go generates all DOM at runtime. All CSS lives in `apps/cb_dashboard/dist/index.html` inside a `<style>` block. No CSS files or component frameworks are used — the single `<style>` block is the only styling surface.

The implementation replaced the entire `<style>` block with a TailAdmin-aligned stylesheet. No Go files were modified; only CSS class styling values changed.

---

## What Changed

### File: `apps/cb_dashboard/dist/index.html`

- **Replaced**: Entire `<style>` block (~391 lines → ~944 lines)
- **WASM version**: bumped cache-buster `?v=9` → `?v=10`

#### New CSS tokens

| Token group | Description |
|---|---|
| `--sidebar-*` | Dedicated variables for the permanent dark navy sidebar (`#1C2434`), independent of light/dark theme |
| `--color-primary` | TailAdmin blue-indigo `#3C50E0` |
| `--color-success` | TailAdmin teal `#0FA979` |
| `--color-warning` | Amber `#F5A623` |
| `--color-bg-main` | Light mode main bg `#EFF4FB` |

#### New CSS classes (were missing from old stylesheet)

| Class | Where used |
|---|---|
| `.login-shell` | Top-level login view wrapper (flex row) |
| `.login-hero` | Left dark-navy hero panel with gradient overlay |
| `.login-hero-title` | Hero heading text |
| `.login-hero-subtitle` | Hero subheading text |
| `.login-hero-meta` | Hero bottom trust indicators |
| `.login-auth` | Right 420px auth form column |
| `.login-card` | Auth form inner card |
| `.login-form` | Login `<form>` element wrapper |
| `.form-label` | Generic form label utility |
| `.header-title` | App header title text |

#### Sidebar

- Permanent dark navy (`#1C2434`) in both light and dark themes
- Hover state: `#313D4A`; Active state: `#3C50E0` (primary blue) with white text
- Section headers use muted slate `#64748B`

#### Dark theme

- Affects only main content area (not sidebar)
- Deep slate palette: surface `#24303F`, bg `#1A222C`, border `#2E3A47`

#### Component updates

- **Cards**: border-first design (`border: 1px solid var(--color-border)`) replaces shadow-heavy style
- **Badges**: `--color-*-dark` tokens for better contrast on light badge backgrounds
- **Tables**: Tighter header padding, subtle stripe on hover
- **Buttons**: Full set: primary, secondary, outline, danger, success, small/large modifiers

---

## Testing

- ✅ WASM build: `GOOS=js GOARCH=wasm go build -o dist/ironledger.wasm .` — exit 0
- ✅ All existing CSS class names preserved (no Go file changes needed)
- ✅ All new login + header CSS classes added

---

## Commit

```
feat: TailAdmin-style dashboard reskin
5a269c0
```
