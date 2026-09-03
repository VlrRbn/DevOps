# Lesson 85: SNS-to-SQS Fan-out

This lab deploys two isolated asynchronous consumer branches behind one SNS
topic. The audit branch receives every valid published event. The billing branch
receives only the event types allowed by its subscription filter policy.

## Runtime Model

```text
aws sns publish
  -> encrypted standard SNS topic
     -> raw audit subscription
        -> encrypted standard SQS queue
        -> audit Lambda
        -> audit DLQ on exhausted failures
     -> raw billing subscription with MessageAttributes filter
        -> encrypted standard SQS queue
        -> billing Lambda
        -> billing DLQ on exhausted failures
```

The two functions use the same code package but separate execution roles, log
groups, source queues, event source mappings, concurrency limits, and DLQs.

## Layout

```text
lab_85/
├── app/
│   └── lambda_function.py
├── events/
│   ├── mixed-batch.json
│   └── success-batch.json
├── evidence/
├── scripts/
│   └── publish-event.sh
├── tests/
│   └── test_lambda_function.py
└── terraform/
    ├── event_source_mappings.tf
    ├── function_execution_roles.tf
    ├── functions.tf
    ├── locals.tf
    ├── monitoring.tf
    ├── outputs.tf
    ├── package.tf
    ├── providers.tf
    ├── queues.tf
    ├── terraform.tfvars.example
    ├── tests/fanout.tftest.hcl
    ├── topic.tf
    ├── variables.tf
    └── versions.tf
```

## Important Boundaries

- SNS fan-out creates independent copies; consumers do not share one queue message.
- The audit subscription has no filter and receives every topic publication.
- The billing filter uses the `event_type` SNS message attribute.
- `raw_message_delivery = true` puts the original JSON in the SQS body instead
  of wrapping it in the SNS notification envelope.
- Filter policy updates are eventually consistent and can take up to 15 minutes.
- A source queue explicitly denies sends that do not originate from the lesson topic.
- Standard SQS partial batch handling continues after one record fails and returns
  only failed record IDs; this differs from the FIFO barrier in lesson 84.
- One branch failure does not roll back or cancel delivery to another branch.
