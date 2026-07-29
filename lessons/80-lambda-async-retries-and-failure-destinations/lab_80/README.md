# Lesson 80: Lambda Asynchronous Invocation, Retries, and Failure Destinations

This lab demonstrates Lambda-managed asynchronous invocation, one bounded retry,
and an SQS on-failure destination.

## Runtime Model

| Stage | What it proves | What it does not prove |
|---|---|---|
| AWS CLI returns `202` | Lambda accepted the event | The handler succeeded |
| Log contains `async_event_processed` | One handler attempt reached the success path | The event was processed exactly once |
| `Errors` metric increases | A handler attempt failed | The destination received the record |
| SQS contains an invocation record | Retry processing ended and delivery succeeded | The original business action is safe to replay |

The configured `maximum_retry_attempts = 1` means at most two handler attempts:
the initial attempt and one retry.

## Layout

```text
lab_80/
├── app/
│   └── lambda_function.py
├── events/
│   ├── failure.json
│   ├── invalid.json
│   └── success.json
├── evidence/
│   └── .gitkeep
├── scripts/
│   ├── invoke-async.sh
│   └── receive-failure.sh
├── tests/
│   └── test_lambda_function.py
└── terraform/
    ├── tests/
    │   └── async_delivery.tftest.hcl
    ├── .gitignore
    ├── async_invoke.tf
    ├── failure_destination.tf
    ├── function_execution_role.tf
    ├── lambda.tf
    ├── locals.tf
    ├── monitoring.tf
    ├── outputs.tf
    ├── package.tf
    ├── providers.tf
    ├── terraform.tfvars.example
    ├── variables.tf
    └── versions.tf
```

## Important Distinction

The SQS queue is a Lambda **destination**, not an SQS event source for the
function. Lambda publishes a failure invocation record to it only after
asynchronous processing ends unsuccessfully.

`receive-failure.sh` selects a destination record by `event_id` and receives it
without deleting. Delete or purge messages only after inspection, and only when
the exact target queue has been verified.
