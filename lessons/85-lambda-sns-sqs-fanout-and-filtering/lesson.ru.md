# Урок 85: Fan-out из SNS в SQS и фильтрация подписок Lambda

## 1. Зачем нужен этот урок

В уроках 82-84 был построен один путь обработки через SQS и разобраны частичные ошибки,
backpressure, одновременные вызовы, порядок FIFO и дедупликацию. В `production` у
одного события часто бывает несколько независимых потребителей:

```text
order.created
├── журнал аудита
├── расчёты и биллинг
├── аналитика
└── уведомление клиента
```

Если производитель сам отправляет событие в каждую очередь, он начинает знать обо
всех потребителях.

```text
Producer
├── отправляет в audit queue
├── отправляет в billing queue
├── отправляет в analytics queue
└── отправляет в notifications queue
```

Проблемы:

- producer связан со всеми потребителями;
- для добавления новой ветки нужно менять producer;
- возможна частичная публикация: в одну очередь сообщение ушло, в другую — нет;
- producer должен знать адреса и разрешения всех очередей;
- логика маршрутизации расползается по приложению.

В этом уроке границей маршрутизации становится тема SNS.
SNS не помещает одно общее сообщение в две очереди. Он создаёт независимые транспортные копии:

```text
Business event_id: order-123

audit SQS:
  messageId: AAA
  event_id: order-123

billing SQS:
  messageId: BBB
  event_id: order-123
```

Поэтому:

- SQS `messageId` в ветках различается;
- количество попыток обработки различается;
- одна копия может успешно удалиться;
- другая может несколько раз повториться и попасть в DLQ;
- связывать ветки нужно по бизнес-полю `event_id`, а не по SQS `messageId`.

В лабораторной используется путь `SNS -> SQS -> Lambda`, а не прямая подписка
Lambda на SNS.

SQS добавляет каждой ветке:

- независимый буфер;
- собственный backlog;
- управление скоростью обработки;
- повторы;
- DLQ;
- ограничение concurrency;
- защиту от временной недоступности Lambda.

## 2. Результаты урока

После урока ты сможешь:

- объяснить разницу между очередью и pub/sub fan-out;
- различать тему SNS, подписку и endpoint;
- направлять события с помощью filter policy подписки;
- объяснить области фильтрации `MessageAttributes` и `MessageBody`;
- объяснить, что меняет raw message delivery;
- разрешить SNS отправку в SQS через resource policy и `aws:SourceArn`;
- доказать, что отказ одной ветки не отменяет другую;
- независимо обрабатывать частичные ошибки стандартной SQS-очереди;
- учитывать eventual consistency фильтров SNS;
- выбирать между прямым SNS-to-Lambda и SNS-to-SQS-to-Lambda.

Карта доказательств:

| Что доказываем | Чем подтверждается |
|---|---|
| Одна публикация расходится по веткам | Один `event_id` успешно завершён в журналах audit и billing |
| Фильтрация работает | `profile.updated` присутствует в audit и отсутствует в billing |
| Payload доставляется без обёртки | Lambda читает исходный JSON прямо из тела SQS |
| Вход в очередь ограничен | Queue policy разрешает ARN темы и запрещает других отправителей |
| Ветки отказывают независимо | Billing повторяет обработку, а audit завершает то же событие |
| Ограничения инфраструктуры соблюдены | Проходят восемь native-тестов Terraform |

### 2.1. Словарь RU ↔ EN

| Английский термин | Как используем по-русски | Точный смысл в этом уроке |
|---|---|---|
| `publisher` | производитель события | Процесс, вызывающий `sns:Publish` |
| `topic` | тема публикации | Ресурс SNS, который принимает и распределяет события |
| `subscription` | подписка | Правило доставки от темы к одному endpoint |
| `subscriber` | ветка-потребитель | Endpoint SQS, получающий подходящую копию события |
| `fan-out` | доставка один-ко-многим | Одна публикация копируется в несколько подписок |
| `filter policy` | политика фильтрации | JSON-правило, определяющее доставку в подписку |
| `filter policy scope` | область фильтрации | Атрибуты сообщения или JSON-тело сообщения |
| `raw message delivery` | доставка без SNS-обёртки | Исходное опубликованное тело становится телом SQS |
| `branch isolation` | изоляция веток | Audit и billing имеют разные очереди, повторы и DLQ |

## 3. Ментальная модель

### 3.1. SNS не заменяет SQS

SNS и SQS решают разные задачи:

| Сервис | Основная роль | Модель доставки |
|---|---|---|
| SNS | распределить одну публикацию подписчикам | отправляет в endpoints |
| SQS | хранить работу до готовности потребителя | потребитель опрашивает очередь |

Вместе они образуют надёжный fan-out:

```text
производитель -> маршрутизация SNS -> независимые буферы SQS -> Lambda
```

- SNS получает одну публикацию и определяет получателей.
- SQS сохраняет отдельную копию сообщения до обработки.
- Lambda забирает сообщения из SQS.

SNS — маршрутизатор, SQS — буфер.

Если Lambda временно недоступна, SNS не должен постоянно ждать её восстановления.
Сообщение уже хранится в SQS, а Lambda обработает его позже.

### 3.2. Fan-out создаёт копии, а не общую работу

Если событие подходит двум подпискам, SNS отправляет отдельную копию в каждый
endpoint. После этого очереди audit и billing владеют разными сообщениями SQS со
своими ID, счётчиками получения, тайм-аутами видимости и результатами DLQ.

- `event_id` — идентификатор бизнес-события. Он одинаковый во всех ветках.
- `messageId` — транспортный идентификатор конкретного сообщения SQS.
  Он будет разным, потому что очереди получили разные копии.

Для поиска одного события во всех ветках используем: `event_id`
Для возврата конкретной неуспешной записи в `batchItemFailures` используем: `messageId`

Распределённой транзакции между ветками нет:

```text
audit завершён + billing завершился ошибкой
```

Успешная обработка `audit` не удаляет сообщение из `billing`.
Ошибка `billing` не возвращает сообщение в `audit`.

Это допустимое промежуточное и даже итоговое эксплуатационное состояние.

### 3.3. Фильтр принадлежит подписке

У темы нет одного общего фильтра. Каждая подписка владеет своим правилом:

```text
audit subscription   -> без фильтра -> получает все события
billing subscription -> event_type входит в [order.created, order.refunded]
```

В лабораторной используется `FilterPolicyScope = MessageAttributes`.
Производитель обязан передать атрибут SNS `event_type`. Одноимённого поля в теле
недостаточно, чтобы пройти фильтр по атрибутам.

У разных потребителей разные интересы. Например:

```text
audit subscription
  → все события

billing subscription
  → order.created, order.refunded

notification subscription
  → order.shipped

analytics subscription
  → все order.* события
```

Для добавления нового потребителя не требуется менять существующие подписки или
producer. Создаётся новая подписка со своим endpoint и своим фильтром.

### 3.4. Raw delivery определяет контракт потребителя

Без raw delivery тело SQS содержит SNS notification envelope, внутри которого
поле `Message` хранит исходный payload. При включённой доставке без обёртки
исходный payload сразу становится телом SQS.

В лабораторной включён raw delivery, а обработчик проверяет совпадение
`event_type` в теле и транспортном атрибуте SNS. При такой доставке в SQS можно
передать не более десяти атрибутов SNS; здесь используется один.

### 3.5. Queue policy защищает границу маршрутизации

Подписка SNS сама по себе не разрешает теме вызывать `sqs:SendMessage`.
Resource policy каждой исходной очереди:

1. разрешает service principal `sns.amazonaws.com`;
2. требует совпадения `aws:SourceArn` с ARN темы урока;
3. явно запрещает `SendMessage` вне этой темы;
4. запрещает незащищённый транспорт.

```bash
sed -n '45,103p' lab_85/terraform/queues.tf
```

Явный запрет не позволяет IAM identity из того же аккаунта с широкими правами
SQS обойти фильтр SNS прямой записью в очередь.

### 3.6. Частичные ошибки стандартной очереди и FIFO отличаются

В уроке 84 обработчик FIFO останавливался после первой ошибки и возвращал
ошибочную запись вместе с необработанным хвостом. Очереди урока 85 стандартные,
поэтому записи независимы:

```text
запись 1 завершилась ошибкой -> вернуть запись 1
запись 2 успешна             -> продолжить и удалить запись 2
```

Оба сопоставления включают `ReportBatchItemFailures`.

### 3.7. Изменения фильтров применяются не мгновенно

Добавление или изменение filter policy SNS может полностью распространиться не
сразу, а в течение 15 минут. Результат сразу после `terraform apply` ещё не
доказывает ошибку политики.

Правильная проверка:

1. Проверить атрибуты подписки:

```bash
aws sns get-subscription-attributes \
  --subscription-arn "$BILLING_SUBSCRIPTION_ARN"
```

2. Убедиться, что FilterPolicy содержит нужное значение.
3. Подождать распространения настройки.
4. Опубликовать новое событие с новым event_id.

## 4. Архитектура лаборатории

```text
                               ┌─ audit subscription
                               │  без фильтра
                               ▼
Producer → SNS topic → audit SQS → audit Lambda
                               │
                               └──────────────→ audit DLQ
                                  после исчерпания попыток


                     ┌─ billing subscription
                     │  фильтр:
SNS topic ───────────┤  order.created
                     │  order.refunded
                     ▼
                billing SQS → billing Lambda
                     │
                     └──────────────→ billing DLQ
                        после исчерпания попыток
```

У обеих веток общие только:

- producer;
- SNS topic;
- формат бизнес-события;
- исходный файл кода Lambda.

После SNS ветки инфраструктурно независимы.

У `audit` и `billing` собственные:

- SNS subscription;
- source queue;
- queue policy;
- Lambda function;
- IAM execution role;
- event source mapping;
- ограничение одновременной обработки;
- CloudWatch log group;
- DLQ;
- CloudWatch alarms.

У каждой Lambda отдельная execution role:

```text
audit role   -> может читать только audit source queue
billing role -> может читать только billing source queue
```

Runtime-роли не должны:

- читать чужую очередь;
- читать DLQ;
- публиковать в SNS;
- управлять инфраструктурой.

Это ограничивает последствия ошибки или компрометации одной функции.

## 5. Разбор реализации

### Тема и подписки

`terraform/topic.tf` создаёт одну шифрованную стандартную тему и две raw SQS
subscriptions. Filter policy есть только у billing.

### Очереди и resource policies

`terraform/queues.tf` создаёт две исходные очереди, две DLQ, redrive allow
policies и queue policies, ограниченные ARN темы.

### Функции и runtime-роли

`package.tf`, `functions.tf`, `function_execution_roles.tf`, `event_source_mappings.tf`

Один пакет кода развёртывается как две функции. Переменная `CONSUMER_NAME`
выбирает поведение ветки, а отдельные роли сохраняют least privilege.

Общий код:

- две отдельные Lambda
- две отдельные IAM-роли
- две отдельные очереди и mappings
- независимое выполнение веток

### Контракт потребителя

Один обработчик используется ветками `audit` и `billing`.

`app/lambda_function.py` проверяет:

- SQS `messageId`;
- JSON-тело;
- `event_id`, `event_type`, `order_id` и неотрицательный `amount`;
- атрибут сообщения SNS `event_type`;
- совпадение типа события в теле и атрибуте.

`fail_consumer` существует только для лабораторной. Значение `billing` ломает
только эту ветку для выбранного события.

### Контракт производителя

`scripts/publish-event.sh`

1. Принимает параметры события: `event_id`, `event_type`, `order_id`, `amount` и `fail_consumer`.
2. Проверяет корректность значений до публикации.
3. Через `jq` создаёт JSON-тело события.
4. Отдельно создаёт SNS-атрибут `event_type`.
5. Публикует тело и атрибут одной командой `aws sns publish`.
6. Сохраняет запрос и ответ AWS в evidence-файл.

Главная идея: тело и SNS-атрибут создаются из одной переменной `event_type`.
Это уменьшает вероятность их случайного несовпадения.

## 6. Локальные проверки

Из корня репозитория:

```bash
python3 -m unittest discover \
  -s lessons/85-lambda-sns-sqs-fanout-and-filtering/lab_85/tests -v

bash -n lessons/85-lambda-sns-sqs-fanout-and-filtering/lab_85/scripts/publish-event.sh
shellcheck lessons/85-lambda-sns-sqs-fanout-and-filtering/lab_85/scripts/publish-event.sh
```

Ожидаемый результат: проходят восемь тестов Python, в скрипте нет ошибок shell.

Затем проверь инфраструктуру:

```bash
cd lessons/85-lambda-sns-sqs-fanout-and-filtering/lab_85/terraform
terraform init
terraform fmt -check -recursive
terraform validate
terraform test
```

Ожидаемый результат: проходят восемь тестов Terraform.

## 7. Развёртывание Terraform

```bash
cp terraform.tfvars.example terraform.tfvars
export AWS_PROFILE=YOUR_PROFILE
aws sso login --profile "$AWS_PROFILE"
aws sts get-caller-identity

terraform plan -out=tfplan
terraform show -no-color tfplan | less
terraform apply tfplan
```

Экспортируй значения лабораторной:

```bash
export AWS_REGION="$(terraform output -raw aws_region)"
export TOPIC_ARN="$(terraform output -raw topic_arn)"
export AUDIT_FUNCTION="$(terraform output -json function_names | jq -r '.audit')"
export BILLING_FUNCTION="$(terraform output -json function_names | jq -r '.billing')"
export AUDIT_QUEUE_URL="$(terraform output -json source_queue_urls | jq -r '.audit')"
export BILLING_QUEUE_URL="$(terraform output -json source_queue_urls | jq -r '.billing')"
export AUDIT_DLQ_URL="$(terraform output -json dead_letter_queue_urls | jq -r '.audit')"
export BILLING_DLQ_URL="$(terraform output -json dead_letter_queue_urls | jq -r '.billing')"
export AUDIT_SUBSCRIPTION_ARN="$(terraform output -json subscription_arns | jq -r '.audit')"
export BILLING_SUBSCRIPTION_ARN="$(terraform output -json subscription_arns | jq -r '.billing')"
```

## 8. Проверка инфраструктурного контракта

Посмотри атрибуты подписки:

```bash
aws sns get-subscription-attributes \
  --region "$AWS_REGION" \
  --subscription-arn "$BILLING_SUBSCRIPTION_ARN" \
  --query 'Attributes.{Raw:RawMessageDelivery,Scope:FilterPolicyScope,Filter:FilterPolicy}' \
  --output table
```

Ожидаются `Raw=true`, `Scope=MessageAttributes` и два типа billing-событий в
`Filter`.

Это доказывает:

- SNS доставляет исходное тело без envelope;
- фильтрация выполняется по SNS message attributes;
- `billing` принимает только два настроенных типа событий.

Посмотри policy одной очереди:

```bash
aws sqs get-queue-attributes \
  --region "$AWS_REGION" \
  --queue-url "$BILLING_QUEUE_URL" \
  --attribute-names Policy \
  --query 'Attributes.Policy' --output text | jq '.'
```

Убедись, что разрешающая и запрещающая записи ссылаются только на `$TOPIC_ARN`.

```text
billing subscription
├── raw delivery включена
├── filter scope настроен правильно
└── разрешены нужные типы событий

billing SQS
├── принимает сообщения от темы урока
├── блокирует обход темы
└── запрещает небезопасный транспорт
```

## 9. Упражнения

### Упражнение 1. Проверь fan-out

Цель: один раз опубликовать `order.created` и найти один бизнес-`event_id` в обеих Lambda.

```bash
export RUN_ID="$(date -u +%Y%m%dT%H%M%S)"
export EVENT_ID="order-created-${RUN_ID}"

../scripts/publish-event.sh \
  "$TOPIC_ARN" "$AWS_REGION" \
  "$EVENT_ID" order.created order-100 42.50 - \
  ../evidence/order-created.json
```

Аргументы означают:

```text
TOPIC_ARN       → тема лабораторной
AWS_REGION      → регион темы
EVENT_ID        → уникальный ID события
order.created   → тип события
order-100       → ID заказа
42.50           → сумма
-               → не вызывать намеренную ошибку
output file     → сохранить доказательство публикации
```

После доставки найди событие в обоих журналах:

```bash
sleep 10
aws logs tail "/aws/lambda/${AUDIT_FUNCTION}" --region "$AWS_REGION" --since 10m | grep "$EVENT_ID"
aws logs tail "/aws/lambda/${BILLING_FUNCTION}" --region "$AWS_REGION" --since 10m | grep "$EVENT_ID"
```

В обеих записях одинаковый бизнес-`event_id`, но SQS `message_id` различается.
Это подтверждает, что fan-out создал две независимые транспортные копии.

- `event_id` одинаковый: обе ветки обрабатывают одно бизнес-событие.
- `message_id` разный: SNS создал отдельную копию для каждой очереди.
- `request_id` разный: `audit` Lambda и `billing` Lambda запускались независимо.

При повторной попытке SQS `message_id` останется прежним, а Lambda `request_id` изменится,
потому что это будет новый invocation.

Что доказал результат:

```text
Одна sns:Publish
├── audit subscription   → audit SQS   → audit Lambda
└── billing subscription → billing SQS → billing Lambda
```

### Упражнение 2. Проверь фильтрацию подписки

Опубликуй событие, которое не подходит фильтру billing.

`Audit` должен его получить, а `billing` — нет, поскольку `billing` разрешает только:

```text
order.created
order.refunded
```

```bash
export EVENT_ID="profile-updated-${RUN_ID}"

../scripts/publish-event.sh \
  "$TOPIC_ARN" "$AWS_REGION" \
  "$EVENT_ID" profile.updated order-100 0 - \
  ../evidence/profile-updated.json
```

После появления журналов:

```bash
sleep 10
aws logs tail "/aws/lambda/${AUDIT_FUNCTION}" --region "$AWS_REGION" --since 10m | grep "$EVENT_ID"
aws logs tail "/aws/lambda/${BILLING_FUNCTION}" --region "$AWS_REGION" --since 10m | grep "$EVENT_ID" || true
```

В audit событие должно быть, в billing — нет.d
`|| true` нужен потому, что `grep` возвращает код `1`, когда строка не найдена.
В данном упражнении отсутствие строки является ожидаемым результатом.

Получившаяся схема:

```text
profile.updated
├── audit subscription   → audit Lambda
└── billing subscription → отфильтровано SNS
```

### Упражнение 3. Проверь изоляцию отказа ветки

Опубликуй подходящее событие, которое ломает только billing:

```bash
export EVENT_ID="billing-failure-${RUN_ID}"

../scripts/publish-event.sh \
  "$TOPIC_ARN" "$AWS_REGION" \
  "$EVENT_ID" order.created order-500 99 billing \
  ../evidence/billing-failure.json
```

Значение которое попадёт в тело события:

```text
fail_consumer = billing
```

Посмотри журналы:

```bash
sleep 10
aws logs tail "/aws/lambda/${AUDIT_FUNCTION}" --region "$AWS_REGION" --since 10m | grep "$EVENT_ID"
aws logs tail "/aws/lambda/${BILLING_FUNCTION}" --region "$AWS_REGION" --since 10m | grep "$EVENT_ID"
```

Ожидаемое состояние:

```text
audit   -> fanout_event_completed
billing -> fanout_event_failed и повторы
```

При повторных попытках:

- `event_id` останется прежним;
- SQS `message_id` останется прежним;
- Lambda `request_id` будет новым для каждого invocation.

После исчерпания попыток копия billing попадёт в billing DLQ.
Ветка audit не должна получить или повторять запись из этой DLQ.

```bash
aws sqs get-queue-attributes \
  --region "$AWS_REGION" \
  --queue-url "$BILLING_DLQ_URL" \
  --attribute-names ApproximateNumberOfMessages \
  --query 'Attributes.ApproximateNumberOfMessages' \
  --output text
```

Итог:

```text
Одна публикация
├── audit copy   → успешно обработана
└── billing copy → повторы → billing DLQ
```

Это доказывает изоляцию веток: постоянная ошибка `billing` не отменяет успешную
обработку `audit` и не загрязняет `audit` DLQ.

## 10. Отрицательные упражнения

Здесь правильный результат — отказ команды. Мы намеренно передаём небезопасные
значения и проверяем защитные механизмы.

### Отклони пустой фильтр billing

```bash
terraform plan -var='billing_event_types=[]'
```

Пустой список запрещён, потому что `billing` перестал бы получать любые события.

### Отклони небезопасный тайм-аут видимости

```bash
terraform plan -var='queue_visibility_timeout_seconds=35'
```

Переданное значение `35` находится в допустимом диапазоне самой переменной, но нарушает
precondition очереди. Ошибка ожидается для обеих source queues.

### Докажи запрет прямой записи в очередь

```bash
aws sqs send-message \
  --region "$AWS_REGION" \
  --queue-url "$BILLING_QUEUE_URL" \
  --message-body '{"bypass":true}'
```

Даже identity с разрешением должна получить `AccessDenied`, потому что queue
policy явно запрещает отправку вне темы.

Это доказывает, что разрешён только штатный маршрут:

```text
Producer → SNS topic → SQS
```

## 11. Разбор типовых проблем

### Billing ничего не получает

Сначала проверяем не Lambda, а SNS subscription, потому что `billing` получает
сообщение только если SNS вообще пропустил его через фильтр. проверь ARN подписки,
регистр `event_type`, атрибуты публикации и задержку распространения фильтра.

```bash
aws sns get-subscription-attributes \
  --region "$AWS_REGION" \
  --subscription-arn "$BILLING_SUBSCRIPTION_ARN" \
  --output json
```

### Lambda получает SNS envelope вместо бизнес-события

Проверь `RawMessageDelivery`. Без raw delivery нужно декодировать поле `Message`
из SNS envelope, а не считать тело SQS готовым бизнес-событием.

```bash
aws sns get-subscription-attributes \
  --region "$AWS_REGION" \
  --subscription-arn "$BILLING_SUBSCRIPTION_ARN" \
  --query 'Attributes.RawMessageDelivery' \
  --output text
```

### SNS не может доставить сообщение в SQS

Проверь `NumberOfNotificationsFailed` и `queue resource policy` очереди. Разрешение
должно содержать service principal SNS и точный ARN темы.

Модель:

```text
SNS subscription существует
|
SNS пытается отправить в SQS
|
SQS queue policy должна это разрешить
```

В лаборатории разрешение:

```text
Principal = sns.amazonaws.com
Action    = sqs:SendMessage
Condition:
  aws:SourceArn = ARN именно нашей SNS topic
```

```bash
aws sqs get-queue-attributes \
  --region "$AWS_REGION" \
  --queue-url "$BILLING_QUEUE_URL" \
  --attribute-names Policy \
  --query 'Attributes.Policy' \
  --output text | jq '.'
```

### Кажется, что отказ одной ветки повлиял на другую

Сопоставляй записи по бизнес-`event_id`, а не по ID сообщения SQS. Проверь, что
mapping, роль, очередь и DLQ относятся к ожидаемой ветке.

### Отфильтрованное событие появилось сразу после изменения policy

Изменения фильтра применяются не мгновенно. Подожди до 15 минут и опубликуй новое
уникальное событие; старая строка журнала не подходит как доказательство.

Сначала убедиться, что AWS уже показывает нужную policy:

```bash
aws sns get-subscription-attributes \
  --region "$AWS_REGION" \
  --subscription-arn "$BILLING_SUBSCRIPTION_ARN" \
  --query 'Attributes.{Scope:FilterPolicyScope,Filter:FilterPolicy}' \
  --output table
```

И обязательно отправлять новое событие с новым `event_id`:

```text
old event_id
  - старый лог уже существует
  - плохое evidence

new event_id
  - можно однозначно проверить новую публикацию
```

## 12. Стоимость и эксплуатационные границы

Лабораторная создаёт одну тему SNS, четыре очереди SQS, две функции Lambda, две
роли, две группы журналов, два mapping и пять CloudWatch alarms. Запросы, шифрование,
журналы, время Lambda, метрики и alarms могут стоить денег.

Для `production` также нужны владелец схемы, версионирование событий, идемпотентность,
разрешение на replay, SLO каждой ветки и transactional outbox, если публикация должна
быть атомарной с изменением базы данных.

Что здесь потенциально стоит денег:

```text
SNS publishes/deliveries
SQS requests
Lambda execution time
CloudWatch logs
CloudWatch metrics/alarms
encryption-related operations
```

## 13. Проверка результата

- проходят 8 тестов Python;
- проходят 8 native-тестов Terraform;
- обе подписки используют raw delivery;
- audit не имеет фильтра, billing использует `MessageAttributes`;
- одно событие `order.created` завершается в обеих ветках;
- `profile.updated` завершается только в audit;
- ошибка billing не ломает audit;
- только копия billing попадает в billing DLQ;
- прямая публикация в очередь запрещена;

## 14. Очистка

```bash
terraform plan -destroy -out=tfplan-destroy
terraform show -no-color tfplan-destroy | less
terraform apply tfplan-destroy
```

Проверь состояние:

```bash
terraform state list
```

Команда не должна вывести ресурсы под управлением Terraform.

## 15. Итоговая модель

Запомни:

1. SNS распределяет, SQS хранит буфер.
2. Одна публикация может создать независимые копии в нескольких очередях.
3. Каждая подписка владеет своим фильтром и endpoint.
4. Raw delivery меняет контракт payload, но не работу фильтра.
5. Resource policy очереди разрешает границу topic-to-queue.
6. Ветка владеет своим лимитом повторов, мощностью, мониторингом и DLQ.
7. Успех ветки не означает транзакционный успех всех потребителей.
8. Частичный ответ стандартной очереди повторяет только ошибочные записи.
9. Изменения фильтра применяются с eventual consistency.
10. Бизнес-`event_id` связывает наблюдения между ветками.

## 16. Официальные источники

- [Что такое Amazon SNS](https://docs.aws.amazon.com/sns/latest/dg/welcome.html)
- [Подписка очереди SQS на тему SNS](https://docs.aws.amazon.com/sns/latest/dg/subscribe-sqs-queue-to-sns-topic.html)
- [Фильтрация сообщений Amazon SNS](https://docs.aws.amazon.com/sns/latest/dg/sns-message-filtering.html)
- [Применение filter policy SNS](https://docs.aws.amazon.com/sns/latest/dg/message-filtering-apply.html)
- [Атрибуты сообщений Amazon SNS](https://docs.aws.amazon.com/sns/latest/dg/sns-message-attributes.html)
- [Raw message delivery Amazon SNS](https://docs.aws.amazon.com/sns/latest/dg/sns-large-payload-raw-message-delivery.html)
- [Event-driven архитектура Lambda](https://docs.aws.amazon.com/lambda/latest/dg/concepts-event-driven-architectures.html)
