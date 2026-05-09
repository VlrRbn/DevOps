# Proof Pack For Lesson 63

## What It Is

The proof pack for lesson 63 is the artifact set that proves your Terraform PR plan pipeline works in both success and failure paths.

It should show:

- a successful plan run
- at least one early failure before `plan`
- plan artifact upload evidence
- concurrency cancellation evidence
- a short operator decision note

## Minimum Evidence Set

Collect at least:

1. `success-plan-run.txt`
2. `fail-validate.txt`
3. `fail-policy.txt`
4. `artifact-list.txt`
5. `concurrency-cancel.txt`
6. `decision.txt`

## Standard Collection Layout

```text
/tmp/l63-proof-YYYYmmdd_HHMMSS/
  success-plan-run.txt
  fail-validate.txt
  fail-policy.txt
  artifact-list.txt
  concurrency-cancel.txt
  decision.txt
```

## What To Capture

### 1. Successful plan run

Save:

- workflow log excerpt
- job summary
- artifact upload confirmation

### 2. Failed validate run

Break HCL or a reference so the pipeline stops before `plan`.

Save:

- failed workflow log excerpt
- exact failing stage

### 3. Failed policy run

Reintroduce one lesson 62 footgun.

Save:

- failed `checkov` or `tflint` output
- stage name where it failed

### 4. Concurrency proof

Push two commits quickly to the same PR.

Save:

- the canceled run evidence
- the latest surviving run evidence

## Decision File Template

```text
decision=PR_PLAN_PIPELINE_OK
timestamp=<ISO8601>
operator=<your_name>
repo=<owner/repo>
pr=<number-or-link>

Success case:
Failure case:
Policy case:
Concurrency proof:
Why this matters before merge:
```

## What Good Evidence Looks Like

- the pipeline reaches `plan` on a healthy PR
- bad code fails before `plan`
- plan artifacts are uploaded and readable
- concurrency cancellation is visible
- the operator can explain the infrastructure impact
