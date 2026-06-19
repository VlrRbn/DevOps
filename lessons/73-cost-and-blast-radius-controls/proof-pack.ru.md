# Пакет доказательств урока 73

Сохраняй доказательства в локальной папке, которая игнорируется Git, например:

```text
lessons/73-cost-and-blast-radius-controls/evidence/l73-cost-guard/
```

Не коммить сырой billing output, account IDs, email-адреса или внутренние DNS-имена без редактирования.

---

## 1. Доказательства по plan policy

Сохрани:

```text
security-policy-decision.txt
security-policy-deny.json
security-policy-warn.json
```

Базовая policy должна всё ещё доказывать:

- destructive changes заблокированы без явного approval;
- public ingress заблокирован;
- required tags проверяются.

---

## 2. Доказательства по cost policy

Сохрани вывод:

```bash
lessons/73-cost-and-blast-radius-controls/policies/test-cost-policy.sh
```

Практичный вариант:

```bash
mkdir -p lessons/73-cost-and-blast-radius-controls/evidence/l73-cost-guard

lessons/73-cost-and-blast-radius-controls/policies/test-cost-policy.sh \
  > lessons/73-cost-and-blast-radius-controls/evidence/l73-cost-guard/cost-policy-tests.txt 2>&1
```

Минимальные файлы:

```text
cost-policy-safe.txt
cost-policy-nat-dev-deny.txt
cost-policy-nat-stage-warn.txt
cost-policy-asg-deny.txt
cost-policy-large-instance-deny.txt
cost-policy-public-lb-warn.txt
```

---

## 3. Доказательства Infracost

Если Infracost доступен, можно сканировать реальный `tfplan.json`, но помни: это отправляет metadata плана во внешний сервис Infracost. Делай это только для lab/non-sensitive планов. В proof-pack сохраняй результат сканирования, а не сырой `tfplan.json`:

```text
infracost.json
infracost-summary.txt
infracost-top.txt
infracost-failing.txt
```

---

## 4. Доказательства AWS Budget

Сохрани отредактированный proof file:

```text
aws-budget-proof-redacted.txt
```

Укажи:

- budget name;
- monthly limit;
- threshold type: actual/forecasted;
- notification target: redacted;
- date checked.

---

## 5. Доказательства по квотам

Сохрани хотя бы одну релевантную quota check:

```text
service-quota-ec2.txt
service-quota-elb.txt
```

В заметке должно быть написано, укладывается ли lab-дизайн в quota.

Пример read-only команды:

```bash
aws service-quotas list-service-quotas \
  --service-code elasticloadbalancing \
  --region eu-west-1 \
  --output table \
  > lessons/73-cost-and-blast-radius-controls/evidence/l73-cost-guard/service-quota-elb.txt
```

---

## 6. Решение по cost risk

Создай:

```text
cost-decision.md
```

`Commit SHA` нужен для audit trail. Это не требует `git commit` или `git push`; возьми текущий локальный `HEAD`:

```bash
git rev-parse HEAD
git status --short
```

Если рабочее дерево не чистое, заполни строку `Working tree status`.

Шаблон:

```markdown
# Решение по cost и blast radius

- Дата проверки: 2026-06-12
- Commit SHA: REPLACE_WITH_GIT_REV_PARSE_HEAD
- Working tree status: dirty, lesson 73 files modified locally
- Целевое окружение: dev
- Источник Terraform plan: lab_73/terraform/envs/dev/tfplan.json
- Версия release/module: local lesson 73 module source

## Security/change policy

- Решение security policy: baseline policy tests passed
- Deny от security policy: нет в принятом proof
- Warnings от security policy: смотри сгенерированные policy evidence, если есть

## Cost policy

- Решение cost policy: ALLOW
- Deny от cost policy: []
- Warnings от cost policy: смотри real-dev-cost-policy/cost-warn.json

## Infracost

- Infracost приложен: yes
- Diagnostics Infracost: none
- Оценочная месячная стоимость: $150
- Ресурсы: 48 всего, 17 с оценкой стоимости, 31 бесплатный
- Главная статья затрат: 5 Interface VPC Endpoints в 2 AZ, примерно $120/month
- Важные замечания:
  - ALB HTTP listener не перенаправляет HTTP на HTTPS.
  - EC2 ssm_proxy потенциально может использовать Graviton, но для этого нужен ARM-compatible AMI.
  - Пример tagging policy в Infracost ожидает тег Service и значения Environment Dev/Stage/Prod.

## AWS Budget

- AWS Budget проверен: yes
- Файл доказательства Budget: aws-budget-proof-redacted.txt
- Budget — это страховочная система оповещений, а не мгновенный блокер apply.

## Quotas

- Quota проверена: yes
- Файл доказательства quota: service-quota-elb.txt
- Решение по ELB quota: lab design укладывается в проверенные quotas.

## Решение

- Apply разрешён для lab: yes
- Причина: deterministic cost policy разрешает dev plan; Infracost estimate принят для lab; дорогие VPC endpoints понятны как главная статья затрат; Budget и quota evidence приложены.
- Reviewer: ---
```
