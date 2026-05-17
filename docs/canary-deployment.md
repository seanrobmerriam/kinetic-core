# Canary Deployment Support

The repository now includes a release gate for canary deployments at `scripts/canary-gate.sh`.

## What It Checks

- `/health` on the baseline and canary targets.
- `/api/v1/operations/slo` on the baseline and canary targets.
- Critical SLO alerts and breached objectives on the canary target.

## Rollback Trigger

If the canary target fails health checks or produces a breached SLO snapshot, the gate runs the rollback command supplied with `--rollback-cmd`.

## Example

```bash
bash scripts/canary-gate.sh \
  --baseline-url http://stable-api:8081 \
  --canary-url http://canary-api:8081 \
  --bearer-token "$OPS_TOKEN" \
  --monitor-seconds 300 \
  --interval-seconds 15 \
  --rollback-cmd 'kubectl rollout undo deployment/ironledger'
```

## Operational Notes

- Use a canary gate after a deployment and before traffic promotion.
- Keep the rollback command idempotent.
- Do not promote a canary if the baseline target is unhealthy.
- For manual incident review, capture the final health and SLO outputs together with the canary start time.
