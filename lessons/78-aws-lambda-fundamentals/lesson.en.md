# Lesson 78. AWS Lambda Fundamentals

## 1. Why This Lesson Exists

The Terraform track taught how to describe, validate, and apply
infrastructure safely. Now starting a separate track about AWS Lambda
and serverless operations.

Lambda is a separate compute model that can be managed with Terraform.

This lesson deliberately creates only one function:

```text
JSON event
    |
    v
AWS Lambda -> Python handler -> JSON response
    |
    v
CloudWatch Logs
```

There is no API Gateway, SQS, EventBridge, VPC, or CI yet. Adding them
immediately would make it difficult to see which part of the system owns the
event, code execution, response, and logs.

## 2. Outcomes

After this lesson, you will be able to:

- explain how Lambda differs from a continuously running EC2 instance;
- distinguish a function, runtime, handler, event, context, and execution
  environment;
- test the core Python function logic locally;
- deploy the function and its execution role with Terraform;
- invoke the function synchronously with the AWS CLI;
- find the invocation in CloudWatch Logs;
- distinguish a successful Lambda API call from successful handler execution;
- remove the lab resources safely.

## 3. Mental Model

### 3.1. Lambda Is Not Just An Unnamed Server

For EC2, we normally think like this:

```text
create instance -> start process -> keep process running
```

Lambda uses a different model:

```text
receive event -> prepare execution environment -> invoke handler ->
return result -> retain environment for possible reuse
```

You do not manage the operating system or keep a process running continuously.
AWS manages the compute environment, while you remain responsible for:

- function code;
- runtime;
- memory and timeout;
- IAM permissions;
- event sources;
- error and retry handling;
- observability;
- cost and concurrency.

### 3.2. Core Terms

| Term | Meaning |
|---|---|
| Function | Lambda configuration and deployed code: `lab78-dev-hello`, its settings, and the ZIP package |
| Runtime | Language execution environment, such as `python3.14` |
| Handler | Entry point invoked by Lambda: `lambda_function.lambda_handler` |
| Event | Invocation input, such as JSON with `"name": "Valerii"` |
| Context | Metadata for the current invocation, such as `aws_request_id` |
| Execution environment | Isolated environment in which the code runs |
| Invocation | One request to run the function |
| Execution role | IAM role used by the function code; this lab grants it CloudWatch Logs permissions |

For a file named `lambda_function.py` and a function named `lambda_handler`, the
handler name is:

```text
lambda_function.lambda_handler
```

The first part identifies the Python module; the second identifies the function
inside it.

### 3.3. Event And Context

When Lambda invokes a handler, AWS passes two arguments:

```python
def lambda_handler(event, context):
```

`event` is the input the function must process. For the synchronous invocation,
we pass:

```json
{
  "name": "Valerii"
}
```

The Python runtime converts the JSON object to a `dict` and passes it as the
first handler argument:

```python
def lambda_handler(event, context):
```

AWS creates `context`. It includes values such as:

- `aws_request_id`;
- function name and version;
- invoked function ARN;
- time remaining before timeout.

Our function reads only the request ID:

```python
request_id = getattr(context, "aws_request_id", "local")
```

You do not create the real context yourself in AWS. Unit tests use a small fake
context only to verify our code.

### 3.4. Cold And Warm Invocation

When an event arrives, Lambda needs an environment in which to run the Python
code. If no suitable execution environment exists, AWS:

```text
creates an execution environment
-> starts the Python runtime
-> imports the code
-> invokes the handler
```

This is a **cold start**. The first invocation often has extra latency, and
CloudWatch Logs can include `Init Duration`.

AWS does not have to destroy the environment after the invocation. If it reuses
an existing environment, this is a **warm invocation**:

```text
next event
-> same execution environment
-> invoke the handler immediately
```

It is usually faster because the runtime and module do not need to start again.
Code outside the handler can therefore run once and then be reused by multiple
invocations.

Reuse is not guaranteed. A function must not rely on memory from a previous
invocation as durable storage. For example, do not do this:

```python
last_user = "Valerii"  # hoping it survives the next invocation
```

Process memory can remain or disappear at any time. Use an external store for
durable state: DynamoDB, S3, RDS, ElastiCache, or another service appropriate
for the problem. Code outside the handler is appropriate for safely reusable
initialization, such as an HTTP client, SDK client, or configuration; it must
not hold critical state for an individual user.

### 3.5. A Synchronous Invocation Has Two Results

When you run:

```bash
aws lambda invoke ...
```

you must distinguish:

1. The Lambda API accepted the request.
2. The handler processed the event successfully.

For example, if the event is:

```json
{
  "name": 42
}
```

AWS Lambda accepts the JSON and invokes the function, so the AWS CLI can exit
with code `0`. But the handler calls `build_greeting(42)`, which raises:

```text
ValueError: name must be a string
```

The resulting state is:

```text
AWS CLI exit code = 0
FunctionError = Unhandled
handler execution = failed
```

Automation must not check only `$?`; it must inspect Lambda response metadata:

```json
{
  "StatusCode": 200,
  "FunctionError": "Unhandled"
}
```

`StatusCode: 200` means the Lambda API processed the request.
`FunctionError: Unhandled` means the Python code ended with an exception.

This is an important operational distinction:

```text
API success != application success
```

## 4. Function Code

Open:

```text
lab_78/app/lambda_function.py
```

The code is divided into two parts:

- `build_greeting()` contains ordinary application logic. It accepts a string,
  trims whitespace, rejects an empty value, and returns a greeting.
- `lambda_handler()` adapts the Lambda event and context to that logic. It reads
  `name`, obtains the Lambda request ID and configured environment, and returns
  a JSON-compatible Python dictionary.

This separation lets us test the core logic without AWS or the Lambda runtime.
The handler treats `event` as untrusted input and verifies that the top-level
JSON value is an object before calling `.get()`.

The function does not log the complete event. Events may contain tokens,
personal data, or other sensitive values. The log record contains only
explicitly selected fields.

### Checkpoint 1

Answer in your own words:

1. Why should core logic be separated from the handler?
2. Who creates `event`, and who creates `context`?
3. Why must execution environment memory not be used as reliable durable
   storage?

## 5. Local Tests

From the lesson directory, run:

```bash
python3 -m unittest discover -s lab_78/tests -v
```

The tests cover:

- a normal name;
- the default value;
- an invalid type;
- a blank name;
- a non-object event;
- the handler response shape.

This is not an AWS Lambda emulator. Unit tests verify the code, but they do not
prove that IAM, the ZIP package, runtime, and CloudWatch are configured
correctly. A real deployment verifies those layers later.

## 6. Terraform Lab

Change to:

```bash
cd lessons/78-aws-lambda-fundamentals/lab_78/terraform
```

Create a local variables file:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Select an authenticated AWS profile before `plan`. For an AWS IAM Identity
Center (SSO) profile, for example:

```bash
export AWS_PROFILE=aws-sso-admin
aws sso login --profile "$AWS_PROFILE"
aws sts get-caller-identity
```

Replace `aws-sso-admin` with your profile name. If the profile does not use
SSO, authenticate it using its configured method and still verify the caller
identity. Then verify `aws_region` and run:

```bash
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan -out=tfplan
```

`terraform init`, formatting, and validation can run without AWS credentials.
`terraform plan` cannot: the AWS provider must authenticate and inspect the
current AWS state before it can build a complete plan.

### 6.1. What Terraform Creates

`main.tf` defines four AWS resources and two supporting data sources.

Terraform first builds the ZIP package locally:

```hcl
data "archive_file" "function" {
  type        = "zip"
  source_file = "../app/lambda_function.py"
  output_path = ".terraform/lambda_function.zip"
}
```

`archive_file` creates nothing in AWS. It packages the Python file into a
deployment package locally.

Terraform then builds a trust policy:

```hcl
data "aws_iam_policy_document" "lambda_trust"
```

It answers this question:

```text
Who may assume this IAM role?
```

The answer is the `lambda.amazonaws.com` service. Terraform creates
`aws_iam_role.lambda` from this policy. It is the function's execution role,
which the Lambda service assumes before it runs the handler.

Terraform also creates this log group explicitly:

```hcl
resource "aws_cloudwatch_log_group" "function"
```

Its name is:

```text
/aws/lambda/lab78-dev-hello
```

The narrow `aws_iam_role_policy.logs` policy allows only
`logs:CreateLogStream` and `logs:PutLogEvents` inside this function's log
group. It does not need `logs:CreateLogGroup`, because Terraform creates the
log group first.

Finally, `aws_lambda_function.hello` connects:

```text
ZIP + runtime + handler + execution role + environment variables
```

Its explicit `depends_on` ensures the log group and log policy exist before the
function. That reduces the risk that its first invocation lacks a destination
or permission for logs.

| Resource | Purpose |
|---|---|
| `archive_file.function` | Builds a ZIP package from the Python file locally |
| `aws_iam_role.lambda` | Trust policy allows the Lambda service to use the role |
| `aws_iam_role_policy.logs` | Allows writes only to this function's log group |
| `aws_cloudwatch_log_group.function` | Retains logs for a limited period |
| `aws_lambda_function.hello` | Function code and configuration |

This lab uses local Terraform state.

### 6.2. Why `source_code_hash` Matters

Terraform does not interpret Python code inside a ZIP package as infrastructure.
`source_code_hash` connects the archive contents to
`aws_lambda_function`.

When code changes:

```text
Python file -> new ZIP hash -> Terraform detects function code update
```

Without the hash, code can change while Terraform plans no function update.

### 6.3. Execution Role And Caller Identity

Do not confuse two identities:

- your AWS identity or CI role creates and invokes the function;
- the Lambda execution role is used by the code while it runs.

This lab's execution role cannot create EC2 instances, read S3 objects, or
retrieve secrets. It can only write logs for its own function.

```text
your identity
    |
    | creates and invokes the function
    v
Lambda service
    |
    | assumes the execution role
    v
Python handler
    |
    | CreateLogStream / PutLogEvents
    v
CloudWatch Logs
```

- The trust policy defines who may assume a role.
- The permissions policy defines what is allowed after assuming it.

### 6.4. Safety Limits

The lab configures:

- `timeout = 5`;
- `memory_size = 128`;
- no default concurrency reservation;
- seven-day log retention;
- `arm64` architecture;
- no public endpoint;
- no VPC.

Values limit the training function's cost and blast radius.

### Checkpoint 2

1. Why does the execution role not need `lambda:InvokeFunction` to invoke
   itself?
2. What changes in the plan after editing `lambda_function.py`?

## 7. Deployment

Before applying, verify the identity:

```bash
aws sts get-caller-identity
```

Apply the saved plan:

```bash
terraform apply tfplan
```

Inspect outputs:

```bash
terraform output
```

## 8. First Invocation

Run from `lab_78/terraform`:

```bash
aws lambda invoke \
  --region "$(terraform output -raw aws_region)" \
  --function-name "$(terraform output -raw function_name)" \
  --cli-binary-format raw-in-base64-out \
  --payload fileb://../events/hello.json \
  ../evidence/invoke-success-response.json \
  | tee ../evidence/invoke-success-metadata.json
aws_cli_exit_code=${PIPESTATUS[0]}
echo "aws_cli_exit_code=$aws_cli_exit_code"
```

Inspect the metadata and function response separately:

```bash
jq . ../evidence/invoke-success-metadata.json
jq . ../evidence/invoke-success-response.json
```

The response should mean:

```json
{
  "message": "Hello, Valerii!",
  "environment": "dev",
  "request_id": "..."
}
```

`request_id` changes for every invocation.

## 9. CloudWatch Logs

Inspect recent records:

```bash
aws logs tail "$(terraform output -raw log_group_name)" \
  --region "$(terraform output -raw aws_region)" \
  --since 10m \
  --format short
```

Find:

- `START RequestId: ...`;
- `{"event": "greeting_created", ...}`;
- `END RequestId: ...`;
- `REPORT RequestId: ...`.

`START`, `END`, and `REPORT` are emitted by the Lambda runtime.
`greeting_created` is emitted by the Python logger.

`Init Duration` may be absent for a warm invocation. That is not an error:
Lambda may have reused an already prepared execution environment.

## 10. Negative Drill

Invoke the function with an invalid `name` type:

```bash
aws lambda invoke \
  --region "$(terraform output -raw aws_region)" \
  --function-name "$(terraform output -raw function_name)" \
  --cli-binary-format raw-in-base64-out \
  --payload fileb://../events/invalid-name.json \
  ../evidence/invoke-error-response.json \
  | tee ../evidence/invoke-error-metadata.json
aws_cli_exit_code=${PIPESTATUS[0]}
echo "aws_cli_exit_code=$aws_cli_exit_code"
```

`PIPESTATUS[0]` captures the AWS CLI status from the pipeline; plain `$?` would
only report the status of `tee`. Now inspect both Lambda result channels:

```bash
jq . ../evidence/invoke-error-metadata.json
jq . ../evidence/invoke-error-response.json
```

Notice:

- the AWS CLI probably returned `0`;
- metadata contains `FunctionError`;
- the response contains exception details;
- CloudWatch Logs contains the stack trace.

Reliable automation must inspect `FunctionError`, not only the command exit
code:

```bash
jq -e 'has("FunctionError") | not' \
  ../evidence/invoke-error-metadata.json
```

This check should exit non-zero because the error is expected.

Now verify the top-level event contract with JSON `null`:

```bash
aws lambda invoke \
  --region "$(terraform output -raw aws_region)" \
  --function-name "$(terraform output -raw function_name)" \
  --cli-binary-format raw-in-base64-out \
  --payload fileb://../events/invalid-event.json \
  ../evidence/invoke-invalid-event-response.json \
  | tee ../evidence/invoke-invalid-event-metadata.json
aws_cli_exit_code=${PIPESTATUS[0]}
echo "aws_cli_exit_code=$aws_cli_exit_code"
```

The response must contain `ValueError: event must be a JSON object`, not an
accidental `AttributeError` from calling `.get()` on `None`.

### Checkpoint 3

1. Why does AWS CLI exit code `0` not prove handler success?
2. Where do you find the Python stack trace?
3. Why should the entire input event not be logged?

## 11. Practical Drills

### Drill 1. Default Value

Create an event:

```bash
printf '{}\n' > /tmp/lambda-default-event.json
```

Invoke the function with `aws lambda invoke` and prove that it returns a
greeting for `world`.

### Drill 2. Code Update

Change only the greeting text in `build_greeting()`, then run:

```bash
terraform plan
```

Explain why Terraform detected a change to `aws_lambda_function.hello` even
though no HCL changed. This proves the following chain:

```text
Python change
-> ZIP hash change
-> Terraform detects code update
-> Lambda code update in-place
```

After the check, restore the original text or apply the change intentionally.

### Drill 3. Caller Versus Execution Role

Answer:

- which identity ran `terraform apply`;
- which role appears in the Lambda configuration;
- why these are not the same identity.

Inspect the execution role:

```bash
aws lambda get-function-configuration \
  --region "$(terraform output -raw aws_region)" \
  --function-name "$(terraform output -raw function_name)" \
  --query '{FunctionName:FunctionName,Runtime:Runtime,Handler:Handler,Role:Role,MemorySize:MemorySize,Timeout:Timeout,Architectures:Architectures}' \
  --output table
```

You should see:

```text
Runtime: python3.14
Handler: lambda_function.lambda_handler
Role: ...lab78-dev-hello-role
MemorySize: 128
Timeout: 5
Architectures: arm64
```

## 12. Troubleshooting

### `No valid credential sources found`

The AWS provider could not find an active local identity. Select the intended
profile, renew its session when necessary, and verify it before rerunning the
plan:

```bash
export AWS_PROFILE=aws-sso-admin
aws sso login --profile "$AWS_PROFILE"
aws sts get-caller-identity
terraform plan -out=tfplan
```

Do not treat the partial output printed before this error as a valid plan.

### `ReservedConcurrentExecutions ... below its minimum value of [10]`

The regional account quota is too small to reserve the requested concurrency
while AWS keeps its required minimum unreserved pool. Leave
`reserved_concurrent_executions` unset for this lab, then create a fresh plan:

```bash
terraform plan -out=tfplan
terraform apply tfplan
```

Do not reuse the old `tfplan`: it was built for a different configuration.

### `Runtime.ImportModuleError`

Verify:

- `lambda_function.py` is at the ZIP root;
- the handler is `lambda_function.lambda_handler`;
- the file and function names match the handler.

### `AccessDeniedException` During Invoke

The caller identity lacks `lambda:InvokeFunction`. This is a permission for the
invoking identity, not the function execution role.

### `ResourceNotFoundException`

It normally means one of three things:

- the function name is wrong;
- a different AWS Region was selected;
- the function has not been created or was already deleted.

Check the function directly:

```bash
aws lambda get-function \
  --function-name "$(terraform output -raw function_name)" \
  --region "$(terraform output -raw aws_region)"
```

### Invocation Succeeds But Response Contains An Error

Check `FunctionError` in metadata and the stack trace in CloudWatch Logs. Do not
rely only on `$?`.

### Plan Is Empty After A Python Code Change

Check that:

- the changed file is inside `lab_78/app/`;
- Terraform uses `data.archive_file.function`;
- `aws_lambda_function` has `source_code_hash`.

In this lab, Terraform recalculates the ZIP archive hash. A code change changes
that hash, so Terraform plans a Lambda update. Do not remove the hash to hide
the problem.

### Logs Have Not Appeared Yet

CloudWatch Logs can update after a short delay. Retry `aws logs tail` after a
few seconds and verify the Region and log group name.

### Checkov Reports VPC, KMS, DLQ, X-Ray, Or Code-Signing Findings

These generic findings require context rather than automatic suppression:

- a VPC is needed only when the function must reach private VPC resources;
- this lab stores non-secret configuration and relies on AWS-managed encryption;
- a DLQ is relevant to asynchronous invocation paths, while this lesson uses
  synchronous invocation;
- X-Ray, code signing, customer-managed KMS keys, and longer log retention are
  valid production decisions but belong to later reliability and delivery
  lessons.

Record these findings as accepted lab limitations. Do not claim that the lab is
a complete production workload, and do not add unrelated infrastructure only
to make a generic scanner green.

## 13. Completion Check

Before cleanup, confirm that:

- all local unit tests pass;
- Terraform formatting and validation pass;
- the saved plan was reviewed before apply;
- the successful invocation has no `FunctionError`;
- the negative invocations have `FunctionError` even though AWS CLI returned `0`;
- the request ID connects the response to the matching CloudWatch log records.

Check logs with:

```bash
aws logs filter-log-events \
  --log-group-name "$(terraform output -raw log_group_name)" \
  --region "$(terraform output -raw aws_region)" \
  --output json | jq '.events[].message'
```

The files under `lab_78/evidence/` are temporary exercise output. Do not commit
them without review and redaction.

## 14. Cleanup

Resource removal is part of the lab. Preserve the function name and Region so
that you can verify AWS afterward:

```bash
FUNCTION_NAME="$(terraform output -raw function_name)"
AWS_REGION="$(terraform output -raw aws_region)"
terraform plan -destroy
terraform destroy
aws lambda get-function --region "$AWS_REGION" --function-name "$FUNCTION_NAME"
```

The final command should return `ResourceNotFoundException`.

## 15. Final Model

```text
caller identity
    |
    | lambda:InvokeFunction
    v
Lambda service
    |
    | assumes execution role
    v
Python handler(event, context)
    |
    +-> response
    |
    +-> CloudWatch Logs
```

Key conclusions:

1. Lambda invokes a handler for an event; it does not keep your process running
   continuously.
2. Event carries input data; context carries invocation metadata.
3. Caller identity and execution role have different responsibilities.
4. Lambda API success does not guarantee handler success.
5. Unit tests, Terraform checks, and a real invocation verify different layers.
6. The first lesson is deliberately small; event sources, retries, packaging,
   and delivery come later.

## 16. Official References

- [AWS Lambda runtimes](https://docs.aws.amazon.com/lambda/latest/dg/lambda-runtimes.html)
- [Python handler in AWS Lambda](https://docs.aws.amazon.com/lambda/latest/dg/python-handler.html)
- [Lambda context object](https://docs.aws.amazon.com/lambda/latest/dg/python-context.html)
- [Lambda quotas](https://docs.aws.amazon.com/lambda/latest/dg/gettingstarted-limits.html)
- [Terraform `aws_lambda_function`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function)
- [Terraform `archive_file`](https://registry.terraform.io/providers/hashicorp/archive/latest/docs/data-sources/file)
