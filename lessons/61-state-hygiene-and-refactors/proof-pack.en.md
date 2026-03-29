# Proof Pack For Lesson 61

## What It Is

The proof pack for lesson 61 is the minimum artifact set that proves you did state surgery safely.

It should show:

- clean baseline before refactor
- exact command or declarative mapping used
- before/after state evidence
- before/after plan evidence
- final operator decision

Raw proof folders are usually local-only.
If you want them in Git, redact sensitive values first and commit only a public-safe subset.

## Why It Matters

1. State refactors are easy to misremember.
2. Address moves are invisible later unless you save proof.
3. Proof habits matter more once remote state is shared and long-lived.

## When To Collect

Collect one proof folder per drill.

Recommended drills:

1. `moved` block rename
2. `terraform state mv`
3. `terraform state rm`
4. `terraform import`

## Standard Collection Layout

```text
/tmp/l61-proof-YYYYmmdd_HHMMSS/
  state-list-before.txt
  state-list-after.txt
  state-before.json
  state-after.json
  plan-before.txt
  plan-after.txt
  command.txt
  notes.txt
  decision.txt
```

## Standard Collection (ready-to-run commands)

Run from:

`lessons/61-state-hygiene-and-refactors/lab_61/terraform/envs`

```bash
STAMP="$(date +%Y%m%d_%H%M%S)"
OUT="/tmp/l61-proof-$STAMP"
mkdir -p "$OUT"

terraform state list | sort > "$OUT/state-list-before.txt"
terraform state pull > "$OUT/state-before.json"
terraform plan -no-color > "$OUT/plan-before.txt"
```

After your refactor command or import:

```bash
terraform state list | sort > "$OUT/state-list-after.txt"
terraform state pull > "$OUT/state-after.json"
terraform plan -no-color > "$OUT/plan-after.txt"
```

Record the surgery command or declarative action:

```bash
cat > "$OUT/command.txt" <<'CMD'
# Example: imperative move
terraform state mv \
  'module.network.aws_cloudwatch_metric_alarm.release_latency' \
  'module.network.aws_cloudwatch_metric_alarm.latency_gate'
CMD
```

Add operator notes:

```bash
cat > "$OUT/notes.txt" <<'EOF2'
what=renamed release_latency to latency_gate
why=align alarm labels with gate naming
risk=Terraform could misread it as destroy/create
proof=plan-before showed create/destroy, plan-after returned clean
EOF2
```

Decision file:

```bash
cat > "$OUT/decision.txt" <<EOF3
decision=STATE_SURGERY_OK
timestamp=$(date -Is)
operator=$(whoami)
env=prod
workspace=default

Drill:
Change:
Command:
Why it was safe:
Pre-check:
Post-check:
Risks:
Rollback:
EOF3
```

## What Good Evidence Looks Like

### `moved`

- `plan-before.txt` should already be clean after `moved` is added correctly
- `state-list-after.txt` should show the new address

### `terraform state mv`

- `plan-before.txt` should show wrong create/destroy after the label rename
- `plan-after.txt` should return to clean after `state mv`

### `terraform state rm`

- `state-list-after.txt` should no longer include the resource
- `plan-after.txt` should show recreation if the block is still present in code

### `terraform import`

- `state-list-after.txt` should include the imported address
- `plan-after.txt` should be clean or fully understood

## Archive For Storage/Handoff

```bash
tar -C /tmp -czf "/tmp/$(basename "$OUT").tar.gz" "$(basename "$OUT")"
echo "saved: /tmp/$(basename "$OUT").tar.gz"
```

## Quick Check

- Is the baseline plan clean?
- Do before/after state lists prove the address change?
- Does the plan evidence show why the surgery was needed?
- Is the final plan clean or explicitly understood?
- Is there a short operator note explaining the change and risk?
