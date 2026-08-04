# Lesson 81: Lambda and DynamoDB Idempotency

This lab implements a small `IN_PROGRESS -> COMPLETED` state machine around a
deterministic report-generation action.

## Runtime Model

| Situation | DynamoDB decision | Handler result |
|---|---|---|
| First key use | conditional `PutItem` creates `IN_PROGRESS` | process once and save `COMPLETED` |
| Same key and same payload after completion | claim is rejected, saved result is read | return `REPLAYED` |
| Same key and different payload | payload hash differs | fail with `IdempotencyConflict` |
| Same key while claim is active | record remains `IN_PROGRESS` | fail with `IdempotencyInProgress` |
| Same key after claim expiry | conditional write replaces expired claim | new owner may process |

The completion update checks `status`, `payload_hash`, and `owner_token`.
`owner_token` is a fresh UUID for one handler execution attempt, while Lambda
`RequestId` remains diagnostic metadata. Therefore, an old attempt cannot
complete a claim that a newer attempt has already reclaimed.

## Layout

```text
lab_81/
├── app/
│   └── lambda_function.py
├── events/
│   ├── conflicting-report.json
│   ├── invalid.json
│   └── report.json
├── evidence/
│   └── .gitkeep
├── scripts/
│   ├── inspect-record.sh
│   └── invoke-sync.sh
├── tests/
│   └── test_lambda_function.py
└── terraform/
    ├── tests/
    │   └── idempotency.tftest.hcl
    ├── function_execution_role.tf
    ├── idempotency_table.tf
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

## Important Boundaries

- DynamoDB TTL is asynchronous cleanup, not an exact timer.
- A strong `GetItem` read is used immediately after a rejected claim.
- The idempotency key must identify one business operation, not one transport
  attempt.
- A conditional claim does not atomically include an external side effect.
  Production payment or provisioning flows need an idempotent downstream API,
  a transaction where possible, or an outbox/workflow design.
