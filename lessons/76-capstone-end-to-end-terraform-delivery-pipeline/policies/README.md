# Lesson 76 Policies

This folder contains the policy and review-decision scripts used by the capstone pipeline.

## Layers

| Script | Role | Blocks apply directly? |
| --- | --- | --- |
| `security-policy.sh` | Security/change guardrails for Terraform JSON plans. | Yes, on security DENY. |
| `cost-policy.sh` | Cost and blast-radius guardrails for Terraform JSON plans. | Yes, on cost DENY. |
| `risk-classifier.sh` | Final apply risk decision from plan, policy outputs, target env, promotion evidence, and incident mode. | Yes, when final risk is `BLOCKED`. |
| `opa/terraform.rego` | Optional OPA/Rego parity checks for selected security rules. | Only when used by `test-opa.sh` or CI. |

## Security Policy

`security-policy.sh` catches security and change-management risks:

- destructive changes without explicit exception;
- public ingress;
- missing required tags;
- NAT/public ALB warnings.

Outputs:

```text
policy-decision.txt
policy-deny.json
policy-warn.json
```

## Cost Policy

`cost-policy.sh` catches financial and scale risks:

- ASG `max_size` above environment limit;
- NAT Gateway denied in `dev` and warned in `stage/prod`;
- oversized instance types denied;
- public ALB warned as a blast-radius signal.

It is deterministic by design. It does not calculate exact AWS cost. It checks known risky patterns in Terraform JSON plan output and writes a decision plus machine-readable evidence.

Outputs:

```text
cost-decision.txt
cost-deny.json
cost-warn.json
```

## Risk Classifier

`risk-classifier.sh` combines the lower-level outputs with environment context:

- `tfplan.json` action counts;
- security policy deny/warn files;
- cost policy deny/warn files;
- target environment: `dev`, `stage`, `prod`;
- promotion evidence for `stage`/`prod`;
- incident mode and incident record.

Possible final decisions:

```text
NO_CHANGE
LOW
MEDIUM
HIGH
EMERGENCY
BLOCKED
```

Precedence:

```text
BLOCKED > EMERGENCY > HIGH > MEDIUM > LOW > NO_CHANGE
```

Outputs:

```text
risk-decision.json
risk-decision.md
```

## Test Runners

Run from repo root:

```bash
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/policies/test-security-policy.sh
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/policies/test-cost-policy.sh
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/policies/test-risk-classifier.sh
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/policies/test-opa.sh
```

`test-opa.sh` is optional and requires `opa`.

## Manual Examples

Run one security fixture manually:

```bash
OUT_DIR=/tmp/l76-security-policy \
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/policies/security-policy.sh \
  lessons/76-capstone-end-to-end-terraform-delivery-pipeline/policies/tests/public-ingress-plan.json
```

Expected: `POLICY_DECISION=DENY`.

Run one cost fixture manually:

```bash
OUT_DIR=/tmp/l76-cost-policy \
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/policies/cost-policy.sh \
  lessons/76-capstone-end-to-end-terraform-delivery-pipeline/policies/tests/cost-high-asg-plan.json \
  dev
```

Expected: `COST_POLICY_DECISION=DENY`.

Run risk classification manually after security and cost outputs exist:

```bash
POLICY_DIR=/tmp/l76-security-policy \
COST_DIR=/tmp/l76-cost-policy \
OUT_DIR=/tmp/l76-risk \
REQUIRE_PROMOTION_EVIDENCE=false \
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/policies/risk-classifier.sh \
  lessons/76-capstone-end-to-end-terraform-delivery-pipeline/policies/tests/cost-high-asg-plan.json \
  dev
```

Important: `security-policy.sh`, `cost-policy.sh`, and `risk-classifier.sh` default to writing outputs in the current directory or their default result directories. For manual drills, set `OUT_DIR` explicitly so generated evidence does not land in the wrong folder.
