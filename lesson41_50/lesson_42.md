# lesson_42

---

# Terraform Safe Ops: cheap vs full envs, state hygiene, apply/destroy runbook

**Date:** 2025-01-06

**Topic:** Make Terraform workflow **safe, repeatable, and cost-controlled**:

- add two environments: **cheap** (minimal spend) and **full** (real multi-AZ + NAT design)
- build a clean **apply/destroy runbook**
- learn **state hygiene** basics and how to avoid “I recreated everything”
- add a “destroy guard” checklist to prevent surprises

> Goal: Practice in AWS without anxiety and without mystery bills.
> 

---

## Goals

- Create **two tfvars** profiles:
    - `cheap.tfvars`: minimal resources to learn basics with low cost
    - `full.tfvars`: multi-AZ with NAT (architecture practice), used only for short sessions
- Standardize commands for:
    - init / validate / plan / apply / destroy
- Learn the “3 golden rules” of Terraform state:
    - never manually edit state
    - prefer refactor tools (`moved` blocks or `state mv`) instead of recreating
    - always know what workspace/env you’re running

---

## Pocket Cheat

| Task | Command | Why |
| --- | --- | --- |
| Format | `terraform fmt -recursive` | Clean diffs |
| Validate | `terraform validate` | Catch errors early |
| Plan (env) | `terraform plan -var-file=envs/cheap.tfvars` | Preview changes |
| Apply (env) | `terraform apply -var-file=envs/cheap.tfvars` | Create |
| Destroy (env) | `terraform destroy -var-file=envs/cheap.tfvars` | Remove everything |
| List state | `terraform state list` | See what TF owns |
| Show resource | `terraform state show <addr>` | Debug exactly what exists |
| Remove from state | `terraform state rm <addr>` | “Stop managing this” (careful) |
| State move | `terraform state mv a b` | Refactor without recreate |

---
