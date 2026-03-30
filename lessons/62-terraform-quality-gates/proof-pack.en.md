# Proof Pack For Lesson 62

## What It Is

The proof pack for lesson 62 is the artifact set that proves your quality gates really catch bad Terraform changes before apply.

It should show:

- a clean baseline run
- a failing run after a deliberate bad change
- a clean run after the fix
- a short explanation of which tool caught what

## When To Collect

Collect one proof folder per drill or one shared folder with separate files per drill.

Minimum drills:

1. public ingress footgun
2. IMDSv2 removed
3. backend bucket protection broken

## Standard Collection Layout

```text
/tmp/l62-proof-YYYYmmdd_HHMMSS/
  baseline-fmt.txt
  baseline-validate.txt
  baseline-tflint.txt
  baseline-checkov.txt
  fail-public-sg.txt
  fail-imdsv2.txt
  fail-backend-bucket.txt
  fix-public-sg.txt
  fix-imdsv2.txt
  fix-backend-bucket.txt
  decision.txt
```

## Standard Collection (ready-to-run commands)

Run from:

`lessons/62-testing-and-policy/lab_62/terraform`

```bash
STAMP="$(date +%Y%m%d_%H%M%S)"
OUT="/tmp/l62-proof-$STAMP"
mkdir -p "$OUT"

terraform fmt -check -recursive > "$OUT/baseline-fmt.txt" 2>&1
terraform -chdir=envs init -backend=false > /dev/null 2>&1
terraform -chdir=envs validate -no-color > "$OUT/baseline-validate.txt" 2>&1

tflint --chdir=envs --init > /dev/null 2>&1
tflint --chdir=envs -f compact > "$OUT/baseline-tflint.txt" 2>&1

checkov -d . --framework terraform --config-file ../../checkov.yaml > "$OUT/baseline-checkov.txt" 2>&1
```

After each deliberate bad change:

```bash
checkov -d . --framework terraform --config-file ../../checkov.yaml > "$OUT/fail-example.txt" 2>&1
```

After returning to good state:

```bash
checkov -d . --framework terraform --config-file ../../checkov.yaml > "$OUT/fix-example.txt" 2>&1
```

Decision file:

```bash
cat > "$OUT/decision.txt" <<EOF2
decision=QUALITY_GATES_OK
timestamp=$(date -Is)
operator=$(whoami)
env=prod
workspace=default

Drill:
Bad change:
Expected catcher:
Why it matters:
State flow: baseline -> fail -> fix -> clean
EOF2
```

## What Good Evidence Looks Like

- baseline run is clean
- failing run really fails on the deliberate bad change
- fixed run is clean again
- it is clear which tool caught the problem

## Archive For Storage/Handoff

```bash
tar -C /tmp -czf "/tmp/$(basename "$OUT").tar.gz" "$(basename "$OUT")"
```

Raw proof folders usually stay local.
If you want them in Git, redact sensitive values first and commit only a public-safe subset.
