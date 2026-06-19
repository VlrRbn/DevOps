# Lesson 73. Cost & Blast-Radius Controls

**Date:** 2026-06-12

**Focus:** add cost visibility, budget guardrails, quota awareness, and blast-radius limits to Terraform delivery before apply.

**Mindset:** a safe Terraform plan must be technically valid, secure, affordable, and limited to the intended environment impact.

---

## 1. Why This Lesson Exists

By lesson 72 the delivery chain is strong:

```text
module contracts -> native tests -> versioned module releases -> dev/stage/prod promotion -> JSON plan policy -> controlled apply
```

One production risk still remains:

```text
A valid Terraform plan can still be financially unsafe.
```

Examples:

- ASG `max_size` changes from `4` to `40`;
- NAT Gateway appears in a cheap lab environment;
- a large instance type is introduced by mistake;
- prod receives a wider blast radius than the release needs;
- a service quota risk is noticed only after apply fails;
- budget alerts exist, but nobody has proof that they are configured.

Lesson 73 adds pre-apply cost and blast-radius controls.

---

## 2. Outcomes

After this lesson you should be able to:

- explain the difference between cost risk and blast radius;
- define per-environment cost limits;
- run a cost/blast-radius policy against `tfplan.json`;
- deny ASG scale increases above environment limits;
- make NAT Gateway changes visible and environment-aware;
- block intentionally oversized instance types for the lab;
- capture budget and quota evidence;
- produce a cost decision artifact before approval/apply.

---

## 3. Connection To Previous Lessons

| Lesson | What it gave you | What lesson 73 adds |
| --- | --- | --- |
| 70 | JSON plan policy | cost-specific rules over the same `tfplan.json` |
| 71 | multi-environment promotion | different cost limits per env |
| 72 | versioned module releases | cost evidence for promoted module versions |

The key idea:

```text
Security policy says: is this change safe enough?
Cost policy says: is this change affordable and limited enough for this environment?
```

---

## 4. Repository Layout

```text
lessons/73-cost-and-blast-radius-controls/
├── README.md
├── lesson.en.md
├── lesson.ru.md
├── proof-pack.en.md
├── proof-pack.ru.md
├── ci/
│   └── lesson73-cost-guard.yml
├── policies/
│   ├── terraform-plan-policy.sh
│   ├── cost-policy.sh
│   ├── test-policy.sh
│   ├── test-cost-policy.sh
│   └── tests/
└── lab_73/
    ├── packer/
    └── terraform/
        ├── envs/
        │   ├── dev/
        │   ├── stage/
        │   └── prod/
        └── modules/
            └── network/
```

`lab_73` keeps the same delivery shape as lessons 71-72. The new topic is not a new architecture; it is a new guardrail layer.

---

## 5. Cost Risk vs Blast Radius

| Risk type | Meaning | Example |
| --- | --- | --- |
| Cost risk | How much money the change can burn | NAT Gateway, expensive instance type, larger ASG |
| Blast radius | How much impact the change can have | prod-wide rollout, public ALB, shared IAM role, common state/backend |
| Quota risk | Whether AWS limits can block the change | ALB quota, EIP quota, IAM role quota, CloudWatch alarm quota |
| Recovery risk | How hard rollback becomes | replacement, deletion, stateful resource change |

A change can be cheap but dangerous:

```text
public ingress from 0.0.0.0/0
```

A change can be expensive but technically valid:

```text
NAT Gateway in every lab environment
```

`Security policy` answers:

* Is this safe in terms of access, `destructive changes`, `public ingress`, and `tags`?

`Cost policy` answers:

* Is this acceptable in terms of cost and scale for the specific `environment`?


You need both `security policy` and `cost/blast-radius policy`.

---

## 6. Environment Risk Matrix

Training thresholds:

| Environment | ASG max_size limit | NAT Gateway | Public ALB | Intent |
| --- | ---: | --- | --- | --- |
| `dev` | 2 | deny | warn | cheap by default |
| `stage` | 3 | warn | warn | production-like but controlled |
| `prod` | 4 | warn | warn | deliberate changes only |

These numbers are intentionally small. They make mistakes visible during the lab.

Production teams should tune these values using real budgets, service ownership, expected traffic, and rollback strategy.

---

## 7. Cost Policy

`policies/cost-policy.sh` reads Terraform JSON plan and target environment:

```bash
policies/cost-policy.sh tfplan.json dev
```

It writes:

```text
cost-policy-results/
  cost-decision.txt
  cost-deny.json
  cost-warn.json
```

Current rules:

| Rule | Decision | Why |
| --- | --- | --- |
| ASG `max_size` above env limit | deny | prevents runaway scale |
| NAT Gateway in `dev` | deny | keeps dev cheap by default |
| NAT Gateway in `stage/prod` | warn | cost must be visible |
| large instance type | deny | blocks accidental expensive compute |
| public ALB | warn | exposure/blast-radius review signal |

Understand the script boundary:

- it does not calculate an exact AWS price;
- it does not replace Infracost, AWS Budgets, or Cost Explorer;
- it checks known risky patterns in a Terraform JSON plan;
- some lesson risks are tested through synthetic fixtures in `policies/tests/` so you do not create expensive AWS resources for the drill;
- in a real apply pipeline, this script must run after `terraform show -json` against the same saved plan that will later be applied.

Full logic in short form:

1. Receive `tfplan.json` and `target_env`
2. Check `jq` and the `plan` file
3. Select limits for `dev` / `stage` / `prod`
4. Check `ASG max_size`
5. Check `NAT Gateway`
6. Check large EC2 `instance types`
7. Check public `Load Balancer`
8. Collect `deny` findings into `cost-deny.json`
9. Collect `warnings` into `cost-warn.json`
10. Write `cost-decision.txt`
11. If `deny_count > 0` → `DENY`, `exit 2`
12. If `deny_count == 0` → `ALLOW`, `exit 0`

When you fill `cost-decision.md`, the `Commit SHA` field does not mean you must commit or push. It records the current local `HEAD` that was used for the check:

```bash
git rev-parse HEAD
git status --short
```

If `git status --short` is not empty, record that explicitly in the decision:

```text
Working tree status: dirty, lesson 73 files modified locally
```

That makes the evidence clear later: it shows both the base commit and whether local uncommitted changes existed during the check.

---

## 8. Local Policy Drills

Run all policy tests:

```bash
lessons/73-cost-and-blast-radius-controls/policies/test-policy.sh
lessons/73-cost-and-blast-radius-controls/policies/test-cost-policy.sh
lessons/73-cost-and-blast-radius-controls/policies/test-opa.sh
```

Run individual examples:

```bash
lessons/73-cost-and-blast-radius-controls/policies/cost-policy.sh \
  lessons/73-cost-and-blast-radius-controls/policies/tests/cost-safe-plan.json \
  dev
```

Expected: `COST_POLICY_DECISION=ALLOW`.

```bash
lessons/73-cost-and-blast-radius-controls/policies/cost-policy.sh \
  lessons/73-cost-and-blast-radius-controls/policies/tests/cost-high-asg-plan.json \
  dev
```

Expected: `COST_POLICY_DECISION=DENY`.

```bash
lessons/73-cost-and-blast-radius-controls/policies/cost-policy.sh \
  lessons/73-cost-and-blast-radius-controls/policies/tests/cost-nat-plan.json \
  stage
```

Expected: `COST_POLICY_DECISION=ALLOW` with cost/blast-radius warnings present.

---

## 9. CI Model

`ci/lesson73-cost-guard.yml` is a template for GitHub Actions.

It intentionally does not assume AWS roles. The purpose is to prove the module and policies before wiring the gate into a real apply workflow.

Workflow checks:

1. Terraform format;
2. Packer format;
3. module native tests;
4. env root validation without remote state;
5. baseline plan policy tests;
6. cost policy tests;
7. optional OPA tests;
8. upload policy evidence.

In a real apply workflow the order should be:

```text
terraform plan
-> terraform show -json
-> security/change policy
-> cost/blast-radius policy
-> human approval
-> apply exact saved plan
```

---

## 10. Infracost Evidence

Infracost is useful for estimate evidence, but this lesson does not require it to pass local tests.

Check:

```bash
infracost auth whoami
```

For the proof pack, prefer scanning a concrete saved plan instead of the whole Terraform tree. This makes Infracost evaluate the exact `tfplan.json` that was reviewed:

```bash
terraform -chdir=lessons/73-cost-and-blast-radius-controls/lab_73/terraform/envs/dev \
  plan -input=false -no-color -out=tfplan

terraform -chdir=lessons/73-cost-and-blast-radius-controls/lab_73/terraform/envs/dev \
  show -json tfplan \
  > lessons/73-cost-and-blast-radius-controls/lab_73/terraform/envs/dev/tfplan.json

infracost scan lessons/73-cost-and-blast-radius-controls/lab_73/terraform/envs/dev/tfplan.json
```

Scanning the whole Terraform tree can run into local module boundary diagnostics. For an accurate check, use a diagnostics-free `tfplan.json` scan.

Security note: `infracost scan tfplan.json` sends plan metadata to the external Infracost service. Use it only for lab/non-sensitive plans or when Infracost is approved as a third-party vendor. Do not send plans that may contain secrets, customer data, or sensitive production metadata.

Save:

```bash
mkdir -p lessons/73-cost-and-blast-radius-controls/evidence/l73-cost-guard

infracost inspect --summary \
  > lessons/73-cost-and-blast-radius-controls/evidence/l73-cost-guard/infracost-summary.txt

infracost inspect --json \
  > lessons/73-cost-and-blast-radius-controls/evidence/l73-cost-guard/infracost.json

infracost inspect --failing \
  > lessons/73-cost-and-blast-radius-controls/evidence/l73-cost-guard/infracost-failing.txt

infracost inspect --top 10 \
  > lessons/73-cost-and-blast-radius-controls/evidence/l73-cost-guard/infracost-top.txt
```

Operational rule:

```text
Cost estimate is evidence, not an invoice.
```

Use Infracost as one signal. Keep `cost-policy.sh` as the deterministic pre-apply gate for known lab risks.

---

## 11. AWS Budgets

AWS Budgets are the billing-side safety net. They are useful, but they are not instant blockers for Terraform apply.

Run:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws budgets describe-budgets \
  --account-id "$ACCOUNT_ID" \
  --output table > budget.txt
```

Do redacted budget proof:

```bash
mkdir -p lessons/73-cost-and-blast-radius-controls/evidence/l73-cost-guard

cat > lessons/73-cost-and-blast-radius-controls/evidence/l73-cost-guard/aws-budget-proof-redacted.txt <<'EOF'
Checked: 2026-06-18
AWS account: redacted
Region: global billing service

Budget reviewed:
- Budget name:
- Budget type:
- Time unit:
- Monthly limit:
- Actual threshold:
- Forecasted threshold:
- Notification target: redacted

Decision:
- AWS Budget exists.
- Budget provides billing-side alerting.
- Budget is not an instant Terraform apply blocker.
- Lesson 73 still requires pre-apply cost policy checks.
EOF
```

This file does not prove the exact price of the `plan`. It proves the presence of a second protection layer:

```text
Pre-apply cost policy prevents known risky changes before apply.
Budget alerts tell you when real spending approaches limits.
```

Use both.

---

## 12. Quota Awareness

Cost is not the only limit. Quotas can stop or degrade a release.

Review at least one relevant quota:

| Area | Service code | What to review |
| --- | --- | --- |
| EC2 | `ec2` | On-Demand instances, Elastic IPs, AMIs, key pairs |
| VPC | `vpc` | VPCs, subnets, NAT gateways, internet gateways, security groups |
| Auto Scaling | `autoscaling` | Auto Scaling Groups, launch configurations |
| Load Balancing  | `elasticloadbalancing` | ALB/NLB/CLB, target groups, listeners, rules |
| EKS | `eks` | clusters, nodegroups, Fargate profiles |
| ECS | `ecs` | clusters, services, task definitions |
| Lambda | `lambda` | concurrent executions, function storage |
| RDS | `rds` | DB instances, clusters, snapshots, parameter groups |
| ElastiCache | `elasticache` | clusters, nodes, subnet groups |
| ECR | `ecr` | repositories, image scan quotas |
| CloudWatch Logs | `logs` | log groups, retention-related limits |
| CloudWatch | `cloudwatch` | alarms, dashboards, metrics |
| CloudFormation | `cloudformation` | stacks, stack sets, resources per stack |
| API Gateway | `apigateway` | APIs, stages, routes, throttling |
| SQS | `sqs` | queues, message throughput-related quotas |
| SNS | `sns` | topics, subscriptions |
| KMS | `kms` | keys, aliases, request quotas |
| Secrets Manager | `secretsmanager` | secrets, versions |
| Route 53 | `route53` | hosted zones, records |
| ACM | `acm` | certificates |
| S3 | `s3` | buckets, access points — but `list-service-quotas` may be sparse |

Check all service codes:

```bash
aws service-quotas list-services \
  --region eu-west-1 \
  --query 'Services[].{Name:ServiceName,Code:ServiceCode}' \
  --output table > codes.txt
```

Example:

```bash
aws service-quotas list-service-quotas \
  --service-code elasticloadbalancing \
  --region eu-west-1 \
  --output table

# Or:

aws service-quotas list-service-quotas \
  --service-code elasticloadbalancing \
  --region eu-west-1 \
  --query 'Quotas[?contains(QuotaName, `Application Load Balancers`) || contains(QuotaName, `Target Groups`) || contains(QuotaName, `Listeners`) || contains(QuotaName, `Rules`) || contains(QuotaName, `Certificates`)].{Name:QuotaName,Value:Value,Adjustable:Adjustable}' \
  --output table
```

Save the relevant output or a redacted summary in the proof pack.

---

## 13. Drills

Run all commands from the repository root. Use a separate `OUT_DIR` for each drill so results are not overwritten.

### Drill 1. Safe plan passes

Run `cost-safe-plan.json` against `dev`:

```bash
OUT_DIR=/tmp/l73-cost-safe-dev \
lessons/73-cost-and-blast-radius-controls/policies/cost-policy.sh \
  lessons/73-cost-and-blast-radius-controls/policies/tests/cost-safe-plan.json \
  dev
```

Expected:

- cost policy allows;
- no deny records.
- `/tmp/l73-cost-safe-dev/cost-decision.txt` contains `COST_POLICY_DECISION=ALLOW`.

### Drill 2. NAT in dev is denied

Run `cost-nat-plan.json` against `dev`:

```bash
set +e
OUT_DIR=/tmp/l73-cost-nat-dev \
lessons/73-cost-and-blast-radius-controls/policies/cost-policy.sh \
  lessons/73-cost-and-blast-radius-controls/policies/tests/cost-nat-plan.json \
  dev
rc=$?
echo "exit_code=${rc}"
set -e
```

Expected:

- cost policy denies;
- rule is `nat_gateway_cost_signal`.
- exit code `2`.

### Drill 3. NAT in stage warns

Run `cost-nat-plan.json` against `stage`:

```bash
OUT_DIR=/tmp/l73-cost-nat-stage \
lessons/73-cost-and-blast-radius-controls/policies/cost-policy.sh \
  lessons/73-cost-and-blast-radius-controls/policies/tests/cost-nat-plan.json \
  stage
```

Expected:

- cost policy allows;
- warning is visible in `cost-warn.json`.
- exit code `0`.

### Drill 4. High ASG max is denied

Run `cost-high-asg-plan.json` against `dev` and `prod`:

```bash
for env in dev prod; do
  set +e
  OUT_DIR="/tmp/l73-cost-high-asg-${env}" \
  lessons/73-cost-and-blast-radius-controls/policies/cost-policy.sh \
    lessons/73-cost-and-blast-radius-controls/policies/tests/cost-high-asg-plan.json \
    "${env}"
  rc=$?
  echo "${env}_exit_code=${rc}"
  set -e
done
```

Expected:

- both deny if `max_size` is above the environment limit.
- rule is `deny_asg_max_size_above_env_limit`.

### Drill 5. Large instance is denied

Run `cost-large-instance-plan.json`:

```bash
set +e
OUT_DIR=/tmp/l73-cost-large-instance \
lessons/73-cost-and-blast-radius-controls/policies/cost-policy.sh \
  lessons/73-cost-and-blast-radius-controls/policies/tests/cost-large-instance-plan.json \
  stage
rc=$?
echo "exit_code=${rc}"
set -e
```

Expected:

- rule is `deny_large_instance_type`.
- exit code `2`.

### Drill 6. Public ALB warns

Run `cost-public-lb-plan.json` against `prod`:

```bash
OUT_DIR=/tmp/l73-cost-public-lb-prod \
lessons/73-cost-and-blast-radius-controls/policies/cost-policy.sh \
  lessons/73-cost-and-blast-radius-controls/policies/tests/cost-public-lb-plan.json \
  prod
```

Expected:

- policy allows;
- warning requires reviewer attention.
- warning is stored in `/tmp/l73-cost-public-lb-prod/cost-warn.json`.

---

## 14. Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `jq is required` | `jq` is not installed | install `jq` before running policy scripts |
| Cost policy exits `2` | plan violates cost/blast rule | inspect `cost-deny.json` |
| NAT warning appears in stage/prod | expected behavior | document the reason and reviewer decision |
| Infracost unavailable | no token/account/tooling | mark it deferred and keep deterministic policy evidence |
| Quota output is too large | full service quota table copied | keep only relevant quota lines or summary |
| CI policy passes but apply would cost more | policy only catches modeled risks | add a new rule or require Infracost/budget review |
| Policy results were overwritten | multiple runs used the same `OUT_DIR` | use a separate `OUT_DIR` for each drill |
| `opa is required` | OPA is not installed locally | install OPA or run only `test-policy.sh` and `test-cost-policy.sh` |
| GitHub Actions workflow does not run | file stayed in `ci/` and was not copied to `.github/workflows/` | copy the template to `.github/workflows/lesson73-cost-guard.yml` |
| `git status` shows `artifacts/` or `cost-policy-results/` | generated outputs are not ignored | check `.gitignore` and do not commit operational artifacts |

---

## 15. Proof Pack

Use `proof-pack.en.md` as the checklist.

Minimum evidence:

- security policy test output;
- cost policy test output;
- safe plan allow;
- NAT dev deny;
- NAT stage/prod warning;
- ASG max deny;
- large instance deny;
- budget proof or deferral note;
- quota proof or summary;
- `cost-decision.md`.

---

## 16. Acceptance Criteria

Lesson 73 is complete when:

- cost policy script exists and is executable;
- cost policy tests pass;
- baseline security policy tests still pass;
- module tests pass;
- safe plan is allowed;
- ASG max-size deny works;
- large instance deny works;
- NAT behavior differs by environment;
- budget/quota evidence is documented;

---

## 17. Lesson Summary

- **What you learned:** safe Terraform delivery must control financial and operational impact, not only syntax and security.
- **What you practiced:** cost policy over `tfplan.json`, ASG/NAT/instance-type gates, warnings vs denies, budget and quota evidence.
- **Operational focus:** block expensive or wide-impact changes before approval and apply.
- **Why it matters:** a plan can be valid, approved, and still financially unsafe.
