# lesson_61

---

# State Hygiene & Safe Refactors (`moved`, `state mv`, `state rm`, `import`)

**Date:** 2026-03-22

**Focus:** learn how to change Terraform structure without accidental destroy, hidden drift, or state confusion.

**Mindset:** lesson 60 made state shared and durable; lesson 61 teaches how not to damage it.

---

## Why This Lesson Exists

Once state becomes remote and long-lived, refactoring Terraform stops being a code-only task.

You are no longer changing just filenames or resource labels. You are changing the contract between:

- resource addresses in code;
- real object IDs in AWS;
- Terraform state as the source of truth.

That is why refactors can become dangerous:

- rename looks like destroy + create;
- split into modules looks like destroy + create;
- importing late can hide drift;
- removing from state can hand ownership away.

This lesson is about controlled state surgery.

In this lesson, treat Terraform state as a mapping between:

- the resource address in Terraform code
- the real AWS object
- the state entry that binds them together

Example:

- in code you have `module.network.aws_cloudwatch_metric_alarm.release_target_5xx`
- in AWS the alarm really exists
- in state Terraform stores: "this address maps to this real object"

---

## Outcomes

- understand when to use `moved` blocks versus `terraform state mv`
- rename or relocate a resource address without recreating the AWS object
- stop managing a resource intentionally with `terraform state rm`
- import an existing AWS resource into Terraform state and reconcile drift
- build a repeatable surgery workflow with snapshots, lock discipline, and proof artifacts

---

## Quick Path

1. Start from a clean remote-backed env (`terraform plan` -> `No changes`).
2. Snapshot current state with `terraform state pull`.
3. Do one declarative rename using a `moved` block.
4. Do one imperative address move with `terraform state mv`.
5. Do one detach exercise with `terraform state rm`.
6. Import one existing CloudWatch alarm or security group.
7. Capture before/after state list + plan proof.

---

## Prerequisites

- lesson 60 completed
- remote backend + locking already active
- one real Terraform env exists and is reachable, for example:
  - `lessons/61-state-hygiene-and-refactors/lab_61/terraform/envs`
- AWS CLI + Terraform configured
- you accept one rule: no state surgery on top of an already dirty plan

---

## Repo Layout

Recommended working area for this lesson:

```text
lessons/61-state-hygiene-and-refactors/
├── lesson.en.md
├── lesson.ru.md
├── proof-pack.en.md
├── proof-pack.ru.md
├── README.md
└── lab_61/
    ├── packer/
    └── terraform/
        ├── backend-bootstrap/
        ├── envs/
        └── modules/network/
```

Use `lab_61/terraform/envs` as the real env root.

The module already contains stable resources suitable for exercises, for example:

- `module.network.aws_cloudwatch_metric_alarm.release_target_5xx`
- `module.network.aws_cloudwatch_metric_alarm.release_latency`
- `module.network.aws_cloudwatch_metric_alarm.alb_unhealthy`
- `module.network.aws_security_group.web`
- `module.network.aws_lb_target_group.web`

---

## The Refactor Hierarchy

Preferred order:

1. `moved` block
   - best for normal in-repo refactors inside the same state
   - codified in Git
   - reproducible for teammates and CI
2. `terraform state mv`
   - good for one-off address moves and surgery after code already changed
   - imperative and not self-documenting by itself
3. `removed` block or `terraform state rm`
   - use when Terraform must stop owning an object
4. `terraform import`
   - use when reality exists first and state must catch up

Practical rule:

- if the refactor can be expressed declaratively, prefer `moved`
- if you are repairing state interactively, use `terraform state mv`

---

## Safety Rails (Non-Negotiable)

Before any surgery:

1. `terraform plan` must be clean.
2. Locking must remain enabled.
3. Snapshot current state.
4. Change one address at a time.
5. Save proof before and after.

Standard baseline commands:

```bash
cd lessons/61-state-hygiene-and-refactors/lab_61/terraform/envs

terraform plan
terraform state list | sort > /tmp/l61-state-before.txt
terraform state pull > /tmp/l61-state-before.json
```

Do not use:

```bash
-lock=false
```

Do not start with import/move/rm while unrelated diffs already exist.

---

## Surgery Mode Runbook

Use this sequence every time:

1. Confirm plan is clean.
2. Snapshot state and current address list.
3. Make the smallest possible code change.
4. Run `terraform plan` and read what Terraform thinks will happen.
5. If the plan shows unwanted destroy/create, correct the address mapping with `moved` or `state mv`.
6. Re-run plan until the result is either:
   - `No changes`, or
   - one intentional understood diff.
7. Save proof artifacts.
8. Only then apply if it requires apply.

This runbook matters more than the individual command names.

---

## Exercise 1: Declarative Rename With `moved`

### Goal

Teach Terraform that an address changed, but the real object did not.

Rename:

- `module.network.aws_cloudwatch_metric_alarm.release_target_5xx`

to:

- `module.network.aws_cloudwatch_metric_alarm.release_5xx_gate`

### Why this is a good first exercise

- same module
- same state
- same resource type
- easy to reason about
- no real infrastructure replacement should happen

### Workflow

1. Rename the resource block in `modules/network/monitoring.tf`.
2. Add a `moved` block, for example in `modules/network/refactors.tf`:

```hcl
moved {
  from = aws_cloudwatch_metric_alarm.release_target_5xx
  to   = aws_cloudwatch_metric_alarm.release_5xx_gate
}
```

3. Run:

```bash
terraform plan
```

### Expected result

- not destroy/create
- ideally `0 to add, 0 to change, 0 to destroy`
- state address changes, AWS alarm stays the same

### Acceptance

- [ ] plan is clean after the rename
- [ ] alarm name in AWS did not change unless intentionally changed in code
- [ ] you can explain why `moved` is better than `state mv` here

---

## Exercise 2: Imperative Address Surgery With `terraform state mv`

### Goal

Perform a one-off state address move when you need direct control.

Rename one more alarm, but this time via CLI:

- from `module.network.aws_cloudwatch_metric_alarm.release_latency`
- to `module.network.aws_cloudwatch_metric_alarm.latency_gate`

### Workflow

1. Change the resource label in code first.
2. Run `terraform plan`.

Terraform will propose create + destroy. That is the signal that address mapping is broken.

3. Move state explicitly:

```bash
terraform state mv \
  'module.network.aws_cloudwatch_metric_alarm.release_latency' \
  'module.network.aws_cloudwatch_metric_alarm.latency_gate'
```

4. Run `terraform plan` again.

### Expected result

- first plan shows unwanted create/destroy
- after `state mv`, plan returns to clean

At this stage, **`apply` is not needed**.

Why:

- `terraform state mv` updates the state immediately
- the next `plan` is the verification step
- if the plan is clean, the repair succeeded

### When this is the right tool

- you already changed code and want to repair state immediately
- you need a one-time move that you do not want to encode permanently
- you are doing controlled operator-led surgery

### Acceptance

- [ ] first plan exposed the wrong create/destroy interpretation
- [ ] `state mv` fixed the address mapping
- [ ] second plan is clean

---

## Exercise 3: Detach Ownership With `terraform state rm`

### Goal

Stop Terraform from managing a resource without deleting the real AWS object.

### Important distinction

`state rm` does **not** destroy the resource.
It only removes the object from Terraform state.
"Exists in the cloud" and "is managed by Terraform" are not the same thing.

### Safe lesson pattern

Use a temporary resource, for example a dedicated CloudWatch alarm.

Avoid using backend resources or core networking components.

### Workflow

1. Pick a disposable lesson resource.
2. Remove it from state:

```bash
terraform state rm module.network.aws_cloudwatch_metric_alarm.latency_gate
```

3. Verify in AWS that the real object still exists.
4. Run `terraform plan`.

### Expected result

Terraform will now want to create that resource again if the block still exists in code.

That is correct.

It proves the difference between:

- actual AWS object
- Terraform state ownership
- desired configuration in code

### Acceptance

- [ ] AWS object still exists after `state rm`
- [ ] Terraform no longer tracks it
- [ ] you can explain why code must be removed or gated too if you do not want recreation

---

## Exercise 4: Import Reality Into State

### Goal

Bring an existing AWS object under Terraform management.

### Good import candidates

- CloudWatch alarm
- security group
- target group

For this lesson, a CloudWatch alarm is the easiest because the address and drift story are easy to read.

### Workflow

1. Create or keep one existing object outside Terraform.
2. Add the matching resource block to code.
3. Import it:

```bash
terraform import \
  'module.network.aws_cloudwatch_metric_alarm.latency_gate' \
  'lab61-release-latency'
```

Use the correct import ID format for the chosen AWS resource type.

Terraform CLI syntax here is `terraform import ADDRESS ID`, and import is done one resource at a time. For `aws_cloudwatch_metric_alarm`, the import ID is the alarm name.


4. Run `terraform plan`.

### Expected result

One of two outcomes is acceptable:

- plan is clean, meaning config matches reality
- plan shows drift, and you then reconcile config until it is understood

### Acceptance

- [ ] import succeeds
- [ ] post-import plan is clean or fully explained
- [ ] drift resolution is documented in proof artifacts

---

## Drill Pack (Mandatory)

### Drill 1: `moved` block rename

- rename one real alarm address with `moved`
- prove no recreation

### Drill 2: `state mv` repair

- rename another real address
- intentionally observe the wrong destroy/create plan first
- repair with `terraform state mv`
- prove clean plan

### Drill 3: `state rm` detach

- detach one disposable object
- prove it still exists in AWS
- prove Terraform would recreate it if the block remains

### Drill 4: import

- import one existing object
- prove post-import plan is understood

### Drill 5: full surgery note

Write a short runbook note for one drill:

- what changed
- why it was safe
- what could have gone wrong
- what evidence proves success

---

## Proof Pack (Must-Have Evidence)

Minimum artifact set for each surgery:

- `terraform state list` before
- `terraform state pull` snapshot before
- first plan showing wrong interpretation, if applicable
- command used (`moved`, `state mv`, `state rm`, or `import`)
- second plan showing the desired result
- short explanation of risk and outcome

Store artifacts per drill, for example:

```text
/tmp/l61-proof-YYYYmmdd_HHMMSS/
  moved-plan-before.txt
  moved-plan-after.txt
  state-list-before.txt
  state-list-after.txt
  state-before.json
  decision.txt
```

See `proof-pack.en.md` for a ready-to-run collection pattern.

Raw proof folders usually stay local.
If you want to commit evidence, redact sensitive values first and commit only a public-safe subset.

---

## Common Pitfalls

- doing surgery on top of unrelated pending changes
- forgetting that resource address and AWS object ID are different things
- running `state rm` and then recreation on next plan
- importing into the wrong address
- treating imperative state commands as self-documenting history
- trying to refactor backend resources instead of regular stack resources

---

## Final Acceptance

You can consider lesson 61 complete when all of these are true:

- [ ] you can explain the difference between `moved` and `terraform state mv`
- [ ] you completed at least one no-recreation rename
- [ ] you completed one `state rm` detach and explained the recreation risk
- [ ] you completed one import and reconciled drift
- [ ] every drill has proof artifacts
- [ ] you can describe a repeatable surgery-mode workflow without guessing

---

## Lesson Summary

- **What you learned:** state is not only storage; it is the address map between Terraform code and real infrastructure.
- **What you practiced:** `moved`, `terraform state mv`, `terraform state rm`, `terraform import`, and clean-plan surgery workflow.
- **Operational focus:** snapshot first, move one thing at a time, re-plan after every surgery, keep proof.
- **Why it matters:** remote state from lesson 60 is only useful if you can evolve code safely.
