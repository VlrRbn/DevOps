# Lesson 83. Lambda SQS Scaling, Concurrency, and Backpressure

## 1. Why This Lesson Exists

Lesson 82 established the correctness contract for an SQS batch consumer:

```text
receive a batch
-> process records independently
-> return exact failed messageId values
-> retry only failed records
```

Correct failure handling is necessary, but it does not answer a capacity question:

> What happens when messages arrive faster than the function can complete them?

Without an explicit limit, an SQS event source mapping can scale Lambda rapidly.
That may drain the queue quickly, but it may also overload a database, exhaust an
API quota, consume regional Lambda concurrency, or increase cost unexpectedly.

This lesson adds a controlled rate mismatch:

```text
20 messages arrive in a burst
-> one message requires about 8 seconds of work
-> the mapping allows 2 concurrent invocations
-> some messages remain visible in SQS
-> two messages are normally in flight
-> the backlog drains gradually
```

The backlog is not automatically a failure. It is the queue absorbing pressure
that the bounded consumer cannot process immediately. Operations must decide
whether the resulting queue age is still acceptable.

## 2. Learning Outcomes

After the lesson, you will be able to:

- distinguish concurrency, throughput, backlog, and backpressure;
- calculate an approximate service rate for a Lambda SQS consumer;
- limit one SQS event source mapping with `MaximumConcurrency`;
- distinguish mapping maximum concurrency from function reserved concurrency;
- explain why reserved concurrency is not provisioned concurrency;
- create a deterministic burst without calling an external dependency;
- observe queue depth without competing with the Lambda poller;
- correlate SQS depth, oldest-message age, Lambda concurrency, throttles, and logs;
- reject a mapping limit below the AWS minimum;
- reject reserved concurrency lower than the mapping cap;
- explain when backlog is healthy buffering and when it is an incident signal;
- destroy the disposable lab safely.

Evidence map:

| Claim | Evidence |
|---|---|
| Mapping cap is active | `ScalingConfig.MaximumConcurrency = 2` from AWS CLI |
| Burst was accepted | `send-burst.sh` reports 20 successful entries and no failures |
| Backlog existed | `backlog.tsv` contains non-zero visible or in-flight samples |
| Queue eventually drained | Later sample has `visible = 0` and `in_flight = 0` |
| Function did useful work | CloudWatch Logs contain `work_started` and `work_completed` |
| Source did not exceed its configured cap | Lambda `ConcurrentExecutions` maximum is at or below 2 for this isolated function |
| Normal cap did not cause throttling | Lambda `Throttles` remains zero |
| Unsafe controls are rejected | Terraform negative tests fail at validation or precondition boundaries |

### 2.1. Lesson Terminology

| English term | Plain wording | Precise meaning in this lesson |
|---|---|---|
| `concurrency` | concurrent executions | Number of Lambda invocations currently running |
| `throughput` | processing rate | Work items completed per unit of time |
| `backlog` | queued work | Accepted messages that have not completed processing |
| `backpressure` | bounded downstream pressure | Queue growth caused when arrival rate exceeds service rate |
| `burst` | sudden message spike | Many messages accepted in a short interval |
| `arrival rate` | incoming rate | Messages entering the queue per second |
| `service rate` | processing rate | Messages the consumer can finish per second |
| `event source mapping` | source-to-function mapping | Lambda-managed link that polls SQS and invokes the function |
| `MaximumConcurrency` | source-level cap | Maximum concurrent invocations allowed for one SQS mapping |
| `reserved concurrency` | function-wide reservation and cap | Capacity reserved for one function and unavailable to other functions |
| `provisioned concurrency` | pre-initialized function capacity | Warm execution environments allocated in advance for a cost |
| `provisioned mode` | dedicated event pollers | Paid SQS mapping mode with configured minimum and maximum pollers |
| `throttling` | capacity rejection | Lambda cannot start an invocation because a concurrency limit was reached |
| `in-flight message` | received hidden message | SQS message received by a consumer and hidden by visibility timeout |
| `queue age` | oldest-message waiting time | Age of the oldest message still available for processing |
| `type annotation` | declared type hint | Information about a value's type for Pylance and other Python analyzers |
| `TypedDict` | typed dictionary contract | Description of required keys and value types for a normal Python dictionary |
| `type narrowing` | runtime-backed type refinement | A check after which the analyzer understands the input type more precisely |
| `cast()` | explicit type assertion | Instruction to the analyzer to treat a value as a type without converting it at runtime |

## 3. Mental Model

### 3.1. Concurrency Is Not Throughput

Concurrency is a snapshot:

```text
How many Lambda invocations are running now?
```

Throughput is a rate:

```text
How many messages complete per second or per minute?
```

Two concurrent invocations do not imply two messages per second. If each
invocation processes one message for eight seconds, the approximate service rate is:

```text
service_rate ~= concurrency * batch_size / average_duration
service_rate ~= 2 * 1 / 8
service_rate ~= 0.25 messages/second
```

Twenty messages therefore need approximately:

```text
drain_time ~= message_count / service_rate
drain_time ~= 20 / 0.25
drain_time ~= 80 seconds

Or:

20 messages / 2 concurrently = 10 waves
10 waves × 8 seconds = ~80 seconds
```

This is an estimate, not an SLO. Cold starts, polling, logging, partial failures,
retries, and duration variance change the real result.

### 3.2. Backlog Is Stored Pressure

Let:

```text
arrival_rate > service_rate

arrival_rate = 5 msg/s
service_rate = 3 msg/s
backlog growth ≈ 2 msg/s
```

Then the queue grows:

```text
producer burst
-> SQS accepts messages
-> bounded consumer processes two at a time
-> remaining messages form a backlog
```

What matters is not only **how many**, but also **how long they have been waiting**.

SQS decouples acceptance from completion. Producers can succeed while consumers
fall behind. This is useful buffering, but it moves the operational question to:

```text
How old may a message become before the business result is too late?
```

Queue depth alone has no universal threshold. Ten messages may be severe for a payment
authorization and irrelevant for a nightly report. Age should be tied to a business
latency objective.

### 3.3. Three Different Concurrency Boundaries

| Boundary | Scope | Reserves capacity? | Lab default |
|---|---|---|---:|
| Mapping `MaximumConcurrency` | One SQS event source | No | `2` |
| Function `reserved concurrency` | All sources of one function | Yes | `null` |
| Account concurrency quota | All functions in one Region | Regional quota | Account value |

The effective concurrency is constrained by every applicable boundary:

```text
effective concurrency
= minimum(
    SQS mapping maximum,
    function reserved limit when configured,
    available account concurrency,
    current demand and Lambda scaling behavior
  )
```

Mapping maximum concurrency protects downstream capacity for one source. It does not
reserve capacity, so another function can still consume the unreserved regional pool.

Reserved concurrency has two effects:

```text
reserve capacity for this function
+
cap this function at the same number
```

Conflict example:

```text
mapping limit = 5
reserved concurrency = 2
  - the mapping can potentially request more concurrency
      than the function can provide
  - Throttles may occur
```

Do not set the function reservation below the sum of maximum concurrency values
for its SQS mappings. Lambda can otherwise throttle accepted queue work.

### 3.4. Reserved Is Not Provisioned

These names are easy to confuse:

| Feature | Primary purpose | Pre-warms environments? | Additional charge? |
|---|---|---:|---:|
| Reserved concurrency | Capacity isolation and upper bound | No | No |
| Provisioned concurrency | Predictable startup latency | Yes | Yes |
| SQS provisioned mode | Dedicated event pollers and faster mapping scale | Not function environments | Yes |

So, `reserved concurrency` is about capacity isolation, while `provisioned concurrency` is about
readiness for fast startup.

This lab uses none of the paid provisioned features. It also leaves reserved concurrency
unset because training accounts can have a small quota and Lambda must retain unreserved
capacity for the account.

### 3.5. Maximum Concurrency Is Per Mapping

The Terraform resource contains:

```hcl
scaling_config {
  maximum_concurrency = var.event_source_maximum_concurrency
}
```

For SQS, AWS accepts values from `2` to `1000`. The default lab value is the
minimum, which makes the queue drain visibly.

If two queues map to one function, each mapping can have a different cap:

```text
urgent queue mapping  -> maximum 8
bulk queue mapping    -> maximum 2
same Lambda function  -> total possible demand 10
```

If function reserved concurrency is also configured, it should be at least the
sum of these source caps.

### 3.6. Throttling Is Not Backpressure Control

A mapping cap stops that source from requesting more than its configured
concurrency. This is deliberate flow control.

Normal limiting:

```text
SQS
↓
the mapping allows a maximum of 2
↓
Lambda runs normally
↓
the remaining messages wait in the queue
```

Throttling:

```text
the mapping attempts to invoke Lambda
↓
no concurrency is available
↓
the invocation is rejected
↓
the message remains unacknowledged
```

Throttling means an invocation could not start because another capacity boundary
was reached:

```text
mapping requests invocation
-> function or account has no available concurrency
-> Lambda throttles
-> SQS message remains unacknowledged
-> visibility timeout and retry semantics apply
```

What happens during throttling:

```text
MaximumConcurrency = 5
reserved concurrency = 2
```

The mapping can potentially try to use up to five concurrent invocations, but the function has
already reached its limit of `2`.

Then:

```text
invocation attempt
↓
Lambda cannot start it
↓
Throttles increases
↓
the message is not acknowledged
↓
visibility timeout / retry
```

Design for a clean source cap rather than using throttles as the normal control mechanism.
Monitor `Throttles` because a zero value distinguishes expected backlog from a capacity conflict.

```text
backlog + Throttles = 0
  - controlled backpressure

backlog + Throttles > 0
  - capacity conflict
```

### 3.7. Approximate Metrics Need Correlation

SQS queue attributes are approximate:

| Signal | Interpretation | Limitation |
|---|---|---|
| Visible messages | Work available to consumers | May update with delay |
| Not visible messages | Received messages currently hidden | Not an exact Lambda concurrency metric |
| Oldest message age | Processing latency pressure | CloudWatch granularity and publication delay |
| Lambda concurrent executions | Running invocations | Function-level unless dimensions isolate further |
| Lambda throttles | Capacity rejected invocations | Does not explain which limit caused them |

The lab uses an isolated function with one source, so function concurrency is a reasonable
proxy for this mapping.

Diagnostic table:

```text
visible      — backlog
in_flight    — messages already received
queue age    — delay
concurrency  — running Lambda invocations
throttles    — rejected invocations
logs         — actual execution overlap
```

## 4. Lab Architecture

```text
send-burst.sh
     |
     | 20 work items, work_seconds = 8
     v
+------------------------+
| standard SQS work queue|
| visibility = 95s       |
+-----------+------------+
            |
            | event source mapping
            | BatchSize = 1
            | MaximumConcurrency = 2
            v
+------------------------+
| Lambda bounded worker  |
| timeout = 15s          |
| reserved = unset       |
+-----------+------------+
            |
            +----> structured CloudWatch Logs

repeated failures
     |
     v
+------------------------+
| SQS DLQ                |
+------------------------+
```

The successful burst should not use the DLQ. The DLQ remains because scaling
controls do not replace bounded retry and failure isolation from lesson 82.

## 5. Implementation Walkthrough

### 5.1. Bounded Work Contract

Open:

```text
lab_83/app/lambda_function.py
```

Each body contains:

```json
{
  "task_id": "burst-task-1",
  "work_seconds": 8
}
```

The parser accepts only a numeric value from zero through ten. Python booleans
are rejected explicitly because `bool` is a subclass of `int`.

The delay is needed only for a measurable training experiment. If the function completed
in, for example, 50 ms, the 20 messages could disappear too quickly.

### 5.2. Why This Handler Uses `TypedDict`, `object`, and `cast()`

A Lambda event comes from an external source, so the code cannot promise that it
has the expected dictionary shape before validation. That is why `lambda_handler()`
accepts `event: object`:

```python
def lambda_handler(event: object, context: object) -> BatchResponse:
```

`object` means that a value exists but its precise type is not known yet.
`require_string_keyed_dict()` performs a runtime check and returns
`dict[str, object]` only after that check succeeds:

```python
def require_string_keyed_dict(
    value: object,
    error_message: str,
) -> dict[str, object]:
    if not isinstance(value, dict) or not all(
        isinstance(key, str) for key in value
    ):
        raise MessageContractError(error_message)

    return cast(dict[str, object], value)
```

Two different protection layers are involved:

1. `isinstance()` and the key check are executed by Python and reject invalid input.
2. `cast()` is for the type analyzer only. It does not convert the value and does
   not replace runtime validation.

After JSON parsing, the code knows the exact work-item shape. `TypedDict` describes it:

```python
class WorkItem(TypedDict):
    task_id: str
    work_seconds: float
```

This does not create a new runtime object type or replace the dictionary. At
runtime, `item` remains a normal `dict`:

```python
item: WorkItem = {
    "task_id": "burst-task-1",
    "work_seconds": 8.0,
}
```

The difference appears in the editor: Pylance now knows that `item["task_id"]`
is a string, `item["work_seconds"]` is numeric, and an unknown key is an error.
Likewise, `WorkResult`, `BatchItemFailure`, and `BatchResponse` define the internal
result and the exact Lambda partial batch response contract.

The full sequence is:

```text
untrusted object
-> runtime dictionary and key validation
-> required-field validation
-> TypedDict with a known shape
-> safe processing and useful Pylance feedback
```

Do not confuse these:

```text
object
  - "the type is not known yet"

isinstance()
  - actually checks the data

cast()
  - checks nothing; it only tells the type checker what type to assume

TypedDict
  - describes the structure of a regular dict for the type checker
```

Annotations do not make invalid input safe by themselves. Without the `isinstance()`
checks, the function could still receive a string, `null`, or a dictionary with invalid
fields and fail with `AttributeError`, `KeyError`, or `TypeError`.

### 5.3. Structured Timing Logs

One successful invocation emits:

```text
batch_started
-> work_started
-> work_completed
-> batch_completed
```

```text
request_id -> which specific Lambda invocation
message_id -> which SQS message
task_id    -> which business task
elapsed_ms -> how long the work actually took
```

Overlap example:

```text
12:00:00 request-A work_started
12:00:01 request-B work_started
12:00:08 request-A work_completed
12:00:09 request-B work_completed
```

This makes it immediately clear how concurrency can be identified from the logs.

`request_id`, `message_id`, `task_id`, and `elapsed_ms` allow overlapping
invocations to be distinguished. A global Python counter would not prove total
concurrency because separate execution environments do not share process memory.

### 5.4. Burst Sender

`send-burst.sh` uses `SendMessageBatch` with at most ten entries per API call. It:

```text
get the parameters
-> validate them
-> split COUNT messages into batches of up to 10
-> build JSON for SendMessageBatch
-> send all batches to SQS
-> save the AWS responses
-> count Successful / Failed
-> exit with an error if at least one entry was not sent
```

### 5.5. Non-Destructive Backlog Sampler

There are two ways to inspect the queue:

```text
get queue attributes
  - simply observe the queue state

ReceiveMessage
  - actually receive messages
```

`sample-backlog.sh` calls only `GetQueueAttributes`. It never calls `ReceiveMessage`,
so it does not hide work or compete with Lambda.

What the script does as a whole:

```text
get the parameters
  - validate the interval and number of samples
  - create a TSV file
  - call GetQueueAttributes several times
  - record timestamp + visible + in_flight + delayed
  - wait for the specified interval between samples
```

The TSV columns are:

```text
timestamp  visible  in_flight  delayed
```

Do not interpret `in_flight` as an exact concurrency counter. Use Lambda metrics
and overlapping request IDs for concurrency evidence.

## 6. Local Verification

From the repository root:

```bash
python3 -m unittest discover \
  -s lessons/83-lambda-sqs-scaling-concurrency-backpressure/lab_83/tests -v

bash -n lessons/83-lambda-sqs-scaling-concurrency-backpressure/lab_83/scripts/*.sh
```

Expected result:

```text
Ran 8 tests
OK
```

The tests prove message validation, bounded duration, injected sleep, successful
batch handling, partial failure isolation, and top-level SQS event validation.
They do not prove AWS scaling behavior.

## 7. Terraform Validation and Deployment

Enter the lab:

```bash
cd lessons/83-lambda-sqs-scaling-concurrency-backpressure/lab_83/terraform
cp terraform.tfvars.example terraform.tfvars
```

Run static and native checks:

```bash
terraform init
terraform fmt -check -recursive
terraform validate
terraform test
```

Expected native-test result:

```text
Success! 8 passed, 0 failed.
```

Authenticate:

```bash
export AWS_PROFILE=YOUR_PROFILE
aws sso login --profile "$AWS_PROFILE"
aws sts get-caller-identity
```

Create and review a saved plan:

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
export MAPPING_UUID="$(terraform output -raw event_source_mapping_uuid)"
mkdir -p ../evidence
```

## 8. Verify the Concurrency Contract

Inspect the deployed mapping:

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
BatchSize = 1
MaximumConcurrency = 2
ResponseTypes contains ReportBatchItemFailures
```

Inspect function concurrency separately:

```bash
aws lambda get-function-concurrency \
  --region "$AWS_REGION" \
  --function-name "$FUNCTION_NAME" \
  --output json
```

An empty object is expected because reserved concurrency is intentionally unset.
It does not mean the mapping cap is missing; the controls live on different resources.

## 9. Run the Burst Drill

Now we verify the main behavior of the lab:

```text
20 messages arrive quickly
  - the mapping allows a maximum of 2 invocations
  - a backlog appears
  - then it gradually drains
```

Start the non-destructive sampler in the background:

```bash
../scripts/sample-backlog.sh \
  "$SOURCE_QUEUE_URL" "$AWS_REGION" \
  5 24 ../evidence/backlog.tsv &
export SAMPLER_PID=$!
```

Keep the backlog sampler running in the first terminal.
While it is still running, open a second terminal and send the 20-message burst.

```bash
../scripts/send-burst.sh \
  "$SOURCE_QUEUE_URL" "$AWS_REGION" \
  20 8 ../evidence/burst.json
```

Expected sender summary:

```text
requested=20 successful=20 failed=0
```

Wait for all samples:

```bash
wait "$SAMPLER_PID"
column -t -s $'\t' ../evidence/backlog.tsv
```

Expected shape, not exact numbers:

```text
timestamp             visible  in_flight  delayed
...                   0        0          0
...                   18       2          0
...                   16       2          0
...                   ...      ...        0
...                   0        0          0
```

The first sample can occur before the burst. SQS values are approximate, and
polling timing varies. The important sequence is non-zero backlog followed by a
drained queue.

## 10. Correlate Logs and Metrics

Inspect structured logs:

```bash
aws logs tail "/aws/lambda/${FUNCTION_NAME}" \
  --region "$AWS_REGION" \
  --since 15m \
  --format short | grep -E 'work_started|work_completed'
```

Different overlapping `request_id` values demonstrate concurrent invocations.
Repeated `task_id` values would indicate delivery retry and require the lesson 81
idempotency boundary around real side effects.

Query Lambda concurrency after CloudWatch publishes the datapoints:

```bash
export METRIC_END="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
export METRIC_START="$(date -u -d '20 minutes ago' +%Y-%m-%dT%H:%M:%SZ)"

aws cloudwatch get-metric-statistics \
  --region "$AWS_REGION" \
  --namespace AWS/Lambda \
  --metric-name ConcurrentExecutions \
  --dimensions Name=FunctionName,Value="$FUNCTION_NAME" \
  --start-time "$METRIC_START" \
  --end-time "$METRIC_END" \
  --period 60 \
  --statistics Maximum \
  --query 'sort_by(Datapoints,&Timestamp)[].[Timestamp,Maximum]' \
  --output table
```

For this isolated function and source, the maximum should not exceed two.
A missing datapoint usually means metric publication has not completed; wait and retry.

So now we have two complementary pieces of evidence:

```text
Logs
  - overlapping invocations actually occurred
  - concurrency reached at least 2

CloudWatch ConcurrentExecutions
  - the function maximum = 2
  - it never exceeded the mapping limit
```

Check throttles:

```bash
aws cloudwatch get-metric-statistics \
  --region "$AWS_REGION" \
  --namespace AWS/Lambda \
  --metric-name Throttles \
  --dimensions Name=FunctionName,Value="$FUNCTION_NAME" \
  --start-time "$METRIC_START" \
  --end-time "$METRIC_END" \
  --period 60 \
  --statistics Sum \
  --query 'sort_by(Datapoints,&Timestamp)[].[Timestamp,Sum]' \
  --output table
```

Expected normal result is `0` or no throttle datapoints.

## 11. Negative and Capacity Drills

### Drill 1. Reject an AWS-Invalid Mapping Limit

```bash
terraform plan \
  -var='event_source_maximum_concurrency=1'
```

Mental model:

```text
the user sets 1
↓
Terraform validation checks the variable
↓
the value violates the contract
↓
plan stops
↓
AWS is not called at all
```

Expected result:

```text
event_source_maximum_concurrency must be an integer between 2 and 1000.
```

This fails before an AWS API request.

### Drill 2. Reject a Reservation Below the Source Cap

```bash
terraform plan \
  -var='event_source_maximum_concurrency=3' \
  -var='function_reserved_concurrency=2'
```

Architecturally, this creates a conflict:

```text
event source mapping: maximum 3
            ↓
Lambda function: maximum 2
            ↓
the third invocation may have no available capacity
            ↓
throttling may occur
```

Expected result:

```text
function_reserved_concurrency must be at least event_source_maximum_concurrency.
```

The precondition prevents a known throttling conflict.

### Drill 3. Review a Matching Reservation Without Applying It

```bash
terraform plan \
  -var='event_source_maximum_concurrency=2' \
  -var='function_reserved_concurrency=2'
```

The plan is structurally valid, but do not apply it. Lesson 78 showed that a low
account quota may reject reserved concurrency because Lambda must preserve a minimum
unreserved pool. A valid Terraform relationship does not prove account quota availability.

### Drill 4. Estimate a Faster Configuration

Do not apply first. Calculate:

```text
concurrency = 4
batch_size = 1
average_duration = 8 seconds

service_rate ~= 4 * 1 / 8 = 0.5 messages/second
20-message drain time ~= 40 seconds
instead of the previous ~80 seconds
```

Then inspect the plan:

```bash
terraform plan \
  -var='event_source_maximum_concurrency=4'
```

Before applying such a change in production, verify downstream capacity, account quota,
cost, queue-age objective, and rollback procedure.

## 12. Troubleshooting

### Backlog Never Appears

Possible causes:

1. `work_seconds` is too small.
2. Too few messages were sent.
3. `MaximumConcurrency` is higher than expected.
4. Sampling started after the queue drained.

Verify the mapping and repeat with `20 8`.

### Queue Does Not Drain

Check:

```bash
aws lambda get-event-source-mapping \
  --region "$AWS_REGION" \
  --uuid "$MAPPING_UUID" \
  --query '[State,StateTransitionReason,LastProcessingResult]' \
  --output table
```

```text
State
  - is the mapping Enabled?

StateTransitionReason
  - why did it enter its current state?

LastProcessingResult
  - what happened during the latest processing attempts?
```

Then inspect function logs, `Errors`, `Throttles`, source-queue age, and DLQ depth.
Do not call `aws sqs receive-message` on the source queue while diagnosing; that changes
message visibility and competes with Lambda.

### In-Flight Count Is Not Exactly Two

SQS attributes are approximate and an event source mapping can have internal
polling behavior. `ApproximateNumberOfMessagesNotVisible` is not the authoritative
Lambda concurrency metric. Correlate it with `ConcurrentExecutions` and logs.

### `PutFunctionConcurrency` Is Rejected

If you enabled reserved concurrency, the account may not have enough quota while
preserving its required unreserved pool. Return the variable to `null` unless the
reservation is required and the quota has been reviewed.

### Throttles Are Non-Zero

Check all boundaries:

```text
MaximumConcurrency mapping
function reserved concurrency
other sources of the same function
regional unreserved concurrency
account concurrency quota
```

```text
backlog + Throttles = 0 -> expected consumption limiting

backlog + Throttles > 0 -> capacity conflict / quota pressure
```

### CloudWatch Metrics Are Empty

CloudWatch publication is delayed. Confirm logs first, wait several minutes, and
repeat the metric query with a wider time range.

### Diagnostic Sequence

```text
queue stuck
→ mapping state
→ logs/errors
→ throttles
→ queue age
→ DLQ
```

## 13. Cost and Operational Boundaries

The lab creates:

- one Lambda function;
- one standard source queue and one DLQ;
- one event source mapping;
- one IAM role and inline policy;
- one CloudWatch log group;
- three CloudWatch alarms.

An exercise with twenty messages, 128 MB of memory, and 8 seconds per message is a
small experiment, but it is not necessarily free. The cost comes not only from Lambda
execution time, but also from SQS requests, logs, metrics, and alarms.

Production capacity review should include:

```text
peak arrival rate
average and p95 duration
batch size and payload size
downstream connection or API limits
queue-age SLO
retry and DLQ behavior
regional Lambda concurrency budget
cost per completed business action
```

Production model:

```text
peak arrival rate
  - required service rate
  - required concurrency
  - check downstream capacity + quota + cost
  - check queue-age SLO
```

## 14. Completion Checklist

The lesson is complete when:

- 8 Python tests pass;
- 8 Terraform native tests pass;
- mapping state is `Enabled`;
- mapping maximum concurrency is `2`;
- reserved concurrency is absent by default;
- a 20-message burst is accepted without failed entries;
- backlog samples show growth and later drainage;
- logs contain multiple request IDs and completed task IDs;
- Lambda concurrency does not exceed the source cap in this isolated lab;
- throttles remain zero during normal bounded processing;
- both unsafe Terraform configurations are rejected;
- you can explain why depth and age require a business objective.

## 15. Cleanup

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

## 16. Final Model

Remember:

1. Concurrency is simultaneous work; throughput is completed work per time.
2. A queue stores pressure when arrival rate exceeds service rate.
3. Mapping maximum concurrency limits one SQS source and reserves no capacity.
4. Reserved concurrency applies to the entire function and consumes account quota.
5. Reserved concurrency does not pre-warm environments.
6. Throttling is a capacity rejection, not a normal flow-control mechanism.
7. Queue depth shows volume; oldest-message age shows latency pressure.
8. Approximate SQS attributes require correlation with Lambda metrics and logs.
9. A higher cap is safe only when downstream capacity, quota, cost, and SLO agree.
10. Scaling controls do not replace idempotency or partial batch failure handling.

## 17. Official References

- [Configuring scaling behavior for SQS event source mappings](https://docs.aws.amazon.com/lambda/latest/dg/services-sqs-scaling.html)
- [Creating and configuring an SQS event source mapping](https://docs.aws.amazon.com/lambda/latest/dg/services-sqs-configure.html)
- [Understanding Lambda function scaling](https://docs.aws.amazon.com/lambda/latest/dg/lambda-concurrency.html)
- [Lambda scaling behavior](https://docs.aws.amazon.com/lambda/latest/dg/scaling-behavior.html)
- [How Lambda processes queue-based event sources](https://docs.aws.amazon.com/lambda/latest/dg/invocation-eventsourcemapping.html)
