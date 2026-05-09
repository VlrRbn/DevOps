# Lesson 63: Terraform CI Plan Pipeline

## Purpose

This lesson extends lessons 60-62:

- lesson 60 gave you remote state and locking
- lesson 61 taught safe state hygiene and refactors
- lesson 62 added pre-apply quality gates
- lesson 63 adds a PR-safe Terraform plan pipeline

The goal is to show infrastructure impact before merge without giving CI the power to apply.

## Included Files

- `lesson.en.md`
  - full lesson flow in English
- `lesson.ru.md`
  - full lesson flow in Russian
- `proof-pack.en.md`
  - evidence collection pattern in English
- `proof-pack.ru.md`
  - evidence collection pattern in Russian
- `ci/terraform-plan-pr.yml`
  - lesson-local GitHub Actions example
- `lab_63/terraform/.tflint.hcl`
  - TFLint config used by the lab

## Quick Start

```bash
cd lessons/63-terraform-ci-plan-pipeline/lab_63/terraform

terraform fmt -check -recursive
terraform -chdir=envs init -backend=false
terraform -chdir=envs validate

tflint --chdir=envs --config=../.tflint.hcl --init
tflint --chdir=envs --config=../.tflint.hcl -f compact

checkov -d . --framework terraform --config-file ../../checkov.yaml
```

## Notes

- Keep the workflow next to the lesson first; copy it into `.github/workflows/` deliberately when ready.
- CI should plan only, never apply.
- Raw CI evidence usually stays local; commit only redacted or public-safe proof when needed.
