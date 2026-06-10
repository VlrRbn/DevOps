# Lesson 70. Policy as Code on Terraform JSON Plan

**Date:** 2026-06-05

**Focus:** evaluate a saved Terraform plan as structured data and block risky changes before apply.

**Main idea:** humans review context; policy catches repeatable mistakes. If a rule is objective, put it in code.

---

## Why This Lesson Exists

Lesson 68 built a controlled apply pipeline.

Lesson 69 split GitHub Actions into separate plan/apply IAM roles.

Lesson 70 adds the next guardrail: a policy layer over `tfplan.json`.

The pipeline already knows how to create a saved plan:

```bash
terraform plan -out=tfplan
terraform show -json tfplan > tfplan.json
```

Now the plan must pass policy before the approved apply job can run.

This lesson work with `jq` because it is explicit, portable, and easy to debug in CI logs. OPA/Rego is introduced as the next step once the team outgrows shell policy checks.

References:

- Terraform JSON plan format: https://developer.hashicorp.com/terraform/internals/json-format
- `terraform show -json`: https://developer.hashicorp.com/terraform/cli/commands/show
- OPA Terraform guide: https://www.openpolicyagent.org/docs/terraform
- Rego policy language: https://www.openpolicyagent.org/docs/policy-language
- Conftest: https://www.conftest.dev/

---

## Outcomes

After this lesson you should be able to:

- generate `tfplan.json` from a saved Terraform plan
- read `.resource_changes[]` and `.change.actions`
- detect deletes and replacements reliably
- block public ingress in standalone and inline security group rules
- require non-empty governance tags on taggable resources
- separate hard denies from warnings
- allow a destructive exception only by exact Terraform address
- upload policy evidence with the plan artifact
- explain where jq policy ends and OPA/Rego begins

---

## Repo Layout

```text
lessons/70-policy-as-code-terraform-json-plan/
├── lesson.en.md
├── lesson.ru.md
├── README.md
├── proof-pack.en.md
├── proof-pack.ru.md
├── ci/
│   └── lesson70-terraform-apply-dev.yml
├── policies/
│   ├── terraform-plan-policy.sh
│   ├── test-policy.sh
│   ├── test-opa.sh
│   ├── allow-destroy.example.json
│   ├── opa/
│   │   └── terraform.rego
│   └── tests/
│       ├── safe-plan.json
│       ├── destroy-plan.json
│       ├── replacement-plan.json
│       ├── public-ingress-plan.json
│       ├── public-ingress-inline-sg-plan.json
│       ├── public-egress-plan.json
│       ├── missing-tags-plan.json
│       ├── empty-tags-plan.json
│       ├── warn-plan.json
│       ├── no-op-warn-plan.json
│       ├── allow-destroy-wrong-address.json
│       ├── allow-destroy-invalid-wildcard.json
│       └── allow-destroy-expired.json
└── lab_70/
    ├── packer/
    └── terraform/
```

---

## A) Terraform JSON Plan Model

The most important field is:

```jq
.resource_changes[]
```

A resource change contains the Terraform address, resource type, and action list:

```json
{
  "address": "module.network.aws_lb.app",
  "mode": "managed",
  "type": "aws_lb",
  "change": {
    "actions": ["update"],
    "before": {},
    "after": {}
  }
}
```

Common action shapes:

| Actions | Meaning | Policy treatment |
| --- | --- | --- |
| `["no-op"]` | no change | ignore |
| `["create"]` | new resource | inspect attributes |
| `["update"]` | in-place update | inspect changed attributes if needed |
| `["delete"]` | destroy | deny by default |
| `["delete", "create"]` | replacement | deny by default |
| `["create", "delete"]` | create-before-destroy replacement | deny by default |

Core rule:

```text
if actions contains "delete" => destructive change
```

Why is that?

Because a `replacement` also contains `delete`:

```text
"actions": ["delete", "create"]
```

That means the policy must not check only exact equality:

```text
actions == ["delete"]
```

It must check:

```text
actions contains "delete"
```

That catches both direct destroys and replacements.

---

## B) Policy Levels

Not every finding should block apply.

Use three levels:

| Level | Meaning | Examples |
| --- | --- | --- |
| `deny` | block apply | destroy, public ingress, missing or empty required tags |
| `warn` | allow but record | new or updated NAT gateway, ASG max size, public ALB |
| `info` | evidence only | changed resource count, plan timestamp |

Lesson 70 implements:

**Deny:**

- destructive changes unless exact address is approved
- public ingress from `0.0.0.0/0` or `::/0`
- missing or empty required tags: `Project`, `Environment`, `ManagedBy`

Public ingress is checked in two Terraform models:

- standalone rule resources: `aws_security_group_rule` with `type = "ingress"` and `aws_vpc_security_group_ingress_rule`
- inline `ingress` blocks inside `aws_security_group`

Outbound/egress rules to `0.0.0.0/0` are not blocked by this rule. That is a separate policy concern, not public ingress.

**Warn:**

- new or updated NAT gateway
- new or updated ASG with `max_size > 4`
- new or updated public ALB

Warning rules intentionally ignore `no-op` resources so accepted existing risk does not create noisy release warnings.

Difference:

```text
deny  -> workflow fails, apply must not be performed
warn  -> workflow does not fail, but a human must see the warning
```

---

## C) Run the Local Policy Tests

From repo root:

```bash
lessons/70-policy-as-code-terraform-json-plan/policies/test-policy.sh
# Optional, if opa is installed:
lessons/70-policy-as-code-terraform-json-plan/policies/test-opa.sh
```

Expected mandatory output:

```text
policy tests passed
```

Optional OPA output, if `opa` is installed:

```text
opa policy tests passed
```

The test runner checks fixture plans:

| Fixture | Expected result |
| --- | --- |
| `safe-plan.json` | allow |
| `warn-plan.json` | allow with warnings |
| `no-op-warn-plan.json` | allow without warnings |
| `destroy-plan.json` | deny |
| `replacement-plan.json` | deny |
| `public-ingress-plan.json` | deny |
| `public-ingress-inline-sg-plan.json` | deny |
| `public-egress-plan.json` | allow |
| `missing-tags-plan.json` | deny |
| `empty-tags-plan.json` | deny |
| wrong destroy exception | deny |
| wildcard destroy exception | input error |
| expired destroy exception | input error |

This gives you fast feedback without creating AWS resources.

Main script flow:

```text
1. check that jq is installed
2. check that tfplan.json exists
3. if ALLOW_DESTROY_FILE exists, validate its format and expiry
4. find destructive changes
5. apply destroy exceptions, if any
6. find public ingress
7. find missing or empty tags
8. find warnings
9. build deny list
10. build warn list
11. make the final decision: ALLOW or DENY
```

Decision Tree:

```text
Read tfplan.json
│
├─ Validate jq exists
├─ Validate plan file exists
├─ Validate optional allow-destroy file
│   └─ Reject malformed, expired, empty, or wildcard exceptions
│
├─ Find destructive changes
│   └─ Remove explicitly allowed destructive addresses
│
├─ Find public ingress in standalone SG rules
│   └─ aws_security_group_rule is checked only when type == "ingress"
├─ Find public ingress in inline aws_security_group ingress
├─ Find resources missing required tags or empty tag values
│
├─ Find warning signals only for create/update actions:
│   ├─ NAT Gateway
│   ├─ ASG max_size > 4
│   └─ public Load Balancer
│
├─ Merge deny findings
├─ Merge warning findings
│
├─ If deny_count > 0:
│   └─ DENY, exit 2
│
└─ Else:
    └─ ALLOW, print warnings if any, exit 0
```

---

## D) Generate a Real Terraform JSON Plan

Use the copied lab when you want to test against real Terraform output.

From env directory:

```bash
cd lessons/70-policy-as-code-terraform-json-plan/lab_70/terraform/envs
terraform init -reconfigure -backend-config=backend.hcl
terraform plan -out=tfplan
terraform show -no-color tfplan > tfplan.txt
terraform show -json tfplan > tfplan.json
```

Run policy:

```bash
OUT_DIR=policy-results ../../../policies/terraform-plan-policy.sh tfplan.json
```

Expected short console output:

```text
POLICY_DECISION=ALLOW
deny_count=0
warn_count=0
policy_results_dir=policy-results
```

If there is a `deny`, the script prints the same summary plus JSON with the deny findings. Details are always written under `policy-results/`.

Read the decision:

```bash
cat policy-results/policy-decision.txt
jq . policy-results/policy-deny.json
jq . policy-results/policy-warn.json
```

Exit code meaning:

| Exit code | Meaning |
| --- | --- |
| `0` | policy allowed the plan |
| `1` | script/input error |
| `2` | policy denied the plan |

The difference between `1` and `2` is useful:

```text
1 = we started the check incorrectly
2 = the check started correctly and found a forbidden change
```

---

## E) Destructive Exceptions

Destroy/replacement is denied by default.

Example of a `destructive rule`

In the script, the logic is:

```json
.resource_changes[]?
| select(.mode == "managed")
| select(.change.actions | index("delete"))
```

The key part is `index("delete")`, and it catches all destructive variants.

The result is written to `destructive.json`.

```text
.resource_changes[]?
| select(.mode == "managed")
| select(.change.actions | index("delete"))
```

If a planned destructive change is intentional, use an exception file with exact Terraform addresses:

```json
{
  "reason": "retire obsolete alarm after incident review",
  "approved_by": "CHANGE-1234",
  "expires": "2099-12-31",
  "allowed_addresses": [
    "module.network.aws_cloudwatch_metric_alarm.old_alarm"
  ]
}
```

Run:

```bash
ALLOW_DESTROY_FILE=../../../policies/allow-destroy.example.json \
OUT_DIR=policy-results \
../../../policies/terraform-plan-policy.sh tfplan.json
```

Rules for exceptions:

- use exact addresses, not wildcards
- keep an approval reference
- keep an expiry date
- save the exception file in the proof pack
- remove the exception after the change is complete

The script validates exception metadata before applying it. A missing file, empty metadata, invalid expiry date, empty address list, or wildcard address is an input error, not a policy allow.

Exception files are not a bypass for normal review. They make the risk explicit and auditable.

---

## F) CI Integration

The correct order is:

1. checkout
2. fmt/test/validate
3. assume plan role
4. generate `tfplan`
5. generate `tfplan.json`
6. run policy
7. upload plan + policy artifacts
8. approve GitHub Environment
9. assume apply role
10. apply the exact saved `tfplan`
11. run post-apply drift check

The important design point: approval happens after the plan and policy artifacts exist.

Lesson file:

```text
lessons/70-policy-as-code-terraform-json-plan/ci/lesson70-terraform-apply-dev.yml
```

Policy step inside the plan job:

```bash
mkdir -p policy-results
OUT_DIR=policy-results ../../../policies/terraform-plan-policy.sh tfplan.json 2>&1 | tee policy-results/policy-output.txt
```

The apply job must use the exact binary `tfplan` artifact from the approved plan job. Do not run a fresh plan after approval and call that “approved”.

---

## G) What This Policy Does Not Solve

Policy over `tfplan.json` is powerful, but not magic.

It does not replace:

- least-privilege IAM
- GitHub Environment approval
- drift detection
- post-apply checks
- human review of `tfplan.txt`
- service-specific release gates

It is a mechanical guardrail between plan and apply.

---

## H) Optional OPA/Rego Path

The jq policy is the primary implementation for this lesson.

OPA/Rego becomes useful when:

- policy rules grow beyond shell readability
- multiple repos need the same policy library
- you want structured unit tests for policy rules
- security/platform teams own policy separately from application code

Optional example:

```text
lessons/70-policy-as-code-terraform-json-plan/policies/opa/terraform.rego
```

The example uses modern Rego v1 syntax: `deny contains msg if { ... }`. The older `deny[msg] { ... }` style may fail on newer OPA versions or require compatibility mode. Run `policies/test-opa.sh` to verify the optional Rego against the lesson fixtures.

If `conftest` is installed:

```bash
conftest test tfplan.json --policy ../../../policies/opa --namespace terraform.plan
```

Use OPA only when the policy surface is large enough to justify the extra language and tooling.

---

## I) Drills

### Drill 1. Safe Plan Allows

```bash
OUT_DIR=/tmp/l70-safe lessons/70-policy-as-code-terraform-json-plan/policies/terraform-plan-policy.sh \
  lessons/70-policy-as-code-terraform-json-plan/policies/tests/safe-plan.json
cat /tmp/l70-safe/policy-decision.txt
```

Expected:

```text
POLICY_DECISION=ALLOW
```

### Drill 2. Destroy Blocks

```bash
set +e
OUT_DIR=/tmp/l70-destroy lessons/70-policy-as-code-terraform-json-plan/policies/terraform-plan-policy.sh \
  lessons/70-policy-as-code-terraform-json-plan/policies/tests/destroy-plan.json
echo $?
set -e
jq . /tmp/l70-destroy/policy-deny.json
```

Expected exit code: `2`.

### Drill 3. Public Ingress Blocks

```bash
set +e
OUT_DIR=/tmp/l70-public lessons/70-policy-as-code-terraform-json-plan/policies/terraform-plan-policy.sh \
  lessons/70-policy-as-code-terraform-json-plan/policies/tests/public-ingress-plan.json
echo $?
set -e
jq . /tmp/l70-public/policy-deny.json
```

Expected rule: `deny_public_ingress`.

Additional check: public egress must not be blocked by the ingress rule.

```bash
OUT_DIR=/tmp/l70-egress lessons/70-policy-as-code-terraform-json-plan/policies/terraform-plan-policy.sh \
  lessons/70-policy-as-code-terraform-json-plan/policies/tests/public-egress-plan.json
cat /tmp/l70-egress/policy-decision.txt
```

Expected: `POLICY_DECISION=ALLOW`.

### Drill 4. Missing Or Empty Tags Block

```bash
set +e
OUT_DIR=/tmp/l70-tags lessons/70-policy-as-code-terraform-json-plan/policies/terraform-plan-policy.sh \
  lessons/70-policy-as-code-terraform-json-plan/policies/tests/missing-tags-plan.json
echo $?
set -e
jq . /tmp/l70-tags/policy-deny.json
```

Expected rule: `deny_missing_required_tags`.

Additional check: the tag key exists, but the value is empty.

```bash
set +e
OUT_DIR=/tmp/l70-empty-tags lessons/70-policy-as-code-terraform-json-plan/policies/terraform-plan-policy.sh \
  lessons/70-policy-as-code-terraform-json-plan/policies/tests/empty-tags-plan.json
echo $?
set -e
jq . /tmp/l70-empty-tags/policy-deny.json
```

Expected rule: `deny_missing_required_tags`.

### Drill 5. Warning Does Not Block

```bash
OUT_DIR=/tmp/l70-warn lessons/70-policy-as-code-terraform-json-plan/policies/terraform-plan-policy.sh \
  lessons/70-policy-as-code-terraform-json-plan/policies/tests/warn-plan.json
cat /tmp/l70-warn/policy-decision.txt
jq . /tmp/l70-warn/policy-warn.json
```

Expected:

- exit code `0`
- `POLICY_DECISION=ALLOW`
- warning exists

### Drill 6. Exact Destroy Exception

```bash
ALLOW_DESTROY_FILE=lessons/70-policy-as-code-terraform-json-plan/policies/allow-destroy.example.json \
OUT_DIR=/tmp/l70-destroy-allowed \
lessons/70-policy-as-code-terraform-json-plan/policies/terraform-plan-policy.sh \
  lessons/70-policy-as-code-terraform-json-plan/policies/tests/destroy-plan.json
cat /tmp/l70-destroy-allowed/policy-decision.txt
jq . /tmp/l70-destroy-allowed/policy-deny.json
```

Expected:

- `POLICY_DECISION=ALLOW`
- empty deny array

### Drill 7. Wildcard Destroy Exception Fails

```bash
set +e
ALLOW_DESTROY_FILE=lessons/70-policy-as-code-terraform-json-plan/policies/tests/allow-destroy-invalid-wildcard.json \
OUT_DIR=/tmp/l70-invalid-exception \
lessons/70-policy-as-code-terraform-json-plan/policies/terraform-plan-policy.sh \
  lessons/70-policy-as-code-terraform-json-plan/policies/tests/destroy-plan.json
echo $?
set -e
```

Expected:

- exit code `1`
- no policy allow
- error explains that wildcard addresses are invalid

### Drill 8. Expired Destroy Exception Fails

```bash
set +e
ALLOW_DESTROY_FILE=lessons/70-policy-as-code-terraform-json-plan/policies/tests/allow-destroy-expired.json \
OUT_DIR=/tmp/l70-expired-exception \
lessons/70-policy-as-code-terraform-json-plan/policies/terraform-plan-policy.sh \
  lessons/70-policy-as-code-terraform-json-plan/policies/tests/destroy-plan.json
echo $?
set -e
```

Expected:

- exit code `1`
- no policy allow
- error explains that the exception is expired

---

## Proof Pack

Save evidence under an ignored folder such as:

```text
lessons/70-policy-as-code-terraform-json-plan/evidence/l70-YYYYmmdd_HHMMSS/
```

Minimum evidence:

- `tfplan.txt`
- `tfplan.json`
- `policy-decision.txt`
- `policy-output.txt`
- `policy-deny.json`
- `policy-warn.json`
- `destructive.json`
- `missing-tags.json`
- `public-ingress-rules.json`
- `plan job URL` or screenshot
- `apply approval result` if CI was used

Use `proof-pack.en.md` as the checklist.

---

## Common Mistakes

- Running policy on `terraform plan` text instead of JSON.
- Grepping for `destroy` in `tfplan.txt` and missing replacements.
- Treating an empty required tag value as a valid tag.
- Blocking public egress with a public ingress rule.
- Approving the workflow before the final `tfplan` exists.
- Running a fresh plan in the apply job instead of applying the approved binary plan.
- Treating warnings as invisible because they do not block.
- Allowing destroy by broad wildcard instead of exact Terraform address.
- Not checking destroy exception expiry against the current UTC date.
- Treating an invalid exception file as an approval instead of failing the policy input.
- Forgetting that `terraform show -json tfplan` can contain sensitive values depending on resources and provider behavior.

---

## Final Acceptance

You are done when:

- [ ] local policy tests pass
- [ ] a real or fixture plan produces `policy-decision.txt`
- [ ] deny rules block expected bad plans
- [ ] warning rules are visible but non-blocking
- [ ] CI template uploads policy artifacts with the plan
- [ ] explain why policy runs before environment approval/apply

---

## Lesson Summary

- **What you learned:** Terraform plans are structured data, not just text for humans.
- **What you practiced:** JSON plan generation, jq policy checks, deny/warn decisions, exact destroy exceptions.
- **Operational skill:** turn repeated review rules into automated gates before apply.
- **CI focus:** plan first, policy second, approval third, apply the exact approved artifact.
