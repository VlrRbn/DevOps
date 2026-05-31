# Lesson 67 - Terraform Native Tests

This lesson adds Terraform native tests for the module contract created in lesson 66.

The lab focuses on `.tftest.hcl`, `mock_provider`, `expect_failures`, and output contract assertions.

## Files

- `lesson.en.md` - English lesson walkthrough
- `lesson.ru.md` - Russian lesson walkthrough
- `proof-pack.en.md` - evidence checklist in English
- `proof-pack.ru.md` - evidence checklist in Russian
- `lab_67/terraform/modules/network/tests/contract_valid.tftest.hcl` - positive contract test
- `lab_67/terraform/modules/network/tests/contract_invalid_inputs.tftest.hcl` - expected failure tests
- `lab_67/terraform/modules/network/tests/output_contract.tftest.hcl` - output interface test
- `.github/workflows/lesson67-terraform-native-tests.yml` - active CI workflow
- `ci/terraform-native-tests.yml` - copyable workflow template for the lesson

## Quick Start

From repo root:

```bash
cd lessons/67-terraform-native-tests/lab_67/terraform/modules/network
terraform init -backend=false
terraform test -no-color
```

Expected:

```text
Success! 13 passed, 0 failed.
```

## Why Tests Are In The Module

These tests validate the reusable module contract. They intentionally live under `modules/network/tests`, not under `envs/tests`, because backend/root-environment wiring is not the focus of this lesson.

## Safety

- Tests use `mock_provider "aws"`.
- Tests do not create real AWS resources.
- AWS provider is pinned in `versions.tf` so CI does not drift across future provider releases.
- Do not commit `.terraform/`, local tfvars, state, or proof artifacts with real environment details.
