# Lesson 80: Lambda Async Retries and Failure Destinations

This lesson continues the Lambda track by moving from a synchronous request to
Lambda's managed asynchronous event queue. It demonstrates why `202 Accepted`
does not prove handler success, how retries change processing semantics, and how
an SQS failure destination preserves the final invocation record.

## Files

- `lesson.en.md` / `lesson.ru.md` - full lesson text.
- `lab_80/app/lambda_function.py` - Lambda handler with explicit success and
  failure paths.
- `lab_80/tests/` - local unit tests for the event contract.
- `lab_80/events/` - success, failure, and invalid events.
- `lab_80/scripts/` - asynchronous invocation and event-specific,
  non-destructive SQS inspection.
- `lab_80/terraform/` - Lambda, IAM, SQS, event invoke configuration, and alarms.
- `lab_80/terraform/tests/` - native Terraform tests for retry and queue controls.
- `lab_80/evidence/` - ignored local folder for temporary results.
- `lab_80/README.md` - lab architecture and file layout.

## Quick Start

From the repository root, run local tests first:

```bash
python3 -m unittest discover \
  -s lessons/80-lambda-async-retries-and-failure-destinations/lab_80/tests -v

bash -n \
  lessons/80-lambda-async-retries-and-failure-destinations/lab_80/scripts/*.sh
```

Then prepare and validate the Terraform root:

```bash
cd lessons/80-lambda-async-retries-and-failure-destinations/lab_80/terraform
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform fmt -check -recursive
terraform validate
terraform test
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

Use the success, failure, retry, destination, and cleanup sequence from
`lesson.en.md` or `lesson.ru.md`.

## Main Flow

```text
AWS CLI --invocation-type Event
-> Lambda asynchronous event queue
-> handler attempt
-> one retry after failure
-> SQS on-failure destination
-> operator inspects the invocation record
```

## Requirements

- Terraform `~> 1.14.0`
- AWS CLI v2
- Python 3
- `jq`
- authenticated AWS credentials that can manage the lab's Lambda, IAM, SQS,
  CloudWatch Logs, and CloudWatch alarm resources

## Safety Notes

- The function has no public endpoint.
- Retry count and event age are bounded.
- The SQS queue uses SQS-managed encryption and one-day retention.
- `receive-failure.sh` does not delete the received message.
- Failure records can contain the original event and operational metadata;
  review them before sharing.
- Run `terraform destroy` after completing the drills.

## What This Lesson Intentionally Does Not Add

- No API Gateway, EventBridge, SNS, or public endpoint.
- No SQS event source mapping; the queue is an on-failure destination only.
- No DynamoDB idempotency store.
- No VPC, X-Ray, code signing, or customer-managed KMS key merely to satisfy
  generic scanner findings.

These omissions keep the lesson focused on Lambda-managed asynchronous
invocation, bounded retries, and failure delivery.
