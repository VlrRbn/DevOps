# Урок 67. Terraform Native Tests

**Дата:** 2026-05-31

**Фокус:** защитить Terraform module contracts через native `.tftest.hcl` tests.

**Подход:** contract не заканчивается на документации. Contract заканчивается там, где regression автоматически падает.

---

## Зачем этот урок

Урок 66 сделал contract для `modules/network` явным:

- valid inputs
- rejected inputs
- preconditions
- stable outputs
- tagging rules
- breaking-change policy

Будущий change может случайно:

- ослабить `project_name` validation
- принять плохой AMI value
- разрешить single-subnet topology
- дать caller перезаписать governance tags
- переименовать output, который использует CI или release script
- изменить output с string на object
- удалить precondition, потому что он кажется redundant

Урок 67 добавляет Terraform native tests, чтобы module contract стал executable.

Цель не в том, чтобы тестировать AWS. Цель в том, чтобы тестировать interface module до плохого `apply`.

---

## Что должен уметь после урока

- объяснить, где `terraform test` находится в Terraform quality chain
- писать `.tftest.hcl` для module contract checks
- использовать `mock_provider`, чтобы не создавать AWS resources
- тестировать valid input combinations
- тестировать expected failures через `expect_failures`
- тестировать stable outputs через mocked `apply`
- отделять fast native tests от live AWS proof drills
- понимать, какое module behavior стоит покрывать native test
- понимать lifecycle native test: setup, run, assert, teardown
- debug common native test failures вроде `Unknown condition value`
- читать failed test output без гадания
- собирать proof artifacts для CI/local evidence

---

## Быстрый маршрут

1. Добавь native test files в `lab_67/terraform/modules/network/tests/`.
2. Добавь mocked AWS provider behavior.
3. Добавь positive contract tests.
4. Добавь negative tests с `expect_failures`.
5. Добавь output contract tests.
6. Запусти `terraform test` из module directory.
7. Сохрани proof artifacts.

---

## Требования

- Понимать разницу между:
  - `terraform validate`
  - `terraform plan`
  - `terraform test`
  - live AWS smoke/proof checks

---

## Структура

```text
lessons/67-terraform-native-tests/
├── lesson.en.md
├── lesson.ru.md
├── README.md
├── proof-pack.en.md
├── proof-pack.ru.md
└── lab_67/
    └── terraform/
        ├── envs/
        │   ├── main.tf
        │   ├── variables.tf
        │   ├── outputs.tf
        │   ├── terraform.tfvars.example
        │   └── backend.hcl.example
        └── modules/network/
            ├── README.md
            ├── variables.tf
            ├── outputs.tf
            └── tests/
                ├── contract_valid.tftest.hcl
                ├── contract_invalid_inputs.tftest.hcl
                └── output_contract.tftest.hcl
```

Важное решение:

> Native contract tests лежат в `modules/network/tests`, а не в `envs/tests`.

Причина: урок тестирует reusable module interface. Папка `envs` больше про root wiring и backend behavior, это другая тема.

---

## A) Mental Model - `Module Contract` должен быть executable

`terraform test` запускает `.tftest.hcl` files с `run` blocks.

`run` block может выполнять:

- `command = plan`
- `command = apply`

В уроке:

- `plan` используется для быстрых input contract checks
- `expect_failures` используется для invalid input tests
- mocked `apply` используется только когда output values unknown during plan
- real AWS resources не создаются ради module contract test

Native tests это regression layer.

Они не заменяют:

- `terraform fmt`
- `terraform validate`
- `tflint`
- `checkov`
- PR plan review
- drift detection
- live smoke checks

Они ловят другое:

- случайно удалили validation
- поменяли output shape
- сломали expected failure
- module стал принимать плохие inputs
- output contract перестал быть стабильным

Они стоят между static checks и live infrastructure proof.

---

### Native Test Lifecycle

Lifecycle:

```text
setup -> run -> assert/expect failure -> teardown
```

Что происходит:

- **setup:** Terraform загружает module, variables, provider configuration, mocks и override blocks.
- **run:** каждый `run` block выполняет `plan` или `apply`.
- **assert:** проверяет, что good scenario даёт нужный result; negative tests проверяют `expect_failures`.
- **teardown:** Terraform удаляет temporary state, созданный test run.

В этом уроке teardown слабый, потому что provider mocked. С real providers teardown важнее, потому что `apply` test может создать temporary infrastructure.

Практическое правило:

- один `run` block должен доказывать одну идею
- используй file-level `variables` для shared valid defaults
- внутри каждого `run` override только ту variable, которую проверяешь
- предпочитай `plan`, если не нужны computed outputs
- используй mocked `apply` только когда value unknown during plan

Пример структуры:

```hcl
variables {
  project_name = "lab67"
  web_ami_id   = "ami-0123456789abcdef0"
}

run "bad_ami_id_fails" {
  command = plan

  variables {
    web_ami_id = "ubuntu-latest"
  }

  expect_failures = [
    var.web_ami_id
  ]
}
```

File-level variables задают healthy baseline. Run-level variable меняет одну вещь. Так failure легче понять.

---

## B) Зачем Mock Provider

Network module содержит AWS resources и data sources.

Обычный plan может требовать:

- AWS provider plugin
- AWS credentials
- region access
- data source calls

Для contract tests это слишком тяжело. Мы не доказываем, что AWS работает. Мы доказываем, что interface module ведёт себя как обещано.

Поэтому test files используют:

```hcl
mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
    }
  }
}
```

Mock provider позволяет Terraform оценить module без создания AWS resources.
Это говорит Terraform: не ходи в настоящий AWS, используй mocked provider responses.

```bash
AZs -> eu-west-1a, eu-west-1b, eu-west-1c
Account -> 123456789012
```

Некоторые AWS-shaped values всё равно должны выглядеть реалистично. Пример:

```hcl
mock_resource "aws_launch_template" {
  defaults = {
    id             = "lt-0123456789abcdef0"
    latest_version = 1
  }
}
```

Почему: AWS provider schema проверяет, что launch template IDs выглядят как `lt-*`.

Дальше есть общий блок:

```hcl
variables {
  aws_region           = "eu-west-1"
  project_name         = "lab67"
  environment          = "test"
  vpc_cidr             = "10.67.0.0/16"
  public_subnet_cidrs  = ["10.67.1.0/24", "10.67.2.0/24"]
  private_subnet_cidrs = ["10.67.11.0/24", "10.67.12.0/24"]
  web_ami_id           = "ami-0123456789abcdef0"
  ssm_proxy_ami_id     = "ami-0123456789abcdef0"
  github_owner         = "VlrRbn"
  github_repo          = "DevOps"
  tf_state_bucket_name = "vlrrbn-tfstate-123456789012-eu-west-1"
  tf_state_key         = "lab67/dev/full/terraform.tfstate"
}
```

Это baseline valid input. Потом идут run blocks.

Пример positive test:

```hcl
run "valid_contract_inputs_plan" {
  command = plan

  assert {
    condition     = output.web_asg_name == "lab67-web-asg"
    error_message = "web_asg_name must keep the stable '<project>-web-asg' output contract."
  }
}
```

Что происходит:

```bash
setup -> mocked provider
run -> terraform plan
assert -> проверка output/condition
teardown -> test cleanup
```

Пример negative test:

```hcl
run "bad_project_name_fails" {
  command = plan

  variables {
    project_name = "Bad_Name"
  }

  expect_failures = [
    var.project_name
  ]
}
```

Тут падение — это успех.

Потому что мы ожидаем, что validation на var.project_name сработает.

Формула:

```bash
failed native test = плохо
expected failure inside expect_failures = хорошо
```

Для output tests добавлены mocked resources:

```hcl
mock_resource "aws_lb" {
  defaults = {
    arn      = "arn:aws:elasticloadbalancing:eu-west-1:123456789012:loadbalancer/app/lab67-app-alb/test"
    dns_name = "internal-lab67-app-alb.example.local"
  }
}
```

Зачем? Потому что outputs вроде `alb_dns_name` и `web_tg_arn` computed after apply. Чтобы проверить output contract без настоящего ALB, мы даём Terraform fake resource values.

---

## C) Test File 1: Valid Contract Inputs

Файл:

```text
lab_67/terraform/modules/network/tests/contract_valid.tftest.hcl
```

Задача:

- valid caller input должен доходить до plan stage
- stable metadata outputs должны сохранять expected values
- real AWS resources не должны создаваться

Test:

```hcl
run "valid_contract_inputs_plan" {
  command = plan

  assert {
    condition     = output.web_asg_name == "lab67-web-asg"
    error_message = "web_asg_name must keep the stable '<project>-web-asg' output contract."
  }

  assert {
    condition     = output.demo_api_token_parameter_name == "/devops/lab67/demo/api-token"
    error_message = "The runtime SSM parameter output must expose only the stable metadata name."
  }

  assert {
    condition     = output.demo_app_secret_name == "/devops/lab67/demo/app-secret"
    error_message = "The runtime Secrets Manager output must expose only the stable metadata name."
  }
}
```

Что он проверяет:

- валидные inputs доходят до `plan`
- `web_asg_name` остаётся stable
- secret-related outputs показывают только metadata names
- plaintext secret values не появляются

Почему `command = plan`, а не `apply`?

Потому что эти outputs можно вычислить на plan stage:

```bash
web_asg_name -> deterministic name
demo_api_token_parameter_name -> variable/default
demo_app_secret_name -> variable/default
```

В plan это computed value, оно может быть unknown.

Критерии:

- valid inputs не падают на validation
- test не требует real AWS resources
- stable metadata outputs остаются predictable

---

## D) Test File 2: Invalid Inputs

Файл:

```text
lab_67/terraform/modules/network/tests/contract_invalid_inputs.tftest.hcl
```

Задача:

- bad inputs должны fail early
- failures должны быть expected и intentional
- каждый test проверяет одно contract rule

Пример:

```hcl
run "bad_project_name_fails" {
  command = plan

  variables {
    project_name = "Bad_Name"
  }

  expect_failures = [
    var.project_name
  ]
}
```

Если validation удалить из `variables.tf`, то этот test упадёт уже как failed test, потому что ожидаемого failure не будет.

Главная идея:

> Failed native test это плохо. Expected failure внутри `expect_failures` это хорошо.

В уроке есть tests для:

- `bad_project_name_fails`
- `bad_web_ami_id_fails`
- `single_private_subnet_fails`
- `too_many_private_subnets_fails`
- `duplicate_private_subnets_fail`
- `bad_private_subnet_cidr_fails`
- `bad_ssm_proxy_ami_id_fails`
- `empty_tag_value_fails`
- `reserved_tag_override_fails`
- `bad_health_check_threshold_fails`
- `bad_state_key_fails`

Критерии:

- invalid inputs fail before apply
- каждый failure указывает на variable contract
- test не зависит от live AWS state

---

## E) Test File 3: Output Contract

Файл:

```text
lab_67/terraform/modules/network/tests/output_contract.tftest.hcl
```

Некоторые outputs unknown during `plan`, потому что они приходят из computed resource attributes.

Примеры:

- ALB DNS name
- target group ARN
- security group IDs
- SSM vpc endpoint IDs

Для этого используется mocked `apply`:

```hcl
run "stable_output_contract" {
  command = apply

  assert {
    condition     = startswith(output.alb_dns_name, "internal-lab67-app-alb")
    error_message = "alb_dns_name must stay a non-empty DNS name consumed by SSM port-forward tests."
  }

  assert {
    condition     = startswith(output.web_tg_arn, "arn:aws:elasticloadbalancing:")
    error_message = "web_tg_arn must stay an ARN-shaped output consumed by health/drift checks."
  }

  assert {
    condition     = can(output.security_groups.web_sg) && can(output.security_groups.alb_sg)
    error_message = "security_groups output must keep stable web_sg and alb_sg keys."
  }

  assert {
    condition     = can(output.ssm_vpc_endpoint_ids["ssm"]) && can(output.ssm_vpc_endpoint_ids["secretsmanager"])
    error_message = "ssm_vpc_endpoint_ids must stay a map keyed by AWS service name."
  }
}
```

Что это защищает:

- `alb_dns_name` не исчез
- `web_tg_arn` остаётся ARN-shaped
- `security_groups` остаётся object с stable keys
- `ssm_vpc_endpoint_ids` остаётся map, не list

Это не создаёт AWS resources, потому что provider mocked.

Правило:

- используй `plan`, когда values known during planning
- используй mocked `apply`, когда tested output computed
- не используй real `apply` для contract-only tests

---

### Debug: `Unknown condition value`

Частая ошибка Terraform native tests:

```text
Error: Unknown condition value
```

Обычно это значит, что `assert` зависит от value, который unknown during `plan`.

Пример:

```hcl
run "stable_output_contract" {
  command = plan

  assert {
    condition = startswith(output.alb_dns_name, "internal-")
  }
}
```

`alb_dns_name` приходит из AWS после создания load balancer, поэтому during `plan` Terraform может знать только то, что потом это будет string.

Варианты исправления:

- поменять test на mocked `apply`
- assert on a value known during plan
- добавить mock или override, который делает value доступным during plan
- вынести check в live proof drill, если это реально runtime behavior

В этой lab `output_contract.tftest.hcl` использует:

```hcl
run "stable_output_contract" {
  command = apply
}
```

Здесь это безопасно, потому что `AWS provider mocked`. Terraform получает concrete output values без создания real infrastructure.

Правило:

> Если value computed by resource, `plan` может его не знать. Используй mocked `apply` или тестируй другой contract.

---

## F) Запуск Тестов

Из repo root:

```bash
cd lessons/67-terraform-native-tests/lab_67/terraform/modules/network
terraform init -backend=false
terraform test -no-color
```

Ожидаемый результат:

```text
Success! 13 passed, 0 failed.
```

Verbose mode:

```bash
terraform test -verbose -no-color
```

Запуск конкретной test directory:

```bash
terraform test -test-directory=tests -no-color
```

Если provider plugin падает из-за local cache/handshake issue, изолируй Terraform data в `/tmp`:

```bash
TF_DATA_DIR=/tmp/l67-module-test-data \
AWS_EC2_METADATA_DISABLED=true \
terraform test -no-color
```

---

### Как Читать Failed Native Test

Не смотри только на последнюю строку. Terraform test output имеет полезную структуру.

Пример:

```bash
tests/contract_invalid_inputs.tftest.hcl... in progress
  run "bad_project_name_fails"... pass
  run "bad_web_ami_id_fails"... fail
tests/contract_invalid_inputs.tftest.hcl... fail

Error: Invalid value for variable
  on variables.tf line ...
```

Читай в таком порядке:

1. **File:** какой `.tftest.hcl` упал?
2. **Run block:** какой `run "..."` упал?
3. **Expectation type:** это обычный `assert` или `expect_failures` test?
4. **Address:** Terraform указывает на `var.web_ami_id`, `output.web_tg_arn` или resource?
5. **Meaning:** module failed too early, too late, или не failed там, где должен был?

Типовые интерпретации:

| Output | Meaning |
| --- | --- |
| `run "...fails"... pass` | Хорошо. Invalid input failed as expected. |
| `run "...fails"... fail` | Плохо. Invalid input больше не падает или падает не по тому address. |
| `Unknown condition value` | Assertion использует value unknown during `plan`. |
| provider schema error | Mock value выглядит нереалистично, например launch template ID не начинается с `lt-`. |
| `0 passed, 0 failed` plus provider error | Test framework даже не смог стартовать provider. Проверяй plugin/cache/environment. |

При debug упрощай test:

- запускай один test file, если нужно
- оставляй один intentional variable override
- используй `terraform test -verbose -no-color`
- проверь, known ли failing value during `plan`
- проверь, похож ли mock value на реальное AWS value

---

## G) Что Не Нужно Тестировать Здесь

Не используй native tests для всего подряд.

Хорошие цели для native tests:

- variable validation
- preconditions
- output names and shapes
- required tag behavior
- module-level assumptions
- known breaking-change guards

Плохие цели для native tests:

- real ALB routing
- real ASG instance refresh behavior
- real IAM permission boundaries
- real SSM port forwarding
- real Secrets Manager decryption
- CloudWatch alarm state transitions

Это относится к live proof drills или будущим integration tests.

---

## H) CI Pattern

Лёгкий native-test job должен запускаться до дорогого plan/apply workflow.

```bash
fmt -> terraform test -> validate/plan -> apply/smoke
```

В этом repo активный workflow находится в `.github/workflows/lesson67-terraform-native-tests.yml`. Файл `ci/terraform-native-tests.yml` оставлен как copyable template для урока.

Пример:

```yaml
name: lesson67-terraform-native-tests

on:
  pull_request:
    paths:
      - 'lessons/67-terraform-native-tests/**'
      - '.github/workflows/lesson67-terraform-native-tests.yml'
```

Почему без AWS credentials?

Потому что tests используют `mock_provider`. Они защищают contract и не трогают AWS.

---

## I) Drill Set

### Drill 1 - Сломай project name validation

Измени valid test variable:

```hcl
project_name = "Bad_Name"
```

Ожидаемо:

- positive test падает
- negative test продолжает проходить, потому что expects that failure

Верни valid value.

### Drill 2 - Удали AMI validation

Временно удали `web_ami_id` validation block.

Ожидаемо:

- `bad_web_ami_id_fails` падает, потому что Terraform больше не rejects `ubuntu-latest`

Верни validation.

### Drill 3 - Разреши one private subnet

Временно измени:

```hcl
length(var.private_subnet_cidrs) >= 2
```

на:

```hcl
length(var.private_subnet_cidrs) >= 1
```

Ожидаемо:

- `single_private_subnet_fails` падает
- test защищает topology contract из урока 66

Верни validation.

### Drill 4 - Удали reserved tag protection

Временно удали reserved-key validation у `common_tags`.

Ожидаемо:

- `reserved_tag_override_fails` падает

Верни validation.

### Drill 5 - Сломай output name

Переименуй output `web_asg_name` в `asg_name`.

Ожидаемо:

- output contract test падает
- это показывает, почему output rename это breaking change

Верни output.

---

## J) Proof Pack

Сохрани:

```text
evidence/
  terraform-version.txt
  terraform-init.txt
  terraform-test.txt
  terraform-test-verbose.txt
  drill-bad-project-name.txt
  drill-remove-ami-validation.txt
  drill-one-private-subnet.txt
  drill-reserved-tag.txt
  drill-output-rename.txt
  decision.txt
```

В `decision.txt` добавь GitHub Actions run URL для `.github/workflows/lesson67-terraform-native-tests.yml`.

Минимальный proof:

```bash
cd lessons/67-terraform-native-tests/lab_67/terraform/modules/network

export EVIDENCE_DIR="../../../../evidence/l67-$(date +%Y%m%d_%H%M%S)"
mkdir -p "$EVIDENCE_DIR"

terraform version > "$EVIDENCE_DIR/terraform-version.txt" 2>&1
terraform init -backend=false -input=false -no-color > "$EVIDENCE_DIR/terraform-init.txt" 2>&1
terraform test -no-color > "$EVIDENCE_DIR/terraform-test.txt" 2>&1
terraform test -verbose -no-color > "$EVIDENCE_DIR/terraform-test-verbose.txt" 2>&1
```

Не коммить `.terraform`, `tfstate`, `terraform.tfvars`, backend files, real env data.

---

## Частые ошибки

- класть module contract tests в `envs/tests` и случайно тестировать backend wiring
- использовать real AWS `apply` для contract-only tests
- проверять слишком много вещей в одном `run` block
- писать `expect_failures`, который указывает не на ту variable
- assert computed outputs during `plan`
- забывать realistic AWS-shaped mock values, например `lt-*` launch template IDs
- считать native tests заменой live smoke checks

---

## Финальные критерии

Урок 67 завершён, если:

- [ ] native tests лежат в `modules/network/tests`
- [ ] provider mocked для contract tests
- [ ] минимум один valid-input test проходит
- [ ] минимум одиннадцать invalid-input tests проходят через `expect_failures`
- [ ] output contract test проходит
- [ ] `terraform test -no-color` возвращает success
- [ ] CI workflow для native tests проходит
- [ ] proof pack содержит test output и drill evidence
- [ ] lesson объясняет, что относится к native tests, а что нет

---

## Итоги Урока

Завершаем теорию.

Главная модель урока 67:

> `terraform test` превращает module contract из документации в executable safety net.

Что входит в native test:

- `.tftest.hcl` files внутри `modules/network/tests`
- `mock_provider "aws"` вместо real AWS calls
- `run` blocks для plan/apply scenarios
- `expect_failures` для expected validation failures
- `assert` blocks для output/interface guarantees

Что важно помнить:

- native tests должны жить рядом с reusable module, а не в `envs`, если проверяется module contract
- mocked provider защищает contract без AWS credentials и без real resources
- expected failure внутри `expect_failures` — это успешный test
- failed native test без `expect_failures` — это regression или ошибка test design
- computed outputs часто нельзя надёжно assert during `plan`; для output contract используй mocked `apply`
- native tests не заменяют live smoke checks, SSM proof, real IAM checks или drift detection
- CI native tests должны запускаться до дорогих AWS-backed plan/apply workflows

Практический итог:

- **Что изучил:** `terraform test` защищает module contracts от regression.
- **Что практиковал:** `.tftest.hcl`, `mock_provider`, `expect_failures`, output assertions, mocked apply.
- **Операционный фокус:** ловить broken module interfaces до PR plan/apply.
- **Почему это важно:** module contracts надёжны только когда они executable and tested.
