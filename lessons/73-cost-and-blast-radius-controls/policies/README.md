# Lesson 73 Policies

This folder contains two policy layers:

- `terraform-plan-policy.sh` - baseline security/change policy from previous lessons.
- `cost-policy.sh` - lesson 73 cost and blast-radius policy.

The baseline policy catches security and change-management risks:

- destructive changes without explicit exception;
- public ingress;
- missing required tags;
- NAT/public ALB warnings.

The cost policy catches lesson-specific financial and scale risks:

- ASG `max_size` above environment limit;
- NAT Gateway denied in `dev` and warned in `stage/prod`;
- oversized instance types denied;
- public ALB warned as a blast-radius signal.

`cost-policy.sh` is deterministic by design. It does not calculate exact AWS cost. It checks known risky patterns in Terraform JSON plan output and writes a decision plus machine-readable evidence.

Run from repo root:

```bash
lessons/73-cost-and-blast-radius-controls/policies/test-policy.sh
lessons/73-cost-and-blast-radius-controls/policies/test-cost-policy.sh
lessons/73-cost-and-blast-radius-controls/policies/test-opa.sh
```

Run one cost fixture manually:

```bash
lessons/73-cost-and-blast-radius-controls/policies/cost-policy.sh \
  lessons/73-cost-and-blast-radius-controls/policies/tests/cost-high-asg-plan.json \
  dev
```

Expected: `COST_POLICY_DECISION=DENY`.

Generated outputs:

```text
cost-policy-results/
  cost-decision.txt
  cost-deny.json
  cost-warn.json
```

Use `OUT_DIR=/tmp/some-dir` when running multiple examples so outputs do not overwrite each other.
