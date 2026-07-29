# Lesson 79: Lambda IAM and Invocation Permissions

This lesson continues the Lambda fundamentals lab by separating the operator
identity, Lambda caller role, function execution role, and function resource
policy.

## Files

- `lesson.en.md` / `lesson.ru.md` - full lesson text.
- `lab_79/app/lambda_function.py` - Lambda handler and testable application logic.
- `lab_79/tests/` - local Python unit tests.
- `lab_79/terraform/` - Lambda and IAM authorization lab.
- `lab_79/terraform/tests/` - native Terraform tests for all grant modes.
- `lab_79/scripts/` - safe caller resolution and assumed-role invocation helpers.
- `lab_79/README.md` - lab layout and authorization mode matrix.
- `lab_79/evidence/` - ignored local folder for temporary invocation results.

## Quick Start

From the repository root, run local tests first:

```bash
python3 -m unittest discover \
  -s lessons/79-lambda-iam-invocation-permissions/lab_79/tests -v

bash -n lessons/79-lambda-iam-invocation-permissions/lab_79/scripts/*.sh
```

Then prepare and validate the Terraform root:

```bash
cd lessons/79-lambda-iam-invocation-permissions/lab_79/terraform
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform fmt -check -recursive
terraform validate
terraform test
```

Resolve the existing operator identity that may assume the Lambda caller role:

```bash
../scripts/resolve-operator-principal.sh
```

Copy its output to `operator_iam_principal_arn` in `terraform.tfvars`, then follow
the three authorization phases in the lesson.

## Main Flow

```text
operator IAM identity
-> sts:AssumeRole
-> Lambda caller role
-> Lambda authorization decision
-> Python handler
-> execution role writes CloudWatch Logs
```

## Requirements

- Terraform `~> 1.14.0`
- AWS CLI v2
- Python 3
- `jq`
- authenticated IAM user that can create the lab resources and assume the generated Lambda caller role
- `iam:GetRole` for automatic resolution of an IAM Identity Center role ARN;
  otherwise set `operator_iam_principal_arn` manually

## Safety Notes

- The lab creates no IAM users or access keys.
- `none` mode is an intentional denied invocation, not a deployment failure.
- Temporary STS credentials are not printed or saved.
- Do not grant `lambda:*` or `Resource = "*"` to make the drill pass.
- Review files under `lab_79/evidence/` before sharing.
- Run `terraform destroy` after the lab.

## What This Lesson Intentionally Does Not Add

- No cross-account invocation.
- No API Gateway, SQS, EventBridge, VPC, or public endpoint.
- No separate proof-pack document.
- No permissions boundary or organization SCP.

These mechanisms are discussed where they affect the authorization decision,
but the lab stays focused on one same-account function invocation.
