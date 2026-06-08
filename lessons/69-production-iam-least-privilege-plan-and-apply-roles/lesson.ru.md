# Урок 69. Production IAM: Least-Privilege Plan and Apply Roles

**Дата:** 2026-06-03

**Фокус:** заменить слишком широкие права автоматизации Terraform на ограниченные роли `plan` и `apply`.

**Подход:** `plan` наблюдает. `apply` меняет только нужный стек. Break-glass доступ живёт отдельно.

Официальные ссылки:

- AWS IAM least privilege and permissions refinement: https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies.html
- AWS IAM Access Analyzer policy generation: https://docs.aws.amazon.com/IAM/latest/UserGuide/access-analyzer-policy-generation.html
- GitHub Actions OIDC with AWS: https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services
- Terraform S3 backend permissions and native lockfile: https://developer.hashicorp.com/terraform/language/backend/s3

---

## Зачем этот урок

В уроке 68 сделали контролируемый apply pipeline:

```text
plan-dev
-> артефакт сохранённого плана
-> подтверждение
-> apply-dev
-> проверка после apply
```

Это исправило процесс доставки изменений, но в 68-м уроке оставалось одно учебное упрощение:

```text
apply role -> AdministratorAccess
```

Для изучения механики pipeline это нормально, но для production-роли, которая применяет изменения, так делать нельзя.

Урок 69 убирает это упрощение. Цель — получить защитимую production-модель:

```text
plan role:
  читает state в backend
  ставит и снимает lock state
  читает AWS-ресурсы для refresh
  не меняет инфраструктуру

apply role:
  читает и пишет только конкретный state key и lockfile
  меняет только те AWS-сервисы, которые нужны этому стеку
  передаёт в EC2 только разрешённые runtime-роли
  доступна только после подтверждения в GitHub Environment

break-glass role:
  отдельная от обычного pipeline
  подтверждается вручную, логируется, ограничена по времени и разбирается после инцидента
  аварийное восстановление
```

Было:

```text
plan role  -> ReadOnlyAccess + backend access
apply role -> AdministratorAccess
```

Стало:

```text
plan role  -> backend lockfile + ограниченная read/refresh policy
apply role -> backend lockfile + ограниченная policy на изменения в lab + ограниченный `iam:PassRole`
```

---

## Что должен уметь после урока

- объяснить, почему `plan` и `apply` требуют разных IAM-прав
- заменить `AdministratorAccess` на ограниченные customer-managed или inline policies
- ограничить S3 backend permissions одним объектом state и одним объектом `.tflock`
- понимать, почему многие AWS `Describe*` APIs всё ещё требуют `Resource = "*"`
- ограничить `iam:PassRole` разрешёнными runtime-ролями и сервисом `ec2.amazonaws.com`
- усилить GitHub OIDC trust через branch, PR и environment subjects
- понимать риск self-management, когда Terraform управляет собственными CI-ролями
- использовать Access Analyzer и last accessed data как инструменты уточнения, а не как генератор, которому слепо доверяют
- доказать, что plan role не может выполнять apply, а apply role больше не имеет admin-доступа

---

## Быстрый маршрут

1. Сделать инвентаризацию ресурсов, которыми Terraform управляет в `lab_69`.
2. Разделить права на backend, read/refresh, изменения инфраструктуры, IAM и PassRole.
3. Убрать `ReadOnlyAccess` с plan role и использовать ограниченную read policy.
4. Убрать `AdministratorAccess` с apply role.
5. Прикрепить ограниченную apply policy для lab stack.
6. Оставить apply role trust привязанным к `repo:<owner>/<repo>:environment:terraform-dev`.
7. Запустить native tests и `terraform validate`.
8. Выполнить безопасное plan/apply упражнение.
9. Выполнить негативное упражнение через plan role или неправильный OIDC subject.
10. Собрать доказательные артефакты.

---

## Требования

- Урок 60: remote state and S3 native lockfile.
- Урок 63: PR plan pipeline.
- Урок 68: controlled apply pipeline.
- Существующие GitHub OIDC provider и роли из lab.
- Рабочий Terraform backend и GitHub Environment `terraform-dev`.
- Умение читать IAM JSON.

---

## Структура

```text
lessons/69-production-iam-least-privilege-plan-and-apply-roles/
├── lesson.en.md
├── lesson.ru.md
├── README.md
├── proof-pack.en.md
├── proof-pack.ru.md
└── lab_69/
    ├── packer/
    └── terraform/
        ├── backend-bootstrap/
        ├── envs/
        └── modules/network/
```

Workflow template:

```text
lessons/69-production-iam-least-privilege-plan-and-apply-roles/ci/lesson69-terraform-apply-dev.yml
```

Урок 69 сохраняет controlled apply model из урока 68, но template уже retargeted на `lab_69`, `lab69/dev/full/terraform.tfstate` и scoped roles из lab69.

Не подставляй lab69 role ARNs в workflow урока 68 без изменения paths, backend key, project name и secret/parameter names.

---

## A) Permission Model

Terraform automation нужны пять групп прав.

| Группа | Plan role | Apply role | Заметки |
| --- | --- | --- | --- |
| Backend state | да | да | объект state и `.tflock` |
| Read/refresh | да | да | `Describe*`, `Get*`, `List*` |
| Изменение инфраструктуры | нет | да, но ограниченно | создать/обновить/удалить управляемые ресурсы |
| Управление IAM | нет | ограниченно | только lab roles/policies |
| `iam:PassRole` | нет | ограниченно | только разрешённые runtime-роли для EC2 |

Главное правило:

```text
Plan role только читает.
Apply role меняет инфраструктуру.
Break-glass роль отдельная.
```

---

## B) Backend State Permissions

С S3 backend и `use_lockfile = true` Terraform нужен доступ к двум объектам:

```text
s3://<bucket>/<state-key>
s3://<bucket>/<state-key>.tflock
```

Для этой лабы:

```text
lab69/dev/full/terraform.tfstate
lab69/dev/full/terraform.tfstate.tflock
```

Права к state нужны и plan role, и apply role, потому что обе jobs запускают `terraform init`, делают refresh state и ставят/снимают lock.

Минимальная форма:

```json
{
  "Sid": "ReadWriteStateObjects",
  "Effect": "Allow",
  "Action": [
    "s3:GetObject",
    "s3:PutObject",
    "s3:DeleteObject"
  ],
  "Resource": [
    "arn:aws:s3:::STATE_BUCKET/lab69/dev/full/terraform.tfstate",
    "arn:aws:s3:::STATE_BUCKET/lab69/dev/full/terraform.tfstate.tflock"
  ]
}
```

Почему plan role нужен `PutObject` и `DeleteObject`?

Потому что lockfile создаётся и удаляется во время Terraform-операций. Plan role read-only для инфраструктуры, но не read-only для backend locking.

---

## C) Plan Role

Plan role должна уметь:

- инициализировать backend
- ставить и снимать lock
- читать state
- читать AWS-ресурсы для refresh
- создавать plan

Она не должна создавать, обновлять или удалять инфраструктуру, передавать роли или менять policies.

В lab теперь используется специализированная plan policy вместо AWS managed `ReadOnlyAccess`.

Read actions для plan role включают AWS-сервисы, которые Terraform читает во время refresh:

```text
ec2:Describe*
elasticloadbalancing:Describe*
autoscaling:Describe*
cloudwatch:Describe*/Get*/List*
iam:Get*/List*
ssm:GetParameter
secretsmanager:DescribeSecret
```

Часть read APIs не поддерживает resource-level scoping. Для таких actions `Resource = "*"` — нормально. Least privilege это не только resource ARNs; это ещё узкие actions, trust policy, state keys и назначение роли.

Критерии:

- [ ] plan role может `terraform plan`
- [ ] plan role не может `terraform apply`
- [ ] plan role не может вызвать API изменения инфраструктуры вроде `ec2:CreateVpc`

---

## D) Apply Role

Apply role нужны права на изменения, но только для стека, которым она управляет.

В этой lab apply-права разделены по AWS-сервисам:

- backend state и lockfile
- read/refresh APIs
- EC2, VPC, subnets, routes, security groups, VPC endpoints, instances, launch templates
- ELBv2: ALB, target group, listener
- Auto Scaling group, policy, instance refresh
- CloudWatch alarms
- lab IAM roles, instance profiles, OIDC provider и inline policies
- ограниченный `iam:PassRole`
- ограниченный `iam:CreateServiceLinkedRole` для AWS service-linked roles, когда они нужны

Это заметно меньше, чем `AdministratorAccess`, потому что нет доступа ко всем сервисам AWS.

Почему кое-где всё ещё есть `Resource = "*"`?

Потому что часть AWS API для изменений плохо или частично поддерживает `resource-level scoping`.

Например, многие EC2 `create/delete` операции удобнее и реалистичнее контролировать через:

- узкий список actions
- узкий OIDC trust
- узкий backend key
- соглашение об именовании проекта: `lab69-*`
- `tags`
- `conditions`, где это возможно
- review policy
- `destroy guard` и policy gates

Production-правило:

```text
Если `Resource` должен быть `*`, сужай список actions и trust policy.
Если `Action` должен быть широким, сужай resources и conditions.
Если и `Action`, и `Resource` вынужденно широкие, документируй причину и добавляй компенсирующий контроль.
```

---

## E) IAM Self-Management Caveat

В lab apply role может управлять IAM-ресурсами по шаблону:

- `arn:aws:iam::<account-id>:role/lab69-*`
- `arn:aws:iam::<account-id>:instance-profile/lab69-*`

Сюда входят сами GitHub plan/apply roles.

Для учебной lab в одном AWS account это удобно, но в production появляется bootstrap-риск:

```text
Pipeline, который может редактировать собственную policy, может случайно или намеренно расширить свои права.
```

Production-варианты:

- управлять CI-ролями в отдельном identity/bootstrap stack
- защищать изменения CI role policies через CODEOWNERS и required reviewers
- использовать permissions boundaries для ролей, которые создаёт Terraform
- использовать Service Control Policies или guardrails на уровне организации
- держать отдельный break-glass путь для восстановления

---

## F) `iam:PassRole` Contract

`iam:PassRole` — одно из самых важных прав в автоматизации Terraform. Он опасен, потому что позволяет одному сервису получить роль.

Например EC2 instance сам по себе не получает IAM-права. Ему прикрепляют instance profile, внутри которого role:

```text
EC2 instance
-> instance profile
-> IAM role
-> permissions
```

Чтобы Terraform создал EC2 с instance profile, apply role должна иметь `iam:PassRole`.

Но если сделать так:

```json
{
  "Action": "iam:PassRole",
  "Resource": "*"
}
```

Тогда pipeline сможет передать EC2 любую роль, включая admin runtime role, если такая есть.

В lab используется более узкая форма:

```json
{
  "Sid": "PassOnlyLabRuntimeRolesToEc2",
  "Effect": "Allow",
  "Action": "iam:PassRole",
  "Resource": "arn:aws:iam::<account-id>:role/${var.project_name}-ec2-ssm-role",
  "Condition": {
    "StringEquals": {
      "iam:PassedToService": "ec2.amazonaws.com"
    }
  }
}
```

Это значит: `apply role` может передать только `-ec2-ssm-role` и только сервису EC2.

Нельзя:

- передать произвольную `admin role`;
- передать `роль Lambda`;
- передать `роль ECS`;
- использовать `PassRole` как общий путь повышения привилегий.

Критерии:

- [ ] разрешённую EC2 runtime role можно передать
- [ ] произвольную admin role нельзя передать
- [ ] отказанная PassRole-попытка сохранена как доказательство

---

## G) OIDC Trust Hardening

Permissions policy отвечает за то:
- что `role` может делать

Trust policy отвечает за то:
- кто может использовать `role`

GitHub Actions не хранит AWS keys. Он получает OIDC token и делает:

```text
GitHub OIDC token -> AWS STS AssumeRoleWithWebIdentity -> временные AWS credentials
```

`Plan role` trust:

```text
repo:<owner>/<repo>:pull_request
repo:<owner>/<repo>:ref:refs/heads/main
```

То есть `plan` может работать из `PR` и `main`.

`Apply role` trust только:

```text
repo:<owner>/<repo>:environment:terraform-dev
```

Это значит:

```text
PR job не может assume apply role
branch job без environment не может assume apply role
только job через GitHub Environment terraform-dev может получить apply credentials
```

Если `terraform-dev` существует, но нет `required reviewers`/`wait timer`, то `trust subject` будет правильный, но ручной gate будет слабый.

Чеклист trust policy:

- `aud` = `sts.amazonaws.com`
- plan role принимает только PR и protected branch subjects
- apply role принимает только environment subject
- environment имеет reviewers или wait timer
- нет wildcard для repo owner
- нет wildcard для environment name
- GitHub Environment имеет protection rules

---

## H) Iterative Least-Privilege Workflow

Least privilege редко получается правильно с первой попытки.

Используй повторение:

```text
1. Начать с рабочей широкой роли
2. Убрать широкую managed policy
3. Прикрепить кандидатную ограниченную policy
4. Запустить plan/apply drill
5. Получить AccessDenied
6. Добавить только недостающий action/resource
7. Повторить
8. Проверить через Access Analyzer / last accessed data
9. Сохранить доказательства
```

Если `AccessDenied` появляется во время нормального безопасного `apply`, это значит:
- policy слишком узкая для легитимной операции и её надо расширить минимально.

Пример плохой реакции:

```text
AccessDenied на ec2:CreateTags
-> вернуть AdministratorAccess
```

Пример правильной реакции:

```text
AccessDenied на ec2:CreateTags
-> добавить ec2:CreateTags
-> по возможности ограничить Resource/Condition
-> сохранить почему добавили
```

Access Analyzer может генерировать policy templates из CloudTrail access activity. Это полезно, но это не замена инженерному review.

При review generated policy:

- убрать лишние actions
- отделить backend от инфраструктурных прав
- оставить `iam:PassRole` явным
- не wildcard-ить IAM resources без документированной причины
- оставить negative tests, которые доказывают, чего роль делать не может

---

## I) Упражнения

### Упражнение 1 - Проверить, что admin-доступ убран

Проверь, что apply role больше не имеет `AdministratorAccess`.

```bash
aws iam list-attached-role-policies \
  --role-name lab69-github-actions-apply-role \
  --output table
```

Ожидаемо:

- нет `AdministratorAccess`
- есть ограниченная inline policy

Сохранить:

```bash
aws iam list-role-policies \
  --role-name lab69-github-actions-apply-role \
  --output json > apply-role-inline-policies.json
```

---

### Упражнение 2 - Plan role может выполнить plan

Цель: доказать, что lab69-github-actions-role достаточно прав для backend lock + refresh + `terraform plan`.

Запусти:

```bash
gh workflow list
```

Запусти нужный workflow из списка:

```bash
gh workflow run lesson69-terraform-apply-dev.yml \
  -f confirm_apply=APPLY
```

Смотреть запуск:

```bash
gh run watch
```

Ожидаемо:

- backend init работает
- refresh работает
- plan создан

---

### Упражнение 3 - Plan role не может выполнить apply

Временно настрой test run на apply через plan role или сделай безопасную прямую команду на изменение с этой ролью.

Ожидаемо:

```text
AccessDenied
```

Не оставляй это как обычный workflow. Это negative proof: упражнение, которое доказывает запрет.

---

### Упражнение 4 - Apply role может выполнить безопасное изменение

Сделай низкорисковое изменение: описание CloudWatch alarm или безопасный tag.

```json
common_tags = {
  Owner = "DevOpsTrack"
  Drill = "safe-apply"
}
```

Ожидаемо:

- `plan-dev` создаёт артефакт плана
- ревьюер подтверждает `terraform-dev`
- `apply-dev` применяет именно этот `tfplan`
- post-apply plan возвращает exit code `0`

---

### Упражнение 5 - Граница PassRole

Попробуй поменять launch template или instance profile path на не-lab role.

```json
  dynamic "iam_instance_profile" {
    for_each = var.enable_web_ssm ? [1] : []
    content {
      name = "l69-passrole-denied-dummy-profile"
    }
```

Ожидаемо:

```text
iam:PassRole denied
```

Сразу revert после доказательства.

---

### Упражнение 6 - Неправильный OIDC subject не может assume apply role

Попробуй assume apply role из job, который не использует environment `terraform-dev`.

Ожидаемо:

```text
Could not assume role with OIDC
```

Это доказывает, что trust policy так же важна, как permissions policy.

---

## J) Proof Pack

Рекомендуемая папка evidence:

```text
lessons/69-production-iam-least-privilege-plan-and-apply-roles/evidence/l69-YYYYmmdd_HHMMSS/
```

Сохранить:

```text
apply-role-attached-policies.json
apply-role-inline-policies.json
plan-role-inline-policies.json
apply-role-trust-policy.json
plan-role-trust-policy.json
plan-role-plan-success.txt
plan-role-apply-denied.txt
apply-safe-change-run.md
passrole-denied.txt
access-analyzer-notes.md
```

---

## Частые ошибки

- заменить `AdministratorAccess` на другую широкую managed policy и назвать это least privilege
- забыть backend lockfile permissions
- ожидать, что каждый AWS action поддерживает resource-level scoping
- оставить `iam:PassRole` с `Resource = "*"`
- позволить PR jobs assume apply role
- дать pipeline редактировать собственные permissions без review
- удалить break-glass path до проверенного recovery
- доверять Access Analyzer output без чистки

---

## Финальные критерии

- [ ] plan role имеет ограниченные backend и read/refresh permissions
- [ ] plan role не имеет permissions на изменение инфраструктуры
- [ ] apply role не имеет `AdministratorAccess`
- [ ] apply role имеет ограниченные backend, read, mutate, IAM и PassRole permissions
- [ ] apply trust привязан к GitHub Environment `terraform-dev`
- [ ] `iam:PassRole` ограничен разрешённой EC2 runtime role и сервисом
- [ ] negative drill доказывает, что plan role не может выполнить apply
- [ ] негативное упражнение доказывает, что неправильный OIDC subject не может assume apply role
- [ ] безопасный apply всё ещё работает
- [ ] proof pack собран и отредактирован

---

## Итоги Урока

- **Что изучил:** как перейти от controlled apply с широкими permissions к scoped IAM.
- **Что практиковал:** разделение plan/apply roles, backend lockfile permissions, ограниченную apply policy, границы PassRole, усиление OIDC trust.
- **Продвинутые навыки:** итеративное уточнение least privilege через denied evidence и Access Analyzer.
- **Операционный фокус:** убрать `AdministratorAccess` из обычного процесса доставки, но оставить recovery paths явными.
