# Lesson 87: HTTP APIs with API Gateway and Lambda

## 1. Why This Lesson Exists

In lessons 82–86 a producer sent a message or event and a consumer processed it
later. Here the client sends an HTTP request and waits for the result on the same
connection. This model serves websites, applications, and internal tools.

```html
HTTP-клиент → API Gateway → Lambda → HTTP-ответ
```

We will build a quote API: the client supplies a unit price in cents and a quantity,
and Lambda returns the total.

The client keeps the connection open and waits for the result. Therefore, we need to
distinguish between:

- API Gateway rejected the request;
- API Gateway could not invoke Lambda;
- Lambda rejected the input as part of normal application logic;
- Lambda terminated with an exception;
- the client itself stopped waiting because of a timeout.

The main skill in this lesson is tracing the request from the client to the function
and determining which component returned the error.

```text
the client constructed an HTTP request

- the API Gateway route was matched
- route authorization succeeded
- API Gateway had permission to invoke Lambda
- Lambda processed the input
- API Gateway constructed the HTTP response
- the client received the expected status and body
```

## 2. Learning Outcomes

- Create an HTTP API, routes, a Lambda integration, and a stage using Terraform.
- Read payload format `2.0` and construct an explicit HTTP response.
- Separate caller permissions, gateway permissions, and Lambda execution permissions.
- Sign a request with SigV4 using the current AWS profile.
- Exercise successful and unsuccessful requests.
- Correlate one request across API Gateway and Lambda logs.
- Reproduce an invocation-permission error and restore the working configuration.
- Explain timeout, retry, and throttling boundaries.

In the lab, we will verify the complete synchronous path:

```text
HTTP request

- route
- AWS_IAM authorization
- Lambda integration
- HTTP response
- access log + Lambda log
```

### 2.1. Lesson Terminology

| Term | Meaning in this lesson |
|---|---|
| HTTP API | The API Gateway product used by the lab |
| route | Method and path, such as `POST /quotes` |
| integration | How a route invokes Lambda |
| stage | Published API settings; `$default` here |
| synchronous invocation | Client waits for the function response |
| payload format version | Contract between API Gateway and Lambda |
| request/response body | Data carried by HTTP |
| SigV4 request signing | Proof of the caller's AWS identity |
| access log | API Gateway record of a request and outcome |
| request ID | Correlates HTTP responses and logs |
| throttling | Load control that may return `429` |
| burst | Short-term demand above the normal rate |

## 3. Mental Model

### 3.1. HTTP API, Route, Integration, and Stage

API Gateway offers HTTP API, REST API, and WebSocket API. This lab uses an **HTTP API**
with Terraform resources from `aws_apigatewayv2_*`.
This is important: HTTP API and REST API are different API Gateway products.
Settings from `aws_api_gateway_*` resources for REST API cannot be mechanically applied
to HTTP API.

The request passes through three entities:

```text
route -> integration -> Lambda
```

The route is selected by method and path:

```text
GET  /health
POST /quotes
```

`auto_deploy = true` automatically publishes API changes in this lab.
It is a development convenience, not a production release approval process.

The routes use different authorization modes:

```text
GET /health  -> NONE    -> public
POST /quotes -> AWS_IAM -> requires SigV4
```

The integration determines which backend to invoke. Both routes use the same Lambda function through a proxy integration.

The stage publishes the API configuration. This lab uses `$default`, so the URL looks like this:

```text
https://API_ID.execute-api.REGION.amazonaws.com/health
```

Mental model:

```text
route answers: "which request?"
integration answers: "which backend?"
stage answers: "which published configuration is available to the client?"
```

### 3.2. What Lambda Receives and Returns

The client sends a regular HTTP body:

```json
{
  "unit_price_cents": 1250,
  "quantity": 3
}
```

But Lambda receives more than just this body. API Gateway creates a `2.0` format event:

```json
{
  "version": "2.0",
  "routeKey": "POST /quotes",
  "headers": {
    "content-type": "application/json"
  },
  "requestContext": {
    "requestId": "api-request-id",
    "http": {
      "method": "POST",
      "path": "/quotes"
    }
  },
  "body": "{\"unit_price_cents\":1250,\"quantity\":3}",
  "isBase64Encoded": false
}
```

The `body` field here is a string. Therefore, the handler first parses the envelope
and then separately decodes the JSON from `body`.

If:

```json
"isBase64Encoded": true
```

the handler first performs Base64 decoding, then UTF-8 decoding, and only then JSON parsing.

The files under `lab_87/events/` contain complete API Gateway events for local tests.
They must not be sent by the client as the HTTP body. Client request bodies are stored
under `lab_87/requests/`.

Lambda returns a proxy response:

```json
{
  "statusCode": 200,
  "headers": {
    "content-type": "application/json"
  },
  "body": "{\"currency\":\"EUR\",\"total_cents\":3750}",
  "isBase64Encoded": false
}
```

API Gateway converts this structure into a real HTTP response:

```http
HTTP/1.1 200 OK
content-type: application/json

{"currency":"EUR","total_cents":3750}
```

The client does not see the outer object containing `statusCode` and `body`;
it receives the status, headers, and decoded contents of `body`.

Mental model:

```text
HTTP request

-> API Gateway event envelope
-> Lambda proxy response
-> HTTP response
```

### 3.3. Three Separate Permission Boundaries

Three principals participate in the request, and each one needs its own permissions.

| Who         | Required permission             | Where it is checked    |
| ----------- | ------------------------------- | ---------------------- |
| HTTP client | `execute-api:Invoke`            | client IAM             |
| API Gateway | `lambda:InvokeFunction`         | Lambda resource policy |
| Lambda      | write access to CloudWatch Logs | Lambda execution role  |

#### Client → API Gateway

The route:

```text
POST /quotes
```

uses `AWS_IAM`. The client must:

1. sign the request with SigV4;
2. have the IAM permission `execute-api:Invoke` for this route.

Permission for the client to invoke Lambda directly does not help here—the client is calling API Gateway.

The route:

```text
GET /health
```

uses `NONE`, so it is accessible without an AWS signature.

#### API Gateway → Lambda

After the client is successfully authorized, API Gateway needs a separate permission:

```text
Principal = apigateway.amazonaws.com

Action    = lambda:InvokeFunction
```

This is configured through the `aws_lambda_permission` resource in the function's
resource policy and restricted by the `source_arn` of this API.

#### Lambda → CloudWatch Logs

The function's execution role allows Lambda to write its own logs.

This role does not authorize the HTTP client and does not give API Gateway permission
to invoke the function.

Terraform outputs an example of a minimal caller policy, but it does not attach it to
the current SSO profile. For the lab, the profile must already have `execute-api:Invoke`.

Mental model:

```text
client IAM     -> can the client access the protected route?
Lambda policy  -> can API Gateway invoke the function?
execution role -> what can the function do after it starts?
```

### 3.4. HTTP Status and Lambda Invocation Success

| Outcome | Typical responding layer in this lab |
|---|---|
| `200` | Lambda returns health or a quote |
| `400` | Lambda rejects malformed JSON |
| `403` | API Gateway rejects an unsigned/unauthorized request |
| `404` | API Gateway finds no matching route |
| `413` | Handler rejects a body larger than 4096 bytes |
| `415` | Handler requires `application/json` |
| `422` | Valid JSON with invalid quote values |
| `429` | API Gateway throttles requests |
| `500` | For example, API Gateway cannot obtain permission to invoke Lambda |
| `502` | For example, the function raises an exception or returns a malformed response |

Returning `statusCode=422` is not a Lambda exception: the invocation completes,
while the HTTP client receives an input rejection. Lambda `Errors` can remain
zero while the API records `4xx`.

It is also important to distinguish between the HTTP status and the client's exit
code: `curl https://example/api`.

A normal `curl` command may exit with code `0` even if the server returned HTTP `500`.

The option `--fail-with-body` preserves the error response body but makes the exit code
non-zero for HTTP `4xx` and `5xx` responses.

For diagnostics, check all of the following together:

- the HTTP status and response body;
- the API Gateway access log;
- the Lambda log and the `Errors` metric.

### 3.5. Timeouts and Repeated Requests

The lab configures:

```text
Take the request time as `0 seconds`:

0 s                  6 s                  10 s                 15 s
│                    │                    │                    │
request sent         Lambda timeout       integration timeout  curl --max-time
                     function stopped     API Gateway stops    client stops
                     client receives 502  waiting              waiting
```

These are three independent limits, not sequential stages of a single request.

If Lambda runs for longer than `6` seconds, Lambda stops the execution. The function
does not return a valid proxy response, so API Gateway returns `502 Bad Gateway` to the client.

The API Gateway limit of `10` seconds is not reached in this scenario because Lambda
has already failed at the six-second mark. The client limit of `15` seconds is also
not reached because the client receives the `502` response earlier.

If the integration remained active for longer than `10` seconds, API Gateway itself
would stop waiting. If no response arrived within `15` seconds, `curl` would terminate
because of its own timeout; that would not be an HTTP status returned by the API.

This leaves transport headroom; tune for your workload.

API Gateway does not automatically retry failed Lambda invocations. There is
no SQS queue, DLQ, or asynchronous retry configuration from lesson 80.
The client decides whether to retry.

A client timeout does not prove that the server stopped: the operation may finish
after the connection closes. Writes need the business idempotency key discussed in lesson 81.
Repeating this calculation is safe because it performs no writes.

### 3.6. CORS and Browser Access

English version:

Short mental model:

```text
CORS          = permission for the browser to read the response
Authorization = permission for the server to execute the request
```

CORS applies only in browsers:

- JavaScript from another origin may be blocked by the browser;
- `curl`, Postman, and server-side clients are not restricted by CORS;
- successful CORS does not grant permission to call a protected route;
- `POST /quotes` still requires `AWS_IAM` and a SigV4 signature.

For example, a frontend at `https://app.example.com` calling an API on another
origin may first send an `OPTIONS` preflight request. Allowed CORS lets JavaScript
read the response, but it does not bypass route authorization:

```text
CORS allowed + authorization succeeds   -> request is executed, response is available to JavaScript
CORS allowed + authorization rejected   -> API returns 401/403
CORS blocked + API returned a response  -> browser does not expose the response to JavaScript
curl/Postman                            -> CORS rules do not apply
```

There is no browser client in this lab, so CORS is not required.

For a user-facing application, authorization is designed separately, for example with a
JWT authorizer; AWS secrets should not be embedded in the browser.

## 4. Lab Architecture

```text
client
  -> HTTPS HTTP API / $default stage
     -> GET /health  (public)
     -> POST /quotes (AWS_IAM + SigV4)
        -> Lambda proxy integration, payload 2.0
           -> http-function execution role
              -> own CloudWatch Logs group

API access log: request ID, route, status, integration error
Lambda log:     API request ID, Lambda request ID, route, status
```

The lab has one HTTP API and one Lambda function, but two routes:

```text
GET /health   -> public  -> Lambda
POST /quotes  -> AWS_IAM -> Lambda
```

Both routes use:

- the `$default` stage, so there is no stage name in the URL;
- Lambda proxy integration;
- payload format `2.0`;
- one function that distinguishes routes by `routeKey`.

There are two independent logs:

- the API Gateway access log shows that the request was received, which route
was selected, the HTTP status, and any integration error;
- the Lambda log shows whether the function was actually invoked and how it
processed the request.

A single request is correlated across layers through the API Gateway request ID:

```text
client
  <- response header: apigw-requestid

API Gateway access log
  requestId=<api-request-id>

Lambda event
  requestContext.requestId=<api-request-id>

Lambda log
  api_request_id=<api-request-id>
  lambda_request_id=<invocation-request-id>
```

`api_request_id` is the same in API Gateway and Lambda.

`lambda_request_id` belongs only to the specific function invocation.

What each layer proves:

```text
The client received an HTTP response
→ API Gateway processed the request

An API access log exists
→ the request reached API Gateway and was classified

A Lambda log exists with the same API request ID
→ API Gateway actually invoked Lambda

The status/body is correct
→ Lambda produced the expected business result
```

An HTTP `200` alone does not explain the full path—the evidence is built from
the response and both logs.

## 5. Implementation Walkthrough

### 5.1. Function and Validation

Mental model of the function:

```text
API Gateway event

-> validate the version 2.0 envelope
-> determine the routeKey
-> read and decode the body
-> validate the business fields
-> perform the calculation
-> return a proxy response
```

`app/lambda_function.py` separates event parsing, JSON validation, calculation,
and response construction. `TypedDict` describes the response shape for the editor;
`isinstance` checks and range checks run at runtime.

Main parts of the code:

- `HttpResponse` describes the expected response shape. It is a hint for the type
checker, not runtime validation.
- `as_object()` verifies that an external value is actually a JSON object.
- `read_json_body()` validates `Content-Type`, body presence, Base64 encoding, UTF-8,
JSON, and the 4096-byte limit.
- `calculate_quote()` accepts exactly two fields and calculates the total in cents.
- `response()` always serializes `body` into a string—this is what the proxy integration requires.
- `lambda_handler()` selects the processing logic based on `routeKey`.

The price is represented as an integer number of cents to avoid `float` rounding.

`True` is rejected explicitly: in Python, `bool` is a subclass of `int`. Otherwise, JSON
like this could pass validation:

```json
{"unit_price_cents": true, "quantity": 2}
```

The fields must be exactly `unit_price_cents` and `quantity`.

The application accepts UTF-8 JSON, including Base64-encoded bodies, and limits the
body to 4096 bytes. This is an application-level limit, not a change to the API Gateway quota.

Expected data errors become HTTP `4xx` responses. Unexpected errors propagate out
instead of being converted into a false `200`. Logs contain identifiers and the result,
without the full event, authorization headers, or request body.

It is important to distinguish between an HTTP request error and a Lambda invocation error:

| Situation                         | Lambda result               | HTTP response |
| --------------------------------- | --------------------------- | ------------: |
| No JSON body                      | handler returns a response  |         `400` |
| Invalid `Content-Type`            | handler returns a response  |         `415` |
| Body larger than 4096 bytes       | handler returns a response  |         `413` |
| Invalid fields or ranges          | handler returns a response  |         `422` |
| Payload `2.0` envelope is invalid | handler raises an exception |         `502` |
| Unexpected program error          | handler raises an exception |         `502` |

A `4xx` response here is still a successfully completed Lambda invocation: the
function recognized the client error itself and constructed an HTTP response.
`502` means that API Gateway did not receive a valid proxy response from the function.

Important error separation:

```text
RequestError
-> expected client error
-> Lambda returns a valid proxy response
-> HTTP 400/413/415/422
-> Lambda invocation is considered successful

ValueError or another unexpected error
-> the exception propagates out of the handler
-> Lambda invocation is considered failed
-> API Gateway returns 502
```

`GET /health` does not read the body. `POST /quotes` goes through the full validation cycle.

### 5.2. Terraform and Resource Names

| File | What to find |
|---|---|
| `http_api.tf` | API, integration, two routes, stage, and access log |
| `api_invoke_permissions.tf` | Permission for API Gateway to invoke the exact routes |
| `function_execution_role.tf` | Trust policy via `aws_iam_policy_document` and log permissions |
| `function.tf` | Function, runtime, memory, and timeout |
| `package.tf` | ZIP containing one Python file |
| `monitoring.tf` | API `5xx` and Lambda `Errors` signals |
| `locals.tf` / `outputs.tf` | Names, route map, and access information |

Terraform resource relationships:

```text
local.routes
  ├─ health: GET /health, NONE
  └─ quotes: POST /quotes, AWS_IAM
       │
       ├─ aws_apigatewayv2_route.http
       │    └─ both routes use the same AWS_PROXY integration
       │
       └─ aws_lambda_permission.api_route
            └─ a separate source ARN for each method/path

aws_apigatewayv2_integration.function
  └─ aws_lambda_function.http
       └─ aws_iam_role.function_execution
            └─ writes only to its own CloudWatch log group
```

Main Terraform chain:

```text
aws_apigatewayv2_api
  → aws_apigatewayv2_route
  → aws_apigatewayv2_integration
  → aws_lambda_function
```

#### `locals.tf`

`local.routes` is the single route definition map:

```hcl
routes = {
  health = { method = "GET",  path = "health", authorization = "NONE" }
  quotes = { method = "POST", path = "quotes", authorization = "AWS_IAM" }
}
```

It is used to create:

- two `aws_apigatewayv2_route` resources;
- two exact `aws_lambda_permission` resources.

#### `http_api.tf`

`aws_apigatewayv2_api` creates the HTTP API itself.

A single integration is used by both routes:

```hcl
integration_type        = "AWS_PROXY"
integration_method      = "POST"
payload_format_version  = "2.0"
```

Do not confuse the two uses of `POST`:

| Setting              | Value             | Meaning                                            |
| -------------------- | ----------------- | -------------------------------------------------- |
| `route_key`          | `POST /quotes`    | the client's request to the HTTP API               |
| `integration_method` | `POST`            | the internal call to the Lambda Invoke API         |
| `GET /health`        | client-side `GET` | internally, Lambda is still invoked through `POST` |

`aws_apigatewayv2_stage.default`:

- uses `$default`, so the stage name is absent from the URL;
- automatically publishes changes through `auto_deploy`;
- configures shared throttling;
- sends access logs to a separate log group.

#### `api_invoke_permissions.tf`

A separate permission is created for each route:

```text
API + stage + method + path → lambda:InvokeFunction
```

For example:

```text
.../$default/POST/quotes
```

`$default` is present in the permission ARN even though it does not appear in the public URL.

#### Other files

- `package.tf` packages the Python file into a ZIP archive.
- `function.tf` creates the log group and Lambda function.
- `function_execution_role.tf` allows the function to write only to its own log group.
- `monitoring.tf` creates separate signals for API `5xx` responses and Lambda `Errors`.

These are different metrics: the API can return a `5xx` even if Lambda was never invoked.

### 5.3. Why invoke-api.sh Exists

The `POST /quotes` route uses `AWS_IAM`, so a regular unsigned `curl` request
receives HTTP `403`.

The script performs the following sequence:

```text
AWS CLI credentials
→ SigV4 signature
→ POST /quotes
→ save status, headers, and body
```

#### Obtaining credentials

Regular `curl` does not read an AWS profile or SSO session. The script obtains
temporary credentials with:

```bash
aws configure export-credentials --format process
```

A temporary `SessionToken` is required for credentials obtained through SSO or STS.

The script protects the credentials:

- `set +x` disables shell tracing;
- `umask 077` restricts permissions on created files;
- credentials are passed to `curl` through stdin configuration rather than command-line arguments;
- the endpoint is restricted to the `execute-api.amazonaws.com` domain in the required region;
- credential variables are unset after the request;
- redirects and automatic retries of the `POST` request are not used.

Do not manually export credentials for the purpose of publishing their output.

#### SigV4 signature

```bash
--aws-sigv4 "aws:amz:$api_region:execute-api"
```

Here:

- `aws:amz` — the AWS SigV4 signing scheme;
- `$api_region` — the API region;
- `execute-api` — the API Gateway service name.

#### Execution results

The script separates the transport result from the HTTP result:

```text
curl exit code
  └─ result of executing the request on the client side

<prefix>.status.txt
  └─ HTTP status returned by API Gateway

<prefix>.headers.txt
  └─ response headers and identifiers

<prefix>.body.json
  └─ application result or error message
```

For HTTP `4xx` and `5xx` responses, `--fail-with-body` preserves the response
body, but `curl` returns a non-zero exit code, usually `22`. DNS, TLS, connection,
and timeout failures have their own `curl` exit codes.

Example execution from the `terraform` directory:

```bash
../scripts/invoke-api.sh \
  "$API_ENDPOINT" \
  "$AWS_REGION" \
  ../requests/quote.json \
  ../evidence/quote
```

Check the saved results:

```bash
cat ../evidence/quote.status.txt
cat ../evidence/quote.headers.txt
jq . ../evidence/quote.body.json
```

A non-zero exit code by itself does not explain the cause: check the HTTP status,
response body, and `curl` message.

The script intentionally does not retry the `POST` request: losing the connection
does not prove that the server did not already process the request.

## 6. Local Verification

Requirements: Python 3.10+, Terraform `~> 1.14.0`, AWS CLI v2 with
`configure export-credentials`, `jq`, Bash, ShellCheck, and curl 7.76+
with `--aws-sigv4` and `--fail-with-body`.

From the repository root:

```bash
python3 -m unittest discover \
  -s lessons/87-lambda-api-gateway-http-api/lab_87/tests -v
bash -n lessons/87-lambda-api-gateway-http-api/lab_87/scripts/invoke-api.sh
shellcheck lessons/87-lambda-api-gateway-http-api/lab_87/scripts/invoke-api.sh

cd lessons/87-lambda-api-gateway-http-api/lab_87/terraform
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform fmt -check -recursive
terraform validate
terraform test
```

Expect 19 local Python/script checks and 10 native Terraform tests.
They do not access AWS resources: the script tests use fake `aws/curl`,
and Terraform uses a mock provider. `init` downloads providers.

## 7. Authentication and Deployment

Run subsequent commands from `lab_87/terraform`.
Replace `YOUR_PROFILE` with your profile. For SSO:

```bash
export AWS_PROFILE=YOUR_PROFILE
export AWS_REGION=eu-west-1
export AWS_PAGER=""
aws sso login --profile "$AWS_PROFILE"
aws sts get-caller-identity

terraform plan -out=tfplan
terraform show -no-color tfplan | less
terraform apply tfplan

export AWS_REGION="$(terraform output -raw aws_region)"
export API_ENDPOINT="$(terraform output -raw api_endpoint)"
export API_ID="$(terraform output -raw api_id)"
export FUNCTION_NAME="$(terraform output -raw function_name)"
export API_LOG_GROUP="$(terraform output -json log_group_names | jq -r '.api')"
export FUNCTION_LOG_GROUP="$(terraform output -json log_group_names | jq -r '.function')"
mkdir -p ../evidence
```

The deployment profile must manage API Gateway, Lambda, IAM, and CloudWatch
logs/alarms, including `iam:PassRole` for the function's execution role.

The Lambda role's permissions are not enough to configure HTTP API access logs:
setup needs log delivery permissions, including `logs:CreateLogDelivery` and `logs:PutResourcePolicy`.

## 8. Verify the Infrastructure Contract

Verify the configuration layer by layer rather than with one broad assertion:

```text
routes
→ integration
→ stage
→ Lambda resource policy
→ caller IAM policy
```

### 8.1. Routes and Authorization

```bash
aws apigatewayv2 get-routes \
  --api-id "$API_ID" \
  --region "$AWS_REGION" \
  --query 'Items[].{Route:RouteKey,Auth:AuthorizationType,Target:Target}' \
  --output table
```

This command proves only that:

- the routes were created in the correct API;
- `/health` is public;
- `/quotes` requires IAM authorization;
- the routes are connected to the integration.

### 8.2. Integration

```bash
aws apigatewayv2 get-integrations \
  --api-id "$API_ID" \
  --region "$AWS_REGION" \
  --query 'Items[].{
    Id:IntegrationId,
    Type:IntegrationType,
    Method:IntegrationMethod,
    Version:PayloadFormatVersion,
    Timeout:TimeoutInMillis
  }' \
  --output table
```

The integration is configured correctly if:

- `integrations/id` matches the target of both routes;
- `AWS_PROXY` means Lambda proxy integration;
- `POST` is the internal Lambda invocation method;
- payload `2.0` defines the event envelope and response format;
- the timeout is `10000` ms.

### 8.3. Stage $default

```bash
aws apigatewayv2 get-stage \
  --api-id "$API_ID" \
  --stage-name '$default' \
  --region "$AWS_REGION" \
  --query '{
    Stage:StageName,
    AutoDeploy:AutoDeploy,
    RateLimit:DefaultRouteSettings.ThrottlingRateLimit,
    BurstLimit:DefaultRouteSettings.ThrottlingBurstLimit,
    LogDestination:AccessLogSettings.DestinationArn,
    LogFormat:AccessLogSettings.Format
  }' \
  --output json
```

The `stage` must match the contract:

- `$default` is used, so the URL does not contain `/dev` or another stage name;
- `AutoDeploy=true` automatically publishes changes;
- throttling is configured at 5 requests per second with a burst of up to 10;
- access logs are sent to the separate log group `/aws/apigateway/lab87-dev-http-api`;
- the log format contains all five diagnostic fields.

### 8.4. Resource policy Lambda

```bash
aws lambda get-policy \
  --function-name "$FUNCTION_NAME" \
  --region "$AWS_REGION" \
  --query Policy \
  --output text |
jq '.Statement[] | {
  Sid,
  Effect,
  Principal,
  Action,
  Resource,
  SourceArn: .Condition.ArnLike."AWS:SourceArn",
  SourceAccount: .Condition.StringEquals."AWS:SourceAccount"
}'
```

The Lambda resource policy is correct if:

- there are exactly two permissions;
- the principal is only `apigateway.amazonaws.com`;
- both permissions apply to the `lab87-dev-http-function` function;
- `SourceAccount` is restricted to your account;
- `SourceArn` values are restricted to the API;
- methods and paths are speci

### 8.5. Example caller policy

```bash
terraform output -json caller_policy_example | jq .
```

These checks confirm the resource configuration, but not the runtime path:

```text
get-routes
  -> routes and authorization types are configured

get-integrations
  -> AWS_PROXY, payload 2.0, and timeout are configured

get-stage
  -> $default, auto deploy, throttling, and access log destination are configured

lambda get-policy
  -> API Gateway is allowed to invoke Lambda from the exact routes

terraform output caller_policy_example
  -> shows the required IAM document, but does not prove that it is attached to the caller
```

These checks confirm the resource configuration, but not the runtime path:

```text
get-routes
  -> routes and authorization types are configured

get-integrations
  -> AWS_PROXY, payload 2.0, and timeout are configured

get-stage
  -> $default, auto deploy, throttling, and access log destination are configured

lambda get-policy
  -> API Gateway is allowed to invoke Lambda from the exact routes

terraform output caller_policy_example
  -> shows the required IAM document, but does not prove that it is attached to the caller
```

## 9. First Request and Quote

### 9.1. Public Health Check

```bash
curl -sS --fail-with-body --connect-timeout 5 --max-time 15 \
  -D ../evidence/health.headers.txt \
  -o ../evidence/health.body.json \
  -w '%{http_code}\n' "$API_ENDPOINT/health"
jq . ../evidence/health.body.json
```

Expect HTTP `200`, `status: "ok"`, and a `request_id`.

### 9.2. Signed POST

```bash
../scripts/invoke-api.sh "$API_ENDPOINT" "$AWS_REGION" \
  ../requests/quote.json ../evidence/quote

cat ../evidence/quote.status.txt
jq . ../evidence/quote.body.json
jq -e '.total_cents == 3750 and .currency == "EUR"' ../evidence/quote.body.json
```

Input: unit price 1250 cents, quantity 3. Output: 3750 cents, or EUR 37.50.
Do not expect `201 Created`: no persistent resource is created.

Repeat with prefix `../evidence/quote-repeat`. The total stays the same,
while `request_id` changes. It is a new HTTP request with the same calculation.

### 9.3. Correlating Response and Logs

```bash
REQUEST_ID="$(jq -r '.request_id' ../evidence/quote-repeat.body.json)"

aws logs tail "$API_LOG_GROUP" \
  --since 10m \
  --region "$AWS_REGION" \
  --format short \
  > ../evidence/api.log

aws logs tail "$FUNCTION_LOG_GROUP" \
  --since 10m \
  --region "$AWS_REGION" \
  --format short \
  > ../evidence/function.log

printf 'REQUEST_ID=%s\n' "$REQUEST_ID"

printf '%s\n' '===== API Gateway ====='
rg -F "$REQUEST_ID" ../evidence/api.log

printf '%s\n' '===== Lambda ====='
rg -F "$REQUEST_ID" ../evidence/function.log
```

Expected:

- in the API log — the `request_id`, route `POST /quotes`, and status `200`;
- in the Lambda log — the same `api_request_id`, route `POST /quotes`, and status `200`;
- only the Lambda log contains a separate `lambda_request_id`.

Keep these files local: logs can contain operational identifiers and integration messages.

Section result:

```text
signed request accepted

→ route selected
→ API Gateway invoked Lambda
→ Lambda performed the calculation
→ API Gateway returned the response
→ the client received the correct result
```

For a single successful request, the evidence is correlated as follows:

| Layer           | Field               | Expected value                  |
| --------------- | ------------------- | ------------------------------- |
| Response body   | `request_id`        | shared API request ID           |
| Response header | `x-request-id`      | the same API request ID         |
| Response header | `apigw-requestid`   | the same API request ID         |
| API access log  | `request_id`        | the same API request ID         |
| Lambda log      | `api_request_id`    | the same API request ID         |
| Lambda log      | `lambda_request_id` | a separate Lambda invocation ID |

For example:

```text
API request ID:    Dsvlzj0rjoEEJPw=
Lambda request ID: d40e964a-2de6-442d-b5ff-ceba4cf74ef3
```

Matching API request IDs prove that the HTTP response and the entries in both
logs belong to the same request. The `lambda_request_id` identifies the specific
function invocation and should not match the API request ID.

The value `integration_error: "-"` in the access log means that API Gateway did
not record an integration error.

Section result:

```text
signed request accepted

→ route selected
→ API Gateway invoked Lambda
→ Lambda performed the calculation
→ API Gateway returned the response
→ the client received the correct result
```

## 10. Client Errors

### 10.1. Unsigned Request

Send the same `POST /quotes` request, but without SigV4:

```bash
rc=0

curl -sS --fail-with-body \
  --connect-timeout 5 \
  --max-time 15 \
  -H 'Content-Type: application/json' \
  --data-binary @../requests/quote.json \
  -D ../evidence/unsigned.headers.txt \
  -o ../evidence/unsigned.body.json \
  -w 'HTTP=%{http_code}\n' \
  "$API_ENDPOINT/quotes" || rc=$?

printf 'curl_exit=%s\n' "$rc"
cat ../evidence/unsigned.body.json
printf '\n'
rg -i '^(x-request-id|apigw-requestid):' \
  ../evidence/unsigned.headers.txt
```

Expect HTTP `403` and exit code `22`. API Gateway rejects the request before
invoking the function. Successful `/health` does not prove access to `/quotes`.

Now prove that Lambda was not invoked. No new request is needed:

```bash
UNSIGNED_REQUEST_ID="$(
  awk '
    tolower($1) == "apigw-requestid:" {
      gsub("\r", "", $2)
      print $2
    }
  ' ../evidence/unsigned.headers.txt
)"

aws logs tail "$API_LOG_GROUP" \
  --since 10m \
  --region "$AWS_REGION" \
  --format short \
  > ../evidence/unsigned-api.log

aws logs tail "$FUNCTION_LOG_GROUP" \
  --since 10m \
  --region "$AWS_REGION" \
  --format short \
  > ../evidence/unsigned-function.log

printf 'REQUEST_ID=%s\n' "$UNSIGNED_REQUEST_ID"

printf '%s\n' '===== API Gateway ====='
rg -F "$UNSIGNED_REQUEST_ID" ../evidence/unsigned-api.log

printf '%s\n' '===== Lambda ====='
if rg -F "$UNSIGNED_REQUEST_ID" ../evidence/unsigned-function.log; then
  echo 'UNEXPECTED: Lambda was invoked'
else
  echo 'EXPECTED: Lambda was not invoked'
fi
```

### 10.2. Invalid Values and Malformed JSON

The `invalid-quote.json` file is syntactically valid, but `quantity` violates the
allowed range of `1–100`.

```bash
rc=0

../scripts/invoke-api.sh \
  "$API_ENDPOINT" \
  "$AWS_REGION" \
  ../requests/invalid-quote.json \
  ../evidence/invalid-quote || rc=$?

printf 'script_exit=%s\n' "$rc"
printf 'HTTP='
cat ../evidence/invalid-quote.status.txt
jq . ../evidence/invalid-quote.body.json

rg -i '^(x-request-id|apigw-requestid):' \
  ../evidence/invalid-quote.headers.txt
```

Here, the expected model is different:

```text
AWS_IAM allowed the request
-> API Gateway invoked Lambda
-> Lambda recognized the client error
-> Lambda returned a valid proxy response
-> the client received HTTP 422
```

`script_exit=22` means only that `curl --fail-with-body` received an HTTP `4xx` response.
It is not the Lambda exit code.

Confirm normal handler execution through the logs:

```bash
INVALID_REQUEST_ID="$(
  jq -r '.request_id' ../evidence/invalid-quote.body.json
)"

aws logs tail "$API_LOG_GROUP" \
  --since 10m \
  --region "$AWS_REGION" \
  --format short \
  > ../evidence/invalid-quote-api.log

aws logs tail "$FUNCTION_LOG_GROUP" \
  --since 10m \
  --region "$AWS_REGION" \
  --format short \
  > ../evidence/invalid-quote-function.log

printf 'REQUEST_ID=%s\n' "$INVALID_REQUEST_ID"

printf '%s\n' '===== API Gateway ====='
rg -F "$INVALID_REQUEST_ID" ../evidence/invalid-quote-api.log

printf '%s\n' '===== Lambda ====='
rg -F "$INVALID_REQUEST_ID" ../evidence/invalid-quote-function.log
```

Therefore:

```text
HTTP 422 ≠ Lambda invocation failure
HTTP 422 = expected result of its validation
```

### 10.3. Malformed JSON

```bash
printf '{' > ../evidence/malformed.json

rc=0

../scripts/invoke-api.sh \
  "$API_ENDPOINT" \
  "$AWS_REGION" \
  ../evidence/malformed.json \
  ../evidence/malformed-response || rc=$?

printf 'script_exit=%s\n' "$rc"
printf 'HTTP='
cat ../evidence/malformed-response.status.txt
jq . ../evidence/malformed-response.body.json

rg -i '^(x-request-id|apigw-requestid):' \
  ../evidence/malformed-response.headers.txt

INVALID_REQUEST_ID="$(
  jq -r '.request_id' ../evidence/malformed-response.body.json
)"

aws logs tail "$API_LOG_GROUP" \
  --since 10m \
  --region "$AWS_REGION" \
  --format short \
  > ../evidence/malformed-response-api.log

aws logs tail "$FUNCTION_LOG_GROUP" \
  --since 10m \
  --region "$AWS_REGION" \
  --format short \
  > ../evidence/malformed-response-function.log

printf 'REQUEST_ID=%s\n' "$INVALID_REQUEST_ID"

printf '%s\n' '===== API Gateway ====='
rg -F "$INVALID_REQUEST_ID" ../evidence/malformed-response-api.log

printf '%s\n' '===== Lambda ====='
rg -F "$INVALID_REQUEST_ID" ../evidence/malformed-response-function.log
```

Malformed JSON is handled correctly:

```text
HTTP=400
error=invalid_json
x-request-id = apigw-requestid
API log: status 400
Lambda log: request_completed, 400
```

### 10.4. Unknown Route

`POST /quotes` exists, but `GET /quotes` is a different route.

```bash
curl -sS -i --connect-timeout 5 --max-time 15 "$API_ENDPOINT/missing"
curl -sS -i --connect-timeout 5 --max-time 15 "$API_ENDPOINT/quotes"
```

Both unknown route keys are rejected by API Gateway with `404`.

In both responses:

- `apigw-requestid` is present — the request was handled by API Gateway;
- `x-request-id` is absent — the response was not produced by our Lambda;
- `GET /quotes` does not go through the `AWS_IAM` authorization check because
only the existing `POST /quotes` route is protected;
- `$default` is the stage name, not a catch-all route.

Errors occur at different layers:

| Request                            |  HTTP | Who produced the response | Lambda invoked              |
| ---------------------------------- | ----: | ------------------------- | --------------------------- |
| Unsigned `POST /quotes`            | `403` | API Gateway               | no                          |
| `POST /quotes` with `quantity: 0`  | `422` | Lambda                    | yes, completed successfully |
| `POST /quotes` with malformed JSON | `400` | Lambda                    | yes, completed successfully |
| `GET /missing`                     | `404` | API Gateway               | no                          |
| `GET /quotes`                      | `404` | API Gateway               | no                          |

Indicators of an API Gateway response:

```text
apigw-requestid is present
x-request-id is absent
```

Indicators of a handler response:

```text
apigw-requestid is present
x-request-id is present
body.request_id matches both headers
```

## 11. Integration Failure Drill

Change only this transition:

```text
client → API Gateway              remains
route and integration             remain
API Gateway → Lambda permission   is temporarily removed
```

`terraform.tfvars` must continue to contain `enable_api_invoke_permission = true`.
The value passed with `-var` below applies only to that command, but the change
applied in AWS remains until it is restored.

```bash
terraform plan -var='enable_api_invoke_permission=false' -out=tfplan-deny
terraform show -no-color tfplan-deny | less
terraform apply tfplan-deny
```

The plan should remove only the two `aws_lambda_permission.api_route` entries.

None of the following should change:

```text
API Gateway
routes
integration
Lambda
IAM execution role
log groups
```

Then verify the actual Lambda resource policy:

```bash
policy_rc=0

aws lambda get-policy \
  --function-name "$FUNCTION_NAME" \
  --region "$AWS_REGION" \
  --output json || policy_rc=$?

printf 'get-policy exit=%s\n' "$policy_rc"
```

Expected:

```text
ResourceNotFoundException:
The resource you requested does not exist.
get-policy exit=254
```

Here, `ResourceNotFoundException` does not mean that the Lambda function is missing.
It means that the existing function no longer has a resource-based policy: both policy
statements were removed.

Send a request while the permission is absent:

```bash
rc=0

curl -sS --fail-with-body \
  --connect-timeout 5 \
  --max-time 15 \
  -D ../evidence/integration-denied.headers.txt \
  -o ../evidence/integration-denied.body.json \
  -w 'HTTP=%{http_code}\n' \
  "$API_ENDPOINT/health" || rc=$?

printf 'curl_exit=%s\n' "$rc"
jq . ../evidence/integration-denied.body.json

rg -i '^(x-request-id|apigw-requestid):' \
  ../evidence/integration-denied.headers.txt
```

Expected:

```text
HTTP=500
curl_exit=22
```

The body should contain a generic API Gateway error:

```json
{
  "message": "Internal Server Error"
}
```

Headers:

```text
apigw-requestid is present
x-request-id is absent
```

Difference from the previous errors:

```text
403 → the request was stopped by authorization
404 → the route was not found
500 → the route and integration were found, but API Gateway cannot invoke Lambda
```

Now prove the cause through the access log and confirm that Lambda was not invoked.

```bash
DENIED_REQUEST_ID="$(
  awk '
    tolower($1) == "apigw-requestid:" {
      gsub("\r", "", $2)
      print $2
    }
  ' ../evidence/integration-denied.headers.txt
)"

aws logs tail "$API_LOG_GROUP" \
  --since 10m \
  --region "$AWS_REGION" \
  --format short \
  > ../evidence/integration-denied-api.log

aws logs tail "$FUNCTION_LOG_GROUP" \
  --since 10m \
  --region "$AWS_REGION" \
  --format short \
  > ../evidence/integration-denied-function.log

printf 'REQUEST_ID=%s\n' "$DENIED_REQUEST_ID"

printf '%s\n' '===== API Gateway ====='
rg -F "$DENIED_REQUEST_ID" ../evidence/integration-denied-api.log

printf '%s\n' '===== Lambda ====='
if rg -F "$DENIED_REQUEST_ID" ../evidence/integration-denied-function.log; then
  echo 'UNEXPECTED: Lambda was invoked'
else
  echo 'EXPECTED: Lambda was not invoked'
fi
```

The integration failure is now fully proven:

```text
API Gateway accepted GET /health
route was found
integration was selected
API Gateway does not have permission to invoke Lambda
API Gateway returned 500
Lambda was not invoked
```

Restore permissions even if the demonstration was inconclusive:

```bash
terraform plan -out=tfplan-restore
terraform show -no-color tfplan-restore | less
terraform apply tfplan-restore

curl -sS --fail-with-body \
  --connect-timeout 5 \
  --max-time 15 \
  -o ../evidence/restored-health.body.json \
  -w 'health HTTP=%{http_code}\n' \
  "$API_ENDPOINT/health"

../scripts/invoke-api.sh \
  "$API_ENDPOINT" \
  "$AWS_REGION" \
  ../requests/quote.json \
  ../evidence/restored-quote

printf 'quote HTTP='
cat ../evidence/restored-quote.status.txt

jq . ../evidence/restored-health.body.json
jq . ../evidence/restored-quote.body.json

plan_rc=0
terraform plan \
  -detailed-exitcode \
  -no-color \
  > ../evidence/final-plan.txt || plan_rc=$?

printf 'terraform_plan_exit=%s\n' "$plan_rc"
tail -n 5 ../evidence/final-plan.txt
```

Recovery is confirmed:

```text
GET /health → HTTP 200
POST /quotes → HTTP 200
calculation 1250 × 3 = 3750
both requests received new request_id values
Terraform plan exit 0
no residual drift
```

Controlled drift is performed in four required stages:

```text
1. Limited plan
   -> only the two aws_lambda_permission resources are removed

2. Failure demonstration
   -> API Gateway returns 500
   -> integration_error reports the missing permission
   -> Lambda is not invoked

3. Restore the normal configuration
   -> enable_api_invoke_permission=true from terraform.tfvars
   -> both permissions are created again

4. Final verification
   -> GET /health returns 200
   -> POST /quotes returns 200
   -> terraform plan -detailed-exitcode returns 0
```

### Section Summary

The experiment separated two types of failures:

```text
Lambda permission is missing
-> API Gateway finds the route
-> API Gateway cannot invoke Lambda
-> the client receives 500
-> integration_error contains the cause
-> no Lambda log is created
-> Lambda Errors do not necessarily increase
```

After recovery:

```text
both permissions are created again
-> both routes work again
-> the final plan is empty
```

## 12. Load Controls

The stage defines a rate of `5` and a burst of `10` for each route.

Mental model:

- `burst=10` allows a short traffic spike;
- `rate=5` defines how quickly the available request capacity is replenished afterward;
- when the limit is exceeded, API Gateway may return `429 Too Many Requests`.

This is an API Gateway limit, not Lambda concurrency and not a financial limit.

Experiment: exactly `40` requests to your own `/health`.
It may produce `429`, but need not: the outcome depends on request speed,
burst capacity, and account limits. Do not keep increasing load just to force a status code.

```bash
for _ in {1..40}; do
  curl -sS --connect-timeout 5 --max-time 15 -o /dev/null \
    -w '%{http_code}\n' "$API_ENDPOINT/health"
done | sort | uniq -c
```

If you receive `429`, let the API recover before further checks.
Real retry policies use bounded attempts, backoff, and jitter.
For POST, first establish whether the operation is safe to repeat.

The experiment result should be interpreted only as follows:

| Result                   | What is proven                                     |
| ------------------------ | -------------------------------------------------- |
| `429` is present         | API Gateway actually applied throttling            |
| All responses are `200`  | This series of requests did not trigger throttling |
| `get-stage` shows `5/10` | Throttling is configured                           |

All `200` responses do not prove that no limit exists. Sequential requests may run
slowly enough for the available capacity to recover between them.

Client strategy for `429`:

```text
limited number of attempts
→ exponential backoff
→ random jitter
→ stop retrying after the configured limit
```

## 13. Troubleshooting

| Symptom | What to check |
|---|---|
| Signed POST returns `403` | IAM `execute-api:Invoke`, profile, signing Region, system clock, and session token |
| URL ending in `/dev` returns `404` | Use `api_endpoint` without a suffix for the `$default` stage |
| POST returns `400/422` | Send `requests/quote.json`, not an `events/` envelope |
| API returns `500`, Lambda logs are empty | `get-policy`, `enable_api_invoke_permission`, `integration_error` |
| API returns `502` | Function exceptions, runtime logs, and proxy response contract |
| Empty body and HTTP `000` | DNS/TLS/network/timeout; this is not an API status |
| No access logs | `get-stage`, log group ARN, deployment permissions for log delivery |
| Browser reports CORS | Separate browser policy; `curl` does not enforce CORS |

Use the following diagnostic sequence:

```text
1. Does curl show HTTP 000?
   └─ check DNS, TLS, network connectivity, and the client timeout

2. Is there an HTTP response with apigw-requestid?
   └─ the request reached API Gateway

3. Is x-request-id present?
   ├─ yes → the response was produced by Lambda
   └─ no  → the response was produced before the handler

4. Is there an API access log entry for the request ID?
   └─ check status, route, and integration_error

5. Is there a Lambda log entry with the same api_request_id?
   ├─ yes → analyze the handler and lambda_request_id
   └─ no  → check the route, authorization, and Lambda resource policy
```

Limitations of the current lab:

- a successful health check proves only that `GET /health` worked at the time of the request;
- CloudWatch metrics arrive with a delay;
- alarms are created, but `alarm_actions` are not configured, so there are no notifications;
- this is a dev configuration, not a production-ready model.

## 14. Completion Checklist

- [ ] 19 local checks and 10 native tests pass.
- [ ] Two explicit HTTP routes exist and quotes requires IAM.
- [ ] Health returns `200`; a signed quote returns `3750`.
- [ ] An unsigned POST returns `403`.
- [ ] Malformed JSON/invalid values return `400/422`.
- [ ] Unknown paths and the wrong method return `404`.
- [ ] One request ID appears in the response and both log groups.
- [ ] The invocation-permission failure has been reproduced and repaired.
- [ ] Both routes work after restoration; final plan exit code is `0`.

## 15. Cleanup

```bash
terraform plan -destroy -out=tfplan-destroy
terraform show -no-color tfplan-destroy | less
terraform apply tfplan-destroy
```

Verify that Terraform tracks no remaining resources:

```bash
terraform state list
```

## 16. Final Model

The client passes route authorization. API Gateway independently needs permission to
invoke Lambda. The function calculates a result and returns the HTTP contract, which API
Gateway forwards to the client. The execution role controls the function's own AWS access.

For diagnosis, first locate the failing layer: network, route, caller IAM,
integration, or handler. Then correlate the HTTP response with logs using the request ID.

## 17. Official References

- [HTTP API Lambda proxy integration and payload v2](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-develop-integrations-lambda.html)
- [HTTP API IAM authorization](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-access-control-iam.html)
- [IAM policy for invoking an API](https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-control-access-using-iam-policies-to-invoke-api.html)
- [Lambda errors through API Gateway](https://docs.aws.amazon.com/lambda/latest/dg/services-apigateway-errors.html)
- [HTTP API integration troubleshooting](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-troubleshooting-lambda.html)
- [HTTP API throttling](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-throttling.html)
- [HTTP API metrics](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-metrics.html)
- [AWS CLI credential export](https://docs.aws.amazon.com/cli/latest/reference/configure/export-credentials.html)
