# Lesson 78: AWS Lambda Fundamentals

This lesson starts the AWS Lambda and serverless operations track. It builds
one small Python Lambda function without hiding the execution model behind API
Gateway, queues, or a delivery pipeline.

## Files

- `lesson.en.md` / `lesson.ru.md` - full lesson text.
- `lab_78/app/lambda_function.py` - Lambda handler and testable application logic.
- `lab_78/tests/` - local Python unit tests.
- `lab_78/events/` - valid and invalid invocation payloads.
- `lab_78/terraform/` - standalone Terraform root for the Lambda, IAM role, and log group.
- `lab_78/README.md` - lab layout and function execution flow.
- `lab_78/evidence/` - ignored local folder for temporary invocation results.

## Quick Start

From the repository root, run local tests first:

```bash
python3 -m unittest discover -s lessons/78-aws-lambda-fundamentals/lab_78/tests -v
```

Then prepare and validate the Terraform root:

```bash
cd lessons/78-aws-lambda-fundamentals/lab_78/terraform
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform fmt -check -recursive
terraform validate
```

Authenticate to AWS before creating a plan. For an IAM Identity Center profile,
for example:

```bash
export AWS_PROFILE=YOUR_PROFILE
aws sso login --profile "$AWS_PROFILE"
aws sts get-caller-identity
terraform plan -out=tfplan
terraform apply tfplan
```

Use the invocation, log inspection, negative drills, and cleanup commands in
`lesson.en.md` or `lesson.ru.md`.

## Main Flow

```text
JSON event
-> Lambda service
-> Python handler(event, context)
-> JSON response
-> CloudWatch Logs
```

The lab verifies the flow at several layers:

```text
local unit tests
-> Terraform fmt and validate
-> reviewed saved plan
-> real Lambda invocation
-> CloudWatch Logs
-> negative invocation checks
-> terraform destroy
```

## Requirements

- Terraform `~> 1.14.0`
- AWS CLI v2
- Python 3
- `jq`
- authenticated AWS credentials with permission to manage the lab's Lambda, IAM,
  and CloudWatch Logs resources

The lab commits `.terraform.lock.hcl` so repeated runs verify the same provider
package checksums.

## Safety Notes

- The function has no public endpoint.
- The execution role can write only to its own log group.
- Timeout and memory are bounded; concurrency reservation is optional because
  low-quota training accounts may be unable to reserve capacity.
- Environment variables in this lesson are configuration, not secrets.
- Invocation files under `lab_78/evidence/` are ignored; review them before
  sharing because error output and request metadata are operational data.
- Run `terraform destroy` after the lab.

## What This Lesson Intentionally Does Not Add

- No remote Terraform backend or CI workflow.
- No API Gateway, SQS, EventBridge, VPC, or public endpoint.
- No separate proof-pack document.
- No third-party Python dependency.
- No VPC, DLQ, X-Ray, code signing, or customer-managed KMS key merely to make
  generic scanner findings disappear.

These omissions keep the first Lambda lesson focused. They are not production
recommendations; later lessons introduce them where their operational purpose is
clear.
