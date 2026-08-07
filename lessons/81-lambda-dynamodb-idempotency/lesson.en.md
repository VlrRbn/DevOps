# Lesson 81. Lambda Idempotency with DynamoDB

## 1. Why This Lesson Exists

Lesson 78 introduced Lambda execution.
Lesson 79 separated caller permissions from execution-role permissions.
Lesson 80 showed that asynchronous processing can retry an event and that duplicate
delivery is a normal distributed-systems condition.

The next question is:

> How can a Lambda function avoid repeating the same business action when the
> same event arrives more than once?

```text
asynchronous event is delivered
-> Lambda begins processing
-> the delivery outcome is uncertain, or processing ends with an error
-> the same event is delivered again
```

This lesson adds a DynamoDB idempotency table. The function uses a conditional write
to make one invocation the owner of an `idempotency_key`. A later invocation with
the same key cannot enter the processing section concurrently. After the first invocation
completes, duplicates return its saved result.

```text
duplicate delivery
-> a new Lambda invocation
-> the RequestId may be new or preserved by a managed asynchronous retry
-> a new owner_token for this handler execution attempt
-> the same `idempotency_key`
-> the same business action must not be performed again
```

The goal is to understand:

- what idempotency protects;
- what it cannot protect by itself;
- why the key is a business contract;
- how conditional writes prevent a check-then-act race;
- why active claims need expiry and ownership;
- why DynamoDB TTL is cleanup rather than precise scheduling.

## 2. Outcomes

By the end of the lesson, you will be able to:

- explain duplicate delivery and idempotent handling;
- distinguish a transport request ID from a business idempotency key;
- build a DynamoDB table with a string partition key and TTL;
- claim a key atomically with a condition expression;
- replay a saved result without executing the processor again;
- reject reuse of one key for a different payload;
- prevent an old worker from completing a reclaimed record;
- inspect records with a strongly consistent read;
- explain the side-effect gap and safer production designs;
- test the state machine locally without AWS.

Flow summarizing the entire lesson:

```text
understand duplicate delivery
-> choose a stable business key
-> atomically create an IN_PROGRESS record
-> execute the processor
-> safely update the record to COMPLETED
-> store result_json
-> return it during replay
-> explain the side-effect gap
```

Flow connecting each lesson outcome to its concrete evidence:

| Outcome                                   | Evidence                                   |
| ----------------------------------------- | ------------------------------------------ |
| The claim is created atomically           | `PutItem` and `ConditionExpression`        |
| The first invocation is processed         | `idempotency_status = PROCESSED`           |
| A duplicate does not invoke the processor | `REPLAYED`, the same `report_id`, and logs |
| The result is stored                      | `result_json` in DynamoDB                  |
| A stale worker is restricted              | conditional completion error               |
| An expired claim is taken over            | a new `owner_token`                        |
| Exactly-once processing is not guaranteed | explanation of the side-effect gap         |

### 2.1. Lesson Terminology

| English term | Plain wording | Precise meaning in this lesson |
|---|---|---|
| `consumer` | event consumer | The component that receives an event; Lambda has this role in the lab |
| `worker` | worker | One concurrent Lambda execution attempt |
| `handler` | Lambda handler | The `lambda_handler` entry point that validates the event and coordinates processing |
| `processor` | business processor | The business-logic function called after successful key acquisition |
| `idempotency key` | idempotency key | A stable business key connecting duplicate deliveries of one operation |
| `claim` | processing claim | An atomically created `IN_PROGRESS` record that assigns the key to one worker |
| `replay` | saved-result replay | A response from a `COMPLETED` record without executing the processor again |
| `payload hash` | payload hash | A fingerprint used to detect reuse of one key with different input data |
| `owner token` | owner token | A unique identifier for the worker that owns an active claim |
| `fencing token` | fencing token | An ownership value that prevents a stale worker from completing a reclaimed record |
| `conditional write` | conditional write | A DynamoDB operation performed only when its `ConditionExpression` is true |
| `strongly consistent read` | strongly consistent read | A DynamoDB read that includes all writes confirmed before the request |
| `time to live (TTL)` | record expiry | An attribute for background deletion of stale DynamoDB records, not a precise timer |
| `side-effect gap` | external-effect persistence gap | A failure window after the business effect but before saving `COMPLETED` |
| `exactly-once` | exactly-once execution | A desired semantic that an idempotency table alone cannot fully guarantee |

## 3. Mental Model

### 3.1. Duplicate Delivery Is Expected

Retries may happen because:

- the producer did not receive an acknowledgment and sent the event again;
- a queue redelivered a message;
- Lambda retried a failed asynchronous invocation;
- a client retried after a timeout;
- an operator replayed an event;
- two producers submitted the same business operation.

The event can therefore be delivered more than once even when every component
behaves as designed.

Without idempotency:

```text
same event twice
-> business action twice
-> two emails, charges, tickets, or deployments
```

With an idempotency record:

```text
one business operation is delivered twice
-> the first invocation acquires the claim
-> performs the processing
-> stores the result

duplicate invocation
-> does not perform the action again
-> retrieves the stored result
```

The lab does not prevent repeated Lambda invocations. It controls the business processing
performed within those invocations:

```text
duplicate delivery
-> the same event is delivered again

repeated Lambda invocation
-> the handler is invoked again

repeated business action
-> an undesirable effect that idempotency must prevent
```

### 3.2. Idempotency Key Is a Business Key

Lambda `RequestId` identifies one invocation lifecycle. It is useful for logs,
but it is not a stable identity for a business operation submitted twice.

An idempotency key should answer:

> Which operation must not be performed twice?

Examples:

- `payment-order-847-attempt-1`;
- `invoice-2026-07-customer-42`;
- `provision-environment-request-9831`;
- a stable event ID generated once by the producer.

The lab uses:

```json
{
  "idempotency_key": "report-2026-08-customer-42",
  "customer_id": "customer-42",
  "report_date": "2026-08-01"
}
```

Producer contract:

```text
the producer creates the idempotency_key once
-> stores it
-> reuses it for every retry of the same operation
```

The producer must reuse that key when retrying the same operation. A new random
key on every retry defeats idempotency.

Comparison table:

| Identifier         | What it represents                                       | Primary purpose |
| ------------------ | --------------------------------------------------------- | --------------- |
| Lambda `RequestId` | One invocation lifecycle; managed retries may preserve it | Diagnostics     |
| `idempotency_key`  | One business operation                                    | Deduplication   |
| `owner_token`      | One actual handler execution attempt                      | Claim fencing   |

### 3.3. Why Read-Then-Write Is Unsafe

The read and the write are two separate operations. Between them, another worker
may perform the same check:

```text
time ----------------------------------------------------------->

Worker A: GetItem(empty) -------- process -------- PutItem
Worker B:       GetItem(empty) -------- process -------- PutItem
```

Both workers observed absence before either wrote the record.

The lab instead begins with one conditional `PutItem`:

```text
attribute_not_exists(idempotency_key) OR expires_at < :now
```

DynamoDB evaluates the condition and write atomically for that item. Only one
concurrent attempt can establish the live claim in that indivisible operation.

Therefore, when two invocations occur concurrently:

```text
worker A
  -> conditional PutItem
  -> the condition is true
  -> the claim is created

worker B
  -> conditional PutItem
  -> the condition is now false
  -> ConditionalCheckFailedException
```

What a conditional write guarantees:

```text
guarantees:
-> only one worker successfully modifies the item under the given condition

does not guarantee:
-> that Lambda is invoked only once
-> that an external side effect is performed exactly once
-> that the worker that acquired the claim will necessarily complete
```

### 3.4. Record State

The first successful claim stores:

```text
idempotency_key = which business operation is being protected
status          = which stage the operation is currently in: IN_PROGRESS
payload_hash    = whether the payload matches the original operation
owner_token     = UUID of the handler execution attempt that owns the claim
expires_at      = until what time the claim is considered active
```

The lab generates a fresh UUID for `owner_token` every time the handler starts.
Lambda `RequestId` is logged separately for diagnostics because managed
asynchronous retries may preserve one Request ID across multiple executions.

After processing, the owner conditionally changes the record:

```text
status       = COMPLETED
result_json  = saved business result
expires_at   = completed-record retention deadline
```

The completion condition checks:

```text
status = IN_PROGRESS
AND payload_hash = expected hash
AND owner_token = current execution attempt
```

State table:

| `status`                     | Meaning                                      | What the duplicate worker does        |
| ---------------------------- | -------------------------------------------- | ------------------------------------- |
| No record                    | The operation has not yet been claimed       | Attempts to create the claim          |
| `IN_PROGRESS`, claim active  | Another worker is processing the operation   | Receives an “already in progress” error |
| `IN_PROGRESS`, claim expired | The previous worker is considered lost       | May take over the claim               |
| `COMPLETED`                  | The result has already been stored           | Returns `result_json`                 |

What is `owner_token` used for?

Imagine that worker A becomes stuck, its claim expires, and worker B takes over the key.

```text
worker A
-> acquired the claim
-> owner_token = A
-> became stuck

claim A expired

worker B
-> took over the key
-> owner_token = B
-> began a new processing attempt
```

Worker A must not later resume and overwrite worker B’s result.

```text
worker A
-> UpdateItem with the condition owner_token = A

current record
-> owner_token = B

result
-> the condition is not satisfied
-> worker A cannot overwrite worker B’s record
```

This fencing check protects the DynamoDB record; it does not stop worker A's
process or reverse an external action it already performed. The claim lifetime
must exceed normal processing time with a safe margin.

Fencing check flow:

```text
worker A’s claim expires
-> worker B reclaims the key
-> owner_token becomes B

worker A resumes
-> conditional completion checks owner_token = A
-> the condition fails
-> worker B’s result is not overwritten
```

### 3.5. Payload Hash

The same idempotency key must not silently represent two different operations.
The function hashes the canonical business payload:

```text
customer_id + report_date
-> canonical JSON
-> SHA-256
-> payload_hash
```

`idempotency_key` answers: “Is this the same operation?”

`payload_hash` verifies: “Has the data for this operation remained unchanged?”

If the key already exists but the hash differs, the function raises `IdempotencyConflict`.

```text
the same idempotency_key
+ a different payload_hash
-> this is not a replay
-> the key was used for a different operation
-> IdempotencyConflict
```

This turns accidental key reuse into a visible failure instead of returning a
result for the wrong request.

Decision table:

| Comparison                    | Meaning                          |
| ----------------------------- | -------------------------------- |
| New key                       | May attempt to create the claim  |
| Same key, same hash           | Replay of the same operation     |
| Same key, different hash      | `IdempotencyConflict`            |

### 3.6. TTL Has Two Jobs

This lab uses one `expires_at` attribute for two retention phases:

| Record state | Meaning of `expires_at` |
|---|---|
| `IN_PROGRESS` | when another worker may reclaim an abandoned claim |
| `COMPLETED` | how long duplicates may replay the saved result |

`expires_at` for `IN_PROGRESS`

When a worker acquires the claim:

```text
status = IN_PROGRESS
expires_at = now + claim_ttl_seconds
```

While the claim has not expired:

```text
status = IN_PROGRESS
+ expires_at > now
-> the claim is active
-> another worker does not receive permission to process
-> processing already in progress
```

If the claim has expired:

```text
status = IN_PROGRESS
+ expires_at < now
-> the previous worker is considered lost
-> a new worker may attempt to take over the claim
```

Takeover flow:

```text
worker A
-> created IN_PROGRESS
-> expires_at = 1000
-> became stuck

current time = 1001
-> the item still exists
-> expires_at < now

worker B
-> conditional PutItem
-> the condition succeeds
-> owner_token is replaced with B
```

`expires_at` for `COMPLETED`

After successful processing, the value changes:

```text
status = COMPLETED
result_json = stored result
expires_at = now + record_ttl_seconds
```

Now, `expires_at` determines how long a repeated request can receive a replayed result:

```text
duplicate request before expires_at
-> the COMPLETED record still exists
-> result_json is returned
-> idempotency_status = REPLAYED
```

After this period ends, the key may become available for processing again.

```text
COMPLETED expires_at < now
-> the idempotency window has ended
-> the same key may potentially be claimed again
-> the business action may be performed again
```

DynamoDB TTL deletion is asynchronous. An expired item may remain visible for
hours or days. Therefore, the claim condition explicitly treats `expires_at < now`
as reclaimable. The function does not wait for physical TTL deletion.

After a completed record's retention expires, the same key may be claimed and
processed again. `record_ttl_seconds` therefore defines the idempotency window,
not merely a storage-cleanup preference.

| Parameter            | Purpose                                                                          |
| -------------------- | -------------------------------------------------------------------------------- |
| `claim_ttl_seconds`  | Maximum duration of ownership for an active claim                                |
| `record_ttl_seconds` | Period during which a completed operation is protected from duplicate processing |

### 3.7. Idempotency Is Not the Same as Exactly-Once Execution

The general production sequence is:

```text
create an IN_PROGRESS claim
-> perform the external action
-> write COMPLETED
```

A process can fail after the external system succeeds but before DynamoDB is updated.
On recovery, the function cannot infer whether the side effect happened.

This is the **side-effect gap**.

```text
IN_PROGRESS claim
-> the external operation completes successfully
-> Lambda fails before UpdateItem(COMPLETED)
-> the record remains IN_PROGRESS
-> the claim expires
-> another worker takes over the key
-> the external operation is performed again
```

Depending on the system, the following approaches are used:

1. `Downstream idempotency key`

If the external API supports idempotency, the same business key is passed to it:

```text
Lambda idempotency_key
-> payment API idempotency key
```

On a repeated invocation, the downstream system recognizes the operation itself:

```text
payment-order-847-attempt-1
-> the first request creates the payment
-> a repeated request returns the result of the same payment
```

The key must remain stable across the entire system boundary.

2. `DynamoDB transaction`

When both the idempotency record and the business change are stored in DynamoDB, they can sometimes be performed in a single transaction:

```text
TransactWriteItems
-> modify the business record
-> write COMPLETED
```

This helps only when all required changes are within DynamoDB’s supported transactional boundary.

3. `Outbox/inbox`

The state change and the message record are written atomically in the same storage system:

```text
business transaction
-> update the state
-> write an outbox event

separate worker
-> deliver the outbox event
```

The recipient can apply inbox deduplication.

4. `Workflow with reconciliation`

The workflow stores explicit stages and, when the outcome is uncertain, checks the external system:

```text
invoke the external operation
-> the outcome is unknown
-> query the current business status
-> continue, retry, or escalate to an operator
```

5. `Business-state verification`

Before repeating an action, the system checks its actual outcome:

```text
claim expires
-> check whether the payment or report already exists
-> do not repeat the action blindly
```

The lab's `generate_report` action is deterministic and does not call another system.

Guarantee boundaries:

| Mechanism                   | What it protects                      | What it does not guarantee       |
| --------------------------- | ------------------------------------- | -------------------------------- |
| Conditional `PutItem`       | A single owner of the claim           | A single external side effect    |
| `owner_token`               | The DynamoDB item from a stale worker | Termination of the stale process |
| `COMPLETED` + `result_json` | Replay of the stored result           | Atomicity with an external API   |
| DynamoDB TTL                | Cleanup of expired records            | The exact deletion time          |
| Downstream idempotency key  | Deduplication in the external system  | A shared distributed transaction |

## 4. Lab Architecture

```text
AWS CLI synchronous invoke
        |
        v
Lambda idempotent worker
        |
        +--> conditional PutItem(IN_PROGRESS)
        |
        +--> deterministic report action
        |
        +--> conditional UpdateItem(COMPLETED)
        |
        +--> CloudWatch Logs and Errors alarm

DynamoDB on-demand table:
partition key: idempotency_key;
TTL attribute: expires_at;
billing mode: PAY_PER_REQUEST.
```

Lambda performs three main steps:

1. acquire the right to process the operation
2. execute the processor
3. store the completed result

Execution role Lambda can perform only:

```text
logs:CreateLogStream
logs:PutLogEvents
dynamodb:GetItem
dynamodb:PutItem
dynamodb:UpdateItem
```

It has no `Scan`, `Query`, `DeleteItem`, table-administration permissions, or
wildcard DynamoDB resource.

Complete interaction flow:

```text
AWS CLI
  |
  | Invoke
  v
Lambda handler
  |
  | conditional PutItem
  v
DynamoDB: IN_PROGRESS
  |
  | processor
  v
generate_report
  |
  | conditional UpdateItem
  v
DynamoDB: COMPLETED + result_json
  |
  v
Lambda response: PROCESSED
```

Component boundaries:

```text
AWS CLI
-> Initiates invocations and stores invocation evidence

Lambda
-> Validating the event and performing state machine transitions

DynamoDB
-> Claim management, status, fencing, and stored result

CloudWatch
-> Stores logs and error metrics

IAM
-> Restricts Lambda’s actions
```

## 5. Inspect the Implementation

### 5.1. Event Validation

Open:

```bash
sed -n '1,34p' ../app/lambda_function.py
```

`parse_event` rejects non-object input and missing business fields before any
claim is created.

Correct order:

```text
receive the event
-> verify that the event is a JSON object
-> validate the required business fields
-> only then access DynamoDB
```

Flow:

```text
event
  |
  v
parse_event
  |
  +-> event is not an object -----> error
  |
  +-> required field is missing -> error
  |
  v
valid business data
  |
  v
claim creation
```

### 5.2. Claim and Replay

Open:

```bash
sed -n '57,120p' ../app/lambda_function.py
```

Observe:

- conditional `put_item`;
- strongly consistent `get_item` after a rejected claim;
- payload-hash comparison;
- replay of `result_json`;
- if the record is not `COMPLETED`, treat it as active `IN_PROGRESS`.

```text
attempt to create the claim
        |
        +-> PutItem succeeds
        |   -> the current worker owns the operation
        |   -> the processor may be invoked
        |
        +-> ConditionalCheckFailed
            -> the record already exists
            -> read it using a strongly consistent GetItem
            -> determine whether this is a replay, conflict, or active claim
```

Decision table:

| Existing record             | Function decision                        |
| --------------------------- | ---------------------------------------- |
| `payload_hash` differs      | `IdempotencyConflict`                    |
| `IN_PROGRESS`, claim active | `processing already in progress` error   |
| `COMPLETED`, hash matches   | Return `result_json` as `REPLAYED`       |
| Record has expired          | A new conditional claim may take it over |

### 5.3. Completion Ownership

Open:

```bash
sed -n '122,153p' ../app/lambda_function.py
```

The following logic is especially important:

```text
processor completed
-> conditional UpdateItem
-> only the current owner can complete the claim
```

The completion update requires the original `owner_token`. This is a fencing
check for the lab's single-record state machine.

Failure behavior:

```text
any part of the ConditionExpression does not match
-> DynamoDB rejects the entire UpdateItem operation
-> the stale worker cannot modify status, result_json, or expires_at
```

## 6. Local Checks

From the repository root:

```bash
python3 -m unittest discover \
  -s lessons/81-lambda-dynamodb-idempotency/lab_81/tests -v
```

Expected result:

```text
Ran 12 tests

OK
```

The tests prove that:

- validation occurs before the claim is created;
- `payload_hash` is stable;
- the first invocation stores the result;
- a replay does not invoke the processor again;
- a payload conflict is detected;
- an active claim blocks another worker;
- an expired claim can be taken over;
- a processor error leaves the record in `IN_PROGRESS`;
- a stale `owner_token` cannot complete a claim that has been taken over;
- every handler execution receives a fresh UUID owner token;
- corrupted `result_json` is rejected.


## 7. Validate and Deploy Terraform

```bash
cd lessons/81-lambda-dynamodb-idempotency/lab_81/terraform
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform fmt -check -recursive
terraform validate
terraform test
```

The four native tests verify:

1. DynamoDB
   -> string partition key
   -> `PAY_PER_REQUEST`
   -> TTL based on `expires_at`

2. Lambda
   -> receives the exact table name
   -> receives the claim TTL and record TTL settings

3. Observability
   -> log retention is limited
   -> error monitoring is configured

4. TTL overrides
   -> valid values are passed to the function environment

Authenticate before Terraform reads AWS data or creates a plan:

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
export FUNCTION_NAME="$(terraform output -raw function_name)"
export TABLE_NAME="$(terraform output -raw idempotency_table_name)"
export AWS_REGION="$(terraform output -raw aws_region)"
export LOG_GROUP="/aws/lambda/${FUNCTION_NAME}"

printf 'function=%s\ntable=%s\nregion=%s\nlog_group=%s\n' \
  "$FUNCTION_NAME" "$TABLE_NAME" "$AWS_REGION" "$LOG_GROUP"
```

## 8. First Invocation: Claim and Complete

Evidence chain for the first invocation:

```text
Invoke metadata without FunctionError
-> the handler completed successfully

response = PROCESSED
-> the invocation followed the new claim path

DynamoDB status = COMPLETED
-> the claim was actually completed

result_json is present
-> the result was stored for replay
```

Move to the lab root:

```bash
cd ..
```

Invoke the function synchronously:

```bash
./scripts/invoke-sync.sh \
  "$FUNCTION_NAME" \
  "$AWS_REGION" \
  events/report.json \
  evidence/first-metadata.json \
  evidence/first-response.json
```

Inspect both files:

```bash
jq . evidence/first-metadata.json
jq . evidence/first-response.json
```

Expected response shape:

```json
{
  "report_id": "12-character-id",
  "customer_id": "customer-42",
  "report_date": "2026-08-01",
  "status": "generated",
  "idempotency_status": "PROCESSED"
}
```

A successful Invoke API call proves:

```text
AWS CLI
-> located the Lambda function
-> Lambda accepted the synchronous invocation
-> the handler completed without an unhandled error
```

The exact `report_id` is deterministic for the key.

Inspect the DynamoDB item:

```bash
./scripts/inspect-record.sh \
  "$TABLE_NAME" \
  "$AWS_REGION" \
  report-2026-08-customer-42 \
  evidence/first-record.json
```

Verify selected fields:

```bash
jq '{
  idempotency_key: .Item.idempotency_key.S,
  status: .Item.status.S,
  payload_hash: .Item.payload_hash.S,
  owner_token: .Item.owner_token.S,
  expires_at: .Item.expires_at.N,
  result_json: (.Item.result_json.S | fromjson)
}' evidence/first-record.json
```

Expected:

```text
status = COMPLETED
result_json.idempotency data represents one saved business result
```

## 9. Duplicate Invocation: Replay

Invoke the exact same event again:

```bash
./scripts/invoke-sync.sh \
  "$FUNCTION_NAME" \
  "$AWS_REGION" \
  events/report.json \
  evidence/replay-metadata.json \
  evidence/replay-response.json
```

The second invocation must follow a different path:

```text
conditional PutItem
-> ConditionExpression is not satisfied
-> the claim is rejected
-> strongly consistent GetItem
-> payload_hash matches
-> status = COMPLETED
-> return the stored result_json
-> idempotency_status = REPLAYED
```

Inspect the response:

```bash
jq . evidence/replay-response.json
```

Expected:

```text
same report_id
idempotency_status = REPLAYED
```

Check the metadata and explicitly compare the two responses:

```bash
jq -s '{
  first_report_id: .[0].report_id,
  replay_report_id: .[1].report_id,
  same_report_id: (.[0].report_id == .[1].report_id),
  first_status: .[0].idempotency_status,
  replay_status: .[1].idempotency_status
}' \
  evidence/first-response.json \
  evidence/replay-response.json
```

The second invocation ran the handler, but it did not run
`generate_report` again. It returned the stored `result_json`.

Inspect application logs:

```bash
aws logs tail "$LOG_GROUP" \
  --region "$AWS_REGION" \
  --since 10m \
  --format short
```

Look for:

```text
idempotency_claimed
idempotency_completed
idempotency_replay
```

There should be one claim/completion pair and one replay for this sequence.
These are two separate synchronous Invoke API calls, so their `RequestId`
values should differ. Each handler execution also has its own `owner_token`.

Complete evidence chain for the replay:

```text
first RequestId
-> idempotency_claimed
-> idempotency_completed
-> DynamoDB status = COMPLETED
-> result_json stored
-> response = PROCESSED

second RequestId
-> idempotency_replay
-> same report_id
-> response = REPLAYED
```

## 10. Conflicting Payload

`events/conflicting-report.json` deliberately reuses the same key with a different `customer_id`.

Invoke it:

```bash
./scripts/invoke-sync.sh \
  "$FUNCTION_NAME" \
  "$AWS_REGION" \
  events/conflicting-report.json \
  evidence/conflict-metadata.json \
  evidence/conflict-response.json
```

AWS CLI can exit successfully because the Lambda Invoke API itself succeeded.
Check the invocation metadata:

```bash
jq . evidence/conflict-metadata.json
jq . evidence/conflict-response.json
```

Expected:

```text
FunctionError = Unhandled
errorMessage contains "already used for another payload"
```

This is not a harmless duplicate. It is a broken producer contract and should remain visible.

## 11. Practical Drills

### Drill 1. Invalid Event Contract

The `events/invalid.json` file does not contain the required `report_date` field.

Invoke the event missing `report_date`:

```bash
./scripts/invoke-sync.sh \
  "$FUNCTION_NAME" \
  "$AWS_REGION" \
  events/invalid.json \
  evidence/invalid-metadata.json \
  evidence/invalid-response.json

jq . evidence/invalid-metadata.json
jq . evidence/invalid-response.json
```

Expected flow:

```text
invalid event
-> parse_event detects the missing report_date field
-> the handler terminates with an error
-> conditional PutItem is not called
-> no DynamoDB item is created
```

Confirm:

- Lambda returned `FunctionError`, which means the Invoke API call succeeded, but the function code rejected the event;
- no record was created for `report-invalid-001`, confirming that the error occurred during Python validation rather than in DynamoDB or IAM;
- data validation occurs before claim creation.

Check absence:

```bash
./scripts/inspect-record.sh \
  "$TABLE_NAME" \
  "$AWS_REGION" \
  report-invalid-001 \
  evidence/invalid-record.json

jq '.Item // "record absent"' evidence/invalid-record.json
```

### Drill 2. Active Claim

Create a new event:

```bash
jq '.idempotency_key = "report-active-claim-001"' \
  events/report.json > /tmp/lab81-active.json
```

Calculate the canonical `payload_hash`; the handler hashes only `customer_id` and `report_date`:

```bash
payload_json="$(jq -cS '{customer_id,report_date}' /tmp/lab81-active.json)"
payload_digest="$(printf '%s' "$payload_json" | sha256sum | awk '{print $1}')"
now_epoch="$(date +%s)"
claim_expires_at="$((now_epoch + 300))"
```

Check the local values:

```bash
printf 'payload=%s\nhash=%s\nnow=%s\nexpires=%s\n' \
  "$payload_json" \
  "$payload_digest" \
  "$now_epoch" \
  "$claim_expires_at"
```

Insert a simulated live claim:

```bash
aws dynamodb put-item \
  --table-name "$TABLE_NAME" \
  --region "$AWS_REGION" \
  --item "$(jq -cn \
    --arg key "report-active-claim-001" \
    --arg digest "$payload_digest" \
    --arg owner "simulated-other-worker" \
    --argjson now "$now_epoch" \
    --argjson expires "$claim_expires_at" \
    '{
      idempotency_key: {S: $key},
      status: {S: "IN_PROGRESS"},
      payload_hash: {S: $digest},
      owner_token: {S: $owner},
      created_at: {N: ($now | tostring)},
      updated_at: {N: ($now | tostring)},
      expires_at: {N: ($expires | tostring)}
    }')"
```

Directly inspect the DynamoDB item immediately after `put-item`:

```bash
./scripts/inspect-record.sh \
  "$TABLE_NAME" \
  "$AWS_REGION" \
  report-active-claim-001 \
  evidence/active-record-before-invoke.json
jq '{
  status: .Item.status.S,
  payload_hash: .Item.payload_hash.S,
  owner_token: .Item.owner_token.S,
  expires_at: .Item.expires_at.N,
  result_json: (.Item.result_json.S // null)
}' evidence/active-record-before-invoke.json
```

Invoke the matching event:

```bash
./scripts/invoke-sync.sh \
  "$FUNCTION_NAME" \
  "$AWS_REGION" \
  /tmp/lab81-active.json \
  evidence/active-metadata.json \
  evidence/active-response.json

jq . evidence/active-metadata.json
jq . evidence/active-response.json
```

Expected flow:

```text
manual PutItem
-> an active IN_PROGRESS record already exists

Lambda
-> conditional PutItem is rejected
-> strongly consistent GetItem
-> payload_hash matches
-> status is not COMPLETED
-> IdempotencyInProgress
-> the processor is not invoked
```

Interpretation:

```text
StatusCode = 200
-> the Invoke API successfully invoked the Lambda function

FunctionError = Unhandled
-> the handler terminated with an error

processing already in progress
-> the existing payload_hash matches
-> the record was not COMPLETED
-> Lambda did not acquire the right to process the operation
```

| Step               | Layer                   | What it proves                                      |
| ------------------ | ----------------------- | --------------------------------------------------- |
| Create a new event | `jq` / local file       | A separate `idempotency_key` is used                |
| Calculate the hash | Shell / Python contract | The hash matches the handler algorithm              |
| `put-item`         | DynamoDB                | An active claim owned by another worker was created |
| Invoke metadata    | Lambda Invoke API       | The handler completed with an error                 |
| Response payload   | Python / Lambda         | The error relates to active processing              |

Expected:

```text
FunctionError = Unhandled
processing already in progress
```

The second worker must not process concurrently.

Flow:

```text
simulated worker
-> PutItem(IN_PROGRESS)
-> owner_token = simulated-other-worker
-> expires_at = now + 300

Lambda worker
-> conditional PutItem
-> ConditionalCheckFailed
-> strongly consistent GetItem
-> payload_hash matches
-> processing already in progress
```

### Drill 3. Reclaim an Expired Claim

Flow:

```text
stale claim
-> status = IN_PROGRESS
-> expires_at < now
-> the item still exists

new Lambda invocation
-> conditional PutItem is allowed
-> owner_token is replaced
-> the processor is invoked
-> the record becomes COMPLETED
```

Expire the simulated record:

```bash
expired_epoch="$(( $(date +%s) - 1 ))"

aws dynamodb update-item \
  --table-name "$TABLE_NAME" \
  --region "$AWS_REGION" \
  --key '{"idempotency_key":{"S":"report-active-claim-001"}}' \
  --update-expression 'SET expires_at = :expired' \
  --expression-attribute-values \
    "{\":expired\":{\"N\":\"${expired_epoch}\"}}"
```

A physically existing but logically expired item can be taken over,
do not wait for DynamoDB TTL deletion. Invoke immediately:

```bash
./scripts/invoke-sync.sh \
  "$FUNCTION_NAME" \
  "$AWS_REGION" \
  /tmp/lab81-active.json \
  evidence/reclaimed-metadata.json \
  evidence/reclaimed-response.json

jq . evidence/reclaimed-response.json
```

Expected:

```text
StatusCode = 200
idempotency_status = PROCESSED
```

Inspect the new owner:

```bash
./scripts/inspect-record.sh \
  "$TABLE_NAME" \
  "$AWS_REGION" \
  report-active-claim-001 \
  evidence/reclaimed-record.json

jq '{
  status: .Item.status.S,
  owner: .Item.owner_token.S,
  expires_at: .Item.expires_at.N
}' evidence/reclaimed-record.json
```

The owner must no longer be `simulated-other-worker`.

Expected:

```text
status = COMPLETED
owner_token != simulated-other-worker
result_json is stored
```

Expected sequence:

```text
expires_at is set to a past timestamp
-> the stale record still exists physically
-> the new conditional PutItem succeeds
-> the new worker receives the owner_token
-> the processor is invoked
-> status becomes COMPLETED
-> result_json is stored
```

### Drill 4. Explain the Side-Effect Gap

Do not break the live function. Analyze this sequence:

```text
1. claim IN_PROGRESS
2. external payment succeeds
3. process crashes before COMPLETED
4. claim expires
5. another invocation reclaims the key
6. the payment may be processed more than once
```

Flow:

```text
claim IN_PROGRESS
-> payment API: success
-> Lambda crashes
-> COMPLETED is not recorded
-> expires_at < now
-> a new worker acquires the claim
-> invokes the payment API again
```

A `side-effect gap` is the gap between a successful external action and recording its result in DynamoDB.

Table of ambiguous states:

| DynamoDB      | External system                      | What is known                       |
| ------------- | ------------------------------------ | ----------------------------------- |
| `IN_PROGRESS` | The operation was not performed      | DynamoDB alone does not prove this  |
| `IN_PROGRESS` | The operation completed successfully | A side-effect gap may have occurred |
| `COMPLETED`   | The result was stored                | The local state machine completed   |

Expected model:

- DynamoDB cannot infer an external side effect;
- unconditional claim deletion can enable duplicate effects;
- the same business idempotency key should cross the downstream boundary;
- uncertain outcomes require domain-specific reconciliation.

Mechanism boundaries:

```text
conditional PutItem
-> protects claim acquisition

owner_token
-> protects the DynamoDB item from a stale worker

both mechanisms
!= prove the state of the external payment
!= reverse a completed payment
!= guarantee exactly-once execution
```

For an external API, end-to-end idempotency is preferred:

```text
Lambda business key
-> pass it to the payment API as the idempotency key
-> retry the request using the same key
-> the payment API returns the result of the previous operation
```

## 12. Metrics and Cost

Inspect the alarm:

```bash
export ALARM_NAME="$(
  terraform -chdir=terraform output -raw function_errors_alarm_name
)"

aws cloudwatch describe-alarms \
  --region "$AWS_REGION" \
  --alarm-names "$ALARM_NAME" \
  --query 'MetricAlarms[0].[AlarmName,StateValue,StateReason]' \
  --output table
```

Field interpretation:

```text
AlarmName
-> verifies that the correct lab alarm is being inspected

StateValue
-> OK, ALARM, or INSUFFICIENT_DATA

StateReason
-> explains why CloudWatch set the current state
```

Conflict and active-claim drills intentionally produce Lambda errors, so the
alarm may enter `ALARM` after CloudWatch publishes the datapoint.

### DynamoDB `PAY_PER_REQUEST`

The table uses the `PAY_PER_REQUEST` billing mode. Throughput is not provisioned in advance; cost depends on the read and write operations actually performed.

This mode is appropriate for the lab because the workload is small and irregular:

```text
no constant workload
-> no need to configure RCU/WCU
-> pay only for actual requests
```

The idempotency state machine operations also consume DynamoDB resources:

```text
first invocation
-> PutItem(IN_PROGRESS)
-> UpdateItem(COMPLETED)

replay, conflict, or active claim
-> rejected conditional PutItem
-> strongly consistent GetItem
```

Cost is affected by:

- the number of invocations and redeliveries;
- the size of the DynamoDB item, including `result_json`;
- the use of strongly consistent reads;
- the retention period for completed records;
- backups and cross-region replication.

## 13. Troubleshooting

### `No valid credential sources found`

Authenticate the same profile used by Terraform and AWS CLI:

```bash
export AWS_PROFILE=YOUR_PROFILE
aws sso login --profile "$AWS_PROFILE"
aws sts get-caller-identity
```

### `AccessDeniedException` for DynamoDB

This error means:

```text
Lambda handler
-> attempts a DynamoDB operation
-> the execution role does not have the required permission
-> DynamoDB rejects the request
```

Check the function execution role and inline policy:

```bash
terraform -chdir=terraform output -raw function_execution_role_arn
terraform -chdir=terraform output -raw function_runtime_policy_name
```

The role needs item operations on the exact table ARN.

### Duplicate Returns `IN_PROGRESS`

```text
worker A
-> acquired the claim
-> status = IN_PROGRESS
-> is still executing the processor

worker B
-> conditional PutItem is rejected
-> reads IN_PROGRESS
-> processing already in progress
```

Possible causes:

- the first invocation is still running;
- it failed after claiming;
- the claim TTL is too long for recovery expectations;
- the processor duration is too close to or longer than claim TTL.

Before modifying or deleting the record, check:

- the DynamoDB item itself;
- the `expires_at` timestamp;
- the `owner_token`;
- the first worker’s CloudWatch Logs.

Use the inspection script:

```bash
./scripts/inspect-record.sh \
  "$TABLE_NAME" \
  "$AWS_REGION" \
  <IDEMPOTENCY_KEY> \
  evidence/in-progress-diagnostic-record.json
```

Use the following exact command for the logs:

```bash
aws logs tail "$LOG_GROUP" \
  --region "$AWS_REGION" \
  --since 60m \
  --format short
```

If healthy processing can outlive the claim, another worker may enter the business section.
The owner token prevents a stale completion write, but it cannot undo duplicate external work.

### Expired Item Is Still Visible

This is normal DynamoDB TTL behavior. DynamoDB TTL deletes expired items asynchronously. Application
logic must evaluate expiry; it must not depend on immediate physical deletion.

- `expires_at` -> the application’s logical decision
- DynamoDB TTL -> asynchronous physical cleanup

Flow:

```text
item exists
-> expires_at > now
   -> the record is still valid

-> expires_at < now
   -> the record has logically expired
   -> TTL may not have deleted it yet
   -> the application applies reclaim logic
```

### Duplicate Produces a Conflict

Compare the business data. The same key was used with a different payload.

```text
same idempotency_key
+ different payload_hash
-> the function treats the request as a different business operation
```

Problematic flow:

```text
first request
-> key = report-2026-08-customer-42
-> payload = customer-42 + 2026-08-01
-> payload_hash = A
-> COMPLETED

repeated request
-> same key
-> customer_id or report_date changed
-> payload_hash = B

A != B
-> IdempotencyConflict
```

Fix the producer contract instead of bypassing the payload hash check.

```text
this is a retry of the same operation
-> restore the original business data
-> use the existing idempotency_key

this is a new operation
-> generate a new idempotency_key
```

Diagnostic flow:

```text
IdempotencyConflict received
-> compare the payloads of the first and repeated events
-> determine whether they represent the same business operation

yes, the same operation
-> the producer incorrectly changed the payload

no, different operations
-> the producer incorrectly reused the old key
```

Decision table:

| Situation                                                         | Correct action                                 |
| ----------------------------------------------------------------- | ---------------------------------------------- |
| Retry of the same operation, but the payload changed accidentally | Fix the producer and send the original payload |
| A new operation used an old key                                   | Create a new business key                      |
| The old `result_json` does not match the new request              | Do not return it                               |
| The hash conflicts because an important field changed             | Review the canonical payload fields            |

### Saved Result Cannot Be Decoded

A `COMPLETED` record without valid `result_json` is corrupted or from an incompatible schema version.

Flow:

```text
claim rejected
-> GetItem
-> payload_hash matches
-> status = COMPLETED
-> read result_json

result_json is valid
-> REPLAYED

result_json is missing or corrupted
-> RuntimeError
-> the stored result is not returned
-> the processor is not invoked again
```

### Alarm Remains `OK`

CloudWatch metrics are not instantaneous. Wait for the metric period, then
inspect:

```bash
aws logs tail "$LOG_GROUP" \
  --region "$AWS_REGION" \
  --since 60m \
  --format short
```

Flow:

```text
specific invocation
-> FunctionError = Unhandled

after some time
-> Lambda Errors datapoint

CloudWatch alarm
-> compares the datapoint with the threshold
-> OK or ALARM
```

## 14. Completion Check

Before cleanup, confirm that:

- 12 local Python tests pass;
- 4 Terraform native tests pass;
- first invocation returns `PROCESSED`;
- duplicate returns `REPLAYED` with the same `report_id`;
- conflict returns a visible function error;
- invalid input creates no record;
- a live claim blocks another worker;
- an expired claim can be reclaimed before TTL physically deletes it;
- runtime IAM is scoped to one table;
- you can explain the side-effect gap.

## 15. Cleanup

Return to the Terraform root:

```bash
cd terraform
```

Create and inspect an exact destroy plan:

```bash
terraform plan -destroy -out=tfplan-destroy
terraform show tfplan-destroy
terraform apply tfplan-destroy
```

Confirm the state is empty:

```bash
terraform state list
```

The command should print no managed resources.

## 16. Final Model

Keep these statements:

1. Duplicate delivery is normal; idempotent consumers are a design requirement.
2. The key identifies a business operation, not an individual invocation.
3. Conditional `PutItem` removes the read-then-write race.
4. `payload_hash` prevents unsafe key reuse.
5. `owner_token` prevents a stale worker from completing a reclaimed claim.
6. A strong read is useful immediately after a rejected claim.
7. TTL is asynchronous retention cleanup, not a precise lock timer.
8. An idempotency table does not make external side effects atomic.

## 17. Official References

- [AWS Lambda best practices](https://docs.aws.amazon.com/lambda/latest/dg/best-practices.html)
- [DynamoDB condition expressions](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/Expressions.OperatorsAndFunctions.html)
- [DynamoDB read consistency](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/HowItWorks.ReadConsistency.html)
- [DynamoDB TTL](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/TTL.html)
- [Working with expired DynamoDB items](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/ttl-expired-items.html)
