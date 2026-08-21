# Lesson 84. Lambda with SQS FIFO: Ordering, Deduplication, and Message Groups

## 1. Why This Lesson Exists

Lessons 82 and 83 used a standard SQS queue. That design provided durable buffering,
partial batch failures (`ReportBatchItemFailures`), and bounded `concurrency`, but it
made no strict ordering promise.

Some workflows have an additional invariant:

```text
update 1 for one entity
-> update 2 for the same entity
-> update 3 for the same entity
```

Processing update 3 before update 2 can corrupt state even if every individual
message is valid. An SQS FIFO queue addresses this problem through message groups:

```text
same MessageGroupId      -> ordered, one active Lambda instance for that group
different MessageGroupId -> may be processed concurrently
```

FIFO also adds `producer`-side duplicate suppression. That feature is useful, but it
does not make the consumer exactly-once and does not replace the DynamoDB idempotency
boundary from lesson 81.

This lesson builds the full contract:

```text
`producer` chooses a stable group key (`MessageGroupId`)
-> producer assigns an explicit deduplication ID (`MessageDeduplicationId`)
-> SQS FIFO preserves order inside the group
-> Lambda processes different groups in parallel
-> handler stops after the first batch failure
-> failed and unprocessed records are retried
```

What is new compared with Standard SQS:

| Standard SQS                                    | FIFO SQS                                            |
| ----------------------------------------------- | --------------------------------------------------- |
| strict ordering is not guaranteed               | ordering is preserved within a `MessageGroupId`     |
| message groups are not the basis of concurrency | different groups provide parallelism                |
| no FIFO producer deduplication                  | supports `MessageDeduplicationId`                   |
| batch records can be treated independently      | after a failure, a FIFO failure barrier is required |

## 2. Learning Outcomes

After the lesson, you will be able to:

- explain why FIFO ordering is scoped to `MessageGroupId`;
- choose a group key from a business entity rather than from a random request;
- distinguish queue order from application idempotency;
- explain the five-minute FIFO deduplication interval;
- use explicit `MessageDeduplicationId` values;
- calculate the concurrency ceiling created by active message groups;
- preserve order when `ReportBatchItemFailures` is enabled;
- identify the hot-group bottleneck;
- deploy a FIFO source queue with a FIFO DLQ;
- verify ordering, cross-group parallelism, duplicate suppression, and failure blocking;
- reject invalid FIFO batch, concurrency, and visibility configurations;

Evidence map:

| Claim | Evidence |
|---|---|
| Source and DLQ are FIFO | AWS CLI reports `FifoQueue = true` and both names end with `.fifo` |
| Producer contract is explicit | Sender supplies both group and deduplication IDs |
| One group is ordered | `work_completed` logs for one group have sequence `1, 2, 3...` |
| Different groups can overlap | Logs show group A and group B work active during overlapping time intervals |
| Duplicate send is suppressed | Two sends are accepted with one deduplication ID, but only the first task is logged |
| FIFO failure barrier works | Failed plus unprocessed IDs appear in `batchItemFailures` and deferred logs |
| DLQ behavior is explained | The poison and returned unprocessed record consume separate receive budgets and can reach the FIFO DLQ together |
| Infrastructure constraints hold | Nine Terraform native tests pass |

The main outcomes can be summarized in six blocks:

```text
1. ordering
   - ordering is guaranteed only within a MessageGroupId

2. grouping
   - use a stable business key
   - not a random ID

3. deduplication
   - explicit MessageDeduplicationId
   - 5-minute deduplication window
   - not exactly-once

4. concurrency
   - depends on the number of active groups
   - MaximumConcurrency only sets an upper bound

5. failure handling
   - after the first failure, do not continue processing the batch
   - preserve FIFO order

6. recovery
   - every returned record consumes its own receive budget
   - with BatchSize > 1, the poison and deferred tail can reach the DLQ together
   - new group work can continue after this barrier leaves the source queue
```

### 2.1. Lesson Terminology

| English term | Plain wording | Precise meaning in this lesson |
|---|---|---|
| `FIFO` | first in, first out | Ordered delivery within an SQS message group |
| `MessageGroupId` | ordering partition key | Messages with the same value are processed sequentially |
| `MessageDeduplicationId` | producer duplicate token | Suppresses another send with the same token during the deduplication interval |
| `deduplication interval` | five-minute suppression window | Time during which SQS remembers a deduplication ID |
| `SequenceNumber` | SQS transport sequence | Large non-consecutive number assigned by SQS to a FIFO message |
| `business sequence` | domain order number | Application-controlled sequence used to reason about entity updates |
| `hot group` | overloaded ordering partition | One group whose sequential backlog dominates queue age |
| `failure barrier` | stop-after-first-failure rule | Failed and later unprocessed records are returned together |
| `head-of-line blocking` | earlier work blocks later work | A failed record prevents later records in its group from progressing |
| `partial batch response` | per-record retry response | `batchItemFailures` returned to the Lambda event source mapping |

## 3. Mental Model

### 3.1. FIFO Is Ordered Per Group, Not Globally

Consider two customer accounts:

```text
group customer-100: debit-1 -> debit-2 -> debit-3
group customer-200: credit-1 -> credit-2
```

SQS FIFO must preserve ordering within each group, but it does not have to
combine multiple groups into one global order:

```text
Lambda invocation A -> customer-100
Lambda invocation B -> customer-200
```

The group key is therefore an architecture decision. A useful key identifies
the smallest business entity that needs strict order:

| Requirement | Possible group key (`MessageGroupId`) |
|---|---|
| Order updates for one account | `account_id` |
| Order commands for one device | `device_id` |
| Order events for one aggregate | `aggregate_id` |
| Global order for everything | One constant group ID, with very low parallelism |

A random group ID destroys ordering because related messages enter different
groups. One constant group ID preserves global order but limits the queue to one
active group and therefore one active Lambda instance for that source.

### 3.2. Message Groups Become a Concurrency Boundary

For an SQS FIFO event source, the effective concurrency is approximately bounded by:

```text
effective concurrency
= minimum(
    active MessageGroupId count,
    event source MaximumConcurrency,
    available Lambda/account concurrency,
    demand
  )
```

Examples:

```text
1 active group, MaximumConcurrency = 4  -> at most 1 concurrent invocation
2 active groups, MaximumConcurrency = 4 -> at most 2 concurrent invocations
8 active groups, MaximumConcurrency = 4 -> at most 4 concurrent invocations
```

Increasing `MaximumConcurrency` cannot speed up one hot group. To gain parallelism,
the business workload needs more independent ordering groups.

### 3.3. Deduplication Is a Producer Feature, Not Exactly-Once Processing

The lab disables content-based deduplication and requires an explicit token:

```text
MessageDeduplicationId = stable identity of one producer operation
```

If two sends use the same token within the five-minute interval:

```text
first SendMessage  -> accepted and available for delivery
second SendMessage -> accepted but not delivered again
```

```text
operation:
charge-order-123-v2

MessageDeduplicationId:
charge-order-123-v2
```

If the producer sends it again with the same ID because of a retry, FIFO can recognize it as a duplicate.

SQS continues remembering the token even after the first message is received and
deleted. However, consumer idempotency is still required because:

- a delivered message can be retried when processing is not acknowledged;
- the producer can send the same business operation with a different token;
- the five-minute interval can expire;
- downstream side effects can fail after being committed but before acknowledgement.

The correct model is:

```text
FIFO deduplication -> reduces duplicate insertion by the producer
consumer idempotency -> protects the business side effect during processing
```

### 3.4. SQS Sequence Number Is Not the Business Version

```text
SequenceNumber
  - assigned by SQS
  - transport metadata

sequence
  - assigned by our application
  - business ordering
```

SQS assigns a `SequenceNumber` to each FIFO message. It is useful transport metadata,
but it is a large non-consecutive value and should not replace an application version.

The lab body includes an explicit sequence:

```json
{
  "task_id": "group-a-run-1-task-2",
  "sequence": 2,
  "work_seconds": 1,
  "should_fail": false
}
```

Do not confuse these three things:

```text
MessageGroupId
  - which sequence the message belongs to

SequenceNumber
  - transport metadata assigned by SQS

sequence
  - which step this is within the business sequence
```

The business sequence makes logs and tests understandable. A real consumer can also compare
the incoming version with the current entity version before applying a state transition.

### 3.5. FIFO Partial Failure Requires a Barrier

For a standard queue, lesson 82 processed every record independently and returned
only the records that failed. Doing that blindly for FIFO can violate order:

```text
record 1 succeeds
record 2 fails
record 3 succeeds  <- unsafe if record 3 depends on record 2
```

So FIFO may have delivered the messages in the correct order, but the consumer itself
violated the business processing order. That is why a `failure barrier` is needed
after the first failure.

The FIFO-safe response is:

```text
process record 1
record 2 fails
stop processing
return record 2 and record 3 in batchItemFailures
```

The handler intentionally sacrifices some batch throughput to preserve the order
contract. A later retry starts again from the failed boundary.

### 3.6. A Poison Message Creates Head-of-Line Blocking

If one message always fails, later messages from the same group cannot overtake it:

```text
group A: sequence 1 -> sequence 2 (poison) -> sequence 3
                              |
                              +-> retries, then FIFO DLQ
```

Because of FIFO, messages 3 and 4 cannot overtake message 2. This is `head-of-line blocking`.

Messages from other groups can continue in parallel. However, there is an important
consequence for the batch already received: sequence 3 is returned in
`batchItemFailures` together with sequence 2. SQS increments
`ApproximateReceiveCount` for both records even though sequence 3 never ran its
business logic.

With `BatchSize = 5`, retries commonly receive the same tail again:

```text
attempt 1: sequence 2 failed, sequence 3 deferred -> return 2 + 3
attempt 2: sequence 2 failed, sequence 3 deferred -> return 2 + 3
attempt 3: sequence 2 failed, sequence 3 deferred -> return 2 + 3
next receive exceeds maxReceiveCount -> both 2 and 3 may reach the DLQ
```

This is neither a FIFO violation nor a handler bug. It preserves ordering at the
cost of potentially moving a valid batch tail to the DLQ. If the requirement is
that only the directly failing record can reach the DLQ, use `BatchSize = 1`.
The next group record is then not received in the same batch as the poison record,
at the cost of batching efficiency.

This is why FIFO monitoring must include oldest-message age and DLQ depth. A queue
can have plenty of total capacity while one important group remains blocked.

For FIFO, the DLQ is not only a way to isolate failures, but also a mechanism for clearing
`head-of-line blocking` after the retry attempts are exhausted.

Key point:

```text
failure barrier
  - prevents later messages from overtaking the failed message

head-of-line blocking
  - a consequence of this ordering when the failure keeps repeating

FIFO DLQ
  - after retries are exhausted, removes returned records from the source queue
  - with BatchSize > 1, this can include the poison and a valid deferred tail
  - new group messages can move again after the barrier is removed
```

### 3.7. Standard or FIFO Is a Business Decision

| Question | Standard queue | FIFO queue |
|---|---|---|
| Strict order required? | No | Within each group |
| Producer deduplication window? | No | Yes |
| Parallelism model | Queue and Lambda capacity | Number of active groups plus capacity |
| Hot-key risk | Lower | Hot group can serialize work |
| Batch failure strategy | Process records independently | Stop after first failure |
| Typical use | Independent background jobs | Ordered entity commands or state transitions |

Do not choose FIFO merely because ordering sounds safer. It adds a contract and a throughput
shape that the producer, consumer, monitoring, and recovery process must all understand.

## 4. Lab Architecture

```text
send-fifo-sequence.sh / send-dedup-pair.sh
                 |
                 | MessageGroupId + MessageDeduplicationId
                 v
+--------------------------------+
| SQS FIFO source queue           |
| explicit deduplication          |
| visibility timeout = 40s        |
+----------------+---------------+
                 |
                 | BatchSize = 5
                 | MaximumConcurrency = 4
                 | ReportBatchItemFailures
                 v
+--------------------------------+
| Lambda FIFO worker              |
| stop after first failure        |
| timeout = 6s                    |
+----------------+---------------+
                 |
                 +----> structured CloudWatch Logs

exhausted failed record
                 |
                 v
+--------------------------------+
| SQS FIFO DLQ                    |
+--------------------------------+
```

The entire flow at a glance:

```text
Producer
│
│ MessageGroupId
│ MessageDeduplicationId
V
SQS FIFO source
│
│ BatchSize = 5
│ MaximumConcurrency = 4
│ ReportBatchItemFailures
V
Lambda
│
├─ success - message completed
│
├─ first failure
│    - failure barrier
│    - failed + deferred records retry
│
└─ poison message
     - retries exhausted
     - FIFO DLQ
```

Both queues are FIFO. A standard DLQ cannot be attached to a FIFO source queue.
The function execution role consumes only the source queue and cannot inspect or
delete DLQ records.

## 5. Implementation Walkthrough

### 5.1. Validate Transport and Business Fields Separately

Open:

```text
sed -n '1,280p' \
  lessons/84-lambda-sqs-fifo-ordering-and-deduplication/lab_84/app/lambda_function.py
```

The handler validates transport metadata:

```text
messageId
attributes.MessageGroupId
attributes.MessageDeduplicationId
```

Their meaning:

```text
messageId
  - the specific SQS message
  - needed for batchItemFailures

MessageGroupId
  - which FIFO sequence the message belongs to

MessageDeduplicationId
  - which deduplication ID was provided by the producer
```

Important: this is **not our business-task data**. It is transport metadata.

It then validates the JSON body:

```text
task_id
sequence
work_seconds
should_fail
```

Important: this is **our business-task data**. It is the business contract.

`TypedDict` does not validate runtime input;
`isinstance()` and explicit range checks still enforce the actual contract.

### 5.2. Validate Every Message ID Before Work Starts

`batchItemFailures` can identify a record only by `messageId`. The handler first
checks every record ID before running business work:

```python
message_ids = [get_message_id(record) for record in records]
```

Suppose the batch looks like this:

```text
record 1 -> valid messageId
record 2 -> valid messageId
record 3 -> broken / missing messageId
```

Therefore, the order is different:

1. Validate the `messageId` of all records.
2. Make sure the batch can be represented correctly in the response.
3. Only then run the business logic.

In other words, first validate the transport contract of the entire batch.

Without this step, the function could complete an early side effect and then discover
that a later malformed record cannot be represented in the response.

If the preliminary `messageId` validation fails:

```text
the handler does not start partial business processing
  - the entire invocation fails
  - the invalid batch will be retried
```

### 5.3. Stop After the First Failure

The central FIFO rule is visible in the code:

```python
failed_and_unprocessed = message_ids[index:]
failures.extend(
    {"itemIdentifier": failed_message_id}
    for failed_message_id in failed_and_unprocessed
)
break
```

The failed message and all records after it are returned. `work_deferred_after_failure`
logs distinguish unprocessed records from records whose business work actually failed.

### 5.4. Send Explicit Group and Deduplication IDs

`send-fifo-sequence.sh` builds batches of at most ten SQS entries. Every entry contains:

```text
MessageGroupId         -> ordering scope chosen by the caller
MessageDeduplicationId -> unique producer-operation token
sequence               -> business-visible order inside the body
```

The script adds a run ID so repeating the drill within five minutes does not
accidentally suppress the new sequence.

### 5.5. Demonstrate Duplicate Suppression Deliberately

`send-dedup-pair.sh` does the opposite: it sends two different bodies with one
explicit deduplication ID. Both API calls can succeed, but only the first body
should become available to Lambda during the deduplication interval.

This proves a producer guarantee. It does not prove exactly-once side effects.

## 6. Local Verification

From the repository root:

```bash
python3 -m unittest discover \
  -s lessons/84-lambda-sqs-fifo-ordering-and-deduplication/lab_84/tests -v

for script in lessons/84-lambda-sqs-fifo-ordering-and-deduplication/lab_84/scripts/*.sh; do
  bash -n "$script"
done
```

Expected result:

```text
Ran 8 tests
OK
```

The tests prove parsing, planned failure, ordered calls, stop-after-first-failure,
and pre-work transport validation. They do not prove AWS FIFO delivery behavior.

## 7. Terraform Validation and Deployment

Enter the Terraform root:

```bash
cd lessons/84-lambda-sqs-fifo-ordering-and-deduplication/lab_84/terraform
cp terraform.tfvars.example terraform.tfvars
```

Run local checks:

```bash
terraform init
terraform fmt -check -recursive
terraform validate
terraform test
```

Expected native-test result:

```text
Success! 9 passed, 0 failed.
```

Authenticate and verify the active identity:

```bash
export AWS_PROFILE=YOUR_PROFILE
aws sso login --profile "$AWS_PROFILE"
aws sts get-caller-identity
```

Create, review, and apply a saved plan:

```bash
terraform plan -out=tfplan
terraform show -no-color tfplan | less
terraform apply tfplan
```

Export runtime values:

```bash
export AWS_REGION="$(terraform output -raw aws_region)"
export FUNCTION_NAME="$(terraform output -raw function_name)"
export SOURCE_QUEUE_URL="$(terraform output -raw source_queue_url)"
export DLQ_URL="$(terraform output -raw dead_letter_queue_url)"
export MAPPING_UUID="$(terraform output -raw event_source_mapping_uuid)"
mkdir -p ../evidence
```

## 8. Verify the FIFO Infrastructure Contract

Inspect source-queue attributes:

```bash
aws sqs get-queue-attributes \
  --region "$AWS_REGION" \
  --queue-url "$SOURCE_QUEUE_URL" \
  --attribute-names FifoQueue ContentBasedDeduplication RedrivePolicy \
  --query 'Attributes' \
  --output json

aws sqs get-queue-attributes \
  --queue-url "$DLQ_URL" \
  --attribute-names FifoQueue
```

Expected properties:

```text
FifoQueue = true
ContentBasedDeduplication = false
RedrivePolicy points to the FIFO DLQ

FifoQueue = true
```

What exactly this proves:

```text
FifoQueue=true
  - the source queue is actually FIFO

ContentBasedDeduplication=false
  - automatic deduplication based on the message body is disabled
  - the producer must provide MessageDeduplicationId

RedrivePolicy
  - the source queue is linked to the DLQ

FifoQueue=true
  - the DLQ_URL is actually FIFO
```

Inspect the event source mapping:

```bash
aws lambda get-event-source-mapping \
  --region "$AWS_REGION" \
  --uuid "$MAPPING_UUID" \
  --query '{State:State,BatchSize:BatchSize,MaximumConcurrency:ScalingConfig.MaximumConcurrency,ResponseTypes:FunctionResponseTypes}' \
  --output table
```

Expected values:

```text
State = Enabled
BatchSize = 5
MaximumConcurrency = 4
ResponseTypes contains ReportBatchItemFailures
```

Here it is important that we prove four different things:

```text
Enabled
  - the mapping is active

BatchSize = 5
  - up to 5 records per Lambda batch

MaximumConcurrency = 4
  - ceiling = 4 concurrent invocations
  - NOT a guarantee that there will always be 4

ReportBatchItemFailures
  - the Lambda mapping accepts partial batch responses
```

## 9. Drill 1: Verify Order Inside One Group

Send five messages to one group:

```bash
../scripts/send-fifo-sequence.sh \
  "$SOURCE_QUEUE_URL" "$AWS_REGION" \
  group-a 5 1 0 ../evidence/group-a.json
```

Arguments after the region mean:

```text
group-a -> MessageGroupId
5       -> number of messages
1       -> seconds of work per message
0       -> no planned failure
```

Wait for processing, then inspect logs:

```bash
sleep 10
aws logs tail "/aws/lambda/${FUNCTION_NAME}" \
  --region "$AWS_REGION" \
  --since 10m \
  --format short | grep 'group-a' | grep 'work_completed'
```

Or filter specifically by this `group_id` + `run_id` and verify:

```bash
export RUN_ID="20261234T567890-12345"

aws logs tail "/aws/lambda/${FUNCTION_NAME}" \
  --region "$AWS_REGION" \
  --since 10m \
  --format short \
  | grep '"group_id": "group-a"' \
  | grep "$RUN_ID" \
  | grep '"event": "work_completed"'
```

Within this run, completed business sequence values must appear as:

```text
1 -> 2 -> 3 -> 4 -> 5
```

For each record, we also have its own:

```text
message_id -> identity of the SQS message
task_id    -> specific task in our run
sequence   -> 1, 2, 3, 4, 5
request_id -> specific Lambda invocation
group_id   -> group-a
```

Do not infer global order from interleaved CloudWatch streams. Filter by group and
run-specific task IDs before evaluating one sequence.

### Drill 2: Verify Parallelism Across Groups

Send two independent groups at nearly the same time:

```bash
../scripts/send-fifo-sequence.sh \
  "$SOURCE_QUEUE_URL" "$AWS_REGION" \
  group-parallel-a 3 1 0 ../evidence/group-parallel-a.json &
export GROUP_A_PID=$!

../scripts/send-fifo-sequence.sh \
  "$SOURCE_QUEUE_URL" "$AWS_REGION" \
  group-parallel-b 3 1 0 ../evidence/group-parallel-b.json &
export GROUP_B_PID=$!

wait "$GROUP_A_PID" "$GROUP_B_PID"
```

Inspect starts and completions:

```bash
sleep 8

aws logs tail "/aws/lambda/${FUNCTION_NAME}" \
  --region "$AWS_REGION" \
  --since 10m \
  --format short | grep -E 'group-parallel-(a|b)' \
  | grep -E 'work_started|work_completed'
```

Expected model:

```text
group A sequence remains ordered
group B sequence remains ordered
work from A and B can overlap
effective concurrency is about 2 because only 2 groups are active
```

`MaximumConcurrency = 4` is only a ceiling. It does not create four-way
parallelism when the queue contains two active groups.

```text
group A → at most 1 active invocation for this group
group B → at most 1 active invocation for this group

total → up to 2 concurrent invocations
```

### Drill 3: Verify Producer Deduplication

Create a fresh token and send two different bodies with that token:

```bash
export DEDUP_ID="dedup-$(date -u +%Y%m%dT%H%M%S)"

../scripts/send-dedup-pair.sh \
  "$SOURCE_QUEUE_URL" "$AWS_REGION" \
  group-dedup "$DEDUP_ID" ../evidence/dedup-pair.json
```

The script reports two accepted API requests. Inspect the saved SQS responses:

```bash
jq '.' ../evidence/dedup-pair.json
```

Then inspect logs by deduplication ID:

```bash
sleep 8
aws logs tail "/aws/lambda/${FUNCTION_NAME}" \
  --region "$AWS_REGION" \
  --since 10m \
  --format short | grep "$DEDUP_ID"
```

Expected result:

```text
two SendMessage calls are acknowledged
only the task with task_id = dedup-first is delivered
the task with task_id = dedup-second is absent

Both SendMessage calls receive successful responses from SQS, and they have:
 - the same MessageId
 - the same SequenceNumber
```

This means SQS recognized the second request as a duplicate of the same FIFO operation
within the deduplication window.

### Drill 4: Verify the FIFO Failure Barrier

Send three records with a planned failure at sequence 2:

```bash
../scripts/send-fifo-sequence.sh \
  "$SOURCE_QUEUE_URL" "$AWS_REGION" \
  group-poison 3 0 2 ../evidence/group-poison.json

export RUN_ID="$(jq -r '.run_id' ../evidence/group-poison.json)"
```

Collect the experiment logs:

```bash
aws logs tail "/aws/lambda/${FUNCTION_NAME}" \
  --region "$AWS_REGION" \
  --since 30m \
  --format short \
  > ../evidence/group-poison-runtime.log
```

Filter this file locally:

```bash
grep "$RUN_ID" ../evidence/group-poison-runtime.log
```

We found the `request_id` of the first attempt: `1ea1a12f-1234-123a-bfaf-c12ddd12345`

Locally:

```bash
grep '1ea1a12f-1234-123a-bfaf-c12ddd12345' \
  ../evidence/group-poison-runtime.log \
  > ../evidence/group-poison-first-attempt.log
```

Expected first-attempt behavior:

```text
sequence 1 -> completed
sequence 2 -> work_failed
sequence 3 -> work_deferred_after_failure
batchItemFailures -> sequence 2 and sequence 3 message IDs
```

But the key point is that even though sequence 3 is valid, it must not be processed
at all during the first attempt.

Sequences 2 and 3 are returned together. Each therefore consumes its own receive
budget and both can reach the FIFO DLQ after that budget is exhausted. Because the
visibility timeout is 40 seconds, allow several minutes for the full redrive sequence.

Our `poison message`: `message_id = 1d12bfe1-123b-12bc-1aac-1234a0e12acf`

Retry attempts for the `poison message`:

```bash
export POISON_MESSAGE_ID="1d12bfe1-123b-12bc-1aac-1234a0e12acf"

aws logs tail "/aws/lambda/${FUNCTION_NAME}" \
  --region "$AWS_REGION" \
  --since 30m \
  --format short \
  | grep "$POISON_MESSAGE_ID" \
  > ../evidence/group-poison-retries.log
```

At this point we have:

```text
group-poison.json
  - what we sent

group-poison-first-attempt.log
  - failure barrier:
   1 success
   2 failed
   3 deferred
   batchItemFailures = 2 + 3

group-poison-retries.log
  - the poison message is retried
  - valid sequence 3 remains deferred and is returned as well
```

Monitor queue depth without receiving source messages:

```bash
watch -n 10 "aws sqs get-queue-attributes \
  --region '$AWS_REGION' \
  --queue-url '$SOURCE_QUEUE_URL' \
  --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible \
  --query 'Attributes' --output table"
```

After the returned tail leaves the source queue, the group becomes unblocked, but
the already-sent sequence 3 does not complete: with the same receive count it can
reach the DLQ together with sequence 2. Inspect DLQ depth:

```bash
aws sqs get-queue-attributes \
  --region "$AWS_REGION" \
  --queue-url "$DLQ_URL" \
  --attribute-names ApproximateNumberOfMessages \
  --query 'Attributes.ApproximateNumberOfMessages' \
  --output text
```

To inspect every DLQ record from this run without deleting it:

```bash
aws sqs receive-message \
  --region "$AWS_REGION" \
  --queue-url "$DLQ_URL" \
  --max-number-of-messages 10 \
  --visibility-timeout 0 \
  --attribute-names All \
  --message-attribute-names All \
  --output json > ../evidence/dlq-snapshot.json

jq --arg run "$RUN_ID" '
  .Messages[]?
  | (.Body | fromjson) as $body
  | select($body.task_id | contains($run))
  | {
      message_id: .MessageId,
      receive_count: .Attributes.ApproximateReceiveCount,
      group_id: .Attributes.MessageGroupId,
      task_id: $body.task_id,
      sequence: $body.sequence,
      should_fail: $body.should_fail
    }
' ../evidence/dlq-snapshot.json
```

Expect both sequence 2 and sequence 3. With `maxReceiveCount = 3`, an
`ApproximateReceiveCount` of 4 is expected because SQS moves a record when its
receive count **exceeds** the configured limit. `receive-message` can return fewer
records than requested, so repeat the snapshot if necessary.

```text
2 -> actually fails
3 -> is not processed because of the failure barrier
|
both are returned through batchItemFailures
|
both get their own ReceiveCount
|
both can exhaust their receive budget
|
both -> FIFO DLQ
```

Now send a new valid task to the same group and verify that the group processes
work again:

```bash
../scripts/send-fifo-sequence.sh \
  "$SOURCE_QUEUE_URL" "$AWS_REGION" \
  group-poison 1 0 0 ../evidence/group-poison-after-dlq.json
```

After execution, get the new `run_id`:

```bash
export AFTER_DLQ_RUN_ID="$(jq -r '.run_id' ../evidence/group-poison-after-dlq.json)"

printf 'run_id=%s\n' "$AFTER_DLQ_RUN_ID"
```

Then:

```bash
sleep 5

aws logs tail "/aws/lambda/${FUNCTION_NAME}" \
  --region "$AWS_REGION" \
  --since 10m \
  --format short \
  | grep '"group_id": "group-poison"' \
  | grep "$AFTER_DLQ_RUN_ID" \
  | grep -E 'work_started|work_completed'
```

Expected:

```text
new sequence 1 -> work_started
new sequence 1 -> work_completed
```

This proves that the group is unblocked; it does not recover the old sequence 3.
DLQ records require a separate, controlled recovery procedure.

This receive call changes DLQ receive metadata even though it does not delete the
message. Do not use the same command on the active source queue.

## 10. Guardrails Terraform

### Guardrail 1. Reject a FIFO Batch Above Ten

```bash
terraform plan -var='batch_size=11'
```

Expected result:

```text
batch_size must be an integer between 1 and 10 for an SQS FIFO source.
```

### Guardrail 2. Reject a Function Limit Below the Mapping Cap

```bash
terraform plan \
  -var='event_source_maximum_concurrency=4' \
  -var='function_reserved_concurrency=3'
```

Expected result:

```text
function_reserved_concurrency must be at least event_source_maximum_concurrency.
```

### Guardrail 3. Reject an Unsafe Visibility Timeout

```bash
terraform plan \
  -var='function_timeout_seconds=6' \
  -var='queue_visibility_timeout_seconds=35'
```

Expected result:

```text
queue_visibility_timeout_seconds must be at least six times the Lambda timeout.
```

These failures occur before infrastructure is changed.

## 11. Troubleshooting

### Messages from One Group Run in Parallel

Verify that the `producer` is really reusing the same `MessageGroupId`. Similar
task IDs in different groups have no shared ordering boundary.

### Only One Invocation Runs Despite a High Mapping Cap

Count active group IDs. One `hot group` allows one active Lambda instance for that
group. Increase group cardinality only when the business order can be partitioned safely.

### The Second Deduplication Message Appears

Check that both sends used exactly the same explicit `MessageDeduplicationId`, the
same FIFO queue, and occurred within five minutes. Do not compare only body fields.

### Later Records Were Processed After a Failure

Confirm that the deployed package contains the FIFO handler and that
`ReportBatchItemFailures` is configured. The handler must `break` after the first
failure and return all remaining identifiers.

### A Valid Record After the Poison Reached the DLQ

This is expected with `BatchSize > 1` when both records were received in one
batch. The handler returned the valid record as unprocessed to preserve order,
so its `ApproximateReceiveCount` increased together with the poison record's
count. Compare `message_id`, `sequence`, `should_fail`, and receive count in the
DLQ snapshot.

Choose according to the contract:

- use `BatchSize > 1` when efficiency matters and the DLQ procedure can
  separate the poison from a valid deferred tail;
- use `BatchSize = 1` when the DLQ must isolate only the directly failing record
  and lower batching efficiency is acceptable.

### A Group Stays Blocked

Inspect `work_failed`, receive attempts, oldest-message age, and FIFO DLQ depth.
A deterministic poison record must be fixed or isolated; increasing concurrency
does not unblock its group.

### CloudWatch Logs Look Out of Order

Different groups and execution environments write to different log streams.
Filter by `group_id` and one run-specific `task_id` prefix. Ordering across groups
is not guaranteed and should not be reconstructed from global log arrival order.

### Diagnostic Sequence

```text
identify group_id and run_id
-> inspect mapping state
-> inspect work_failed / work_deferred logs
-> inspect source age and visible depth
-> inspect FIFO DLQ depth
-> correct the poison message or consumer
-> replay only through an approved recovery procedure
```

## 12. Cost and Operational Boundaries

The lab creates:

- one Lambda function;
- one FIFO source queue and one FIFO DLQ;
- one event source mapping;
- one IAM role and inline policy;
- one CloudWatch log group;
- three CloudWatch alarms.

FIFO requests, Lambda duration, CloudWatch logs, metrics, and alarms can incur charges.

Production capacity review should include:

```text
What business entity defines ordering?
How many active groups exist at peak?
Can one group become a hot partition?
How is MessageDeduplicationId generated and retained?
What idempotency boundary protects the side effect?
How long may one group remain blocked?
Who approves DLQ replay and in what order?
```

## 13. Completion Checklist

The lesson is complete when:

- 8 Python tests pass;
- 9 Terraform native tests pass;
- source queue and DLQ are FIFO;
- content-based deduplication is disabled;
- mapping uses `BatchSize = 5` and `MaximumConcurrency = 4`;
- one group completes in business-sequence order;
- two groups show independent order and overlapping work;
- a duplicate pair produces only one delivered task;
- first failure returns failed plus unprocessed records;
- poison and valid deferred records can reach the FIFO DLQ together;
- a new valid task proves that the group is unblocked afterward;
- all three invalid Terraform configurations are rejected;
- you can explain why FIFO still needs idempotency.

## 14. Cleanup

Wait until the source queue is drained, then review a destroy plan:

```bash
terraform plan -destroy -out=tfplan-destroy
terraform show -no-color tfplan-destroy | less
terraform apply tfplan-destroy
```

Verify state:

```bash
terraform state list
```

The command should return no managed resources.

## 15. Final Model

Remember:

1. FIFO order is scoped to `MessageGroupId`.
2. Different groups provide parallelism without breaking per-group order.
3. One hot group cannot be accelerated by raising only `MaximumConcurrency`.
4. Deduplication ID suppresses producer duplicates for five minutes.
5. FIFO deduplication does not replace consumer idempotency.
6. SQS `SequenceNumber` is transport metadata, not the application version.
7. A FIFO partial batch handler stops after the first failure.
8. Failed and unprocessed records must be returned together.
9. Every returned unprocessed record consumes its own receive budget and can
   reach the DLQ together with the poison record.
10. `BatchSize = 1` isolates failures more precisely; a larger batch is more
    efficient but requires handling valid deferred records in the DLQ.
11. FIFO recovery must preserve the same ordering assumptions as normal delivery.

## 16. Official References

- [SQS FIFO queue key terms](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/FIFO-key-terms.html)
- [SQS FIFO queues and Lambda concurrency](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/fifo-queue-lambda-behavior.html)
- [Lambda SQS scaling configuration](https://docs.aws.amazon.com/lambda/latest/dg/services-sqs-scaling.html)
- [Lambda SQS error handling and partial batch responses](https://docs.aws.amazon.com/lambda/latest/dg/services-sqs-errorhandling.html)
- [Using dead-letter queues in Amazon SQS](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-dead-letter-queues.html)
- [Lambda parameters for SQS event source mappings](https://docs.aws.amazon.com/lambda/latest/dg/services-sqs-parameters.html)
- [SQS FIFO exactly-once processing terminology](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/FIFO-queues-exactly-once-processing.html)
