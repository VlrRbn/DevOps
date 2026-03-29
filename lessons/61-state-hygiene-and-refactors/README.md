# Lesson 61: State Hygiene & Safe Refactors

## Purpose

This lesson continues lesson 60.

Lesson 60 made Terraform state shared, remote, and protected.
Lesson 61 teaches how to change Terraform structure safely after that point.

The core topics are:

- `moved` blocks for declarative refactors
- `terraform state mv` for imperative address surgery
- `terraform state rm` for safe detach from Terraform ownership
- `terraform import` for adopting existing infrastructure
- proof-first refactor discipline

## Prerequisites

- lesson 60 completed
- remote backend active in `lab_61/terraform/envs`
- AWS CLI + Terraform configured
- one real env exists and is healthy enough to produce a clean baseline plan

## Layout

- `lesson.en.md`
  - full lesson flow (EN)
- `lesson.ru.md`
  - full lesson flow (RU)
- `proof-pack.en.md`
  - what evidence to save for each surgery drill (EN)
- `proof-pack.ru.md`
  - what evidence to save for each surgery drill (RU)
- `lab_61/terraform/`
  - real Terraform stack for state refactor drills
- `lab_61/packer/`
  - lesson AMI layout

## Quick Start

```bash
cd lessons/61-state-hygiene-and-refactors/lab_61/terraform/envs

terraform plan
terraform state list | sort > /tmp/l61-state-before.txt
terraform state pull > /tmp/l61-state-before.json
```

Then choose one drill:

1. declarative rename with `moved`
2. imperative rename with `terraform state mv`
3. detach with `terraform state rm`
4. adopt reality with `terraform import`

## Working Rule

Never start any state surgery if:

- `terraform plan` is already dirty for unrelated reasons
- locking is disabled
- you do not have a state snapshot

## Notes

- Prefer `moved` when the refactor can be described declaratively.
- Use `terraform state mv` when you need direct operator-led repair.
- `terraform state rm` removes ownership from state, not the real AWS object.
- Do not practice lesson 61 on backend resources created in `backend-bootstrap/`.
- Raw proof folders usually stay local; commit them only if you redact sensitive values first.
