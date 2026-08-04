# Lesson 81: Lambda Idempotency with DynamoDB

This lesson continues the Lambda track by addressing duplicate delivery.
A DynamoDB conditional write lets one handler execution attempt claim an
idempotency key, while later attempts either replay the completed result or stop
behind an active claim.

## Files

- `lesson.en.md` / `lesson.ru.md` - full lesson text.
- `lab_81/app/lambda_function.py` - idempotency state machine.
- `lab_81/tests/` - local unit tests for claims, replay, conflicts, and expiry.
- `lab_81/events/` - valid, conflicting, and invalid example events.
- `lab_81/scripts/` - synchronous invocation and strongly consistent record
  inspection.
- `lab_81/terraform/` - Lambda, DynamoDB, IAM, packaging, logs, and alarms.
- `lab_81/terraform/tests/` - native Terraform tests for the infrastructure
  contract.
- `lab_81/evidence/` - ignored local folder for temporary results.
- `lab_81/README.md` - lab architecture and file layout.

## Quick Start

From the repository root, run local tests first:

```bash
python3 -m unittest discover \
  -s lessons/81-lambda-dynamodb-idempotency/lab_81/tests -v

bash -n lessons/81-lambda-dynamodb-idempotency/lab_81/scripts/*.sh
```

Then prepare and validate the Terraform root:

```bash
cd lessons/81-lambda-dynamodb-idempotency/lab_81/terraform
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

Follow the first-call, replay, conflict, stale-claim, and cleanup sequence in
`lesson.en.md` or `lesson.ru.md`.

## Main Flow

```text
event + idempotency_key
-> conditional PutItem(IN_PROGRESS)
-> one handler execution attempt owns the claim
-> business action
-> conditional UpdateItem(COMPLETED, result)
-> duplicate returns the saved result
```

## Requirements

- Terraform `~> 1.14.0`
- AWS CLI v2
- Python 3
- `jq`
- authenticated AWS credentials that can manage the lab's Lambda, DynamoDB,
  IAM, CloudWatch Logs, and CloudWatch alarm resources

## Safety Notes

- The Lambda function has no public endpoint.
- The runtime role can use only `GetItem`, `PutItem`, and `UpdateItem` on one
  exact DynamoDB table.
- DynamoDB uses on-demand billing, server-side encryption, and TTL.
- The table is intentionally disposable and has no PITR in this isolated lab.
- Idempotency records and saved results can contain business metadata; review
  them before sharing.
- Run `terraform destroy` after completing the drills.

## What This Lesson Intentionally Does Not Add

- No API Gateway, SQS source mapping, EventBridge, or public endpoint.
- No AWS Lambda Powertools dependency; the native state machine is visible for
  study.
- No external payment, email, or provisioning side effect.
- No DynamoDB transaction, outbox, global table, stream, or PITR.

These omissions keep the lesson focused on idempotency boundaries.
