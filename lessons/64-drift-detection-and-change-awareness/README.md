# Lesson 64: Drift Detection & Change Awareness

## Purpose

This lesson extends the Terraform delivery chain from lessons 60-63:

- lesson 60 gave remote state and locking
- lesson 61 covered safe state refactors
- lesson 62 added pre-apply quality gates
- lesson 63 added a PR plan pipeline
- lesson 64 checks whether deployed AWS reality still matches `main`

The goal is to detect drift early, store evidence, and choose a clear triage path without auto-applying from CI.

## Files

- `lesson.en.md`
  - full lesson flow in English
- `lesson.ru.md`
  - full lesson flow in Russian
- `proof-pack.en.md`
  - evidence collection pattern in English
- `proof-pack.ru.md`
  - evidence collection pattern in Russian
- `ci/terraform-drift.yml`
  - lesson-local GitHub Actions workflow example
- `lab_64/terraform/`
  - Terraform lab copied forward from `lab_63` and renamed to `lab_64`

## Quick Start

```bash
cd lessons/64-drift-detection-and-change-awareness/lab_64/terraform

terraform fmt -check -recursive
terraform -chdir=envs init -backend=false
terraform -chdir=envs validate

terraform -chdir=envs init -reconfigure -backend-config=backend.hcl
terraform -chdir=envs plan -detailed-exitcode -no-color
```

Exit code meaning:

- `0` means no drift
- `1` means pipeline/backend/provider error
- `2` means a diff exists and must be triaged

## Notes

- Copy workflow into `.github/workflows/` when ready.
- The drift workflow must never run `apply`.
- Raw drift evidence usually stays local; commit only redacted or public-safe proof when needed.
