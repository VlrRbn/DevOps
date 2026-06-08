# Lesson 69. Production IAM: Least-Privilege Plan and Apply Roles

**Date:** 2026-06-03

**Focus:** replace broad Terraform automation permissions with scoped `plan` and `apply` roles.

**Mindset:** `plan` should observe. `apply` should change only the intended stack. Break-glass should be separate.

Official references:

- AWS IAM least privilege and permissions refinement: https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies.html
- AWS IAM Access Analyzer policy generation: https://docs.aws.amazon.com/IAM/latest/UserGuide/access-analyzer-policy-generation.html
- GitHub Actions OIDC with AWS: https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services
- Terraform S3 backend permissions and native lockfile: https://developer.hashicorp.com/terraform/language/backend/s3

---

## Why This Lesson Exists

Lesson 68 built a controlled apply pipeline:

```text
plan-dev
-> saved plan artifact
-> approval
-> apply-dev
-> post-apply check
```

That fixed the delivery flow, but lesson 68 still kept one lab shortcut:

```text
apply role -> AdministratorAccess
```

That is acceptable while learning pipeline mechanics. It is not acceptable as a normal production delivery role.

Lesson 69 removes that shortcut. The goal is to create a defensible production model:

```text
plan role:
  read backend state
  acquire/release state lock
  refresh/read AWS resources
  cannot mutate infrastructure

apply role:
  read/write only this backend state key and lockfile
  mutate only the service areas used by this stack
  pass only approved runtime roles to EC2
  assume only through GitHub Environment approval

break-glass role:
  separate from the normal pipeline
  manually approved, logged, time-limited, and reviewed after the incident
  emergency recovery
```

Was:

```text
plan role  -> ReadOnlyAccess + backend access
apply role -> AdministratorAccess
```

Became:

```text
plan role  -> backend lockfile + scoped read/refresh policy
apply role -> backend lockfile + scoped lab mutate policy + restricted iam:PassRole
```

---

## Outcomes

After this lesson you should be able to:

- explain why `plan` and `apply` need different IAM permissions
- replace `AdministratorAccess` with scoped customer-managed or inline policies
- scope S3 backend permissions to one state object and one `.tflock` object
- understand why many AWS `Describe*` APIs still require `Resource = "*"`
- restrict `iam:PassRole` to approved runtime roles and `ec2.amazonaws.com`
- harden GitHub OIDC trust with branch, PR, and environment subjects
- identify the self-management caveat when Terraform manages its own CI roles
- use Access Analyzer and last accessed data as refinement tools, not blind generators
- prove that plan role cannot apply and apply role no longer has admin rights

---

## Quick Path

1. Inventory Terraform-managed resources in `lab_69`.
2. Separate permissions into backend, read/refresh, mutate, IAM, and PassRole groups.
3. Remove `ReadOnlyAccess` from the plan role and use a scoped read policy.
4. Remove `AdministratorAccess` from the apply role.
5. Attach a scoped apply policy for the lab stack.
6. Keep apply role trust bound to `repo:<owner>/<repo>:environment:terraform-dev`.
7. Run native tests and `terraform validate`.
8. Run a safe plan/apply drill.
9. Run a negative drill with the plan role or a wrong OIDC subject.
10. Capture proof artifacts.

---

## Prerequisites

- Lesson 60: remote state and S3 native lockfile.
- Lesson 63: PR plan pipeline.
- Lesson 68: controlled apply pipeline.
- Existing GitHub OIDC provider and roles from the lab.
- Working Terraform backend and `terraform-dev` GitHub Environment.
- Comfort reading IAM JSON.

---

## Repo Layout

```text
lessons/69-production-iam-least-privilege-plan-and-apply-roles/
├── lesson.en.md
├── lesson.ru.md
├── README.md
├── proof-pack.en.md
├── proof-pack.ru.md
└── lab_69/
    ├── packer/
    └── terraform/
        ├── backend-bootstrap/
        ├── envs/
        └── modules/network/
```

Workflow template:

```text
lessons/69-production-iam-least-privilege-plan-and-apply-roles/ci/lesson69-terraform-apply-dev.yml
```

Lesson 69 keeps the same controlled apply model from lesson 68, but the template is retargeted to `lab_69`, `lab69/dev/full/terraform.tfstate`, and the lab69 scoped roles.

Do not point the lesson 68 workflow at lab69 role ARNs without also retargeting the workflow paths, backend key, project name, and secret/parameter names.

---

## A) Permission Model

Terraform automation needs five permission groups.

| Group | Plan role | Apply role | Notes |
| --- | --- | --- | --- |
| Backend state | yes | yes | state object and `.tflock` |
| Read/refresh | yes | yes | `Describe*`, `Get*`, `List*` |
| Mutate infrastructure | no | yes, but scoped | create/update/delete managed resources |
| IAM management | no | limited yes | only lab roles/policies |
| `iam:PassRole` | no | limited yes | only approved runtime roles to EC2 |

Core rule:

```text
Plan role reads.
Apply role changes.
Break-glass role is separate.
```

---

## B) Backend State Permissions

With S3 backend and `use_lockfile = true`, Terraform needs access to two objects:

```text
s3://<bucket>/<state-key>
s3://<bucket>/<state-key>.tflock
```

For this lab:

```text
lab69/dev/full/terraform.tfstate
lab69/dev/full/terraform.tfstate.tflock
```

The state permissions must be available to both plan and apply roles because both jobs run `terraform init`, refresh state, and acquire/release locks.

Minimum shape:

```json
{
  "Sid": "ReadWriteStateObjects",
  "Effect": "Allow",
  "Action": [
    "s3:GetObject",
    "s3:PutObject",
    "s3:DeleteObject"
  ],
  "Resource": [
    "arn:aws:s3:::STATE_BUCKET/lab69/dev/full/terraform.tfstate",
    "arn:aws:s3:::STATE_BUCKET/lab69/dev/full/terraform.tfstate.tflock"
  ]
}
```

Why does plan need `PutObject` and `DeleteObject`?

Because the lockfile is created and removed during Terraform operations. Plan is read-only for infrastructure, not read-only for backend locking.

---

## C) Plan Role

The plan role should be able to:

- initialize backend
- acquire/release lock
- read state
- refresh AWS resources
- generate a plan

It should not be able to create/update/delete infrastructure, pass roles, change policies.

The lab now uses a purpose-built plan policy instead of AWS managed `ReadOnlyAccess`.

Plan read actions include service areas Terraform must refresh:

```text
ec2:Describe*
elasticloadbalancing:Describe*
autoscaling:Describe*
cloudwatch:Describe*/Get*/List*
iam:Get*/List*
ssm:GetParameter
secretsmanager:DescribeSecret
```

Some read APIs do not support resource-level scoping. For those actions, `Resource = "*"` is normal. Least privilege is not only about resource ARNs; it is also about narrowing actions, trust, state keys, and role purpose.

Acceptance:

- [ ] plan role can run `terraform plan`
- [ ] plan role cannot run `terraform apply`
- [ ] plan role cannot call mutate APIs such as `ec2:CreateVpc`

---

## D) Apply Role

The apply role needs mutation rights, but only for the stack it manages.

In this lab, apply permissions are grouped by service area:

- backend state and lockfile
- read/refresh APIs
- EC2/VPC/subnets/routes/security groups/VPC endpoints/instances/launch templates
- ELBv2 ALB/target group/listener
- Auto Scaling group/policy/instance refresh
- CloudWatch alarms
- lab IAM roles, instance profiles, OIDC provider, and inline policies
- restricted `iam:PassRole`
- restricted `iam:CreateServiceLinkedRole` for AWS service-linked roles when needed

This is significantly less than `AdministratorAccess`, because it does not provide access to all AWS services.

Why is there still `Resource = "*"`?

Because some AWS `mutation APIs` have poor or only partial support for `resource-level scoping`.

For example, many EC2 `create/delete` operations are more practical and realistic to control through:

- narrow `action list`
- narrow `OIDC trust`
- narrow `backend key`
- project naming convention: `lab69-*`
- `tags`
- `conditions` where possible
- `policy review`
- `destroy guard / policy gates`

Production rule:

```text
If Resource must be *, narrow the action list and trust policy.
If Action must be broad, narrow the resource and conditions.
If both must be broad, document why and add a compensating control.
```

---

## E) IAM Self-Management Caveat

In the `lab apply role`, IAM resources can be managed by pattern:

- `arn:aws:iam::<account-id>:role/lab69-*`
- `arn:aws:iam::<account-id>:instance-profile/lab69-*`

That includes the GitHub plan/apply roles themselves.

This is useful for a single-account training lab, but in production it creates a bootstrap risk:

```text
A pipeline that can edit its own policy can accidentally or maliciously widen itself.
```

Production options:

- manage CI roles in a separate identity/bootstrap stack
- protect CI role policy changes with CODEOWNERS and required reviewers
- use permissions boundaries for roles Terraform creates
- use SCPs or organization-level guardrails
- keep a separate break-glass path for recovery

---

## F) `iam:PassRole` Contract

`iam:PassRole` is one of the most important permissions in Terraform automation. It is dangerous because it allows one AWS service to receive an IAM role.

For example, an EC2 instance does not get IAM permissions by itself. An instance profile is attached to it, and inside that instance profile there is a role:

```text
EC2 instance
-> instance profile
-> IAM role
-> permissions
```

To let Terraform create an EC2 instance with an instance profile, the apply role must have `iam:PassRole`.

But if you do this:

```json
{
  "Action": "iam:PassRole",
  "Resource": "*"
}
```

Then the pipeline will be able to pass any role to EC2, including an `admin runtime role`, if such a role exists.

The lab policy uses a tighter shape:

```json
{
  "Sid": "PassOnlyLabRuntimeRolesToEc2",
  "Effect": "Allow",
  "Action": "iam:PassRole",
  "Resource": "arn:aws:iam::<account-id>:role/${var.project_name}-ec2-ssm-role",
  "Condition": {
    "StringEquals": {
      "iam:PassedToService": "ec2.amazonaws.com"
    }
  }
}
```

This means the `apply role` can pass only the lab EC2 SSM role and only to the EC2 service.

Not allowed:

- pass an arbitrary `admin role`
- pass a `Lambda role`
- pass an `ECS role`
- use `PassRole` as a general `escalation path`

Acceptance:

- [ ] approved EC2 runtime role can be passed
- [ ] arbitrary admin role cannot be passed
- [ ] denied PassRole attempt is captured as proof

---

## G) OIDC Trust Hardening

Permissions policy answers:
- what the `role` is allowed to do

Trust policy answers:
- who is allowed to use the `role`

GitHub Actions does not store AWS keys. It receives an `OIDC token` and performs:

```text
GitHub OIDC token -> AWS STS AssumeRoleWithWebIdentity -> temporary AWS credentials
```

`Plan role` trust:

```text
repo:<owner>/<repo>:pull_request
repo:<owner>/<repo>:ref:refs/heads/main
```

That means `plan` can run from both `PR` and `main`.

`Apply role` trust only:

```text
repo:<owner>/<repo>:environment:terraform-dev
```

This means:

```text
PR job cannot assume the apply role
branch job without environment cannot assume the apply role
only a job through GitHub Environment terraform-dev can receive apply credentials
```

If `terraform-dev` exists, but there are no `required reviewers` / `wait timer`, then the `trust subject` will be correct, but the `human gate` will be weak.

Trust policy checklist:

- `aud` = `sts.amazonaws.com`
- plan role accepts PR and protected branch subjects only
- apply role accepts environment subject only
- environment has reviewers or wait timer
- no wildcard repo owner
- no wildcard environment name
- GitHub Environment has protection rules

---

## H) Iterative Least-Privilege Workflow

Least privilege is rarely correct on the first attempt.

Use this loop:

```text
1. Start from working broad role
2. Remove broad managed policy
3. Attach candidate scoped policy
4. Run plan/apply drill
5. Capture AccessDenied
6. Add only the missing action/resource
7. Repeat
8. Review with Access Analyzer / last accessed data
9. Capture proof
```

If `AccessDenied` appears during a normal safe `apply`, it means:

- the policy is too narrow for a legitimate operation and must be expanded minimally.

Example of a bad reaction:

```text
AccessDenied on ec2:CreateTags
-> restore AdministratorAccess
```

Example of the correct reaction:

```text
AccessDenied on ec2:CreateTags
-> add ec2:CreateTags
-> restrict Resource/Condition where possible
-> document why it was added
```

Access Analyzer can generate policy templates from CloudTrail access activity. That is useful, but it is not a substitute for engineering review.

When reviewing generated policy:

- remove unrelated actions
- split backend from infrastructure permissions
- keep `iam:PassRole` explicit
- avoid wildcarding IAM resources unless documented
- keep negative tests proving what the role cannot do

---

## I) Drills

### Drill 1 - Confirm admin is gone

Check that the apply role no longer has `AdministratorAccess`.

```bash
aws iam list-attached-role-policies \
  --role-name lab69-github-actions-apply-role \
  --output table
```

Expected:

- no `AdministratorAccess`
- scoped inline policy exists

Capture:

```bash
aws iam list-role-policies \
  --role-name lab69-github-actions-apply-role \
  --output json > apply-role-inline-policies.json
```

---

### Drill 2 - Plan role can plan

Goal: prove that `lab69-github-actions-role` has enough permissions for `backend lock` + `refresh` + `terraform plan`.

Run:

```bash
gh workflow list
```

Run the required workflow from the list:

```bash
gh workflow run lesson69-terraform-apply-dev.yml \
  -f confirm_apply=APPLY
```

Run watch:

```bash
gh run watch
```

Expected:

- backend init works
- refresh works
- plan is produced

---

### Drill 3 - Plan role cannot apply

Temporarily configure a test run to use the plan role for apply, or run a harmless direct mutation command with that role.

Expected:

```text
AccessDenied
```

Do not keep this as the normal workflow. It is a negative proof drill.

---

### Drill 4 - Apply role can make a safe change

Make a low-risk change such as a CloudWatch alarm description or a harmless tag.

```json
common_tags = {
  Owner = "DevOpsTrack"
  Drill = "safe-apply"
}
```

Expected:

- `plan-dev` creates plan artifact
- reviewer approves `terraform-dev`
- `apply-dev` applies exact `tfplan`
- post-apply plan exit code is `0`

---

### Drill 5 - PassRole boundary

Try to change the launch template or instance profile path to use a non-lab role.

```json
  dynamic "iam_instance_profile" {
    for_each = var.enable_web_ssm ? [1] : []
    content {
      name = "l69-passrole-denied-dummy-profile"
    }
```

Expected:

```text
iam:PassRole denied
```

Revert immediately after capturing proof.

---

### Drill 6 - Wrong OIDC subject cannot assume apply role

Try to assume the apply role from a job that does not use environment `terraform-dev`.

Expected:

```text
Could not assume role with OIDC
```

This proves trust policy matters as much as permissions policy.

---

## J) Proof Pack

Suggested evidence folder:

```text
lessons/69-production-iam-least-privilege-plan-and-apply-roles/evidence/l69-YYYYmmdd_HHMMSS/
```

Capture:

```text
apply-role-attached-policies.json
apply-role-inline-policies.json
plan-role-inline-policies.json
apply-role-trust-policy.json
plan-role-trust-policy.json
plan-role-plan-success.txt
plan-role-apply-denied.txt
apply-safe-change-run.md
passrole-denied.txt
access-analyzer-notes.md
```

---

## Common Pitfalls

- replacing `AdministratorAccess` with another broad managed policy and calling it least privilege
- forgetting backend lockfile permissions
- expecting every AWS action to support resource-level scoping
- using `iam:PassRole` with `Resource = "*"`
- allowing PR jobs to assume apply role
- letting the pipeline edit its own permissions without review
- deleting the break-glass path before proving recovery
- trusting Access Analyzer output without pruning it

---

## Final Acceptance

- [ ] plan role has scoped backend and read/refresh permissions
- [ ] plan role does not have mutate permissions
- [ ] apply role does not have `AdministratorAccess`
- [ ] apply role has scoped backend, read, mutate, IAM, and PassRole permissions
- [ ] apply trust is bound to GitHub Environment `terraform-dev`
- [ ] `iam:PassRole` is restricted to approved EC2 runtime role and service
- [ ] negative drill proves plan role cannot apply
- [ ] negative drill proves wrong OIDC subject cannot assume apply role
- [ ] safe apply still works
- [ ] proof pack is captured and redacted

---

## Lesson Summary

- **What you learned:** how to move from controlled apply with broad permissions to controlled apply with scoped IAM.
- **What you practiced:** plan/apply role separation, backend lockfile permissions, scoped apply policy, PassRole boundaries, OIDC trust hardening.
- **Advanced skill:** iterative least-privilege refinement using denial evidence and Access Analyzer.
- **Operational focus:** remove `AdministratorAccess` from normal delivery while keeping recovery paths explicit.
