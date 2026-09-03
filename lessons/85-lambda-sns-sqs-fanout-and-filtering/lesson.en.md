# Lesson 85: Lambda SNS-to-SQS Fan-out and Subscription Filtering

## 1. Why This Lesson Exists

In Lessons 82–84, we built a single processing path through SQS and covered partial
failures, backpressure, concurrent invocations, FIFO ordering, and deduplication.
In `production`, a single event often has multiple independent consumers:

```text
order.created
├── audit history
├── billing workflow
├── analytics
└── customer notification
```

Publishing the event separately to every queue couples the producer to all consumers.

```text
Producer
├── sends to audit queue
├── sends to billing queue
├── sends to analytics queue
└── sends to notifications queue
```

Problems:

- the producer is coupled to all consumers;
- adding a new branch requires changing the producer;
- partial publishing is possible: the message may reach one queue but not another;
- the producer must know the addresses and permissions of all queues;
- routing logic becomes scattered throughout the application.

This lesson inserts an SNS topic as the routing boundary.
SNS does not place one shared message into two queues. It creates independent transport copies:

```text
Business event_id: order-123

audit SQS:
  messageId: AAA
  event_id: order-123

billing SQS:
  messageId: BBB
  event_id: order-123
```

Therefore:

- the SQS `messageId` differs between branches;
- the number of processing attempts differs;
- one copy may be deleted successfully;
- another may be retried several times and end up in the DLQ;
- branches should be correlated using the business field `event_id`, not the SQS `messageId`.

The lab deliberately uses `SNS -> SQS -> Lambda` instead of direct SNS-to-Lambda
subscriptions.

SQS gives each branch:

- an independent buffer;
- its own backlog;
- processing-rate control;
- retries;
- a DLQ;
- concurrency limits;
- protection against temporary Lambda unavailability.

## 2. Learning Outcomes

After the lesson, you can:

- explain the difference between queueing and pub/sub fan-out;
- distinguish an SNS topic, subscription, and endpoint;
- route events with a subscription filter policy;
- explain `MessageAttributes` versus `MessageBody` filter scope;
- explain what raw message delivery changes;
- authorize SNS to send to SQS with a resource policy and `aws:SourceArn`;
- prove that one branch failure does not cancel another branch;
- handle standard SQS partial failures independently;
- recognize SNS filter eventual consistency;
- choose between direct SNS-to-Lambda and SNS-to-SQS-to-Lambda.

Evidence map:

| Claim | Evidence |
|---|---|
| One publish fans out | One `event_id` completes in both audit and billing logs |
| Filtering works | `profile.updated` appears in audit but not billing |
| Payload remains raw | Lambda parses the original JSON directly from the SQS body |
| Queue ingress is constrained | Queue policy allows the topic ARN and denies other senders |
| Branches fail independently | Billing retries while audit completes the same event |
| Infrastructure contracts hold | Eight Terraform native tests pass |

### 2.1. Lesson Terminology

| English term | Plain wording | Meaning in this lesson |
|---|---|---|
| `publisher` | event producer | Process that calls `sns:Publish` |
| `topic` | publication channel | SNS resource that accepts and distributes events |
| `subscription` | delivery rule | Connection from the topic to one endpoint |
| `subscriber` | consumer branch | SQS endpoint receiving a matching event copy |
| `fan-out` | one-to-many delivery | One publication copied to multiple subscriptions |
| `filter policy` | routing condition | JSON rule deciding whether a subscription receives an event |
| `filter policy scope` | filter input | Message attributes or JSON message body |
| `raw message delivery` | unwrapped payload | Original published body becomes the SQS body |
| `branch isolation` | independent failure boundary | Audit and billing have separate queues, retries, and DLQs |

## 3. Mental Model

### 3.1. SNS Does Not Replace SQS

SNS and SQS solve different problems:

| Service | Main role | Delivery model |
|---|---|---|
| SNS | distribute one publication to subscribers | push to endpoints |
| SQS | buffer work until a consumer is ready | consumer polls |

Together they form a durable fan-out pipeline:

```text
publisher -> SNS routing -> independent SQS buffers -> Lambda consumers
```

- SNS receives a single publication and determines the recipients.
- SQS stores a separate copy of the message until it is processed.
- Lambda retrieves messages from SQS.

SNS is the router; SQS is the buffer.

If Lambda is temporarily unavailable, SNS does not need to keep waiting for it to recover.
The message is already stored in SQS, and Lambda can process it later.

### 3.2. Fan-out Creates Copies, Not Shared Work

When an event matches two subscriptions, SNS sends one copy to each endpoint.
The audit and billing queues then own separate SQS messages with separate message
IDs, receive counts, visibility timeouts, and DLQ outcomes.

- `event_id` — the identifier of the business event. It is the same across all branches.
- `messageId` — the transport-level identifier of a specific SQS message. It will be different because the queues received separate copies.

To find the same event across all branches, use: `event_id`

To return a specific failed record in `batchItemFailures`, use: `messageId`

There is no distributed transaction across branches:

```text
audit completed + billing failed
```

Successful processing in `audit` does not delete the message from `billing`.
A failure in `billing` does not return the message to `audit`.

is a valid intermediate and final operational state.

### 3.3. Filtering Belongs to the Subscription

The topic does not have one global filter. Every subscription owns its routing
policy:

```text
audit subscription   -> no filter -> receives all events
billing subscription -> event_type in [order.created, order.refunded]
```

The lab uses `FilterPolicyScope = MessageAttributes`. The publisher must send an
`event_type` message attribute. A body field with the same name does not satisfy
an attribute-scoped filter by itself.

Different consumers are interested in different events. For example:

```text
audit subscription
  → all events

billing subscription
  → order.created, order.refunded

notification subscription
  → order.shipped

analytics subscription
  → all order.* events
```

Adding a new consumer does not require changing the existing subscriptions orthe
producer. A new subscription is created with its own endpoint and its own filter.

### 3.4. Raw Delivery Defines the Consumer Contract

Without raw delivery, the SQS body contains an SNS notification envelope whose
`Message` field contains the original payload. With raw delivery enabled, the
original payload becomes the SQS body directly.

This lab enables raw delivery and validates that the body `event_type` matches
the transported SNS message attribute. Raw delivery to SQS supports at most ten
SNS message attributes; the lab uses one.

### 3.5. Queue Policies Protect the Routing Boundary

An SNS subscription does not automatically authorize the topic to call
`sqs:SendMessage`. Each source queue has a resource policy that:

1. allows the SNS service principal;
2. requires `aws:SourceArn` to equal the lesson topic ARN;
3. explicitly denies `SendMessage` outside that topic;
4. denies insecure transport.

```bash
sed -n '45,103p' lab_85/terraform/queues.tf
```

The explicit deny prevents a same-account IAM identity with broad SQS
permissions from bypassing SNS filtering by writing directly to the queue.

### 3.6. Standard and FIFO Partial Failures Differ

Lesson 84 stopped after the first FIFO failure and returned the failed plus
unprocessed tail. These lesson 85 queues are standard queues, so records are
independent:

```text
record 1 fails   -> return record 1
record 2 succeeds -> continue and delete record 2
```

Both mappings enable `ReportBatchItemFailures`.

### 3.7. Filter Changes Are Eventually Consistent

SNS filter policy additions or changes can take up to 15 minutes to become fully
effective. A result observed immediately after `terraform apply` is not proof of
a broken policy.

Correct verification:

1. Check the subscription attributes:

```bash
aws sns get-subscription-attributes \
  --subscription-arn "$BILLING_SUBSCRIPTION_ARN"
```

2. Make sure that `FilterPolicy` contains the required value.
3. Wait for the setting to propagate.
4. Publish a new event with a new `event_id`.

## 4. Lab Architecture

```text
                               ┌─ audit subscription
                               │  no filter
                               ▼
Producer → SNS topic → audit SQS → audit Lambda
                               │
                               └──────────────→ audit DLQ
                                  after retry attempts are exhausted


                     ┌─ billing subscription
                     │  filter:
SNS topic ───────────┤  order.created
                     │  order.refunded
                     ▼
                billing SQS → billing Lambda
                     │
                     └──────────────→ billing DLQ
                        after retry attempts are exhausted
```

The two branches share only:

- the producer;
- the SNS topic;
- the business-event format;
- the Lambda source code file.

After SNS, the branches are infrastructure-independent.

`audit` and `billing` each have their own:

- SNS subscription;
- source queue;
- queue policy;
- Lambda function;
- IAM execution role;
- event source mapping;
- concurrency limit;
- CloudWatch log group;
- DLQ;
- CloudWatch alarms.

Each Lambda function has its own execution role:

```text
audit role   -> can read only from the audit source queue
billing role -> can read only from the billing source queue
```

Runtime roles should not:

- read another branch's queue;
- read from the DLQ;
- publish to SNS;
- manage infrastructure.

This limits the impact of an error or compromise in a single function.

## 5. Implementation Walkthrough

### Topic and Subscriptions

`terraform/topic.tf` creates one encrypted standard topic and two raw SQS
subscriptions. Only billing has a filter policy.

### Queues and Resource Policies

`terraform/queues.tf` creates two source queues, two DLQs, redrive allow
policies, and topic-scoped queue policies.

### Functions and Runtime Roles

`package.tf`, `functions.tf`, `function_execution_roles.tf`, `event_source_mappings.tf`

The same package is deployed as two functions. `CONSUMER_NAME` selects branch
behavior, while separate roles preserve least privilege.

Shared code:

- two separate Lambda functions;
- two separate IAM roles;
- two separate queues and event source mappings;
- independent branch execution.

### Consumer Contract

A single handler is used by both the `audit` and `billing` branches.

`app/lambda_function.py` validates:

- SQS `messageId`;
- JSON body;
- `event_id`, `event_type`, `order_id`, and non-negative `amount`;
- SNS `event_type` message attribute;
- equality between body and attribute event types.

`fail_consumer` is a lab-only field. Setting it to `billing` fails only that
branch for the selected event.

### Publisher Contract

`scripts/publish-event.sh`

1. Accepts the event parameters: `event_id`, `event_type`, `order_id`, `amount`, and `fail_consumer`.
2. Validates the values before publishing.
3. Uses `jq` to build the JSON event body.
4. Separately creates the SNS `event_type` attribute.
5. Publishes the body and the attribute with a single `aws sns publish` command.
6. Saves the request and the AWS response to an evidence file.

The main idea is that both the body and the SNS attribute are created from the same
`event_type` variable. This reduces the risk of them accidentally becoming inconsistent.

## 6. Local Verification

From the repository root:

```bash
python3 -m unittest discover \
  -s lessons/85-lambda-sns-sqs-fanout-and-filtering/lab_85/tests -v

bash -n lessons/85-lambda-sns-sqs-fanout-and-filtering/lab_85/scripts/publish-event.sh
shellcheck lessons/85-lambda-sns-sqs-fanout-and-filtering/lab_85/scripts/publish-event.sh
```

Expected result: eight Python tests pass and the publisher has no shell errors.

Then run infrastructure checks:

```bash
cd lessons/85-lambda-sns-sqs-fanout-and-filtering/lab_85/terraform
terraform init
terraform fmt -check -recursive
terraform validate
terraform test
```

Expected result: eight Terraform tests pass.

## 7. Terraform Deployment

```bash
cp terraform.tfvars.example terraform.tfvars
export AWS_PROFILE=YOUR_PROFILE
aws sso login --profile "$AWS_PROFILE"
aws sts get-caller-identity

terraform plan -out=tfplan
terraform show -no-color tfplan | less
terraform apply tfplan
```

Export runtime values:

```bash
export AWS_REGION="$(terraform output -raw aws_region)"
export TOPIC_ARN="$(terraform output -raw topic_arn)"
export AUDIT_FUNCTION="$(terraform output -json function_names | jq -r '.audit')"
export BILLING_FUNCTION="$(terraform output -json function_names | jq -r '.billing')"
export AUDIT_QUEUE_URL="$(terraform output -json source_queue_urls | jq -r '.audit')"
export BILLING_QUEUE_URL="$(terraform output -json source_queue_urls | jq -r '.billing')"
export AUDIT_DLQ_URL="$(terraform output -json dead_letter_queue_urls | jq -r '.audit')"
export BILLING_DLQ_URL="$(terraform output -json dead_letter_queue_urls | jq -r '.billing')"
export AUDIT_SUBSCRIPTION_ARN="$(terraform output -json subscription_arns | jq -r '.audit')"
export BILLING_SUBSCRIPTION_ARN="$(terraform output -json subscription_arns | jq -r '.billing')"
```

## 8. Verify the Infrastructure Contract

Inspect subscription attributes:

```bash
aws sns get-subscription-attributes \
  --region "$AWS_REGION" \
  --subscription-arn "$BILLING_SUBSCRIPTION_ARN" \
  --query 'Attributes.{Raw:RawMessageDelivery,Scope:FilterPolicyScope,Filter:FilterPolicy}' \
  --output table
```

Expected values are `Raw=true`, `Scope=MessageAttributes`, and both billing event
types in `Filter`.

This proves:

- SNS delivers the original message body without an envelope;
- filtering is performed using SNS message attributes;
- `billing` accepts only the two configured event types.

Inspect one queue policy:

```bash
aws sqs get-queue-attributes \
  --region "$AWS_REGION" \
  --queue-url "$BILLING_QUEUE_URL" \
  --attribute-names Policy \
  --query 'Attributes.Policy' --output text | jq '.'
```

Confirm the allow and deny statements reference only `$TOPIC_ARN`.

```text
billing subscription
├── raw delivery is enabled
├── filter scope is configured correctly
└── the required event types are allowed

billing SQS
├── accepts messages from the lesson topic
├── blocks bypassing the topic
└── rejects insecure transport
```

## 9. Drills

### Drills 1: Prove Fan-out

Goal: publish `order.created` once and find the same business `event_id` in both
Lambda functions.

```bash
export RUN_ID="$(date -u +%Y%m%dT%H%M%S)"
export EVENT_ID="order-created-${RUN_ID}"

../scripts/publish-event.sh \
  "$TOPIC_ARN" "$AWS_REGION" \
  "$EVENT_ID" order.created order-100 42.50 - \
  ../evidence/order-created.json
```

The arguments mean:

```text
TOPIC_ARN       → the lab topic
AWS_REGION      → the topic region
EVENT_ID        → unique event ID
order.created   → event type
order-100       → order ID
42.50           → amount
-               → do not trigger an intentional failure
output file     → save the publication evidence
```

After delivery, search both logs:

```bash
sleep 10
aws logs tail "/aws/lambda/${AUDIT_FUNCTION}" --region "$AWS_REGION" --since 10m | grep "$EVENT_ID"
aws logs tail "/aws/lambda/${BILLING_FUNCTION}" --region "$AWS_REGION" --since 10m | grep "$EVENT_ID"
```

Both records have the same business `event_id`, but the SQS `message_id` is different. This
confirms that fan-out created two independent transport copies.

- the same `event_id`: both branches are processing the same business event;
- a different `message_id`: SNS created a separate copy for each queue;
- a different `request_id`: the `audit` Lambda and `billing` Lambda were invoked independently.

On a retry, the SQS `message_id` remains the same, while the Lambda `request_id` changes because
it is a new invocation.

What the result proves:

```text
One sns:Publish
├── audit subscription   → audit SQS   → audit Lambda
└── billing subscription → billing SQS → billing Lambda
```

### Drill 2: Prove Subscription Filtering

Publish an event outside the billing filter.

`audit` should receive it, while `billing` should not, because `billing` allows only:

```text
order.created
order.refunded
```

```bash
export EVENT_ID="profile-updated-${RUN_ID}"

../scripts/publish-event.sh \
  "$TOPIC_ARN" "$AWS_REGION" \
  "$EVENT_ID" profile.updated order-100 0 - \
  ../evidence/profile-updated.json
```

After logs settle:

```bash
sleep 10
aws logs tail "/aws/lambda/${AUDIT_FUNCTION}" --region "$AWS_REGION" --since 10m | grep "$EVENT_ID"
aws logs tail "/aws/lambda/${BILLING_FUNCTION}" --region "$AWS_REGION" --since 10m | grep "$EVENT_ID" || true
```

Audit must contain the event; billing must not.
`|| true` is needed because `grep` returns exit code `1` when no matching line is found.
In this exercise, the absence of a matching line is the expected result.

Resulting flow:

```text
profile.updated
├── audit subscription   → audit Lambda
└── billing subscription → filtered out by SNS
```

### Drill 3: Prove Branch Failure Isolation

Publish a matching event that fails only billing:

```bash
export EVENT_ID="billing-failure-${RUN_ID}"

../scripts/publish-event.sh \
  "$TOPIC_ARN" "$AWS_REGION" \
  "$EVENT_ID" order.created order-500 99 billing \
  ../evidence/billing-failure.json
```

The value that will be included in the event body:

```text
fail_consumer = billing
```

Inspect logs:

```bash
sleep 10
aws logs tail "/aws/lambda/${AUDIT_FUNCTION}" --region "$AWS_REGION" --since 10m | grep "$EVENT_ID"
aws logs tail "/aws/lambda/${BILLING_FUNCTION}" --region "$AWS_REGION" --since 10m | grep "$EVENT_ID"
```

Expected state:

```text
audit   -> fanout_event_completed
billing -> fanout_event_failed and retries
```

On retries:

- `event_id` remains the same;
- the SQS `message_id` remains the same;
- the Lambda `request_id` is new for each invocation.

After the receive budget is exhausted, billing moves its copy to the billing DLQ.
Audit must not receive or retry that DLQ record.

```bash
aws sqs get-queue-attributes \
  --region "$AWS_REGION" \
  --queue-url "$BILLING_DLQ_URL" \
  --attribute-names ApproximateNumberOfMessages \
  --query 'Attributes.ApproximateNumberOfMessages' \
  --output text
```

Final result:

```text
One publication
├── audit copy   → processed successfully
└── billing copy → retries → billing DLQ
```

This proves branch isolation: a persistent failure in `billing` does not undo
successful processing in `audit` and does not pollute the `audit` DLQ.

## 10. Negative Drills

Here, the correct result is for the command to fail. We intentionally pass unsafe
values and verify the protective controls.

### Reject an Empty Billing Filter

```bash
terraform plan -var='billing_event_types=[]'
```

An empty list is not allowed because `billing` would stop receiving any events.

### Reject an Unsafe Visibility Timeout

```bash
terraform plan -var='queue_visibility_timeout_seconds=35'
```

The provided value `35` is within the allowed range of the variable itself,
but it violates the queue precondition. The error is expected for both source queues.

### Prove Direct Queue Send Is Denied

```bash
aws sqs send-message \
  --region "$AWS_REGION" \
  --queue-url "$BILLING_QUEUE_URL" \
  --message-body '{"bypass":true}'
```

Even an identity with an allow should receive `AccessDenied` because the queue
policy has an explicit deny for sends outside the topic.

This proves that only the intended path is allowed:

```text
Producer → SNS topic → SQS
```

## 11. Troubleshooting

### Billing Receives Nothing

First, check the SNS subscription rather than Lambda, because `billing` receives the
message only if SNS allows it through the filter in the first place. Verify the
subscription ARN, the case of `event_type`, the publication attributes, and the filter
propagation delay.

```bash
aws sns get-subscription-attributes \
  --region "$AWS_REGION" \
  --subscription-arn "$BILLING_SUBSCRIPTION_ARN" \
  --output json
```

### Lambda Reports an SNS Envelope Instead of the Business Event

Check `RawMessageDelivery`. Without raw delivery, decode the SNS envelope's
`Message` field instead of parsing the SQS body as the business event.

```bash
aws sns get-subscription-attributes \
  --region "$AWS_REGION" \
  --subscription-arn "$BILLING_SUBSCRIPTION_ARN" \
  --query 'Attributes.RawMessageDelivery' \
  --output text
```

### SNS Cannot Deliver to SQS

Inspect `NumberOfNotificationsFailed` and the `queue resource policy`. The allow
must use the SNS service principal and the exact topic ARN.

Model:

```text
SNS subscription exists
|
SNS attempts to deliver to SQS
|
the SQS queue policy must allow it
```

In lab, the permission is:

```text
Principal = sns.amazonaws.com
Action    = sqs:SendMessage
Condition:
  aws:SourceArn = the ARN of our specific SNS topic
```

```bash
aws sqs get-queue-attributes \
  --region "$AWS_REGION" \
  --queue-url "$BILLING_QUEUE_URL" \
  --attribute-names Policy \
  --query 'Attributes.Policy' \
  --output text | jq '.'
```

### One Branch Failure Appears to Affect Another

Correlate by business `event_id`, not SQS message ID. Verify that each mapping,
role, queue, and DLQ belongs to the expected branch.

### Filtered Event Appears Immediately After a Policy Change

Filter changes are eventually consistent. Wait up to 15 minutes and publish a
new unique event; never reuse an old log line as evidence.

First, make sure AWS already shows the required policy:

```bash
aws sns get-subscription-attributes \
  --region "$AWS_REGION" \
  --subscription-arn "$BILLING_SUBSCRIPTION_ARN" \
  --query 'Attributes.{Scope:FilterPolicyScope,Filter:FilterPolicy}' \
  --output table
```

And always publish a new event with a new `event_id`:

```text
old event_id
  - an old log entry already exists
  - poor evidence

new event_id
  - the new publication can be verified unambiguously
```

## 12. Cost and Operational Boundaries

The lab creates one SNS topic, four SQS queues, two Lambda functions, two roles,
two log groups, two mappings, and five CloudWatch alarms. Requests, encryption, logs,
Lambda duration, metrics, and alarms can incur charges.

Production design must also define schema ownership, event versioning, idempotency,
replay authorization, per-branch SLOs, and a transactional outbox when publication must
be atomic with a database change.

What can potentially incur costs here:

```text
SNS publishes/deliveries
SQS requests
Lambda execution time
CloudWatch logs
CloudWatch metrics/alarms
encryption-related operations
```

## 13. Completion Checklist

- 8 Python tests pass;
- 8 Terraform native tests pass;
- both subscriptions use raw delivery;
- audit has no filter and billing uses `MessageAttributes`;
- one `order.created` event completes in both branches;
- `profile.updated` completes only in audit;
- a billing failure does not fail audit;
- only billing's copy reaches the billing DLQ;
- direct queue publishing is denied;

## 14. Cleanup

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

1. SNS distributes; SQS buffers.
2. One publication can produce independent copies in multiple queues.
3. Every subscription owns its own filter and endpoint.
4. Raw delivery changes the payload contract, not filter behavior.
5. Queue resource policies authorize the topic-to-queue edge.
6. A branch owns its retry budget, concurrency, monitoring, and DLQ.
7. Branch success is not a transaction across all consumers.
8. Standard queue partial failures retry only failed records.
9. Filter changes are eventually consistent.
10. Business event IDs provide cross-branch correlation.

## 16. Official References

- [What is Amazon SNS?](https://docs.aws.amazon.com/sns/latest/dg/welcome.html)
- [Subscribing SQS to an SNS topic](https://docs.aws.amazon.com/sns/latest/dg/subscribe-sqs-queue-to-sns-topic.html)
- [Amazon SNS message filtering](https://docs.aws.amazon.com/sns/latest/dg/sns-message-filtering.html)
- [Applying an SNS filter policy](https://docs.aws.amazon.com/sns/latest/dg/message-filtering-apply.html)
- [Amazon SNS message attributes](https://docs.aws.amazon.com/sns/latest/dg/sns-message-attributes.html)
- [Amazon SNS raw message delivery](https://docs.aws.amazon.com/sns/latest/dg/sns-large-payload-raw-message-delivery.html)
- [Lambda event-driven architectures](https://docs.aws.amazon.com/lambda/latest/dg/concepts-event-driven-architectures.html)
