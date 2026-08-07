# Lesson 82. Lambda SQS Event Source Mapping

## 1. Why This Lesson Exists

In Lesson 80, SQS was the destination queue for the final failure. First, the sender invoked Lambda asynchronously, and then the Lambda service managed the internal retries. Only after the retries were exhausted did the Lambda service place a service-generated record describing the failed invocation into SQS.

In Lesson 81, a single business operation was made idempotent.

Now, SQS stores the original jobs that the function must process:

```text
producer
-> SQS source queue
-> Lambda event source mapping polls messages
-> Lambda invokes the handler with a batch
-> successful messages are acknowledged
-> failed messages are retried or moved to a DLQ
```

The distinction matters. Sending an event asynchronously to Lambda and letting
Lambda poll SQS are different delivery systems with different retry controls.

| Mechanism                | Who receives the original event | Where retries are managed                     |
| ------------------------ | ------------------------------- | --------------------------------------------- |
| Asynchronous Invoke      | Lambda first                    | In Lambda’s internal queue                    |
| SQS event source mapping | SQS first                       | Through SQS message visibility and redelivery |

The main question is:

> How can one Lambda invocation process several SQS messages without retrying
> every successful message when only one record fails?

The answer is a partial batch response:

```json
{
  "batchItemFailures": [
    {
      "itemIdentifier": "failed-02-sqs-message-id"
    }
  ]
}
```

```text
passed-01-sqs-message-id -> success
failed-02-sqs-message-id -> failure
passed-03-sqs-message-id -> success
-> batchItemFailures = [failed-02-sqs-message-id.messageId]
-> Lambda deletes passed-01 and passed-03
-> failed-02 becomes visible again
-> only failed-02 is retried
```

Thus, the mechanism prevents unnecessary retries of neighboring records that were processed successfully.

It does not fix the underlying cause of the `failed-02-sqs-message-id` error. It only isolates that record from the rest of the batch.

Comparison table:

| Property              | Async Invoke + destination  | SQS event source mapping |
| --------------------- | --------------------------- | ------------------------ |
| Initial recipient     | Lambda                      | SQS                      |
| What the queue stores | Final failure record        | Original job             |
| Who manages retrieval | Lambda’s internal mechanism | Lambda poller            |
| Retry unit            | Asynchronous event          | SQS message or batch     |

## 2. Learning Outcomes

After this lesson, you will be able to:

- distinguish a Lambda failure destination from an SQS event source mapping;
- explain who polls SQS and who deletes successful messages;
- validate the SQS batch event contract;
- process records independently inside one invocation;
- return `batchItemFailures` with exact SQS `messageId` values;
- explain visibility timeout and calculate a safe minimum;
- configure a source queue, DLQ, redrive policy, and redrive allow policy;
- explain why partial failures may not increment Lambda `Errors`;
- trace a poison message through retries into the DLQ;
- explain why partial batch response does not replace idempotency.

Evidence map:

| What we are proving                                               | Primary evidence                                                                                                                                                                          |
| ----------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| The event source mapping is connected to the correct source queue | `State = Enabled`; `EventSourceArn` matches the ARN of the source queue                                                                                                                   |
| Batch processing settings are applied                             | `BatchSize = 5`; `MaximumBatchingWindowInSeconds = 5`                                                                                                                                     |
| Partial batch response is enabled on the AWS side                 | `FunctionResponseTypes` contains `ReportBatchItemFailures`                                                                                                                                |
| The handler implements the partial batch response contract        | The response contains `batchItemFailures`; the exact SQS `messageId` is used for a failed record; an empty list is returned for a fully successful batch                                  |
| The successful message was accepted by SQS                        | A successful `SendMessage` response and the returned `MessageId`                                                                                                                          |
| The successful message was processed by Lambda                    | CloudWatch Logs contain `sqs_message_processed`, the exact `message_id`, and `task_id = report-success-001`                                                                               |
| The successful message was removed from the source queue          | `ApproximateNumberOfMessages = 0` and `ApproximateNumberOfMessagesNotVisible = 0` after refreshing the approximate SQS attributes                                                         |
| A failed record is isolated from neighboring records              | A Python test with a mixed batch: successful records are processed, while `batchItemFailures` contains only the `messageId` of the failed record                                          |
| The failed message is retried a limited number of times           | The message appears in the DLQ; its `ApproximateReceiveCount` reflects repeated receives                                                                                                  |
| SQS moves the failed message to the DLQ                           | The source queue `redrive_policy` points to the DLQ and contains `maxReceiveCount = 3`                                                                                                    |
| The entire Lambda invocation can also fail                        | A direct Invoke returns `StatusCode = 200`, `FunctionError = Unhandled`, and the payload contains `errorMessage`                                                                          |
| The execution role has only the required permissions              | CloudWatch Logs permissions are limited to the function’s log group; SQS actions are limited to the ARN of the source queue; there is no access to the DLQ and no wildcard SQS `Resource` |
| The configuration passes automated checks                         | 9 Python unit tests and 5 Terraform native tests complete successfully                                                                                                                    |

### 2.1. Lesson Terminology

| English term | Plain wording | Precise meaning in this lesson |
|---|---|---|
| `batch` | message batch | Several SQS records passed to one Lambda invocation |
| `partial batch response` | per-record failure response | Handler response that lists only failed `messageId` values |
| `event source mapping` | event source mapping | A Lambda-managed link that polls SQS and invokes the function with message batches |
| `asynchronous invocation` | asynchronous invocation | An invocation in which Lambda first accepts an event into its internal queue |
| `destination` | invocation destination | A resource that receives the final record of an asynchronous Lambda invocation |
| `visibility timeout` | temporary message lease | Time during which a received message is hidden from other consumers |
| `poison message` | consistently failing message | Message that causes an error on every processing attempt |
| `Lambda execution role` | runtime permissions role | IAM role assumed by Lambda while the handler runs; `runtime role` is informal wording |
| `poller` | queue polling component | Lambda component that receives SQS messages for an event source mapping |
| `redrive` | move or replay messages | Automatic movement to a DLQ or controlled movement from a DLQ back to a source queue |
| `body` | message body | Exact SQS record field containing the payload string |
| `CloudWatch alarm` | metric alarm | A resource that compares a metric with a threshold and changes state |
| `Terraform native tests` | Terraform test files | Tests in `.tftest.hcl` executed by `terraform test` |

## 3. Mental Model

### 3.1. Failure Destination Is Not an Event Source

Lesson 80:

```text
AWS CLI invokes Lambda asynchronously
-> Lambda owns the internal retry queue
-> final failure record is sent to SQS
```

SQS was located at the end of the flow.

A message in SQS meant approximately the following:

```text
Lambda could not ultimately process the asynchronous event
-> a final failure record was created
-> the record was sent to the destination queue
```

Until that point, retries were managed by Lambda, not by SQS.

Lesson 82:

```text
producer sends a message to SQS
-> Lambda service polls SQS
-> event source mapping invokes the function synchronously
-> queue state controls retry and redrive
```

SQS is now located at the beginning of the processing flow.

Terminology boundary:

```text
destination queue
-> the queue receives data from Lambda after processing

source queue
-> Lambda receives data from the queue for processing
```

In lesson 80, SQS stored the final failure record. In this lesson, SQS stores the original work item.

| Question                          | Destination from Lesson 80                                | Source from Lesson 82                                 |
| --------------------------------- | --------------------------------------------------------- | ----------------------------------------------------- |
| What is stored                    | Final failure record                                      | Original job                                          |
| Where the queue is located        | After Lambda                                              | Before Lambda                                         |
| Who initiates processing          | The sender invokes Lambda                                 | The Lambda poller reads from SQS                      |
| Who manages the primary retries   | Lambda asynchronous invocation                            | SQS visibility and redelivery                         |
| Can the message be moved to a DLQ | The destination is already Lambda’s final failure outcome | SQS moves the message according to the redrive policy |

### 3.2. Lambda Owns Polling and Acknowledgement

Your handler does not call `ReceiveMessage` or `DeleteMessage` directly.
The Lambda event source mapping does that around the invocation:

```text
Lambda poller
-> calls ReceiveMessage on the source SQS queue
-> the message becomes invisible
-> constructs the Records[] event
-> the event source mapping invokes the handler
-> the handler returns a result
-> Lambda deletes successful messages using DeleteMessage
```

For a failed record with partial batch response:

```text
the handler returns the messageId in batchItemFailures
-> Lambda does not delete that record
-> the visibility timeout expires
-> the message becomes visible again
```

The execution role still needs:

```text
sqs:ReceiveMessage - Receive messages from the source queue
sqs:DeleteMessage - Delete successfully processed messages
sqs:GetQueueAttributes - Read queue attributes required by the polling mechanism
```

These permissions are scoped to the exact source queue ARN. The runtime role
does not receive from the DLQ; inspection and remediation are operator duties.

It is important to distinguish between two entities:

```text
Lambda poller
-> performs the automatic polling

execution role
-> authorizes this mechanism to work with the queue
```

Unlike a push integration such as an S3 notification, this same-account SQS
mapping does not require an `aws_lambda_permission` statement for an `sqs.amazonaws.com`
principal. Lambda owns the poller and uses the function execution role to access SQS.
A cross-account queue would additionally require an appropriate SQS queue policy.

Who deletes the message?

```text
the handler successfully processes the record
-> Lambda interprets the result
-> Lambda deletes the message from SQS
```

When partial batch response is enabled, Lambda matches the result to specific `messageId` values:

```text
messageId is absent from batchItemFailures
-> the record is considered successful
-> Lambda deletes it

messageId is present in batchItemFailures
-> the record is considered failed
-> Lambda does not delete it
```

Separation of responsibilities:

| Component            | Responsibility                                |
| -------------------- | --------------------------------------------- |
| Sender               | Performs `SendMessage`                        |
| SQS                  | Stores the message and manages its visibility |
| Lambda poller        | Retrieves messages                            |
| Event source mapping | Builds the batch and invokes the function     |
| Handler              | Processes records and returns the result      |
| Lambda               | Deletes successfully processed messages       |
| Execution role       | Grants access to the source queue             |

### 3.3. A Batch Is One Lambda Invocation

A single event can contain multiple records:

```text
one SQS message
-> one Records[] entry

multiple SQS messages
-> multiple Records[] entries
-> one handler invocation

event
└── Records
    ├── Records[0]
    ├── Records[1]
    └── Records[2]
```

The handler is invoked once for the entire `Records[]` array, and then the function code
iterates over the individual records.

`batch_size = 5` means that a batch can contain between 1 and 5 records. It is an upper limit,
not a guarantee.
Lambda may invoke the function with fewer records because of the queue depth, the batch
accumulation window, or the event size limit.

The batching window is also a maximum. A full batch can be invoked earlier.

| Parameter                        | Value | Meaning                                         |
| -------------------------------- | ----: | ----------------------------------------------- |
| `BatchSize`                      |   `5` | No more than five records per invocation        |
| `MaximumBatchingWindowInSeconds` |   `5` | No more than five seconds to accumulate a batch |

You must distinguish between three levels:

```text
SQS message
-> one individual message

Records[]
-> a batch of received messages

Lambda invocation
-> one handler invocation for the entire batch
```

### 3.4. Default Failure Is All-or-Nothing

Without partial batch response, Lambda evaluates the result of the entire invocation
rather than each record individually.

Without partial batch response:

```text
message A -> success
message B -> failure
message C -> success
the handler raises an exception
-> the entire batch is considered failed
-> Lambda does not delete A, B, or C
-> the visibility timeout expires
-> A, B, and C become visible again
-> the entire batch may be delivered again
```

Therefore, a full batch failure creates two problems:

| Problem                        | Cause                                                                       |
| ------------------------------ | --------------------------------------------------------------------------- |
| Unnecessary Lambda invocations | Successfully processed records are included in a batch again                |
| Repeated business actions      | Successful processing of a record does not guarantee exactly-once execution |

Without partial batch response, only two outcomes are possible:

```text
the handler completes successfully
-> the entire batch is considered successful

the handler raises an exception
-> the entire batch is considered failed
```

### 3.5. Partial Batch Response

Partial batch response allows the handler to tell Lambda:

- which records failed.

The event source mapping enables:

```hcl
function_response_types = ["ReportBatchItemFailures"]
```

This tells Lambda to interpret the handler response as a partial batch processing result.

The handler must return an object in the following format:

```json
{
  "batchItemFailures": [
    {
      "itemIdentifier": "exact-sqs-messageId"
    }
  ]
}
```

`itemIdentifier` is the exact SQS `messageId` of the failed record.

The handler catches record-level errors and returns only failed identifiers:

```text
message A -> success
message B -> failure
message C -> success

handler:
-> catches the error for B
-> adds B.messageId to batchItemFailures
-> continues processing C
-> returns a normal response

Result:

A is absent from batchItemFailures
-> Lambda deletes A

B is present in batchItemFailures
-> Lambda does not delete B
-> B is retried after the visibility timeout expires

C is absent from batchItemFailures
-> Lambda deletes C
```

Both sides of the contract are required:

| Side | Requirement |
|---|---|
| Terraform | Enable `ReportBatchItemFailures` |
| Handler | Return valid `batchItemFailures` JSON |
| Failed item | Use the exact SQS `messageId` |
| Whole batch success | Return an empty list |

If the handler throws outside record-level error handling, Lambda treats the
whole batch as failed.

Identifier boundary:

```text
messageId
-> the record identifier used by Lambda and the SQS batch response

task_id
-> a business key and potential idempotency key

messageId != task_id
```

### 3.6. Visibility Timeout Is a Lease

When the Lambda poller calls `ReceiveMessage`, SQS temporarily hides the message from other consumers:

```text
message is visible
-> Lambda receives it
-> message is invisible
-> handler processes the batch
```

This period is called the visibility timeout.

Successful processing:

```text
Lambda receives the message
-> the message becomes invisible
-> the handler successfully processes the record
-> Lambda calls DeleteMessage
-> the message is permanently deleted
```

On success, Lambda deletes the message. On failure, the message becomes visible
again when the visibility timeout expires.

Processing failure:

```text
Lambda receives the message
-> the message becomes invisible
-> the record fails
-> Lambda does not delete the message
-> the visibility timeout expires
-> the message becomes visible again
-> redelivery may occur
```

AWS recommends:

```text
visibility timeout
>= 6 × Lambda function timeout + maximum batching window
```

Lab values:

```text
6 × 10 seconds + 5 seconds = 65 seconds
configured visibility timeout = 70 seconds
```

The extra time allows for throttling and retry behavior around batch processing.
A visibility timeout that is shorter than real processing can allow concurrent
processing of the same message.

### 3.7. Redrive Policy and DLQ

The source queue has:

```text
maxReceiveCount = 3
DLQ = lab82-...-sqs-dlq
```

After the receive budget is exhausted, SQS moves the poison message to the DLQ.
The lab uses three receives.

The DLQ also has a redrive allow policy:

```text
redrivePermission = byQueue
sourceQueueArns = [exact source queue ARN]
```

This prevents unrelated queues from selecting the lab DLQ.

A `poison message` is a message that consistently causes an error on every processing attempt.

In this lab, it is the message containing:

```text
{
  "task_id": "report-poison-001",
  "action": "generate_report",
  "should_fail": true
}
```

`generate_report` intentionally raises a `RuntimeError`, so the record is included in `batchItemFailures` every time.

Flow:

```text
SQS delivery
-> Lambda processes the record
-> generate_report raises RuntimeError
-> the handler catches the exception
-> the messageId is added to batchItemFailures
-> Lambda does not delete the message
-> the visibility timeout expires
-> the message is delivered again
-> ApproximateReceiveCount increases
-> maxReceiveCount is exhausted
-> SQS moves the message to the DLQ
```

The redrive policy (`redrive_policy`) answers two questions:

- where to move the message
- after how many receives to move it

Conceptually:

```json
{
  "deadLetterTargetArn": "<DLQ ARN>",
  "maxReceiveCount": 3
}
```

`redrive_allow_policy` is a separate policy. It is configured on the DLQ and determines which source queues are allowed to use that DLQ.

- the handler reports the record failure
- Lambda does not delete the record
- SQS counts the receives and moves the message

| Policy                 | Where it is configured | What it controls                     | Main fields                              |
| ---------------------- | ---------------------- | ------------------------------------ | ---------------------------------------- |
| `redrive_policy`       | Source queue           | The target DLQ and `maxReceiveCount` | `deadLetterTargetArn`, `maxReceiveCount` |
| `redrive_allow_policy` | DLQ                    | Which queues may use this DLQ        | `redrivePermission`, `sourceQueueArns`   |

### 3.8. Partial Batch Response Is Not Exactly-Once

SQS event source mappings use the following delivery model:

```text
at-least-once
-> the message is delivered at least once
-> the same message may occasionally be delivered more than once
```

Flow:

```text
Lambda received the message
-> the handler created the report
-> the report was successfully sent to the client
-> a failure occurred before the message was acknowledged
-> Lambda did not delete the message from SQS
-> the visibility timeout expired
-> the message was delivered again
-> the handler attempts to create and send the report again
```

`partial batch response` does not know whether an irreversible action occurred during processing before the error.

```text
partial batch response
-> isolates the failure of a single record
-> reduces retries of successfully processed neighboring records

partial batch response
!= exactly-once
!= a guarantee that the business action is performed only once
```

For payments, emails, and resource provisioning, the mechanism in this lesson must be combined with the idempotency state machine from Lesson 81.

The lab message contains a stable business identifier:

```json
{
  "task_id": "report-success-001",
  "action": "generate_report"
}
```

The `task_id`, rather than the SQS `messageId`, can be used as the idempotency key.

```text
first delivery:
task_id = report-success-001
-> create a claim
-> perform the action
-> store the result

redelivery:
task_id = report-success-001
-> a completed result is found
-> do not perform the action again
-> return the stored result
```

| Identifier      | Purpose                                                         |
| --------------- | --------------------------------------------------------------- |
| SQS `messageId` | Tell Lambda which transport-level record must be retried        |
| `task_id`       | Prevent the business action from being performed more than once |

```text
batchItemFailures
-> uses messageId

idempotency
-> uses a stable task_id
```

| Mechanism              | Problem it solves                               | What it does not guarantee               |
| ---------------------- | ----------------------------------------------- | ---------------------------------------- |
| Visibility timeout     | Temporarily hides the message during processing | Successful processing                    |
| Partial batch response | Isolates a failed record within a batch         | Exactly-once processing                  |
| DLQ                    | Prevents unlimited retries                      | Fixing the underlying cause of the error |
| Idempotency            | Prevents repeated business actions              | The absence of message redelivery        |

## 4. Lab Architecture

```text
                         original job
                              |
                              v
+------------+      +-----------------------+
| sender     | ---> | source SQS queue      |
+------------+      | visibility = 70s      |
                    | maxReceiveCount = 3   |
                    +-----------+-----------+
                                |
                                | Lambda poller
                                v
                    +-----------------------+
                    | event source mapping  |
                    | batch size = 5        |
                    | batch window = 5s     |
                    | partial response = on |
                    +-----------+-----------+
                                |
                                v
                    +-----------------------+
                    | Lambda consumer       |
                    | processes Records[]   |
                    +-----------+-----------+
                                |
                      failed records are retried
                                |
                         retries are exhausted
                                v
                    +-----------------------+
                    | SQS DLQ               |
                    | retention = 14 days   |
                    +-----------------------+
```

### 1. Source SQS queue

It receives jobs from the sender.

Purpose:

```text
store the original messages
-> temporarily hide received messages
-> make unacknowledged messages visible again
-> move messages that have exhausted their retries to the DLQ
```

### 2. Event source mapping

This is the link between the source queue and Lambda.

It is responsible for:

```text
polling the source queue
-> building Records[]
-> invoking Lambda
-> interpreting batchItemFailures
-> deleting successfully processed messages
```

It is a managed Lambda configuration.

### 3. Lambda consumer

The function receives a batch of records and validates each one independently:

```text
Records[]
-> validate the SQS envelope
-> parse the body
-> validate the business fields
-> execute generate_report
```

Each record can have one of the following outcomes:

```text
success
-> the record is not added to batchItemFailures

record failure
-> the exact messageId is added to batchItemFailures
```

If the contract of the entire event is violated, for example if `messageId` is missing, the handler fails the entire invocation.

### 4. DLQ

The DLQ stores messages that have exhausted their receive budget.

Message flow:

```text
processing failure
-> the message is not deleted
-> the visibility timeout expires
-> the message is delivered again
-> three receives are exhausted
-> SQS moves the message to the DLQ
```

The DLQ does not participate in the normal processing of successful messages.

Two different paths after Lambda:

```text
success
-> DeleteMessage
-> the message is deleted

record failure
-> messageId is included in batchItemFailures
-> the message is retried
-> it may later be moved to the DLQ
```

Observability:

| Signal                                          | What it shows                                   |
| ----------------------------------------------- | ----------------------------------------------- |
| Lambda `Errors`                                 | The entire Lambda invocation failed             |
| `ApproximateAgeOfOldestMessage`                 | The source queue is falling behind              |
| `ApproximateNumberOfMessagesVisible` in the DLQ | Some messages have exhausted their retry budget |

Parameters and their purposes:

| Parameter                 | Where it is configured      | Purpose                                  |
| ------------------------- | --------------------------- | ---------------------------------------- |
| `70s`                     | Source queue                | Provide a safe visibility timeout        |
| `3`                       | Source queue redrive policy | Limit the number of receives             |
| `5` messages              | Event source mapping        | Set the maximum batch size               |
| `5s`                      | Event source mapping        | Set the maximum batching window          |
| `ReportBatchItemFailures` | Event source mapping        | Enable partial batch response            |
| `14 days`                 | DLQ                         | Retain failed messages for investigation |

## 5. Implementation Walkthrough

### 5.1. Record Validation

Open the parser:

```bash
sed -n '14,52p' ../app/lambda_function.py
```

`parse_record` validates two contracts:

1. SQS envelope:
   - record is an object;
   - `messageId` is a non-empty string;
   - `body` is a string.
2. Business body:
   - body contains valid JSON object;
   - `task_id` is non-empty;
   - `action` is `generate_report`;
   - `should_fail` is boolean.

Flow:

```text
SQS record
-> is the record an object?
-> does it contain a non-empty messageId?
-> is body a string?
-> can body be parsed as a JSON object?
-> is task_id present?
-> action = generate_report?
-> is should_fail a boolean?
-> the record is accepted for processing
```

A missing `messageId` is special. The handler cannot put an unknown record into `batchItemFailures`,
so it fails the whole invocation rather than acknowledge work it cannot identify safely.

### 5.2. Isolating individual records

Open the batch processing loop:

```bash
sed -n '68,118p' ../app/lambda_function.py
```

The main responsibility of `process_batch()`:

```text
receive Records[]
-> process each record independently
-> collect only the messageId values of failed records
-> return batchItemFailures
```

First, the function validates the overall event contract:

```text
event must be an object
-> event.Records must be a list
```

If the overall contract is violated, processing individual records is impossible. Therefore, `process_batch()` raises an exception, and the entire Lambda invocation fails.

#### Validating `messageId`

For each record, `messageId` is validated **before** entering the record-level `try/except` block:

```text
retrieve the record from Records[]
-> verify that the record is an object
-> retrieve messageId
-> verify that messageId is a non-empty string
-> only then begin isolated processing of the record
```

This is necessary because partial batch response can identify a failed record only by its exact SQS `messageId`.

If `messageId` is missing:

```text
no messageId
-> itemIdentifier cannot be constructed
-> the failed record cannot be identified precisely
-> MessageContractError is not caught at the record level
-> the exception propagates out of process_batch
-> the entire Lambda invocation fails
```

In other words, a record without a `messageId` cannot be isolated.

#### Record isolation boundary

After `messageId` has been validated successfully, the `try/except` block for that specific record begins:

```python
try:
    _, message = parse_record(record)
    result = processor(message)
```

Two operations are performed within this boundary:

```text
parse_record
-> validates the body and the business contract of the message

processor
-> performs the business processing
-> by default, this is generate_report
```

#### Successful record

If `parse_record()` and `processor()` complete successfully:

```text
write sqs_message_processed to the log
-> do not add messageId to failures
-> continue to the next record
```

The log entry contains:

```text
event = sqs_message_processed
message_id
task_id
report_id
```

#### Failed record

If `parse_record()` or `processor()` raises an exception, it is caught by:

```python
except Exception as error:
```

The function then:

```text
writes sqs_message_failed to the log
-> includes message_id
-> includes the error type and message
-> adds the exact messageId to failures
-> continues the loop
```

The failure entry is constructed as follows:

```python
failures.append({
    "itemIdentifier": message_id
})
```

The key point:

```text
an exception occurs inside parse_record or processor
-> it propagates back to process_batch
-> the except block inside process_batch catches it
-> the exception does not reach lambda_handler
-> the loop continues
-> the next record is also processed
```

This is what it means to isolate the failure of a single record.

#### `process_batch()` response

After all records have been processed, the function returns:

```python
return {
    "batchItemFailures": failures
}
```

When processing completes normally, there are two primary response forms.

All records are successful:

```json
{
  "batchItemFailures": []
}
```

Some records failed:

```json
{
  "batchItemFailures": [
    {
      "itemIdentifier": "message-bad"
    }
  ]
}
```

However, if an exception occurs outside the record-level `try/except` block, for example because `messageId` is missing, `process_batch()` does not return `batchItemFailures`: the entire invocation fails.

#### Example: batch A, B, C

```text
A -> valid record
B -> should_fail = true
C -> valid record
```

Processing record A:

```text
parse_record succeeds
-> processor succeeds
-> sqs_message_processed is written to the log
-> A.messageId is not added to failures
```

Processing record B:

```text
parse_record succeeds
-> processor calls generate_report
-> generate_report raises RuntimeError
-> the except block inside process_batch catches RuntimeError
-> sqs_message_failed is written to the log
-> B.messageId is added to failures
```

Processing record C:

```text
the loop was not stopped by the failure of B
-> parse_record succeeds
-> processor succeeds
-> sqs_message_processed is written to the log
-> C.messageId is not added to failures
```

Final response:

```json
{
  "batchItemFailures": [
    {
      "itemIdentifier": "B.messageId"
    }
  ]
}
```

When `ReportBatchItemFailures` is enabled, the result is interpreted as follows:

```text
A is absent from batchItemFailures
-> Lambda deletes A

B is present in batchItemFailures
-> Lambda does not delete B
-> after the visibility timeout, B may be delivered again

C is absent from batchItemFailures
-> Lambda deletes C
```

Final boundary:

```text
an error occurs inside the record-level try block
-> the exception is caught
-> only the messageId of that record is added to batchItemFailures
-> batch processing continues
```

```text
an error occurs before the record-level try block
-> the exception is not caught at the record level
-> process_batch fails
-> the entire Lambda invocation is considered unsuccessful
```

### 5.3. Terraform Contract

Inspect the queue and mapping:

- `queues.tf`;
- `vent_source_mapping.tf`;
- `function_execution_role.tf`.

Important relationships:

```text
source queue
-> its redrive policy points to the DLQ ARN

DLQ
-> allows only the source queue ARN to use it

event source mapping
-> reads from the source queue ARN
-> invokes the required Lambda ARN
-> enables ReportBatchItemFailures

execution role
-> has access only to the source queue ARN
```

SQS queues:

1. What we verify: the source queue, the DLQ, and the redrive policies.
2. What we expect:
   - the source queue has a visibility timeout;
   - its `redrive_policy` points to the DLQ ARN;
   - `maxReceiveCount` is configured;
   - the DLQ has a `redrive_allow_policy` that allows only the source queue.
3. What the result proves: Terraform links the source queue and the DLQ in the correct direction.
4. What it does not prove: that a message has already been retried or has actually reached the DLQ.
5. Layer: Terraform and SQS.

Event Source Mapping:

1. What we verify: the connection between the source queue and Lambda, and the batch processing settings.
2. What we expect:
   - `event_source_arn` points to the source queue;
   - `function_name` points to the Lambda function;
   - the batch size and batching window are configured;
   - `ReportBatchItemFailures` is enabled.
3. What the result proves: Terraform defines the required event source mapping contract.
4. What it does not prove: that the mapping has already been created in AWS and is in the `Enabled` state.
5. Layer: Terraform and Event Source Mapping.

Explanation of `depends_on`:

```text
depends_on
-> enforces the creation order of the IAM policy and the mapping
!= grants IAM permissions
```

Execution Role:

1. What we verify: the Lambda runtime permissions.
2. What we expect:
   - CloudWatch Logs permissions are limited to the function’s log group;
   - `sqs:ReceiveMessage`, `sqs:DeleteMessage`, and `sqs:GetQueueAttributes` are allowed;
   - the SQS `Resource` is the exact ARN of the source queue;
   - there is no access to the DLQ;
   - there is no wildcard `Resource = "*"`.
3. What the result proves: the Lambda poller receives the minimum required permissions through the execution role.
4. What it does not prove: that the created function actually uses this role or that SQS API calls have already completed successfully.
5. Layer: Terraform and IAM.

## 6. Local Verification

From the repository root:

```bash
python3 -m unittest discover \
  -s lessons/82-lambda-sqs-event-source-mapping/lab_82/tests -v

bash -n lessons/82-lambda-sqs-event-source-mapping/lab_82/scripts/*.sh
shellcheck lessons/82-lambda-sqs-event-source-mapping/lab_82/scripts/*.sh
```

Expected:

```text
Ran 9 tests

OK
```

- `processor.call_count = 2` -> the second record was processed after the first successful record


| Test                                             | What it proves                                                          |
| ------------------------------------------------ | ----------------------------------------------------------------------- |
| `test_parse_record_accepts_valid_message`        | A valid SQS record returns the `messageId` and parsed `body`            |
| `test_parse_record_rejects_invalid_json`         | Invalid JSON raises `MessageContractError`                              |
| `test_parse_record_rejects_unknown_action`       | Only `action = generate_report` is allowed                              |
| `test_generate_report_is_deterministic`          | The same message produces the same result                               |
| `test_successful_batch_returns_no_failures`      | A successful batch returns `batchItemFailures: []`                      |
| `test_mixed_batch_reports_only_failed_record`    | In a mixed batch, only `message-bad` is returned                        |
| `test_processor_failure_isolated_to_one_record`  | A processor exception is isolated to one record, and the loop continues |
| `test_missing_message_id_fails_whole_invocation` | A missing `messageId` causes the entire invocation to fail              |
| `test_non_sqs_event_is_rejected`                 | An event without a `Records` list is rejected                           |

## 7. Terraform Validation and Deployment

```bash
cd lessons/82-lambda-sqs-event-source-mapping/lab_82/terraform
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform fmt -check -recursive
terraform validate
terraform test
```

Expected native test result:

```text
Success! 5 passed, 0 failed.
```

Authenticate before planning:

```bash
export AWS_PROFILE=YOUR_PROFILE
aws sso login --profile "$AWS_PROFILE"
aws sts get-caller-identity
```

Create and review a saved plan:

```bash
terraform plan -out=tfplan
terraform show tfplan
terraform apply tfplan
```

Export runtime values:

```bash
export AWS_REGION="$(terraform output -raw aws_region)"
export FUNCTION_NAME="$(terraform output -raw function_name)"
export SOURCE_QUEUE_URL="$(terraform output -raw source_queue_url)"
export DLQ_URL="$(terraform output -raw dead_letter_queue_url)"
export MAPPING_UUID="$(terraform output -raw event_source_mapping_uuid)"
export LOG_GROUP="/aws/lambda/${FUNCTION_NAME}"

printf 'region=%s\nfunction=%s\nsource=%s\ndlq=%s\nmapping=%s\n' \
  "$AWS_REGION" "$FUNCTION_NAME" "$SOURCE_QUEUE_URL" "$DLQ_URL" "$MAPPING_UUID"
```

## 8. Verify the Event Source Mapping

What we are verifying now:

1. What we verify:
   - the event source mapping created in AWS.
2. Expected result:
   - the mapping is enabled, uses batches of up to five messages, a batching window of up to five seconds, and partial batch response.
3. What this proves:
   - AWS stored the expected configuration, and the mapping is connected to the source queue.
4. What this does not prove:
   - that a specific message has already been received, processed, or deleted.
5. Verification layer:
   - Event Source Mapping and AWS Lambda.

```bash
aws lambda get-event-source-mapping \
  --uuid "$MAPPING_UUID" \
  --region "$AWS_REGION" \
  --query '{State:State,LastResult:LastProcessingResult,BatchSize:BatchSize,BatchWindow:MaximumBatchingWindowInSeconds,ResponseTypes:FunctionResponseTypes,Source:EventSourceArn}' \
  --output table
```

Expected contract:

```text
State = Enabled
BatchSize = 5
BatchWindow = 5
ResponseTypes contains ReportBatchItemFailures
Source points to the ARN of the source queue
-> it must not point to the DLQ
```

If `State` is still `Creating` or `Enabling`, wait and run the command again.

## 9. Successful Message Flow

Move to the lab root:

```bash
cd ..
```

Send one successful message:

```bash
./scripts/send-message.sh \
  "$SOURCE_QUEUE_URL" \
  "$AWS_REGION" \
  events/success-message.json \
  evidence/success-send.json

jq . evidence/success-send.json
```

The `SendMessage` response proves only that SQS accepted the message. It does not
prove Lambda processed it.

```text
events/success-message.json
-> send-message.sh
-> SQS SendMessage API
-> the source queue returns a MessageId
```

What we are verifying now:

1. What we verify:
   - whether Lambda received the message and whether the handler processed the record successfully.
2. Expected result:
   - the logs contain `sqs_message_processed` with the exact `message_id`, `task_id = report-success-001`, and `report_id`.
3. What this proves:
   - the Lambda poller received the record, the event source mapping invoked the handler, and the business processing completed successfully.
4. What this does not prove:
   - that the message has already been permanently deleted from the source queue.
5. Verification layer:
   - AWS Lambda and CloudWatch Logs.

Wait for the consumer and inspect logs:

```bash
aws logs tail "$LOG_GROUP" \
  --region "$AWS_REGION" \
  --since 10m \
  --format short
```

Find:

```text
sqs_message_processed
message_id
report-success-001
report_id
```

Confirmed:

```text
Lambda poller received the message
-> the event source mapping invoked the handler
-> the handler parsed the body
-> task_id = report-success-001
-> generate_report completed successfully
-> report_id = 4195abf32f9f was created
-> sqs_message_processed was written to the log
```

What we are verifying now:

1. What we verify:
   - whether the source queue returned to zero after successful processing.
2. Expected result:
   - there are no visible or invisible messages.
3. What this proves:
   - the message is no longer waiting for processing and is not temporarily invisible; together with the success log, this confirms the complete successful path.
4. What this does not prove:
   - that SQS could never have delivered the message more than once; the delivery model remains at-least-once.
5. Verification layer:
   - SQS and Shell.

Inspect queue attributes without receiving a message:

```bash
./scripts/inspect-queue.sh \
  "$SOURCE_QUEUE_URL" \
  "$AWS_REGION" \
  evidence/source-after-success.json

jq . evidence/source-after-success.json
```

After metric convergence, visible and in-flight counts should return to zero.
SQS approximate attributes may lag, so logs and queue state are complementary evidence.

This means:

```text
no visible messages
-> the message is not waiting to be processed

no invisible messages
-> the message is not currently being processed by the Lambda poller

no delayed messages
-> the message is not waiting for its delay period to expire
```

Confirmed:

```text
SQS accepted the message
-> the Lambda poller received it
-> the event source mapping invoked the handler
-> the handler processed the record successfully
-> Lambda acknowledged the successful result
-> the source queue returned to zero
```

## 10. Poison Message and DLQ Flow

What we are verifying now:

1. What we verify:
   - whether the source SQS queue accepts the deterministic poison message.
2. Expected result:
   - `SendMessage` returns a non-empty `MessageId`, and the response is saved to `evidence/poison-send.json`.
3. What this proves:
   - SQS accepted the poison message.
4. What this does not prove:
   - that Lambda has already received it, that a `RuntimeError` occurred, that the message was retried, or that it reached the DLQ.
5. Verification layer:
   - Shell and SQS.

Send the deterministic poison message:

```bash
./scripts/send-message.sh \
  "$SOURCE_QUEUE_URL" \
  "$AWS_REGION" \
  events/poison-message.json \
  evidence/poison-send.json

jq . evidence/poison-send.json
```

`generate_report()` causes the following:

```text
RuntimeError
-> the handler catches the error during record processing
-> the exact messageId is included in batchItemFailures
-> the overall Lambda invocation still completes successfully
```

The message is then not deleted and becomes visible again later.

Expected processing cycle:

```text
poison-message.json
-> SendMessage to the source SQS queue
-> the Lambda poller receives the message
-> generate_report raises RuntimeError
-> except catches the record-level error
-> sqs_message_failed
-> returns its messageId in batchItemFailures
-> the Lambda invocation itself completes successfully
-> after 70 seconds, the message becomes visible again
-> Lambda receives it again
-> SQS increments ApproximateReceiveCount
-> the cycle repeats
-> SQS moves the message to the DLQ
```

-> Lambda receives it again

What we are verifying now:

1. What we verify:
   - whether the message appeared in the DLQ after exhausting its receive attempts.
2. Expected result:
   - `dlq_visible=0` may appear initially, followed by `dlq_visible=1`.
3. What this proves:
   - at least one message became visible in the DLQ after the redrive policy was applied.
4. What this does not prove:
   - that it is specifically message `732ea431-...`, what its body contains, or how many times it was received. We will verify this in the next step.
5. Verification layer:
   - SQS and Shell.

Poll DLQ attributes without consuming the message:

```bash
for _ in {1..14}; do
  ./scripts/inspect-queue.sh \
    "$DLQ_URL" \
    "$AWS_REGION" \
    evidence/dlq-attributes.json >/dev/null

  visible="$(jq -r '.Attributes.ApproximateNumberOfMessages // "0"' \
    evidence/dlq-attributes.json)"
  printf 'dlq_visible=%s\n' "$visible"

  if (( visible > 0 )); then
    break
  fi
  sleep 30
done

jq . evidence/dlq-attributes.json
```

This can take several minutes because visibility timeout and Lambda retry
backoff are intentionally real parts of the drill.

This means:

```text
there is one visible message in the DLQ
-> it is available for an operator to receive

there are no invisible messages
-> no consumer has currently received this message

there are no delayed messages
-> it is not waiting for a delay period to expire
```

What we are verifying now:

1. What we verify:
   - the body of the visible message in the DLQ, its SQS `MessageId`, and its `ApproximateReceiveCount`.
2. Expected result:
   - the body contains `task_id = report-poison-001`, `action = generate_report`, and `should_fail = true`; the receive count reflects repeated deliveries.
3. What this proves:
   - the message in the DLQ is the specific deterministic poison message, not a different message.
4. What this does not prove:
   - the exact cause of each failure without correlating the message with CloudWatch Logs.
5. Verification layer:
   - SQS and Shell.

Inspect, but do not delete, the DLQ message:

```bash
./scripts/receive-messages.sh \
  "$DLQ_URL" \
  "$AWS_REGION" \
  evidence/dlq-messages.json

jq '.Messages[]? | {
  MessageId,
  ApproximateReceiveCount: .Attributes.ApproximateReceiveCount,
  body: (.Body | fromjson)
}' evidence/dlq-messages.json
```

Expected body:

```json
{
  "task_id": "report-poison-001",
  "action": "generate_report",
  "should_fail": true
}
```

```text
the source SQS queue accepted the poison message
-> the message was not successfully deleted
-> it exhausted its receive budget
-> SQS moved that specific message to the DLQ
```

`receive-messages.sh` must not delete the message: after it is received, it will only become temporarily invisible for 30 seconds.
Do not run `DeleteMessage`, and do not return the message to the source queue yet.

What we verify:

1. Search for `sqs_message_failed` with the exact `message_id`.
2. Expect `error_type = RuntimeError` and the `task_id` in the error message.
3. This proves that `generate_report()` intentionally rejected the poison message.
4. A single log entry does not prove the exact number of invocations—we need to see multiple entries.
5. Layer: CloudWatch Logs and AWS Lambda.

```bash
aws logs tail "$LOG_GROUP" \
  --region "$AWS_REGION" \
  --since 60m \
  --format short
```

This is runtime evidence that the source queue’s visibility timeout is working:

```text
record failure
-> Lambda does not delete the message
-> it remains invisible for 70 seconds
-> it becomes visible again
-> the Lambda poller receives it again
```

## 11. Partial Failure Versus Invocation Error

The poison path returns a normal handler response with one failed item. It may
leave Lambda `Errors` at zero.

We verify that the record does not contain a valid `messageId`:

```text
no messageId
-> itemIdentifier cannot be constructed
-> the exception occurs before the record-level try/except block
-> process_batch does not return batchItemFailures
-> the entire Lambda invocation fails
```

Flow:

```text
invalid-batch-event.json
-> direct Lambda Invoke
-> lambda_handler
-> process_batch
-> the record does not contain messageId
-> MessageContractError propagates out of process_batch
-> FunctionError = Unhandled
```

What we are verifying now:

1. What we verify:
   - whether the entire Lambda invocation fails with an unhandled error when the record cannot be identified by an exact `messageId`.
2. Expected result:
   - the metadata contains `StatusCode = 200` and `FunctionError = Unhandled`; the payload contains an `errorMessage` mentioning `messageId`.
3. What this proves:
   - the Lambda Invoke API successfully invoked the function, but the handler terminated with an unhandled exception.
4. What this does not prove:
   - SQS behavior, message redelivery, DLQ changes, or message deletion.
5. Verification layer:
   - AWS Lambda.

Now invoke Lambda directly with an intentionally invalid SQS envelope. This command bypasses queue polling and verifies the whole-invocation error boundary:

```bash
aws lambda invoke \
  --function-name "$FUNCTION_NAME" \
  --region "$AWS_REGION" \
  --cli-binary-format raw-in-base64-out \
  --payload fileb://events/invalid-batch-event.json \
  evidence/invalid-batch-response.json \
  > evidence/invalid-batch-metadata.json

jq . evidence/invalid-batch-metadata.json
jq . evidence/invalid-batch-response.json
```

Expected:

```text
StatusCode = 200
-> the Lambda Invoke API accepted and executed the request to the function

FunctionError = Unhandled
-> the handler did not return a normal result
-> the exception propagated out of lambda_handler
-> the entire invocation failed

the record does not contain a valid messageId
-> process_batch raises MessageContractError
-> the exception is not caught at the record level
-> batchItemFailures is not returned
-> the entire invocation fails
```

Direct invocation does not acknowledge or delete any SQS message.
It is used only to demonstrate the contract boundary.

## 12. Drills

### Drill 1. Reject an Unsafe Visibility Timeout

What we are verifying now:

1. What we verify:
   - whether Terraform allows `queue_visibility_timeout_seconds = 60`.
2. Expected result:
   - `terraform plan` fails because of validation or a precondition.
3. What this proves:
   - the infrastructure contract blocks a visibility timeout that is too short before any changes are applied.
4. What this does not prove:
   - the actual runtime behavior of Lambda and SQS—this is only a static Terraform check.
5. Layer:
   - Terraform.


From the Terraform root:

```bash
cd terraform
terraform plan \
  -var='queue_visibility_timeout_seconds=60'
```

Expected failure:

```text
queue_visibility_timeout_seconds must be at least six times the Lambda timeout plus the batching window
```

Explain why `60` is insufficient:

```text
6 × function timeout + batch window
= 6 × 10 + 5
= 65 seconds
```

Return to the lab root:

```bash
cd ..
```

### Drill 2. Inspect Least-Privilege Runtime IAM

What we are verifying now:

1. What we verify:
   - the inline policy of the Lambda execution role.
2. Expected result:
   - CloudWatch Logs permissions are limited to the function’s log group, while SQS permissions are limited to the source queue.
3. What this proves:
   - the runtime role follows the principle of least privilege.
4. What this does not prove:
   - that Lambda actually used every permission or that no other IAM policies exist.
5. Layer:
   - IAM and AWS CLI.

```bash
export ROLE_ARN="$(terraform -chdir=terraform output -raw function_execution_role_arn)"
export POLICY_NAME="$(terraform -chdir=terraform output -raw function_runtime_policy_name)"
export ROLE_NAME="${ROLE_ARN##*/}"

aws iam get-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-name "$POLICY_NAME" \
  --query 'PolicyDocument.Statement' \
  --output json
```

Confirm:

```text
logs permissions -> exact Lambda log group
SQS receive/delete/attributes -> exact source queue ARN
no SQS access -> DLQ ARN
no wildcard SQS resource
```

The SQS service moves the message to the DLQ according to the redrive policy, rather than
Lambda doing so through `sqs:SendMessage`.

The operator who inspects the DLQ uses separate credentials. Runtime and
operator responsibilities are intentionally different.

### Drill 3. Explain Safe DLQ Redrive

A message in the DLQ is evidence of an unresolved failure and means that its retry attempts
have been exhausted and the cause of the failure has not yet been fixed, so the message
must not be returned to the source queue immediately.


Correct order:

1. Inspect the message body and CloudWatch Logs.
2. Determine the cause: code, data, IAM, or an external dependency.
3. Fix the root cause.
4. Deploy the new version.
5. Verify the fix with a controlled message.
6. Approve the redrive operation.
7. Return messages at a limited rate.
8. Monitor source queue age, Lambda `Errors`, and DLQ depth.

The lab does not automate redrive because replaying the unchanged poison message
would create a failure loop.

### Drill 4. Connect Lesson 81

Imagine that `generate_report` sends a paid email, and then the process loses the response.

A possible scenario:

```text
Lambda sent the email
-> the external service completed the operation
-> Lambda lost the response or terminated before acknowledging the SQS message
-> the message was delivered again
-> Lambda sends the email a second time
```

Partial batch response solves only the redelivery decision:

```text
which messageId was processed successfully
which messageId must be retried
```

However, it does not know whether the external service completed the action before the error occurred.

Therefore:

```text
SQS at-least-once delivery
+
a non-atomic external side effect
=
risk of repeating the business action
```

### Solution

Use the following value as the idempotency key:

```text
task_id = report-poison-001
```

Flow:

```text
receive the message
-> check task_id in the idempotency store
-> if task_id is new, create a claim and perform the action
-> store the result
-> if task_id is already completed, return the stored result
-> do not perform the side effect again
```

## 13. Observability

What we are verifying now:

1. What we verify:
   - the state of the three alarms after the successful message, the poison message, and the
   direct failed invocation.
2. Expected result:
   - a table containing the name, state, and reason for each alarm.
3. What this proves:
   - CloudWatch receives the metrics and applies the configured thresholds.
4. What this does not prove:
   - the exact cause of the problem without correlating the alarms with the logs and queue states.
5. Layer:
   - CloudWatch Metrics and CloudWatch Alarms.

Inspect all three alarms:

```bash
export FUNCTION_ERRORS_ALARM="$(terraform -chdir=terraform output -raw function_errors_alarm_name)"
export SOURCE_AGE_ALARM="$(terraform -chdir=terraform output -raw source_age_alarm_name)"
export DLQ_DEPTH_ALARM="$(terraform -chdir=terraform output -raw dlq_depth_alarm_name)"

aws cloudwatch describe-alarms \
  --region "$AWS_REGION" \
  --alarm-names \
    "$FUNCTION_ERRORS_ALARM" \
    "$SOURCE_AGE_ALARM" \
    "$DLQ_DEPTH_ALARM" \
  --query 'MetricAlarms[*].[AlarmName,StateValue,StateReason]' \
  --output table
```

Signal ownership:

| Signal | Detects | Does not prove |
|---|---|---|
| Lambda `Errors` | Whole invocation failed | Every record succeeded |
| Source oldest age | Queue processing is delayed | Root cause |
| DLQ visible depth | Retry budget was exhausted | Remediation is safe |
| Application logs | Per-record outcome and message ID | Queue deletion by themselves |

CloudWatch and SQS approximate metrics are not instantaneous. Correlate them
with logs and queue attributes before making a decision.

An alarm can return to `OK` after an error if the datapoint leaves the evaluation window and missing data is configured as `notBreaching`.

Therefore, `OK` does not mean that no errors have ever occurred.

## 14. Troubleshooting

### Event Source Mapping Does Not Become `Enabled`

What we are verifying now:

1. What we verify:
   - the current state of the mapping and the explanation for its most recent state transition.
2. Expected result in a healthy configuration:
   - `State = Enabled`.
3. What this proves:
   - AWS created and activated the connection between SQS and Lambda.
4. What this does not prove:
   - that messages are being processed successfully—the handler can still return errors.
5. Layer:
   - AWS Lambda Event Source Mapping.

Inspect its reason:

```bash
aws lambda get-event-source-mapping \
  --uuid "$MAPPING_UUID" \
  --region "$AWS_REGION" \
  --query '{State:State,Reason:StateTransitionReason,LastResult:LastProcessingResult}' \
  --output json
```

Four main causes:

1. The execution role is missing:
   - `sqs:ReceiveMessage`
   - `sqs:DeleteMessage`
   - `sqs:GetQueueAttributes`
2. Lambda and SQS are in different Regions.
3. The Lambda timeout is greater than the queue visibility timeout.
4. The mapping specifies the wrong source queue ARN.


### Successful Messages Are Retried with the Poison Message

This means that partial batch response is not actually working as intended.

Check both parts of partial batch reporting:

```text
Event Source Mapping:
   FunctionResponseTypes = ["ReportBatchItemFailures"]

Handler:
   returns batchItemFailures with the exact SQS messageId

After constructing the partial response:
   the handler does NOT raise an exception
```

A thrown exception makes the entire batch fail.

### DLQ Remains Empty

If the poison message does not appear in the DLQ, first determine **where it currently is in its lifecycle**.

Check:

```bash
./scripts/inspect-queue.sh \
  "$SOURCE_QUEUE_URL" \
  "$AWS_REGION" \
  evidence/source-diagnostic.json

aws logs tail "$LOG_GROUP" \
  --region "$AWS_REGION" \
  --since 30m \
  --format short
```

Possible explanations:

```text
the message is currently invisible:
   -> Lambda has already received it
   -> the visibility timeout has not expired yet

maxReceiveCount has not been exhausted yet:
   -> the message is still going through redeliveries

Event Source Mapping is disabled:
   -> Lambda is not receiving messages at all

the message was unexpectedly processed successfully:
   -> Lambda acknowledged success
   -> SQS deleted it
   -> it will not reach the DLQ

ApproximateNumberOfMessages has not updated yet:
   -> SQS metrics/attributes may be delayed
```

How to distinguish the states:

```text
ApproximateNumberOfMessages > 0
-> the message is visible in the source queue

ApproximateNumberOfMessagesNotVisible > 0
-> the message is currently being processed by the consumer / Lambda

both = 0
+
sqs_message_processed exists
-> the message was successfully deleted

both = 0
+
repeated sqs_message_failed entries exist
+
DLQ > 0
-> the message has already moved to the DLQ
```

### Lambda `Errors` Stays `0` for the Poison Message

This is expected in the lab:

```text
generate_report -> RuntimeError
-> process_batch caught the exception
-> messageId was added to batchItemFailures
-> the handler returned a valid response
-> the entire Lambda invocation completed successfully
```

So these failures should be detected through:

```text
CloudWatch Logs
-> sqs_message_failed + message_id

DLQ depth
-> the message exhausted its retry budget

Source queue age
-> the queue is starting to fall behind
```

### The Source Queue Looks Empty During Processing

A message can be invisible rather than deleted. Inspect both:

```text
ApproximateNumberOfMessages
-> visible messages that are ready to be received

ApproximateNumberOfMessagesNotVisible
-> messages that have already been received by a consumer and are hidden by the visibility timeout
```

Do not use `receive-message` as a source-queue inspection command while Lambda is polling.
That receive competes with the event source mapping and changes visibility.

### A Successful Record Still Ran Twice

This is compatible with at-least-once delivery. Partial batch response reduces
one source of duplicates; it does not eliminate every duplicate. Add the
idempotency boundary from lesson 81 around the real business action.

```text
SQS redelivered task_id=123
-> Lambda checks the idempotency key
-> sees that task_id=123 has already been completed
-> does not repeat the business action
```

## 15. Cost and Operational Boundaries

The lab uses:

- 1 × source SQS queue
- 1 × DLQ
- 1 × Lambda
- 1 × Event Source Mapping
- 1 × CloudWatch Log Group
- 3 × CloudWatch Alarm

Primary cost drivers:

- SQS
  -> `SendMessage`
  -> polling
  -> retries
  -> diagnostic requests

- Lambda
  -> number of invocations
  -> batch processing duration

- CloudWatch Logs
  -> log ingestion
  -> log retention

- CloudWatch Alarms
  -> three configured alarms

## 16. Completion Checklist

Before cleanup, confirm:

- 9 Python unit tests pass;
- 5 Terraform native tests pass;
- event source mapping is `Enabled`;
- a successful message produces `sqs_message_processed`;
- a poison message reaches the DLQ after bounded retries;
- partial record failure is distinguished from invocation failure;
- runtime IAM targets only the source queue;
- you can calculate the visibility timeout minimum;
- you can explain why redrive happens only after remediation;
- you can explain why lesson 81 idempotency still matters.

## 17. Cleanup

Create and review the destroy plan:

```bash
terraform plan -destroy -out=tfplan-destroy
terraform show tfplan-destroy
terraform apply tfplan-destroy
```

The source queue and DLQ are disposable lab resources. Destroying them deletes
remaining messages, including the poison-message evidence.

Verify state:

```bash
terraform state list
```

The command should print no managed resources.

## 18. Final Model

Remember:

1. An SQS event source mapping is a managed poller, not a Lambda destination.
2. One Lambda invocation can contain several SQS records.
3. Without `partial batch response`, one error can retry the whole batch.
4. `ReportBatchItemFailures` must be enabled in Terraform and implemented in code.
5. Visibility timeout hides a message; it does not acknowledge it.
6. Redrive policy bounds repeated poison-message processing.
7. A DLQ message requires investigation before replay.
8. Partial record failures may not increment Lambda `Errors`.
9. `At-least-once` processing still requires idempotent business actions.

## 19. Official References

- [Using Lambda with Amazon SQS](https://docs.aws.amazon.com/lambda/latest/dg/with-sqs.html)
- [Creating and configuring an SQS event source mapping](https://docs.aws.amazon.com/lambda/latest/dg/services-sqs-configure.html)
- [Handling errors and partial batch responses](https://docs.aws.amazon.com/lambda/latest/dg/services-sqs-errorhandling.html)
- [Lambda parameters for SQS event sources](https://docs.aws.amazon.com/lambda/latest/dg/services-sqs-parameters.html)
- [Using dead-letter queues in Amazon SQS](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-dead-letter-queues.html)
