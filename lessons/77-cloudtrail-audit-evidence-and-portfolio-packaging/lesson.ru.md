# Урок 77. CloudTrail, аудиторские доказательства

**Цель:** закрыть трек Terraform delivery: доказать, что AWS реально записал в аудит, и упаковать итоговый проект.

**Фокус:** аудиторские доказательства CloudTrail, подтверждение OIDC role assumption, заметки по аудиту state backend, расследование `AccessDenied` и безопасная публикация материалов.

---

## 1. Зачем нужен этот урок

Урок 76 доказал delivery pipeline:

```text
PR checks
-> fresh plan from protected branch
-> policy gates
-> cost gates
-> risk classification
-> approval
-> exact saved-plan apply
-> post-apply drift check
-> runtime health evidence
```

Эти доказательства показывают, что сделал pipeline. Но остаётся последний операционный вопрос:

```text
Могу ли я доказать, что увидел AWS?
```

На этот вопрос отвечает CloudTrail. Он записывает вызовы AWS API как события: кто вызвал API, когда, через какую role/session, успешно или нет, и какой сервис/ресурс был затронут.

Terraform-оператор должен уметь связать обе стороны:

```text
GitHub workflow evidence <-> CloudTrail evidence со стороны AWS
```

---

## 2. Результаты урока

После урока ты должен уметь:

- объяснить CloudTrail одним предложением;
- отличать management events от data events;
- находить `AssumeRoleWithWebIdentity` от GitHub Actions OIDC;
- определять plan/apply role, которую использовал Terraform;
- расследовать `AccessDenied` через CloudTrail, а не угадывать;
- объяснять, почему для Terraform S3 backend нужны S3 data events;
- собирать аудиторские доказательства CloudTrail для итогового проекта;
- упаковывать проект для интервью без утечки чувствительных данных.

---

## 3. Связь с предыдущими уроками

| Урок | Что добавил | Что делает урок 77 |
| --- | --- | --- |
| 60 | remote state и locking | объясняет, как аудировать доступ к state object |
| 63 | PR plan pipeline | связывает доказательства CI plan с AWS role assumption |
| 64 | drift detection | использует CloudTrail для расследования неожиданных изменений со стороны AWS |
| 65 | secrets и safe inputs | усиливает редактирование чувствительных данных перед публикацией доказательств |
| 69 | разделение plan/apply roles | доказывает, какая role реально использовалась |
| 70 | JSON plan policy | включает результат policy в доказательную историю |
| 71 | multi-env promotion | связывает продвижение dev/stage/prod с AWS audit trails |
| 76 | end-to-end delivery capstone | становится исходным итоговым проектом для упаковки аудиторских доказательств |

Урок 77 закрывает контур вокруг уже собранной архитектуры.

Отдельный CI для урока 77 не нужен. Проверки скриптов можно запускать локально, а live AWS-проверки CloudTrail остаются ручной практикой, потому что зависят от аккаунта, региона, времени запуска и заранее включённых data events.

---

## 4. Ментальная модель CloudTrail

CloudTrail записывает AWS account activity как события.

- CloudTrail записывает не “сервер работает/не работает”,
- а “кто вызвал какой AWS API”.

CloudTrail отвечает на вопросы:

```text
Кто?
Когда?
Через какую роль/session?
Какой AWS service?
Какой API action?
Успешно или с ошибкой?
Какие request parameters?
Какой errorCode/errorMessage?
```

Представь цепочку:

```text
GitHub Actions job
-> OIDC token
-> STS AssumeRoleWithWebIdentity
-> temporary AWS credentials
-> Terraform calls AWS API
-> CloudTrail records API events
```

Для Terraform delivery самые полезные группы событий:

| Область | Примеры событий | Зачем важно |
| --- | --- | --- |
| STS / OIDC | `AssumeRoleWithWebIdentity` | доказывает, что GitHub Actions получил временные AWS credentials |
| IAM | `CreateRole`, `PutRolePolicy`, `PassRole` | доказывает изменения ролей и политик |
| EC2 / ELB / ASG | `RunInstances`, `CreateLoadBalancer`, `UpdateAutoScalingGroup` | доказывает изменения инфраструктуры |
| S3 backend | `GetObject`, `PutObject`, `DeleteObject` | доказывает доступ к state object, если data events включены |
| CloudTrail | `LookupEvents`, изменения trail | доказывает доступ к аудиту или изменения audit configuration |

`AssumeRoleWithWebIdentity` это обычно первое событие, которое мы ищем после GitHub Actions workflow:

```text
GitHub OIDC token -> AWS STS -> temporary credentials for IAM role
```

Главное правило:

```text
CloudTrail не заменяет доказательства pipeline. Он проверяет и дополняет их.
```

---

## 5. Management Events vs Data Events

| Тип события | Примеры | Поведение по умолчанию | Зачем Terraform |
| --- | --- | --- | --- |
| Management events | IAM, STS, EC2, ALB, ASG control-plane calls | видны в Event History для недавних событий | достаточно для role assumption и infra API calls |
| Data events | S3 object `GetObject`, `PutObject`, `DeleteObject` | нужно включать отдельно | нужны для object-level state audit |

Delivery management events обычно достаточно, чтобы понять:

- какая role использовалась;
- какие AWS API Terraform вызывал;
- где был `AccessDenied`;
- какие control-plane изменения происходили.

Для Terraform state backend нужен object-level S3 audit.

Bucket-level events отвечают на вопросы вроде:

```text
Был ли включён bucket versioning?
Менялась ли bucket policy?
```

Data events уровня объекта отвечают на вопросы вроде:

```text
Кто прочитал terraform.tfstate?
Кто записал terraform.tfstate?
Кто удалил terraform.tfstate.tflock?
```

Data events могут добавить шум и стоимость, будет сложнее искать нужное. В production используй узкие selectors для Terraform state bucket/prefix, а не включай широкие S3 data events на все S3 buckets.

Важное ограничение: `aws cloudtrail lookup-events` удобен для недавних management events. Для object-level S3 data events обычно нужен заранее настроенный источник данных: CloudTrail Lake, Athena по trail logs в S3 или другая система, куда CloudTrail доставляет события.

---

## 6. GitHub Actions OIDC Audit Trail

Цепочка role assumption:

```text
GitHub Actions job
-> OIDC token from token.actions.githubusercontent.com
-> AWS STS AssumeRoleWithWebIdentity
-> temporary AWS credentials
-> Terraform AWS API calls
```

Главное событие:

```text
eventName = AssumeRoleWithWebIdentity
```

Полезные поля:

```text
eventTime
eventSource
eventName
awsRegion
sourceIPAddress
userIdentity
requestParameters.roleArn
requestParameters.roleSessionName
responseElements.assumedRoleUser.arn
errorCode
errorMessage
```

Это событие доказывает, что workflow получил AWS role через OIDC. Оно не доказывает, что весь deployment успешен. Для этого нужно связать его с plan/apply artifacts и post-apply evidence.

**Что конкретно мы проверяем**
1. `eventName`

Должно быть:

```text
AssumeRoleWithWebIdentity
```

2. `requestParameters.roleArn`

Показывает, какую IAM role пытались assume.

Например:

```text
arn:aws:iam::<account-id>:role/lab76-dev-github-actions-plan-role
```

3. `requestParameters.roleSessionName`

Обычно там видно имя session, которое настроено в workflow.

Например:

```text
gha-lesson76-promote-dev
```

4. `responseElements.assumedRoleUser.arn`

Показывает итоговую assumed-role identity.

5. `errorCode` и `errorMessage`

Если всё хорошо, ошибки нет. Если OIDC trust policy неправильная, может быть `AccessDenied`.

**Что это доказывает**
Это доказывает:

```text
GitHub Actions действительно получил временные AWS credentials для нужной role.
```

**Что это НЕ доказывает**
Это не доказывает:

```text
Terraform apply был успешен
инфраструктура работает
risk decision был правильный
post-apply drift clean
```

Для этого нужны другие доказательства:
- `plan.txt`;
- `tfplan.json`;
- `risk-decision.md`;
- `apply.txt`;
- `post_apply_plan.txt`;
- runtime health evidence;
- GitHub run URL;
- commit SHA.

**Как связать GitHub и AWS**
Минимальная связка:

```text
GitHub run URL
Commit SHA
Target environment
Role ARN
Role session name
CloudTrail eventTime
Apply result
Post-apply result
```

---

## 7. Базовые CloudTrail CLI команды

Найти последние OIDC role assumptions:

```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity \
  --region eu-west-1 \
  --max-results 10 \
  --query 'Events[].{Time:EventTime,Name:EventName,User:Username,EventId:EventId}' \
  --output table
```

Не выводи весь `lookup-events` как table без `--query`: CloudTrail event содержит большой вложенный JSON, и терминал станет почти нечитаемым.

Посмотреть одно событие как JSON:

```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity \
  --region eu-west-1 \
  --max-results 1 \
  --query 'Events[0].CloudTrailEvent' \
  --output text | jq .
```

Найти события IAM:

```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventSource,AttributeValue=iam.amazonaws.com \
  --region eu-west-1 \
  --max-results 20 \
  --query 'Events[].{Time:EventTime,Name:EventName,User:Username,EventId:EventId}' \
  --output table
```

Сохранить последние события для ревью:

```bash
aws cloudtrail lookup-events \
  --region eu-west-1 \
  --max-results 50 \
  --output json > cloudtrail-recent-events.json
```

---

## 8. S3 State Backend Audit

Для Terraform remote state имена объектов обычно выглядят так:

```text
lab76/dev/full/terraform.tfstate
lab76/dev/full/terraform.tfstate.tflock
lab76/stage/full/terraform.tfstate
lab76/prod/full/terraform.tfstate
```

Важные действия с объектами:

```text
GetObject -  кто прочитал terraform.tfstate
PutObject - кто записал terraform.tfstate
DeleteObject - кто удалил state или lock file
CopyObject - кто копировал state object
ListObjectVersions - кто смотрел версии state object
```

`lookup-events` может показать недавние management events, но не стоит воспринимать его как полноценный поиск по object-level S3 access. Чтение и запись `terraform.tfstate` требуют S3 data event logging, включённого до события. Если data events не были включены заранее, CloudTrail не сможет задним числом показать object-level events для этого действия.

Шаблон state backend audit decision:

```markdown
# State Backend Audit Decision

- State bucket:
- State prefix:
- Data events enabled: yes/no/deferred
- Reason:
- Cost risk:
- Production recommendation:
```

Ожидаемая production-рекомендация:

```text
Включить S3 data events только для Terraform state bucket/prefix, а не для всех S3 buckets аккаунта.
Заранее определить, где эти data events будут проверяться: CloudTrail Lake, Athena по trail logs или другая централизованная система аудита.
```

### Optional production path: создать CloudTrail trail

Event History достаточно для базового lab-а, но для production-style аудита нужен отдельный trail. В этом уроке есть optional Terraform root:

```text
lab_77/audit-trail/
```

Он создаёт:

- отдельный S3 bucket для CloudTrail logs;
- public access block;
- S3 bucket versioning;
- SSE-S3 encryption;
- lifecycle retention;
- CloudTrail trail для management events;
- точечные S3 data events только для Terraform state bucket/prefixes.

Это не новая application-инфраструктура. Это audit layer вокруг уже созданного capstone.

Используй его, если хочешь доказать не только recent management events из Event History, но и настроенный audit trail с selectors.

```bash
cd lessons/77-cloudtrail-audit-evidence-and-portfolio-packaging/lab_77/audit-trail
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

После apply:

```bash
terraform output -raw trail_name
```

И передай имя в snapshot script:

```bash
../../scripts/cloudtrail-audit-snapshot.sh \
  --region eu-west-1 \
  --state-bucket YOUR_TFSTATE_BUCKET \
  --state-prefix lab76/dev/full/ \
  --trail-name YOUR_TRAIL_NAME
```

Важно: S3 data events могут стоить денег и давать шум. Не включай их на все buckets аккаунта. Для lab и production scope должен быть узким: только Terraform state bucket/prefixes.

Для более строгого production/compliance можно усилить audit log bucket через S3 Object Lock и SSE-KMS. В lab это не включено по умолчанию: Object Lock усложняет cleanup, а SSE-KMS требует отдельной KMS key policy и добавляет ещё один слой troubleshooting.

#### Cleanup audit trail

По умолчанию `force_destroy_log_bucket = false`. Это значит:

```text
terraform destroy удалит CloudTrail trail и настройки bucket,
но сам S3 log bucket может остаться, если внутри есть log object versions.
```

Это нормальное поведение для audit bucket. Логи не должны исчезать случайно.

Варианты:

1. Оставить bucket как audit evidence.

Это безопасный вариант, если логи могут понадобиться позже.

2. Для disposable lab включить удаление содержимого:

```hcl
force_destroy_log_bucket = true
```

Потом:

```bash
terraform apply -auto-approve
terraform destroy
```

3. Удалить object versions/delete markers вручную, если bucket уже остался после destroy.

Сначала посмотреть содержимое:

```bash
aws s3api list-object-versions \
  --bucket YOUR_CLOUDTRAIL_LOG_BUCKET \
  --region eu-west-1
```

После очистки bucket можно повторить:

```bash
terraform destroy
```

Не удаляй audit logs, если они нужны для proof-pack или расследования.


Например:

```bash
bucket: vlrrbn-tfstate-123456789012-eu-west-1
prefix: lab76/prod/full/
```

---

## 9. Расследование AccessDenied

Когда Terraform падает с `AccessDenied`, не угадывай.

Правильный подход:

```text
Сначала понять, какой API action был запрещён,
какая role его вызвала,
и должен ли этот deny вообще быть ошибкой.
```

Потому что `AccessDenied` бывает двух типов.

### 1. Expected guardrail

Это когда отказ ожидаемый и правильный.

Пример:

- plan role пытается сделать `CreateRole`
- Но plan role должна только читать и строить plan, а не менять AWS.

Тогда `AccessDenied` это не баг. Это доказательство:

- least privilege работает

#### 2. Missing permission

Это когда действие легитимное, но роль слишком узкая.

Пример:

- apply role должна обновить ASG tag
- но не имеет `autoscaling:CreateOrUpdateTags`

Тогда это уже не guardrail, а недостающий permission. Мы не даём `Admin`, а добавляем конкретный action на конкретный scope.

Используй порядок действий:

```text
1. Сохранить Terraform error.
2. Определить примерное время ошибки.
3. Найти события CloudTrail вокруг этого времени.
4. Найти eventName, eventSource, errorCode и errorMessage.
5. Определить assumed role.
6. Решить: это ожидаемый guardrail или недостающее разрешение.
7. Менять IAM только если действие легитимно.
8. Сохранить доказательства до и после.
```

Важные поля:

```text
eventTime
eventName - какой API action
eventSource - какой сервис
awsRegion
userIdentity.type
userIdentity.sessionContext.sessionIssuer.arn - какая IAM role
requestParameters
errorCode - AccessDenied/UnauthorizedOperation
errorMessage - почему отказ
```

Важная мысль:

```text
AccessDenied не всегда ошибка. Иногда это доказательство, что guardrail сработал.
```

---

## 10. Скрипт аудиторского снимка

В уроке есть:

```text
scripts/cloudtrail-audit-snapshot.sh
```

Он собирает:

- AWS caller identity;
- последние события `AssumeRoleWithWebIdentity`;
- последние события IAM;
- последние события EC2, ELBv2 и Auto Scaling;
- недавние события, похожие на denied;
- заметки по S3 backend;
- Markdown summary для ревью.

Пример:

```bash
lessons/77-cloudtrail-audit-evidence-and-portfolio-packaging/scripts/cloudtrail-audit-snapshot.sh \
  --region eu-west-1 \
  --state-bucket YOUR_STATE_BUCKET \
  --state-prefix lab76/ \
  --start-time 2026-07-01T10:00:00Z \
  --end-time 2026-07-01T11:00:00Z \
  --release-id l76-demo \
  --workflow-url https://github.com/OWNER/REPO/actions/runs/123456789 \
  --trail-name YOUR_TRAIL_NAME
```

Скрипт не меняет AWS-ресурсы. Он только читает CloudTrail и STS data.

---

## 11. Практические упражнения

### Упражнение 1. Найти GitHub OIDC Role Assumption

Запусти GitHub Actions workflow из урока 76. Затем выполни:

```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity \
  --region eu-west-1 \
  --max-results 10 \
  --output json > assume-role-events.json
```

Ожидаемые доказательства:

- имя события — `AssumeRoleWithWebIdentity`;
- role ARN совпадает с plan/apply role;
- время события близко к GitHub workflow run;
- нет неожиданного `errorCode`.

### Упражнение 2. Разобрать одно запрещённое действие

Используй безопасный denied case из предыдущих уроков, например plan role пытается менять инфраструктуру.

Сохрани:

```bash
aws cloudtrail lookup-events \
  --region eu-west-1 \
  --max-results 50 \
  --output json > cloudtrail-after-deny.json
```

Напиши короткое решение:

```markdown
# AccessDenied Decision

- Failure time:
- Event name:
- Event source:
- Role:
- Error:
- Expected denial: yes/no
- Action taken:
```

### Упражнение 3. State Backend Audit Decision

Напиши заметку с решением по data events для state backend. Не включай широкие S3 data events вслепую.

Ожидаемый ответ:

```text
Для production backend включить S3 data events только для Terraform state bucket/prefix. Для короткой lab — задокументировать, если это отложено из-за стоимости или лишнего шума.
```

### Упражнение 4. Связать GitHub и AWS Evidence

Выбери один workflow run и собери таблицу:

```markdown
| Evidence | Value |
| --- | --- |
| GitHub run URL |  |
| Commit SHA |  |
| Target environment |  |
| AWS role assumed |  |
| CloudTrail event time |  |
| Risk decision |  |
| Apply result |  |
| Post-apply exit code |  |
```

Ожидаемый результат:

```text
CloudTrail и workflow artifacts описывают одно и то же изменение.
```

---

## 12. Разбор типовых проблем

| Симптом | Вероятная причина | Что проверить |
| --- | --- | --- |
| События CloudTrail не найдены | не тот регион или событие слишком старое | CloudTrail region, time window, Event History retention |
| Нет S3 object access events | data events не включены или проверяются не через `lookup-events` | trail/event selector configuration, CloudTrail Lake, Athena или log destination |
| OIDC-событие отсутствует | workflow не получил AWS role | GitHub job logs, OIDC provider, role trust policy |
| AccessDenied event не очевиден | задержка CloudTrail или не то поле поиска | поиск по времени, source, имени события и role ARN |
| Event показывает не ту роль | переменная или secret workflow указывает на не тот ARN | GitHub variables and environment secrets |
| Доказательства содержат account IDs | сырые файлы скопированы в папку | redaction checklist перед commit |
| Портфолио слишком подробное | утекли внутренние детали реализации | опиши контроли кратко, не публикуй внутренние артефакты |

---

## 13. Пакет доказательств

Создай ignored-папку для доказательств, например:

```bash
mkdir -p lessons/77-cloudtrail-audit-evidence-and-portfolio-packaging/evidence/l77-$(date -u +%Y%m%d_%H%M%S)
```

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
denied-events.json
s3-management-events.json
state-backend-audit-decision.md
access-denied-decision.md
```

Сырые доказательства могут содержать чувствительные операционные метаданные. Храни их локально или редактируй перед commit.

Если файл пустой или событие не найдено, не удаляй этот результат. Сохрани файл и объясни причину в `cloudtrail-summary.md`: это тоже полезное доказательство, если оно понятно описано.

---

## 14. Критерии успеха

Урок завершён, когда:

- [ ] ты можешь объяснить CloudTrail одним предложением;
- [ ] ты можешь найти `AssumeRoleWithWebIdentity`;
- [ ] ты можешь объяснить management events vs data events;
- [ ] ты можешь объяснить, почему для S3 state backend audit нужны data events;
- [ ] ты расследовал один denied event или задокументировал, почему denied event не было;
- [ ] ты создал CloudTrail audit snapshot;
- [ ] ты заполнил state backend audit decision note;
- [ ] ты прошёл redaction checklist перед публикацией;
- [ ] твой proof-pack объясняет и доказательства pipeline, и аудиторские доказательства со стороны AWS.

---

## 15. Итоги урока

- **Что изучил:** CloudTrail даёт аудиторские доказательства со стороны AWS для Terraform delivery.
- **Что практиковал:** поиск OIDC role assumption, проверку Terraform-событий, audit decision для state backend и упаковку итогового проекта.
- **Операционный фокус:** доказать не только то, что сказал pipeline, но и то, что записал AWS.
