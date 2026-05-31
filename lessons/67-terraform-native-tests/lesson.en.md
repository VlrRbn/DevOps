# Lesson 67. Terraform Native Tests

**Date:** 2026-05-31

**Focus:** protect Terraform module contracts with native `.tftest.hcl` tests.

**Mindset:** a contract is not finished when it is documented. A contract is finished when regressions fail automatically.

---

## Why This Lesson Exists

Lesson 66 made the `modules/network` contract explicit:

- valid inputs
- rejected inputs
- preconditions
- stable outputs
- tagging rules
- breaking-change policy

A future change can accidentally:

- weaken `project_name` validation
- accept a bad AMI value
- allow single-subnet topology
- let callers override governance tags
- rename an output used by CI or release scripts
- change an output from string to object
- remove a precondition because it looks redundant

Lesson 67 adds Terraform native tests so the module contract becomes executable.

The goal is not to test AWS itself. The goal is to test your module interface before bad changes reach `apply`.

---

## Outcomes

After this lesson you should be able to:

- explain where `terraform test` fits in the Terraform quality chain
- write `.tftest.hcl` files for module contract checks
- use `mock_provider` to avoid real AWS resources for contract tests
- test valid input combinations
- test expected failures with `expect_failures`
- test stable outputs with mocked `apply`
- separate fast native tests from live AWS proof drills
- decide which module behavior deserves a native test
- understand the native test lifecycle: setup, run, assert, teardown
- debug common native test failures such as `Unknown condition value`
- read failed test output without guessing
- capture proof artifacts for CI/local evidence

---

## Quick Path

1. Add native test files under `lab_67/terraform/modules/network/tests/`.
2. Add mocked AWS provider behavior.
3. Add positive contract tests.
4. Add negative tests with `expect_failures`.
5. Add output contract tests.
6. Run `terraform test` from the module directory.
7. Save proof artifacts.

---

## Prerequisites

- Understand the difference between:
  - `terraform validate`
  - `terraform plan`
  - `terraform test`
  - live AWS smoke/proof checks

---

## Repo Layout

```text
lessons/67-terraform-native-tests/
├── lesson.en.md
├── lesson.ru.md
├── README.md
├── proof-pack.en.md
├── proof-pack.ru.md
└── lab_67/
    └── terraform/
        ├── envs/
        │   ├── main.tf
        │   ├── variables.tf
        │   ├── outputs.tf
        │   ├── terraform.tfvars.example
        │   └── backend.hcl.example
        └── modules/network/
            ├── README.md
            ├── variables.tf
            ├── outputs.tf
            └── tests/
                ├── contract_valid.tftest.hcl
                ├── contract_invalid_inputs.tftest.hcl
                └── output_contract.tftest.hcl
```

Important choice:

> Native contract tests live in `modules/network/tests`, not in `envs/tests`.

Reason: this lesson tests the reusable module interface. The `envs` folder tests root wiring and backend behavior, which is a different concern.

---

## A) Mental Model - `Module Contract` must be executable

`terraform test` executes `.tftest.hcl` files containing `run` blocks.

A `run` block can execute:

- `command = plan`
- `command = apply`

In lesson:

- use `plan` for fast input contract checks
- use `expect_failures` for invalid input tests
- use mocked `apply` only when output values are unknown during plan
- never create real AWS resources just to test a module contract

Native tests are a regression layer.

They do not replace:

- `terraform fmt`
- `terraform validate`
- `tflint`
- `checkov`
- PR plan review
- drift detection
- live smoke checks

They catch something else:

* validation was accidentally removed
* the output shape changed
* an expected failure was broken
* the module started accepting bad inputs
* the output contract stopped being stable

They sit between static checks and live infrastructure proof.

---

### Native Test Lifecycle

Lifecycle:

```text
setup -> run -> assert/expect failure -> teardown
```

What happens:

- **setup:** Terraform loads the module, variables, provider configuration, mocks, and override blocks.
- **run:** each `run` block executes `plan` or `apply`.
- **assert:** checks that the good scenario produces the expected result; negative tests evaluate `expect_failures`.
- **teardown:** Terraform removes any temporary state created by the test run.

In this lesson, teardown is weak because the provider is mocked. With real providers, teardown matters more because an `apply` test can create temporary infrastructure.

Practical rule:

- one `run` block should prove one idea
- use file-level `variables` for shared valid defaults
- override only the variable you are intentionally testing inside each `run`
- prefer `plan` unless you need computed outputs
- use mocked `apply` only when a value is unknown during plan

Example structure:

```hcl
variables {
  project_name = "lab67"
  web_ami_id   = "ami-0123456789abcdef0"
}

run "bad_ami_id_fails" {
  command = plan

  variables {
    web_ami_id = "ubuntu-latest"
  }

  expect_failures = [
    var.web_ami_id
  ]
}
```

The file-level variables define the healthy baseline. The run-level variable changes one thing. That makes the failure easy to understand.

---

## B) Why Mock The Provider

The network module contains AWS resources and data sources.

A normal plan may need:

- AWS provider plugin
- AWS credentials
- region access
- data source calls

For contract tests, that is too heavy. We are not proving that AWS works. We are proving that the module interface behaves as promised.

So the test files use:

```hcl
mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
    }
  }
}
```

The mock provider lets Terraform evaluate the module without creating AWS resources.
Terraform says: don’t hit real AWS; use mocked provider responses.

```bash
AZs -> eu-west-1a, eu-west-1b, eu-west-1c
Account -> 123456789012
```

Some AWS-shaped values still need realistic defaults. Example:

```hcl
mock_resource "aws_launch_template" {
  defaults = {
    id             = "lt-0123456789abcdef0"
    latest_version = 1
  }
}
```

Why: AWS provider schema validates that launch template IDs look like `lt-*`.

Then there is a shared block:

```hcl
variables {
  aws_region           = "eu-west-1"
  project_name         = "lab67"
  environment          = "test"
  vpc_cidr             = "10.67.0.0/16"
  public_subnet_cidrs  = ["10.67.1.0/24", "10.67.2.0/24"]
  private_subnet_cidrs = ["10.67.11.0/24", "10.67.12.0/24"]
  web_ami_id           = "ami-0123456789abcdef0"
  ssm_proxy_ami_id     = "ami-0123456789abcdef0"
  github_owner         = "VlrRbn"
  github_repo          = "DevOps"
  tf_state_bucket_name = "vlrrbn-tfstate-123456789012-eu-west-1"
  tf_state_key         = "lab67/dev/full/terraform.tfstate"
}
```

This is the baseline valid input. Then come the `run` blocks.

Example of a positive test:

```hcl
run "valid_contract_inputs_plan" {
  command = plan

  assert {
    condition     = output.web_asg_name == "lab67-web-asg"
    error_message = "web_asg_name must keep the stable '<project>-web-asg' output contract."
  }
}
```

What happens:

```bash
setup -> mocked provider
run -> terraform plan
assert -> check output/condition
teardown -> test cleanup
```

Example of a negative test:

```hcl
run "bad_project_name_fails" {
  command = plan

  variables {
    project_name = "Bad_Name"
  }

  expect_failures = [
    var.project_name
  ]
}
```

Here, failure means success.

Because we expect validation on `var.project_name` to trigger.

Formula:

```bash
failed native test = BAD
expected failure inside expect_failures = GOOD
```

For output tests, mocked resources are added:

```hcl
mock_resource "aws_lb" {
  defaults = {
    arn      = "arn:aws:elasticloadbalancing:eu-west-1:123456789012:loadbalancer/app/lab67-app-alb/test"
    dns_name = "internal-lab67-app-alb.example.local"
  }
}
```

Why? Because outputs like `alb_dns_name` and `web_tg_arn` are computed after apply. To test the output contract without a real ALB, we give Terraform fake resource values.


---

## C) Test File 1: Valid Contract Inputs

File:

```text
lab_67/terraform/modules/network/tests/contract_valid.tftest.hcl
```

Purpose:

- valid caller input should reach the plan stage
- stable metadata outputs should keep their expected values
- no real AWS resources should be created

Test:

```hcl
run "valid_contract_inputs_plan" {
  command = plan

  assert {
    condition     = output.web_asg_name == "lab67-web-asg"
    error_message = "web_asg_name must keep the stable '<project>-web-asg' output contract."
  }

  assert {
    condition     = output.demo_api_token_parameter_name == "/devops/lab67/demo/api-token"
    error_message = "The runtime SSM parameter output must expose only the stable metadata name."
  }

  assert {
    condition     = output.demo_app_secret_name == "/devops/lab67/demo/app-secret"
    error_message = "The runtime Secrets Manager output must expose only the stable metadata name."
  }
}
```

What it checks:

- valid inputs make it through to `plan`
- `web_asg_name` remains stable
- secret-related outputs expose only metadata names
- plaintext secret values do not appear

Why `command = plan` instead of `apply`?

Because these outputs can be computed at the plan stage:

```bash
web_asg_name -> deterministic name
demo_api_token_parameter_name -> variable/default
demo_app_secret_name -> variable/default
```

In `plan`, this is a computed value, so it may be unknown.


Acceptance:

- valid inputs do not fail validation
- test does not require real AWS resources
- stable metadata outputs remain predictable

---

## D) Test File 2: Invalid Inputs

File:

```text
lab_67/terraform/modules/network/tests/contract_invalid_inputs.tftest.hcl
```

Purpose:

- bad inputs should fail early
- failures should be expected and intentional
- each test should check one contract rule

Example:

```hcl
run "bad_project_name_fails" {
  command = plan

  variables {
    project_name = "Bad_Name"
  }

  expect_failures = [
    var.project_name
  ]
}
```

If validation is removed from `variables.tf`, this test will fail as a failed test, because the expected failure will no longer occur.

The important idea:

> A failed native test is bad. An expected failure inside `expect_failures` is good.

This lesson includes tests for:

- `bad_project_name_fails`
- `bad_web_ami_id_fails`
- `single_private_subnet_fails`
- `too_many_private_subnets_fails`
- `duplicate_private_subnets_fail`
- `bad_private_subnet_cidr_fails`
- `bad_ssm_proxy_ami_id_fails`
- `empty_tag_value_fails`
- `reserved_tag_override_fails`
- `bad_health_check_threshold_fails`
- `bad_state_key_fails`

Acceptance:

- invalid inputs fail before apply
- each failure points at the variable contract
- no test depends on live AWS state

---

## E) Test File 3: Output Contract

File:

```text
lab_67/terraform/modules/network/tests/output_contract.tftest.hcl
```

Some outputs are unknown during `plan` because they come from computed resource attributes.

Example:

- ALB DNS name
- target group ARN
- security group IDs
- SSM vpc endpoint IDs

For these, use mocked `apply`:

```hcl
run "stable_output_contract" {
  command = apply

  assert {
    condition     = startswith(output.alb_dns_name, "internal-lab67-app-alb")
    error_message = "alb_dns_name must stay a non-empty DNS name consumed by SSM port-forward tests."
  }

  assert {
    condition     = startswith(output.web_tg_arn, "arn:aws:elasticloadbalancing:")
    error_message = "web_tg_arn must stay an ARN-shaped output consumed by health/drift checks."
  }

  assert {
    condition     = can(output.security_groups.web_sg) && can(output.security_groups.alb_sg)
    error_message = "security_groups output must keep stable web_sg and alb_sg keys."
  }

  assert {
    condition     = can(output.ssm_vpc_endpoint_ids["ssm"]) && can(output.ssm_vpc_endpoint_ids["secretsmanager"])
    error_message = "ssm_vpc_endpoint_ids must stay a map keyed by AWS service name."
  }
}
```

What this protects:

- `alb_dns_name` has not disappeared
- `web_tg_arn` remains ARN-shaped
- `security_groups` remains an object with stable keys
- `ssm_vpc_endpoint_ids` remains a map, not a list


This does not create AWS resources because the provider is mocked.

Rule:

- use `plan` when values are known during planning
- use mocked `apply` when the tested output is computed
- do not use real `apply` for contract-only tests

---

### Debug: `Unknown condition value`

A common Terraform native test error is:

```text
Error: Unknown condition value
```

This usually means your `assert` depends on a value that is not known during `plan`.

Example:

```hcl
run "stable_output_contract" {
  command = plan

  assert {
    condition = startswith(output.alb_dns_name, "internal-")
  }
}
```

`alb_dns_name` comes from AWS after the load balancer exists, so during `plan` Terraform may only know that it will be a string later.

Fix options:

- change the test to mocked `apply`
- assert on a value known during plan
- add a mock or override that makes the value available during plan
- move the check to a live proof drill if it is really a runtime behavior

In this lab, `output_contract.tftest.hcl` uses:

```hcl
run "stable_output_contract" {
  command = apply
}
```

That is safe here because the `AWS provider is mocked`. It gives Terraform concrete output values without creating real infrastructure.

Rule:

> If the value is computed by a resource, `plan` may not know it. Use mocked `apply` or test a different contract.

---

## F) Run The Tests

From repo root:

```bash
cd lessons/67-terraform-native-tests/lab_67/terraform/modules/network
terraform init -backend=false
terraform test -no-color
```

Expected result:

```text
Success! 13 passed, 0 failed.
```

Verbose mode:

```bash
terraform test -verbose -no-color
```

Run a specific test directory:

```bash
terraform test -test-directory=tests -no-color
```

If the provider plugin fails with a local cache/handshake issue, isolate Terraform data into `/tmp`:

```bash
TF_DATA_DIR=/tmp/l67-module-test-data \
AWS_EC2_METADATA_DISABLED=true \
terraform test -no-color
```

---

### How To Read A Failed Native Test

Do not read only the last line. Terraform test output has a useful structure.

Example shape:

```bash
tests/contract_invalid_inputs.tftest.hcl... in progress
  run "bad_project_name_fails"... pass
  run "bad_web_ami_id_fails"... fail
tests/contract_invalid_inputs.tftest.hcl... fail

Error: Invalid value for variable
  on variables.tf line ...
```

Read it in this order:

1. **File:** which `.tftest.hcl` failed?
2. **Run block:** which `run "..."` failed?
3. **Expectation type:** was it a normal `assert` or an `expect_failures` test?
4. **Address:** did Terraform point at `var.web_ami_id`, `output.web_tg_arn`, or a resource?
5. **Meaning:** did the module fail too early, too late, or not fail when it should have?

Common interpretations:

| Output | Meaning |
| --- | --- |
| `run "...fails"... pass` | Good. The invalid input failed as expected. |
| `run "...fails"... fail` | Bad. The invalid input probably no longer fails, or it fails at the wrong address. |
| `Unknown condition value` | Assertion used a value unknown during `plan`. |
| provider schema error | Mock value shape is unrealistic, for example launch template ID not starting with `lt-`. |
| `0 passed, 0 failed` plus provider error | Test framework could not even start the provider. Check plugin/cache/environment. |

When debugging, reduce the test:

- run only one test file if needed
- keep one intentional variable override
- use `terraform test -verbose -no-color`
- check whether the failing value is known during `plan`
- check whether your mock value looks like a real AWS value

---

## G) What Not To Test Here

Do not use native tests for everything.

Good native test targets:

- variable validation
- preconditions
- output names and shapes
- required tag behavior
- module-level assumptions
- known breaking-change guards

Bad native test targets:

- real ALB routing
- real ASG instance refresh behavior
- real IAM permission boundaries
- real SSM port forwarding
- real Secrets Manager decryption
- CloudWatch alarm state transitions

Those belong in live proof drills or later integration tests.

---

## H) CI Pattern

A lightweight native-test job should run before any expensive plan/apply workflow.

```bash
fmt -> terraform test -> validate/plan -> apply/smoke
```

In this repo, the active workflow lives in `.github/workflows/lesson67-terraform-native-tests.yml`. The `ci/terraform-native-tests.yml` file remains as a copyable template for the lesson.

Example:

```yaml
name: lesson67-terraform-native-tests

on:
  pull_request:
    paths:
      - 'lessons/67-terraform-native-tests/**'
      - '.github/workflows/lesson67-terraform-native-tests.yml'
```

Why no AWS credentials?

Because these tests use `mock_provider`. They protect the contract without touching AWS.

---

## I) Drill Set

### Drill 1 - Break project name validation

Change the valid test variable:

```hcl
project_name = "Bad_Name"
```

Expected:

- the positive test fails
- the negative test still passes because it expects that failure

Restore the valid value.

### Drill 2 - Remove AMI validation

Temporarily remove the `web_ami_id` validation block.

Expected:

- `bad_web_ami_id_fails` fails because Terraform no longer rejects `ubuntu-latest`

Restore the validation.

### Drill 3 - Allow one private subnet

Temporarily change:

```hcl
length(var.private_subnet_cidrs) >= 2
```

to:

```hcl
length(var.private_subnet_cidrs) >= 1
```

Expected:

- `single_private_subnet_fails` fails
- this proves the test protects the lesson 66 topology contract

Restore the validation.

### Drill 4 - Remove reserved tag protection

Temporarily remove the `common_tags` reserved-key validation.

Expected:

- `reserved_tag_override_fails` fails

Restore the validation.

### Drill 5 - Break an output name

Rename output `web_asg_name` to `asg_name`.

Expected:

- output contract test fails
- this demonstrates why output renames are breaking changes

Restore the output.

---

## J) Proof Pack

Save:

```text
evidence/
  terraform-version.txt
  terraform-init.txt
  terraform-test.txt
  terraform-test-verbose.txt
  drill-bad-project-name.txt
  drill-remove-ami-validation.txt
  drill-one-private-subnet.txt
  drill-reserved-tag.txt
  drill-output-rename.txt
  decision.txt
```

In `decision.txt`, add the GitHub Actions run URL for `.github/workflows/lesson67-terraform-native-tests.yml`.

Minimal proof:

```bash
cd lessons/67-terraform-native-tests/lab_67/terraform/modules/network

export EVIDENCE_DIR="../../../../evidence/l67-$(date +%Y%m%d_%H%M%S)"
mkdir -p "$EVIDENCE_DIR"

terraform version > "$EVIDENCE_DIR/terraform-version.txt" 2>&1
terraform init -backend=false -input=false -no-color > "$EVIDENCE_DIR/terraform-init.txt" 2>&1
terraform test -no-color > "$EVIDENCE_DIR/terraform-test.txt" 2>&1
terraform test -verbose -no-color > "$EVIDENCE_DIR/terraform-test-verbose.txt" 2>&1
```

Do not commit `.terraform`, `tfstate`, `terraform.tfvars`, backend files, real env data.

---

## Common Pitfalls

- putting module contract tests in `envs/tests` and accidentally testing backend wiring
- using real AWS `apply` for contract-only tests
- testing too many things in one run block
- writing `expect_failures` that points at the wrong variable
- asserting computed outputs during `plan`
- forgetting realistic AWS-shaped mock values such as `lt-*` launch template IDs
- treating native tests as a replacement for live smoke checks

---

## Final Acceptance

Lesson 67 is complete if:

- [ ] native tests live under `modules/network/tests`
- [ ] provider is mocked for contract tests
- [ ] at least one valid-input test passes
- [ ] at least eleven invalid-input tests pass through `expect_failures`
- [ ] output contract test passes
- [ ] `terraform test -no-color` returns success
- [ ] native-test CI workflow passes
- [ ] proof pack contains test output and drill evidence
- [ ] lesson explains what belongs in native tests and what does not

---

## Lesson Summary

Theory wrap-up.

The main model for lesson 67:

> `terraform test` turns a module contract from documentation into an executable safety net.

What belongs in a native test:

- `.tftest.hcl` files inside `modules/network/tests`
- `mock_provider "aws"` instead of real AWS calls
- `run` blocks for plan/apply scenarios
- `expect_failures` for expected validation failures
- `assert` blocks for output/interface guarantees

What to remember:

- native tests should live next to the reusable module, not under `envs`, when the module contract is the target
- mocked provider protects the contract without AWS credentials or real resources
- an expected failure inside `expect_failures` is a successful test
- a failed native test without `expect_failures` is a regression or a test design bug
- computed outputs often cannot be asserted reliably during `plan`; use mocked `apply` for output contracts
- native tests do not replace live smoke checks, SSM proof, real IAM checks, or drift detection
- CI native tests should run before expensive AWS-backed plan/apply workflows

Practical summary:

- **What you learned:** `terraform test` can protect module contracts from regression.
- **What you practiced:** `.tftest.hcl`, `mock_provider`, `expect_failures`, output assertions, mocked apply.
- **Operational focus:** catch broken module interfaces before PR plan/apply.
- **Why it matters:** module contracts only stay reliable when they are executable and tested.
