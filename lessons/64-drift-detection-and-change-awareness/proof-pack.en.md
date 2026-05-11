# Proof Pack For Lesson 64

## What It Is

The proof pack for lesson 64 proves that your drift workflow can separate clean state, real drift, and pipeline failure.

It should show:

- a `NO_DRIFT` baseline
- a deliberate `DRIFT_DETECTED` run
- readable plan evidence
- a triage decision
- a final return to `NO_DRIFT`

## Suggested Layout

```text
/tmp/l64-proof-YYYYmmdd_HHMMSS/
  baseline-decision.txt
  baseline-plan.txt
  drift-decision.txt
  drift-plan.txt
  drift-tfplan.txt
  fix-decision.txt
  fix-plan.txt
  triage-note.txt
```

## Local Collection Pattern

Run from:

`lessons/64-drift-detection-and-change-awareness/lab_64/terraform/envs`

```bash
STAMP="$(date +%Y%m%d_%H%M%S)"
OUT="/tmp/l64-proof-$STAMP"
mkdir -p "$OUT"

terraform init -reconfigure -backend-config=backend.hcl

set +e
terraform plan -detailed-exitcode -input=false -no-color -out=tfplan > "$OUT/baseline-plan.txt" 2>&1
ec=$?
set -e

if [ "$ec" -eq 0 ]; then
  echo "NO_DRIFT" > "$OUT/baseline-decision.txt"
elif [ "$ec" -eq 2 ]; then
  echo "DRIFT_DETECTED" > "$OUT/baseline-decision.txt"
else
  echo "PIPELINE_ERROR" > "$OUT/baseline-decision.txt"
fi

terraform show -no-color tfplan > "$OUT/baseline-tfplan.txt"
```

After introducing manual drift, repeat the same pattern and save files as `drift-*`.

After reverting or codifying the change, repeat again and save files as `fix-*`.

## Triage Note Template

```text
decision=DRIFT_TRIAGED
timestamp=<ISO8601>
operator=<your_name>
env=lab64

Drift introduced:
Workflow decision:
Plan evidence:
Triage choice:
Clean-state proof:
```

## Good Evidence

- baseline starts as `NO_DRIFT`
- manual change produces `DRIFT_DETECTED`
- plan output explains the diff
- triage note says revert/codify/import/investigate
- final run returns to `NO_DRIFT`
