# Lesson 83: Lambda SQS Scaling Worker

The lab creates a standard SQS queue and one Lambda event source mapping with
`MaximumConcurrency = 2`. Each message asks the worker to wait for a bounded
number of seconds, making the relationship between concurrency and backlog
visible without calling an external dependency.

## Runtime Model

| Control | Scope | Lab default | Effect |
|---|---|---:|---|
| `BatchSize` | Event source mapping | `1` | One work item per Lambda invocation |
| `MaximumConcurrency` | Event source mapping | `2` | This queue can use at most two concurrent invocations |
| Reserved concurrency | Entire function | `null` | Function uses available unreserved account concurrency |
| Function timeout | One invocation | `15s` | Bounds one work item attempt |
| Visibility timeout | Source queue | `95s` | Covers processing and throttling retries |

## Layout

```text
lab_83/
├── app/
│   └── lambda_function.py
├── events/
│   ├── fast-work-item.json
│   ├── invalid-work-item.json
│   └── work-item.json
├── evidence/
│   └── .gitkeep
├── scripts/
│   ├── sample-backlog.sh
│   └── send-burst.sh
├── tests/
│   └── test_lambda_function.py
└── terraform/
    ├── tests/
    │   └── sqs_scaling.tftest.hcl
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

- Mapping maximum concurrency limits only this SQS source.
- Reserved concurrency limits every event source and direct invocation of the
  function. It also removes capacity from the regional unreserved pool.
- Reserved concurrency does not pre-initialize environments and does not remove
  cold starts. That is a different feature from provisioned concurrency.
- Backpressure is not automatically an error. It is an intentional rate mismatch
  that must remain within queue-age and business-latency objectives.
- SQS depth attributes are approximate. Correlate them with Lambda metrics and logs.
- `sample-backlog.sh` calls only `GetQueueAttributes`; it does not compete with
  the Lambda poller.
