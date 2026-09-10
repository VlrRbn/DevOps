# Lesson 86: EventBridge Routing Lab

This lab deploys two isolated asynchronous branches behind one custom EventBridge
bus. The audit rule accepts created and refunded orders. The high-value rule
accepts only created orders whose numeric `detail.amount` is at least `100`.

## Runtime Model

```text
aws events put-events
  -> custom event bus
     -> audit rule
        -> audit source SQS -> audit Lambda -> processing DLQ
        -> delivery DLQ when EventBridge cannot send to source SQS
     -> high-value rule
        -> high-value source SQS -> high-value Lambda -> processing DLQ
        -> delivery DLQ when EventBridge cannot send to source SQS
```

The functions share one code package but have separate execution roles, log
groups, source queues, event source mappings, concurrency limits, and DLQs.

## Layout

```text
lab_86/
├── app/
│   └── lambda_function.py
├── events/
│   ├── order-created-high-value.json
│   ├── order-created-low-value.json
│   ├── order-refunded.json
│   └── wrong-source.json
├── evidence/
├── patterns/
│   ├── audit.json
│   └── high-value.json
├── scripts/
│   └── put-event.sh
├── tests/
│   └── test_lambda_function.py
└── terraform/
    ├── event_source_mappings.tf
    ├── eventbridge.tf
    ├── function_execution_roles.tf
    ├── functions.tf
    ├── locals.tf
    ├── monitoring.tf
    ├── outputs.tf
    ├── package.tf
    ├── providers.tf
    ├── queues.tf
    ├── terraform.tfvars.example
    ├── tests/routing.tftest.hcl
    ├── variables.tf
    └── versions.tf
```

## Important Boundaries

- A rule matches the fields it declares and ignores unspecified fields.
- EventBridge string matching is exact; `Order Created` and `order.created` differ.
- The high-value pattern expects a JSON number, not the string `"150"`.
- One event may match zero, one, or both rules.
- A successful `PutEvents` call proves ingestion, not rule matching or consumer completion.
- A delivery DLQ belongs to an EventBridge target and captures target-delivery failures.
- A processing DLQ belongs to an SQS source queue and captures exhausted consumer failures.
- Standard SQS partial batch handling returns only failed message IDs.
- Direct writes to source queues are denied so callers cannot bypass EventBridge routing.
