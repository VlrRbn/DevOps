# Lesson 85: Lambda SNS-to-SQS Fan-out and Filtering

This lesson extends the Lambda messaging track from one queue to multiple
independent consumer branches. One producer publishes a business event to an
Amazon SNS topic. SNS copies every matching event to dedicated SQS queues, and
separate Lambda functions consume those queues at their own pace.

## Files

- `lesson.en.md` / `lesson.ru.md` - full lesson text.
- `lab_85/app/lambda_function.py` - shared audit/billing consumer with standard-queue partial failures.
- `lab_85/tests/` - local tests for raw delivery, event contracts, and branch-specific failure.
- `lab_85/events/` - successful and mixed local SQS batches.
- `lab_85/scripts/publish-event.sh` - guarded SNS publisher with an `event_type` attribute.
- `lab_85/terraform/` - SNS, SQS, Lambda, IAM, filter policy, DLQs, and alarms.
- `lab_85/terraform/tests/` - native Terraform tests for fan-out boundaries.
- `lab_85/evidence/` - ignored local folder for temporary results.
- `lab_85/README.md` - lab architecture and file layout.

## Quick Start

From the repository root, run local tests first:

```bash
python3 -m unittest discover \
  -s lessons/85-lambda-sns-sqs-fanout-and-filtering/lab_85/tests -v

bash -n lessons/85-lambda-sns-sqs-fanout-and-filtering/lab_85/scripts/publish-event.sh
shellcheck lessons/85-lambda-sns-sqs-fanout-and-filtering/lab_85/scripts/publish-event.sh

for script in lessons/85-lambda-sns-sqs-fanout-and-filtering/lab_85/scripts/*.sh; do
  bash -n "$script"
done
```

Then prepare and validate the Terraform root:

```bash
cd lessons/85-lambda-sns-sqs-fanout-and-filtering/lab_85/terraform
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

Continue with the fan-out, filtering, failure-isolation, and cleanup drills in
`lesson.en.md` or `lesson.ru.md`.

## Main Flow

```text
publisher
  -> SNS topic
     -> audit subscription (no filter)
        -> audit SQS -> audit Lambda -> audit DLQ
     -> billing subscription (event_type filter)
        -> billing SQS -> billing Lambda -> billing DLQ
```

## Requirements

- Terraform `~> 1.14.0`
- AWS CLI v2
- Python 3
- `jq`
- `shellcheck` for the local script check
- authenticated AWS credentials that can manage the lab's SNS, SQS, Lambda,
  IAM, CloudWatch Logs, and CloudWatch alarm resources

## Safety Notes

- Both Lambda functions have no public endpoint and perform no external business action.
- Source queue policies accept `SendMessage` only from the lesson SNS topic.
- The failure drill affects only the disposable billing branch.
- SNS filter policy changes are eventually consistent and can take up to 15 minutes.
- Raw SQS delivery is limited to ten SNS message attributes; this lab uses one.
- Evidence can contain account IDs, ARNs, message IDs, order IDs, and timestamps.
- Run `terraform destroy` after completing the drills.

## What This Lesson Intentionally Does Not Add

- No direct SNS-to-Lambda subscription; SQS provides buffering and branch isolation.
- No SNS FIFO topic; ordering and deduplication were covered in lesson 84.
- No transactional outbox or schema registry.
- No cross-account topic or queue policies.

These boundaries keep the lesson focused on pub/sub fan-out, subscription
filtering, raw delivery, queue authorization, and failure isolation.
