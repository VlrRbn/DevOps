# Урок 66. Module Contracts & Interface Guarantees

**Дата:** 2026-05-30

**Фокус:** превратить Terraform modules в стабильные интерфейсы с validated inputs, predictable outputs, invariants и breaking-change discipline.

**Подход:** module это не папка. Module это contract.

---

## Зачем этот урок

К этому моменту уже практиковал:

- remote state and locking
- safe refactors
- Terraform quality gates
- PR plan pipelines
- drift detection
- secret-safe inputs

Следующий риск другой:

> Module принимает плохой input, отдаёт неожиданный output или silently меняет поведение.

Так reusable infrastructure становится опасной.

Урок 66 делает interface module явным:

- что caller может передавать
- какие values отклоняются рано
- какие outputs гарантированы
- какие assumptions всегда должны быть true
- что считается breaking change

Terraform modules reusable только тогда, когда public interface стабилен и enforced. Одной документации недостаточно; важные правила должны быть executable.

---

## Что должен уметь после урока

- определить понятный module contract для `modules/network`
- добавить validation для dangerous или inconsistent inputs
- добавить preconditions там, где variable validation недостаточно
- стандартизировать outputs как стабильный interface
- enforce required tags, но оставить возможность caller-provided tags
- документировать breaking vs non-breaking module changes
- пройти drills, где invalid input падает до `apply` и до изменения инфраструктуры
- собрать proof artifacts для contract behavior

---

## Быстрый маршрут

1. Сделать inventory всех module inputs.
2. Классифицировать inputs:
   - required
   - optional
   - dangerous
   - derived
3. Добавить validation для caller-facing mistakes.
4. Добавить preconditions для design invariants.
5. Стандартизировать output names and shapes.
6. Документировать output consumers.
7. Добавить breaking-change policy.
8. Запустить bad-input drills.
9. Сохранить proof pack.

---

## Требования

- урок 61: safe refactor mindset
- урок 62: Terraform quality gates
- урок 63: PR plan pipeline
- урок 64: drift detection
- урок 65: safe inputs and secrets
- рабочая lab в `lab_66/terraform`

---

## Структура

```text
lessons/66-module-contracts-and-interface-guarantees/
├── lesson.en.md
├── lesson.ru.md
├── README.md
├── proof-pack.en.md
├── proof-pack.ru.md
└── lab_66/
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
            ├── locals.tf
            ├── asg.tf
            └── outputs.tf
```

---

## A) Contract Model

Module contract состоит из пяти частей.

| Contract part | Meaning |
| --- | --- |
| Inputs | Что caller может передать |
| Validation | Какие values rejected early |
| Resources | Что module owns and manages |
| Outputs | На что caller может depend |
| Compatibility rules | Что считается breaking change |

**Breaking changes:**
* переименовать или удалить существующий `output`
* изменить тип или форму `output` (`type/shape`)
* изменить значение по умолчанию (`default`), если это меняет поведение инфраструктуры
* сделать необязательный `input` обязательным
* удалить поддержку ранее допустимого режима (`mode`)

**Non-breaking changes:**
* добавить новый `output`
* добавить необязательный `input` с безопасным значением по умолчанию (`safe default`)
* добавить `validation` для значений, которые никогда не поддерживались безопасно / корректно (`never safely supported`)

Важное правило:

> Если Terraform технически принимает value, это ещё не значит, что module должен его принимать.

Пример:

- Terraform технически может принять один private subnet.
- Lab ASG/internal ALB design ожидает минимум два private subnets.
- Значит module contract должен reject single private subnet.

Self-check:

Ответь своими словами после чтения примера выше. Это не проверка на угадывание; цель — убедиться, что ты можешь применить contract model к реальным inputs.

1. Почему для этой lab один `private_subnet_cidr` должен отклоняться, даже если Terraform технически принимает list из одного элемента?
2. Почему `web_ami_id = "ubuntu-latest"` это плохой input contract?
3. Что из этого breaking change: добавить новый output, переименовать existing output, добавить optional variable с default, поменять default `web_desired_capacity` с `2` на `1`?

---

## B) Input Inventory

Если не можешь объяснить input, interface module уже неясный.

Полный contract для этой lab находится в `lab_66/terraform/modules/network/README.md`. Таблица ниже — high-risk excerpt, который нужно уметь объяснить по памяти.

| Variable | Caller must set? | Default | Risk | Contract |
|---|---:|---|---|---|
| `project_name` | no | `lab66` | naming drift | lowercase kebab-style |
| `environment` | no | `dev` | tag drift | lowercase env name |
| `vpc_cidr` | no | `10.0.0.0/16` | invalid network | valid IPv4 CIDR |
| `public_subnet_cidrs` | no | 2 CIDRs | ALB/AZ/index failure | 2-6 unique valid CIDRs |
| `private_subnet_cidrs` | no | 2 CIDRs | ASG/AZ/index failure | 2-6 unique valid CIDRs |
| `web_ami_id` | yes | none | wrong artifact | AMI-shaped ID |
| `ssm_proxy_ami_id` | yes | none | wrong debug host | AMI-shaped ID |
| `web_desired_capacity` | no | `2` | invalid ASG capacity | min <= desired <= max |
| `common_tags` | no | `{}` | governance drift | non-empty tags, no reserved keys |

Критерии:

- [ ] каждая variable имеет purpose
- [ ] каждая dangerous variable имеет validation или documented reason why not
- [ ] каждое validation error объясняет caller, как исправить input

Как рассуждать об input:

- `required` подходит для values, которые зависят от конкретного окружения или build artifact и не должны угадываться module.
- `optional` подходит для безопасного default, когда caller может ничего не передавать и получить ожидаемое поведение.
- `dangerous` не значит “запрещено”. Это значит, что плохое value может сломать naming, runtime, security, cost allocation или downstream automation.
- `derived` лучше вычислять внутри module, если value создаётся этим же module. Иначе caller сможет передать inconsistent value, которое не совпадает с реальными resources.

Пример:

- `web_ami_id` required, потому что module не знает, какой именно baked AMI ты собрал для web fleet.
- `common_tags` optional, потому что module может работать без caller tags, но dangerous, потому что tags влияют на ownership, cost reporting и governance.
- `private_subnet_ids` output, потому что эти subnets создаются внутри module. Caller не должен вручную передавать IDs resources, которыми module сам владеет.

Self-check:

Ответить своими словами после чтения модели выше. Если ответ совпадает с примером по смыслу то этого достаточно.

1. Почему `web_ami_id` и `ssm_proxy_ami_id` required, а не default?
2. Почему `common_tags` optional, но всё равно dangerous?
3. Почему `private_subnet_ids` лучше output, а не input для этого module?

---

## C) Variable Validation

Использовать variable validation для ошибок, которые caller может исправить до `apply`.

Важный нюанс: в real root module с remote backend и data sources `terraform plan` может сначала обратиться к backend или прочитать data sources, а потом показать validation error. Поэтому точное обещание такое: bad input должен падать до изменения инфраструктуры. Если нужна проверка вообще без AWS credentials, использовать backend-less CI contract gate.

Также: Terraform может напечатать часть proposed plan и строку вроде `Plan: 22 to add`, а потом завершиться validation error. Это не successful plan. Для drill важен final result: команда завершилась non-zero exit code, показала понятную validation error и не выполняла `apply`.

### Project name

```hcl
variable "project_name" {
  type        = string
  description = "Project prefix for resource names"
  default     = "lab66"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,30}$", var.project_name))
    error_message = "project_name must be lowercase kebab-style, start with a letter, and be 3-31 characters."
  }
}
```

Что защищаем:

- resource names
- tags
- predictable naming
- automation, которая может ожидать нормальный prefix

Почему это contract, а не просто стиль:

- имя проекта попадёт в имена ресурсов
- inconsistent naming ломает поиск, cost reports, scripts, dashboards
- лучше отклонить сразу, чем потом иметь ресурсы с разными naming conventions

### AMI ID shape

```hcl
variable "web_ami_id" {
  type        = string
  description = "Baked web AMI used by the single rolling ASG fleet"

  validation {
    condition     = can(regex("^ami-[0-9a-f]{8,17}$", var.web_ami_id))
    error_message = "web_ami_id must look like an AWS AMI ID, for example ami-0123456789abcdef0."
  }
}
```

Что защищаем:

- caller должен передать AWS AMI ID
- не label
- не filename
- не Packer template name
- не ubuntu-latest

### Subnet contract

```hcl
variable "private_subnet_cidrs" {
  type        = list(string)
  description = "Private subnet CIDR blocks (minimum 2 for ASG spread)"

  validation {
    condition     = length(var.private_subnet_cidrs) >= 2
    error_message = "At least two private subnet CIDRs are required for the web instances."
  }

  validation {
    condition     = length(var.private_subnet_cidrs) <= 6
    error_message = "private_subnet_cidrs must contain at most six CIDRs because this module maps subnet keys a-f."
  }

  validation {
    condition     = length(distinct(var.private_subnet_cidrs)) == length(var.private_subnet_cidrs)
    error_message = "private_subnet_cidrs must not contain duplicate CIDRs."
  }

  validation {
    condition     = alltrue([for cidr in var.private_subnet_cidrs : can(cidrhost(cidr, 0))])
    error_message = "Every private_subnet_cidrs entry must be a valid IPv4 CIDR block."
  }
}
```

Тут 4 разных rules:

- минимум 2, потому что design требует spread
- максимум 6, потому что module maps subnet keys a-f
- без duplicates, потому что duplicate subnet CIDRs бессмысленны/опасны
- каждый элемент должен быть валидным CIDR

Validation хорошо проверяет:

- string format
- list length
- numeric ranges
- allowed values
- basic relationships между variables
- empty/null values
- reserved keys

Validation плохо подходит для:

- существует ли AMI реально
- хватает ли quota в AWS
- есть ли AZ в регионе
- доступен ли subnet после apply
- проходит ли health check runtime

Для этого нужны provider checks, preconditions, postconditions, tests или manual proof.

### Capacity contract

```hcl
variable "web_desired_capacity" {
  type        = number
  description = "ASG desired capacity for the rolling web fleet"
  default     = 2

  validation {
    condition     = var.web_desired_capacity >= var.web_min_size && var.web_desired_capacity <= var.web_max_size
    error_message = "web_desired_capacity must be between web_min_size and web_max_size."
  }
}
```

---

## D) Preconditions and Interface Invariants

Использовать preconditions, когда правило зависит от derived values или resource behavior.

Пример из `asg.tf`:

```hcl
resource "aws_autoscaling_group" "web" {
  vpc_zone_identifier = local.private_subnet_ids

  lifecycle {
    create_before_destroy = true

    precondition {
      condition     = length(local.private_subnet_ids) >= 2
      error_message = "ASG requires at least two private subnets for this lab design."
    }

    precondition {
      condition     = var.web_min_size <= var.web_desired_capacity && var.web_desired_capacity <= var.web_max_size
      error_message = "ASG capacity contract requires web_min_size <= web_desired_capacity <= web_max_size."
    }
  }
}
```

Output preconditions защищают values, которые использует automation:

```hcl
output "alb_dns_name" {
  description = "DNS name of the internal ALB (reach via SSM port forwarding)"
  value       = aws_lb.app.dns_name

  precondition {
    condition     = aws_lb.app.dns_name != ""
    error_message = "alb_dns_name output contract requires a non-empty ALB DNS name."
  }
}
```

| Тип проверки                 | Что защищает                      | Кто виноват, если проверка упала        | Для чего        |
| ---------------------------- | --------------------------------- | ----------------------------------------| ----------------|
| Validation                   | систему от плохого внешнего input | caller / пользователь / внешний клиент  | Хороша для format/range/list length |
| Precondition                 | предположения дизайна             | код, который неправильно вызвал функцию | Хороша для derived values и relationships |
| Postcondition / output check | гарантии интерфейса               | сама функция / её реализация            | Хороша для проверки результата, contract guarantees, regression bugs |

Правило:

- validations защищают caller input
- preconditions защищают design assumptions
- output preconditions защищают interface guarantees

Не добавлять проверки везде подряд. Добавлять их там, где неправильное value создаст плохой plan, broken runtime или unsafe interface.

---

## E) Output Contract

Плохой output design:

```hcl
output "stuff" {
  value = {
    alb = aws_lb.app
    asg = aws_autoscaling_group.web
  }
}
```

Почему плохо:

- caller начинает зависеть от internals module
- создаёт нестабильную output shape
- downstream automation начинает зависеть от internals
- может раскрыть sensitive-looking metadata
- непонятно, какие поля реально supported

Лучше:

```hcl
output "alb_dns_name" {
  value       = aws_lb.app.dns_name
  description = "DNS name of the internal ALB (reach via SSM port forwarding)"
}

output "web_asg_name" {
  value       = aws_autoscaling_group.web.name
  description = "Auto Scaling Group name for the rolling web fleet"
}

output "web_tg_arn" {
  value       = aws_lb_target_group.web.arn
  description = "ARN of the web target group"
}
```

Output rules:

- output names стабильные
- name говорит, что это такое
- no whole-resource outputs
- no plaintext secret outputs
- sensitive outputs marked `sensitive = true`
- output type/shape changes считаются breaking changes

Output должен быть consumer-oriented, а не resource-oriented.

---

## F) Tagging Contract

Tags это часть module interface, потому что они влияют на:

- cost allocation
- ownership
- automation filters
- compliance/governance
- cleanup scripts
- dashboards/alerts

Caller-provided tags:

```hcl
variable "common_tags" {
  type        = map(string)
  description = "Optional caller-provided tags. Required governance tags are merged after this map and cannot be overridden."
  default     = {}

  validation {
    condition     = alltrue([for k, v in var.common_tags : length(trimspace(k)) > 0 && length(trimspace(v)) > 0])
    error_message = "common_tags must not contain empty keys or empty values."
  }

  validation {
    condition = alltrue([
      for k in keys(var.common_tags) :
      !contains(["Project", "Environment", "ManagedBy", "Lesson"], k)
    ])
    error_message = "common_tags must not set reserved keys: Project, Environment, ManagedBy, Lesson."
  }
}
```

Required tags:

```hcl
locals {
  required_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Lesson      = "66"
  }

  tags = merge(var.common_tags, local.required_tags)
}
```

В Terraform merge при одинаковых ключах берёт значение из последнего map.
То есть если caller передаст:

```hcl
common_tags = {
  Project = "manual"
}
```
local.required_tags.Project всё равно победит.

Но validation всё равно запрещает caller передавать Project.

- caller сразу видит, что reserved keys запрещены
- нет silent override
- ошибка объясняет governance rule
- CI/drills могут проверить поведение
- меньше путаницы: caller не думает, что его Project = "manual" применился

Caller может добавить metadata, но не может override governance tags.

---

## G) Breaking Change Policy

### Breaking Changes

Breaking changes требуют заметку в уроке или PR:

- переименование или удаление output
- изменение типа или формы output
- изменение типа required input
- изменение default, если оно меняет поведение инфраструктуры
- удаление поддержки ранее допустимого режима
- изменение resource addresses без `moved` block
- превращение optional input в required input

### Non-Breaking Changes

- добавление optional input с safe default
- добавление нового output
- уточнение документации без изменения поведения
- добавление validation, которая отклоняет values, которые module никогда безопасно не поддерживал
- добавление internal resources, если они не меняют public outputs или default behavior

Разберём нюанс.

Добавить validation может быть breaking или non-breaking.

Non-breaking:

```hcl
web_ami_id = "ubuntu-latest"
```

Если module никогда реально не мог безопасно работать с `ubuntu-latest`, то validation просто формализует уже существующий contract.

Breaking:

```hcl
project_name = "myproject"
```

Раньше это работало, а новая validation требует обязательно `my-project-prod`, хотя старый формат был нормальным и реально supported. Тогда caller upgrade ломается.

Ещё пример:

Изменить default:

```hcl
web_desired_capacity = 2
```

на:

```hcl
web_desired_capacity = 1
```

Это breaking, потому что caller ничего не поменял, но infrastructure behavior изменился.

Правило:

> Если caller может обновить module и получить неожиданный plan или сломанную automation, это breaking change.

---

## H) Упражнения

Запускать упражнения из `lab_66/terraform/envs`. Вывод сохранять в ignored `evidence/`.

### Упражнение 1 — неправильный project name отклоняется

Задать:

```hcl
project_name = "Bad_Name"
```

Запусти:

```bash
terraform plan -no-color
```

Ожидаемо:

- plan падает до изменения ресурсов
- ошибка объясняет naming contract

Критерии:

- [ ] invalid input отклоняется до `apply` и до изменения инфраструктуры
- [ ] error message объясняет, как исправить input

---

### Упражнение 2 — один private subnet отклоняется

Задать:

```hcl
private_subnet_cidrs = ["10.30.11.0/24"]
```

Ожидаемо:

- variable validation или ASG precondition падает
- без изменения инфраструктуры

Критерии:

- [ ] lab не может случайно запуститься в single-AZ режиме
- [ ] ошибка происходит до apply

---

### Упражнение 3 — слишком много private subnets отклоняется

Задать:

```hcl
private_subnet_cidrs = [
  "10.30.11.0/24",
  "10.30.12.0/24",
  "10.30.13.0/24",
  "10.30.14.0/24",
  "10.30.15.0/24",
  "10.30.16.0/24",
  "10.30.17.0/24",
]
```

Ожидаемо:

- validation падает до того, как subnet mapping даст непонятную index error
- ошибка объясняет поддерживаемый контракт 2-6 subnets

Критерии:

- [ ] oversized subnet list отклоняется понятным contract-friendly сообщением

---

### Упражнение 4 — неправильный AMI ID отклоняется

Задать:

```hcl
web_ami_id = "ubuntu-latest"
```

Ожидаемо:

- validation падает до `apply` и до изменения инфраструктуры

Критерии:

- [ ] неправильная форма artifact отклоняется рано

---

### Упражнение 5 — пустой tag отклоняется

Задать:

```hcl
common_tags = {
  Owner = ""
}
```

Ожидаемо:

- validation падает

Критерии:

- [ ] tag contract enforced

---

### Упражнение 6 — reserved tag отклоняется

Задать:

```hcl
common_tags = {
  Project = "override"
}
```

Ожидаемо:

- validation падает
- caller не может перезаписать governance tags

Критерии:

- [ ] required tag contract protected

---

Все 6 negative drills прошли:

- project_name = "Bad_Name" отклонён
- один private subnet отклонён
- семь private subnets отклонены
- web_ami_id = "ubuntu-latest" отклонён
- пустой tag value отклонён
- reserved tag override отклонён

---

### Упражнение 7 — ревью output contract

Создать `output-contract.md`:

| Output | Consumer | Stability |
|------------|------------|------------|
| alb_dns_name | SSM proxy curl tests | stable |
| web_asg_name | release workflows | stable |
| web_tg_arn | health/drift workflows | stable |
| ssm_vpc_endpoint_ids | private runtime proof | stable map keyed by service |

Критерии:

- [ ] у каждого output есть consumer
- [ ] ни один output не раскрывает whole resource
- [ ] secret outputs отсутствуют

---

## I) Proof Pack

Capture:

```text
evidence/
  input-inventory.md
  fmt.txt
  validate.txt
  baseline-plan.txt
  bad-project-name-plan.txt
  one-subnet-plan.txt
  too-many-subnets-plan.txt
  bad-ami-id-plan.txt
  empty-tag-plan.txt
  reserved-tag-plan.txt
  output-contract.md
  baseline-plan-after-fixes.txt
```

`baseline-plan` не означает `0 to change`. Если lab ещё не применена, baseline может показывать creates. В этом уроке baseline означает: plan читаемый, временные bad-input overrides удалены, plaintext secrets не выводятся.

Для каждого упавшего drill сохранить:

- команду
- ошибку
- почему он упал
- почему это хорошее падение

Не коммитить настоящие `terraform.tfvars`, `backend.hcl`, `.terraform/`, `tfstate` или proof-файлы с чувствительными деталями окружения.

---

## J) CI Contract Gate

Workflow `.github/workflows/lesson66-contract-tests.yml` запускает статическую contract-проверку для урока.

Он проверяет:

- форматирование Terraform
- `terraform init` без backend
- `terraform validate`
- негативные input drills, которые должны упасть с ожидаемыми validation messages

CI специально не использует AWS credentials. Его задача — доказать, что module отклоняет плохой input до доступа к remote state или AWS API. Реальное AWS-поведение всё ещё доказывается вручную через proof pack.

---

## Частые ошибки

- проверять только тип, но не смысл значения
- выводить whole resource вместо стабильных output-полей
- позволять callers перезаписывать обязательные tags
- менять outputs без breaking-change note
- добавлять validations, которые ломают реально поддерживаемые сценарии
- полагаться только на README вместо executable validation
- писать validation messages, которые говорят что сломалось, но не объясняют как исправить

---

## Security Checklist

- outputs не раскрывают plaintext secrets
- sensitive outputs помечены `sensitive = true`
- module не принимает secret values без необходимости
- invalid network shapes падают до `apply`
- AMI inputs отклоняют arbitrary text
- callers не могут перезаписать required tags
- output shapes стабильны и documented
- breaking changes documented

---

## Финальные критерии

Урок 66 завершён, если:

- [ ] все важные variables имеют documented contract
- [ ] dangerous inputs имеют validation или preconditions
- [ ] outputs stable и documented
- [ ] required tags enforced
- [ ] минимум 6 bad-input drills падают корректно
- [ ] baseline plan возвращается после исправления inputs
- [ ] module README содержит output contract и breaking-change policy
- [ ] CI workflow для contract checks проходит

---

## Итоги Урока

Завершаем теорию.

Главная модель урока 66:

> Terraform module это публичный contract, а не просто папка с `.tf` файлами.

Что входит в contract:

- `inputs`: что caller может передать
- `validations`: какие значения module отклоняет заранее
- `resources`: чем module владеет внутри
- `outputs`: на что caller и automation могут безопасно опираться
- `compatibility rules`: что считается breaking change

Что важно помнить:

- плохой input должен падать до `apply` и до изменения инфраструктуры
- validation проверяет caller input
- precondition проверяет design invariant рядом с resource/output
- output должен быть consumer-oriented, а не whole-resource dump
- tags являются частью interface, потому что их используют cost, ownership, automation и governance
- default может быть breaking change, если он меняет infrastructure behavior
- CI contract gate проверяет module contract без AWS credentials
- manual proof pack всё ещё нужен для real AWS-backed behavior

Практический итог:

- **Что изучил:** modules are contracts, not folders.
- **Что практиковал:** variable validation, preconditions, output contracts, tagging invariants, breaking-change policy.
- **Операционный фокус:** fail early, когда caller передаёт dangerous inputs.
- **Почему это важно:** module reuse безопасен только когда interface explicit, documented и enforced.
