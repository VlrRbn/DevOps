# lesson_58

---

# Release Automation & Runbook Standardization

**Date:** 2026-03-03

**Focus:** turn lesson 57 gate logic into one repeatable release command.

**Mindset:** no manual release decisions without evidence.

---

## Why This Lesson Exists

Lesson_57 gave you:

- safety vs quality alarms
- canary checkpoint decisions
- proof-pack discipline

But the flow was still mostly manual.  
Lesson_58 standardizes the same flow so every release is run the same way.

---

## Outcomes

- one script runs load + snapshots + build sampling + decision
- one standard decision output: `GO` / `HOLD` / `ROLLBACK`
- one reusable incident/release note template
- one evidence folder per run (timestamped)

---

## Prerequisites

- lesson 57 completed
- Terraform outputs available in lab env:
  - `web_asg_name`
  - `web_tg_arn`
  - `alb_dns_name`
- AWS CLI + Terraform configured
- traffic path to ALB available:
  - either run on proxy host
  - or use SSM port-forward and pass `--alb-url http://127.0.0.1:18080/`

---

## Lab Network Note

In this lab, ALB is internal.

- Local workstation path: run checks via SSM port-forward (`127.0.0.1:18080`).
- In-VPC path: run checks from a host that already has direct route to internal ALB.

Port-forward is mainly used here to keep release execution and proof artifacts on your local machine.

---

## Repo Layout

```text
lessons/58-release-automation-runbook-standardization/
├── incident-note.md
├── lesson.en.md
├── README.md
├── templates/
│   └── incident-note.template.md
└── scripts/
    └── release-check.sh
```

---

## Standard Signal Contract

Automation expects these alarm names (from lesson_57):

- `${PROJECT}-target-5xx-critical` (safety)
- `${PROJECT}-alb-unhealthy-hosts` (safety)
- `${PROJECT}-release-target-5xx` (quality)
- `${PROJECT}-release-latency` (quality)

Decision rules:

- safety `ALARM` => `ROLLBACK`
- release 5xx `ALARM` => `ROLLBACK`
- release latency `ALARM` => `HOLD`
- otherwise => `GO`

---

## Script: One Command Release Check

Script location:

- `lessons/58-release-automation-runbook-standardization/scripts/release-check.sh`

What it does:

1. reads Terraform outputs (`ASG`, `TG`, `ALB`, `PROJECT`)
2. runs load (baseline/canary duration)
3. snapshots alarms/refresh/target health/scaling activities
4. samples build identity from response body
5. evaluates gates and prints decision
6. writes a timestamped artifact folder

### Usage

```bash
chmod +x lessons/58-release-automation-runbook-standardization/scripts/release-check.sh

# from terraform env dir:
cd lessons/57-deployment-quality-gates/lab_57/terraform/envs

# baseline run (3 minutes) - only if this shell can reach internal ALB directly
../../../../58-release-automation-runbook-standardization/scripts/release-check.sh \
  --mode baseline \
  --out-root /tmp

# canary run (5 minutes) - only if this shell can reach internal ALB directly
../../../../58-release-automation-runbook-standardization/scripts/release-check.sh \
  --mode canary \
  --require-checkpoint \
  --out-root /tmp
```

Recommended for internal ALB: run through local SSM port-forward (2 terminals).

Terminal 1 (keep session open):

```bash
cd lessons/57-deployment-quality-gates/lab_57/terraform/envs
export PROXY_ID="$(terraform output -raw ssm_proxy_instance_id)"
export ALB_DNS="$(terraform output -raw alb_dns_name)"

aws ssm start-session \
  --target "$PROXY_ID" \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters "{\"host\":[\"$ALB_DNS\"],\"portNumber\":[\"80\"],\"localPortNumber\":[\"18080\"]}"
```

Terminal 2:

```bash
cd lessons/57-deployment-quality-gates/lab_57/terraform/envs

# baseline (3 minutes)
../../../../58-release-automation-runbook-standardization/scripts/release-check.sh \
  --mode baseline \
  --alb-url http://127.0.0.1:18080/ \
  --out-root /tmp

# canary (5 minutes, checkpoint-safe)
../../../../58-release-automation-runbook-standardization/scripts/release-check.sh \
  --mode canary \
  --require-checkpoint \
  --alb-url http://127.0.0.1:18080/ \
  --out-root /tmp
```

---

## Output Contract

Each run creates one folder:

`/tmp/l58-<mode>-YYYYmmdd_HHMMSS/`

With files:

- `alarms.json`
- `target-health.json`
- `instance-refreshes.json`
- `scaling-activities.json`
- `build-sampler.txt`
- `load.log`
- `load.summary.txt`
- `load.codes.txt`
- `decision.txt`
- `summary.json`

This intentionally mirrors lesson_57 proof-pack style (same signal family, same evidence logic).

---

## Incident/Release Note Template

Template path:

- `lessons/58-release-automation-runbook-standardization/templates/incident-note.template.md`

How to use:

```bash
cp lessons/58-release-automation-runbook-standardization/templates/incident-note.template.md \
   /tmp/l58-incident-note.md
```

Fill it after each canary decision, using values from `decision.txt` and `summary.json`.

---

## Runbook (Checkpoint)

1. Start instance refresh with checkpoint mode enabled in ASG preferences.
2. Verify you are at checkpoint:
   ```bash
   aws autoscaling describe-instance-refreshes \
     --auto-scaling-group-name "$ASG_NAME" \
     --max-records 1 \
     --query 'InstanceRefreshes[0].[Status,PercentageComplete,StatusReason]' \
     --output table
   ```
   Expect: `InProgress` and `PercentageComplete=50` (for `[50]` checkpoint mode).
3. At 50% checkpoint, run canary check script once (`--require-checkpoint` recommended).
4. Read `decision.txt`.
5. Action:
   - `GO` => continue rollout
   - `HOLD` => extend canary window, investigate
   - `ROLLBACK` => abort and roll back immediately
6. Attach artifact directory + incident note.

---

## Drills

### Drill 1: Healthy candidate -> GO

- rollout good AMI
- run canary check at checkpoint
- expected: `DECISION=GO`

### Drill 2: Latency regression -> HOLD

1. Find one web instance in current ASG:
   ```bash
   WEB_ID="$(aws autoscaling describe-auto-scaling-groups \
     --auto-scaling-group-names "$ASG_NAME" \
     --query 'AutoScalingGroups[0].Instances[0].InstanceId' \
     --output text)"
   echo "$WEB_ID"
   ```
2. Open SSM session to that instance and verify `tc`:
   ```bash
   aws ssm start-session --target "$WEB_ID"
   command -v tc
   ```
3. Inject latency on the instance:
   ```bash
   sudo tc qdisc add dev eth0 root netem delay 700ms 100ms
   sudo tc qdisc show dev eth0
   ```
4. Run canary check from terminal with ALB access.
5. Expected: `DECISION=HOLD` and release latency alarm tends to `ALARM`.
6. Cleanup on the web instance:
   ```bash
   sudo tc qdisc del dev eth0 root
   sudo tc qdisc show dev eth0
   ```

### Drill 3: 5xx regression -> ROLLBACK

- deploy bad AMI returning 5xx
- run canary check
- expected: `DECISION=ROLLBACK`

---

## Pitfalls

- running against wrong ALB endpoint
- mixing baseline and canary with different load shape
- making decision without artifact folder
- changing alarm names without updating automation

---

## Final Acceptance

- [ ] one command produces decision + evidence pack
- [ ] decision logic matches alarm states
- [ ] incident note is filled from artifacts, not memory
- [ ] team can replay decision from files only

---

## Lesson Summary

Lesson_58 is not a new deployment model.  
It is operational standardization of lessons_55-57:

- same guardrails
- same gates
- less manual variance
- stronger release auditability
