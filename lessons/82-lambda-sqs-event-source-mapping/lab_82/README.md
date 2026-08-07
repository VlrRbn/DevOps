# Lesson 82: Lambda SQS Batch Consumer

This lab connects a standard SQS source queue to Lambda through an event source
mapping and enables `ReportBatchItemFailures`.

## Runtime Model

| Situation | Handler response | Queue result |
|---|---|---|
| Every record succeeds | Empty `batchItemFailures` | Lambda deletes the batch |
| One record fails | Failed `messageId` is returned | Only that message is retried |
| Handler throws | Invocation error | The whole batch is retried |
| Receive budget is exhausted | The record keeps failing | SQS moves it to the DLQ |
| Successful record is delivered again | It may run again | Business code still needs idempotency |

## Layout

```text
lab_82/
├── app/
│   └── lambda_function.py
├── events/
│   ├── invalid-batch-event.json
│   ├── invalid-message.json
│   ├── poison-message.json
│   └── success-message.json
├── evidence/
│   └── .gitkeep
├── scripts/
│   ├── inspect-queue.sh
│   ├── receive-messages.sh
│   └── send-message.sh
├── tests/
│   └── test_lambda_function.py
└── terraform/
    ├── tests/
    │   └── sqs_consumer.tftest.hcl
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

- Lambda polls SQS and invokes the function synchronously with a batch. This is
  not Lambda's managed asynchronous invocation queue from lesson 80.
- `ReportBatchItemFailures` works only when both the event source mapping and the
  handler response use the expected contract.
- A returned item failure is not necessarily a Lambda `Errors` datapoint because
  the handler completed normally.
- Visibility timeout hides received messages; it does not delete them.
- The source queue redrive policy moves repeatedly failed records to the DLQ.
- Partial batch response reduces unnecessary retries but does not provide
  exactly-once processing. Use the idempotency pattern from lesson 81 around real
  side effects.
