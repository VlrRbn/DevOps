# Lesson 86: Lambda EventBridge Routing and Event Patterns

This lesson extends the Lambda messaging track from SNS subscription filtering to
content-based routing on a custom Amazon EventBridge bus. Two rules inspect the
same event envelope and route matching events into isolated SQS-to-Lambda consumer
branches.

## Files

- `lesson.en.md` / `lesson.ru.md` - full lesson text and runtime drills.
- `lab_86/app/lambda_function.py` - shared audit/high-value SQS consumer.
- `lab_86/tests/` - local tests for envelopes, validation, and partial failures.
- `lab_86/events/` - complete EventBridge events used to test rule patterns.
- `lab_86/patterns/` - audit and numeric high-value event patterns.
- `lab_86/scripts/put-event.sh` - guarded custom-event publisher.
- `lab_86/terraform/` - event bus, rules, targets, SQS, Lambda, IAM, DLQs, and alarms.
- `lab_86/terraform/tests/` - native Terraform tests for routing boundaries.
- `lab_86/evidence/` - ignored local folder for temporary runtime results.
- `lab_86/README.md` - lab architecture and file layout.

## Quick Start

From the repository root, run local checks first:

```bash
python3 -m unittest discover \
  -s lessons/86-lambda-eventbridge-routing-and-event-patterns/lab_86/tests -v

bash -n \
  lessons/86-lambda-eventbridge-routing-and-event-patterns/lab_86/scripts/put-event.sh

shellcheck \
  lessons/86-lambda-eventbridge-routing-and-event-patterns/lab_86/scripts/put-event.sh
```

Then prepare and validate the Terraform root:

```bash
cd lessons/86-lambda-eventbridge-routing-and-event-patterns/lab_86/terraform
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform fmt -check -recursive
terraform validate
terraform test
```

Authenticate before testing live EventBridge patterns or creating a saved plan:

```bash
export AWS_PROFILE=YOUR_PROFILE
aws sso login --profile "$AWS_PROFILE"
aws sts get-caller-identity
terraform plan -out=tfplan
terraform show -no-color tfplan | less
terraform apply tfplan
```

Continue with the routing, filtering, delivery-failure, processing-failure, and
cleanup drills in `lesson.en.md` or `lesson.ru.md`.

## Main Flow

```text
publisher -> custom EventBridge bus
  -> audit rule: created OR refunded
     -> audit SQS -> audit Lambda -> audit processing DLQ
     -> audit delivery DLQ if EventBridge cannot reach SQS
  -> high-value rule: created AND amount >= 100
     -> high-value SQS -> high-value Lambda -> high-value processing DLQ
     -> high-value delivery DLQ if EventBridge cannot reach SQS
```

## Requirements

- Terraform `~> 1.14.0`
- AWS CLI v2
- Python 3
- `jq`
- `shellcheck` for the publisher check
- authenticated AWS credentials that can manage the lab's EventBridge, SQS,
  Lambda, IAM, CloudWatch Logs, and CloudWatch alarm resources

## Safety Notes

- Both Lambda functions have no public endpoint and perform no external business action.
- Source queue policies accept `SendMessage` only from the corresponding EventBridge rule.
- EventBridge target DLQs and SQS processing DLQs are intentionally separate.
- The delivery-failure drill temporarily introduces drift in one disposable dev queue policy.
- `PutEvents` acceptance does not prove that any rule matched the event.
- Evidence can contain account IDs, ARNs, message IDs, order IDs, and timestamps.
- Run `terraform destroy` after completing the drills.

## What This Lesson Intentionally Does Not Add

- No EventBridge Pipes, Scheduler, archive, replay, schema registry, or global endpoint.
- No direct EventBridge-to-Lambda target; SQS keeps buffering and branch isolation visible.
- No cross-account or cross-Region event bus policy.

These boundaries keep the lesson focused on event envelopes, event patterns,
target permissions, retries, and the distinction between delivery and processing failures.
