# Lesson 80. Lambda Asynchronous Invocation, Retries, and Failure Destinations

## 1. Why This Lesson Exists

Lessons 78 and 79 established two foundations:

- how a Lambda `handler` runs;
- who can invoke the Lambda function — IAM.

What happens after Lambda accepts work but processes itblater.

With asynchronous invocation, this response:

```json
{
  "StatusCode": 202
}
```

means only:

```text
With an asynchronous invocation, the caller does not wait for the handler to
execute. It submits the event to the Lambda service, receives confirmation that
the event was accepted, and finishes its work.
```

It does not mean that the handler completed successfully. The handler can fail
later, Lambda can retry it, the event can expire, or the failure destination can
reject the final invocation record.

This lesson makes those states visible.

## 2. Outcomes

After the lesson, you will be able to:

- distinguish synchronous and asynchronous Lambda invocation;
- explain why `202 Accepted` is not a business success signal;
- configure bounded retry attempts and maximum event age;
- distinguish the initial attempt from additional retries;
- route failed asynchronous invocation records to SQS;
- explain the difference between a DLQ and a Lambda destination;
- inspect CloudWatch Logs, alarms, and the SQS failure record;
- explain why retryable consumers require idempotency;
- clean up the lab without deleting diagnostic evidence prematurely.

### 2.1. Lesson Terminology

| English term | Plain wording | Precise meaning in this lesson |
|---|---|---|
| `synchronous invocation` | synchronous call | The caller waits for the handler and receives its response |
| `asynchronous invocation` | asynchronous call | Lambda accepts the event and runs the handler separately from the sender request |
| `Lambda asynchronous queue` | internal Lambda async queue | The AWS-managed queue of accepted events; users cannot access it directly |
| `retry` | retry attempt | An additional handler execution after event processing fails |
| `event age` | event age | Time elapsed since the Lambda service accepted the event |
| `failure destination` | failure destination | The resource that receives the final invocation record after retries are exhausted |
| `dead-letter queue (DLQ)` | dead-letter queue | A queue containing the original event that Lambda could not process |
| `invocation record` | invocation record | An envelope containing request, response, context, and execution details for a destination |
| `event_id` | business event ID | A stable event identifier preserved across retry attempts |
| `RequestId` | Lambda request ID | A diagnostic execution identifier assigned by the Lambda service |
| `DestinationDeliveryFailures` | destination delivery failures | The CloudWatch metric for records Lambda could not send to a destination |
| `idempotency` | idempotency | Processing behavior in which a duplicate event does not repeat the business effect |

## 3. Mental Model

### 3.1. Synchronous and Asynchronous Invocation

For `synchronous` invocation `RequestResponse`, the caller waits for the handler:

```text
caller
  -> Lambda service
  -> handler
  -> response or FunctionError
  -> caller
```

Here, the API invocation and the handler execution are connected as a single chain.

For `asynchronous` invocation `Event`, Lambda acknowledges the request before running the handler:

```text
caller
  -> Lambda asynchronous queue
  <- 202 Accepted

Lambda asynchronous queue
  -> handler attempt
  -> retry or completion
  -> optional destination

or

Lambda asynchronous queue
  -> handler failure
  -> retry
  -> failure destination
```

The `caller` invocation and the `handler` execution are now two separate operations.

### 3.2. Acceptance, Processing, and Delivery

Three different questions must be checked:

| Question | Evidence |
|---|---|
| Did Lambda accept the event? | AWS CLI returned `StatusCode = 202` |
| Did the handler process it? | Function logs and Lambda metrics |
| Was the final failure record delivered? | Message in SQS and no `DestinationDeliveryFailures` |

```text
caller
  -> Lambda async queue
  <- 202 Accepted
      only event acceptance is proven

Lambda async queue
  -> handler
      handler invocation is proven

handler
  -> success log
      successful processing is proven

or

handler
  -> failure
  -> retry
  -> SQS failure destination
      delivery of the failure record is proven
```

One signal cannot answer all three questions.

Interpret the situation as follows:

```text
202 is present, but there are no logs
-> the event was accepted, but execution has not yet been proven

a log containing RuntimeError is present
-> the handler was invoked and failed

the handler failed, and an SQS message is present
-> processing failed, but the failure destination worked successfully

the handler failed, SQS is empty,
and DestinationDeliveryFailures is increasing
-> a separate failure occurred while delivering the record to the destination
```

### 3.3. Retry Semantics

The lab configures:

```hcl
maximum_retry_attempts       = 1
maximum_event_age_in_seconds = 300
```

`maximum_retry_attempts = 1` means:

```text
initial attempt + at most one retry = at most two handler attempts
```

It does not mean one total attempt.

The lab produces a retry through a handler exception. Throttling and `429/5xx`
system errors use a different backoff path and can return the event to the queue
until its maximum age is reached. Therefore, `maximum_retry_attempts = 1` is not
a universal limit for every failure type.

```text
Lambda async queue
  -> attempt 1
      -> failure

  -> retry 1
      -> success
         or
      -> failure

retries exhausted
  -> failure destination
```

Lambda asynchronous processing is at-least-once in practice. Duplicate delivery
can occur, and a successful operation can be repeated if failure happens after
the side effect but before completion is recorded.

Therefore a real consumer needs an idempotency strategy, for example:

```text
event_id
  -> check the deduplication store

event_id is absent
  -> store the event_id
  -> perform the action

event_id already exists
  -> do not repeat the action
  -> exit safely
```

This lab includes `event_id` in the contract but intentionally does not add a
DynamoDB deduplication store.

### 3.4. DLQ and Failure Destination

A Lambda dead-letter queue and a Lambda destination are related but not identical:

| Mechanism | Payload |
|---|---|
| Lambda DLQ | Original event plus limited error message attributes |
| On-failure destination | Invocation record with request and response context |

This lab uses an on-failure destination in SQS because it provides richer diagnostic context:

```text
requestContext — service metadata for asynchronous processing: attempt count and completion condition;
requestPayload — the original event passed to the function;
responseContext — the function execution status and error indicator;
responsePayload — the result or exception information.
```

The SQS queue is not an event source for this function. It stores the final
failure record after asynchronous processing ends unsuccessfully.

Flow DLQ:

```text
Lambda async queue
  -> handler
  -> retries exhausted
  -> DLQ
     -> original event
     -> limited error attributes
```

Flow On-failure destination:

```text
Lambda async queue
  -> handler
  -> retry
  -> retries exhausted
  -> SQS destination
     -> full invocation record
```

## 4. Lab Architecture

Terraform creates:

- one Python Lambda worker;
- one execution role for logs and failure delivery;
- one encrypted SQS failure destination;
- one asynchronous event invoke configuration;
- one alarm for handler errors;
- one alarm for destination delivery failures.

You can interpret the architecture as follows:

```text
the caller receives only 202
Lambda manages the queue and retries
the handler writes the result of each attempt to Logs
SQS receives only the final failure record
alarms monitor function execution and destination delivery separately
```

### 4.1. Where to Find Each Resource

After splitting the configuration, each file owns one concern:

| File | Contents |
|---|---|
| `locals.tf` | shared naming convention and tags |
| `package.tf` | Python ZIP packaging |
| `function_execution_role.tf` | execution role and her IAM policy |
| `failure_destination.tf` | SQS queue |
| `lambda.tf` | log group and Lambda function |
| `async_invoke.tf` | retries, event age, and on-failure destination |
| `monitoring.tf` | CloudWatch alarms |
| `outputs.tf` | names and ARNs used by verification commands |

Resource names also state their purpose:

```text
lab80-dev-lambda-async-worker
lab80-dev-role-lambda-execution
lab80-dev-policy-for-role-lambda-execution-allow-logs-and-failure-delivery
lab80-dev-sqs-lambda-failure-destination
```

Flow:

```text
AWS CLI
  |
  | InvocationType=Event
  v
Lambda async queue
  |
  +--> handler success --> CloudWatch Logs
  |
  +--> handler failure --> retry --> SQS failure destination
                         \
                          -> invocation record
```

The lab has no public endpoint and no long-lived access keys.

## 5. Local Checks

From the repository root:

```bash
python3 -m unittest discover \
  -s lessons/80-lambda-async-retries-and-failure-destinations/lab_80/tests -v

bash -n \
  lessons/80-lambda-async-retries-and-failure-destinations/lab_80/scripts/*.sh
```

Then:

```bash
cd lessons/80-lambda-async-retries-and-failure-destinations/lab_80/terraform
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform fmt -check -recursive
terraform validate
terraform test
```

`terraform test` uses a mock AWS provider. It checks configuration structure,
not real retry timing, IAM propagation, or SQS delivery.

## 6. Deploy the Lab

Authenticate first:

```bash
aws sts get-caller-identity
```

Create and review a saved plan:

```bash
terraform plan -out=tfplan
terraform show tfplan
terraform apply tfplan
```

Export outputs used by later commands:

```bash
FUNCTION_NAME="$(terraform output -raw function_name)"
AWS_REGION="$(terraform output -raw aws_region)"
FAILURE_QUEUE_URL="$(terraform output -raw failure_queue_url)"

printf 'function=%s\nregion=%s\nqueue=%s\n' \
  "$FUNCTION_NAME" "$AWS_REGION" "$FAILURE_QUEUE_URL"
```

Confirm the asynchronous configuration:

```bash
aws lambda get-function-event-invoke-config \
  --region "$AWS_REGION" \
  --function-name "$FUNCTION_NAME" \
  --output json | jq .
```

Verify:

- `MaximumRetryAttempts` is `1`;
- `MaximumEventAgeInSeconds` is `300`;
- `DestinationConfig.OnFailure.Destination` is the lab SQS ARN.

## 7. Successful Asynchronous Event

Make the scripts executable:

```bash
chmod +x ../scripts/*.sh
```

Submit a successful event:

```bash
../scripts/invoke-async.sh \
  "$FUNCTION_NAME" \
  "$AWS_REGION" \
  ../events/success.json \
  ../evidence/success-acceptance.json

jq . ../evidence/success-acceptance.json
```

Expected API result:

```json
{
  "StatusCode": 202
}
```

Now inspect the handler evidence:

```bash
aws logs tail "/aws/lambda/$FUNCTION_NAME" \
  --region "$AWS_REGION" \
  --since 10m \
  --format short
```

Find `evt-success-001` and the application record
`"event": "async_event_processed"`. It proves that the handler reached its
successful completion path. Runtime `END`/`REPORT` lines are not sufficient by
themselves because Lambda also writes them around failed attempts.

## 8. Failed Event and Retry

Submit the intentional failure:

```bash
../scripts/invoke-async.sh \
  "$FUNCTION_NAME" \
  "$AWS_REGION" \
  ../events/failure.json \
  ../evidence/failure-acceptance.json
```

The script still expects `202`. That is correct: Lambda accepted a valid API
request even though the handler will reject its payload deliberately.

Watch logs:

```bash
aws logs tail "/aws/lambda/$FUNCTION_NAME" \
  --region "$AWS_REGION" \
  --since 10m \
  --follow \
  --format short
```

Stop `--follow` with `Ctrl+C` after observing the failure attempts.

For an asynchronous retry performed by the Lambda service itself, repeated
processing of the same event can retain the same `RequestId`:

```text
same event_id
+ same RequestId
+ two START entries at different times
+ two RuntimeError entries
=
the initial attempt and one retry performed by Lambda
```

Retry timing is managed by Lambda and is not an exact timer contract. Do not
write automation that assumes the retry happens at one precise second.

### 8.1. `event_id` and Lambda `RequestId`

Do not confuse these two identifiers:

| Identifier  | Created by     | What it represents                    |
| ----------- | -------------- | ------------------------------------- |
| `event_id`  | event sender   | the business event inside the payload |
| `RequestId` | Lambda service | an asynchronous request and its Lambda-managed retry lifecycle |

`RequestId` is a transport diagnostic identifier, not a business event key.
For a retry after a function error that Lambda manages, it can remain the same
across attempts.

#### Retry of the same asynchronous event

The caller submitted the event once. The handler failed, after which Lambda performed the configured retry:

```text
caller
  -> event_id=evt-failure-001
  -> Lambda async queue

attempt 1
  -> RequestId=A
  -> RuntimeError

retry
  -> RequestId=A
  -> RuntimeError
```

Main conclusion:

```text
event_id
-> identifies the business event
-> used for idempotency

RequestId
-> diagnostic identifier of the asynchronous Lambda request
-> can remain the same during a Lambda-managed retry
-> does not replace event_id
```

#### Two Separate Invocations with the Same Payload

In Drill 2, the caller submits the same payload twice:

```text
caller invoke 1
  -> event_id=evt-duplicate-001
  -> RequestId=A

caller invoke 2
  -> event_id=evt-duplicate-001
  -> RequestId=B
```

Different `RequestId` values do not imply different business events.
Conversely, Lambda can deliver an asynchronous event more than once even when
the handler does not fail. Invocation count and `RequestId` therefore cannot
replace an idempotency key.

Without an external deduplication store, the same `event_id` may be processed multiple times.

## 9. Inspect the Failure Destination

Verify three facts:

- After all retries are exhausted, the message actually appears in SQS.
- The message belongs specifically to `evt-failure-001`.
- The invocation record contains two attempts and the function error.

Wait for the final SQS record:

```bash
../scripts/receive-failure.sh \
  "$FAILURE_QUEUE_URL" \
  "$AWS_REGION" \
  ../evidence/failure-record.json \
  evt-failure-001
```

The script uses long polling and may take several minutes while Lambda completes
the retry lifecycle. It receives messages with visibility timeout `0`, selects
the record for the requested `event_id`, and does not delete it. This filter
prevents an earlier drill record from being mistaken for the current result.

Inspect the envelope:

```bash
jq '.Messages[0] | {
  MessageId,
  Attributes,
  Body
}' ../evidence/failure-record.json
```

Decode the destination record stored in `Body`:

```bash
jq -r '.Messages[0].Body' ../evidence/failure-record.json |
  jq '{
    requestContext,
    requestPayload,
    responseContext,
    responsePayload
  }'

or

jq -r '.Messages[0].Body' ../evidence/failure-record.json |
  jq '{
    event_id: .requestPayload.event_id,
    approximateInvokeCount: .requestContext.approximateInvokeCount,
    condition: .requestContext.condition,
    functionError: .responseContext.functionError,
    statusCode: .responseContext.statusCode,
    responsePayload: .responsePayload
  }'
```

Verify that:

| Field | Expected value | What it proves |
|---|---|---|
| `requestPayload.event_id` | `evt-failure-001` | this is the intended event |
| `requestContext.approximateInvokeCount` | `2` | the initial attempt and one retry ran |
| `requestContext.condition` | `RetriesExhausted` | the retry limit was exhausted |
| `responseContext.functionError` | `Unhandled` | the handler ended with an unhandled exception |

## 10. Metrics and Alarms

Different metric groups answer different asynchronous processing questions:

| Metric | What it shows |
|---|---|
| `AsyncEventsReceived` | events successfully queued by Lambda |
| `Invocations` | actual handler attempts, including retries |
| `Errors` | handler execution attempts that ended with a function error |
| `AsyncEventAge` | how long an event waited before an attempt |
| `AsyncEventsDropped` | events discarded after age or retry limits |
| `DestinationDeliveryFailures` | Lambda could not publish the final destination record |

The lab creates alarms for `Errors` and `DestinationDeliveryFailures` because a
single failed event can exercise them meaningfully. A persistent workload
normally also defines thresholds for queue age and dropped events.

Flow:

```text
handler
  -> RuntimeError
  -> Errors metric increases
  -> function errors alarm

retries exhausted
  -> Lambda sends record to SQS
  -> delivery succeeds
  -> DestinationDeliveryFailures remains 0
  -> destination alarm stays OK
```

Inspect alarm state:

```bash
aws cloudwatch describe-alarms \
  --region "$AWS_REGION" \
  --alarm-names \
    "$(terraform output -raw function_errors_alarm_name)" \
    "$(terraform output -raw destination_delivery_failure_alarm_name)" \
  --query 'MetricAlarms[*].[AlarmName,StateValue,StateReason]' \
  --output table
```

Expected interpretation:

- the error alarm can move to `ALARM` after the failed attempts;
- the destination delivery failure alarm should remain `OK`;
- `INSUFFICIENT_DATA` can appear before CloudWatch receives a full period.

The second alarm does not report handler failures. It reports that Lambda could
not publish the final record to the configured destination.

## 11. Practical Drills

### Drill 1. Invalid Event Contract

`../events/invalid.json` has an `event_id`, but its `mode` violates the contract.

Flow:

```text
caller
  -> Lambda async queue
  <- 202 Accepted

Lambda async queue
  -> attempt 1
  -> ValueError

Lambda async queue
  -> retry 1
  -> ValueError

retries exhausted
  -> SQS failure destination
  -> invocation record
```

Invoke it asynchronously:

```bash
../scripts/invoke-async.sh \
  "$FUNCTION_NAME" \
  "$AWS_REGION" \
  ../events/invalid.json \
  ../evidence/invalid-acceptance.json
```

Monitor the execution attempts:

```bash
aws logs tail "/aws/lambda/$FUNCTION_NAME" \
  --region "$AWS_REGION" \
  --since 10m \
  --follow \
  --format short
```

Retrieve the final record:

```bash
../scripts/receive-failure.sh \
  "$FAILURE_QUEUE_URL" \
  "$AWS_REGION" \
  ../evidence/invalid-failure-record.json \
  evt-invalid-001
```

Inspect it:

```bash
jq -r '.Messages[0].Body' ../evidence/invalid-failure-record.json |
  jq '{
    event_id: .requestPayload.event_id,
    approximateInvokeCount: .requestContext.approximateInvokeCount,
    condition: .requestContext.condition,
    functionError: .responseContext.functionError,
    statusCode: .responseContext.statusCode,
    responsePayload: .responsePayload
  }'
```

Predict the result before running it:

- API acceptance: `202`;
- handler result: `ValueError`;
- retry: yes, within the configured limit;
- final record: SQS destination.

### Drill 2. Duplicate Event

Prepare a distinct event and submit it twice without changing `event_id`:

```bash
jq '.event_id = "evt-duplicate-001"' \
  ../events/success.json > /tmp/lab80-duplicate.json

for attempt in 1 2; do
  ../scripts/invoke-async.sh \
    "$FUNCTION_NAME" \
    "$AWS_REGION" \
    /tmp/lab80-duplicate.json \
    "../evidence/duplicate-${attempt}-acceptance.json"
done
```

Flow:

```text
caller invoke 1
  -> Lambda async queue
  -> handler
  -> async_event_processed

caller invoke 2
  -> Lambda async queue
  -> handler
  -> async_event_processed
```

Count occurrences in the logs:

```bash
aws logs tail "/aws/lambda/$FUNCTION_NAME" \
  --region "$AWS_REGION" \
  --since 10m \
  --format short |
  grep 'async_event_processed' |
  grep 'evt-duplicate-001'
```

Expect two `async_event_processed` records: the handler processes both copies
because the lab has no idempotency store.
They should share the same `event_id` but have different `request_id` values
created for the separate invocations.

### Drill 3. Disable Retries

Set:

```hcl
maximum_retry_attempts = 0
```

Flow:

```text
caller
  -> Lambda async queue
  <- 202 Accepted

Lambda async queue
  -> handler attempt 1
  -> RuntimeError

maximum_retry_attempts = 0
  -> no retry
  -> SQS failure destination
```

Create and apply a fresh saved plan:

```bash
terraform plan -out=tfplan-no-retry
terraform apply tfplan-no-retry
```

Prepare and submit an event with a new identifier:

```bash
jq '.event_id = "evt-no-retry-001"' \
  ../events/failure.json > /tmp/lab80-no-retry.json

../scripts/invoke-async.sh \
  "$FUNCTION_NAME" \
  "$AWS_REGION" \
  /tmp/lab80-no-retry.json \
  ../evidence/no-retry-acceptance.json

../scripts/receive-failure.sh \
  "$FAILURE_QUEUE_URL" \
  "$AWS_REGION" \
  ../evidence/no-retry-failure-record.json \
  evt-no-retry-001
```

Verify that `requestContext.approximateInvokeCount` is `1`, not `2`.

After the drill, return the value to `1`, create a new saved plan, and apply it:

```bash
terraform plan -out=tfplan-restore-retry
terraform apply tfplan-restore-retry
```

### Drill 4. Destination Permission Failure

Read the runtime IAM policy and identify the exact permission required to
publish to SQS:

```text
sqs:SendMessage
```

This is an analysis drill. Do not remove the permission manually during the
normal lesson flow: that experiment creates IAM drift and requires a separate
Terraform recovery step.

Flow when permission is missing:

```text
handler
  -> RuntimeError
  -> retry
  -> RetriesExhausted

Lambda
  -> attempts to send the invocation record
  -> AccessDenied on sqs:SendMessage
  -> SQS remains empty
  -> DestinationDeliveryFailures increases
```

## 12. Troubleshooting

### `No valid credential sources found`

The AWS session can expire between local checks and `terraform plan`.
Authenticate again and verify the active identity:

```bash
export AWS_PROFILE=YOUR_PROFILE
aws sso login --profile "$AWS_PROFILE"
aws sts get-caller-identity
```

### The CLI Returns `202`, but No Log Appears

Check:

```text
202 received
  -> verify the function name and region
  -> verify the asynchronous invocation configuration
  -> check CloudWatch Logs
  -> check Errors / Invocations / Throttles
  -> check the execution role
```

Remember that asynchronous processing can be delayed.

### No Message Appears in SQS

The failure record does not appear in SQS immediately after the handler's first
failure. It is delivered only after the entire asynchronous processing cycle
has completed.

Check:

```text
SQS is empty
  -> did the handler actually fail?
  -> have all retries completed?
  -> is an OnFailure destination configured?
  -> is `sqs:SendMessage` allowed?
  -> are the queue URL and region correct?
  -> has `DestinationDeliveryFailures` increased?
```

Also confirm that you did not accidentally use synchronous `RequestResponse`.

### The Same Message Keeps Appearing

`receive-failure.sh` intentionally sets the visibility timeout to `0` and does not delete messages.

This is done for the lab so that the diagnostic record does not disappear after the first inspection.

After completing inspection, you can delete one exact message by its receipt
handle:

```bash
RECEIPT_HANDLE="$(
  jq -r '.Messages[0].ReceiptHandle' ../evidence/failure-record.json
)"

aws sqs delete-message \
  --region "$AWS_REGION" \
  --queue-url "$FAILURE_QUEUE_URL" \
  --receipt-handle "$RECEIPT_HANDLE"
```

Use only a receipt handle from the intended queue and current receive result.

### `DestinationDeliveryFailures` Remains `OK`

That is expected when delivery to SQS succeeds. Handler errors belong to the
`Errors` metric; destination delivery failures are a separate failure layer.

Flow:

```text
handler
  -> RuntimeError
  -> Errors > 0
  -> the function errors alarm may transition to ALARM

Lambda
  -> sqs:SendMessage
  -> the message is delivered
  -> DestinationDeliveryFailures = 0
  -> the destination alarm remains OK
```

## 13. Completion Check

Before cleanup, confirm that:

- Python tests and Terraform native tests passed;
- the successful event returned `202` and appeared in logs;
- the failed event also returned `202`;
- the failed event produced handler errors and a retry;
- SQS contains a decoded invocation record;
- the error and destination delivery alarms have been interpreted correctly;
- the execution role scopes `sqs:SendMessage` to one queue;
- no temporary AWS credentials were written to evidence;
- you can explain why the handler is not idempotent yet.

Files under `lab_80/evidence/` are temporary results. Do not commit them without
reviewing and redacting operational metadata.

## 14. Cleanup

Save identifiers before destroy:

```bash
FUNCTION_NAME="$(terraform output -raw function_name)"
FAILURE_QUEUE_URL="$(terraform output -raw failure_queue_url)"
AWS_REGION="$(terraform output -raw aws_region)"
```

Create and inspect a saved destroy plan, then apply that exact plan:

```bash
terraform plan -destroy -out=tfplan-destroy
terraform show tfplan-destroy
terraform apply tfplan-destroy
```

Verify removal:

```bash
aws lambda get-function \
  --region "$AWS_REGION" \
  --function-name "$FUNCTION_NAME"

aws sqs get-queue-attributes \
  --region "$AWS_REGION" \
  --queue-url "$FAILURE_QUEUE_URL" \
  --attribute-names QueueArn
```

Both commands should report that their resource no longer exists.

## 15. Final Model

```text
202 Accepted
    -> event entered Lambda's asynchronous delivery system

handler success
    -> proved by execution evidence, not API acceptance

handler failure
    -> can produce retries and duplicate processing

retries exhausted
    -> final invocation record goes to the failure destination

destination delivery failure
    -> separate operational failure with its own metric
```

Key conclusions:

1. Transport acceptance and business completion are different states.
2. Retry count describes additional attempts, not total attempts.
3. Retryable processing requires idempotency at the business boundary.
4. A failure destination preserves richer context than a basic DLQ.
5. Logs, function metrics, destination metrics, and SQS records answer different
   diagnostic questions.
6. Bounded retries and event age prevent infinite or stale processing.

## 16. Official References

- [Invoking Lambda asynchronously](https://docs.aws.amazon.com/lambda/latest/dg/invocation-async.html)
- [Configuring error handling](https://docs.aws.amazon.com/lambda/latest/dg/invocation-async-error-handling.html)
- [Lambda destinations](https://docs.aws.amazon.com/lambda/latest/dg/invocation-async-retain-records.html)
- [Lambda metrics](https://docs.aws.amazon.com/lambda/latest/dg/monitoring-metrics-types.html)
- [Troubleshooting duplicate Lambda invocations](https://repost.aws/knowledge-center/lambda-function-duplicate-invocations)
- [Terraform event invoke configuration](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function_event_invoke_config)
