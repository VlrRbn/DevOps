# Lesson 62: Terraform Quality Gates & Policy Baseline

## Purpose

This lesson adds a practical pre-apply quality layer on top of lessons 60-61.

You already have:

- remote state and locking
- safe refactors and state surgery

Now you add:

- formatting gate
- validation gate
- linting gate
- misconfiguration/security gate
- CI shape for Terraform quality checks

## Prerequisites

- lesson 60 completed
- lesson 61 completed
- Terraform env available in `lab_62/terraform/envs`
- AWS CLI + Terraform configured
- `tflint` and `checkov` installed locally when running the drills

## Layout

- `lesson.en.md`
  - full lesson flow (EN)
- `lesson.ru.md`
  - full lesson flow (RU)
- `proof-pack.en.md`
  - evidence collection pattern (EN)
- `proof-pack.ru.md`
  - evidence collection pattern (RU)
- `checkov.yaml`
  - baseline Checkov config for the lesson
- `ci/terraform-quality-gates.yml`
  - example GitHub Actions workflow for Terraform quality gates
- `lab_62/terraform/.tflint.hcl`
  - TFLint config for the lesson lab

## Quick Start

```bash
cd lessons/62-terraform-quality-gates/lab_62/terraform

terraform fmt -check -recursive
terraform -chdir=envs init -backend=false
terraform -chdir=envs validate

tflint --chdir=envs --init
tflint --chdir=envs -f compact

checkov -d . --framework terraform --config-file ../../checkov.yaml
```

## Notes

- Keep CI examples in the lesson folder first; promote to `.github/workflows/` deliberately.
- Raw proof folders usually stay local; commit only redacted or public-safe evidence.
- This lesson is a baseline quality gate, not a full policy platform.
