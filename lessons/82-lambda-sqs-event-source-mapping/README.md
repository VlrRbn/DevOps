# Lesson 82: Lambda SQS Event Source Mapping

This lesson continues the Lambda track by turning SQS into an event source rather
than a failure destination. Lambda polls a standard queue, invokes one function
with a batch, acknowledges successful records, and retries only identifiers
returned through `ReportBatchItemFailures`.

## Files

- `lesson.en.md` / `lesson.ru.md` - full lesson text.
- `lab_82/app/lambda_function.py` - SQS batch consumer and partial failure response.
- `lab_82/tests/` - local unit tests for record validation and failure isolation.
- `lab_82/events/` - success, poison, and invalid message bodies.
- `lab_82/scripts/` - safe send, queue-attribute inspection, and non-deleting DLQ inspection.
- `lab_82/terraform/` - source queue, DLQ, Lambda, IAM, event source mapping, and alarms.
- `lab_82/terraform/tests/` - native Terraform tests for queue and batch contracts.
- `lab_82/evidence/` - ignored local folder for temporary results.
- `lab_82/README.md` - lab architecture and file layout.

## Quick Start

From the repository root, run local tests first:

```bash
python3 -m unittest discover \
  -s lessons/82-lambda-sqs-event-source-mapping/lab_82/tests -v

bash -n lessons/82-lambda-sqs-event-source-mapping/lab_82/scripts/*.sh
```

Then prepare and validate the Terraform root:

```bash
cd lessons/82-lambda-sqs-event-source-mapping/lab_82/terraform
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform fmt -check -recursive
terraform validate
terraform test
```

Authenticate before creating a saved plan:

```bash
export AWS_PROFILE=YOUR_PROFILE
aws sso login --profile "$AWS_PROFILE"
aws sts get-caller-identity
terraform plan -out=tfplan
terraform apply tfplan
```

Follow the success, poison-message, DLQ, observability, and cleanup sequence in
`lesson.en.md` or `lesson.ru.md`.

## Main Flow

```text
producer -> SQS source queue
         -> Lambda event source mapping polls a batch
         -> handler returns batchItemFailures
         -> successful records are deleted
         -> failed records become visible again
         -> exhausted poison message moves to the DLQ
```

## Requirements

- Terraform `~> 1.14.0`
- AWS CLI v2
- Python 3
- `jq`
- authenticated AWS credentials that can manage Lambda, IAM, SQS, CloudWatch
  Logs, and CloudWatch alarms for the disposable lab

## Safety Notes

- The function has no public endpoint.
- The execution role consumes only the exact source queue and cannot read the DLQ.
- `receive-messages.sh` does not delete inspected DLQ messages.
- Do not run `receive-message` against the source queue while Lambda is polling;
  an operator can temporarily hide work from the consumer.
- Queue bodies and logs can contain business data; review evidence before sharing.
- Run `terraform destroy` after completing the drills.

## What This Lesson Intentionally Does Not Add

- No FIFO queue or ordering guarantee.
- No Powertools Batch Processor dependency; the response contract remains visible.
- No automatic DLQ redrive because remediation must happen before replay.
- No external side effect or duplicate-sensitive business action.

These boundaries keep the lesson focused on SQS polling, batch acknowledgement,
visibility, retry, and redrive semantics.
