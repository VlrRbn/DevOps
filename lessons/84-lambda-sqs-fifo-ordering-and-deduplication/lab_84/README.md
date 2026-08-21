# Lesson 84: Lambda SQS FIFO Worker

This lab connects one FIFO source queue to Lambda and uses explicit
`MessageGroupId` and `MessageDeduplicationId` values. The handler processes a
batch in order, stops after the first failure, and returns both the failed record
and every record it intentionally left unprocessed.

## Runtime Model

| Control | Scope | Lab default | Effect |
|---|---|---:|---|
| FIFO ordering | One message group | Enabled | Records in the same group do not run concurrently |
| Message groups | Entire source queue | Chosen by producer | Different groups can run in parallel |
| Explicit deduplication ID | FIFO queue, five-minute window | Required | Repeated send is accepted but not delivered again in the window |
| `BatchSize` | Event source mapping | `5` | Exposes the stop-after-first-failure contract |
| `MaximumConcurrency` | Event source mapping | `4` | Source can invoke at most four concurrent workers |
| Reserved concurrency | Entire function | `null` | Does not consume training-account reservation by default |
| Function timeout | One invocation | `6s` | Bounds one batch attempt |
| Visibility timeout | Source queue | `40s` | Covers processing and retry behavior |

## Layout

```text
lab_84/
├── app/
│   └── lambda_function.py
├── events/
│   ├── failure-batch.json
│   ├── invalid-batch.json
│   └── success-batch.json
├── evidence/
│   └── .gitkeep
├── scripts/
│   ├── send-dedup-pair.sh
│   └── send-fifo-sequence.sh
├── tests/
│   └── test_lambda_function.py
└── terraform/
    ├── tests/
    │   └── sqs_fifo.tftest.hcl
    ├── event_source_mapping.tf
    ├── function_execution_role.tf
    ├── lambda.tf
    ├── locals.tf
    ├── monitoring.tf
    ├── outputs.tf
    ├── package.tf
    ├── providers.tf
    ├── queues.tf
    ├── terraform.tfvars.example
    ├── variables.tf
    └── versions.tf
```

## Important Boundaries

- FIFO ordering is per `MessageGroupId`, not a global queue lock.
- Lambda concurrency is bounded by active message groups, mapping maximum
  concurrency, function/account capacity, and current demand.
- A FIFO source queue must use a FIFO DLQ.
- FIFO queues do not support `MaximumBatchingWindowInSeconds`.
- Deduplication suppresses duplicate sends; it does not replace consumer
  idempotency after a message has been delivered.
- With `ReportBatchItemFailures`, the handler stops after the first failure and
  returns failed plus unprocessed record IDs to preserve order.
- SQS increments the receive count of every returned record. With a multi-record
  FIFO batch, a valid deferred tail record can therefore reach the DLQ together
  with the poison record. `BatchSize = 1` avoids this collateral DLQ movement at
  the cost of batching efficiency.
- The execution role can consume only the source queue and cannot read the DLQ.
