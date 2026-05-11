# lesson_64

---

# Drift Detection & Change Awareness (Scheduled Plan, Evidence, Triage)

**Date:** 2026-05-10

**Focus:** detect infrastructure drift safely and explain **what changed, where, and what to do next**.

**Mindset:** if Terraform state and real infrastructure diverge, your next apply becomes a surprise.

---

## Why This Lesson Exists

After lesson 63, pull requests show what Terraform **would** do before merge.

That still leaves one dangerous gap:

- someone changes AWS manually
- an operator tests something and forgets to revert
- a console change bypasses Git
- a resource drifts from the declared configuration

That is **drift**.

If drift is not detected early:

- the next plan becomes confusing
- the next apply may revert or replace things unexpectedly
- operators lose trust in Terraform as the source of truth

This lesson builds a **scheduled drift detection workflow** that:

- runs automatically
- checks the current deployed environment against code in `main`
- stores proof artifacts
- produces a clear triage result:
    - **NO_DRIFT**
    - **DRIFT_DETECTED**
    - **PIPELINE_ERROR**

---

## Outcomes

- build a scheduled GitHub Actions workflow for Terraform drift detection
- reuse OIDC + remote backend from lesson 63
- use `terraform plan -detailed-exitcode` as the core signal
- separate drift from pipeline failure
- collect readable evidence artifacts
- define a triage workflow:
    - revert manual change
    - import/reconcile
    - intentionally accept and codify

---

## Quick Path

1. Reuse the CI auth/backend model from lesson 63.
2. Create a scheduled workflow that checks out `main`.
3. Run `fmt`, `validate`, then remote-backend `plan -detailed-exitcode`.
4. Save:
    - raw plan output
    - `terraform show` output
    - drift decision file
5. Make one deliberate manual drift in AWS.
6. Prove the workflow detects it.
7. Triage the drift and return to clean state.

---

## Prerequisites

- lesson 60 completed: remote state + locking
- lesson 61 completed: safe state refactors
- lesson 63 completed: PR plan pipeline with OIDC
- one stable env exists in AWS and is managed by Terraform
- can understand the difference between:
    - configuration change in Git
    - out-of-band change in AWS
    - state mapping issue

---

## Repo Layout

```
lessons/64-drift-detection-and-change-awareness/
├── lesson.en.md
├── lesson.ru.md
├── README.md
├── proof-pack.en.md
├── proof-pack.ru.md
├── ci/
│   └── terraform-drift.yml
└── lab_64/
    └── terraform/
        ├── envs/
        ├── modules/network/
        └── backend.hcl.example
```

---

## Target Flow

```
Scheduled GitHub Actions run
  |
  v
checkout main
  |
  +--> terraform fmt -check
  +--> terraform validate
  +--> terraform init (remote backend)
  +--> terraform plan -detailed-exitcode
             |
             +--> exit 0 => NO_DRIFT
             +--> exit 2 => DRIFT_DETECTED
             +--> exit 1 => PIPELINE_ERROR
  |
  v
artifact upload + decision file
```

Important rule:

- this workflow **detects**
- it does **not** auto-apply fixes

---

## A) What Counts As Drift

Drift means:

- real AWS object no longer matches Terraform configuration on `main`

Examples:

- someone edits a security group rule in the console
- a tag is changed manually
- `deletion_protection` on ALB is toggled outside Terraform
- a CloudWatch alarm threshold is edited manually

Not drift:

- an unmerged PR branch with intended Terraform changes
- a local uncommitted edit
- a pipeline formatting issue

Practical rule:

> Drift detection runs against deployed code on `main`, not against your feature branch.
> 

---

## B) Core Detection Signal — `terraform plan -detailed-exitcode`

This is the heart of the lesson.

Terraform returns:

- `0` → no diff
- `1` → error
- `2` → diff exists

For a scheduled workflow on `main`:

- `1` is not drift; it is a pipeline/backend/provider problem
- `2` is your drift signal

### Local dry run pattern

From your env root:

```bash
terraform init -reconfigure -backend-config=backend.hcl
terraform plan -detailed-exitcode -no-color -out=tfplan
echo $?
```

Interpretation:

- `0` → clean
- `1` → fix pipeline/tooling first
- `2` → drift or some config/reality mismatch that must be triaged

---

## C) Workflow (`ci/terraform-drift.yml`)

```yaml
name: terraform-drift

on:
  # Scheduled drift check against deployed reality and the main branch code.
  schedule:
    - cron: '0 6 * * *'
  # Manual run is useful while learning and during incident triage.
  workflow_dispatch: {}

permissions:
  # Required for GitHub OIDC -> AWS assume-role.
  id-token: write
  contents: read

concurrency:
  # Drift detection is global for this env; keep only one active run.
  group: terraform-drift-lab64-main
  cancel-in-progress: true

env:
  TF_ROOT: lessons/64-drift-detection-and-change-awareness/lab_64/terraform
  TF_IN_AUTOMATION: true
  TF_INPUT: false
  AWS_REGION: ${{ vars.AWS_REGION || 'eu-west-1' }}

jobs:
  drift-detection:
    runs-on: ubuntu-latest

    defaults:
      run:
        shell: bash
        working-directory: ${{ env.TF_ROOT }}

    steps:
      - name: Checkout main
        uses: actions/checkout@v4
        with:
          ref: main

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: '1.14.0'
          terraform_wrapper: false

      - name: Configure AWS credentials via OIDC
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-region: ${{ env.AWS_REGION }}
          role-to-assume: ${{ vars.TF_PLAN_ROLE_ARN }}
          role-session-name: gha-terraform-drift

      - name: Terraform fmt
        run: terraform fmt -check -recursive

      - name: Terraform init (no backend)
        run: terraform -chdir=envs init -backend=false -input=false -no-color

      - name: Terraform validate
        run: terraform -chdir=envs validate -no-color

      - name: Write backend.hcl
        working-directory: ${{ env.TF_ROOT }}/envs
        run: |
          # CI writes backend config from repo variables and never migrates state.
          cat > backend.hcl <<EOF2
          bucket       = "${{ vars.TF_STATE_BUCKET }}"
          key          = "lab64/dev/full/terraform.tfstate"
          region       = "${{ env.AWS_REGION }}"
          encrypt      = true
          use_lockfile = true
          EOF2

      - name: Terraform init (remote backend)
        run: terraform -chdir=envs init -reconfigure -backend-config=backend.hcl -input=false -no-color

      - name: Terraform plan (detect drift)
        id: drift_plan
        working-directory: ${{ env.TF_ROOT }}/envs
        run: |
          set +e
          terraform plan -detailed-exitcode -input=false -no-color -out=tfplan > plan.txt 2>&1
          ec=$?
          echo "exitcode=$ec" >> "$GITHUB_OUTPUT"

          if [ "$ec" -eq 0 ]; then
            echo "NO_DRIFT" > decision.txt
          elif [ "$ec" -eq 2 ]; then
            echo "DRIFT_DETECTED" > decision.txt
          else
            echo "PIPELINE_ERROR" > decision.txt
          fi

          exit 0

      - name: Terraform show
        working-directory: ${{ env.TF_ROOT }}/envs
        run: |
          if [ -f tfplan ]; then
            terraform show -no-color tfplan > tfplan.txt
          else
            : > tfplan.txt
          fi

      - name: Upload drift artifacts
        uses: actions/upload-artifact@v4
        with:
          name: terraform-drift
          path: |
            ${{ env.TF_ROOT }}/envs/plan.txt
            ${{ env.TF_ROOT }}/envs/tfplan.txt
            ${{ env.TF_ROOT }}/envs/decision.txt

      - name: Job summary
        working-directory: ${{ env.TF_ROOT }}/envs
        run: |
          {
            echo "## Terraform Drift Detection"
            echo
            echo "- decision: $(cat decision.txt)"
            echo "- artifact: terraform-drift"
          } >> "$GITHUB_STEP_SUMMARY"

      - name: Fail on drift
        if: steps.drift_plan.outputs.exitcode == '2'
        run: |
          echo "Drift detected. See terraform-drift artifact."
          exit 2

      - name: Fail on pipeline error
        if: steps.drift_plan.outputs.exitcode == '1'
        run: |
          echo "Pipeline error during drift check."
          exit 1
```

Copy it to:

- `.github/workflows/terraform-drift.yml`

The workflow:

- checks out `main`
- assumes the AWS role through OIDC
- runs `fmt`
- runs `validate`
- initializes the remote backend
- runs `terraform plan -detailed-exitcode`
- stores `decision.txt`, `plan.txt`, and `tfplan.txt`
- fails on `DRIFT_DETECTED` and `PIPELINE_ERROR`

It does not run `apply`.

---

## D) Decision Model — What To Do When Drift Appears

Not every drift means “apply immediately”.

Triage options are:

### 1. Revert the manual change

Use when:

- the console/API change was accidental
- Terraform config is still the intended truth

### 2. Accept the change and codify it

Use when:

- the manual change was correct
- Terraform code is now stale

In that case:

- update code
- open PR
- review plan
- merge

### 3. Import/reconcile

Use when:

- object was created or changed outside Terraform enough that mapping/config must be repaired
- lessons 61 “state surgery” is needed

### 4. Investigate first

Use when:

- you don’t understand the diff
- plan output is not enough
- the change might be provider/schema/state related

---

## E) Triage Runbook

When drift workflow fails with `DRIFT_DETECTED`:

1. Download artifact
2. Read:
    - `decision.txt`
    - `plan.txt`
    - `tfplan.txt`
3. Answer:
    - what changed?
    - is it manual drift, intended change, or state issue?
4. Decide:
    - revert in AWS
    - update Terraform code
    - use import/state surgery
5. Re-run drift workflow until it returns `NO_DRIFT`

---

## F) Drift Drill Ideas (Mandatory)

### Drill 1 — Manual managed-tag drift

Change an existing Terraform-managed tag manually in AWS.

Do not add an arbitrary extra tag to an ASG-created web instance. The individual web instances are created by the Auto Scaling Group and are not directly tracked as separate Terraform resources in this lab.

Use the SSM proxy instance instead:

```bash
SSM_PROXY_ID="$(terraform output -raw ssm_proxy_instance_id)"

aws ec2 create-tags \
  --resources "$SSM_PROXY_ID" \
  --tags Key=Role,Value=manual-change
```

Expected:

- scheduled/manual drift workflow returns `DRIFT_DETECTED`
- the plan shows Terraform wants to restore `Role = "ssm-proxy"`

Why this is good:

- low blast radius
- easy to explain in plan output

---

### Drill 2 — Managed security group rule drift

Remove an existing Terraform-managed SG rule manually in AWS.

Do not use an arbitrary extra SG rule for this drill. In this lab, ingress rules are modeled as separate `aws_security_group_rule` resources, so deleting a managed rule gives a clearer drift signal.

Remove the rule that allows the SSM proxy to reach the internal ALB:

```bash
ALB_SG_ID="$(terraform output -json security_groups | jq -r '.alb_sg')"
SSM_PROXY_SG_ID="$(terraform output -json security_groups | jq -r '.ssm_proxy_sg')"

aws ec2 revoke-security-group-ingress \
  --group-id "$ALB_SG_ID" \
  --ip-permissions "IpProtocol=tcp,FromPort=80,ToPort=80,UserIdGroupPairs=[{GroupId=$SSM_PROXY_SG_ID}]"
```

Expected:

- drift workflow fails
- plan shows Terraform wants to recreate `aws_security_group_rule.alb_http_from_ssm_proxy`

Why this matters:

- this is a production footgun
- a missing rule can break private access paths

### Drill 3 — ALB setting drift

Manually toggle a Terraform-managed ALB attribute.

Use `drop_invalid_header_fields`. It is safer for a drill than touching deletion protection.

```bash
ALB_ARN="$(terraform output -raw alb_arn)"

aws elbv2 modify-load-balancer-attributes \
  --load-balancer-arn "$ALB_ARN" \
  --attributes Key=routing.http.drop_invalid_header_fields.enabled,Value=false
```

Verify the manual change:

```bash
aws elbv2 describe-load-balancer-attributes \
  --load-balancer-arn "$ALB_ARN" \
  --query 'Attributes[?Key==`routing.http.drop_invalid_header_fields.enabled`]' \
  --output table
```

Expected:

- drift workflow detects it
- plan shows Terraform wants to restore `drop_invalid_header_fields = true`
- you classify whether to revert or codify

---

## G) How To Run a Drill Properly

Pattern:

1. Baseline:
    - run drift workflow
    - prove `NO_DRIFT`
2. Introduce one manual AWS change
3. Run drift workflow again
4. Capture:
    - failing run
    - artifact
    - triage note
5. Revert or codify change
6. Run workflow again
7. Prove return to `NO_DRIFT`

For Drill 1, revert the manual tag with:

```bash
SSM_PROXY_ID="$(terraform output -raw ssm_proxy_instance_id)"

aws ec2 create-tags \
  --resources "$SSM_PROXY_ID" \
  --tags Key=Role,Value=ssm-proxy
```

For Drill 2, return to clean state by letting Terraform recreate the missing rule:

```bash
terraform apply
```

For Drill 3, return to clean state the same way:

```bash
terraform apply
```

This is the same muscle pattern you already built:

- baseline
- fail
- fix
- clean

---

## H) Evidence Pack (Must-Have)

For each drill, save:

- workflow run result
- `decision.txt`
- `plan.txt`
- `tfplan.txt`
- short note:
    - what drift was introduced
    - how it appeared in plan
    - what triage choice you made
    - how you returned to clean state

---

## Common Pitfalls

- running drift detection on a feature branch
- treating exit code `1` as drift
- auto-applying drift fixes from CI
- detecting drift but not recording the triage decision
- leaving manual AWS changes in place

---

## Security Checklist

- OIDC only, no static AWS keys
- remote backend used consistently
- drift workflow has no `apply`
- artifacts are treated as operational data
- CI role is least privilege for plan/refresh/backend access

---

## Final Acceptance

Lesson 64 is complete if:

- [ ]  scheduled/manual workflow detects drift using `detailed-exitcode`
- [ ]  `NO_DRIFT`, `DRIFT_DETECTED`, and `PIPELINE_ERROR` are clearly separated
- [ ]  at least 2 real drift drills were completed
- [ ]  each drift has proof artifacts and a triage decision
- [ ]  clean state is restored after drills

---

## Lesson Summary

- **What you learned:** how to detect and triage infrastructure drift safely
- **What you practiced:** scheduled plan workflow, detailed exit code interpretation, evidence collection, triage discipline
- **Operational focus:** detect reality/code divergence early, before the next apply surprises you
- **Why it matters:** drift today becomes a dangerous plan tomorrow
