# Пакет доказательств урока 70

Этот чеклист нужен для доказательств по Policy as Code на Terraform JSON Plan.

Рекомендуемая игнорируемая папка:

```text
lessons/70-policy-as-code-terraform-json-plan/evidence/l70-YYYYmmdd_HHMMSS/
```

## 1. Артефакты Plan

Сохрани:

```bash
cp tfplan.txt evidence/l70-YYYYmmdd_HHMMSS/
cp tfplan.json evidence/l70-YYYYmmdd_HHMMSS/
```

Обязательные файлы:

- `tfplan.txt`
- `tfplan.json`

Перед публикацией проверь и замаскируй чувствительные данные.

## 2. Решение Policy

Сохрани:

```bash
cp policy-results/policy-decision.txt evidence/l70-YYYYmmdd_HHMMSS/
cp policy-results/policy-output.txt evidence/l70-YYYYmmdd_HHMMSS/
cp policy-results/policy-deny.json evidence/l70-YYYYmmdd_HHMMSS/
cp policy-results/policy-warn.json evidence/l70-YYYYmmdd_HHMMSS/
```

Обязательные файлы:

- `policy-decision.txt`
- `policy-output.txt`
- `policy-deny.json`
- `policy-warn.json`

## 3. Доказательства по правилам

Сохрани выходные файлы по отдельным правилам:

- `destructive.json`
- `destructive-unapproved.json`
- `public-ingress-rules.json`
- `public-ingress-inline-sg.json`
- `missing-tags.json`
- `warn-nat.json`
- `warn-asg-max.json`
- `warn-public-lb.json`

## 4. Доказательства для exception

Если destroy/replacement был разрешён, сохрани:

- exception file
- ссылку на approval
- причину
- дату истечения
- policy decision до и после exception
- доказательство invalid exception, если проверялся wildcard или некорректный exception
- доказательство истёкшего exception, если такая проверка выполнялась

Destroy exceptions без точных addresses должны отклоняться.
Destroy exceptions с прошедшей датой `expires` должны отклоняться относительно текущей UTC-даты.

## 5. Проверки на ложные срабатывания

Если проверяешь policy глубже, сохрани доказательства:

- public ingress блокируется
- public egress не блокируется правилом ingress
- отсутствующие required tags блокируются
- пустые значения required tags блокируются

## 6. Доказательства CI

Если использовал GitHub Actions, сохрани:

- URL workflow run
- имя plan artifact
- имя apply artifact
- скриншот или заметку о подтверждении GitHub Environment
- результат post-apply drift check

## 7. Финальное решение

Создай `decision.txt`:

```text
DECISION=ALLOW|DENY
reason=<short explanation>
reviewer=<name or handle>
timestamp=<UTC timestamp>
artifacts=<folder path>
```

## 8. Чеклист маскирования

Перед коммитом или публикацией проверь:

- AWS account IDs
- ARNs, если они раскрывают внутреннюю инфраструктуру
- instance IDs
- public IPs
- secret values
- имена backend bucket, если считаешь их приватными
- GitHub role ARNs
