# Lesson 58: Release Automation & Runbook Standardization

## Purpose

This lesson standardizes the release-check flow from lesson 57 into one repeatable command:

- run baseline/canary load
- capture release evidence
- evaluate safety + quality gates
- print `GO` / `HOLD` / `ROLLBACK`

It also adds a reusable incident/release note template for consistent handoff.

## Prerequisites

- Lesson 57 completed and deployed
- Terraform outputs available in lab env:
  - `web_asg_name`
  - `web_tg_arn`
  - `alb_dns_name`
- AWS CLI + Terraform configured
- Reachability to internal ALB:
  - run from proxy host, or
  - use SSM port-forward (`--alb-url http://127.0.0.1:18080/`)

## Layout

- `lesson.en.md`
  - full lesson theory, runbook, drills, acceptance (EN)
- `lesson.ru.md`
  - full lesson theory, runbook, drills, acceptance (RU)
- `scripts/release-check.sh`
  - one-command release check (`baseline`/`canary`) with decision + artifacts
- `templates/incident-note.template.md`
  - reusable release/incident note template


### Lab Network Note

In this lab, ALB is internal.  
From local workstation, checks are run via SSM port-forward (`127.0.0.1:18080`).

If you run the check directly on the proxy instance inside VPC, port-forward is not required.


## Quick Start

```bash
chmod +x lessons/58-release-automation-runbook-standardization/scripts/release-check.sh

# Run from the lesson 57 terraform env directory
cd lessons/57-deployment-quality-gates/lab_57/terraform/envs

# Baseline check (3 min)
../../../../58-release-automation-runbook-standardization/scripts/release-check.sh \
  --mode baseline \
  --out-root /tmp

# Canary check (5 min)
../../../../58-release-automation-runbook-standardization/scripts/release-check.sh \
  --mode canary \
  --require-checkpoint \
  --out-root /tmp
```

Port-forward variant:

```bash
../../../../58-release-automation-runbook-standardization/scripts/release-check.sh \
  --mode canary \
  --alb-url http://127.0.0.1:18080/ \
  --out-root /tmp
```

Checkpoint verification (before canary):

```bash
aws autoscaling describe-instance-refreshes \
  --auto-scaling-group-name "$ASG_NAME" \
  --max-records 1 \
  --query 'InstanceRefreshes[0].[Status,PercentageComplete,StatusReason]' \
  --output table
```

For `[50]` checkpoint mode, expect `InProgress` + `50`.

## Decision Contract

Expected alarm names:

- `${PROJECT}-target-5xx-critical` (safety)
- `${PROJECT}-alb-unhealthy-hosts` (safety)
- `${PROJECT}-release-target-5xx` (quality)
- `${PROJECT}-release-latency` (quality)

Decision logic:

- any safety alarm in `ALARM` -> `ROLLBACK`
- release target 5xx in `ALARM` -> `ROLLBACK`
- release latency in `ALARM` -> `HOLD`
- no successful HTTP responses in load phase (`load_ok=0`) -> `HOLD`
- otherwise -> `GO`

Exit code contract:

- `0` = `GO`
- `1` = `HOLD`
- `2` = `ROLLBACK`
- `3` = canary aborted by `--require-checkpoint` (not at expected checkpoint)

## Output Contract

Each run writes:

`/tmp/l58-<mode>-YYYYmmdd_HHMMSS/`

Main artifacts:

- `decision.txt`
- `summary.json`
- `alarms.json`
- `target-health.json`
- `instance-refreshes.json`
- `scaling-activities.json`
- `build-sampler.txt`
- `load.log`
- `load.summary.txt`
- `load.codes.txt`

## Incident Note Template

```bash
cp lessons/58-release-automation-runbook-standardization/templates/incident-note.template.md \
   /tmp/l58-incident-note.md
```

Fill from `decision.txt` + `summary.json` + artifact files.

## Troubleshooting

- Wrong endpoint/no traffic: pass `--alb-url` explicitly and verify SSM tunnel.
- Unknown alarm states: verify lesson 57 alarm names still match current `PROJECT`.
- Empty build sampler: confirm response still includes `BUILD`/`Hostname`/`InstanceId`.
- `load_ok=0` or many `000` codes: you likely have no route to internal ALB from this shell; use proxy host or `--alb-url` with SSM port-forward.
- For latency HOLD drill, use `tc` flow documented in lesson section `Drill 2: Latency regression -> HOLD`.
- Unexpected decision: inspect `alarms.json` and `decision.txt` first.

## Cleanup

Lesson 58 itself creates only local artifact folders.  
To clean infrastructure, use lesson 57 Terraform cleanup:

```bash
cd lessons/57-deployment-quality-gates/lab_57/terraform/envs
terraform destroy
```
