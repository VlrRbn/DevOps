# Lesson 66. Module Contracts & Interface Guarantees

**Date:** 2026-05-30

**Focus:** turn Terraform modules into stable interfaces with validated inputs, predictable outputs, invariants, and breaking-change discipline.

**Mindset:** a module is not a folder. A module is a contract.

---

## Why This Lesson Exists

By now I have practiced:

- remote state and locking
- safe refactors
- Terraform quality gates
- PR plan pipelines
- drift detection
- secret-safe inputs

The next risk is different:

> A module accepts bad input, produces surprising output, or changes behavior silently.

That is how reusable infrastructure becomes dangerous.

Lesson 66 makes the module interface explicit:

- what callers may pass
- what values are rejected early
- what outputs are guaranteed
- what assumptions must always be true
- what counts as a breaking change

Terraform modules are reusable only when their public interface is stable and enforced. Documentation alone is not enough; important rules should be executable.

---

## Outcomes

- define a clear module contract for `modules/network`
- add validation for dangerous or inconsistent inputs
- add preconditions where variable validation is not enough
- standardize outputs as a stable interface
- enforce required tags while still allowing caller-provided tags
- document breaking vs non-breaking module changes
- run drills proving invalid input fails before `apply` and before infrastructure changes
- capture proof artifacts for contract behavior

---

## Quick Path

1. Inventory every module input.
2. Classify inputs:
   - required
   - optional
   - dangerous
   - derived
3. Add validation to caller-facing mistakes.
4. Add preconditions for design invariants.
5. Standardize output names and shapes.
6. Document output consumers.
7. Add a breaking-change policy.
8. Run bad-input drills.
9. Capture proof pack.

---

## Prerequisites

- lesson 61: safe refactor mindset
- lesson 62: Terraform quality gates
- lesson 63: PR plan pipeline
- lesson 64: drift detection
- lesson 65: safe inputs and secrets
- working lab copied into `lab_66/terraform`

---

## Repo Layout

```text
lessons/66-module-contracts-and-interface-guarantees/
├── lesson.en.md
├── lesson.ru.md
├── README.md
├── proof-pack.en.md
├── proof-pack.ru.md
└── lab_66/
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
            ├── locals.tf
            ├── asg.tf
            └── outputs.tf
```

---

## A) Contract Model

A module contract has five parts.

| Contract part | Meaning |
| --- | --- |
| Inputs | What callers may pass |
| Validation | What values are rejected early |
| Resources | What the module owns and manages |
| Outputs | What callers may depend on |
| Compatibility rules | What counts as a breaking change |

**Breaking changes:**
* `rename/remove` existing `output`
* change `output type/shape`
* change `default` that changes infrastructure behavior
* make optional `input` required
* remove support for previously valid `mode`

**Non-breaking changes:**
* add new `output`
* add optional `input` with safe `default`
* add `validation` for values that were never safely supported


Important rule:

> Terraform accepting a value does not mean your module should accept it.

Example:

- Terraform can technically accept one private subnet.
- The lab ASG/internal ALB design expects at least two private subnets.
- Therefore the module contract must reject a single private subnet.

Self-check:

Answer in your own words after reading the example above. This is not a guessing test; the goal is to confirm that you can apply the contract model to real inputs.

1. Why must this lab reject one `private_subnet_cidr`, even though Terraform can technically accept a one-item list?
2. Why is `web_ami_id = "ubuntu-latest"` a bad input contract?
3. Which of these are breaking changes: adding a new output, renaming an existing output, adding an optional variable with a default, changing `web_desired_capacity` default from `2` to `1`?

---

## B) Input Inventory

If you cannot explain an input, the module interface is already unclear.

The full contract for this lab lives in `lab_66/terraform/modules/network/README.md`. The table below is the high-risk excerpt you should be able to explain from memory.

| Variable | Caller must set? | Default | Risk | Contract |
|---|---:|---|---|---|
| `project_name` | no | `lab66` | naming drift | lowercase kebab-style |
| `environment` | no | `dev` | tag drift | lowercase env name |
| `vpc_cidr` | no | `10.0.0.0/16` | invalid network | valid IPv4 CIDR |
| `public_subnet_cidrs` | no | 2 CIDRs | ALB/AZ/index failure | 2-6 unique valid CIDRs |
| `private_subnet_cidrs` | no | 2 CIDRs | ASG/AZ/index failure | 2-6 unique valid CIDRs |
| `web_ami_id` | yes | none | wrong artifact | AMI-shaped ID |
| `ssm_proxy_ami_id` | yes | none | wrong debug host | AMI-shaped ID |
| `web_desired_capacity` | no | `2` | invalid ASG capacity | min <= desired <= max |
| `common_tags` | no | `{}` | governance drift | non-empty tags, no reserved keys |

Acceptance:

- [ ] every variable has a purpose
- [ ] every dangerous variable has validation or a documented reason why not
- [ ] every validation error tells the caller how to fix the input

How to reason about inputs:

- `required` fits values that depend on a specific environment or build artifact and should not be guessed by the module.
- `optional` fits safe defaults where the caller can omit the value and still get expected behavior.
- `dangerous` does not mean "forbidden". It means a bad value can break naming, runtime, security, cost allocation, or downstream automation.
- `derived` should usually be computed inside the module when the module creates that value. Otherwise the caller can pass an inconsistent value that does not match the real resources.

Example:

- `web_ami_id` is required because the module does not know which baked AMI you built for the web fleet.
- `common_tags` is optional because the module can work without caller tags, but dangerous because tags affect ownership, cost reporting, and governance.
- `private_subnet_ids` is an output because these subnets are created inside the module. The caller should not manually pass IDs for resources owned by the module.

Self-check:

Answer in your own words after reading the model above. If answer matches the example in meaning, that is enough.

1. Why are `web_ami_id` and `ssm_proxy_ami_id` required instead of defaulted?
2. Why is `common_tags` optional but still dangerous?
3. Why should `private_subnet_ids` be an output, not an input, for this module?

---

## C) Variable Validation

Use variable validation for mistakes the caller can fix before `apply`.

Important nuance: in a real root module with a remote backend and data sources, `terraform plan` can contact the backend or read data sources before showing a validation error. The precise guarantee is this: bad input must fail before infrastructure changes. If you need a check with no AWS credentials at all, use the backend-less CI contract gate.

Also: Terraform can print part of a proposed plan and a line like `Plan: 22 to add`, then still finish with a validation error. That is not a successful plan. For the drill, the final result matters: the command exited non-zero, showed a clear validation error, and did not run `apply`.

### Project name

```hcl
variable "project_name" {
  type        = string
  description = "Project prefix for resource names"
  default     = "lab66"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,30}$", var.project_name))
    error_message = "project_name must be lowercase kebab-style, start with a letter, and be 3-31 characters."
  }
}
```

What this protects:

- resource names
- tags
- predictable naming
- automation that expects a normal prefix

Why this is a contract, not just style:

- the project name is used in resource names
- inconsistent naming breaks search, cost reports, scripts, and dashboards
- it is better to reject bad naming early than to create resources with mixed naming conventions

### AMI ID shape

```hcl
variable "web_ami_id" {
  type        = string
  description = "Baked web AMI used by the single rolling ASG fleet"

  validation {
    condition     = can(regex("^ami-[0-9a-f]{8,17}$", var.web_ami_id))
    error_message = "web_ami_id must look like an AWS AMI ID, for example ami-0123456789abcdef0."
  }
}
```

What this protects:

- the caller must pass an AWS AMI ID
- not a label
- not a filename
- not a Packer template name
- not `ubuntu-latest`

### Subnet contract

```hcl
variable "private_subnet_cidrs" {
  type        = list(string)
  description = "Private subnet CIDR blocks (minimum 2 for ASG spread)"

  validation {
    condition     = length(var.private_subnet_cidrs) >= 2
    error_message = "At least two private subnet CIDRs are required for the web instances."
  }

  validation {
    condition     = length(var.private_subnet_cidrs) <= 6
    error_message = "private_subnet_cidrs must contain at most six CIDRs because this module maps subnet keys a-f."
  }

  validation {
    condition     = length(distinct(var.private_subnet_cidrs)) == length(var.private_subnet_cidrs)
    error_message = "private_subnet_cidrs must not contain duplicate CIDRs."
  }

  validation {
    condition     = alltrue([for cidr in var.private_subnet_cidrs : can(cidrhost(cidr, 0))])
    error_message = "Every private_subnet_cidrs entry must be a valid IPv4 CIDR block."
  }
}
```

These are four separate rules:

- minimum 2, because the design needs spread
- maximum 6, because the module maps subnet keys `a-f`
- no duplicates, because duplicate subnet CIDRs are meaningless and dangerous
- every item must be a valid CIDR

Validation is good for:

- string format
- list length
- numeric ranges
- allowed values
- basic relationships between variables
- empty/null values
- reserved keys

Validation is not good for:

- proving an AMI really exists
- proving AWS quota is available
- proving an AZ exists in the selected region
- proving a subnet is reachable after apply
- proving runtime health checks pass

For those checks, use provider checks, preconditions, postconditions, tests, or manual proof.

### Capacity contract

```hcl
variable "web_desired_capacity" {
  type        = number
  description = "ASG desired capacity for the rolling web fleet"
  default     = 2

  validation {
    condition     = var.web_desired_capacity >= var.web_min_size && var.web_desired_capacity <= var.web_max_size
    error_message = "web_desired_capacity must be between web_min_size and web_max_size."
  }
}
```

---

## D) Preconditions and Interface Invariants

Use preconditions when the rule depends on derived values or resource behavior.

Example from `asg.tf`:

```hcl
resource "aws_autoscaling_group" "web" {
  vpc_zone_identifier = local.private_subnet_ids

  lifecycle {
    create_before_destroy = true

    precondition {
      condition     = length(local.private_subnet_ids) >= 2
      error_message = "ASG requires at least two private subnets for this lab design."
    }

    precondition {
      condition     = var.web_min_size <= var.web_desired_capacity && var.web_desired_capacity <= var.web_max_size
      error_message = "ASG capacity contract requires web_min_size <= web_desired_capacity <= web_max_size."
    }
  }
}
```

Use output preconditions to protect values consumed by other automation:

```hcl
output "alb_dns_name" {
  description = "DNS name of the internal ALB (reach via SSM port forwarding)"
  value       = aws_lb.app.dns_name

  precondition {
    condition     = aws_lb.app.dns_name != ""
    error_message = "alb_dns_name output contract requires a non-empty ALB DNS name."
  }
}
```

Rule:

- validations protect caller input
- preconditions protect design assumptions
- output preconditions protect interface guarantees

Do not add checks everywhere. Add checks where a wrong value would create a bad plan, broken runtime, or unsafe interface.

---

## E) Output Contract

Bad output design:

```hcl
output "stuff" {
  value = {
    alb = aws_lb.app
    asg = aws_autoscaling_group.web
  }
}
```

Why it is bad:

- leaks implementation detail
- creates unstable output shape
- makes downstream automation depend on internals
- may expose sensitive-looking metadata

Better:

```hcl
output "alb_dns_name" {
  value       = aws_lb.app.dns_name
  description = "DNS name of the internal ALB (reach via SSM port forwarding)"
}

output "web_asg_name" {
  value       = aws_autoscaling_group.web.name
  description = "Auto Scaling Group name for the rolling web fleet"
}

output "web_tg_arn" {
  value       = aws_lb_target_group.web.arn
  description = "ARN of the web target group"
}
```

Output rules:

- output names are stable
- name says what it is
- no whole-resource outputs
- no plaintext secret outputs
- sensitive outputs are marked `sensitive = true`
- output type/shape changes are breaking changes

Output should be consumer-oriented, not resource-oriented.

---

## F) Tagging Contract

Tags are part of the module interface because they affect:

- cost allocation
- ownership
- automation filters
- compliance/governance
- cleanup scripts
- dashboards/alerts

Caller-provided tags:

```hcl
variable "common_tags" {
  type        = map(string)
  description = "Optional caller-provided tags. Required governance tags are merged after this map and cannot be overridden."
  default     = {}

  validation {
    condition     = alltrue([for k, v in var.common_tags : length(trimspace(k)) > 0 && length(trimspace(v)) > 0])
    error_message = "common_tags must not contain empty keys or empty values."
  }

  validation {
    condition = alltrue([
      for k in keys(var.common_tags) :
      !contains(["Project", "Environment", "ManagedBy", "Lesson"], k)
    ])
    error_message = "common_tags must not set reserved keys: Project, Environment, ManagedBy, Lesson."
  }
}
```

Required tags:

```hcl
locals {
  required_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Lesson      = "66"
  }

  tags = merge(var.common_tags, local.required_tags)
}
```

In Terraform, `merge` uses the value from the last map when keys overlap.
So if the caller passes:

```hcl
common_tags = {
  Project = "manual"
}
```

`local.required_tags.Project` would still win.

But validation still rejects caller-provided `Project`.

- the caller immediately sees that reserved keys are forbidden
- there is no silent override
- the error explains the governance rule
- CI/drills can verify the behavior
- there is less confusion: the caller does not think `Project = "manual"` was applied

The caller can add metadata, but cannot override governance tags.

---

## G) Breaking Change Policy

### Breaking Changes

Breaking changes require a note in the lesson or PR:

- renaming or removing an output
- changing an output type or shape
- changing a required input type
- changing a default that changes infrastructure behavior
- removing support for a previously valid mode
- changing resource addresses without a `moved` block
- making a formerly optional input required

### Non-Breaking Changes

- adding an optional input with a safe default
- adding a new output
- tightening documentation without changing behavior
- adding validation that rejects values the module never safely supported
- adding internal resources that do not change public outputs or default behavior

Nuance:

Adding validation can be breaking or non-breaking.

Non-breaking:

```hcl
web_ami_id = "ubuntu-latest"
```

If the module could never safely work with `ubuntu-latest`, the validation just formalizes the existing contract.

Breaking:

```hcl
project_name = "myproject"
```

If this used to be a valid supported name, but a new validation now requires `my-project-prod`, the caller upgrade breaks.

Another example:

Changing the default from:

```hcl
web_desired_capacity = 2
```

to:

```hcl
web_desired_capacity = 1
```

is breaking because the caller changed nothing, but infrastructure behavior changed.

Rule:

> If a caller can upgrade the module and get a surprising plan, document it as breaking.

---

## H) Drills

Run drills from `lab_66/terraform/envs`. Save output to ignored `evidence/`.

### Drill 1 — Bad project name rejected

Set:

```hcl
project_name = "Bad_Name"
```

Run:

```bash
terraform plan -no-color
```

Expected:

- plan fails before resource changes
- error explains the naming contract

Acceptance:

- [ ] invalid input rejected before `apply` and before infrastructure changes
- [ ] error message explains how to fix the input

---

### Drill 2 — One private subnet rejected

Set:

```hcl
private_subnet_cidrs = ["10.30.11.0/24"]
```

Expected:

- variable validation or ASG precondition fails
- no infrastructure changes

Acceptance:

- [ ] lab cannot accidentally run single-AZ
- [ ] failure happens before apply

---

### Drill 3 — Too many subnets rejected

Set:

```hcl
private_subnet_cidrs = [
  "10.30.11.0/24",
  "10.30.12.0/24",
  "10.30.13.0/24",
  "10.30.14.0/24",
  "10.30.15.0/24",
  "10.30.16.0/24",
  "10.30.17.0/24",
]
```

Expected:

- validation fails before subnet mapping can produce an unclear index error
- error explains the supported 2-6 subnet contract

Acceptance:

- [ ] oversized subnet list is rejected with a contract-friendly message

---

### Drill 4 — Bad AMI ID rejected

Set:

```hcl
web_ami_id = "ubuntu-latest"
```

Expected:

- validation fails before `apply` and before infrastructure changes

Acceptance:

- [ ] wrong artifact shape rejected early

---

### Drill 5 — Empty tag rejected

Set:

```hcl
common_tags = {
  Owner = ""
}
```

Expected:

- validation fails

Acceptance:

- [ ] tag contract is enforced

---

### Drill 6 — Reserved tag rejected

Set:

```hcl
common_tags = {
  Project = "override"
}
```

Expected:

- validation fails
- caller cannot override governance tags

Acceptance:

- [ ] required tag contract is protected

---

### Drill 7 — Output contract review

Write `output-contract.md`:

| Output | Consumer | Stability |
|------------|------------|------------|
| alb_dns_name | SSM proxy curl tests | stable |
| web_asg_name | release workflows | stable |
| web_tg_arn | health/drift workflows | stable |
| ssm_vpc_endpoint_ids | private runtime proof | stable map keyed by service |

Acceptance:

- [ ] every output has a consumer
- [ ] no output exposes a whole resource
- [ ] no secret output exists

---

## I) Proof Pack

Capture:

```text
evidence/
  input-inventory.md
  fmt.txt
  validate.txt
  baseline-plan.txt
  bad-project-name-plan.txt
  one-subnet-plan.txt
  too-many-subnets-plan.txt
  bad-ami-id-plan.txt
  empty-tag-plan.txt
  reserved-tag-plan.txt
  output-contract.md
  baseline-plan-after-fixes.txt
```

`baseline-plan` does not mean `0 to change`. If the lab is not applied yet, the baseline can show creates. In this lesson, baseline means: the plan is readable, temporary bad-input overrides are removed, and plaintext secrets are not printed.

For each failed drill, save:

- command
- error
- why it failed
- why that failure is good

Do not commit real `terraform.tfvars`, `backend.hcl`, `.terraform/`, `tfstate`, or proof files with sensitive environment details.

---

## J) CI Contract Gate

The repo workflow `.github/workflows/lesson66-contract-tests.yml` runs a static contract gate for lesson.

It checks:

- Terraform formatting
- backend-less `terraform init`
- `terraform validate`
- negative input drills that must fail with the expected validation messages

The CI job intentionally does not use AWS credentials. Its job is to prove that the module rejects bad input before remote state or cloud APIs are needed. Real AWS behavior still belongs in the manual proof pack.

---

## Common Pitfalls

- validating only type, not meaning
- outputting whole resources
- letting callers override required tags
- changing outputs without a breaking-change note
- adding validations that reject real supported use cases
- relying only on README instead of executable validation
- using validation messages that say what failed but not how to fix it

---

## Security Checklist

- no output exposes plaintext secrets
- sensitive outputs are marked sensitive
- module does not accept secret values unless unavoidable
- invalid network shapes fail before apply
- AMI inputs reject arbitrary text
- required tags cannot be overwritten by callers
- output shapes are stable and documented
- breaking changes are documented

---

## Final Acceptance

Lesson 66 is complete if:

- [ ] all important variables have documented contracts
- [ ] dangerous inputs have validation or preconditions
- [ ] outputs are stable and documented
- [ ] required tags are enforced
- [ ] at least 6 bad-input drills fail correctly
- [ ] baseline plan returns after fixing inputs
- [ ] module README contains output contract and breaking-change policy
- [ ] lesson CI contract workflow passes

---

## Lesson Summary

Theory wrap-up.

The main model for lesson 66:

> A Terraform module is a public contract, not just a folder with `.tf` files.

What belongs in the contract:

- `inputs`: what callers may pass
- `validations`: which values the module rejects early
- `resources`: what the module owns internally
- `outputs`: what callers and automation may safely depend on
- `compatibility rules`: what counts as a breaking change

What to remember:

- bad input must fail before `apply` and before infrastructure changes
- validation checks caller input
- precondition checks a design invariant near a resource/output
- output should be consumer-oriented, not a whole-resource dump
- tags are part of the interface because cost, ownership, automation, and governance use them
- a default can be a breaking change if it changes infrastructure behavior
- the CI contract gate checks the module contract without AWS credentials
- the manual proof pack is still needed for real AWS-backed behavior

Practical summary:

- **What you learned:** modules are contracts, not folders.
- **What you practiced:** variable validation, preconditions, output contracts, tagging invariants, breaking-change policy.
- **Operational focus:** fail early when callers provide dangerous inputs.
- **Why it matters:** module reuse is safe only when the interface is explicit, documented, and enforced.
