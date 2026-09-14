# Lesson 87: HTTP API Lab

This lab deploys a regional API Gateway HTTP API and one Lambda function.
The `$default` stage exposes the API without a stage suffix in its URL.

## Runtime Model

```text
GET /health  -> public route ------+
                                  +-> Lambda -> JSON HTTP response
POST /quotes -> IAM + SigV4 route -+

caller IAM policy -> execute-api:Invoke on POST /quotes
Lambda resource policy -> API Gateway may invoke these exact routes
Lambda execution role -> write function logs only
```

`POST /quotes` accepts integer `unit_price_cents` and `quantity` and returns
`total_cents` in EUR. This is a calculator, not an order/payment API: the client
supplies the price, and no business state is stored.

## Layout

lab_87/
├── app/
│   └── lambda_function.py
├── events/
│   ├── health-v2.json
│   └── quote-v2.json
├── requests/
│   ├── invalid-quote.json
│   └── quote.json
├── evidence/
├── scripts/
│   └── invoke-api.sh
├── tests/
│   ├── test_invoke_api.py
│   └── test_lambda_function.py
└── terraform/
    ├── api_invoke_permissions.tf
    ├── function.tf
    ├── function_execution_role.tf
    ├── http_api.tf
    ├── locals.tf
    ├── monitoring.tf
    ├── outputs.tf
    ├── package.tf
    ├── providers.tf
    ├── terraform.tfvars.example
    ├── tests/
    │   └── http_api.tftest.hcl
    ├── variables.tf
    └── versions.tf

## Important Boundaries

- Send files from `requests/` as HTTP bodies. Files in `events/` represent the
  envelope API Gateway supplies to Lambda and are used by local tests.
- Direct handler tests cannot prove HTTP route authorization or Lambda resource permissions.
- `AWS_IAM` authenticates the caller; it does not grant API Gateway permission to
  invoke Lambda. The Lambda execution role does not grant either permission.
- `caller_policy_example` is a reference, not an attached IAM policy. Use an
  existing authorized profile or have its administrator grant this route's access.
- HTTP `400/422` from the handler are controlled responses, not Lambda failures.
- Removing the API's Lambda permission should produce HTTP `500` before the
  handler runs. Inspect API access logs, not only Lambda `Errors`.
- No `$default` route exists. The stage name does not create a catch-all route.
- `invoke-api.sh` uses AWS CLI credential resolution and curl SigV4. It writes
  response headers/body/status locally, preserves curl failures, and never retries POST.
- Logs omit request bodies and authorization headers, but still contain operational
  identifiers. They are not automatically safe to publish.
- Review saved plans before applying. Restore `enable_api_invoke_permission=true`
  after the fault drill and destroy the lab when finished.