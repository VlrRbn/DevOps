# lesson_62

---

# Terraform Quality Gates & Policy Baseline (`fmt`, `validate`, `tflint`, `checkov`)

**Date:** 2026-03-24

**Focus:** after lessons 60-61 you have remote state and safe refactors. The next is automatic quality gates that block footguns before apply.

**Mindset:** a good Terraform workflow should fail early. Not at `apply`, not after an incident, but at `fmt`, `validate`, `tflint`, `checkov`, and CI gate level.

---

## Why This Lesson Exists

After lesson 61, you already know how to work safely with state.
Even with good state and a clean refactor, you can still commit bad infrastructure code:

- overly open ingress
- IMDSv2 removed
- backend protections weakened
- tags forgotten
- insecure defaults pushed into PRs

This lesson is not about heavy enterprise policy-as-code. It is about a practical baseline:

- formatting
- validation
- linting
- security/misconfig scanning
- CI that blocks bad changes before they reach apply

---

## Outcomes

- understand the role of `fmt`, `validate`, `tflint`, and `checkov`
- run local quality gates before commit
- define a CI gate for Terraform paths
- build at least 3 reproducible footgun drills
- prove that bad changes are blocked before apply

---

## Quick Path

1. Build a local baseline with `terraform fmt -check` and `terraform validate`.
2. Add a `tflint` config for `lab_62/terraform`.
3. Add a `checkov` config for Terraform scan.
4. Prepare an example CI workflow.
5. Make 3 deliberate bad changes.
6. Prove that the gates catch them.
7. Save proof artifacts.

---

## Prerequisites

- lesson 60 completed
- lesson 61 completed
- `lab_62/terraform/envs` already exists and initializes
- AWS CLI + Terraform configured
- willingness to run the same checks repeatedly while drilling

---

## Repo Layout

```text
lessons/62-terraform-quality-gates/
├── lesson.en.md
├── lesson.ru.md
├── README.md
├── proof-pack.en.md
├── proof-pack.ru.md
├── checkov.yaml
├── ci/
│   └── terraform-quality-gates.yml
└── lab_62/
    ├── packer/
    └── terraform/
        ├── .tflint.hcl
        ├── backend-bootstrap/
        ├── envs/
        └── modules/network/
```

---

## What Each Tool Catches

### `terraform fmt -check`

Catches:

- unformatted HCL
- noisy diffs caused by style drift

Does not catch:

- logic errors
- security issues

### `terraform validate`

Catches:

- syntax problems
- invalid references
- part of provider schema misuse

Does not catch:

- insecure patterns
- weak architecture choices

### `tflint`

Catches:

- Terraform/AWS lint problems
- deprecated or weak argument usage
- part of your quality baseline if rules are configured

### `checkov`

Catches:

- security/misconfig patterns
- missing IMDSv2 hardening
- risky security group patterns
- weakened storage protections

Practical rule:

- `fmt` and `validate` are hygiene baseline
- `tflint` is Terraform/AWS lint layer
- `checkov` is security and misconfig layer

---

## Local Quality Gate Baseline

Working directory:

```bash
cd lessons/62-terraform-quality-gates/lab_62/terraform
```

Baseline run:

```bash
terraform fmt -recursive
terraform fmt -check -recursive
terraform -chdir=envs init -backend=false
terraform -chdir=envs validate

tflint --chdir=envs --init
tflint --chdir=envs -f compact

checkov -d . --framework terraform --config-file ../../checkov.yaml
```

---

## TFLint Baseline

Use `lab_62/terraform/.tflint.hcl`.

It should cover at least:

- AWS ruleset
- Terraform recommended preset
- compact output

It is a strong early-warning layer.

---

## Checkov Baseline

Use `checkov.yaml` in the lesson root.

The idea here is:

- do not try to model the entire universe
- focus on misconfigs that matter for this lab
- keep exceptions explicit if you really need them

For this lesson track, the most important checks are:

- EC2 metadata hardening
- security groups
- backend bucket protections

That is why `checkov.yaml` in this lesson should stay **curated**, not “scan every at once”.

---

## CI Shape

The repo already has an older Terraform CI workflow for a different path.

For lesson 62, do not break or overwrite it.
Keep an example next to the lesson:

- `ci/terraform-quality-gates.yml`

Then promote it into `.github/workflows/` intentionally.

That keeps the learning path separate from accidental repo-wide CI changes.

Quick local YAML sanity check

```hcl
python3 - <<'PY'
import yaml, pathlib
p = pathlib.Path("lessons/62-terraform-quality-gates/ci/terraform-quality-gates.yml")
print(yaml.safe_load(p.read_text())["name"])
PY
```

---

## Footgun Drills (Mandatory)

### Drill 1: Public ingress footgun

Make a deliberate bad change:

- add ingress `0.0.0.0/0` on `22`, `80`, or `443` where it should not exist

Expected result:

- `checkov` and/or another gate should fail

### Drill 2: IMDSv2 removed

Remove:

```hcl
metadata_options {
  http_tokens = "required"
}
```

from `aws_launch_template.web` or `aws_instance.ssm_proxy`.

Expected result:

- `checkov` should fail on missing IMDSv2 enforcement

### Drill 3: Backend bucket protection broken

```hcl
terraform -chdir=backend-bootstrap init -backend=false
terraform -chdir=backend-bootstrap validate
tflint --chdir=backend-bootstrap -f compact
checkov -d backend-bootstrap --framework terraform --config-file ../../checkov.yaml
```

In `backend-bootstrap/main.tf`, temporarily break one protection layer:

- versioning
- encryption
- public access block

Expected result:

- `checkov` should flag the misconfiguration

### Drill 4: Tags/consistency drift

Make a change that violates your tag or naming baseline.

Expected result:

- `tflint` and/or review baseline should show that naming/policy discipline drifted

---

## How To Run A Drill Properly

For each drill:

1. Save baseline output.
2. Introduce one bad change.
3. Run the gate again.
4. Save failing output.
5. Revert to good state.
6. Run the gate again and save clean output.

So the pattern is not only “break and fix”, but:

- baseline
- fail
- fix
- clean

---

## Common Pitfalls

- do not jump straight into full OPA/Sentinel platform work
- do not scan the entire repo with one giant unscoped checkov command
- do not rely only on CI if the same problem can be caught locally in 10 seconds
- do not build allowlists without explaining why the exception is acceptable

---

## What We Intentionally Do Not Fix In This Lesson

In lesson 62 we intentionally do **not** close the entire default Checkov output.

Out of scope here:

- ALB access logging
- ALB HTTPS/TLS-only listener model
- target group HTTP -> HTTPS redesign
- S3 KMS-by-default instead of AES256
- S3 replication
- S3 access logging
- S3 lifecycle and event notifications
- VPC flow logs
- full SG egress-model redesign

Why:

- that is no longer a “quality gates baseline”
- it pulls in extra buckets, policies, certificates, logging resources, and new architecture choices

Inside this lesson line we only fix the cheap and meaningful items:

- IMDSv2 hardening
- EC2 monitoring / root volume encryption for the proxy instance
- ALB deletion protection and invalid header handling
- default security group lockdown
- curated Checkov scope aligned with the lesson goals

---

## Proof Pack (Must-Have Evidence)

Minimum:

- baseline run output
- failing output for each drill
- fixed output after return to good state
- short notes or decision file:
  - what you broke
  - which tool caught it
  - why it matters

See `proof-pack.en.md` for the collection pattern.

---

## Final Acceptance

Lesson 62 is complete if:

- [ ] you can explain the role of `fmt`, `validate`, `tflint`, and `checkov`
- [ ] local baseline gate works
- [ ] you have an example CI workflow for Terraform quality gates
- [ ] at least 3 footgun drills are really blocked by the gates
- [ ] each drill has proof artifacts

---

## Lesson Summary

- **What you learned:** how to build Terraform quality gates before apply.
- **What you practiced:** `terraform fmt`, `terraform validate`, `tflint`, `checkov`, and deliberate bad-change drills.
- **Operational focus:** fail early instead of failing late; catch bad infrastructure code before `plan/apply`.
- **Why it matters:** remote state and safe refactors do not help if weak code enters the repo.
