# Lab 79

This lab extends lesson 78 with explicit Lambda invocation authorization.

## Authorization Modes

| Mode | Identity policy on Lambda caller role | Function resource policy | Expected result |
|---|---:|---:|---|
| `none` | no | no | `AccessDeniedException` |
| `lambda_caller_identity_policy` | yes | no | invocation succeeds |
| `function_resource_policy` | no | yes | invocation succeeds in the same account |

The function execution role is separate in every mode. It writes function logs
and does not receive `lambda:InvokeFunction`.

## Layout

```text
lab_79/
├── app/
│   └── lambda_function.py
├── events/
│   └── greeting.json
├── evidence/
│   └── .gitkeep
├── scripts/
│   ├── invoke-as-role.sh
│   └── resolve-operator-principal.sh
├── tests/
│   └── test_lambda_function.py
└── terraform/
    ├── tests/
    │   └── invocation_modes.tftest.hcl
    ├── .gitignore
    ├── .terraform.lock.hcl
    ├── function_execution_role.tf
    ├── function_invoke_permissions.tf
    ├── lambda.tf
    ├── locals.tf
    ├── outputs.tf
    ├── providers.tf
    ├── terraform.tfvars.example
    ├── lambda_caller_role.tf
    ├── variables.tf
    └── versions.tf
```

## Safety

- No IAM users or long-lived access keys are created.
- Temporary STS credentials remain inside `invoke-as-role.sh`.
- The Lambda caller role is trusted only by `operator_iam_principal_arn`.
- Identity-based invocation permission targets one function ARN.
- Generated evidence and Terraform runtime files are ignored.

Use the commands in `lesson.ru.md` or `lesson.en.md`. Do not commit generated
ZIP packages, Terraform state, plans, invocation responses, or logs.

Invocation commands save temporary results under `evidence/`. The repository
ignores these generated files while keeping the empty directory.

Starting with `invoke_permission_mode = "none"` is intentional: the first invocation must fail.
