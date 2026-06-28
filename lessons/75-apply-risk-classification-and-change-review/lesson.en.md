# Apply Risk Classification & Change Review

**Date:** 2026-06-26

**Focus:** combine Terraform plan data, policy outputs, cost warnings, target environment, promotion evidence, and incident context into one final apply risk decision.

**Mindset:** an allowed plan is not automatically a low-risk plan. Approval should match risk.

---

## 1. Why This Lesson Exists

By this point, the delivery chain already contains separate checks:

```text
native tests -> security policy -> cost policy -> promotion evidence -> controlled apply -> least-privilege IAM -> recovery runbooks
```

But all of these checks answer different questions.

`security policy` answers:

```text
Is this change allowed at all?
```

For example:

- no `public ingress`
- no `destroy` without an exception
- required tags are present

`cost policy` answers:

```text
Is this change within the cost/blast-radius limits?
```

For example:

* ASG is not too large
* NAT is forbidden in `dev`
* public ALB produces a warning

`promotion evidence` answers:

```text
Did this change actually pass through the previous environment?
```

For example:

* `stage apply` must prove that `dev` was verified
* `prod apply` must prove that `stage` was verified

But one main question still remains before approval:

```text
What is the risk level of this apply?
```

Because `allowed` does not mean `low risk`.

Examples:

| Plan                                     | Policy result            | Real review risk |
| ---------------------------------------- | ------------------------ | ---------------- |
| Update one tag in `dev`                  | allow                    | low              |
| Add NAT Gateway in `stage`               | allow with warning       | medium           |
| Update ASG launch template in `prod`     | may be allowed by policy | high             |
| Delete old alarm with approved exception | allow with exception     | medium/high      |
| Apply during an active incident          | technically possible     | emergency        |
| Public ingress                           | deny                     | blocked          |

Lesson 75 adds the final layer:

```text
policy/cost/promote/context -> risk-decision.json / risk-decision.md
```

The artifact shows what changed, which environment is affected, which policies produced `warn` / `deny`, whether promotion evidence exists, what approval level is required, and whether `apply` can be started.

**Main model**

```text
Policy decides: allowed or not allowed.
Risk classification decides: how strictly this must be reviewed.
```

**Why this matters**

If you only have `allow/deny`, then all allowed changes look the same.

That is bad, because:

```text
tag in dev
```

and

```text
IAM/ASG change in prod
```

can both be `allowed`, but the review level must be different.

`risk-decision.json` is for the machine/CI:

```json
{
  "risk": "HIGH",
  "apply_allowed": true,
  "approval_required": true,
  "approval_level": "senior_reviewer_or_prod_environment",
  "reason_codes": ["target_env_prod"]
}
```

`risk-decision.md` is for the human:

```text
Risk: HIGH
Apply allowed: true
Approval required: true
Reason Codes:
- target_env_prod
```

**Important distinction**

`apply_allowed=true` does not mean “apply immediately.”

It means:

```text
the risk gate did not block apply
```

But if:

```text
approval_required=true
```

then a human or GitHub Environment must still approve it.

---

## 2. Outcomes

After this lesson you should be able to:

- classify applies as `NO_CHANGE`, `LOW`, `MEDIUM`, `HIGH`, `EMERGENCY`, or `BLOCKED`;
- combine security policy and cost policy outputs;
- use environment as a risk multiplier;
- require promotion evidence for `stage`/`prod`;
- treat IAM, destroy, replacement, and prod changes as higher risk;
- generate machine-readable and reviewer-readable risk artifacts;
- explain why “policy allowed” does not always mean “low risk”.

---

## 3. Connection To Previous Lessons

| Lesson | What it gave you | What lesson 75 adds |
| --- | --- | --- |
| 68 | controlled apply | final risk decision before approval/apply |
| 70 | JSON plan policy | security deny/warn inputs |
| 71 | promotion chain | promotion evidence as risk input |
| 73 | cost/blast-radius policy | cost deny/warn inputs |
| 74 | recovery runbooks | emergency classification and break-glass context |

Core model:

```text
Policy decides whether a plan is allowed.
Risk classification decides how much review it needs.
```

---

## 4. Repository Layout

```text
lessons/75-apply-risk-classification-and-change-review/
├── README.md
├── lesson.en.md
├── lesson.ru.md
├── proof-pack.en.md
├── proof-pack.ru.md
├── ci/
│   ├── lesson75-risk-review.yml
│   └── lesson75-real-plan-risk-review.yml
├── scripts/
│   ├── run-local-checks.sh
│   ├── promotion-evidence-template.sh
│   └── reviewer-note-template.sh
├── policies/
│   ├── terraform-plan-policy.sh
│   ├── cost-policy.sh
│   ├── risk-classifier.sh
│   ├── test-risk-classifier.sh
│   └── tests/
└── lab_75/
```

`lab_75` keeps the infrastructure shape from the previous lessons.

`scripts/` is the operator/helper layer, similar to lesson 74. These scripts do not replace `policies/`; they help run local checks, generate promotion evidence, and prepare reviewer notes.

---

## 5. Risk Levels

| Risk | Meaning | Examples | Approval |
| --- | --- | --- | --- |
| `NO_CHANGE` | no managed changes | plan contains only `no-op` managed resources | no approval required |
| `LOW` | small, reversible, usually dev-only | tag/description change in `dev` | normal env approval |
| `MEDIUM` | visible infra change or warnings | stage change, NAT warning, ASG/launch template change | reviewer approval |
| `HIGH` | prod, IAM, destroy, replacement, or sensitive change | prod ASG update, IAM policy change, approved destroy | senior/manual approval |
| `EMERGENCY` | active incident or break-glass context | prod down, recovery apply, incident mitigation | incident approval + record |
| `BLOCKED` | deny or missing required evidence | security deny, cost deny, missing promotion evidence, invalid tfplan.json | no apply |

Important: `NO_CHANGE` is possible only if the input files are valid:

```text
policy-deny.json exists
policy-warn.json exists
cost-deny.json exists
cost-warn.json exists
tfplan.json is valid
```

Why? Because otherwise `{}` or a missing policy output could look like “no changes.”

Important: `EMERGENCY` does not bypass `deny`:

```text
EMERGENCY does not bypass deny.
EMERGENCY requires INCIDENT_RECORD_FILE.
```

An incident record is required:

```text
what happened
who approved it
why the emergency path is needed
```

**Most important priority rule**

```text
BLOCKED > EMERGENCY > HIGH > MEDIUM > LOW > NO_CHANGE
```

This means:

```text
if there is deny -> BLOCKED
even if INCIDENT_MODE=true
```

```text
if there is an active incident and evidence exists -> EMERGENCY
even if there is destroy/replacement
```

```text
if prod -> at least HIGH
```

```text
if stage/warning -> at least MEDIUM
```

```text
if there are no changes -> NO_CHANGE
but only after valid inputs
```

Rule:

```text
Deny means stop.
Risk means choose the approval level.
Fail closed: if required policy/cost outputs are missing or malformed, risk must become BLOCKED.
```

---

## 6. Risk Inputs

`policies/risk-classifier.sh` reads:

```text
tfplan.json
target_env
policy-results/policy-deny.json
policy-results/policy-warn.json
cost-policy-results/cost-deny.json
cost-policy-results/cost-warn.json
PROMOTION_EVIDENCE_FILE
INCIDENT_MODE
INCIDENT_RECORD_FILE
RELEASE_ID
SOURCE_ENV
ALLOW_MISSING_POLICY_OUTPUTS
```

### `tfplan.json`

This is the machine-readable Terraform plan:

```bash
terraform show -json tfplan > tfplan.json
```

It is needed so the classifier can count:

```text
changed_count
destructive_count
replacement_count
iam_change_count
asg_or_launch_template_change_count
```

So the classifier does not inspect the whole plan manually. It counts important classes of changes.

### `target_env`

```text
dev
stage
prod
```

The environment itself affects the risk.

```text
dev -> can be LOW
stage -> at least MEDIUM when there are changes
prod -> at least HIGH when there are changes
```

Why?

Because the same change has a different cost of failure in different environments.

`policy-deny.json`

Comes from:

```bash
terraform-plan-policy.sh
```

If it contains at least one `deny`: -> risk = `BLOCKED`

`policy-warn.json`
If it contains a `warning`: -> risk = at least `MEDIUM`

`cost-deny.json`
If it contains a cost `deny`: -> risk = `BLOCKED`

`cost-warn.json`
If it contains a cost `warning`: -> risk = at least `MEDIUM`

### `PROMOTION_EVIDENCE_FILE`

Required for `stage` / `prod` when there are managed changes.

It proves that the change has already passed through the previous environment.

For `stage`: -> source_env = `dev`

For `prod`: -> source_env = `stage`

Now evidence is validated as a contract:

```json
{
  "release_id": "l75-demo",
  "source_env": "dev",
  "status": "passed",
  "commit_sha": "0123456789abcdef0123456789abcdef01234567"
}
```

Important: the file simply existing is not enough. It must be valid.

### `INCIDENT_MODE`

If:

```bash
INCIDENT_MODE=true
```

then the classifier can return: -> `EMERGENCY`

But only if there is: -> `INCIDENT_RECORD_FILE`

### `INCIDENT_RECORD_FILE`

This is break-glass evidence:

- which incident
- which severity
- why the emergency path is needed
- who approved it

For now, in the lesson, only the presence of a non-empty file is checked.

### Fail-closed inputs

The most important principle:

```text
if a required input is missing or broken -> BLOCKED
```

For example:

- `policy-deny.json` is missing
- `cost-warn.json` is missing
- `policy-deny.json` is `{}`, not `[]`
- `tfplan.json` is `{}`, not a Terraform plan

All of this must block `apply`.

Main signals:

| Signal | Risk effect |
| --- | --- |
| missing or malformed required policy/cost output | `BLOCKED` |
| security/cost deny | `BLOCKED` |
| missing/invalid promotion evidence for `stage`/`prod` when managed changes exist | `BLOCKED` |
| incident mode with incident record | `EMERGENCY` if no deny exists |
| incident mode without incident record | `BLOCKED` |
| prod environment | `HIGH` |
| IAM change | `HIGH` |
| destroy/replacement | `HIGH` |
| policy/cost warning | at least `MEDIUM` |
| ASG/launch template change | at least `MEDIUM` |
| stage environment | at least `MEDIUM` |
| no managed resource changes | `NO_CHANGE` |
| small dev-only change | `LOW` |

Precedence is applied from strongest to weakest:

```text
BLOCKED > EMERGENCY > HIGH > MEDIUM > LOW > NO_CHANGE
```

This means:

- `BLOCKED` always wins over other levels;
- `EMERGENCY` does not bypass denies and does not work without `INCIDENT_RECORD_FILE`;
- `HIGH` is stronger than `MEDIUM` and `LOW`;
- `NO_CHANGE` is possible only after required input files exist and are valid.

The classifier also separates two decisions:

- `risk` — how dangerous the change is;
- `approval_required` and `approval_level` — whether approval is required and which path should be used.

This makes pipeline automation easier: machines read `apply_allowed`, `approval_required`, and `approval_level`; humans read `reason_codes`.

Promotion evidence is validated as a contract, not as “a file exists”. When evidence is required, the classifier expects a JSON object with:

- `release_id` — must match `RELEASE_ID` if provided;
- `source_env` — must match `SOURCE_ENV` if provided;
- `status` — must be `passed`;
- `commit_sha` — must look like a Git SHA.

---

## 7. Risk Classifier

Direct run:

```bash
lessons/75-apply-risk-classification-and-change-review/policies/risk-classifier.sh tfplan.json dev
```

Useful environment variables:

```bash
POLICY_DIR=policy-results
COST_DIR=cost-policy-results
OUT_DIR=risk-results
INCIDENT_MODE=false
INCIDENT_RECORD_FILE=/tmp/incident-record.md
RELEASE_ID=l75-demo
SOURCE_ENV=dev
PROMOTION_EVIDENCE_FILE=/tmp/promotion-evidence.json
REQUIRE_PROMOTION_EVIDENCE=true
ALLOW_MISSING_POLICY_OUTPUTS=false
```

The idea is simple: this is the final “decision aggregator”.

It does not search for every problem from scratch. Instead, it takes already prepared inputs:

```text
terraform plan -> tfplan.json
terraform-plan-policy.sh -> policy-deny.json / policy-warn.json
cost-policy.sh -> cost-deny.json / cost-warn.json
promotion-evidence-template.sh or CI artifact -> promotion-evidence.json
incident record -> only if INCIDENT_MODE=true
target_env -> second argument: dev/stage/prod
risk-classifier.sh -> risk-decision.json / risk-decision.md
```

Manual chain for a real `dev` plan:

```bash
cd lessons/75-apply-risk-classification-and-change-review/lab_75/terraform/envs/dev

terraform plan -out=tfplan
terraform show -json tfplan > tfplan.json

mkdir -p ../../../../evidence/policy-results \
         ../../../../evidence/cost-policy-results \
         ../../../../evidence/risk-results

OUT_DIR=../../../../evidence/policy-results \
../../../../policies/terraform-plan-policy.sh tfplan.json

OUT_DIR=../../../../evidence/cost-policy-results \
../../../../policies/cost-policy.sh tfplan.json dev

POLICY_DIR=../../../../evidence/policy-results \
COST_DIR=../../../../evidence/cost-policy-results \
OUT_DIR=../../../../evidence/risk-results \
REQUIRE_PROMOTION_EVIDENCE=false \
../../../../policies/risk-classifier.sh tfplan.json dev
```

And turns them into one final result:

```text
risk-decision.json
risk-decision.md
```

`risk-decision.json` contains:

* `risk`
* `apply_allowed`
* `approval_required`
* `approval_level`
* `promotion_present`
* `promotion_valid`
* `reason_codes`
* counters for destructive/replacement/IAM/policy/cost signals
* `fail_closed: true`

So instead of forcing the reviewer to manually open 5 different files, the classifier collects the answer:

```text
Risk: HIGH
Apply allowed: true
Approval required: true
Reason codes:
- target_env_prod
- iam_change
- replacement_change
```

Key model:

- policy/cost outputs = signals
- risk-classifier = final decision

Important variables:

```bash
INCIDENT_MODE=false
```

If `true`, this is an emergency/break-glass scenario.

But important:

```text
INCIDENT_MODE=true does not bypass deny
```

If there is a deny, the result will still be `BLOCKED`.

```bash
PROMOTION_EVIDENCE_FILE=/tmp/promotion-evidence.json
```

A file that proves the change has passed through the previous environment.

For example, for `prod`, it must prove that `stage` has already passed successfully.

```bash
REQUIRE_PROMOTION_EVIDENCE=true
```

For `stage` / `prod`, evidence must exist. Otherwise, this is fail-closed.

```bash
ALLOW_MISSING_POLICY_OUTPUTS=false
```

If policy output files are missing, the classifier must not think:

```text
no files = no problems
```

Correct behavior:

```text
no files = check is broken = BLOCKED
```

This is `fail closed`.

Exit codes:

```text
0  -> risk gate allowed the pipeline to continue
1  -> input/tooling failed
2  -> risk gate blocked apply
64 -> script was called incorrectly
```

---

## 8. Approval Mapping

| Risk | Apply allowed? | Suggested approval path |
| --- | --- | --- |
| `NO_CHANGE` | yes | no approval required |
| `LOW` | yes | normal env approval |
| `MEDIUM` | yes | reviewer or stage environment |
| `HIGH` | yes | senior reviewer / high-risk environment |
| `EMERGENCY` | yes, only with incident record | break-glass / incident approval |
| `BLOCKED` | no | none |

The purpose of this section: `risk` does not apply infrastructure by itself. It tells you what level of review is required before `apply`.

The most important point here:

```text
apply_allowed=true
```

does not mean:

```text
you can immediately press apply
```

It only means:

```text
the risk gate did not block the change
```

But if:

```text
approval_required=true
```

then a human or GitHub Environment approval is required.

Example:

```text
Risk: HIGH
Apply allowed: true
Approval required: true
Reason Codes:
- iam_change
```

This means:

```text
There is no policy deny.
There is no cost deny.
But there are IAM changes.
So apply is technically allowed, but only after high-risk review.
```

Why this is the correct model:

```text
deny/block = the change is forbidden
risk/approval = the change is allowed, but requires control
```

So we separate:

```text
risk
apply_allowed
approval_required
approval_level
```

Example:

```json
{
  "risk": "HIGH",
  "apply_allowed": true,
  "approval_required": true,
  "approval_level": "senior_reviewer_or_high_risk_environment"
}
```

Read it as:

```text
The change is risky, but not forbidden.
Apply is possible only after senior/high-risk approval.
```

And here is `BLOCKED`:

```json
{
  "risk": "BLOCKED",
  "apply_allowed": false,
  "approval_required": false,
  "approval_level": "none"
}
```

Read it as:

```text
The change is forbidden.
Approval is not needed, because there is nothing to approve.
First fix the plan/policy/evidence.
```

GitHub Environment model:

```text
terraform-dev
terraform-stage
terraform-prod
terraform-high-risk
terraform-break-glass
```

The idea:

- normal `dev` apply can go through `terraform-dev`
- `stage` goes through `terraform-stage`
- `prod` goes through `terraform-prod`
- `HIGH` can be routed to a separate `terraform-high-risk`
- `EMERGENCY` goes to `terraform-break-glass`

In this lesson, the implementation stays simple: the classifier creates an artifact, and the reviewer uses it before approving `apply`.

---

## 9. CI Model

- `ci/lesson75-real-plan-risk-review.yml` - real AWS-backed plan through OIDC and the remote backend. The active copy lives in `.github/workflows/lesson75-real-plan-risk-review.yml`.

Workflows do not run `apply`.

The correct order for a real apply pipeline is:

```text
fmt/test/validate
-> terraform plan -out=tfplan
-> terraform show -json tfplan
-> security policy
-> cost policy
-> risk classifier
-> upload plan/policy/risk artifacts
-> environment approval
-> apply exact tfplan
-> post-apply drift check
```

Important:

```text
Risk decision must exist before human approval.
```

A reviewer should see:

- `tfplan.txt`;
- `policy-decision.txt`;
- `cost-decision.txt`;
- `risk-decision.md`;
- promotion evidence for `stage`/`prod`.

The real plan workflow does:

```text
OIDC assume plan role
-> write backend.hcl / terraform.auto.tfvars
-> terraform init with S3 backend
-> terraform plan -out=tfplan
-> terraform show -json tfplan
-> security policy
-> cost policy
-> risk classifier
-> upload real plan/policy/cost/risk artifacts
```

Required repository variables:

```text
AWS_REGION
TF_STATE_BUCKET
TF_WEB_AMI_ID
TF_SSM_PROXY_AMI_ID
TF_GITHUB_OIDC_PROVIDER_ARN
TF_PLAN_ROLE_ARN_DEV
TF_PLAN_ROLE_ARN_STAGE
TF_PLAN_ROLE_ARN_PROD
```

`dev` does not need promotion evidence. `stage` and `prod` require a repo-relative `promotion_evidence_path` so the classifier can validate promotion context.

CI has additional safeguards:

- `ALLOW_MISSING_POLICY_OUTPUTS=true` is explicitly forbidden in CI;
- global `REQUIRE_PROMOTION_EVIDENCE=false` is explicitly forbidden in CI;
- policy/cost exit `2` does not stop risk artifact collection, but tooling errors stop the job;
- `risk-classifier` remains the final gate: if risk is `BLOCKED`, the workflow fails after artifacts are saved.

---

## 10. Local Tests

Run all inherited and risk tests:

```bash
lessons/75-apply-risk-classification-and-change-review/policies/test-policy.sh
lessons/75-apply-risk-classification-and-change-review/policies/test-cost-policy.sh
lessons/75-apply-risk-classification-and-change-review/policies/test-risk-classifier.sh
lessons/75-apply-risk-classification-and-change-review/policies/test-opa.sh
```

The risk tests prove:

- no-change plan -> `NO_CHANGE`;
- safe dev change -> `LOW`;
- stage NAT warning with evidence -> `MEDIUM`;
- prod change with evidence -> `HIGH`;
- invalid promotion evidence -> `BLOCKED`;
- policy deny -> `BLOCKED`;
- missing or malformed policy/cost outputs -> `BLOCKED`;
- incident mode -> `EMERGENCY`;
- incident mode without incident record -> `BLOCKED`;
- missing stage promotion evidence with managed changes -> `BLOCKED`.

---

## 11. Drills

All drills run locally against synthetic `tfplan.json` fixtures. No AWS access is required.

From repo root:

```bash
cd lessons/75-apply-risk-classification-and-change-review
```

Prepare temporary files:

```bash
mkdir -p /tmp/l75-review

cat > /tmp/l75-review/promotion-evidence-stage.json <<'EOF'
{
  "release_id": "l75-demo",
  "source_env": "dev",
  "status": "passed",
  "workflow_run_url": "https://example.invalid/workflow",
  "commit_sha": "0123456789abcdef0123456789abcdef01234567"
}
EOF

cat > /tmp/l75-review/promotion-evidence-prod.json <<'EOF'
{
  "release_id": "l75-demo",
  "source_env": "stage",
  "status": "passed",
  "workflow_run_url": "https://example.invalid/workflow",
  "commit_sha": "0123456789abcdef0123456789abcdef01234567"
}
EOF

cat > /tmp/l75-review/incident-record.md <<'EOF'
# Incident Record

- Incident ID: INC-L75-001
- Severity: SEV-2
- Reason: lesson 75 emergency-mode drill
- Approval: simulated
EOF
```

### Drill 1. Low-risk dev change

Use `safe-plan.json` with target env `dev`.

```bash
rm -rf /tmp/l75-review/low-dev
mkdir -p /tmp/l75-review/low-dev/policy /tmp/l75-review/low-dev/cost
printf '[]\n' > /tmp/l75-review/low-dev/policy/policy-deny.json
printf '[]\n' > /tmp/l75-review/low-dev/policy/policy-warn.json
printf '[]\n' > /tmp/l75-review/low-dev/cost/cost-deny.json
printf '[]\n' > /tmp/l75-review/low-dev/cost/cost-warn.json

POLICY_DIR=/tmp/l75-review/low-dev/policy \
COST_DIR=/tmp/l75-review/low-dev/cost \
OUT_DIR=/tmp/l75-review/low-dev/risk \
REQUIRE_PROMOTION_EVIDENCE=false \
policies/risk-classifier.sh policies/tests/safe-plan.json dev
```

Expected:

```text
Risk: LOW
Apply allowed: true
Approval required: true
Approval level: standard
Reason Codes:
- small_dev_change
```

### Drill 2. Medium-risk stage warning

Use `cost-nat-plan.json` with target env `stage` and promotion evidence file.

```bash
rm -rf /tmp/l75-review/medium-stage
mkdir -p /tmp/l75-review/medium-stage/policy /tmp/l75-review/medium-stage/cost

OUT_DIR=/tmp/l75-review/medium-stage/policy \
policies/terraform-plan-policy.sh policies/tests/cost-nat-plan.json || true

OUT_DIR=/tmp/l75-review/medium-stage/cost \
policies/cost-policy.sh policies/tests/cost-nat-plan.json stage || true

POLICY_DIR=/tmp/l75-review/medium-stage/policy \
COST_DIR=/tmp/l75-review/medium-stage/cost \
OUT_DIR=/tmp/l75-review/medium-stage/risk \
PROMOTION_EVIDENCE_FILE=/tmp/l75-review/promotion-evidence-stage.json \
RELEASE_ID=l75-demo \
SOURCE_ENV=dev \
policies/risk-classifier.sh policies/tests/cost-nat-plan.json stage
```

Expected:

```text
Risk: MEDIUM
Approval required: true
Approval level: reviewer_or_stage_environment
Apply allowed: true
Promotion required: true
Promotion present: true
Promotion valid: true
Reason Codes:
- target_env_stage
- warnings_present
```

### Drill 3. High-risk prod change

Use a safe plan with target env `prod` and promotion evidence file.

```bash
rm -rf /tmp/l75-review/high-prod
mkdir -p /tmp/l75-review/high-prod/policy /tmp/l75-review/high-prod/cost
printf '[]\n' > /tmp/l75-review/high-prod/policy/policy-deny.json
printf '[]\n' > /tmp/l75-review/high-prod/policy/policy-warn.json
printf '[]\n' > /tmp/l75-review/high-prod/cost/cost-deny.json
printf '[]\n' > /tmp/l75-review/high-prod/cost/cost-warn.json

POLICY_DIR=/tmp/l75-review/high-prod/policy \
COST_DIR=/tmp/l75-review/high-prod/cost \
OUT_DIR=/tmp/l75-review/high-prod/risk \
PROMOTION_EVIDENCE_FILE=/tmp/l75-review/promotion-evidence-prod.json \
RELEASE_ID=l75-demo \
SOURCE_ENV=stage \
policies/risk-classifier.sh policies/tests/safe-plan.json prod
```

Expected:

```text
Risk: HIGH
Approval required: true
Approval level: senior_reviewer_or_prod_environment
Apply allowed: true
Reason Codes:
- target_env_prod
```

### Drill 4. Blocked public ingress

Use `public-ingress-plan.json` with target env `dev`.

```bash
rm -rf /tmp/l75-review/blocked-ingress
mkdir -p /tmp/l75-review/blocked-ingress/policy /tmp/l75-review/blocked-ingress/cost

OUT_DIR=/tmp/l75-review/blocked-ingress/policy \
policies/terraform-plan-policy.sh policies/tests/public-ingress-plan.json || true

printf '[]\n' > /tmp/l75-review/blocked-ingress/cost/cost-deny.json
printf '[]\n' > /tmp/l75-review/blocked-ingress/cost/cost-warn.json

POLICY_DIR=/tmp/l75-review/blocked-ingress/policy \
COST_DIR=/tmp/l75-review/blocked-ingress/cost \
OUT_DIR=/tmp/l75-review/blocked-ingress/risk \
REQUIRE_PROMOTION_EVIDENCE=false \
policies/risk-classifier.sh policies/tests/public-ingress-plan.json dev || true
```

Expected:

```text
Risk: BLOCKED
Approval required: false
Approval level: none
Apply allowed: false
Security policy denies: 1
Reason Codes:
- policy_or_cost_deny_present
```

### Drill 5. Emergency mode

Run classifier with:

```bash
INCIDENT_MODE=true
INCIDENT_RECORD_FILE=/tmp/incident-record.md
```

Command:

```bash
rm -rf /tmp/l75-review/emergency
mkdir -p /tmp/l75-review/emergency/policy /tmp/l75-review/emergency/cost
printf '[]\n' > /tmp/l75-review/emergency/policy/policy-deny.json
printf '[]\n' > /tmp/l75-review/emergency/policy/policy-warn.json
printf '[]\n' > /tmp/l75-review/emergency/cost/cost-deny.json
printf '[]\n' > /tmp/l75-review/emergency/cost/cost-warn.json

POLICY_DIR=/tmp/l75-review/emergency/policy \
COST_DIR=/tmp/l75-review/emergency/cost \
OUT_DIR=/tmp/l75-review/emergency/risk \
INCIDENT_MODE=true \
INCIDENT_RECORD_FILE=/tmp/l75-review/incident-record.md \
REQUIRE_PROMOTION_EVIDENCE=false \
policies/risk-classifier.sh policies/tests/safe-plan.json dev
```

Expected:

```text
Risk: EMERGENCY
Approval required: true
Approval level: incident_commander_and_break_glass
Apply allowed: true
Incident mode: true
Incident record required: true
Incident record present: true
Reason Codes:
- incident_mode_enabled
```

Counterexample:

```bash
OUT_DIR=/tmp/l75-review/emergency-missing-record/risk \
POLICY_DIR=/tmp/l75-review/emergency/policy \
COST_DIR=/tmp/l75-review/emergency/cost \
INCIDENT_MODE=true \
REQUIRE_PROMOTION_EVIDENCE=false \
policies/risk-classifier.sh policies/tests/safe-plan.json dev || true
```

Expected: `BLOCKED` with reason `incident_record_missing`.

### Drill 6. Missing promotion evidence

Run classifier for `stage` or `prod` without `PROMOTION_EVIDENCE_FILE`.

```bash
rm -rf /tmp/l75-review/missing-promotion
mkdir -p /tmp/l75-review/missing-promotion/policy /tmp/l75-review/missing-promotion/cost
printf '[]\n' > /tmp/l75-review/missing-promotion/policy/policy-deny.json
printf '[]\n' > /tmp/l75-review/missing-promotion/policy/policy-warn.json
printf '[]\n' > /tmp/l75-review/missing-promotion/cost/cost-deny.json
printf '[]\n' > /tmp/l75-review/missing-promotion/cost/cost-warn.json

POLICY_DIR=/tmp/l75-review/missing-promotion/policy \
COST_DIR=/tmp/l75-review/missing-promotion/cost \
OUT_DIR=/tmp/l75-review/missing-promotion/risk \
RELEASE_ID=l75-demo \
SOURCE_ENV=dev \
policies/risk-classifier.sh policies/tests/safe-plan.json stage || true
```

Expected:

```text
Risk: BLOCKED
Approval required: false
Approval level: none
Apply allowed: false
Promotion required: true
Promotion present: false
Promotion valid: false
Reason Codes:
- promotion_evidence_missing
```

### Drill 7. No-change plan

Use a fixture where managed resources do not change.

```bash
rm -rf /tmp/l75-review/no-change
mkdir -p /tmp/l75-review/no-change/policy /tmp/l75-review/no-change/cost
printf '[]\n' > /tmp/l75-review/no-change/policy/policy-deny.json
printf '[]\n' > /tmp/l75-review/no-change/policy/policy-warn.json
printf '[]\n' > /tmp/l75-review/no-change/cost/cost-deny.json
printf '[]\n' > /tmp/l75-review/no-change/cost/cost-warn.json

POLICY_DIR=/tmp/l75-review/no-change/policy \
COST_DIR=/tmp/l75-review/no-change/cost \
OUT_DIR=/tmp/l75-review/no-change/risk \
REQUIRE_PROMOTION_EVIDENCE=false \
policies/risk-classifier.sh policies/tests/no-op-warn-plan.json dev
```

Expected:

```text
Risk: NO_CHANGE
Approval required: false
Approval level: none
Apply allowed: true
Changed resources: 0
Reason Codes:
- no_managed_resource_changes
```

Meaning:

- if Terraform is not going to change any managed resources, approval is not needed
- but this is allowed only if policy/cost outputs exist and are valid
- otherwise `{}` or a broken pipeline could incorrectly become `NO_CHANGE`

### Drill 8. Fail closed on missing outputs

Run the classifier without `policy-deny.json`, `policy-warn.json`, `cost-deny.json`, and `cost-warn.json`.

```bash
rm -rf /tmp/l75-review/fail-closed
mkdir -p /tmp/l75-review/fail-closed/policy /tmp/l75-review/fail-closed/cost

POLICY_DIR=/tmp/l75-review/fail-closed/policy \
COST_DIR=/tmp/l75-review/fail-closed/cost \
OUT_DIR=/tmp/l75-review/fail-closed/risk \
REQUIRE_PROMOTION_EVIDENCE=false \
policies/risk-classifier.sh policies/tests/safe-plan.json dev || true
```

Expected:

- risk `BLOCKED`;
- `apply_allowed=false`;
- reason includes `policy_deny_missing`, `policy_warn_missing`, `cost_deny_missing`, `cost_warn_missing`.

---

## 12. Troubleshooting

| Symptom | Likely cause | What to do |
| --- | --- | --- |
| risk is `BLOCKED` | deny exists or evidence is missing | inspect `risk-decision.md` reasons |
| safe plan became `BLOCKED` | policy/cost outputs are missing or malformed | run security/cost policy first or check `POLICY_DIR`/`COST_DIR` |
| stage/prod blocked unexpectedly | missing `PROMOTION_EVIDENCE_FILE` or evidence failed the contract | check `release_id`, `source_env`, `status`, `commit_sha` |
| risk is higher than expected | env, IAM, destroy, replacement, or warning signal raised it | inspect counts in `risk-decision.json` |
| risk is `NO_CHANGE` | plan has no managed resource changes | confirm this is the expected plan and not the wrong fixture/artifact |
| classifier exits `64` for `tfplan.json` | this is not a Terraform JSON plan or it lacks `resource_changes[].change.actions` | regenerate JSON with `terraform show -json tfplan` |
| classifier exits `64` | wrong args/env values | check usage and target env |
| emergency mode used too casually | no incident record | require break-glass evidence |
| policy allow but risk high | plan is allowed but still sensitive | use stronger approval |

---

## 13. Acceptance Criteria

Lesson is complete when:

- risk classifier exists and is executable;
- classifier reads policy/cost outputs;
- classifier uses a fail-closed model for missing/malformed inputs;
- classifier rejects JSON that does not look like a Terraform plan;
- classifier produces `risk-decision.json` and `risk-decision.md`;
- no-change plan becomes `NO_CHANGE`;
- safe dev change becomes `LOW`;
- stage warning becomes `MEDIUM`;
- prod change becomes `HIGH`;
- invalid promotion evidence becomes `BLOCKED`;
- policy deny becomes `BLOCKED`;
- incident mode becomes `EMERGENCY`;
- incident mode without incident record becomes `BLOCKED`;
- missing promotion evidence blocks stage/prod when managed changes exist;
- risk artifact is available before approval;

---

## 14. Lesson Summary

- **What you learned:** allowed plans still need risk classification.
- **What you practiced:** combining Terraform action data, policy outputs, cost outputs, environment, promotion evidence, and incident mode into one review artifact.
- **Core safety rule:** the classifier must fail closed instead of pretending a change is safe when inputs are missing.
- **Operational focus:** approval should match risk.
