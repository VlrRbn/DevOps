# Lesson 66 - Module Contracts & Interface Guarantees

This lesson turns Terraform lab_65 into a contract-driven module.

The goal is not to add more infrastructure. The goal is to make the module safer to consume by defining what inputs are accepted, what outputs are stable, and which changes are breaking.

## Files

- `lesson.en.md` - English lesson walkthrough
- `lesson.ru.md` - Russian lesson walkthrough
- `proof-pack.en.md` - evidence checklist in English
- `proof-pack.ru.md` - evidence checklist in Russian
- `lab_66/terraform/modules/network/README.md` - module contract reference
- `lab_66/terraform/modules/network/variables.tf` - input validations
- `lab_66/terraform/modules/network/asg.tf` - runtime preconditions
- `lab_66/terraform/modules/network/outputs.tf` - output guarantees
- `.github/workflows/lesson66-contract-tests.yml` - CI gate for static contract checks

## Lab Focus

- Terraform variable validation
- Cross-variable capacity validation
- Lifecycle preconditions
- Output preconditions
- Stable module outputs for automation consumers
- Required governance tags that callers cannot override
- Breaking vs non-breaking module changes

## Quick Start

From repo root:

```bash
cd lessons/66-module-contracts-and-interface-guarantees/lab_66/terraform/envs
cp terraform.tfvars.example terraform.tfvars
cp backend.hcl.example backend.hcl
```

Edit:

- `terraform.tfvars`
- `backend.hcl`

Then:

```bash
terraform init -reconfigure -backend-config=backend.hcl
terraform fmt -recursive
terraform validate
terraform plan -no-color
```

## Contract Drills

The lesson intentionally asks to break the contract with temporary `contract-drill.auto.tfvars` files:

- invalid `project_name`
- only one private subnet
- too many private subnets
- invalid AMI ID
- empty tag value
- reserved governance tag override

These files are ignored by `lab_66/terraform/envs/.gitignore`.

## CI Contract Gate

The CI workflow for this lesson is intentionally AWS-free:

- runs `terraform fmt -check -diff -recursive`
- runs `terraform init -backend=false`
- runs `terraform validate`
- runs the negative input drills and expects Terraform to fail with contract-friendly validation messages
- uploads short-lived failed-plan transcripts for debugging

It does not replace the manual proof pack. The workflow proves that the module contract rejects bad input without requiring AWS credentials. The manual proof pack still proves the real AWS-backed lab behavior.

In the real `envs` root, `terraform plan` may still contact the remote backend or read data sources before showing a validation error. The contract guarantee is that bad input fails before `apply` and before infrastructure changes.

## Safety

- Do not commit `terraform.tfvars`, `backend.hcl`, local state, or plan files.
- This lesson still reuses the private runtime pattern from earlier lessons, including SSM proxy and internal ALB.
- Secret values are not part of this lesson's contract surface; only secret names/metadata are exposed.
