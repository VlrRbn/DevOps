# Пакет доказательств урока 69 - минимальные IAM-права для production

Рекомендуемая папка для доказательств:

```bash
mkdir -p lessons/69-production-iam-least-privilege-plan-and-apply-roles/evidence/l69-YYYYmmdd_HHMMSS
```

Перед публичным коммитом замаскируй ID аккаунта, имена бакетов, уникальные ID ролей, при необходимости AMI ID и URL запусков GitHub Actions.

## 1. Инвентаризация политик ролей

Сохрани прикреплённые и встроенные политики (`inline policies`):

```bash
aws iam list-attached-role-policies --role-name lab69-github-actions-apply-role --output json > apply-role-attached-policies.json
aws iam list-role-policies --role-name lab69-github-actions-apply-role --output json > apply-role-inline-policies.json
aws iam list-role-policies --role-name lab69-github-actions-role --output json > plan-role-inline-policies.json
```

Ожидаемый результат:

- apply role не имеет `AdministratorAccess`
- plan role не имеет широких прав на изменение инфраструктуры

## 2. Политики доверия

Сохрани документы trust policy:

```bash
aws iam get-role --role-name lab69-github-actions-apply-role --output json > apply-role-trust-policy.json
aws iam get-role --role-name lab69-github-actions-role --output json > plan-role-trust-policy.json
```

Ожидаемый результат:

- apply role `sub` привязан к GitHub Environment
- plan role `sub` разрешает только PR/main

## 3. Положительные доказательства

Сохрани доказательства, что `plan` и безопасный `apply` всё ещё работают:

```text
plan-role-plan-success.txt
apply-safe-change-run.md
post-apply-exitcode.txt
```

Ожидаемый результат:

- `plan` завершается успешно
- `apply` завершается успешно для безопасного изменения в разрешённой области
- код выхода после контрольного `plan` равен `0`

## 4. Негативные доказательства

Сохрани доказательства отказа в доступе:

```text
plan-role-apply-denied.txt
passrole-denied.txt
wrong-oidc-subject-denied.txt
```

Ожидаемый результат:

- plan role не может менять инфраструктуру
- apply role не может передавать произвольные роли
- задача (`job`) без нужного GitHub Environment не может принять apply role

## 5. Заметки по доработке прав

Сохрани короткую заметку для ревью:

```text
access-analyzer-notes.md
least-privilege-review.md
```

Укажи:

- почему какой-то `Resource = "*"` остался
- действия, которые добавлены после доказанного `AccessDenied`
- действия, которые намеренно отклонены
- дальнейшие шаги для более строгой production IAM-модели
