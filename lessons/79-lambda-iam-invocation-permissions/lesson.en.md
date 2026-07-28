# Lesson 79. Lambda IAM and Invocation Permissions

## 1. Why This Lesson Exists

In lesson 78, we created a Lambda function, invoked it with the AWS CLI, and
learned that caller identity and execution role have different responsibilities.
This lesson explores that boundary in detail.

The central question is:

```text
Why can one identity invoke a function while another receives AccessDenied?
```

Looking only at the execution role is not enough. The invocation decision can
depend on:

- the caller's identity-based policy;
- the Lambda function's resource-based policy;
- the trust policy of a role assumed through STS;
- permissions boundaries, session policies, and AWS Organizations SCPs;
- an explicit `Deny` in any applicable policy.

The lab tests three modes in sequence:

```text
none     -> AccessDenied
lambda_caller_identity_policy -> Allow in the Lambda caller role
function_resource_policy -> Allow in the function resource policy
```

## 2. Outcomes

After this lesson, you will be able to:

- distinguish operator identity, Lambda caller role, and function execution role;
- explain the difference between authentication and authorization;
- distinguish a trust policy, identity-based policy, and resource-based policy;
- assume an IAM role safely through `sts:AssumeRole`;
- reproduce and diagnose `AccessDeniedException`;
- grant `lambda:InvokeFunction` for exactly one function;
- inspect a role policy and Lambda resource policy with the AWS CLI;
- explain why cross-account invocation is stricter than same-account invocation.

## 3. Mental Model

### 3.1. Four Participants

Four different entities participate in this lab:

| Entity | Responsibility |
|---|---|
| Operator identity | Runs Terraform and assumes the Lambda caller role |
| Lambda caller role | Calls Lambda and passes the authorization check |
| Lambda service | Accepts the API request and starts the function |
| Function execution role | Grants permissions to Python code during execution |

Names used by the lab:

| Purpose | Terraform address | AWS name |
|---|---|---|
| Lambda function | `aws_lambda_function.greeting` | `lab79-dev-lambda-function` |
| Lambda caller role | `aws_iam_role.lambda_caller` | `lab79-dev-role-lambda-caller` |
| Invoke policy on that role | `aws_iam_role_policy.lambda_caller_invoke_access` | `lab79-dev-policy-for-role-lambda-caller-allow-invoke-function` |
| Permission on the function | `aws_lambda_permission.function_allows_lambda_caller` | statement `AllowLambdaCallerInvoke` |
| Running function role | `aws_iam_role.function_execution` | `lab79-dev-role-lambda-execution` |
| Log write policy | `aws_iam_role_policy.function_log_access` | `lab79-dev-policy-for-role-lambda-execution-allow-write-logs` |

The flow is:

```text
operator identity
    | terraform apply
    | sts:AssumeRole
    v
Lambda caller role
    |
    | lambda:InvokeFunction
    v
Lambda service
    | IAM authorizes the API call
    | sts:AssumeRole
    v
function execution role
    | the handler is invoked
    | logs:CreateLogStream / logs:PutLogEvents
    v
CloudWatch Logs
```

The function execution role does not invoke the function. Lambda assumes it
after invocation begins so the handler can call permitted AWS APIs.

### 3.2. Authentication and Authorization

Authentication answers:

```text
Who sent the request?
```

Authorization answers:

```text
May this identity perform this action on this resource?
```

This command:

```bash
aws sts get-caller-identity
```

shows the current identity, but it does not prove that the identity may perform
`lambda:InvokeFunction`.

### 3.3. Three Policy Types in the Lab

A trust policy belongs to an IAM role and defines who may perform `sts:AssumeRole`.

```text
Lambda caller role trust policy:
Principal = operator IAM role

Function execution role trust policy:
Principal = lambda.amazonaws.com
```

An identity-based policy is attached to an IAM user or role and defines which
AWS APIs that identity may call.

A resource-based policy is attached to a resource. For Lambda, it defines which
principals may invoke the function.

An IAM role trust policy is technically also a resource-based policy, but it
protects a different resource and action:

```text
role trust policy       -> who may perform sts:AssumeRole
Lambda resource policy  -> who may perform lambda:InvokeFunction
```

### 3.4. How AWS Makes the Decision

A simplified same-account model is:

```text
matching Allow
+ no applicable explicit Deny
= request allowed
```

Without a matching `Allow`, the result is an implicit deny.

An explicit deny overrides an allow. Permission in a Lambda resource policy
therefore cannot bypass an SCP, permissions boundary, or another applicable
policy that explicitly denies the request.

Cross-account invocation normally requires both sides:

```text
identity policy in the caller account
+ function resource policy in the owner account
```

Both participants in this lab are in one account, which lets us compare
identity-based and resource-based grants independently.

Which policies participate at each transition:

| Transition                      | What is checked                                                    |
| ------------------------------- | ------------------------------------------------------------------ |
| Operator → Terraform APIs       | Policies of the operator/deployment identity                       |
| Operator → Lambda caller role   | Trust policy of the Lambda caller role and applicable restrictions |
| Lambda caller role → Lambda     | Identity policy of the role and/or resource policy of the function |
| Lambda service → Function execution role | Trust policy of the function execution role              |
| Handler → CloudWatch Logs       | Identity policy of the function execution role                     |

What each successful step proves:

| Successful operation      | What it actually proves                                  |
| ------------------------- | -------------------------------------------------------- |
| `terraform apply`         | The operator can create/change resources                 |
| `sts:AssumeRole`          | The operator can assume the Lambda caller role           |
| `sts get-caller-identity` | AWS recognized the current credentials                   |
| `lambda invoke`           | The current identity is allowed to invoke the function   |
| Handler response appeared | The handler was actually invoked                         |
| CloudWatch log appeared   | The execution role had the required permissions for Logs |

## 4. Lab Architecture

Terraform creates:

- one Python Lambda function;
- a separate function execution role only for CloudWatch Logs;
- a separate Lambda caller role;
- one of two ways to grant `lambda:InvokeFunction`.

This variable selects the mode:

```hcl
invoke_permission_mode = "none"
```

Allowed values are:

| Mode | Policy on Lambda caller role | Lambda resource policy | Result |
|---|---:|---:|---|
| `none` | no | no | `AccessDeniedException` |
| `lambda_caller_identity_policy` | yes | no | invocation succeeds |
| `function_resource_policy` | no | yes | invocation succeeds in the same account |

Native Terraform tests verify that the modes do not overlap.

## 5. Local Tests

From the repository root, run:

```bash
python3 -m unittest discover \
  -s lessons/79-lambda-iam-invocation-permissions/lab_79/tests -v

for script in lessons/79-lambda-iam-invocation-permissions/lab_79/scripts/*.sh; do
    echo "Checking $script"
    bash -n "$script" || exit 1
done
```

Then run:

```bash
cd lessons/79-lambda-iam-invocation-permissions/lab_79/terraform
terraform init
terraform fmt -check -recursive
terraform validate
terraform test
```

`terraform test` uses a mock AWS provider. It verifies the Terraform
configuration shape, but not real IAM propagation or an actual Lambda
invocation.

## 6. Prepare the Operator Principal

### 6.1. Why an STS Session ARN Is Wrong Here

After an SSO login, `aws sts get-caller-identity` often returns:

```text
arn:aws:sts::123456789012:assumed-role/ROLE_NAME/SESSION_NAME
```

This is the ARN of a temporary STS session. The trust policy needs the stable
IAM role ARN:

```text
arn:aws:iam::123456789012:role/PATH/ROLE_NAME
```

The helper script detects the current identity and resolves the IAM role ARN
when needed:

```bash
chmod +x ../scripts/*.sh
../scripts/resolve-operator-principal.sh
```

The script changes nothing in AWS. For an SSO role, it makes the read-only
`iam:GetRole` call.

### 6.2. Prepare tfvars

Create the local file:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Insert the resolved ARN:

```hcl
operator_iam_principal_arn = "arn:aws:iam::123456789012:role/REAL_ROLE_PATH/ROLE_NAME"
invoke_permission_mode     = "none"
```

Do not commit `terraform.tfvars`: the ARN exposes account structure, and other
labs may place sensitive values in the same file type.

## 7. Phase 1: Expected AccessDenied

### 7.1. Plan and Apply

Verify the current identity:

```bash
aws sts get-caller-identity
```

Create and apply a saved plan:

```bash
terraform plan -out=tfplan-none
terraform apply tfplan-none
```

```bash
terraform show -json tfplan-none |
  jq -r '
    .resource_changes[] |
    "\(.change.actions | join(",")) \(.address)"
  '
```

In `none` mode, the function and both roles exist, but the Lambda caller role has no
`lambda:InvokeFunction` permission and the function has no allowing resource policy.

### 7.2. Invoke Through the Lambda Caller Role

The helper script:

1. assumes the Lambda caller role through STS;
2. keeps temporary credentials only inside its process;
3. invokes Lambda under that role;
4. stores metadata and response separately.

Run:

```bash
../scripts/invoke-as-role.sh \
  "$(terraform output -raw lambda_caller_role_arn)" \
  "$(terraform output -raw function_name)" \
  "$(terraform output -raw aws_region)" \
  ../events/greeting.json \
  ../evidence/none-response.json \
  ../evidence/none-metadata.json

echo "invoke_exit_code=$?"
```

Expected result:

```text
AccessDeniedException
... is not authorized to perform: lambda:InvokeFunction ...
```

A non-zero exit code is success for this drill: it proves that the absence of
an `Allow` produces an implicit deny.

Check that there is no identity policy:

```text
LAMBDA_CALLER_ROLE_NAME="$(
  terraform output -raw lambda_caller_role_arn |
    awk -F/ '{print $NF}'
)"

aws iam list-role-policies \
  --role-name "$LAMBDA_CALLER_ROLE_NAME" \
  --output json |
  jq .
```

Check that there is no Lambda resource policy:

```text
aws lambda get-policy \
  --region "$(terraform output -raw aws_region)" \
  --function-name "$(terraform output -raw function_name)"
```

Full phase 1 chain:

```text
Operator credentials
        |
        | terraform apply
        v
Lambda + roles are created
        |
        | sts:AssumeRole
        v
Lambda caller role session is created
        |
        | lambda:InvokeFunction
        v
IAM policy evaluation
        |
        | identity Allow?  no
        | resource Allow?  no
        | explicit Deny?   not required
        v
Implicit deny
        |
        v
AccessDeniedException
        |
        v
Handler is not invoked
```

Correct error classification:

```text
| Error                                              | Stage                    | What it means                                       |
| -------------------------------------------------- | ------------------------ | --------------------------------------------------- |
| `Unable to locate credentials`                     | Before AWS               | AWS CLI did not find credentials                    |
| `ExpiredToken`                                     | Authentication           | The temporary session has expired                   |
| `AccessDenied` on `sts:AssumeRole`                 | Role assumption          | The operator cannot assume the Lambda caller role   |
| `AccessDeniedException` on `lambda:InvokeFunction` | Invocation authorization | The Lambda caller role has no invoke permission     |
| `ResourceNotFoundException`                        | Lambda lookup            | The function was not found in the specified context |
| `InvalidRequestContentException`                   | Request parsing          | The payload is invalid                              |
| `FunctionError` in metadata                        | Handler already invoked  | The error happened inside the function              |
```

## 8. Phase 2: Identity-Based Permission

Change:

```hcl
invoke_permission_mode = "lambda_caller_identity_policy"
```

Create a fresh plan:

```bash
terraform plan -out=tfplan-identity
terraform apply tfplan-identity
```

Do not reuse `tfplan-none`; that saved plan was built with different input
values.

Terraform adds an inline policy to the Lambda caller role:

```json
{
  "Effect": "Allow",
  "Action": "lambda:InvokeFunction",
  "Resource": "arn:aws:lambda:REGION:ACCOUNT:function:lab79-dev-lambda-function"
}
```

Invoke again:

```bash
../scripts/invoke-as-role.sh \
  "$(terraform output -raw lambda_caller_role_arn)" \
  "$(terraform output -raw function_name)" \
  "$(terraform output -raw aws_region)" \
  ../events/greeting.json \
  ../evidence/identity-response.json \
  ../evidence/identity-metadata.json
```

Expected response:

```json
{
  "message": "Hello, Valerii!",
  "environment": "dev",
  "request_id": "..."
}
```

Inspect the policy:

```bash
LAMBDA_CALLER_ROLE_NAME="$(
  terraform output -raw lambda_caller_role_arn | awk -F/ '{print $NF}'
)"

aws iam get-role-policy \
  --role-name "$LAMBDA_CALLER_ROLE_NAME" \
  --policy-name "$(terraform output -raw caller_invoke_policy_name)" \
  --output json | jq .
```

Confirm that `Action` contains only `lambda:InvokeFunction` and `Resource`
targets only this lab function.

Full phase 2 chain:

```text
Operator identity
    |
    | sts:AssumeRole
    | allowed by the Lambda caller role trust policy
    v
Lambda caller role session
    |
    | lambda:InvokeFunction
    | allowed by the role identity-based policy
    v
Lambda service
    |
    | sts:AssumeRole
    | allowed by the execution role trust policy
    v
Execution role session
    |
    | handler is invoked
    | logs:PutLogEvents
    v
CloudWatch Logs
```

## 9. Phase 3: Lambda Resource-Based Permission

Now compare the other authorization path. Change:

```hcl
invoke_permission_mode = "function_resource_policy"
```

The new plan should contain two important changes:

```text
- remove the inline invoke policy from the Lambda caller role
+ add aws_lambda_permission to the function
```

Apply:

```bash
terraform plan -out=tfplan-resource
terraform apply tfplan-resource
```

Prove that the role no longer has an inline policy:

```bash
aws iam list-role-policies \
  --role-name "$LAMBDA_CALLER_ROLE_NAME" \
  --output json | jq .
```

Inspect the function resource policy:

```bash
aws lambda get-policy \
  --region "$(terraform output -raw aws_region)" \
  --function-name "$(terraform output -raw function_name)" \
  --query Policy \
  --output text | jq .
```

The policy should contain the Lambda caller role ARN as principal and
`lambda:InvokeFunction` as the action.

Invoke again:

```bash
../scripts/invoke-as-role.sh \
  "$(terraform output -raw lambda_caller_role_arn)" \
  "$(terraform output -raw function_name)" \
  "$(terraform output -raw aws_region)" \
  ../events/greeting.json \
  ../evidence/resource-response.json \
  ../evidence/resource-metadata.json
```

Invocation should succeed again, but the `Allow` now belongs to the function,
not the role.

Why is it important to remove the `identity-based policy`?

Imagine Terraform left the policy on the role and additionally created a `resource policy`:

```text
Lambda caller role:
Allow lambda:InvokeFunction

Lambda:
Allow Lambda caller role
```

The invocation would succeed, but we would not be able to prove which permission allowed it.

Possible cases:

- the `identity-based policy` alone was enough
- the `resource-based policy` alone was enough
- both mechanisms worked
- one of them was configured incorrectly

## 10. What the Execution Role Must Not Do

Inspect the execution role:

```bash
FUNCTION_EXECUTION_ROLE_NAME="$(
  terraform output -raw function_execution_role_arn | awk -F/ '{print $NF}'
)"

aws iam list-role-policies \
  --role-name "$FUNCTION_EXECUTION_ROLE_NAME" \
  --output json | jq .
```

It should contain only the logs policy. Inspect it:

```bash
aws iam get-role-policy \
  --role-name "$FUNCTION_EXECUTION_ROLE_NAME" \
  --policy-name "$(terraform output -raw function_logs_policy_name)" \
  --output json | jq .
```

The execution role does not need `lambda:InvokeFunction` because the Python code
does not invoke a function. If the function later needs to invoke another
Lambda, grant permission for that specific function ARN, not `*`.

## 11. Practical Drills

Preparation:

```bash
cd lessons/79-lambda-iam-invocation-permissions/lab_79/terraform

terraform plan -out=tfplan-identity
terraform apply tfplan-identity

CALLER_ROLE_ARN="$(terraform output -raw lambda_caller_role_arn)"
FUNCTION_NAME="$(terraform output -raw function_name)"
REGION="$(terraform output -raw aws_region)"
EVENT="../events/greeting.json"

../scripts/invoke-as-role.sh \
  "$CALLER_ROLE_ARN" \
  "$FUNCTION_NAME" \
  "$REGION" \
  "$EVENT" \
  ../evidence/control-response.json \
  ../evidence/control-metadata.json
```

### Drill 1. Incorrect Function ARN

Under the assumed Lambda caller role, try to invoke a function name that does not
exist.

With the current policy scoped to the `lab79-dev-lambda-function` ARN, expect
`AccessDeniedException`: the grant does not cover a different function name.

```bash
WRONG_FUNCTION="${FUNCTION_NAME}-does-not-exist"

set +e

../scripts/invoke-as-role.sh \
  "$CALLER_ROLE_ARN" \
  "$WRONG_FUNCTION" \
  "$REGION" \
  "$EVENT" \
  ../evidence/exercise-1-response.json \
  ../evidence/exercise-1-metadata.json \
  >../evidence/exercise-1.log 2>&1

set -e

cat ../evidence/exercise-1.log
```

Explain how that result differs from `ResourceNotFoundException`:

- `AccessDeniedException` means authorization stopped the request;
- `ResourceNotFoundException` is possible when an applicable policy allows the
  request for that ARN, but the function does not exist in the selected Region.

AWS services do not reveal resource existence uniformly in every IAM scenario;
a service can deliberately return access denied to avoid information
disclosure.

### Drill 2. Verify Scope

Create a second temporary Lambda function to temporarily extend the lab.
Prove that a policy scoped to the `lab79-dev-lambda-function` ARN cannot invoke another
function.

Do not expand `Resource` to `*` for convenience.

The script creates a temporary function using the existing execution role, verifies that invocation is denied, and then deletes it.

```bash
TEMP_FUNCTION="lab79-dev-temp-$(date +%s)"
BUILD_DIR="$(mktemp -d)"

EXECUTION_ROLE_ARN="$(
  terraform output -raw function_execution_role_arn
)"

RUNTIME="$(
  aws lambda get-function-configuration \
    --region "$REGION" \
    --function-name "$FUNCTION_NAME" \
    --query Runtime \
    --output text
)"

cat >"$BUILD_DIR/handler.py" <<'PY'
def lambda_handler(event, context):
    return {
        "message": "Temporary Lambda was invoked",
        "request_id": context.aws_request_id,
    }
PY

(
  cd "$BUILD_DIR"
  python3 -m zipfile -c function.zip handler.py
)

aws lambda create-function \
  --region "$REGION" \
  --function-name "$TEMP_FUNCTION" \
  --runtime "$RUNTIME" \
  --role "$EXECUTION_ROLE_ARN" \
  --handler handler.lambda_handler \
  --zip-file "fileb://$BUILD_DIR/function.zip" \
  >/dev/null

aws lambda wait function-active-v2 \
  --region "$REGION" \
  --function-name "$TEMP_FUNCTION"

echo "Temporary function created: $TEMP_FUNCTION"
```

Invocation using the Lambda caller role:

```bash
set +e

../scripts/invoke-as-role.sh \
  "$CALLER_ROLE_ARN" \
  "$TEMP_FUNCTION" \
  "$REGION" \
  "$EVENT" \
  ../evidence/exercise-2-response.json \
  ../evidence/exercise-2-metadata.json \
  >../evidence/exercise-2.log 2>&1

set -e

cat ../evidence/exercise-2.log
```

Deletion of the temporary function:

```bash
aws lambda delete-function \
  --region "$REGION" \
  --function-name "$TEMP_FUNCTION"

rm -rf "$BUILD_DIR"

echo "Temporary function deleted"
```
Verification that the function was deleted:

```bash
set +e

aws lambda get-function \
  --region "$REGION" \
  --function-name "$TEMP_FUNCTION"

set -e
```

### Drill 3. Return to `none`

After the successful `function_resource_policy` phase, set:

```bash
terraform plan -var='invoke_permission_mode=none' -out=tfplan-none
terraform apply tfplan-none
```

Apply a fresh plan and prove that invocation is denied again. This confirms
that the earlier success came from the specific `Allow`, not residual access.

Verify that no inline policy is attached:

```bash
LAMBDA_CALLER_ROLE_NAME="$(
  terraform output -raw lambda_caller_role_arn |
    awk -F/ '{print $NF}'
)"

aws iam list-role-policies \
  --role-name "$LAMBDA_CALLER_ROLE_NAME" \
  --output json |
  jq .
```

Verify that no resource policy is attached:

```bash
set +e

aws lambda get-policy \
  --region "$REGION" \
  --function-name "$FUNCTION_NAME"

POLICY_RC=$?

set -e

echo "get_policy_exit_code=$POLICY_RC"
```

Final invocation check:

```bash
set +e

../scripts/invoke-as-role.sh \
  "$CALLER_ROLE_ARN" \
  "$FUNCTION_NAME" \
  "$REGION" \
  "$EVENT" \
  ../evidence/exercise-3-response.json \
  ../evidence/exercise-3-metadata.json \
  >../evidence/exercise-3.log 2>&1

INVOKE_RC=$?

set -e

cat ../evidence/exercise-3.log
echo "invoke_exit_code=$INVOKE_RC"
```

## 12. Troubleshooting

### `operator_iam_principal_arn must be an IAM role or user ARN`

You passed an STS session ARN:

```text
arn:aws:sts::...:assumed-role/...
```

Run `resolve-operator-principal.sh` or find the underlying IAM role ARN:

```bash
aws iam get-role --role-name ROLE_NAME --query Role.Arn --output text
```

### `AccessDenied` During `sts:AssumeRole`

Check:

- whether the current operator identity matches `operator_iam_principal_arn`;
- whether the latest Terraform plan was applied;
- whether a permissions boundary, session policy, or SCP denies
  `sts:AssumeRole`;
- whether the IAM role was recreated with a different ARN.

Inspect the trust policy:

```bash
aws sts get-caller-identity

CALLER_ROLE_NAME="$(
  terraform output -raw lambda_caller_role_arn |
  awk -F/ '{print $NF}'
)"

aws iam get-role \
  --role-name "$LAMBDA_CALLER_ROLE_NAME" \
  --query 'Role.AssumeRolePolicyDocument' \
  --output json | jq .
```

### Invoke Still Returns `AccessDenied` After Apply

IAM changes do not propagate instantly. Wait a few seconds and retry with a new
STS session. The helper script creates a new session on each run.

Also check:

```bash
terraform output -raw invoke_permission_mode
```

### `aws lambda get-policy` Returns `ResourceNotFoundException`

The function has no resource policy in `none` and `lambda_caller_identity_policy`
modes, so this response is expected. The command should return a policy only
in `function_resource_policy` mode.

### Role Policy Exists but Invocation Is Denied

Check:

- the exact function ARN in `Resource`;
- Region;
- qualifier when invoking a version or alias;
- permissions boundary;
- session policy;
- Organizations SCP;
- explicit deny.

```bash
aws iam get-role-policy \
  --role-name "$CALLER_ROLE_NAME" \
  --policy-name "$(terraform output -raw caller_invoke_policy_name)" \
  --output json |
  jq '.PolicyDocument.Statement'
```

The policy evaluator considers all applicable controls, not one document.

### The Helper Script Does Not Show Metadata

For an API-level `AccessDenied`, Lambda did not accept the invocation, so there
is no normal successful Lambda API metadata. Inspect AWS CLI stderr and its exit
code `echo $?`.

### Checkov Reports VPC, KMS, DLQ, X-Ray, Or Code-Signing Findings

These are expected generic findings for a small synchronous training function.
Lesson 79 verifies the IAM authorization path and does not add unrelated resources:

- a VPC is needed only when the function must reach private VPC resources;
- this lab stores non-secret configuration and relies on AWS-managed encryption;
- a DLQ is relevant to asynchronous invocation paths, while this lesson uses
  synchronous invocation;
- X-Ray, code signing, customer-managed KMS keys, and longer log retention are
  valid production decisions but belong to later reliability and delivery
  lessons.

## 13. Completion Check

Before cleanup, confirm that:

- Python unit tests passed;
- `terraform validate` and `terraform test` passed;
- `none` ended with the expected `AccessDeniedException`;
- `lambda_caller_identity_policy` invoked the function through a policy on the role;
- `function_resource_policy` invoked it through a policy on Lambda;
- the execution role contains only log permissions;
- temporary STS credentials were not written to evidence.

Files under `lab_79/evidence/` are temporary results. Do not commit them without
reviewing and redacting operational metadata.

## 14. Cleanup

All modes are managed by one Terraform root. Save the function name and Region
before deleting the resources:

```bash
FUNCTION_NAME="$(terraform output -raw function_name)"
LAB_AWS_REGION="$(terraform output -raw aws_region)"

terraform destroy

aws lambda get-function \
  --region "$LAB_AWS_REGION" \
  --function-name "$FUNCTION_NAME"
```

The final command should return `ResourceNotFoundException`.

## 15. Final Model

```text
trust policy
    -> who may assume a role

identity-based policy
    -> what an IAM identity may do

Lambda resource-based policy
    -> which principal may invoke the function

execution role
    -> what the handler may do after it starts
```

Key conclusions:

1. Deployment, invocation, and runtime execution use different identities.
2. Having credentials proves authentication, not authorization.
3. The absence of a matching allow produces an implicit deny.
4. An explicit deny overrides an allow.
5. Same-account Lambda invocation can be granted through an identity policy or
   resource policy; cross-account invocation normally requires both sides.
6. Least privilege means minimal `Action`, `Resource`, and trusted principal,
   not merely a short JSON policy.

## 16. Official References

- [AWS Lambda permissions](https://docs.aws.amazon.com/lambda/latest/dg/lambda-permissions.html)
- [Identity-based and resource-based policies](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_identity-vs-resource.html)
- [IAM policy evaluation logic](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_evaluation-logic.html)
- [IAM role trust policies](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_manage_modify.html)
- [AWS CLI `lambda invoke`](https://docs.aws.amazon.com/cli/latest/reference/lambda/invoke.html)
- [Terraform `aws_lambda_permission`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_permission)
