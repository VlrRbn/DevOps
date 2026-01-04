# lesson_41

---

# Terraform CI: fmt/validate + plan in GitHub Actions

**Date:** 2025-01-04

**Topic:** Add **GitHub Actions CI** for Terraform: `fmt`, `validate`, `tflint`, `plan`.

> Outcome: every push/PR runs checks automatically, stop breaking Terraform by accident.
> 

---

## Goals

- Add CI checks that run on every push/PR:
    - `terraform fmt -check`
    - `terraform validate`
    - `tflint`
- Make the workflow work **without AWS credentials** (default).
- Enable `terraform plan` when ready (with AWS auth).
- Keep it safe: no secrets in repo, no accidental applies.

---

## Pocket Cheat

| Thing | Command / File | Why |
| --- | --- | --- |
| Format check | `terraform fmt -check -recursive` | Fail fast on style |
| Validate | `terraform validate` | Catch syntax/provider config issues |
| Lint | `tflint` | Catch Terraform/AWS mistakes |
| Plan | `terraform plan` | Show diffs before apply |
| CI workflow | `.github/workflows/terraform-ci.yml` | Automatic checks |
| Vars file | `envs/dev.tfvars` | Stable inputs for CI |
| Safe mode | no `apply` in CI | Prevent disasters |

---
