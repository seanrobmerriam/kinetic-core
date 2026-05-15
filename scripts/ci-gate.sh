#!/usr/bin/env bash
#
# ci-gate.sh — local quality gate mirroring .github/workflows/ci.yml
#
# Run this before pushing to verify all CI checks will pass.
#
# Usage:
#   bash scripts/ci-gate.sh                  # all checks including integration
#   bash scripts/ci-gate.sh --skip-integration  # skip live-server tests
#
# Requires: rebar3, node, npm on PATH.
# On Windows: run from Git Bash or WSL.

set -euo pipefail

SKIP_INTEGRATION=false
for arg in "$@"; do
  [[ "$arg" == "--skip-integration" ]] && SKIP_INTEGRATION=true
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

# ─── Helpers ─────────────────────────────────────────────────────────────────

section() {
  echo
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  $1"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

run_check() {
  local label="$1"; shift
  printf "  %-42s" "$label..."
  local tmpout
  tmpout=$(mktemp)
  if "$@" >"$tmpout" 2>&1; then
    echo "✓ PASS"
    PASS=$((PASS + 1))
  else
    echo "✗ FAIL"
    FAIL=$((FAIL + 1))
    echo "    --- output ---"
    tail -20 "$tmpout" | sed 's/^/    /'
    echo "    ---------------"
  fi
  rm -f "$tmpout"
}

cd "$ROOT"

# ─── Erlang backend ──────────────────────────────────────────────────────────

section "Erlang Backend"
run_check "rebar3 compile"      rebar3 compile
run_check "rebar3 ct"           rebar3 ct
run_check "rebar3 dialyzer"     rebar3 dialyzer
run_check "rebar3 proper"       rebar3 proper --numtests 50

# ─── Dashboard ───────────────────────────────────────────────────────────────

section "Dashboard (apps/cb_dashboard)"
(cd apps/cb_dashboard && run_check "npm ci"           npm ci)
(cd apps/cb_dashboard && run_check "npm run lint"     npm run lint)
(cd apps/cb_dashboard && run_check "npm run build"    npm run build)
(cd apps/cb_dashboard && run_check "npm test"         npm test -- --passWithNoTests)

# ─── Mutation testing ────────────────────────────────────────────────────────

section "Mutation Testing"
run_check "kill rate ≥ 70%" \
  env MUTATION_STRICT=1 MUTATION_THRESHOLD=0.70 node test/mutation-test.js

# ─── Integration tests (optional) ────────────────────────────────────────────

if [ "$SKIP_INTEGRATION" = true ]; then
  echo
  echo "  [skipped] Integration tests (--skip-integration)"
else
  section "Integration Tests"

  rebar3 release >/dev/null 2>&1

  _build/default/rel/ironledger/bin/ironledger foreground &
  API_PID=$!
  trap "kill $API_PID 2>/dev/null || true" EXIT

  HEALTHY=false
  for i in $(seq 1 30); do
    curl -sf http://localhost:8081/health >/dev/null 2>&1 && { HEALTHY=true; break; } || sleep 2
  done

  if [ "$HEALTHY" = true ]; then
    run_check "contract tests" \
      env API_URL=http://localhost:8081 \
          DASHBOARD_AUTH_EMAIL=admin@example.com \
          DASHBOARD_AUTH_PASSWORD=secret-pass \
          node test/contracts.js
  else
    echo "  ✗ FAIL  API server did not become healthy within 60s"
    FAIL=$((FAIL + 1))
  fi

  kill $API_PID 2>/dev/null || true
fi

# ─── Summary ─────────────────────────────────────────────────────────────────

section "Summary"
echo "  Passed : $PASS"
echo "  Failed : $FAIL"
echo

if [ "$FAIL" -gt 0 ]; then
  echo "  GATE: FAIL — $FAIL check(s) did not pass. Fix before pushing."
  exit 1
else
  echo "  GATE: PASS — all checks green."
fi
