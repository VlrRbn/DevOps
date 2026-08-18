# Lesson 83: Lambda SQS Scaling, Concurrency, and Backpressure

This lesson continues the Lambda and SQS track by moving from correct batch
handling to controlled throughput. A burst of bounded work enters a standard
SQS queue while one event source mapping limits the worker to two concurrent
Lambda invocations.

## Files

- `lesson.en.md` / `lesson.ru.md` - full lesson text.
- `lab_83/app/lambda_function.py` - SQS batch worker with structured timing logs.
- `lab_83/tests/` - local unit tests for the message and batch contracts.
- `lab_83/events/` - valid, fast, and invalid work-item examples.
- `lab_83/scripts/send-burst.sh` - sends deterministic SQS message bursts.
- `lab_83/scripts/sample-backlog.sh` - samples queue depth without receiving messages.
- `lab_83/terraform/` - source queues, Lambda, IAM, event source scaling, and alarms.
- `lab_83/terraform/tests/` - native Terraform tests for concurrency and timeout contracts.
- `lab_83/evidence/` - ignored local folder for temporary results.
- `lab_83/README.md` - lab architecture and file layout.

## Quick Start

From the repository root, run local tests first:

```bash
python3 -m unittest discover \
  -s lessons/83-lambda-sqs-scaling-concurrency-backpressure/lab_83/tests -v

for script in lessons/83-lambda-sqs-scaling-concurrency-backpressure/lab_83/scripts/*.sh; do
  bash -n "$script"
done
```

Then prepare and validate the Terraform root:

```bash
cd lessons/83-lambda-sqs-scaling-concurrency-backpressure/lab_83/terraform
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

Follow the burst, backlog, metrics, negative drills, and cleanup sequence in
`lesson.en.md` or `lesson.ru.md`.

## Main Flow

```text
20 work items -> standard SQS queue
              -> event source mapping MaximumConcurrency = 2
              -> at most two in-flight Lambda invocations from this source
              -> backlog grows, then drains
              -> queue age and depth expose backpressure
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
- Work duration is bounded to ten seconds by the message contract.
- The event source mapping cap is two concurrent invocations.
- Reserved concurrency is `null` by default to avoid consuming a scarce
  training-account quota.
- Queue inspection never receives or hides source messages.
- Evidence may contain message identifiers and timestamps; review before sharing.
- Run `terraform destroy` after completing the drills.

## What This Lesson Intentionally Does Not Add

- No provisioned concurrency or SQS provisioned poller mode.
- No FIFO queue, message groups, or ordering guarantee.
- No automatic scaling based on queue depth.
- No external database, API, email, or payment dependency.

These boundaries keep the lab focused on concurrency limits, throughput,
backlog, throttling, and backpressure.
