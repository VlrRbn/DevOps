# Урок 73. Контроль расходов и blast radius

**Дата:** 2026-06-12

**Фокус:** добавить видимость расходов, бюджетные ограничения, учёт квот и контроль blast radius в Terraform delivery до `apply`.

**Подход:** безопасный Terraform plan должен быть не только технически валидным и безопасным, но ещё финансово разумным и ограниченным по области воздействия.

---

## 1. Зачем нужен этот урок

К уроку 72 delivery chain уже сильная:

```text
module contracts -> native tests -> versioned module releases -> dev/stage/prod promotion -> JSON plan policy -> controlled apply
```

Но остаётся production-риск:

```text
Валидный Terraform plan всё ещё может быть финансово опасным.
```

Примеры:

- ASG `max_size` меняется с `4` на `40`;
- NAT Gateway появляется в дешёвом lab-окружении;
- случайно выбран слишком большой instance type;
- prod получает больший blast radius, чем нужен release;
- риск по квотам замечают только после failed apply;
- budget alerts вроде есть, но доказательства никто не сохранил.

Урок 73 добавляет pre-apply проверки расходов и blast radius.

---

## 2. Результаты урока

После урока ты должен уметь:

- объяснить разницу между cost risk и blast radius;
- определить лимиты расходов по окружениям;
- запускать cost/blast-radius policy против `tfplan.json`;
- блокировать ASG scale выше env limit;
- делать изменения NAT Gateway видимыми и завязанными на окружение;
- блокировать слишком большие instance types для lab;
- сохранять доказательства по budget и quotas;
- готовить файл cost decision до approval/apply.

---

## 3. Связь с предыдущими уроками

| Урок | Что уже есть | Что добавляет урок 73 |
| --- | --- | --- |
| 70 | JSON plan policy | cost-specific правила по тому же `tfplan.json` |
| 71 | multi-environment promotion | разные лимиты расходов для разных окружений |
| 72 | versioned module releases | доказательства cost review для продвигаемых версий модуля |

Главная идея:

```text
Security policy отвечает: change достаточно безопасен?
Cost policy отвечает: change достаточно доступен по цене и ограничен по области воздействия для этого environment?
```

---

## 4. Структура репозитория

```text
lessons/73-cost-and-blast-radius-controls/
├── README.md
├── lesson.en.md
├── lesson.ru.md
├── proof-pack.en.md
├── proof-pack.ru.md
├── ci/
│   └── lesson73-cost-guard.yml
├── policies/
│   ├── terraform-plan-policy.sh
│   ├── cost-policy.sh
│   ├── test-policy.sh
│   ├── test-cost-policy.sh
│   └── tests/
└── lab_73/
    ├── packer/
    └── terraform/
        ├── envs/
        │   ├── dev/
        │   ├── stage/
        │   └── prod/
        └── modules/
            └── network/
```

`lab_73` сохраняет структуру delivery из уроков 71-72. Новая тема — дополнительный слой guardrails.

---

## 5. Cost Risk и Blast Radius

| Тип риска | Значение | Пример |
| --- | --- | --- |
| Cost risk | сколько денег может сжечь изменение | NAT Gateway, дорогой instance type, большой ASG |
| Blast radius | какую область может затронуть изменение | prod rollout, public ALB, shared IAM role, общий state/backend |
| Quota risk | может ли изменение упереться в AWS limits | ALB quota, EIP quota, IAM role quota, CloudWatch alarm quota |
| Recovery risk | насколько сложным становится rollback | replacement, deletion, stateful resource change |

Change может быть дешёвым, но опасным:

```text
public ingress from 0.0.0.0/0
```

Change может быть дорогим, но технически валидным:

```text
NAT Gateway in every lab environment
```

`Security policy` отвечает:

- Это безопасно с точки зрения доступа, `destructive changes`, `public ingress`, `tags`?

`Cost policy` отвечает:

Это допустимо по цене и масштабу для конкретного environment?

Нужны обе policy: `security` и `cost/blast-radius`.

---

## 6. Матрица рисков по окружениям

Учебные пороги:

| Environment | ASG max_size limit | NAT Gateway | Public ALB | Intent |
| --- | ---: | --- | --- | --- |
| `dev` | 2 | deny | warn | дешёвый по умолчанию |
| `stage` | 3 | warn | warn | похоже на production, но с контролем |
| `prod` | 4 | warn | warn | только осознанные изменения |

Числа специально маленькие, чтобы ошибки были видны в lab.

В production эти значения настраиваются по реальным budgets, владельцам сервисов, трафику и rollback strategy.

---

## 7. Cost Policy

`policies/cost-policy.sh` читает Terraform JSON plan и целевое environment:

```bash
policies/cost-policy.sh tfplan.json dev
```

Он пишет:

```text
cost-policy-results/
  cost-decision.txt
  cost-deny.json
  cost-warn.json
```

Текущие правила:

| Правило | Решение | Зачем |
| --- | --- | --- |
| ASG `max_size` выше лимита окружения | deny | защищает от неконтролируемого масштабирования |
| NAT Gateway в `dev` | deny | dev должен быть дешёвым по умолчанию |
| NAT Gateway в `stage/prod` | warn | расходы должны быть видимыми |
| large instance type | deny | блокирует случайно дорогие вычислительные ресурсы |
| public ALB | warn | сигнал для проверки blast radius |

Важно понимать границы этого скрипта:

- он не считает точную цену AWS;
- он не заменяет Infracost, AWS Budgets или Cost Explorer;
- он проверяет известные рискованные паттерны в Terraform JSON plan;
- часть рисков в уроке проверяется на искусственных fixtures из `policies/tests/`, чтобы не создавать дорогие ресурсы в AWS;
- для реального apply pipeline этот скрипт должен запускаться после `terraform show -json`, на том же сохранённом плане, который потом будет применяться.

Полная логика в коротком виде:

1. Получить tfplan.json и target_env
2. Проверить jq и файл plan
3. Выбрать лимиты для dev/stage/prod
4. Проверить ASG max_size
5. Проверить NAT Gateway
6. Проверить большие EC2 instance types
7. Проверить public Load Balancer
8. Собрать deny в cost-deny.json
9. Собрать warnings в cost-warn.json
10. Записать cost-decision.txt
11. Если deny_count > 0 → DENY, exit 2
12. Если deny_count == 0 → ALLOW, exit 0

Когда заполняешь `cost-decision.md`, поле `Commit SHA` не означает, что нужно делать commit или push. Оно фиксирует текущий локальный `HEAD`, против которого выполнялась проверка:

```bash
git rev-parse HEAD
git status --short
```

Если `git status --short` не пустой, явно запиши это в decision:

```text
Working tree status: dirty, lesson 73 files modified locally
```

Так через месяц будет понятно не только какой commit был базой, но и были ли локальные незакоммиченные изменения во время проверки.

---

## 8. Локальные проверки policy

Запусти все policy tests:

```bash
lessons/73-cost-and-blast-radius-controls/policies/test-policy.sh
lessons/73-cost-and-blast-radius-controls/policies/test-cost-policy.sh
lessons/73-cost-and-blast-radius-controls/policies/test-opa.sh
```

Индивидуальные примеры:

```bash
lessons/73-cost-and-blast-radius-controls/policies/cost-policy.sh \
  lessons/73-cost-and-blast-radius-controls/policies/tests/cost-safe-plan.json \
  dev
```

Ожидаемо: `COST_POLICY_DECISION=ALLOW`.

```bash
lessons/73-cost-and-blast-radius-controls/policies/cost-policy.sh \
  lessons/73-cost-and-blast-radius-controls/policies/tests/cost-high-asg-plan.json \
  dev
```

Ожидаемо: `COST_POLICY_DECISION=DENY`.

```bash
lessons/73-cost-and-blast-radius-controls/policies/cost-policy.sh \
  lessons/73-cost-and-blast-radius-controls/policies/tests/cost-nat-plan.json \
  stage
```

Ожидаемо: `COST_POLICY_DECISION=ALLOW`, при этом cost/blast-radius warnings должны быть видны.

---

## 9. Модель CI

`ci/lesson73-cost-guard.yml` — учебная копия GitHub Actions workflow.

Он специально не получает AWS roles. Цель — доказать module и policies до подключения gate к реальному apply workflow.

Workflow проверяет:

1. Terraform format;
2. Packer format;
3. module native tests;
4. env root validation без remote state;
5. baseline plan policy tests;
6. cost policy tests;
7. optional OPA tests;
8. загрузку policy evidence.

В реальном apply workflow порядок должен быть таким:

```text
terraform plan
-> terraform show -json
-> security/change policy
-> cost/blast-radius policy
-> human approval
-> apply exact saved plan
```

---

## 10. Доказательства Infracost

Infracost полезен для оценки стоимости, но этот урок не требует его для локальных проверок.

Проверка:

```bash
infracost auth whoami
```

Для proof-pack лучше сканировать не всё дерево Terraform, а конкретный сохранённый план. Так Infracost проверяет именно тот `tfplan.json`, который был создан перед ручной проверкой:

```bash
terraform -chdir=lessons/73-cost-and-blast-radius-controls/lab_73/terraform/envs/dev \
  plan -input=false -no-color -out=tfplan

terraform -chdir=lessons/73-cost-and-blast-radius-controls/lab_73/terraform/envs/dev \
  show -json tfplan \
  > lessons/73-cost-and-blast-radius-controls/lab_73/terraform/envs/dev/tfplan.json

infracost scan lessons/73-cost-and-blast-radius-controls/lab_73/terraform/envs/dev/tfplan.json
```

Если сканировать всё дерево Terraform, Infracost может споткнуться о границы локальных модулей. Для точной проверки использовать сканирование `tfplan.json` без diagnostics-ошибок.

Security note: `infracost scan tfplan.json` отправляет metadata плана во внешний сервис Infracost. Делай это только для lab/non-sensitive планов или если Infracost одобрен как third-party vendor. Не отправляй планы, которые могут содержать secrets, customer data или sensitive production metadata.

Сохрани:

```bash
mkdir -p lessons/73-cost-and-blast-radius-controls/evidence/l73-cost-guard

infracost inspect --summary \
  > lessons/73-cost-and-blast-radius-controls/evidence/l73-cost-guard/infracost-summary.txt

infracost inspect --json \
  > lessons/73-cost-and-blast-radius-controls/evidence/l73-cost-guard/infracost.json

infracost inspect --failing \
  > lessons/73-cost-and-blast-radius-controls/evidence/l73-cost-guard/infracost-failing.txt

infracost inspect --top 10 \
  > lessons/73-cost-and-blast-radius-controls/evidence/l73-cost-guard/infracost-top.txt
```

Операционное правило:

```text
Cost estimate is evidence, not an invoice.
```

Используй Infracost как один сигнал. `cost-policy.sh` остаётся детерминированным pre-apply gate для известных рисков lab.

---

## 11. AWS Budgets

AWS Budgets — страховка на стороне billing. Они полезны, но не являются мгновенным блокером для Terraform apply.

Запусти:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws budgets describe-budgets \
  --account-id "$ACCOUNT_ID" \
  --output table > budget.txt
```

Сделай redacted budget proof:

```bash
mkdir -p lessons/73-cost-and-blast-radius-controls/evidence/l73-cost-guard

cat > lessons/73-cost-and-blast-radius-controls/evidence/l73-cost-guard/aws-budget-proof-redacted.txt <<'EOF'
Checked: 2026-06-18
AWS account: redacted
Region: global billing service

Budget reviewed:
- Budget name:
- Budget type:
- Time unit:
- Monthly limit:
- Actual threshold:
- Forecasted threshold:
- Notification target: redacted

Decision:
- AWS Budget exists.
- Budget provides billing-side alerting.
- Budget is not an instant Terraform apply blocker.
- Lesson 73 still requires pre-apply cost policy checks.
EOF
```

Этот файл доказывает не точную цену `plan`, а наличие второго слоя защиты:

```text
Pre-apply cost policy предотвращает известные опасные changes до apply.
Budget alerts показывают, когда реальные расходы приближаются к лимитам.
```

Используй оба.

---

## 12. Понимание квот

Cost — не единственный лимит. Квоты могут остановить или ухудшить release.

Проверь хотя бы одну релевантную квоту:

| Область | Service code | Что полезно смотреть |
| --- | --- | --- |
| EC2 | `ec2` | On-Demand instances, Elastic IPs, AMIs, key pairs |
| VPC | `vpc` | VPCs, subnets, NAT gateways, internet gateways, security groups |
| Auto Scaling | `autoscaling` | Auto Scaling Groups, launch configurations |
| Load Balancing  | `elasticloadbalancing` | ALB/NLB/CLB, target groups, listeners, rules |
| EKS | `eks` | clusters, nodegroups, Fargate profiles |
| ECS | `ecs` | clusters, services, task definitions |
| Lambda | `lambda` | concurrent executions, function storage |
| RDS | `rds` | DB instances, clusters, snapshots, parameter groups |
| ElastiCache | `elasticache` | clusters, nodes, subnet groups |
| ECR | `ecr` | repositories, image scan quotas |
| CloudWatch Logs | `logs` | log groups, retention-related limits |
| CloudWatch | `cloudwatch` | alarms, dashboards, metrics |
| CloudFormation | `cloudformation` | stacks, stack sets, resources per stack |
| API Gateway | `apigateway` | APIs, stages, routes, throttling |
| SQS | `sqs` | queues, message throughput-related quotas |
| SNS | `sns` | topics, subscriptions |
| KMS | `kms` | keys, aliases, request quotas |
| Secrets Manager | `secretsmanager` | secrets, versions |
| Route 53 | `route53` | hosted zones, records |
| ACM | `acm` | certificates |
| S3 | `s3` | buckets, access points — но `list-service-quotas` может вернуть не все квоты |

Посмотреть все service codes:

```bash
aws service-quotas list-services \
  --region eu-west-1 \
  --query 'Services[].{Name:ServiceName,Code:ServiceCode}' \
  --output table > codes.txt
```

Пример:

```bash
aws service-quotas list-service-quotas \
  --service-code elasticloadbalancing \
  --region eu-west-1 \
  --output table

# Или:

aws service-quotas list-service-quotas \
  --service-code elasticloadbalancing \
  --region eu-west-1 \
  --query 'Quotas[?contains(QuotaName, `Application Load Balancers`) || contains(QuotaName, `Target Groups`) || contains(QuotaName, `Listeners`) || contains(QuotaName, `Rules`) || contains(QuotaName, `Certificates`)].{Name:QuotaName,Value:Value,Adjustable:Adjustable}' \
  --output table
```

Сохрани релевантный вывод или отредактированное резюме в proof-pack.

---

## 13. Упражнения

Все команды запускаются из корня репозитория. Для каждого упражнения используется отдельный `OUT_DIR`, чтобы результаты не перезаписывались.

### Упражнение 1. Safe plan проходит

Запусти `cost-safe-plan.json` против `dev`:

```bash
OUT_DIR=/tmp/l73-cost-safe-dev \
lessons/73-cost-and-blast-radius-controls/policies/cost-policy.sh \
  lessons/73-cost-and-blast-radius-controls/policies/tests/cost-safe-plan.json \
  dev
```

Ожидаемо:

- cost policy разрешает;
- deny-записей нет.
- `/tmp/l73-cost-safe-dev/cost-decision.txt` содержит `COST_POLICY_DECISION=ALLOW`.

### Упражнение 2. NAT в dev блокируется

Запусти `cost-nat-plan.json` против `dev`:

```bash
set +e
OUT_DIR=/tmp/l73-cost-nat-dev \
lessons/73-cost-and-blast-radius-controls/policies/cost-policy.sh \
  lessons/73-cost-and-blast-radius-controls/policies/tests/cost-nat-plan.json \
  dev
rc=$?
echo "exit_code=${rc}"
set -e
```

Ожидаемо:

- cost policy блокирует;
- правило: `nat_gateway_cost_signal`.
- exit code `2`.

### Упражнение 3. NAT в stage даёт warning

Запусти `cost-nat-plan.json` против `stage`:

```bash
OUT_DIR=/tmp/l73-cost-nat-stage \
lessons/73-cost-and-blast-radius-controls/policies/cost-policy.sh \
  lessons/73-cost-and-blast-radius-controls/policies/tests/cost-nat-plan.json \
  stage
```

Ожидаемо:

- cost policy разрешает;
- warning виден в `cost-warn.json`.
- exit code `0`.

### Упражнение 4. Большой ASG max блокируется

Запусти `cost-high-asg-plan.json` против `dev` и `prod`:

```bash
for env in dev prod; do
  set +e
  OUT_DIR="/tmp/l73-cost-high-asg-${env}" \
  lessons/73-cost-and-blast-radius-controls/policies/cost-policy.sh \
    lessons/73-cost-and-blast-radius-controls/policies/tests/cost-high-asg-plan.json \
    "${env}"
  rc=$?
  echo "${env}_exit_code=${rc}"
  set -e
done
```

Ожидаемо:

- оба deny, если `max_size` выше environment limit.
- правило: `deny_asg_max_size_above_env_limit`.

### Упражнение 5. Большой instance блокируется

Запусти `cost-large-instance-plan.json`:

```bash
set +e
OUT_DIR=/tmp/l73-cost-large-instance \
lessons/73-cost-and-blast-radius-controls/policies/cost-policy.sh \
  lessons/73-cost-and-blast-radius-controls/policies/tests/cost-large-instance-plan.json \
  stage
rc=$?
echo "exit_code=${rc}"
set -e
```

Ожидаемо:

- правило: `deny_large_instance_type`.
- exit code `2`.

### Упражнение 6. Public ALB даёт warning

Запусти `cost-public-lb-plan.json` против `prod`:

```bash
OUT_DIR=/tmp/l73-cost-public-lb-prod \
lessons/73-cost-and-blast-radius-controls/policies/cost-policy.sh \
  lessons/73-cost-and-blast-radius-controls/policies/tests/cost-public-lb-plan.json \
  prod
```

Ожидаемо:

- policy разрешает;
- warning требует внимания ревьюера.
- warning находится в `/tmp/l73-cost-public-lb-prod/cost-warn.json`.

---

## 14. Разбор проблем

| Симптом | Вероятная причина | Что делать |
| --- | --- | --- |
| `jq is required` | `jq` не установлен | установи `jq` перед запуском policy-скриптов |
| Cost policy exits `2` | plan нарушает cost/blast rule | смотри `cost-deny.json` |
| NAT warning в stage/prod | ожидаемое поведение | задокументируй причину и решение ревьюера |
| Infracost недоступен | нет токена, аккаунта или инструмента | отметь проверку как отложенную и сохрани deterministic policy evidence |
| Quota output слишком большой | скопирована полная таблица | оставь релевантные строки quota или короткое резюме |
| CI policy проходит, но apply может стоить дороже | policy ловит только смоделированные риски | добавь новое правило или требуй Infracost/budget review |
| Результаты policy перезаписались | несколько запусков использовали один `OUT_DIR` | используй отдельный `OUT_DIR` для каждого упражнения |
| `opa is required` | OPA не установлен локально | установи OPA или запускай только `test-policy.sh` и `test-cost-policy.sh` |
| GitHub Actions workflow не запускается | файл остался в `ci/`, но не скопирован в `.github/workflows/` | скопируй шаблон в `.github/workflows/lesson73-cost-guard.yml` |
| В `git status` появились `artifacts/` или `cost-policy-results/` | сгенерированные файлы не игнорируются | проверь `.gitignore` и не коммить operational artifacts |

---

## 15. Пакет доказательств

Используй `proof-pack.ru.md` как чек-лист.

Минимальные доказательства:

- security policy test output;
- cost policy test output;
- safe plan allow;
- NAT dev deny;
- NAT stage/prod warning;
- ASG max deny;
- large instance deny;
- budget proof или deferral note;
- quota proof или короткое резюме;
- `cost-decision.md`.

---

## 16. Критерии успеха

Урок 73 завершён, если:

- cost policy script существует и исполняемый;
- cost policy tests проходят;
- baseline security policy tests всё ещё проходят;
- module tests проходят;
- safe plan разрешается;
- ASG max-size deny работает;
- large instance deny работает;
- NAT behavior отличается по окружениям;
- budget/quota evidence задокументированы;

---

## 17. Итоги урока

- **Что изучил:** безопасная Terraform delivery должна контролировать финансовый и операционный impact, а не только синтаксис и security.
- **Что практиковал:** cost policy по `tfplan.json`, ASG/NAT/instance-type gates, warnings vs denies, budget и quota evidence.
- **Операционный фокус:** блокировать дорогие или wide-impact changes до approval и apply.
- **Почему это важно:** plan может быть валидным, approved и всё равно financially unsafe.
