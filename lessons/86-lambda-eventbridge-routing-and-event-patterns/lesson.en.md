# Lesson 86: Lambda EventBridge Routing and Event Patterns

## 1. Why This Lesson Exists

Lesson 85 used SNS to copy one publication into independent SQS consumer branches.
Its billing subscription filtered on one SNS message attribute. That model works
well when a publisher knows the topic and subscribers need simple fan-out.

This lesson introduces Amazon EventBridge as a routing plane. A publisher sends
a structured event envelope to a `custom event` bus. Rules inspect metadata and
fields inside `detail`, then independently deliver matching events to targets.

The important change is not merely replacing one AWS service with another:

```text
SNS lesson:         publish notification -> subscription filtering
EventBridge lesson: publish event envelope -> content-based routing rules
```

For example, an event such as “an order for 150 was created” may be relevant to:

- `audit` — because it is an order event;
- the high-value order processor — because the amount is at least 100.

The rules make decisions independently. A single order can be routed to both branches.

The lab deliberately keeps SQS between EventBridge and Lambda:

```text
publisher -> EventBridge rule -> SQS -> Lambda
```

That buffer preserves the queue backlog, concurrency controls, retries, and failure
isolation learned in lessons 82–85. It also exposes two failure planes that must
not be confused:

```text
EventBridge → SQS    delivery failure → delivery DLQ
SQS → Lambda         processing failure → processing DLQ
```

If EventBridge does not have permission to write the message to SQS, Lambda will never see it.

If the message has already reached SQS but the handler fails, that is a different failure mode
with a different recovery procedure.

Those failures require different DLQs, metrics, ownership, and recovery actions.

## 2. Learning Outcomes

After completing the lesson, you should be able to:

- explain when EventBridge routing is more appropriate than SNS fan-out;
- identify the EventBridge envelope and the business payload inside `detail`;
- write and test exact and numeric event patterns;
- predict whether an event matches zero, one, or multiple rules;
- publish custom events and inspect per-entry `PutEvents` failures;
- authorize EventBridge to send only from an expected rule to an SQS queue;
- distinguish a target delivery DLQ from an SQS processing DLQ;
- preserve partial batch responses and per-branch concurrency limits;
- diagnose accepted-but-unmatched events;
- restore Terraform-managed queue policy after a controlled drift drill.

The main new skill is determining at which stage the event stopped:

```text
PutEvents accepted
 - event pattern matched
 - EventBridge delivered to SQS
 - SQS stored the message
 - Lambda processed the message
 - business result is correct
```

### 2.1. Lesson Terminology

| Term | Meaning in this lesson |
|---|---|
| custom event bus | Named EventBridge bus owned by this lab |
| event envelope | EventBridge metadata plus the nested `detail` payload |
| `source` | Stable identifier for the event producer/domain |
| `detail-type` | Human-readable event category used by rules |
| `detail` | JSON business payload carried by the envelope |
| event pattern | Declarative JSON criteria attached to a rule |
| content-based routing | Choosing targets from values inside the event |
| target | Resource invoked when a rule matches |
| delivery DLQ | Queue for events EventBridge could not deliver to a target |
| processing DLQ | Queue for messages a Lambda consumer repeatedly failed to process |
| partial batch response | Lambda response that returns only failed SQS message IDs |

## 3. Mental Model

### 3.1. EventBridge and SNS Solve Overlapping but Different Problems

Both services can fan one input out to multiple destinations, but their primary
models differ:

```text
SNS:         topic → subscription with a filter → receiver
EventBridge: bus   → rule with an event pattern → target
```

| Question | SNS | EventBridge |
|---|---|---|
| Publisher sends to | topic | event bus |
| Routing unit | subscription | rule plus target |
| Typical contract | message plus attributes | standard envelope plus `detail` |
| Filtering | subscription filter policy | event pattern |
| Content operators | useful but narrower | rich exact, numeric, prefix, exists, and other operators |
| Common use | notifications and pub/sub fan-out | application and AWS event routing |

In SNS, we created a queue subscription to a topic. In EventBridge, we create a rule on
the event bus and assign a target to it separately. A single rule can have multiple targets.

This is not a rule that EventBridge is always better. Choose from delivery semantics,
integrations, contract ownership, throughput, cost, and operational needs rather
than from service popularity.

EventBridge works with a common event envelope. A rule can evaluate at the same time:

- who sent the event — `source`;
- what happened — `detail-type`;
- business conditions — fields inside `detail`.

For example: “an event from the order service, the type is order creation, and the
amount is at least 100.”

### 3.2. The Envelope Is Part of the Contract

A custom event delivered to SQS looks conceptually like this:

```json
{
  "version": "0",
  "id": "generated-by-eventbridge",
  "detail-type": "Order Created",
  "source": "com.devops.orders",
  "account": "123456789012",
  "time": "2026-09-06T12:00:00Z",
  "region": "eu-west-1",
  "resources": [],
  "detail": {
    "event_id": "event-001",
    "order_id": "order-001",
    "amount": 150,
    "fail_consumer": null
  }
}
```

The top-level `id` identifies the EventBridge event. The lab's `detail.event_id`
is a business identifier chosen by the producer. They solve different problems.

When the same business event is published again, EventBridge may assign a new `id`,
while the producer keeps the same `detail.event_id`. Therefore, for correlating business
observations, we use `detail.event_id`.

For routing, we are primarily interested in three fields:

- `source` — the event source. `com.devops.orders` is an agreed identifier string, not a network address.
- `detail-type` — the category: here, `Order Created`.
- `detail` — the business data. The amount is located at `detail.amount`, not at the top level.

The handler extracts them like this:

```python
envelope = json.loads(record["body"])

source = envelope["source"]
event_type = envelope["detail-type"]
business_event = envelope["detail"]
amount = business_event["amount"]
```

The envelope describes the origin and category of the event, while `detail` contains
its business meaning. Rules can evaluate both parts.

### 3.3. A Pattern Declares Only What Must Match

The audit rule uses:

```json
{
  "source": ["com.devops.orders"],
  "detail-type": ["Order Created", "Order Refunded"]
}
```

Fields omitted from the pattern do not restrict matching. This rule does not
care about `detail.amount`.

The high-value rule adds a nested numeric condition:

```json
{
  "source": ["com.devops.orders"],
  "detail-type": ["Order Created"],
  "detail": {
    "amount": [
      {
        "numeric": [">=", 100]
      }
    ]
  }
}
```

`150` is a JSON number. `"150"` is a string and does not satisfy this numeric
operator. Event contracts include types, not only field names.

### 3.4. Rules Evaluate Independently

EventBridge does not choose the first matching rule. Every rule evaluates the
same event independently, with source = com.devops.orders:

| Event | Audit rule | High-value rule |
|---|---:|---:|
| Order Created, amount `150` | match | match |
| Order Created, amount `25` | match | no match |
| Order Refunded, amount `150` | match | no match |
| Order Created from wrong `source` | no match | no match |

Therefore, a single event may match zero, one, or multiple rules; delivery to their
targets is verified separately. If the event does not match any rule, EventBridge
does not have to treat that as an error.

It is important to distinguish between:

```text
PutEvents accepted → the event was accepted
event pattern matched → a specific rule matched
```

### 3.5. Delivery Failure and Processing Failure Are Different

The complete branch is:

```text
EventBridge rule
  -> source SQS
     -> Lambda
```

The target delivery DLQ belongs to the first arrow:

```text
EventBridge --cannot send--> source SQS
           -> delivery DLQ
```

The processing DLQ belongs after SQS accepted the message:

```text
source SQS -> Lambda fails repeatedly
           -> processing DLQ
```

A message in the delivery DLQ never reached the source queue. A message in the
processing DLQ reached the queue and exhausted `maxReceiveCount`. Putting both
failure classes in one queue would erase critical diagnostic context.

`Delivery DLQ` applies to EventBridge delivery to the target queue.

For example, the rule matched, but the queue policy does not allow `events.amazonaws.com`
to perform `sqs:SendMessage`. The message never reached the source SQS queue, so Lambda
never received it. With a correctly configured `delivery DLQ`, EventBridge can store
the undelivered event there together with information about the delivery error.

`Processing DLQ` applies to processing an SQS message that has already been accepted.

For example, the message was delivered successfully, but Lambda triggers the intentional
lab error every time. After repeated receives, SQS moves the message to the `processing DLQ`
according to the `redrive_policy`.

The recovery procedures are also different:

- For a delivery failure, first fix the delivery path: queue permissions and target
configuration. Changing the Lambda code will not help here.
- For a processing failure, fix the handler or the data, then decide how to reprocess
the message.

We examine evidence for the specific stage: rule matching, delivery, and processing records.

### 3.6. `PutEvents` Success Requires More Than Exit Code Zero

`PutEvents` processes entries independently. The API can return HTTP success
while one entry contains `ErrorCode` and `ErrorMessage`. A correct publisher
checks `FailedEntryCount`, not only the AWS CLI exit code.

Example response:

```json
{
  "FailedEntryCount": 1,
  "Entries": [
    {
      "EventId": "accepted-event-id"
    },
    {
      "ErrorCode": "InternalFailure",
      "ErrorMessage": "Internal Service Failure"
    }
  ]
}
```

There is another trap: sending to a custom bus name that does not exist can
still return success while no rule receives the event. The lab publisher first
runs `describe-event-bus`, then checks `FailedEntryCount` after `put-events`.

Even after those checks, publication proves only ingestion. It does not prove:

- that a rule matched;
- that EventBridge delivered to SQS;
- that Lambda processed the event;
- that the business side effect completed.

### 3.7. Standard SQS Partial Failures Still Apply

Both branches use standard queues. Their handlers continue after one record
fails and return only failed `messageId` values in `batchItemFailures`.

That behavior differs from lesson 84's FIFO barrier, where the handler stopped after
the first failure to preserve message-group order. EventBridge changes the routing
before the queue, but not the batch-processing behavior after the queue.

Here, the exact SQS `messageId` is required. Neither the EventBridge `id` nor the 
business field `detail.event_id` can be used as `itemIdentifier`.

With `ReportBatchItemFailures` enabled, successfully processed records are deleted,while
the failed record remains for retry. If the handler raises an exception for the entire
invocation, no partial response is returned and the whole batch is considered unsuccessful.

These retries belong to the Lambda processing stage and, after the retry attempts are
exhausted, lead to the `processing DLQ`. The EventBridge `delivery DLQ` does not
participate in them.

## 4. Lab Architecture

```text
put-event.sh
    │
    ▼
custom EventBridge bus
  |
  +-- audit rule
  |     source=com.devops.orders
  |     detail-type=Order Created OR Order Refunded
  |       |
  |       +--> audit source SQS --> audit Lambda
  |       |                         |
  |       |                         +--> SQS redrive -> processing DLQ audit
  |       |
  |       +-- delivery failure --> audit delivery DLQ
  |
  +-- high-value rule
        source=com.devops.orders
        detail-type=Order Created
        detail.amount >= 100
          |
          +--> high-value source SQS --> high-value Lambda
          |                              |
          |                              +--> SQS redrive -> processing DLQ high-value
          |
          +-- delivery failure --> high-value delivery DLQ
```

Rule conditions:

- `Audit`: `source = com.devops.orders`, with event type `Order Created` or `Order Refunded`.
- `High-value`: the same source, only `Order Created`, with numeric `detail.amount >= 100`.

Each branch has its own:

- EventBridge rule and target;
- source queue and restrictive queue policy;
- target delivery DLQ;
- Lambda function, log group, and execution role;
- event source mapping and concurrency cap;
- SQS processing DLQ;
- backlog, delivery-failure, and DLQ alarms.

## 5. Implementation Walkthrough

### Event Bus, Rules, and Targets

In `eventbridge.tf`, three types of resources are responsible for three different tasks.

#### Event bus — where we publish:

```hcl
resource "aws_cloudwatch_event_bus" "orders" {
  name = local.event_bus_name
}
```

#### Rule — which events match:

```hcl
resource "aws_cloudwatch_event_rule" "route" {
  for_each = local.event_patterns

  name           = local.rule_names[each.key]
  event_bus_name = aws_cloudwatch_event_bus.orders.name
  event_pattern  = each.value
}
```

`local.event_patterns` contains two keys: `audit` and `high_value`.

Their values are JSON patterns generated with `jsonencode` in `locals.tf`.

#### Target — where to deliver the matched event:

```hcl
event_bus_name = aws_cloudwatch_event_bus.orders.name
rule           = aws_cloudwatch_event_rule.route[each.key].name
arn            = aws_sqs_queue.source[each.key].arn
```

The same `each.key` links the rule and queue of the same branch. `target_id` identifies
the target within the rule, while `arn` specifies the actual destination address.

Each target has:

```hcl
retry_policy {
  maximum_event_age_in_seconds = var.target_maximum_event_age_seconds
  maximum_retry_attempts       = var.target_maximum_retry_attempts
}

dead_letter_config {
  arn = aws_sqs_queue.delivery_dead_letter[each.key].arn
}
```

`depends_on` requires the source queue policies and delivery DLQ policies to be
created before the targets are registered. We will examine queue authorization
in the next section.

The lab has two separate retry mechanisms:

1. EventBridge could not deliver the event to SQS.

The target `retry_policy` applies:

```text
EventBridge → SQS
            → delivery failure
```

Up to 10 retry attempts are configured, and the event age is limited to 3600 seconds.
After delivery attempts stop, the event is sent to the delivery DLQ if its configuration
allows it.

2. SQS has already received the message, but Lambda cannot process it successfully.

The source queue `maxReceiveCount` applies:

```text
SQS → Lambda
    → processing failure
```

This parameter limits the number of times the message can be received before it is
moved to the processing DLQ.

Therefore, increasing EventBridge `maximum_retry_attempts` does not give Lambda
additional processing attempts.

And increasing SQS `maxReceiveCount` does not help EventBridge deliver the event to the queue.

### Queue Authorization

`terraform/queues.tf` allows `sqs:SendMessage` only when `aws:SourceArn` equals the
ARN of the corresponding EventBridge rule. An explicit deny prevents messages from
being sent directly to the queue while bypassing the routing path.

Do not confuse two different `source` values:

```text
source in the event -> com.devops.orders -> checked by the event pattern
aws:SourceArn       -> rule ARN          -> checked by the queue policy
```

`source` is data provided by the sender.
`aws:SourceArn` is part of the AWS request context for the queue.
The event field does not replace the authorization check.

The additional `DenySendOutsideExpectedRule` blocks direct `SendMessage` calls
and delivery through another rule. `DenyInsecureTransport` blocks insecure transport.

Each source queue moves failed messages only to its own processing DLQ. Each
`EventBridge` target points to a separate delivery DLQ. Their purposes are already
visible from the resource names.

The `delivery DLQ` requires a separate `policy`. In the code, it also allows `EventBridge`
to send messages only from the corresponding rule. Permission to write to the source SQS
queue does not automatically grant permission to write to the `delivery DLQ`.

The `processing DLQ` uses a different mechanism: `redrive_allow_policy` with `byQueue`
restricts message redrive to the specific source SQS queue. It does not require permission
for `EventBridge`.

### Lambda Consumers

Both functions use `app/lambda_function.py`, but `CONSUMER_NAME` selects the
branch. `EXPECTED_EVENT_SOURCE` is also passed at runtime so the consumer checks
the producer identity even after routing.

The environment variables differ:

```text
CONSUMER_NAME         → audit or high_value
EXPECTED_EVENT_SOURCE → com.devops.orders
```

The new part of the processing logic is validation of the EventBridge envelope
inside the SQS body.

`parse_record()` validates:

- a non-empty EventBridge `id`;
- that `source` matches `EXPECTED_EVENT_SOURCE`;
- `detail-type`: `Order Created` or `Order Refunded`;
- a `detail` object with non-empty `event_id` and `order_id`;
- a numeric, non-negative `amount`;
- `fail_consumer`: `null`, `audit`, or `high_value`.

The routing rule does not replace contract validation. For example, the `audit`
pattern does not validate the amount, but Lambda will reject `"amount": "150"`
because it is a string.

At the same time, the handler does not re-check the high-value order threshold.
The `amount >= 100` decision belongs to the EventBridge rule; the shared Lambda
code accepts any valid non-negative amount.

`process_event()` either raises the intentional lab error for the selected branc
or returns a result:

```python
{
    "event_id": event["event_id"],
    "event_type": event["event_type"],
    "consumer_name": consumer_name,
    "result_id": "...",
    "status": "completed",
}
```

The handler validates the transport ID before business processing, parses the
EventBridge envelope from the SQS body, validates `detail`, logs structured events,
and returns standard-queue partial failures.

### Publisher

`put-event.sh` converts command-line parameters into a single `PutEvents` request.

**The request format differs from the event that Lambda receives**:

| In the `PutEvents` request          | In the delivered event                                               |
| ----------------------------------- | -------------------------------------------------------------------- |
| `Source`                            | `source`                                                             |
| `DetailType`                        | `detail-type`                                                        |
| `Detail` — a string containing JSON | `detail` — a JSON object                                             |
| `EventBusName`                      | selects the event bus; it does not become a field with the same name |

The script converts the short input:

```text
order.created  → Order Created

order.refunded → Order Refunded
```

The business data is built with `jq`. For the amount, it uses:

```bash
--argjson amount "$amount"
```

Therefore, `150` is placed into `detail` as a number, not as the string `"150"`.

The entire `detail` object is then encoded as a string for the API:

```jq
Detail: ($detail[0] | tojson)
```

This does not convert the amount inside the object into a string; the entire
object is serialized.

When EventBridge delivers the event, `detail` will again be an object with a
numeric `amount`.

The script works in the following sequence:

1. Validates the arguments.
2. Uses `describe-event-bus` to verify that the event bus exists.
3. Builds the request and calls `put-events`.
4. Saves the publication data and the AWS response to an evidence file.
5. Checks `FailedEntryCount`; if it is non-zero, the script exits with an error.

The evidence is saved **before checking for individual entry failures**, so a
rejected publication can still be investigated.

A successful run proves only **PutEvents accepted**. Rule matching and downstream
processing are verified separately. Do not run the script yet.

## 6. Local Verification

From the repository root:

```bash
python3 -m unittest discover \
  -s lessons/86-lambda-eventbridge-routing-and-event-patterns/lab_86/tests -v

bash -n \
  lessons/86-lambda-eventbridge-routing-and-event-patterns/lab_86/scripts/put-event.sh

shellcheck \
  lessons/86-lambda-eventbridge-routing-and-event-patterns/lab_86/scripts/put-event.sh

find lessons/86-lambda-eventbridge-routing-and-event-patterns/lab_86 \
  -type f -name '*.json' -print0 | xargs -0 -n1 jq empty
```

Expected Python result:

```text
Ran 9 tests
OK
```

Then validate the infrastructure contract:

```bash
cd lessons/86-lambda-eventbridge-routing-and-event-patterns/lab_86/terraform
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform fmt -check -recursive
terraform validate
terraform test
```

Expected native-test result:

```text
Success! 12 passed, 0 failed.
```

## 7. Terraform Deployment

Authenticate explicitly:

```bash
export AWS_PROFILE=YOUR_PROFILE
export AWS_REGION=eu-west-1

aws sso login --profile "$AWS_PROFILE"
aws sts get-caller-identity
```

Review a saved plan before applying it:

```bash
terraform plan -out=tfplan
terraform show -no-color tfplan | less
terraform apply tfplan
```

Export the runtime identifiers:

```bash
export EVENT_BUS_NAME="$(terraform output -raw event_bus_name)"
export EVENT_SOURCE="$(terraform output -raw event_source)"

export AUDIT_RULE="$(terraform output -json rule_names | jq -r '.audit')"
export HIGH_VALUE_RULE="$(terraform output -json rule_names | jq -r '.high_value')"

export AUDIT_FUNCTION="$(terraform output -json function_names | jq -r '.audit')"
export HIGH_VALUE_FUNCTION="$(terraform output -json function_names | jq -r '.high_value')"

export AUDIT_SOURCE_QUEUE_URL="$(terraform output -json source_queue_urls | jq -r '.audit')"
export HIGH_VALUE_SOURCE_QUEUE_URL="$(terraform output -json source_queue_urls | jq -r '.high_value')"

export AUDIT_PROCESSING_DLQ_URL="$(terraform output -json processing_dead_letter_queue_urls | jq -r '.audit')"
export HIGH_VALUE_PROCESSING_DLQ_URL="$(terraform output -json processing_dead_letter_queue_urls | jq -r '.high_value')"

export AUDIT_DELIVERY_DLQ_URL="$(terraform output -json delivery_dead_letter_queue_urls | jq -r '.audit')"
export HIGH_VALUE_DELIVERY_DLQ_URL="$(terraform output -json delivery_dead_letter_queue_urls | jq -r '.high_value')"
```

## 8. Verify the Infrastructure Contract

Inspect the custom bus and rules:

```bash
aws events describe-event-bus \
  --name "$EVENT_BUS_NAME" \
  --region "$AWS_REGION"

aws events list-rules \
  --event-bus-name "$EVENT_BUS_NAME" \
  --region "$AWS_REGION" \
  --query 'Rules[].{Name:Name,State:State,Pattern:EventPattern}'
```

An object with the fields `Name` and `Arn` is expected. `Name` must match `$EVENT_BUS_NAME`.

Two rules are expected:

- `audit` in the `ENABLED` state, with `source = com.devops.orders` and two `detail-type` values;
- `high-value` in the `ENABLED` state, additionally with `detail.amount >= 100`.

The output proves:

- the custom bus `lab86-dev-orders-bus` exists in `eu-west-1`;
- both rules are enabled;
- `audit` accepts `Order Created` and `Order Refunded`;
- `high-value` accepts only `Order Created` events with numeric `detail.amount >= 100`.

Inspect each target's retry and DLQ settings:

```bash
for RULE_NAME in "$AUDIT_RULE" "$HIGH_VALUE_RULE"; do
  printf '\nRule: %s\n' "$RULE_NAME"

  aws events list-targets-by-rule \
    --event-bus-name "$EVENT_BUS_NAME" \
    --rule "$RULE_NAME" \
    --region "$AWS_REGION" \
    --query 'Targets[].{Id:Id,Arn:Arn,Retry:RetryPolicy,DLQ:DeadLetterConfig}' \
    --output json
done
```

For each rule, one target is expected:

- `Arn` — the ARN of the corresponding source SQS queue;
- `MaximumEventAgeInSeconds` — 3600;
- `MaximumRetryAttempts` — 10;
- `DeadLetterConfig.Arn` — the ARN of the delivery DLQ for the same branch.


Inspect the source queue's `redrive policy` and resource policy:

```bash
aws sqs get-queue-attributes \
  --queue-url "$HIGH_VALUE_SOURCE_QUEUE_URL" \
  --region "$AWS_REGION" \
  --attribute-names QueueArn RedrivePolicy Policy \
  --output json |
jq '{
  QueueArn: .Attributes.QueueArn,
  RedrivePolicy: (.Attributes.RedrivePolicy | fromjson),
  Policy: (.Attributes.Policy | fromjson)
}'
```

Expected:

- `QueueArn` ends with `lab86-dev-high-value-events`;
- `RedrivePolicy.deadLetterTargetArn` points to `...high-value-events-processing-dlq`;
- `maxReceiveCount` matches the Terraform configuration;
- `AllowExpectedRuleToSend` allows `events.amazonaws.com`;
- its `aws:SourceArn` points to `lab86-dev-high-value-route`;
- `DenySendOutsideExpectedRule` and `DenyInsecureTransport` are present.

Confirm that the processing and delivery DLQ URLs are different:

```bash
printf 'Processing DLQ: %s\nDelivery DLQ:   %s\n' \
  "$HIGH_VALUE_PROCESSING_DLQ_URL" \
  "$HIGH_VALUE_DELIVERY_DLQ_URL"

test "$HIGH_VALUE_PROCESSING_DLQ_URL" != "$HIGH_VALUE_DELIVERY_DLQ_URL"
printf 'exit_code=%s\n' "$?"
```

Expected exit code: `exit_code=0`.

## 9. Test Event Patterns Before Publishing

`test-event-pattern` sends the pattern and a test event to AWS to check
whether they match, but it does not publish the event to the event bus.

```bash
LAB_ROOT="$(cd .. && pwd)"

aws events test-event-pattern \
  --event-pattern "file://$LAB_ROOT/patterns/audit.json" \
  --event "file://$LAB_ROOT/events/order-created-high-value.json" \
  --region "$AWS_REGION"

aws events test-event-pattern \
  --event-pattern "file://$LAB_ROOT/patterns/high-value.json" \
  --event "file://$LAB_ROOT/events/order-created-high-value.json" \
  --region "$AWS_REGION"
```

Both commands should return:

```json
{
  "Result": true
}
```

Reason:

- `audit` matches by `source` and `detail-type`;
- `high-value` additionally matches the numeric condition `amount >= 100` because
the amount is `150`.

Now build the complete routing matrix:

```bash
for event_file in \
  order-created-high-value.json \
  order-created-low-value.json \
  order-refunded.json \
  wrong-source.json; do

  printf '\n%s\n' "$event_file"

  for pattern in audit high-value; do
    result="$(aws events test-event-pattern \
      --event-pattern "file://$LAB_ROOT/patterns/$pattern.json" \
      --event "file://$LAB_ROOT/events/$event_file" \
      --region "$AWS_REGION" \
      --query Result \
      --output text)"

    printf '  %-10s %s\n' "$pattern" "$result"
  done
done
```

Expected matrix:

```text
order-created-high-value.json
  audit      True
  high-value True

order-created-low-value.json
  audit      True
  high-value False

order-refunded.json
  audit      True
  high-value False

wrong-source.json
  audit      False
  high-value False
```

It verifies:

- independent matching of the two rules;
- the numeric threshold;
- the `detail-type` restriction;
- the required `source` match;
- the normal case where zero rules match.

This deterministic pattern test is stronger than inferring routing only from
the temporary absence of a log line.

## 10. Runtime Routing Drills

Create unique identifiers:

```bash
RUN_ID="$(date -u +%Y%m%dT%H%M%S)-$RANDOM"

mkdir -p ../evidence
```

### Drill 1: One Event Matches Both Rules

Publish a high-value created order:

```bash
EVENT_ID="high-$RUN_ID"

../scripts/put-event.sh \
  "$EVENT_BUS_NAME" "$AWS_REGION" "$EVENT_SOURCE" \
  "$EVENT_ID" order.created "order-$RUN_ID" 150 - \
  "../evidence/$EVENT_ID.json"
```

Check only the acceptance result:

```bash
jq '{
  EventId: .detail.event_id,
  Amount: .detail.amount,
  FailedEntryCount: .put_events_response.FailedEntryCount,
  EventBridgeId: .put_events_response.Entries[0].EventId
}' "../evidence/$EVENT_ID.json"
```

Expected:

- `EventId` starts with `high-`;
- `Amount` is the number `150`;
- `FailedEntryCount` equals `0`;
- `EventBridgeId` contains a generated identifier.

Inspect both consumers:

```bash
aws logs tail "/aws/lambda/$AUDIT_FUNCTION" \
  --since 5m --region "$AWS_REGION" --format short | grep -F "$EVENT_ID"

aws logs tail "/aws/lambda/$HIGH_VALUE_FUNCTION" \
  --since 5m --region "$AWS_REGION" --format short | grep -F "$EVENT_ID"
```

After that, search for the event locally:

```bash
rg -F "$EVENT_ID" \
  "../evidence/$EVENT_ID-audit.log" \
  "../evidence/$EVENT_ID-high-value.log"
```

Both branches should log `routed_event_completed` for the same business event.
Their SQS `messageId` and generated `result_id` values may differ.

The same `event_id` correlates a single business event. Different `message_id` values
prove that the SQS copies are independent; different `request_id` values show independent
Lambda invocations; and different `result_id` values include the branch name.

### Drill 2: A Low-Value Event Matches Audit Only

```bash
EVENT_ID="low-$RUN_ID"

../scripts/put-event.sh \
  "$EVENT_BUS_NAME" "$AWS_REGION" "$EVENT_SOURCE" \
  "$EVENT_ID" order.created "order-low-$RUN_ID" 25 - \
  "../evidence/$EVENT_ID.json"

sleep 15

aws logs tail "/aws/lambda/$AUDIT_FUNCTION" \
  --since 10m \
  --region "$AWS_REGION" \
  --format short \
  > "../evidence/$EVENT_ID-audit.log"

aws logs tail "/aws/lambda/$HIGH_VALUE_FUNCTION" \
  --since 10m \
  --region "$AWS_REGION" \
  --format short \
  > "../evidence/$EVENT_ID-high-value.log"
```

The audit branch should contain the event.

Check only the acceptance result:

```bash
jq '{
  EventId: .detail.event_id,
  Amount: .detail.amount,
  FailedEntryCount: .put_events_response.FailedEntryCount,
  EventBridgeId: .put_events_response.Entries[0].EventId
}' "../evidence/$EVENT_ID.json"
```

Expected: the number `25`, `FailedEntryCount = 0`, and a non-empty `EventBridgeId`.

Check `audit`:

```bash
rg -F "$EVENT_ID" "../evidence/$EVENT_ID-audit.log"
```

Expected: `routed_event_started` and `routed_event_completed`.

Check `high-value`:

```bash
if rg -F "$EVENT_ID" "../evidence/$EVENT_ID-high-value.log"; then
  echo "UNEXPECTED: event found in high-value"
else
  echo "EXPECTED: event absent from high-value"
fi
```

### Drill 3: Event Type Can Override an Otherwise Matching Amount

```bash
EVENT_ID="refund-$RUN_ID"

../scripts/put-event.sh \
  "$EVENT_BUS_NAME" "$AWS_REGION" "$EVENT_SOURCE" \
  "$EVENT_ID" order.refunded "order-refund-$RUN_ID" 150 - \
  "../evidence/$EVENT_ID.json"
```

Check:

```bash
jq '{
  EventId: .detail.event_id,
  Amount: .detail.amount,
  FailedEntryCount: .put_events_response.FailedEntryCount,
  EventBridgeId: .put_events_response.Entries[0].EventId
}' "../evidence/$EVENT_ID.json"
```

`amount=150` satisfies the numeric condition, but `Order Refunded` does not
satisfy the high-value rule's `detail-type`. All declared pattern fields must
match, so only audit receives the event.

Verify the routing through the logs:

```bash
aws logs tail "/aws/lambda/$AUDIT_FUNCTION" \
  --since 10m \
  --region "$AWS_REGION" \
  --format short \
  > "../evidence/$EVENT_ID-audit.log"

aws logs tail "/aws/lambda/$HIGH_VALUE_FUNCTION" \
  --since 10m \
  --region "$AWS_REGION" \
  --format short \
  > "../evidence/$EVENT_ID-high-value.log"
```

Audit:

```bash
rg -F "$EVENT_ID" "../evidence/$EVENT_ID-audit.log"
```

Expected: `routed_event_started` and `routed_event_completed`.

High-value:

```bash
if rg -F "$EVENT_ID" "../evidence/$EVENT_ID-high-value.log"; then
  echo "UNEXPECTED: refund found in high-value"
else
  echo "EXPECTED: refund absent from high-value"
fi
```

### Drill 4: Accepted Does Not Mean Matched

```bash
EVENT_ID="wrong-source-$RUN_ID"

../scripts/put-event.sh \
  "$EVENT_BUS_NAME" "$AWS_REGION" com.example.wrong \
  "$EVENT_ID" order.created "order-wrong-$RUN_ID" 150 - \
  "../evidence/$EVENT_ID.json"
```

For verification, save the logs from both functions and check both files.

The publisher should report a valid EventBridge event ID, but neither consumer
should log this business event. EventBridge accepted it; no rule matched it.

## 11. Processing-Failure Isolation Drill

Publish an event that matches both rules but fails only in `high_value`:

```bash
EVENT_ID="processing-failure-$RUN_ID"

../scripts/put-event.sh \
  "$EVENT_BUS_NAME" "$AWS_REGION" "$EVENT_SOURCE" \
  "$EVENT_ID" order.created "order-failure-$RUN_ID" 150 high_value \
  "../evidence/$EVENT_ID.json"
```

Verify the routing through the logs:

```bash
aws logs tail "/aws/lambda/$AUDIT_FUNCTION" \
  --since 10m \
  --region "$AWS_REGION" \
  --format short \
  > "../evidence/$EVENT_ID-audit.log"

aws logs tail "/aws/lambda/$HIGH_VALUE_FUNCTION" \
  --since 10m \
  --region "$AWS_REGION" \
  --format short \
  > "../evidence/$EVENT_ID-high-value.log"
```

The audit branch completes. The high-value branch returns its SQS message ID in
`batchItemFailures`. After `maxReceiveCount` is exhausted, SQS moves that message
to the high-value processing DLQ.

Show the lines related to the event:

```bash
rg -F "$EVENT_ID" \
  "../evidence/$EVENT_ID-audit.log" \
  "../evidence/$EVENT_ID-high-value.log"
```

The output proves processing isolation:

- `audit` successfully completed its copy once;
- `high-value` processed the same SQS copy three times;
- the same `message_id` indicates retries of the same message;
- different `request_id` values indicate three separate Lambda invocations;
- intervals of about 40 seconds correspond to the visibility timeout;
- each attempt ended with `PlannedConsumerError`.

Now verify the processing DLQ:

```bash
aws sqs receive-message \
  --queue-url "$HIGH_VALUE_PROCESSING_DLQ_URL" \
  --region "$AWS_REGION" \
  --max-number-of-messages 1 \
  --visibility-timeout 30 \
  --wait-time-seconds 10 \
  --no-paginate \
  --attribute-names All \
  --output json >"../evidence/$EVENT_ID-processing-dlq.json"

jq --arg event_id "$EVENT_ID" '
  .Messages[]?
  | (.Body | fromjson) as $event
  | select($event.detail.event_id == $event_id)
  | {
      message_id: .MessageId,
      receive_count: .Attributes.ApproximateReceiveCount,
      source: $event.source,
      detail_type: $event["detail-type"],
      event_id: $event.detail.event_id
    }
' "../evidence/$EVENT_ID-processing-dlq.json"
```

The event must not appear in the delivery DLQ. EventBridge delivered it
successfully; the downstream consumer failed.

## 12. Target Delivery-Failure Drill

Run this drill only in the disposable dev lab. It temporarily replaces the
high-value source queue policy with an explicit deny for EventBridge, publishes
one event, then restores the Terraform declaration through a reviewed plan.

First, save the current policy and extract the queue ARN:

```bash
aws sqs get-queue-attributes \
  --queue-url "$HIGH_VALUE_SOURCE_QUEUE_URL" \
  --region "$AWS_REGION" \
  --attribute-names QueueArn Policy \
  --output json >../evidence/high-value-queue-policy-before.json

HIGH_VALUE_SOURCE_QUEUE_ARN="$(
  jq -r '.Attributes.QueueArn' ../evidence/high-value-queue-policy-before.json
)"
```

Check baseline:

```bash
jq '{
  QueueArn: .Attributes.QueueArn,
  Statements: (
    .Attributes.Policy
    | fromjson
    | .Statement
    | map({
        Sid,
        Effect,
        Principal,
        Action,
        Condition
      })
  )
}' ../evidence/high-value-queue-policy-before.json
```

Create and apply the temporary deny policy:

```bash
jq -cn --arg queue_arn "$HIGH_VALUE_SOURCE_QUEUE_ARN" '
  {
    Policy: ({
      Version: "2012-10-17",
      Statement: [{
        Sid: "DenyEventBridgeDeliveryDrill",
        Effect: "Deny",
        Principal: {Service: "events.amazonaws.com"},
        Action: "sqs:SendMessage",
        Resource: $queue_arn
      }]
    } | tojson)
  }
' >../evidence/high-value-deny-attributes.json

aws sqs set-queue-attributes \
  --queue-url "$HIGH_VALUE_SOURCE_QUEUE_URL" \
  --region "$AWS_REGION" \
  --attributes file://../evidence/high-value-deny-attributes.json
```

Check the actual AWS state:

```bash
aws sqs get-queue-attributes \
  --queue-url "$HIGH_VALUE_SOURCE_QUEUE_URL" \
  --region "$AWS_REGION" \
  --attribute-names Policy \
  --output json |
jq '.Attributes.Policy | fromjson'
```

Publish a high-value event:

```bash
EVENT_ID="delivery-failure-$RUN_ID"

../scripts/put-event.sh \
  "$EVENT_BUS_NAME" "$AWS_REGION" "$EVENT_SOURCE" \
  "$EVENT_ID" order.created "order-delivery-$RUN_ID" 150 - \
  "../evidence/$EVENT_ID.json"
```

Permission failures are non-retriable EventBridge delivery errors and should be
sent to the configured target DLQ. Allow a short propagation delay, then inspect it:

```bash
aws sqs receive-message \
  --queue-url "$HIGH_VALUE_DELIVERY_DLQ_URL" \
  --region "$AWS_REGION" \
  --max-number-of-messages 1 \
  --visibility-timeout 30 \
  --wait-time-seconds 10 \
  --attribute-names All \
  --message-attribute-names All \
  --no-paginate \
  --output json \
  > "../evidence/$EVENT_ID-delivery-dlq.json"

jq --arg event_id "$EVENT_ID" '
  .Messages[]?
  | (.Body | fromjson) as $event
  | select($event.detail.event_id == $event_id)
  | {
      message_id: .MessageId,
      error_code: .MessageAttributes.ERROR_CODE.StringValue,
      error_message: .MessageAttributes.ERROR_MESSAGE.StringValue,
      retry_attempts: .MessageAttributes.RETRY_ATTEMPTS.StringValue,
      exhausted_retry_condition:
        .MessageAttributes.EXHAUSTED_RETRY_CONDITION.StringValue,
      rule_arn: .MessageAttributes.RULE_ARN.StringValue,
      target_arn: .MessageAttributes.TARGET_ARN.StringValue,
      event_id: $event.detail.event_id
    }
' "../evidence/$EVENT_ID-delivery-dlq.json"
```

Restore the Terraform-managed policy immediately:

```bash
terraform plan -out=tfplan-restore
terraform show -no-color tfplan-restore | less
terraform apply tfplan-restore

terraform plan -detailed-exitcode
printf 'exit_code=%s\n' "$?"
```

The final exit code should be `0`. If it is `2`, review and repair the remaining
drift before continuing. Do not leave the target policy in the drill state.

### Prove JSON Type Matters

Create a temporary copy of the high-value fixture where `amount` is a string:

```bash
jq '.detail.amount = "150"' \
  "$LAB_ROOT/events/order-created-high-value.json" \
  >../evidence/high-value-string-amount.json

aws events test-event-pattern \
  --event-pattern "file://$LAB_ROOT/patterns/high-value.json" \
  --event file://../evidence/high-value-string-amount.json
```

Expected result: `false`.

## 13. Troubleshooting

### `PutEvents` succeeds, but there is no Lambda log entry

Check the path step by step:

1. `FailedEntryCount = 0` in the evidence.
2. The event matches the pattern through `test-event-pattern`.
3. The rule has the correct target.
4. There is no delivery error in the delivery DLQ.
5. The Lambda event source mapping is enabled.

### The script accepts an incorrect event bus name

Use the lab script, not only `aws events put-events`. The script first calls
`describe-event-bus`, because EventBridge may report success for a non-existent
custom event bus and the event may be lost without matching any rules.

Therefore, the lab script first runs:

```bash
aws events describe-event-bus \
  --name "$EVENT_BUS_NAME" \
  --region "$AWS_REGION"
```

Only after this check succeeds does it call `put-events`.

### EventBridge reports `NO_PERMISSIONS`

Check the queue policy:

```text
Principal      = events.amazonaws.com
Action         = sqs:SendMessage
aws:SourceArn  = exact rule ARN
```

Also look for a conflicting `Deny`.

### The source queue appears empty

Lambda polls it continuously. An empty queue may mean successful processing rather
than a routing failure. Search for the unique business `event_id` in the function
logs and verify the pattern instead of relying only on queue depth.

### The processing DLQ remains empty

Check that:

- the message actually reached the required branch;
- the event source mapping is enabled;
- Lambda actually returns the record in `batchItemFailures`;
- the visibility timeout has expired;
- the message has exhausted `maxReceiveCount`.

### The delivery DLQ remains empty

Check three things:

- the temporary `Deny` was actually added to the source queue policy;
- the delivery DLQ has its own `Allow` for `events.amazonaws.com`;
- EventBridge registered a failed invocation.

Two metrics are especially useful:

```text
FailedInvocations

InvocationsFailedToBeSentToDLQ
```

The first shows a target delivery failure. The second shows that EventBridge also failed
to write the event to the delivery DLQ.

### The pattern file works, but the Terraform rule differs

The patterns actually deployed are taken from `locals.tf`, while the files under
`patterns/*.json` are used by the `test-event-pattern` command.

Compare them with the actual output:

```bash
terraform output -json event_patterns | jq .
```

The files in `patterns/` are used in the exercises. `locals.tf` remains the source of
truth for deployment, so both representations must be kept consistent.

## 14. Cost and Operational Boundaries

The lab creates:

- 1 custom event bus;
- 2 EventBridge rules;
- 6 SQS queues;
- 2 Lambda functions;
- 2 log groups;
- 2 event source mappings;
- 2 IAM roles;
- 8 CloudWatch alarms.

With the small number of events used in the lab, EventBridge, SQS, and Lambda request 
costs are low. A more noticeable recurring cost may come from the eight CloudWatch alarms,
because they continue to exist and are billed independently of the number of events.
Messages in the DLQs remain there until their retention period expires or the queues are
deleted. In this lab, the DLQs are configured with a 14-day retention period.

Do not create rules that publish matching events back to the same event bus without a field
that terminates the loop. Cyclic routing increases costs and may lead to delivery throttling.

## 15. Completion Checklist

- [ ] Python unit tests pass.
- [ ] Shell and JSON checks pass.
- [ ] Terraform validation and all 12 native tests pass.
- [ ] The pattern matrix matches the expected four-event result.
- [ ] A high-value created event reaches both branches.
- [ ] A low-value created event reaches only audit.
- [ ] A refunded event reaches only audit despite a high amount.
- [ ] A wrong-source event is accepted but matches neither rule.
- [ ] A selected consumer failure reaches only its processing DLQ.
- [ ] The delivery drill reaches the target delivery DLQ.
- [ ] Queue-policy drift is restored and final plan exit code is `0`.
- [ ] Direct source-queue send is denied.

## 16. Cleanup

First ensure the delivery-failure drill policy has been restored.
Then destroy the lab through Terraform:

```bash
terraform plan -destroy -out=tfplan-destroy
terraform show -no-color tfplan-destroy | less
terraform apply tfplan-destroy
```

Verify that Terraform tracks no remaining resources:

```bash
terraform state list
```

The repository-wide `.gitignore` excludes runtime evidence and Terraform state.

## 17. Final Model

Keep these statements separate:

1. `PutEvents` accepted the entry.
2. A rule pattern matched the envelope.
3. EventBridge delivered the matched event to its target.
4. SQS buffered the delivered message.
5. Lambda processed the message successfully.
6. The business operation completed correctly.

EventBridge rules answer routing questions. A target delivery DLQ answers why a
matched event did not reach the target. An SQS processing DLQ answers why an accepted
queue message could not be consumed. Logs and business state answer whether processing
produced the intended result.

## 18. Official References

- [Event pattern syntax](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-create-pattern.html)
- [Event pattern best practices](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-patterns-best-practices.html)
- [Sending events with PutEvents](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-putevents.html)
- [EventBridge targets](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-targets.html)
- [EventBridge retry policy](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-rule-retry-policy.html)
- [EventBridge target dead-letter queues](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-rule-dlq.html)
- [Using Lambda with SQS](https://docs.aws.amazon.com/lambda/latest/dg/with-sqs.html)
- [Lambda SQS partial batch responses](https://docs.aws.amazon.com/lambda/latest/dg/services-sqs-errorhandling.html)
