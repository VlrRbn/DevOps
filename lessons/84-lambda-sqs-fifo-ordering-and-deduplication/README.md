# Lesson 84: Lambda SQS FIFO Ordering and Deduplication

This lesson continues the Lambda and SQS track by replacing the standard source queue
with a FIFO queue. It demonstrates per-group ordering, parallel processing across groups,
explicit producer deduplication, and the failure barrier required for a FIFO partial
batch response.

## Files

- `lesson.en.md` / `lesson.ru.md` - full lesson text.
- `lab_84/app/lambda_function.py` - FIFO-aware batch worker that stops after the first failure.
- `lab_84/tests/` - local tests for FIFO attributes, ordering, and the failure barrier.
- `lab_84/events/` - successful, failed, and invalid local SQS FIFO events.
- `lab_84/scripts/` - ordered sequence and duplicate-pair senders.
- `lab_84/terraform/` - FIFO source queue, FIFO DLQ, Lambda, IAM, mapping, and alarms.
- `lab_84/terraform/tests/` - native Terraform tests for FIFO and retry contracts.
- `lab_84/evidence/` - ignored local folder for temporary results.
- `lab_84/README.md` - lab architecture and file layout.

## Quick Start

From the repository root, run local tests first:

```bash
python3 -m unittest discover \
  -s lessons/84-lambda-sqs-fifo-ordering-and-deduplication/lab_84/tests -v

for script in lessons/84-lambda-sqs-fifo-ordering-and-deduplication/lab_84/scripts/*.sh; do
  bash -n "$script"
done
```

Then prepare and validate the Terraform root:

```bash
cd lessons/84-lambda-sqs-fifo-ordering-and-deduplication/lab_84/terraform
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
terraform show -no-color tfplan | less
terraform apply tfplan
```

Follow the single-group, multi-group, deduplication, failure-barrier, and cleanup
drills in `lesson.en.md` or `lesson.ru.md`.

## Main Flow

```text
producer -> explicit MessageGroupId + MessageDeduplicationId
         -> SQS FIFO source queue
         -> Lambda event source mapping
         -> ordered processing inside each group
         -> parallel processing across different groups
         -> first batch failure returns failed + unprocessed records
         -> returned records consume their own receive budgets
         -> poison and deferred tail records may both reach the FIFO DLQ
```

## Requirements

- Terraform `~> 1.14.0`
- AWS CLI v2
- Python 3
- `jq`
- authenticated AWS credentials that can manage the lab's Lambda, IAM, SQS,
  CloudWatch Logs, and CloudWatch alarm resources

## Safety Notes

- The function has no public endpoint and performs no external business action.
- Work duration is bounded to three seconds by the message contract.
- Explicit deduplication IDs are scoped to disposable lab runs.
- The poison-message drill intentionally blocks one FIFO group until retries are exhausted.
- With `BatchSize > 1`, valid records returned after a poison record can exhaust
  their receive budgets and reach the DLQ without running business logic.
- Queue inspection must not receive from the source queue while Lambda is polling.
- Evidence can contain message IDs, deduplication IDs, group IDs, and timestamps.
- Run `terraform destroy` after completing the drills.

## What This Lesson Intentionally Does Not Add

- No content-based deduplication; the producer contract remains explicit.
- No global ordering claim across different message groups.
- No high-throughput FIFO mode or provisioned pollers.
- No external database or duplicate-sensitive side effect.

These boundaries keep the lab focused on FIFO ordering scope, deduplication, parallel
message groups, and correct failure handling.
