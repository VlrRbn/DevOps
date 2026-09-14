# Lesson 87: HTTP APIs with API Gateway and Lambda

This lesson moves from asynchronous messaging to synchronous HTTP requests.
Build an API with a public health route and an IAM-protected quote calculator,
then trace routing, authorization, integration failures, and application responses.

## Files

- `lesson.en.md`/`lesson.ru.md` - full lesson text and runtime drills.
- `lab_87/app/lambda_function.py` - payload v2 adapter and side-effect-free calculator.
- `lab_87/tests/` - handler and signed-request script tests without AWS access.
- `lab_87/events/` - Lambda event fixtures, not HTTP request bodies.
- `lab_87/requests/` - JSON bodies to send to the HTTP API.
- `lab_87/scripts/invoke-api.sh` - SigV4 request using the current AWS CLI profile.
- `lab_87/terraform/` - API, routes, integration, function, IAM, logs, and alarms.
- `lab_87/terraform/tests/` - native Terraform tests with a mock AWS provider.
- `lab_87/evidence/` - ignored local folder for temporary runtime results.
- `lab_87/README.md` - lab architecture and file layout.

## Quick Start

From the repository root, run local checks first:

```bash
python3 -m unittest discover \
  -s lessons/87-lambda-api-gateway-http-api/lab_87/tests -v
bash -n lessons/87-lambda-api-gateway-http-api/lab_87/scripts/invoke-api.sh
shellcheck lessons/87-lambda-api-gateway-http-api/lab_87/scripts/invoke-api.sh
```

Then prepare and validate the Terraform root:

```bash
cd lessons/87-lambda-api-gateway-http-api/lab_87/terraform
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform fmt -check -recursive
terraform validate
terraform test
```

Authenticate before creating a saved plan:

```bash
export AWS_PROFILE=YOUR_PROFILE
export AWS_REGION=eu-west-1
export AWS_PAGER=""
aws sso login --profile "$AWS_PROFILE"
aws sts get-caller-identity
terraform plan -out=tfplan
terraform show -no-color tfplan | less
terraform apply tfplan
```

Continue with sections 8-15 of the lesson for infrastructure inspection, signed
requests, error drills, log correlation, permission restoration, and cleanup.
Local mocks do not prove that deployment or SigV4 works in your AWS account.

## Main Flow

```text
HTTPS client -> HTTP API / $default stage
  -> GET /health  (public)
  -> POST /quotes (AWS_IAM + SigV4)
     -> Lambda proxy integration / payload 2.0
        -> validate input -> calculate total -> HTTP response

API access logs <--- same API request ID ---> Lambda application logs
```

## Requirements

- Terraform `~> 1.14.0` and Python 3.10+ for local tests.
- AWS CLI v2 with `configure export-credentials` and an authenticated profile.
- curl 7.76+ with `--aws-sigv4` and `--fail-with-body`, Bash, `jq`, and ShellCheck.
- Deployment permissions for API Gateway, Lambda, IAM, CloudWatch Logs, and alarms,
  including `iam:PassRole` for the function role.
- Caller permission `execute-api:Invoke` for `POST /quotes`; see the
  `caller_policy_example` output. Terraform does not attach that policy for you.

## Safety Notes

- `/health` is publicly reachable and billable; it returns no business data.
- `/quotes` only calculates a value. It does not create orders or charge money.
- The Lambda execution role can only write to its own log group.
- API Gateway invocation grants name the exact API, stage, method, and path.
- Throttling is best effort, not a hard spending limit or concurrency reservation.
- The signed-request helper does not print credentials or retry POST automatically.
- The fault drill removes invocation permissions only in this disposable dev lab;
  restore them before cleanup. Both CloudWatch alarms have no notification actions.
- Responses and logs stay local. Review any evidence before publishing it.
- Run `terraform destroy` after completing the drills.

## What This Lesson Intentionally Does Not Add

- No REST API, WebSocket API, Function URL, custom domain, or browser/CORS client.
- No JWT authorizer, cross-account access, database, or write-side idempotency store.
- No queue, DLQ, or asynchronous Lambda retry configuration.
