# Lesson 66 Proof Pack

Use this proof pack to show that the module contract works and that contract failures are understandable.

Run from:

```bash
cd lessons/66-module-contracts-and-interface-guarantees/lab_66/terraform/envs
```

Create an evidence folder:

```bash
export EVIDENCE_DIR="../../../evidence/l66-$(date +%Y%m%d_%H%M%S)"
mkdir -p "$EVIDENCE_DIR"
```

## 1. Baseline Validation

```bash
terraform fmt -check -recursive .. > "$EVIDENCE_DIR/fmt.txt" 2>&1
terraform validate -no-color > "$EVIDENCE_DIR/validate.txt" 2>&1
terraform plan -no-color > "$EVIDENCE_DIR/baseline-plan.txt" 2>&1
```

Expected:

- fmt passes
- validate passes
- plan is readable
- baseline plan can show creates if the lab is not applied yet
- temporary `contract-drill.auto.tfvars` is absent
- no plaintext secret values appear in outputs

## 2. Bad Project Name

```bash
cat > contract-drill.auto.tfvars <<'EOF'
project_name = "LAB_66"
EOF

terraform plan -no-color > "$EVIDENCE_DIR/bad-project-name-plan.txt" 2>&1 || true
rm -f contract-drill.auto.tfvars
```

Expected:

- Terraform rejects the value before apply.
- Error explains the expected lowercase kebab-style format.

## 3. Too Few Private Subnets

```bash
cat > contract-drill.auto.tfvars <<'EOF'
private_subnet_cidrs = ["10.30.11.0/24"]
EOF

terraform plan -no-color > "$EVIDENCE_DIR/one-subnet-plan.txt" 2>&1 || true
rm -f contract-drill.auto.tfvars
```

Expected:

- Terraform rejects the value before apply.
- Error explains that at least two private subnet CIDRs are required.

## 4. Too Many Private Subnets

```bash
cat > contract-drill.auto.tfvars <<'EOF'
private_subnet_cidrs = [
  "10.30.11.0/24",
  "10.30.12.0/24",
  "10.30.13.0/24",
  "10.30.14.0/24",
  "10.30.15.0/24",
  "10.30.16.0/24",
  "10.30.17.0/24",
]
EOF

terraform plan -no-color > "$EVIDENCE_DIR/too-many-subnets-plan.txt" 2>&1 || true
rm -f contract-drill.auto.tfvars
```

Expected:

- Terraform rejects the value before apply.
- Error explains the supported 2-6 subnet contract.

## 5. Bad AMI ID

```bash
cat > contract-drill.auto.tfvars <<'EOF'
web_ami_id = "ubuntu-latest"
EOF

terraform plan -no-color > "$EVIDENCE_DIR/bad-ami-id-plan.txt" 2>&1 || true
rm -f contract-drill.auto.tfvars
```

Expected:

- Terraform rejects the value before apply.
- Error explains the required AMI ID shape.

## 6. Empty Tag Value

```bash
cat > contract-drill.auto.tfvars <<'EOF'
common_tags = {
  Owner = ""
}
EOF

terraform plan -no-color > "$EVIDENCE_DIR/empty-tag-plan.txt" 2>&1 || true
rm -f contract-drill.auto.tfvars
```

Expected:

- Terraform rejects empty tag values.

## 7. Reserved Tag Override

```bash
cat > contract-drill.auto.tfvars <<'EOF'
common_tags = {
  Project = "manual"
}
EOF

terraform plan -no-color > "$EVIDENCE_DIR/reserved-tag-plan.txt" 2>&1 || true
rm -f contract-drill.auto.tfvars
```

Expected:

- Terraform rejects caller attempts to override reserved governance tags.

## 8. Output Contract Review

Create:

```bash
cat > "$EVIDENCE_DIR/output-contract.md" <<'EOF'
| Output | Consumer | Stability |
|---|---|---|
| alb_dns_name | SSM proxy curl tests | stable |
| web_asg_name | release workflows | stable |
| web_tg_arn | health/drift workflows | stable |
| ssm_vpc_endpoint_ids | private runtime proof | stable map keyed by service |
EOF
```

Expected:

- Each public output has a known consumer.
- No output exposes a whole resource or plaintext secret value.

## 9. Final Baseline Plan

```bash
terraform plan -no-color > "$EVIDENCE_DIR/baseline-plan-after-fixes.txt" 2>&1
```

Expected:

- No temporary drill file is left behind.
- Baseline plan is readable.
- Baseline plan can show creates if the lab is not applied yet.
- Module contract rejects invalid inputs before infrastructure changes.

## 10. CI Contract Gate

Check the GitHub Actions run for `.github/workflows/lesson66-contract-tests.yml`.

Expected:

- Terraform formatting passed.
- Backend-less init and validate passed.
- Negative input drills failed with expected validation messages.
- No AWS credentials were required.

## 11. Decision

Create:

```bash
cat > "$EVIDENCE_DIR/decision.txt" <<'EOF'
Decision: PASS
Lesson: 66-module-contracts-and-interface-guarantees

Evidence:
- variable validation rejects invalid caller input
- ASG preconditions document runtime assumptions
- outputs are stable and documented
- reserved governance tags cannot be overridden by callers
- breaking/non-breaking module change policy is documented
- CI contract gate checks the same negative input behavior
EOF
```
