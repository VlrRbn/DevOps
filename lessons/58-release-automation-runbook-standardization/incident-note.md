# Release / Incident Note

## Metadata

- date: 2026-03-03
- environment: lab environment (internal ALB, accessed via SSM port-forward)
- service: `project-redacted` web fleet behind ALB target group
- lesson/lab: lesson 58 (automation) on top of lesson 57 gates
- operator: `operator-redacted`

## Change Context

- candidate build: `57-01` (observed in canary build sampler)
- previous build: `57-02` (baseline build sampler was 100% `57-02`)
- rollout mode: single-fleet rolling `Instance Refresh`
- checkpoint: expected `50%` (`--require-checkpoint --checkpoint-pct 50`)

## Signals Observed

- safety alarms:
  - `lab57-target-5xx-critical = OK`
  - `lab57-alb-unhealthy-hosts = OK`
- quality alarms:
  - `lab57-release-target-5xx = OK`
  - `lab57-release-latency = OK`
- target health:
  - baseline: 2/2 healthy (`i-xxxxxxxxxxxx1`, `i-xxxxxxxxxxxx2`)
  - canary: 2/2 healthy (`i-xxxxxxxxxxxx3`, `i-xxxxxxxxxxxx2`)
- refresh status:
  - at decision time (from `decision.txt`): `InProgress`, `50%`, checkpoint matched
  - later snapshot (`instance-refreshes.json`): `InProgress`, `100%` (refresh kept progressing)
- load profile (baseline/canary):
  - baseline: `total=36960 ok=36960 bad=0 avg=0.078s`
  - canary: `total=54960 ok=54960 bad=0 avg=0.090s`
  - `load_http_000=0` in both runs
- build sampling:
  - baseline sampler: `57-02` only (80/80)
  - canary sampler: mixed `57-01` and `57-02` (40/40)

## Decision

- decision: `GO`
- reason: all safety + quality gates stayed `OK`; target health stable; canary had no transport failures
- decision timestamp: `2026-03-03T20:00:58+00:00`

## Evidence Links

- artifact directory:
  - baseline: `evidence/l58-baseline-<timestamp>/`
  - canary: `evidence/l58-canary-<timestamp>/`
- `decision.txt`:
  - `evidence/l58-baseline-<timestamp>/decision.txt`
  - `evidence/l58-canary-<timestamp>/decision.txt`
- `summary.json`:
  - `evidence/l58-baseline-<timestamp>/summary.json`
  - `evidence/l58-canary-<timestamp>/summary.json`
- `alarms.json`:
  - `evidence/l58-baseline-<timestamp>/alarms.json`
  - `evidence/l58-canary-<timestamp>/alarms.json`
- `target-health.json`:
  - `evidence/l58-baseline-<timestamp>/target-health.json`
  - `evidence/l58-canary-<timestamp>/target-health.json`
- `instance-refreshes.json`:
  - `evidence/l58-baseline-<timestamp>/instance-refreshes.json`
  - `evidence/l58-canary-<timestamp>/instance-refreshes.json`
- `scaling-activities.json`:
  - `evidence/l58-baseline-<timestamp>/scaling-activities.json`
  - `evidence/l58-canary-<timestamp>/scaling-activities.json`
- `build-sampler.txt`:
  - `evidence/l58-baseline-<timestamp>/build-sampler.txt`
  - `evidence/l58-canary-<timestamp>/build-sampler.txt`
- `load.summary.txt`:
  - `evidence/l58-baseline-<timestamp>/load.summary.txt`
  - `evidence/l58-canary-<timestamp>/load.summary.txt`

Note: raw evidence files remain local and are intentionally not committed.

## Actions Taken

- action 1: baseline check executed through local SSM port-forward (`127.0.0.1:18080`)
- action 2: canary check executed with strict checkpoint guard (`--require-checkpoint`)
- action 3: release marked `GO`; rollout allowed to continue

## Follow-ups

- follow-up 1: align canary duration with checkpoint window (`checkpoint_delay=180s` vs `canary=300s`) to keep decision window strictly inside checkpoint
- follow-up 2: optionally archive each result folder into `.tar.gz` for easier handoff
- owner: `operator-redacted`
- due date: 2026-03-04
