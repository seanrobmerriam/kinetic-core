#!/usr/bin/env bash
#
# canary-gate.sh — validate a canary deployment and trigger rollback on failure.
#
# The gate checks the stable baseline and canary endpoints using the existing
# health and SLO APIs. If the canary fails the gate, the optional rollback
# command is executed automatically.
#
# Usage:
#   bash scripts/canary-gate.sh \
#     --canary-url http://localhost:18081 \
#     --baseline-url http://localhost:18082 \
#     --rollback-cmd 'kubectl rollout undo deployment/ironledger' \
#     --bearer-token "$TOKEN" \
#     --monitor-seconds 300 \
#     --interval-seconds 15

set -euo pipefail

BASELINE_URL=""
CANARY_URL=""
HEALTH_PATH="/health"
SLO_PATH="/api/v1/operations/slo"
MONITOR_SECONDS=120
INTERVAL_SECONDS=15
ROLLBACK_CMD=""
BEARER_TOKEN=""

usage() {
  cat <<'EOF'
Usage: bash scripts/canary-gate.sh --canary-url URL [options]

Options:
  --baseline-url URL      Stable release URL to compare against.
  --canary-url URL        Canary release URL to validate. Required.
  --health-path PATH      Health endpoint path (default: /health).
  --slo-path PATH         SLO snapshot path (default: /api/v1/operations/slo).
  --monitor-seconds N     Total monitoring window in seconds (default: 120).
  --interval-seconds N    Poll interval in seconds (default: 15).
  --bearer-token TOKEN    Bearer token for authenticated SLO checks.
  --rollback-cmd CMD      Shell command to run automatically on canary failure.
  --help                  Show this help text.
EOF
}

while (($#)); do
  case "$1" in
    --baseline-url)
      BASELINE_URL="$2"
      shift 2
      ;;
    --canary-url)
      CANARY_URL="$2"
      shift 2
      ;;
    --health-path)
      HEALTH_PATH="$2"
      shift 2
      ;;
    --slo-path)
      SLO_PATH="$2"
      shift 2
      ;;
    --monitor-seconds)
      MONITOR_SECONDS="$2"
      shift 2
      ;;
    --interval-seconds)
      INTERVAL_SECONDS="$2"
      shift 2
      ;;
    --bearer-token)
      BEARER_TOKEN="$2"
      shift 2
      ;;
    --rollback-cmd)
      ROLLBACK_CMD="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$CANARY_URL" ]]; then
  echo "Missing required --canary-url" >&2
  usage >&2
  exit 2
fi

if [[ -z "$BASELINE_URL" ]]; then
  BASELINE_URL="$CANARY_URL"
fi

curl_args=(--silent --show-error --fail --connect-timeout 5 --max-time 15)
if [[ -n "$BEARER_TOKEN" ]]; then
  curl_args+=(-H "Authorization: Bearer ${BEARER_TOKEN}")
fi

tmpdir=$(mktemp -d)
cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT

fetch_json() {
  local name="$1"
  local base_url="$2"
  local path="$3"
  local body_file="$tmpdir/${name}.json"
  local status_file="$tmpdir/${name}.status"

  if curl "${curl_args[@]}" -o "$body_file" -w '%{http_code}' "${base_url}${path}" >"$status_file"; then
    local http_code
    http_code=$(cat "$status_file")
    if [[ "$http_code" != "200" ]]; then
      echo "[$name] ${base_url}${path} returned HTTP ${http_code}" >&2
      tail -c 500 "$body_file" >&2 || true
      return 1
    fi
    echo "$body_file"
    return 0
  fi

  echo "[$name] ${base_url}${path} request failed" >&2
  tail -c 500 "$body_file" >&2 || true
  return 1
}

evaluate_slo() {
  local name="$1"
  local json_file="$2"

  if node - "$json_file" <<'NODE'
const fs = require('fs');
const filePath = process.argv[2];
const data = JSON.parse(fs.readFileSync(filePath, 'utf8'));
const objectives = Array.isArray(data.objectives) ? data.objectives : [];
const alerts = Array.isArray(data.alerts) ? data.alerts : [];
const breachedObjectives = objectives.filter((objective) => objective.status === 'breached');
const criticalAlerts = alerts.filter((alert) => alert.severity === 'critical' && alert.state === 'firing');

console.log(JSON.stringify({
  objectiveCount: objectives.length,
  breachedObjectives: breachedObjectives.map((objective) => objective.id ?? objective.objective ?? 'unknown'),
  criticalAlerts: criticalAlerts.map((alert) => alert.alert_id ?? alert.objective ?? 'unknown')
}));

process.exit(breachedObjectives.length > 0 || criticalAlerts.length > 0 ? 1 : 0);
NODE
  then
    echo "[$name] SLO snapshot is healthy"
    return 0
  fi

  echo "[$name] SLO snapshot failed the gate" >&2
  return 1
}

check_target() {
  local name="$1"
  local base_url="$2"

  echo "==> Checking ${name} at ${base_url}"

  local health_ok=true
  local slo_ok=true

  if ! fetch_json "$name-health" "$base_url" "$HEALTH_PATH" >/dev/null; then
    health_ok=false
  fi

  local slo_file
  if slo_file=$(fetch_json "$name-slo" "$base_url" "$SLO_PATH"); then
    if ! evaluate_slo "$name" "$slo_file"; then
      slo_ok=false
    fi
  else
    slo_ok=false
  fi

  if [[ "$health_ok" = true && "$slo_ok" = true ]]; then
    echo "[$name] gate passed"
    return 0
  fi

  echo "[$name] gate failed"
  return 1
}

run_rollback() {
  if [[ -z "$ROLLBACK_CMD" ]]; then
    echo "Canary failed and no rollback command was provided" >&2
    return 1
  fi

  echo "==> Canary failed; executing rollback command"
  echo "    $ROLLBACK_CMD"
  bash -lc "$ROLLBACK_CMD"
}

deadline=$((SECONDS + MONITOR_SECONDS))
iteration=0

while :; do
  iteration=$((iteration + 1))
  echo "==> Canary monitor pass ${iteration}"

  if [[ -n "$BASELINE_URL" ]]; then
    check_target "baseline" "$BASELINE_URL" || {
      echo "Baseline is unhealthy; refusing to promote the canary" >&2
      exit 3
    }
  fi

  if ! check_target "canary" "$CANARY_URL"; then
    run_rollback
    exit 1
  fi

  if (( MONITOR_SECONDS <= 0 )); then
    break
  fi

  if (( SECONDS >= deadline )); then
    break
  fi

  sleep "$INTERVAL_SECONDS"
done

echo "Canary gate passed for ${MONITOR_SECONDS}s"
