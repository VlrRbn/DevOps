# Capstone: End-to-End Terraform Delivery Pipeline

**Date:** 2026-06-28

**Focus:** connect the previous Terraform delivery lessons into one controlled release process: local checks, module tests, plan artifacts, policy gates, cost gates, risk classification, approval, exact-plan apply, post-apply verification, runtime health evidence, and proof pack.

**Mindset:** this lesson is not a new feature. It proves that the whole delivery system works together.

---

## 1. Why This Lesson Exists

Previous lessons built the pieces separately:

```text
remote state -> module contracts -> native tests -> PR plan -> policy gates -> cost gates -> risk review -> controlled apply -> promotion -> drift checks -> incident runbooks
```

The capstone ties everything together into one operational question:

```text
Can I prove exactly what changed, why it was allowed, who reviewed it, what was applied, and whether the environment is clean afterwards?
```

A mature Terraform delivery process is evidence, approval, reproducibility, and recovery readiness.

---

## 2. Outcomes

After this lesson you should be able to:

- run safe local checks before opening a PR;
- explain the difference between PR preview plan and apply plan;
- validate module contracts and environment roots;
- generate `tfplan`, `tfplan.txt`, and `tfplan.json`;
- run security policy and cost/blast-radius policy;
- run the risk classifier and read `risk-decision.md`;
- require approval based on target environment and risk;
- apply the exact saved `tfplan`, not a different fresh plan;
- capture post-apply drift and runtime health evidence;

---

## 3. Connection To Previous Lessons

| Lesson | What it gave you | How lesson 76 uses it |
| --- | --- | --- |
| 60 | remote state and locking | separate backend keys and state safety |
| 61 | state hygiene and refactors | state-safe change discipline |
| 62 | Terraform quality gates | fmt/validate/tflint/checkov habits |
| 63 | CI plan pipeline | PR plan and artifact thinking |
| 64 | drift detection | post-apply and scheduled drift checks |
| 65 | secrets and safe inputs | no secrets in repo or plan artifacts without review |
| 66 | module contracts | module interface guarantees |
| 67 | native tests | `terraform test` before release/apply |
| 68 | controlled apply | exact saved plan before apply |
| 69 | least-privilege roles | separated plan/apply roles |
| 70 | JSON plan policy | security policy on `tfplan.json` |
| 71 | multi-env promotion | `dev -> stage -> prod` evidence |
| 72 | module release discipline | pinned module version and release note thinking |
| 73 | cost/blast-radius controls | cost policy and blast-radius warnings |
| 74 | incident runbooks | recovery procedure and runtime evidence |
| 75 | risk classification | final `LOW/MEDIUM/HIGH/EMERGENCY/BLOCKED` decision |

---

## 4. Repository Layout

```text
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/
├── README.md
├── lesson.en.md
├── lesson.ru.md
├── proof-pack.en.md
├── proof-pack.ru.md
├── ci/
│   ├── lesson76-pr-checks.yml
│   ├── lesson76-capstone-promote.yml
│   └── lesson76-drift-check.yml
├── scripts/
│   ├── run-local-checks.sh
│   ├── promotion-evidence-template.sh
│   ├── reviewer-note-template.sh
│   ├── write-terraform-env-files.sh
│   ├── runtime-health-check.sh
│   ├── state-snapshot.sh
│   ├── post-incident-check.sh
│   ├── collect-capstone-proof.sh
│   └── summarize-capstone.sh
├── policies/
│   ├── security-policy.sh
│   ├── cost-policy.sh
│   ├── risk-classifier.sh
│   └── tests/
├── runbooks/
└── lab_76/
    ├── packer/
    └── terraform/
        ├── backend-bootstrap/
        ├── envs/dev/
        ├── envs/stage/
        ├── envs/prod/
        └── modules/network/
```

`ci/` contains templates. Copy them into `.github/workflows/` only when you are ready to wire the lesson into GitHub Actions.

---

## 5. Final Delivery Model

```text
PR checks
  -> fmt / validate / module tests / policy tests
  -> optional PR plan preview

merge to main
  -> choose target environment
  -> verify promotion evidence
  -> create saved tfplan
  -> render tfplan.txt and tfplan.json
  -> run security policy
  -> run cost policy
  -> run risk classifier
  -> upload review artifacts
  -> wait for GitHub Environment approval
  -> apply exact tfplan
  -> post-apply plan -detailed-exitcode
  -> runtime health check
  -> proof pack
```

Important distinction:

```text
PR plan = preview for review.
Apply plan = fresh saved plan created from the protected branch and applied exactly.
```

Do not apply an old PR artifact blindly.

`tfplan.sha256` catches accidental file mismatch inside the review package. It is not a complete security boundary: if an attacker can replace the whole artifact, they can replace the checksum too. The real protection here is the protected branch, GitHub Environment approval, least-privilege roles, short retention, and artifact attestation if needed.

---

## 6. Acceptance Gates

| Gate                   | Required evidence                                             | Answers one question?                                                                            |
| ---------------------- | ------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| Local quality          | output from `scripts/run-local-checks.sh`                     | does the code look generally valid?                                                              |
| Module contract        | output from `terraform test`                                  | did the module break its interface?                                                              |
| Environment validation | `terraform validate` for `dev`, `stage`, `prod`               | is the root env valid for dev/stage/prod?                                                        |
| Backend isolation      | `backend.hcl` uses the correct state key                      | is the state key correct, and are environments not overwriting each other?                       |
| Plan artifact          | `tfplan`, `tfplan.txt`, `tfplan.json`                         | is there an exact `tfplan`, a human-readable `tfplan.txt`, and a machine-readable `tfplan.json`? |
| Security policy        | `policy-decision.txt`, `policy-deny.json`, `policy-warn.json` | are there no forbidden changes?                                                                  |
| Cost policy            | `cost-decision.txt`, `cost-deny.json`, `cost-warn.json`       | are there no cost/blast-radius violations?                                                       |
| Risk review            | `risk-decision.json`, `risk-decision.md`                      | is apply allowed, what is the risk level, and is approval required?                              |
| Approval               | GitHub Environment approval or manual reviewer note           | did a human or GitHub Environment gate approve it?                                               |
| Apply                  | `apply.txt` from `terraform apply tfplan`                     | was the exact saved plan applied?                                                                |
| Drift check            | `post_apply_exitcode.txt` equals `0`                          | after apply, does Terraform see a clean state?                                                   |
| Runtime health         | target health, ASG health, alarm state evidence               | is the service actually healthy, not just Terraform-clean?                                       |
| Recovery readiness     | required runbook exists before risky apply                    | is there a runbook if apply goes badly?                                                          |


---

## 7. Local Checks

Run from repo root:

```bash
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/scripts/run-local-checks.sh
```

Optional checks:

```bash
RUN_OPA=true lessons/76-capstone-end-to-end-terraform-delivery-pipeline/scripts/run-local-checks.sh
RUN_TERRAFORM=true lessons/76-capstone-end-to-end-terraform-delivery-pipeline/scripts/run-local-checks.sh
```

`RUN_TERRAFORM=true` can require Terraform provider/plugin access if the local plugin cache is empty.

---

## 8. Manual Capstone Flow

Use this flow when practicing locally before wiring GitHub Actions.

`backend.hcl` and `terraform.tfvars` are not committed. For local work, create them from the examples and replace the placeholders:

```bash
cd lessons/76-capstone-end-to-end-terraform-delivery-pipeline/lab_76/terraform/envs/dev
cp backend.hcl.example backend.hcl
cp terraform.tfvars.example terraform.tfvars
```

In CI, `scripts/write-terraform-env-files.sh` creates these files from GitHub Variables. That keeps the workflow independent from local ignored files.

```bash
terraform init -backend-config=backend.hcl
terraform fmt -check -recursive ../..
terraform validate
terraform plan -out=tfplan
terraform show -no-color tfplan > tfplan.txt
terraform show -json tfplan > tfplan.json
sha256sum tfplan > tfplan.sha256
```

Run policy gates from repo root:

```bash
OUT_DIR=/tmp/l76-policy \
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/policies/security-policy.sh \
  lessons/76-capstone-end-to-end-terraform-delivery-pipeline/lab_76/terraform/envs/dev/tfplan.json

OUT_DIR=/tmp/l76-cost \
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/policies/cost-policy.sh \
  lessons/76-capstone-end-to-end-terraform-delivery-pipeline/lab_76/terraform/envs/dev/tfplan.json \
  dev
```

Run risk review:

```bash
POLICY_DIR=/tmp/l76-policy \
COST_DIR=/tmp/l76-cost \
OUT_DIR=/tmp/l76-risk \
REQUIRE_PROMOTION_EVIDENCE=false \
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/policies/risk-classifier.sh \
  lessons/76-capstone-end-to-end-terraform-delivery-pipeline/lab_76/terraform/envs/dev/tfplan.json \
  dev
```

Generate reviewer note:

```bash
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/scripts/reviewer-note-template.sh \
  /tmp/l76-risk/risk-decision.json \
  > /tmp/l76-reviewer-note.md
```

Only after review, apply the exact plan:

```bash
terraform apply tfplan
terraform plan -detailed-exitcode -input=false -no-color > post_apply_plan.txt
printf '%s\n' "$?" > post_apply_exitcode.txt
```

---

## 9. Promotion Evidence

For `stage` and `prod`, managed changes require promotion evidence.

`Promotion evidence` must prove that:

- this change has already passed through the previous environment
- on the same `commit SHA`
- with the same `release_id`
- the source run finished with `success`
- the source apply artifact contains `promotion-manifest.json`
- that manifest shows `apply_exitcode == 0`, `post_apply_exitcode == 0`, and `final_status == PROMOTABLE`
- `source_workflow_run_url`
  -> GitHub API
  -> status `completed`
  -> conclusion `success`
  -> `head_sha == current GITHUB_SHA`

Generate a template:

```bash
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/scripts/promotion-evidence-template.sh \
  l76-demo \
  dev \
  "$(git rev-parse HEAD)" \
  "https://github.com/OWNER/REPO/actions/runs/123456789" \
  > /tmp/promotion-evidence-stage.json
```

Minimum fields:

```json
{
  "release_id": "l76-demo",
  "source_env": "dev",
  "status": "passed",
  "commit_sha": "...",
  "source_workflow_run_url": "https://github.com/OWNER/REPO/actions/runs/..."
}
```

In CI this is stricter than a text note. The workflow downloads the source apply artifact and validates `promotion-manifest.json` before planning `stage` or `prod`.

For `prod`, the source environment should normally be `stage`.

---

## 10. Runtime Health Evidence

Terraform can be clean after `apply`, but the service may still not work:

- ASG exists, but instances are unhealthy
- ALB exists, but the target group is unhealthy
- CloudWatch alarm is in `ALARM`
- SSM endpoint exists, but the session does not work
- nginx did not start
- `user_data` failed
- Security Group allows the wrong traffic

After apply, collect read-only runtime evidence:

```bash
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/scripts/runtime-health-check.sh dev
```

The script reads Terraform outputs and checks:

- ALB target health;
- ASG instance health;
- CloudWatch alarm states.

It does not modify infrastructure or state.

---

## 11. Incident And Recovery Evidence

Before recovery work, capture current state evidence:

```bash
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/scripts/state-snapshot.sh dev
```

After recovery work, capture post-incident plan status:

```bash
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/scripts/post-incident-check.sh dev
```

Use runbooks in `runbooks/` for:

- failed apply;
- stuck lock;
- state restore;
- break-glass;
- rollback vs fix-forward;
- drift after emergency.

---

## 12. CI Templates

This lesson ships three templates:

| File | Purpose |
| --- | --- |
| `ci/lesson76-pr-checks.yml` | safe PR checks: fmt, scripts, policies, module tests |
| `ci/lesson76-capstone-promote.yml` | controlled promotion skeleton: plan artifacts before approval, exact-plan apply after approval |
| `ci/lesson76-drift-check.yml` | scheduled/manual read-only drift detection that fails on exit code `2` |

### Capstone promote

Plan job:

```text
validate inputs
checkout exact commit
local checks
verify source workflow run through GitHub API
assume plan role
generate backend/tfvars
terraform init/validate/plan
policy gates
cost gates
risk classifier
upload review artifact
fail if apply_allowed=false
```

Apply job:

```text
GitHub Environment approval
download reviewed artifact
assume apply role
restore backend/tfvars
init
sha256 check
terraform apply exact tfplan
post-apply drift check
upload apply artifact even on failure
```

### Drift check

Read-only workflow:

```text
schedule/manual
assume plan role
generate backend/tfvars
init
fmt/validate
terraform plan -detailed-exitcode -out=tfplan
upload drift evidence
fail on exit code 2
```

The promote template is intentionally conservative. Before using it against real AWS, verify:

- GitHub OIDC provider exists;
- GitHub Actions are pinned by commit SHA and upgraded through a separate review;
- `TF_PLAN_ROLE_ARN_*` variables are set;
- `TF_APPLY_ROLE_ARN_*` environment secrets are set;
- `TF_STATE_BUCKET`, `TF_WEB_AMI_ID`, `TF_SSM_PROXY_AMI_ID`, and `TF_GITHUB_OIDC_PROVIDER_ARN` variables are set;
- backend bucket/key are correct and generated by CI instead of being read from Git;
- GitHub Environments require reviewers for `stage`/`prod`;
- generated artifacts are reviewed before approval;
- `source_workflow_run_url` for `stage`/`prod` points to the previous environment run and is verified through the GitHub API;
- blocked risk still uploads a review artifact so reviewers can inspect why apply was stopped;
- apply artifact is uploaded even when apply or post-apply check fails;
- drift workflow uses plan role only, runs `fmt/validate`, saves `tfplan.txt`/`tfplan.json`, does not upload the binary `tfplan`, and does not apply changes.

---

## 13. Troubleshooting

| Symptom | Likely cause | What to check |
| --- | --- | --- |
| `terraform init` asks for bucket | missing or wrong `backend.hcl` | backend file path and values |
| plan role fails | OIDC, trust policy, or role ARN problem | GitHub variables, IAM trust policy, repo/ref claims |
| policy passes but risk is `BLOCKED` | missing evidence or deny from another gate | `risk-decision.md` reason codes |
| `stage`/`prod` blocked | missing promotion evidence | `PROMOTION_EVIDENCE_FILE`, `release_id`, `source_env` |
| apply blocked by approval | GitHub Environment protection | reviewers, branch restrictions, environment name |
| apply uses different changes | fresh plan used after approval | apply exact saved `tfplan` artifact only |
| post-apply exit code `2` | drift or unapplied diff | inspect `post_apply_plan.txt` |
| runtime health unhealthy | app, ALB, ASG, or alarm problem | target health, ASG activities, CloudWatch alarms |
| stuck lock | previous run interrupted | inspect lock, use runbook before force-unlock |

`Terraform init` asks for the bucket. Possible causes:

```text
backend.hcl is missing
backend.hcl was not passed through -backend-config
bucket placeholder was not replaced
CI did not generate backend.hcl
```

What to do:

```bash
ls -la backend.hcl
cat backend.hcl
terraform init -backend-config=backend.hcl -reconfigure
```

Plan role fails. Possible causes:

```text
TF_PLAN_ROLE_ARN_* is not set
OIDC trust does not match repo/ref/environment
role does not have access to the state bucket
role does not allow read/list/describe actions
```

Policy passes, but risk is `BLOCKED`. Possible causes:

```text
policy outputs missing
cost outputs missing
promotion evidence missing
promotion evidence invalid
incident mode without incident record
```

Check:

```text
risk-decision.md
risk-decision.json
Reason Codes
```

Apply is blocked by approval. Check:

```text
environment name terraform-dev/stage/prod
required reviewers
prevent self-review
deployment branches
secrets TF_APPLY_ROLE_ARN_*
```

Post-apply exit code `2`. Possible causes:

```text
drift
eventual consistency
provider read-after-write issue
failed partial apply
resource changed outside Terraform
config does not match the applied plan context
```

---

## 14. Practical Drills

### Drill 1. Local capstone checks

Run:

```bash
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/scripts/run-local-checks.sh
```

Expected: script and policy checks pass.

### Drill 2. Dev review package

Create for `dev`: `tfplan`, `tfplan.txt`, `tfplan.json`, policy outputs, cost outputs, risk decision, and reviewer note.

```bash
cd lessons/76-capstone-end-to-end-terraform-delivery-pipeline/lab_76/terraform/envs/dev
terraform init -backend-config=backend.hcl
terraform fmt -check -recursive ../..
terraform validate
terraform plan -out=tfplan
terraform show -no-color tfplan > tfplan.txt
terraform show -json tfplan > tfplan.json
sha256sum tfplan > tfplan.sha256
```

Then from the repo root:

```bash
OUT_DIR=/tmp/l76-policy \
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/policies/security-policy.sh \
  lessons/76-capstone-end-to-end-terraform-delivery-pipeline/lab_76/terraform/envs/dev/tfplan.json
```

```bash
OUT_DIR=/tmp/l76-cost \
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/policies/cost-policy.sh \
  lessons/76-capstone-end-to-end-terraform-delivery-pipeline/lab_76/terraform/envs/dev/tfplan.json \
  dev
```

```bash
POLICY_DIR=/tmp/l76-policy \
COST_DIR=/tmp/l76-cost \
OUT_DIR=/tmp/l76-risk \
REQUIRE_PROMOTION_EVIDENCE=false \
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/policies/risk-classifier.sh \
  lessons/76-capstone-end-to-end-terraform-delivery-pipeline/lab_76/terraform/envs/dev/tfplan.json \
  dev
```

Expected: the reviewer can answer what will change and why `apply` is allowed or blocked.

### Drill 3. Stage promotion evidence

Generate promotion evidence from `dev` to `stage`, then run the risk classifier for a managed change in `stage`.

```bash
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/scripts/promotion-evidence-template.sh \
  l76-demo \
  dev \
  "$(git rev-parse HEAD)" \
  "https://github.com/OWNER/REPO/actions/runs/123456789" \
  > /tmp/promotion-evidence-stage.json
```

Check:

```bash
jq . /tmp/promotion-evidence-stage.json
```

```bash
POLICY_DIR=/tmp/l76-policy \
COST_DIR=/tmp/l76-cost \
OUT_DIR=/tmp/l76-risk-stage \
PROMOTION_EVIDENCE_FILE=/tmp/promotion-evidence-stage.json \
SOURCE_ENV=dev \
RELEASE_ID=l76-demo \
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/policies/risk-classifier.sh \
  lessons/76-capstone-end-to-end-terraform-delivery-pipeline/lab_76/terraform/envs/stage/tfplan.json \
  stage
```

Expected: without evidence, risk is `BLOCKED`; with valid evidence, risk depends on the type of change.

### Drill 4. Prod high-risk review

Run the risk classifier for `prod` with promotion evidence from `stage`.

Expected: for managed changes, risk is at least `HIGH`.

### Drill 5. Blocked change

Use a fixture, for example `public-ingress-plan.json`.

```bash
set +e
OUT_DIR=/tmp/l76-blocked-policy \
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/policies/security-policy.sh \
  lessons/76-capstone-end-to-end-terraform-delivery-pipeline/policies/tests/public-ingress-plan.json
echo "policy exit code=$?"
set -e
```

Expected: the security policy produces a `deny`, and the risk classifier returns `BLOCKED`.

### Drill 6. Incident mode

Run the risk classifier with `INCIDENT_MODE=true` and a real `INCIDENT_RECORD_FILE`.

`INCIDENT_MODE` does not disable `security-policy.sh` or `cost-policy.sh`.

It only tells the `risk-classifier`:

```text
this is an emergency path
promotion evidence does not have to be required
but an incident record is required
```

Expected: with a record, risk can become `EMERGENCY`; without a record, it will be `BLOCKED`.

---

## 15. Proof Pack

Use `proof-pack.en.md` or `proof-pack.ru.md`. You can collect evidence into one folder and generate a summary:

```bash
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/scripts/collect-capstone-proof.sh dev
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/scripts/summarize-capstone.sh <evidence-dir>
```

`collect-capstone-proof.sh` collects known files only from lesson/env/evidence locations. It does not search outputs in `/tmp`. If you ran policy/cost/risk scripts with `OUT_DIR=/tmp/...`, copy those directories into the evidence folder first.

Minimum evidence:

```text
local-checks.txt
tfplan.txt
tfplan.json
policy-decision.txt
cost-decision.txt
risk-decision.md
reviewer-note.md
apply.txt
post_apply_plan.txt
post_apply_exitcode.txt
runtime-health-summary.txt
promotion-manifest.json
capstone-review-summary.md
```

Do not commit raw evidence if it contains account IDs, ARNs, internal DNS names, IPs, or secrets.

---

## 16. Acceptance Criteria

The lesson is complete when:

- local checks pass;
- module tests pass;
- `dev/stage/prod` roots validate;
- PR check template exists;
- promotion template documents plan-before-approval and exact-plan apply;
- drift check template exists and is read-only;
- proof collection and summary scripts work;
- policy, cost, and risk gates work;
- runtime health script points to `lab_76` and collects evidence;
- proof-pack documents what to save;
- runbooks are linked from the lesson;
- RU and EN docs have the same structure.

---

## 17. Lesson Summary

- **What you learned:** how to connect Terraform delivery controls into one auditable pipeline.
- **What you practiced:** checks, plans, policies, risk classification, approval, exact-plan apply, and verification.
- **Operational focus:** apply only what was reviewed, save evidence, and keep recovery runbooks close.
- **Why it matters:** production delivery is controlled evidence plus safe rollback/recovery paths.
