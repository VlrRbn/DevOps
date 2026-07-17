# Lab 78

This lab deploys one Python Lambda function with:

- a dedicated IAM execution role;
- least-privilege CloudWatch Logs permissions;
- an explicitly managed log group;
- a ZIP package built by Terraform;
- bounded timeout and memory, with optional concurrency reservation.

## Execution Flow

```text
AWS invokes `lambda_handler`
        ↓
Reads `event["name"]`
        ↓
Missing `name` -> `"world"`
        ↓
`build_greeting` validates the type
        ↓
Trims whitespace
        ↓
Rejects an empty string
        ↓
Builds `"Hello, <name>!"`
        ↓
Reads the AWS request ID
        ↓
Reads `APP_ENV`
        ↓
Writes a structured JSON log record
        ↓
Returns a result dictionary
```

## Layout

```text
lab_78/
├── app/
│   └── lambda_function.py
├── events/
│   ├── hello.json
│   ├── invalid-event.json
│   └── invalid-name.json
├── evidence/
│   └── .gitkeep
├── tests/
│   └── test_lambda_function.py
└── terraform/
    ├── .gitignore
    ├── .terraform.lock.hcl
    ├── main.tf
    ├── outputs.tf
    ├── providers.tf
    ├── terraform.tfvars.example
    ├── variables.tf
    └── versions.tf
```

Use the commands in `lesson.ru.md` or `lesson.en.md`. Do not commit generated
ZIP packages, Terraform state, plans, invocation responses, or logs.

Invocation commands save temporary results under `evidence/`. The repository
ignores these generated files while keeping the empty directory.
