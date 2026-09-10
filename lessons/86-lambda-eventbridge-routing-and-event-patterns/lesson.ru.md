# Урок 86: Маршрутизация Lambda через EventBridge и шаблоны событий

## 1. Зачем нужен этот урок

В уроке 85 SNS копировал одну публикацию в независимые ветки обработки через SQS.
Подписка billing отбирала события по одному атрибуту сообщения SNS. Такая схема хорошо
подходит, когда отправитель знает нужную тему, а подписчикам нужен простой fan-out.

В этом уроке Amazon EventBridge выступает как уровень маршрутизации. Отправитель
передаёт структурированное событие в `шину событий`. Правила проверяют метаданные
и поля внутри `detail`, а затем независимо доставляют подходящие события своим целям.

Главное изменение не сводится к замене одного сервиса AWS другим:

```text
Урок с SNS:         публикация уведомления -> фильтры подписок
Урок с EventBridge: публикация события     -> правила маршрутизации по содержимому
```

Например, событие «создан заказ на 150» может заинтересовать:

- `audit` — потому что это событие заказа;
- обработчик крупных заказов — потому что сумма не меньше 100.

Правила принимают решения независимо. Один заказ может попасть в обе ветки.

Между EventBridge и Lambda намеренно остаётся SQS:

```text
отправитель -> правило EventBridge -> SQS -> Lambda
```

Очередь сохраняет накопление сообщений, ограничения параллелизма, повторы и изоляцию
отказов из уроков 82–85. Заодно становятся видны два разных уровня ошибок, которые
нельзя смешивать:

```text
EventBridge → SQS    ошибка доставки → delivery DLQ
SQS → Lambda        ошибка обработки → processing DLQ
```

Если EventBridge не имеет права записать сообщение в SQS, Lambda его вообще не увидит.

Если сообщение уже оказалось в SQS, но обработчик падает, это другая неисправность с
другой процедурой восстановления.

Для этих ошибок нужны разные DLQ, метрики, ответственные команды и процедуры
восстановления.

## 2. Результаты урока

После урока ты сможешь:

- объяснить, когда маршрутизация EventBridge уместнее fan-out через SNS;
- различать оболочку EventBridge и бизнес-данные внутри `detail`;
- писать и проверять точные и числовые шаблоны событий;
- определять, совпадёт ли событие с нулём, одним или несколькими правилами;
- публиковать пользовательские события и проверять ошибки отдельных записей `PutEvents`;
- разрешать EventBridge запись в SQS только от ожидаемого правила;
- отличать DLQ доставки к цели от DLQ обработки сообщений SQS;
- сохранять частичный ответ по пакету и ограничения параллелизма каждой ветки;
- разбирать ситуацию «событие принято, но никуда не попало»;
- восстанавливать управляемую Terraform политику очереди после контролируемого drift-упражнения.

Главный новый навык — определять, на каком этапе остановилось событие:

```text
PutEvents accepted
 - event pattern matched
 - EventBridge delivered to SQS
 - SQS stored message
 - Lambda processed message
 - business result correct
```

### 2.1. Словарь RU ↔ EN

| По-русски | English term | Значение в этом уроке |
|---|---|---|
| пользовательская шина событий | custom event bus | Именованная шина EventBridge, созданная для лаборатории |
| оболочка события | event envelope | Метаданные EventBridge и вложенные данные `detail` |
| источник события | `source` | Стабильный идентификатор отправителя или предметной области |
| тип события | `detail-type` | Понятная человеку категория события, которую проверяют правила |
| данные события | `detail` | Бизнес-данные JSON внутри оболочки |
| шаблон события | event pattern | Декларативные условия JSON, закреплённые за правилом |
| маршрутизация по содержимому | content-based routing | Выбор целей по значениям внутри события |
| цель | target | Ресурс, куда правило отправляет подходящее событие |
| DLQ доставки | delivery DLQ | Очередь для событий, которые EventBridge не смог доставить цели |
| DLQ обработки | processing DLQ | Очередь для сообщений, которые Lambda не смогла обработать после повторов |
| частичный ответ по пакету | partial batch response | Ответ Lambda только с идентификаторами неудачных сообщений SQS |

## 3. Ментальная модель

### 3.1. EventBridge и SNS решают похожие, но не одинаковые задачи

Оба сервиса могут разветвлять один входной поток на несколько получателей, но
их основные модели различаются:

```text
SNS:         topic → subscription с фильтром → получатель
EventBridge: bus   → rule с event pattern    → target
```

| Вопрос | SNS | EventBridge |
|---|---|---|
| Куда публикует отправитель | тема | шина событий |
| Единица маршрутизации | подписка | правило и его цель |
| Типичный контракт | сообщение и атрибуты | стандартная оболочка и `detail` |
| Фильтрация | политика фильтра подписки | шаблон события |
| Условия по содержимому | полезные, но более узкие | точные, числовые, prefix, exists и другие операторы |
| Частое применение | уведомления и pub/sub fan-out | маршрутизация событий приложений и сервисов AWS |

В SNS мы создавали подписку очереди на тему. В EventBridge создаём правило на шине и
отдельно назначаем ему цель. У одного правила может быть несколько целей.

Из таблицы не следует, что EventBridge всегда лучше. Выбор зависит от гарантий доставки,
интеграций, владельца контракта, нагрузки, стоимости и требований к эксплуатации,
а не от популярности сервиса.

EventBridge работает с общей оболочкой события. Правило может одновременно проверять:

- кто отправил событие — `source`;
- что произошло — `detail-type`;
- бизнес-условия — поля внутри `detail`.

Например: «событие от сервиса заказов, тип — создание заказа, сумма не меньше 100».

### 3.2. Оболочка входит в контракт события

Пользовательское событие, доставленное в SQS, выглядит примерно так:

```json
{
  "version": "0",
  "id": "generated-by-eventbridge",
  "detail-type": "Order Created",
  "source": "com.devops.orders",
  "account": "123456789012",
  "time": "2026-09-06T12:00:00Z",
  "region": "eu-west-1",
  "resources": [],
  "detail": {
    "event_id": "event-001",
    "order_id": "order-001",
    "amount": 150,
    "fail_consumer": null
  }
}
```

Верхнеуровневый `id` идентифицирует событие EventBridge. Поле `detail.event_id`
в лаборатории задаёт отправитель как бизнес-идентификатор. У них разные задачи.

При повторной публикации того же бизнес-события EventBridge может выдать новый `id`,
а отправитель сохранит прежний `detail.event_id`. Поэтому для связи бизнес-наблюдений
используем именно `detail.event_id`.

Для маршрутизации нас прежде всего интересуют три поля:

- `source` — источник события. `com.devops.orders` — согласованная строка, а не адрес для сетевого подключения.
- `detail-type` — категория: здесь `Order Created`.
- `detail` — бизнес-данные. Сумма находится по пути `detail.amount`, а не на верхнем уровне.

Обработчик извлекает их так:

```python
envelope = json.loads(record["body"])

source = envelope["source"]
event_type = envelope["detail-type"]
business_event = envelope["detail"]
amount = business_event["amount"]
```

Оболочка описывает происхождение и категорию события, `detail` содержит его бизнес-смысл.
Правила могут проверять обе части.

### 3.3. Шаблон указывает только обязательные совпадения

Правило audit использует:

```json
{
  "source": ["com.devops.orders"],
  "detail-type": ["Order Created", "Order Refunded"]
}
```

Поля, которых нет в шаблоне, не ограничивают совпадение. Например, это правило
не проверяет `detail.amount`.

Правило крупных заказов добавляет вложенное числовое условие:

```json
{
  "source": ["com.devops.orders"],
  "detail-type": ["Order Created"],
  "detail": {
    "amount": [
      {
        "numeric": [">=", 100]
      }
    ]
  }
}
```

`150` — число JSON. `"150"` — строка, которая не удовлетворяет числовому
условию. В контракт входят не только имена полей, но и их типы.

### 3.4. Правила проверяются независимо

EventBridge не выбирает первое подошедшее правило. Каждое правило независимо
проверяет одно и то же событие, при source = com.devops.orders:

| Событие | Правило audit | Правило крупных заказов |
|---|---:|---:|
| Order Created на `150` | совпадение | совпадение |
| Order Created на `25` | совпадение | нет |
| Order Refunded на `150` | совпадение | нет |
| Order Created с неверным `source` | нет | нет |

Поэтому одно событие может дать ноль, одно или несколько совпавших правил;
доставка их целям проверяется отдельно. Если оно не совпало ни с одним правилом,
EventBridge не обязан считать это ошибкой.

Здесь важно разделять:

```text
PutEvents accepted → событие принято
event pattern matched → конкретное правило совпало
```

### 3.5. Ошибка доставки и ошибка обработки — разные вещи

Полная ветка выглядит так:

```text
правило EventBridge
  -> исходная очередь SQS
     -> Lambda
```

DLQ доставки относится к первой стрелке:

```text
EventBridge --не может отправить--> исходная очередь SQS
            -> DLQ delivery
```

DLQ обработки используется после того, как SQS уже принял сообщение:

```text
исходная очередь SQS -> повторяющиеся ошибки Lambda
                     -> DLQ processing
```

Сообщение в DLQ доставки не дошло до исходной очереди. Сообщение в DLQ обработки
дошло до неё и исчерпало `maxReceiveCount`. Одна общая очередь для этих ошибок
стёрла бы важный диагностический контекст.

`Delivery DLQ` относится к доставке EventBridge в целевую очередь.

Например, правило совпало, но queue policy не разрешает сервису events.amazonaws.com
выполнить `sqs:SendMessage`. Сообщение не попало в source SQS, поэтому Lambda его не получала.
При корректной настройке `delivery DLQ` EventBridge может сохранить там недоставленное
событие и сведения об ошибке.

`Processing DLQ` относится к обработке уже принятого SQS сообщения.

Например, сообщение доставлено, но Lambda каждый раз вызывает учебную ошибку.
После повторных получений SQS перемещает сообщение в `processing DLQ` согласно `redrive_policy`.

Процедуры восстановления тоже отличаются:

- Для delivery failure сначала исправляем доставку: права очереди, настройки цели.
Изменение кода Lambda здесь не поможет.
- Для processing failure исправляем обработчик или данные, затем решаем, как повторно
обработать сообщение.

Cмотрим на доказательства конкретного этапа: совпадение правила, доставку, записи обработки.

### 3.6. Для успеха `PutEvents` недостаточно кода возврата 0

`PutEvents` обрабатывает записи независимо. API может вернуть успешный HTTP-код,
хотя отдельная запись содержит `ErrorCode` и `ErrorMessage`. Корректный
отправитель проверяет `FailedEntryCount`, а не только код возврата AWS CLI.

Пример ответа:

```json
{
  "FailedEntryCount": 1,
  "Entries": [
    {
      "EventId": "accepted-event-id"
    },
    {
      "ErrorCode": "InternalFailure",
      "ErrorMessage": "Internal Service Failure"
    }
  ]
}
```

Есть и менее очевидная ловушка: отправка на несуществующую пользовательскую шину
может завершиться успешно, но событие не получит ни одно правило. Скрипт лаборатории
сначала вызывает `describe-event-bus`, а после `put-events` проверяет `FailedEntryCount`.

Даже эти проверки доказывают только приём события. Они не доказывают:

- что подошло хотя бы одно правило;
- что EventBridge доставил событие в SQS;
- что Lambda обработала сообщение;
- что бизнес-операция завершилась правильно.

### 3.7. Частичные ошибки стандартной SQS никуда не исчезают

Обе ветки используют стандартные очереди. Обработчик продолжает работу после ошибки
одной записи и возвращает только неудачные `messageId` в `batchItemFailures`.

В уроке 84 для FIFO действовал барьер: после первой ошибки обработчик прекращал работу,
чтобы сохранить порядок внутри группы. EventBridge меняет маршрутизацию до очереди, но
не обработку batch после очереди.

Здесь нужен именно SQS `messageId`. Ни EventBridge `id`, ни бизнес-поле `detail.event_id`
для `itemIdentifier` не подходят.

При включённом `ReportBatchItemFailures` успешно обработанные записи удаляются, а
ошибочная остаётся для повтора. Если обработчик выбросит исключение на весь вызов,
частичного ответа не будет и весь batch считается неуспешным.

Эти повторы относятся к уровню Lambda processed message и при исчерпании попыток ведут
в `processing DLQ`. EventBridge `delivery DLQ` в них не участвует.

## 4. Архитектура лаборатории

```text
put-event.sh
    │
    ▼
Custom event bus
    │
    ├── audit rule
    │   source = com.devops.orders
    │   detail-type = Order Created ИЛИ Order Refunded
    │       │
    │       ├── доставка успешна -> source SQS audit -> Lambda audit
    │       │                          │
    │       │                          └── SQS redrive -> processing DLQ audit
    │       │
    │       └── ошибка доставки -> delivery DLQ audit
    │
    └── high-value rule
        source = com.devops.orders
        detail-type = Order Created
        detail.amount >= 100
            │
            ├── доставка успешна -> source SQS high-value -> Lambda high-value
            │                          │
            │                          └── SQS redrive -> processing DLQ high-value
            │
            └── ошибка доставки -> delivery DLQ high-value
```

Условия правил:

- `Audit`: `source = com.devops.orders`, тип — `Order Created` или `Order Refunded`.
- `High-value`: тот же источник, только `Order Created` и числовая сумма `detail.amount >= 100`.

У каждой ветки свои:

- правило и цель EventBridge;
- исходная очередь и строгая политика доступа;
- DLQ доставки к цели;
- функция Lambda, группа логов и роль выполнения;
- привязка источника событий и предел параллелизма;
- DLQ обработки SQS;
- alarms для очереди, ошибок доставки и обеих DLQ.

## 5. Разбор реализации

### Шина, правила и цели

В `eventbridge.tf` три вида ресурсов отвечают за три разные задачи.

#### Шина — куда публикуем:

```hcl
resource "aws_cloudwatch_event_bus" "orders" {
  name = local.event_bus_name
}
```

#### Правило — какие события подходят:

```hcl
resource "aws_cloudwatch_event_rule" "route" {
  for_each = local.event_patterns

  name           = local.rule_names[each.key]
  event_bus_name = aws_cloudwatch_event_bus.orders.name
  event_pattern  = each.value
}
```

`local.event_patterns` содержит два ключа: `audit` и `high_value`.
Их значения —JSON-шаблоны, сформированные через `jsonencode` в `locals.tf`.

####Цель — куда доставлять совпавшее событие:

```hcl
event_bus_name = aws_cloudwatch_event_bus.orders.name
rule           = aws_cloudwatch_event_rule.route[each.key].name
arn            = aws_sqs_queue.source[each.key].arn
```

Одинаковый `each.key` связывает правило и очередь одной ветки. `target_id` идентифицирует
цель внутри правила, а `arn` задаёт настоящий адрес получателя.

У каждой цели настроены:

```hcl
retry_policy {
  maximum_event_age_in_seconds = var.target_maximum_event_age_seconds
  maximum_retry_attempts       = var.target_maximum_retry_attempts
}

dead_letter_config {
  arn = aws_sqs_queue.delivery_dead_letter[each.key].arn
}
```

`depends_on` требует сначала создать policies исходных очередей и delivery DLQ, затем
зарегистрировать цели. Авторизацию этих очередей разберём следующим блоком.

В лаборатории два отдельных механизма повторов:

1. EventBridge не смог записать событие в SQS

Работает `retry_policy` цели:

```text
EventBridge → SQS
            → ошибка доставки
```

Настроено до 10 повторных попыток, возраст события ограничен 3600 секундами. После
прекращения доставки событие направляется в delivery DLQ, если её настройки позволяют это.

2. SQS уже получил сообщение, но Lambda не справляется

Работает `maxReceiveCount` исходной очереди:

```text
SQS → Lambda
    → ошибка обработки
```

Этот параметр ограничивает количество получений сообщения перед переносом в processing DLQ.
Поэтому увеличение EventBridge `maximum_retry_attempts` не даст Lambda дополнительных попыток.
А увеличение SQS `maxReceiveCount` не поможет EventBridge доставить сообщение в очередь.

### Авторизация очередей

`terraform/queues.tf` разрешает `sqs:SendMessage`, только когда `aws:SourceArn`
равен ARN соответствующего правила EventBridge. Явный запрет не позволяет
отправить сообщение прямо в очередь в обход маршрутизации.

Не путать два разных `source`:

```text
source в событии -> com.devops.orders -> проверяется event pattern
aws:SourceArn    -> ARN правила       -> проверяется queue policy
```

`source` — данные, указанные отправителем.
`aws:SourceArn` — контекст AWS-запроса к очереди. Поле события не заменяет проверку прав.

Дополнительный `DenySendOutsideExpectedRule` блокирует прямой `SendMessage` и
отправку через другое правило. `DenyInsecureTransport` запрещает незащищённый транспорт.

Каждая исходная очередь переносит неудачные сообщения только в свою DLQ обработки.
Каждая цель EventBridge указывает на отдельную DLQ доставки. Их назначение видно уже
из имён ресурсов.

Для `delivery DLQ` нужна отдельная `policy`. В коде она тоже разрешает `EventBridge`
отправку только от соответствующего правила. Разрешение писать в source SQS
автоматически не даёт права писать в `delivery DLQ`.

`Processing DLQ` использует другой механизм: `redrive_allow_policy` с `byQueue` ограничивает
перенос сообщений конкретной source SQS. Разрешение `EventBridge` ей не требуется.

### Обработчики Lambda

Обе функции используют `app/lambda_function.py`, а переменная `CONSUMER_NAME` выбирает
ветку. Вторая переменная, `EXPECTED_EVENT_SOURCE`, позволяет повторно проверить
отправителя уже внутри обработчика.

Различаются переменные окружения:

```text
CONSUMER_NAME         → audit или high_value
EXPECTED_EVENT_SOURCE → com.devops.orders
```

Новая часть обработки — проверка EventBridge envelope внутри SQS body.

`parse_record()` проверяет:

- непустой EventBridge `id`;
- совпадение `source` с `EXPECTED_EVENT_SOURCE`;
- `detail-type`: `Order Created` или `Order Refunded`;
- объект `detail` с непустыми `event_id`, `order_id`;
- числовой неотрицательный `amount`;
- `fail_consumer`: `null`, `audit` или `high_value`.

Правило маршрутизации не заменяет проверку контракта. Например, `audit` pattern не
проверяет сумму, но Lambda отклонит `"amount": "150"`, поскольку это строка.

При этом обработчик не проверяет порог крупных заказов повторно. Решение `amount >= 100`
принадлежит EventBridge rule; общий код Lambda принимает любую допустимую неотрицательную сумму.

`process_event()` либо вызывает учебную ошибку для выбранной ветки, либо формирует результат:

```python
{
    "event_id": event["event_id"],
    "event_type": event["event_type"],
    "consumer_name": consumer_name,
    "result_id": "...",
    "status": "completed",
}
```

Функция сначала проверяет транспортный идентификатор, затем разбирает оболочку
EventBridge из тела сообщения SQS, проверяет `detail`, пишет структурированные
логи и возвращает частичный ответ для стандартной очереди.

### Скрипт публикации

`put-event.sh` превращает параметры командной строки в один запрос `PutEvents`.

**Формат запроса отличается от события, которое получит Lambda**:

| В запросе `PutEvents` | В доставленном событии |
|---|---|
| `Source` | `source` |
| `DetailType` | `detail-type` |
| `Detail` — строка с JSON | `detail` — JSON-объект |
| `EventBusName` | выбирает шину, не становится одноимённым полем |

Скрипт преобразует короткий ввод:

```text
order.created  → Order Created
order.refunded → Order Refunded
```

Бизнес-данные собираются через `jq`. Для суммы используется:

```bash
--argjson amount "$amount"
```

Поэтому `150` попадает в `detail` числом, а не строкой `"150"`.

Затем весь объект `detail` кодируется в строку для API:

```jq
Detail: ($detail[0] | tojson)
```

Это не превращает внутреннюю сумму в строку: сериализуется весь объект.
При доставке EventBridge `detail` снова будет объектом с числовым `amount`.

Последовательность работы скрипта:

1. Проверяет аргументы.
2. Через `describe-event-bus` проверяет существование шины.
3. Собирает запрос и вызывает `put-events`.
4. Сохраняет данные публикации и ответ AWS в evidence-файл.
5. Проверяет `FailedEntryCount`; при ненулевом значении завершается с ошибкой.

Evidence сохраняется **до проверки ошибок отдельных записей**, поэтому
отклонённую публикацию можно исследовать.

Успешный запуск подтверждает только **PutEvents accepted**. Совпадение правил
и дальнейшую обработку проверяем отдельно. Пока скрипт не запускаем.

## 6. Локальные проверки

Из корня репозитория:

```bash
python3 -m unittest discover \
  -s lessons/86-lambda-eventbridge-routing-and-event-patterns/lab_86/tests -v

bash -n \
  lessons/86-lambda-eventbridge-routing-and-event-patterns/lab_86/scripts/put-event.sh

shellcheck \
  lessons/86-lambda-eventbridge-routing-and-event-patterns/lab_86/scripts/put-event.sh

find lessons/86-lambda-eventbridge-routing-and-event-patterns/lab_86 \
  -type f -name '*.json' -print0 | xargs -0 -n1 jq empty
```

Ожидаемый результат Python:

```text
Ran 9 tests
OK
```

Затем проверь инфраструктурный контракт:

```bash
cd lessons/86-lambda-eventbridge-routing-and-event-patterns/lab_86/terraform
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform fmt -check -recursive
terraform validate
terraform test
```

Ожидаемый результат native-тестов:

```text
Success! 12 passed, 0 failed.
```

## 7. Развёртывание Terraform

Явно выполни вход:

```bash
export AWS_PROFILE=YOUR_PROFILE
export AWS_REGION=eu-west-1

aws sso login --profile "$AWS_PROFILE"
aws sts get-caller-identity
```

Перед применением просмотри сохранённый план:

```bash
terraform plan -out=tfplan
terraform show -no-color tfplan | less
terraform apply tfplan
```

Экспортируй идентификаторы ресурсов:

```bash
export EVENT_BUS_NAME="$(terraform output -raw event_bus_name)"
export EVENT_SOURCE="$(terraform output -raw event_source)"

export AUDIT_RULE="$(terraform output -json rule_names | jq -r '.audit')"
export HIGH_VALUE_RULE="$(terraform output -json rule_names | jq -r '.high_value')"

export AUDIT_FUNCTION="$(terraform output -json function_names | jq -r '.audit')"
export HIGH_VALUE_FUNCTION="$(terraform output -json function_names | jq -r '.high_value')"

export AUDIT_SOURCE_QUEUE_URL="$(terraform output -json source_queue_urls | jq -r '.audit')"
export HIGH_VALUE_SOURCE_QUEUE_URL="$(terraform output -json source_queue_urls | jq -r '.high_value')"

export AUDIT_PROCESSING_DLQ_URL="$(terraform output -json processing_dead_letter_queue_urls | jq -r '.audit')"
export HIGH_VALUE_PROCESSING_DLQ_URL="$(terraform output -json processing_dead_letter_queue_urls | jq -r '.high_value')"

export AUDIT_DELIVERY_DLQ_URL="$(terraform output -json delivery_dead_letter_queue_urls | jq -r '.audit')"
export HIGH_VALUE_DELIVERY_DLQ_URL="$(terraform output -json delivery_dead_letter_queue_urls | jq -r '.high_value')"
```

## 8. Проверка инфраструктурного контракта

Посмотри пользовательскую шину и правила:

```bash
aws events describe-event-bus \
  --name "$EVENT_BUS_NAME" \
  --region "$AWS_REGION"

aws events list-rules \
  --event-bus-name "$EVENT_BUS_NAME" \
  --region "$AWS_REGION" \
  --query 'Rules[].{Name:Name,State:State,Pattern:EventPattern}'
```

Ожидается объект с полями `Name` и `Arn`. `Name` должен совпадать с `$EVENT_BUS_NAME`.

Ожидаются два правила:

- `audit` в состоянии `ENABLED`, с `source = com.devops.orders` и двумя `detail-type`;
- `high-value` в состоянии `ENABLED`, дополнительно с `detail.amount >= 100`.

Вывод доказывает:

- custom bus `lab86-dev-orders-bus` существует в `eu-west-1`;
- оба правила включены;
- `audit` принимает `Order Created` и `Order Refunded`;
- `high-value` принимает только `Order Created` с числовым `detail.amount >= 100`.

Проверь настройки повторов и DLQ каждой цели:

```bash
for RULE_NAME in "$AUDIT_RULE" "$HIGH_VALUE_RULE"; do
  printf '\nRule: %s\n' "$RULE_NAME"

  aws events list-targets-by-rule \
    --event-bus-name "$EVENT_BUS_NAME" \
    --rule "$RULE_NAME" \
    --region "$AWS_REGION" \
    --query 'Targets[].{Id:Id,Arn:Arn,Retry:RetryPolicy,DLQ:DeadLetterConfig}' \
    --output json
done
```

Для каждого правила ожидается одна цель:

- `Arn` — ARN соответствующей source SQS;
- `MaximumEventAgeInSeconds` — 3600;
- `MaximumRetryAttempts` — 10;
- `DeadLetterConfig.Arn` — ARN delivery DLQ той же ветки.

Посмотри политику переноса (`redrive policy`) и ресурсную политику исходной очереди:

```bash
aws sqs get-queue-attributes \
  --queue-url "$HIGH_VALUE_SOURCE_QUEUE_URL" \
  --region "$AWS_REGION" \
  --attribute-names QueueArn RedrivePolicy Policy \
  --output json |
jq '{
  QueueArn: .Attributes.QueueArn,
  RedrivePolicy: (.Attributes.RedrivePolicy | fromjson),
  Policy: (.Attributes.Policy | fromjson)
}'
```

Ожидается:

- `QueueArn` заканчивается на `lab86-dev-high-value-events`;
- `RedrivePolicy.deadLetterTargetArn` указывает на `...high-value-events-processing-dlq`;
- `maxReceiveCount` соответствует настройке Terraform;
- `AllowExpectedRuleToSend` разрешает `events.amazonaws.com`;
- его `aws:SourceArn` указывает на `lab86-dev-high-value-route`;
- присутствуют `DenySendOutsideExpectedRule` и `DenyInsecureTransport`.

Убедись, что URL двух типов DLQ различаются:

```bash
printf 'Processing DLQ: %s\nDelivery DLQ:   %s\n' \
  "$HIGH_VALUE_PROCESSING_DLQ_URL" \
  "$HIGH_VALUE_DELIVERY_DLQ_URL"

test "$HIGH_VALUE_PROCESSING_DLQ_URL" != "$HIGH_VALUE_DELIVERY_DLQ_URL"
printf 'exit_code=%s\n' "$?"
```

Ожидаемый код возврата: `exit_code=0`.

## 9. Проверка шаблонов до публикации

`test-event-pattern` отправляет шаблон и тестовое событие в AWS для проверки
совпадения, но не публикует событие в шину.

```bash
LAB_ROOT="$(cd .. && pwd)"

aws events test-event-pattern \
  --event-pattern "file://$LAB_ROOT/patterns/audit.json" \
  --event "file://$LAB_ROOT/events/order-created-high-value.json" \
  --region "$AWS_REGION"

aws events test-event-pattern \
  --event-pattern "file://$LAB_ROOT/patterns/high-value.json" \
  --event "file://$LAB_ROOT/events/order-created-high-value.json" \
  --region "$AWS_REGION"
```

Обе команды должны вернуть:

```json
{
  "Result": true
}
```

Причина:

- `audit` совпадает по `source` и `detail-type`;
- `high-value` дополнительно совпадает по числовому условию `amount >= 100`,
поскольку сумма равна `150`.

Теперь собери полную матрицу маршрутизации:

```bash
for event_file in \
  order-created-high-value.json \
  order-created-low-value.json \
  order-refunded.json \
  wrong-source.json; do

  printf '\n%s\n' "$event_file"

  for pattern in audit high-value; do
    result="$(aws events test-event-pattern \
      --event-pattern "file://$LAB_ROOT/patterns/$pattern.json" \
      --event "file://$LAB_ROOT/events/$event_file" \
      --region "$AWS_REGION" \
      --query Result \
      --output text)"

    printf '  %-10s %s\n' "$pattern" "$result"
  done
done
```

Ожидаемая матрица:

```text
order-created-high-value.json
  audit      True
  high-value True

order-created-low-value.json
  audit      True
  high-value False

order-refunded.json
  audit      True
  high-value False

wrong-source.json
  audit      False
  high-value False
```

Она проверяет:

- независимое совпадение двух rules;
- числовой порог;
- ограничение по `detail-type`;
- обязательное совпадение `source`;
- нормальный случай с нулём совпавших правил.

Такая проверка шаблона надёжнее, чем вывод о маршрутизации только по временному
отсутствию строки в логах.

## 10. Упражнения на маршрутизацию

Создай уникальные идентификаторы:

```bash
RUN_ID="$(date -u +%Y%m%dT%H%M%S)-$RANDOM"

mkdir -p ../evidence
```

### Упражнение 1. Одно событие подходит двум правилам

Опубликуйте крупный созданный заказ:

```bash
EVENT_ID="high-$RUN_ID"

../scripts/put-event.sh \
  "$EVENT_BUS_NAME" "$AWS_REGION" "$EVENT_SOURCE" \
  "$EVENT_ID" order.created "order-$RUN_ID" 150 - \
  "../evidence/$EVENT_ID.json"
```

Проверьте только результат приёма:

```bash
jq '{
  EventId: .detail.event_id,
  Amount: .detail.amount,
  FailedEntryCount: .put_events_response.FailedEntryCount,
  EventBridgeId: .put_events_response.Entries[0].EventId
}' "../evidence/$EVENT_ID.json"
```

Ожидается:

- `EventId` начинается с `high-`;
- `Amount` — число `150`;
- `FailedEntryCount` равен `0`;
- `EventBridgeId` содержит сгенерированный идентификатор.

Проверь обе функции:

```bash
aws logs tail "/aws/lambda/$AUDIT_FUNCTION" \
  --since 5m --region "$AWS_REGION" --format short | grep -F "$EVENT_ID"

aws logs tail "/aws/lambda/$HIGH_VALUE_FUNCTION" \
  --since 5m --region "$AWS_REGION" --format short | grep -F "$EVENT_ID"
```

После этого ищем событие локально:

```bash
rg -F "$EVENT_ID" \
  "../evidence/$EVENT_ID-audit.log" \
  "../evidence/$EVENT_ID-high-value.log"
```

Обе ветки должны записать `routed_event_completed` для одного бизнес-события.
Их SQS `messageId` и сформированные `result_id` могут отличаться.

Одинаковый `event_id` связывает одно бизнес-событие. Разные `message_id` доказывают
независимые SQS-копии; разные `request_id` — независимые вызовы Lambda; разные
`result_id` включают имя ветки.

### Упражнение 2. Небольшой заказ попадает только в audit

```bash
EVENT_ID="low-$RUN_ID"

../scripts/put-event.sh \
  "$EVENT_BUS_NAME" "$AWS_REGION" "$EVENT_SOURCE" \
  "$EVENT_ID" order.created "order-low-$RUN_ID" 25 - \
  "../evidence/$EVENT_ID.json"

sleep 15

aws logs tail "/aws/lambda/$AUDIT_FUNCTION" \
  --since 10m \
  --region "$AWS_REGION" \
  --format short \
  > "../evidence/$EVENT_ID-audit.log"

aws logs tail "/aws/lambda/$HIGH_VALUE_FUNCTION" \
  --since 10m \
  --region "$AWS_REGION" \
  --format short \
  > "../evidence/$EVENT_ID-high-value.log"
```

В audit событие должно быть, в ветке крупных заказов — нет.

Проверьте только результат приёма:

```bash
jq '{
  EventId: .detail.event_id,
  Amount: .detail.amount,
  FailedEntryCount: .put_events_response.FailedEntryCount,
  EventBridgeId: .put_events_response.Entries[0].EventId
}' "../evidence/$EVENT_ID.json"
```

Ожидается число `25`, `FailedEntryCount = 0` и непустой `EventBridgeId`.

Проверка `audit`:

```bash
rg -F "$EVENT_ID" "../evidence/$EVENT_ID-audit.log"
```

Ожидаются `routed_event_started` и `routed_event_completed`.

Проверка `high-value`:

```bash
if rg -F "$EVENT_ID" "../evidence/$EVENT_ID-high-value.log"; then
  echo "UNEXPECTED: событие найдено в high-value"
else
  echo "EXPECTED: событие отсутствует в high-value"
fi
```

### Упражнение 3. Тип события важнее подходящей суммы

```bash
EVENT_ID="refund-$RUN_ID"

../scripts/put-event.sh \
  "$EVENT_BUS_NAME" "$AWS_REGION" "$EVENT_SOURCE" \
  "$EVENT_ID" order.refunded "order-refund-$RUN_ID" 150 - \
  "../evidence/$EVENT_ID.json"
```

Проверяем:

```bash
jq '{
  EventId: .detail.event_id,
  Amount: .detail.amount,
  FailedEntryCount: .put_events_response.FailedEntryCount,
  EventBridgeId: .put_events_response.Entries[0].EventId
}' "../evidence/$EVENT_ID.json"
```

`amount=150` удовлетворяет числовому условию, но `Order Refunded` не подходит
полю `detail-type` правила крупных заказов. Совпасть должны все объявленные
поля, поэтому событие получает только audit.

Маршрутизацию проверяем по журналам:

```bash
aws logs tail "/aws/lambda/$AUDIT_FUNCTION" \
  --since 10m \
  --region "$AWS_REGION" \
  --format short \
  > "../evidence/$EVENT_ID-audit.log"

aws logs tail "/aws/lambda/$HIGH_VALUE_FUNCTION" \
  --since 10m \
  --region "$AWS_REGION" \
  --format short \
  > "../evidence/$EVENT_ID-high-value.log"
```

Audit:

```bash
rg -F "$EVENT_ID" "../evidence/$EVENT_ID-audit.log"
```

Ожидаются `routed_event_started` и `routed_event_completed`.


High-value:

```bash
if rg -F "$EVENT_ID" "../evidence/$EVENT_ID-high-value.log"; then
  echo "UNEXPECTED: refund найден в high-value"
else
  echo "EXPECTED: refund отсутствует в high-value"
fi
```

### Упражнение 4. Принято не значит маршрутизировано

```bash
EVENT_ID="wrong-source-$RUN_ID"

../scripts/put-event.sh \
  "$EVENT_BUS_NAME" "$AWS_REGION" com.example.wrong \
  "$EVENT_ID" order.created "order-wrong-$RUN_ID" 150 - \
  "../evidence/$EVENT_ID.json"
```

Для проверки сохрани журналы обеих функций и проверь оба файла.

Скрипт должен вывести корректный идентификатор события EventBridge, но ни одна
функция не запишет это бизнес-событие в лог. EventBridge его принял, однако ни
одно правило не совпало.

## 11. Упражнение на изоляцию ошибки обработки

Отправь событие, которое подходит обоим правилам, но ломает только `high_value`:

```bash
EVENT_ID="processing-failure-$RUN_ID"

../scripts/put-event.sh \
  "$EVENT_BUS_NAME" "$AWS_REGION" "$EVENT_SOURCE" \
  "$EVENT_ID" order.created "order-failure-$RUN_ID" 150 high_value \
  "../evidence/$EVENT_ID.json"
```

Маршрутизацию проверяем по журналам:

```bash
aws logs tail "/aws/lambda/$AUDIT_FUNCTION" \
  --since 10m \
  --region "$AWS_REGION" \
  --format short \
  > "../evidence/$EVENT_ID-audit.log"

aws logs tail "/aws/lambda/$HIGH_VALUE_FUNCTION" \
  --since 10m \
  --region "$AWS_REGION" \
  --format short \
  > "../evidence/$EVENT_ID-high-value.log"
```

Ветка `audit` завершится успешно. Ветка крупных заказов вернёт идентификатор
сообщения SQS в `batchItemFailures`. После исчерпания `maxReceiveCount` SQS
перенесёт сообщение в DLQ обработки `high-value`.

Покажите относящиеся к событию строки:

```bash
rg -F "$EVENT_ID" \
  "../evidence/$EVENT_ID-audit.log" \
  "../evidence/$EVENT_ID-high-value.log"
```

Вывод докажит изоляцию обработки:

- `audit` успешно завершил свою копию один раз;
- `high-value` трижды обработал одну и ту же SQS-копию;
- одинаковый `message_id` — это повторы одного сообщения;
- разные `request_id` — три отдельных вызова Lambda;
- интервалы около 40 секунд соответствуют visibility timeout;
- каждая попытка завершилась `PlannedConsumerError`.

Теперь проверяем processing DLQ:

```bash
aws sqs receive-message \
  --queue-url "$HIGH_VALUE_PROCESSING_DLQ_URL" \
  --region "$AWS_REGION" \
  --max-number-of-messages 1 \
  --visibility-timeout 30 \
  --wait-time-seconds 10 \
  --no-paginate \
  --attribute-names All \
  --output json >"../evidence/$EVENT_ID-processing-dlq.json"

jq --arg event_id "$EVENT_ID" '
  .Messages[]?
  | (.Body | fromjson) as $event
  | select($event.detail.event_id == $event_id)
  | {
      message_id: .MessageId,
      receive_count: .Attributes.ApproximateReceiveCount,
      source: $event.source,
      detail_type: $event["detail-type"],
      event_id: $event.detail.event_id
    }
' "../evidence/$EVENT_ID-processing-dlq.json"
```

В DLQ доставки этого события быть не должно. EventBridge успешно доставил его,
а ошибка произошла уже в обработчике.

## 12. Упражнение на ошибку доставки к цели

Выполняй это упражнение только в одноразовой dev-лаборатории. Оно временно заменяет
политику исходной очереди high-value на явный запрет для EventBridge, публикует
событие, а затем восстанавливает декларацию Terraform через просмотренный план.

Сначала сохрани текущую policy и извлеки ARN очереди:

```bash
aws sqs get-queue-attributes \
  --queue-url "$HIGH_VALUE_SOURCE_QUEUE_URL" \
  --region "$AWS_REGION" \
  --attribute-names QueueArn Policy \
  --output json >../evidence/high-value-queue-policy-before.json

HIGH_VALUE_SOURCE_QUEUE_ARN="$(
  jq -r '.Attributes.QueueArn' ../evidence/high-value-queue-policy-before.json
)"
```

Проверь baseline:

```bash
jq '{
  QueueArn: .Attributes.QueueArn,
  Statements: (
    .Attributes.Policy
    | fromjson
    | .Statement
    | map({
        Sid,
        Effect,
        Principal,
        Action,
        Condition
      })
  )
}' ../evidence/high-value-queue-policy-before.json
```

Создай и примени временную запрещающую политику:

```bash
jq -cn --arg queue_arn "$HIGH_VALUE_SOURCE_QUEUE_ARN" '
  {
    Policy: ({
      Version: "2012-10-17",
      Statement: [{
        Sid: "DenyEventBridgeDeliveryDrill",
        Effect: "Deny",
        Principal: {Service: "events.amazonaws.com"},
        Action: "sqs:SendMessage",
        Resource: $queue_arn
      }]
    } | tojson)
  }
' >../evidence/high-value-deny-attributes.json

aws sqs set-queue-attributes \
  --queue-url "$HIGH_VALUE_SOURCE_QUEUE_URL" \
  --region "$AWS_REGION" \
  --attributes file://../evidence/high-value-deny-attributes.json
```

Проверь фактическое состояние AWS:

```bash
aws sqs get-queue-attributes \
  --queue-url "$HIGH_VALUE_SOURCE_QUEUE_URL" \
  --region "$AWS_REGION" \
  --attribute-names Policy \
  --output json |
jq '.Attributes.Policy | fromjson'
```

Опубликуй крупный заказ:

```bash
EVENT_ID="delivery-failure-$RUN_ID"

../scripts/put-event.sh \
  "$EVENT_BUS_NAME" "$AWS_REGION" "$EVENT_SOURCE" \
  "$EVENT_ID" order.created "order-delivery-$RUN_ID" 150 - \
  "../evidence/$EVENT_ID.json"
```

Ошибка прав считается неповторяемой ошибкой доставки EventBridge и должна
попасть в настроенную DLQ цели. Дай изменениям немного времени и проверь очередь:

```bash
aws sqs receive-message \
  --queue-url "$HIGH_VALUE_DELIVERY_DLQ_URL" \
  --region "$AWS_REGION" \
  --max-number-of-messages 1 \
  --visibility-timeout 30 \
  --wait-time-seconds 10 \
  --attribute-names All \
  --message-attribute-names All \
  --no-paginate \
  --output json \
  > "../evidence/$EVENT_ID-delivery-dlq.json"

jq --arg event_id "$EVENT_ID" '
  .Messages[]?
  | (.Body | fromjson) as $event
  | select($event.detail.event_id == $event_id)
  | {
      message_id: .MessageId,
      error_code: .MessageAttributes.ERROR_CODE.StringValue,
      error_message: .MessageAttributes.ERROR_MESSAGE.StringValue,
      retry_attempts: .MessageAttributes.RETRY_ATTEMPTS.StringValue,
      exhausted_retry_condition:
        .MessageAttributes.EXHAUSTED_RETRY_CONDITION.StringValue,
      rule_arn: .MessageAttributes.RULE_ARN.StringValue,
      target_arn: .MessageAttributes.TARGET_ARN.StringValue,
      event_id: $event.detail.event_id
    }
' "../evidence/$EVENT_ID-delivery-dlq.json"
```

Сразу восстанови политику, управляемую Terraform:

```bash
terraform plan -out=tfplan-restore
terraform show -no-color tfplan-restore | less
terraform apply tfplan-restore

terraform plan -detailed-exitcode
printf 'exit_code=%s\n' "$?"
```

Финальный код должен быть `0`. Если получен `2`, разбери и устрани оставшийся drift.
Не оставляй политику цели в состоянии упражнения.

## 13. Разбор типовых проблем

### `PutEvents` успешен, но в Lambda нет записи

Проверяем последовательно:

1. В evidence `FailedEntryCount = 0`.
2. Событие совпадает с pattern через test-event-pattern.
3. У правила есть правильный target.
4. В delivery DLQ нет ошибки доставки.
5. Event source mapping Lambda включён.

### Скрипт принимает ошибочное имя шины

Используй скрипт лаборатории, а не только `aws events put-events`. Скрипт сначала
вызывает `describe-event-bus`, потому что EventBridge может вернуть успех для
несуществующей пользовательской шины и потерять событие без совпадений.

Поэтому лабораторный скрипт сначала выполняет:

```bash
aws events describe-event-bus \
  --name "$EVENT_BUS_NAME" \
  --region "$AWS_REGION"
```

Только после успешной проверки он вызывает `put-events`.

### EventBridge сообщает `NO_PERMISSIONS`

Проверяем queue policy:

```text
Principal     = events.amazonaws.com
Action        = sqs:SendMessage
aws:SourceArn = точный ARN правила
```

Также ищем конфликтующий `Deny`.

### Исходная очередь выглядит пустой

Lambda постоянно опрашивает её. Пустая очередь может означать успешную обработку,
а не ошибку маршрутизации. Ищи уникальный бизнес-`event_id` в логах функции и
проверяй шаблон, не полагаясь только на глубину очереди.

### DLQ обработки остаётся пустой

Проверяем:

- сообщение действительно дошло до нужной ветки;
- event source mapping включён;
- Lambda действительно возвращает запись в `batchItemFailures`;
- закончился visibility timeout;
- сообщение исчерпало `maxReceiveCount`.

### DLQ доставки остаётся пустой

Проверяем три вещи:

- временный `Deny` действительно появился в policy source queue;
- delivery DLQ имеет собственный `Allow` для `events.amazonaws.com`;
- EventBridge зарегистрировал failed invocation.

Особенно полезны две метрики:

```text
FailedInvocations
InvocationsFailedToBeSentToDLQ
```

Первая показывает ошибку доставки цели. Вторая показывает, что EventBridge также
не смог записать событие в delivery DLQ.

### Файл шаблона работает, а правило Terraform отличается

Фактически развёрнутые шаблоны берутся из `locals.tf`, а файлы `patterns/*.json`
используются командой `test-event-pattern`.

Сравни его с фактическим выводом:

```bash
terraform output -json event_patterns | jq .
```

Файлы в `patterns/` используются в упражнениях. Источником истины для развёртывания
остаётся `locals.tf`, поэтому оба представления нужно поддерживать согласованными.

## 14. Стоимость и эксплуатационные границы

Лаборатория создаёт:

- 1 custom event bus;
- 2 EventBridge rules;
- 6 SQS queues;
- 2 Lambda;
- 2 log groups;
- 2 event source mappings;
- 2 IAM roles;
- 8 CloudWatch alarms.

При учебном количестве событий запросы EventBridge, SQS и Lambda стоят мало. Более
заметной постоянной статьёй могут быть восемь CloudWatch alarms, потому что они
существуют и тарифицируются независимо от количества событий. Сообщения в DLQ
сохраняются до истечения retention либо удаления очередей. В этой лаборатории
DLQ настроены на 14 дней.

Не создавай правила, которые публикуют подходящие события обратно в ту же шину
без поля, завершающего цикл. Циклическая маршрутизация увеличивает расходы и
может привести к ограничению скорости доставки.

## 15. Проверка результата

- [ ] Python unit tests проходят.
- [ ] Проверки shell и JSON проходят.
- [ ] Terraform validate и все 12 native-тестов проходят.
- [ ] Матрица шаблонов даёт ожидаемый результат для четырёх событий.
- [ ] Созданный крупный заказ попадает в обе ветки.
- [ ] Небольшой заказ попадает только в audit.
- [ ] Возврат попадает только в audit, несмотря на большую сумму.
- [ ] Событие с неверным источником принимается, но не совпадает с правилами.
- [ ] Ошибка выбранного обработчика попадает только в его DLQ обработки.
- [ ] Ошибка доставки попадает в DLQ цели EventBridge.
- [ ] Drift политики очереди устранён, финальный код плана равен `0`.
- [ ] Прямая запись в исходную очередь запрещена.

## 16. Очистка

Сначала убедись, что после упражнения восстановлена политика доставки.
Затем удали лабораторию через Terraform:

```bash
terraform plan -destroy -out=tfplan-destroy
terraform show -no-color tfplan-destroy | less
terraform apply tfplan-destroy
```

Проверь, что в state не осталось ресурсов:

```bash
terraform state list
```

Общий `.gitignore` репозитория исключает временные результаты выполнения и state Terraform.

## 17. Итоговая модель

Не объединяй следующие утверждения:

1. `PutEvents` принял запись.
2. Шаблон правила совпал с оболочкой.
3. EventBridge доставил подходящее событие цели.
4. SQS сохранил доставленное сообщение.
5. Lambda успешно обработала сообщение.
6. Бизнес-операция дала правильный результат.

Правила EventBridge отвечают на вопросы маршрутизации. DLQ доставки объясняет, почему
подходящее событие не достигло цели. DLQ обработки SQS объясняет, почему принятое сообщение
не удалось обработать. Логи и бизнес-состояние показывают, получен ли нужный результат.

## 18. Официальные источники

- [Синтаксис шаблонов EventBridge](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-create-pattern.html)
- [Рекомендации по шаблонам событий](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-patterns-best-practices.html)
- [Отправка событий через PutEvents](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-putevents.html)
- [Цели EventBridge](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-targets.html)
- [Повторы доставки EventBridge](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-rule-retry-policy.html)
- [DLQ для целей EventBridge](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-rule-dlq.html)
- [Использование Lambda с SQS](https://docs.aws.amazon.com/lambda/latest/dg/with-sqs.html)
- [Частичные ошибки пакета SQS](https://docs.aws.amazon.com/lambda/latest/dg/services-sqs-errorhandling.html)
