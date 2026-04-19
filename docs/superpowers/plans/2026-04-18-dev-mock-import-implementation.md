# Dev Mock Import Implementation Plan

> Scope: Add a development-only, idempotent mock-data import flow exposed via an explicit API endpoint and a dashboard dev button.

## Tasks

- [ ] Add backend importer module
  - [ ] Create `cb_mock_data_importer` with deterministic seed dataset (parties, accounts, products, transactions, holds, loans)
  - [ ] Ensure idempotency by matching existing entities before create operations
  - [ ] Return a compact summary of created vs existing entities
- [ ] Add backend HTTP handler and route
  - [ ] Create `/api/v1/dev/mock-import` handler
  - [ ] `GET` returns capability (`enabled`)
  - [ ] `POST` executes import only when dev tools are enabled
  - [ ] Register route in router
  - [ ] Map `dev_tools_disabled` to a proper HTTP response
- [ ] Add configuration flag
  - [ ] Add `enable_dev_tools` under `cb_integration` in `config/sys.config`
- [ ] Wire dashboard action
  - [ ] Add API calls to read capability and trigger import
  - [ ] Add dev-only header action button
  - [ ] Refresh core datasets after import
- [ ] Verify end-to-end
  - [ ] `rebar3 compile`
  - [ ] Build dashboard wasm (`GOOS=js GOARCH=wasm go build -o dist/main.wasm`)
  - [ ] Smoke-check import endpoint call path
