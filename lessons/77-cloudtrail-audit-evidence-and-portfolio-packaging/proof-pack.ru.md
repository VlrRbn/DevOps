# Пакет доказательств урока 77

Сохраняй доказательства в локальной папке, которая игнорируется Git, например:

```bash
mkdir -p lessons/77-cloudtrail-audit-evidence-and-portfolio-packaging/evidence/l77-$(date -u +%Y%m%d_%H%M%S)
```

Не коммить сырые доказательства без осознанной редактуры. `tfplan.json`, `backend.hcl`, `terraform.auto.tfvars` и runtime outputs могут содержать account IDs, ARNs, внутренние DNS names, IP-адреса и другую операционную информацию.

---

## 1. Снимок CloudTrail

Сохрани:

```text
cloudtrail-summary.md
aws-caller-identity.json
aws-cli-version.txt
assume-role-with-web-identity-events.json
iam-events.json
ec2-events.json
elbv2-events.json
autoscaling-events.json
cloudtrail-trails.json
cloudtrail-event-selectors.json
cloudtrail-events.json
recent-events.json
s3-management-events.json
denied-events.json
```

Должно быть видно:

- время сбора;
- регион;
- AWS identity, через которую собирался аудит;
- доказательство OIDC role assumption, если workflow запускался;
- последние события сервисов, связанные с Terraform delivery;
- краткое объяснение, если часть событий не найдена или проверка отложена.

---

## 2. Связь GitHub и AWS

Сохрани таблицу с:

```text
GitHub run URL
Commit SHA
Target environment
Release ID
Plan/apply role ARN или замаскированный ARN
CloudTrail event time
CloudTrail event name
Apply result
Post-apply result
```

Ожидаемый вывод:

```text
Доказательства из GitHub workflow и CloudTrail описывают одно и то же изменение.
```

---

## 3. Доказательство OIDC role assumption

Сохрани:

```text
assume-role-with-web-identity-events.json
assume-role-review.md
```

Проверь поля:

```text
eventName
requestParameters.roleArn
requestParameters.roleSessionName
responseElements.assumedRoleUser.arn
errorCode
errorMessage
```

---

## 4. Доказательство AccessDenied

Сохрани один из вариантов:

```text
access-denied-decision.md
cloudtrail-after-deny.json
```

Если во время lab не было denied event, явно задокументируй это.

Решение должно сказать:

- ожидаемый guardrail или недостающее разрешение;
- какая роль участвовала;
- имя события и source;
- какое действие принято.

---

## 5. Решение по аудиту state backend

Сохрани:

```text
state-backend-audit-decision.md
audit-trail-plan.txt
audit-trail-apply.txt
audit-trail-outputs.txt
```

Должно быть:

- state bucket;
- state prefix;
- включены ли S3 data events;
- где они проверяются: CloudTrail Lake, Athena по trail logs или другая система аудита;
- решение по стоимости и шуму;
- production-рекомендация.

Важно: `aws cloudtrail lookup-events` полезен для недавних management events, но не является полноценным способом поиска object-level S3 data events.

Если optional `lab_77/audit-trail/` не применялся, явно напиши `deferred`. Если применялся, сохрани `terraform output`, `cloudtrail-event-selectors.json` и имя trail, которое передавалось в snapshot script.

---

## 6. Проверка редактирования

Перед публичной публикацией проверь, что удалены или замаскированы:

- AWS account IDs;
- полные ARNs;
- internal DNS names;
- private IPs;
- сырой `tfplan.json`;
- Terraform state files;
- secret values;
- notification emails/endpoints;
- непроверенные сырые события CloudTrail.

---

## 7. Итоговая заметка

Создай:

```text
lesson77-final-review.md
```

Шаблон:

```markdown
# Итоговая проверка урока 77

- Снимок CloudTrail собран: yes/no
- OIDC role assumption найден: yes/no
- AccessDenied разобран: yes/no/deferred
- Решение по аудиту state backend заполнено: yes/no
- Портфолио отредактировано перед публикацией: yes/no
- Файлы, безопасные для публичного показа, выбраны: yes/no
- Где лежат оставшиеся чувствительные доказательства:
- Итоговое решение:
```
