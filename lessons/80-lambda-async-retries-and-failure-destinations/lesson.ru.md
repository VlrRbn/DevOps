# Урок 80. Асинхронный вызов Lambda, повторы и обработка отказов

## 1. Зачем нужен этот урок

В уроках 78 и 79 мы разобрали две основы:

- как выполняется обработчик (`handler`) Lambda;
- как IAM определяет, кто может вызвать Lambda.

Но мы ещё не разобрали, что происходит, когда Lambda принимает задачу и
обрабатывает её позже.

При асинхронном вызове такой ответ:

```json
{
  "StatusCode": 202
}
```

означает только одно:

```text
При асинхронном вызове вызывающая сторона не ждёт выполнения обработчика.
Она передаёт событие сервису Lambda, получает подтверждение приёма и завершает
свою работу.
```

Это не означает, что обработчик завершился успешно. Позже он может упасть, Lambda
может повторить вызов, событие может устареть, а failure destination может не принять итоговую запись.

В этом уроке сделаем все эти состояния наблюдаемыми.

## 2. Результаты урока

После урока ты сможешь:

- различать синхронный и асинхронный вызов Lambda;
- объяснить, почему `202 Accepted` не доказывает успешную обработку;
- ограничить число повторов и максимальный возраст события;
- отличать первую попытку обработки от дополнительных повторов;
- направить запись о неудачном вызове в SQS;
- объяснить разницу между DLQ и Lambda destination;
- проверить CloudWatch Logs, alarms и запись об отказе в SQS;
- объяснить, зачем повторяемому обработчику нужна идемпотентность;
- удалить лабораторию, не уничтожив диагностические данные раньше времени.

## 3. Ментальная модель

### 3.1. Синхронный и асинхронный вызов

При синхронном вызове `RequestResponse` вызывающая сторона ждёт завершения обработчика:

```text
caller
  -> Lambda service
  -> handler
  -> response или FunctionError
  -> caller
```

Здесь вызов API и выполнение обработчика связаны в одну цепочку.

При асинхронном вызове `Event` Lambda подтверждает запрос до запуска обработчика:

```text
caller
  -> Lambda asynchronous queue
  <- 202 Accepted

Lambda asynchronous queue
  -> handler attempt
  -> retry или success
  -> optional destination

or

Lambda asynchronous queue
  -> handler failure
  -> retry
  -> failure destination
```

Запрос вызывающей стороны и выполнение обработчика теперь являются двумя
отдельными операциями.

### 3.2. Приём, обработка и доставка результата

Нужно проверить три разных факта:

| Вопрос | Доказательство |
|---|---|
| Lambda приняла событие? | AWS CLI вернул `StatusCode = 202` |
| Обработчик выполнил событие? | Журналы функции и метрики Lambda |
| Итоговая запись об отказе доставлена? | Сообщение в SQS и отсутствие `DestinationDeliveryFailures` |

```text
caller
  -> Lambda async queue
  <- 202 Accepted
      доказан только приём

Lambda async queue
  -> handler
      доказан запуск

handler
  -> success log
      доказана успешная обработка

или

handler
  -> failure
  -> retry
  -> SQS failure destination
      доказана доставка записи об отказе
```

Один сигнал не отвечает сразу на все три вопроса.

Читать ситуацию так:

```text
202 есть, логов нет
-> событие принято, выполнение пока не доказано

лог с RuntimeError есть
-> обработчик запустился и завершился ошибкой

ошибка обработчика есть, сообщение SQS есть
-> обработка провалилась, но failure destination сработал успешно

ошибка обработчика есть, SQS пустая,
DestinationDeliveryFailures растёт
-> произошёл отдельный отказ доставки в destination
```

### 3.3. Как работают повторы

В лаборатории настроено:

```hcl
maximum_retry_attempts       = 1
maximum_event_age_in_seconds = 300
```

`maximum_retry_attempts = 1` означает:

```text
первая попытка + не более одного повтора = не более двух запусков обработчика
```

Это не одна попытка всего.

В лаборатории повтор возникает из-за исключения в обработчике. Для throttling и
системных ошибок `429/5xx` Lambda использует другой backoff и может возвращать
событие в очередь до достижения максимального возраста. Поэтому
`maximum_retry_attempts = 1` нельзя считать универсальным пределом для любого
типа отказа.

```text
Lambda async queue
  -> attempt 1
      -> failure

  -> retry 1
      -> success
         или
      -> failure

retries exhausted
  -> failure destination
```

Асинхронная обработка Lambda на практике имеет семантику at-least-once. Событие
может прийти повторно. Кроме того, полезное действие может завершиться успешно,
а функция — упасть до того, как зафиксирует завершение.

Поэтому реальному обработчику нужна стратегия идемпотентности, например:

```text
event_id
  -> проверить хранилище дедупликации

event_id отсутствует
  -> записать event_id
  -> выполнить действие

event_id уже существует
  -> не повторять действие
  -> завершиться безопасно
```

В контракте этой лаборатории есть `event_id`, но хранилище дедупликации DynamoDB
намеренно не добавлено.

### 3.4. DLQ и failure destination

Dead-letter queue и Lambda destination решают похожие задачи, но содержат разные данные:

| Механизм | Содержимое |
|---|---|
| Lambda DLQ | Исходное событие и ограниченные атрибуты ошибки |
| On-failure destination | Полная запись с контекстом запроса и ответа |

В лаборатории используется on-failure destination в SQS, потому что он сохраняет
больше диагностических данных:

```text
requestContext — служебный контекст асинхронной обработки: число попыток, условие завершения;
requestPayload — исходное событие, переданное функции;
responseContext — статус выполнения функции и признак ошибки;
responsePayload — результат или информация об исключении.
```

Очередь SQS не является источником событий для этой функции. Lambda отправляет
туда итоговую запись только после неудачного завершения асинхронной обработки.

Схема DLQ:

```text
Lambda async queue
  -> handler
  -> retries exhausted
  -> DLQ
     -> original event
     -> limited error attributes
```

Схема On-failure destination:

```text
Lambda async queue
  -> handler
  -> retry
  -> retries exhausted
  -> SQS destination
     -> full invocation record
```

## 4. Архитектура лаборатории

Terraform создаёт:

- одну Python Lambda-функцию;
- execution role для журналов и отправки записи об отказе;
- зашифрованную SQS failure destination;
- конфигурацию асинхронного вызова;
- alarm для ошибок обработчика;
- alarm для ошибок доставки в destination.

Можно читать архитектуру так:

```text
caller принимает только 202
Lambda управляет очередью и повторами
обработчик пишет результат попытки в Logs
SQS получает только итоговую запись об отказе
alarms наблюдают функцию и доставку отдельно
```

### 4.1. Где искать ресурсы

После разделения конфигурации каждый файл отвечает за один блок:

| Файл | Что в нём находится |
|---|---|
| `locals.tf` | единая схема имён и общие теги |
| `package.tf` | упаковка Python-кода в ZIP |
| `function_execution_role.tf` | execution role и её IAM policy |
| `failure_destination.tf` | очередь SQS |
| `lambda.tf` | log group и Lambda-функция |
| `async_invoke.tf` | повторы, возраст события и on-failure destination |
| `monitoring.tf` | CloudWatch alarms |
| `outputs.tf` | имена и ARN для команд проверки |

Имена ресурсов также показывают их назначение:

```text
lab80-dev-lambda-async-worker
lab80-dev-role-lambda-execution
lab80-dev-policy-for-role-lambda-execution-allow-logs-and-failure-delivery
lab80-dev-sqs-lambda-failure-destination
```

Поток:

```text
AWS CLI
  |
  | InvocationType=Event
  v
Lambda async queue
  |
  +--> handler success --> CloudWatch Logs
  |
  +--> handler failure --> retry --> SQS failure destination
                         \
                          -> invocation record
```

У функции нет публичного endpoint, а лаборатория не создаёт постоянные ключи
доступа.

## 5. Локальные проверки

Из корня репозитория:

```bash
python3 -m unittest discover \
  -s lessons/80-lambda-async-retries-and-failure-destinations/lab_80/tests -v

bash -n \
  lessons/80-lambda-async-retries-and-failure-destinations/lab_80/scripts/*.sh
```

Затем:

```bash
cd lessons/80-lambda-async-retries-and-failure-destinations/lab_80/terraform
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform fmt -check -recursive
terraform validate
terraform test
```

`terraform test` использует подменённый AWS provider. Он проверяет структуру
конфигурации, но не реальное время повторов, распространение прав IAM или доставку в SQS.

## 6. Развёртывание лаборатории

Сначала проверь аутентификацию:

```bash
aws sts get-caller-identity
```

Создай, проверь и примени сохранённый план:

```bash
terraform plan -out=tfplan
terraform show tfplan
terraform apply tfplan
```

Сохрани outputs для следующих команд:

```bash
FUNCTION_NAME="$(terraform output -raw function_name)"
AWS_REGION="$(terraform output -raw aws_region)"
FAILURE_QUEUE_URL="$(terraform output -raw failure_queue_url)"

printf 'function=%s\nregion=%s\nqueue=%s\n' \
  "$FUNCTION_NAME" "$AWS_REGION" "$FAILURE_QUEUE_URL"
```

Проверь конфигурацию асинхронного вызова:

```bash
aws lambda get-function-event-invoke-config \
  --region "$AWS_REGION" \
  --function-name "$FUNCTION_NAME" \
  --output json | jq .
```

Убедись, что:

- `MaximumRetryAttempts` равен `1`;
- `MaximumEventAgeInSeconds` равен `300`;
- `DestinationConfig.OnFailure.Destination` содержит ARN очереди лаборатории.

## 7. Успешное асинхронное событие

Сделай скрипты исполняемыми:

```bash
chmod +x ../scripts/*.sh
```

Отправь успешное событие:

```bash
../scripts/invoke-async.sh \
  "$FUNCTION_NAME" \
  "$AWS_REGION" \
  ../events/success.json \
  ../evidence/success-acceptance.json

jq . ../evidence/success-acceptance.json
```

Ожидаемый ответ API:

```json
{
  "StatusCode": 202
}
```

Теперь проверь выполнение обработчика:

```bash
aws logs tail "/aws/lambda/$FUNCTION_NAME" \
  --region "$AWS_REGION" \
  --since 10m \
  --format short
```

Найди `evt-success-001` и запись приложения
`"event": "async_event_processed"`. Именно она доказывает, что обработчик дошёл
до успешного завершения. Служебные строки `END`/`REPORT` сами по себе
недостаточны: Lambda пишет их и для попыток, завершившихся ошибкой.

## 8. Неудачное событие и повтор

Отправь событие с намеренной ошибкой:

```bash
../scripts/invoke-async.sh \
  "$FUNCTION_NAME" \
  "$AWS_REGION" \
  ../events/failure.json \
  ../evidence/failure-acceptance.json
```

Скрипт снова ожидает `202`. Это правильно: Lambda приняла корректный API-запрос,
хотя обработчик позже намеренно отклонит событие.

Следи за журналом:

```bash
aws logs tail "/aws/lambda/$FUNCTION_NAME" \
  --region "$AWS_REGION" \
  --since 10m \
  --follow \
  --format short
```

После появления повторов останови `--follow` сочетанием `Ctrl+C`.

При асинхронном повторе, которым управляет сама Lambda, обработка одного события
может сохранять тот же `RequestId`:

```text
одинаковый event_id
+ одинаковый RequestId
+ два START в разное время
+ два RuntimeError
=
первая попытка и один retry со стороны Lambda
```

Время повторов контролирует Lambda. Это не точный таймер, поэтому автоматизация
не должна ожидать повтор в строго определённую секунду.

### 8.1. `event_id` и Lambda `RequestId`

Не путай два идентификатора:

| Идентификатор | Кто создаёт | Что обозначает |
|---|---|---|
| `event_id` | отправитель события | бизнес-событие внутри payload |
| `RequestId` | сервис Lambda | асинхронный запрос и его Lambda-managed retry lifecycle |

`RequestId`: транспортный диагностический идентификатор, а не ключ
бизнес-события. При повторе после ошибки, которым управляет сама Lambda, он
может сохраняться между попытками.

#### Повтор одного асинхронного события

Вызывающая сторона отправила событие один раз. Обработчик завершился ошибкой,
после чего Lambda выполнила настроенный повтор:

```text
caller
  -> event_id=evt-failure-001
  -> Lambda async queue

attempt 1
  -> RequestId=A
  -> RuntimeError

retry
  -> RequestId=A
  -> RuntimeError
```

Главный вывод:

```text
event_id
-> идентификатор бизнес-события
-> используется для идемпотентности

RequestId
-> диагностический идентификатор асинхронного запроса Lambda
-> может сохраняться при Lambda-managed retry
-> не заменяет event_id
```

#### Два отдельных вызова с одинаковой полезной нагрузкой

В упражнении 2 вызывающая сторона дважды отправляет одну и ту же полезную
нагрузку:

```text
caller invoke 1
  -> event_id=evt-duplicate-001
  -> RequestId=A

caller invoke 2
  -> event_id=evt-duplicate-001
  -> RequestId=B
```

Два разных `RequestId` не означают два разных бизнес-события. И наоборот,
Lambda может доставить асинхронное событие повторно даже без ошибки
обработчика. Поэтому нельзя использовать количество вызовов или `RequestId`
как замену ключу идемпотентности.

Без внешнего хранилища дедупликации одинаковый `event_id` может быть обработан несколько раз.

## 9. Проверка failure destination

Проверяем три факта:

- После исчерпания повторов сообщение действительно появилось в SQS.
- Сообщение относится именно к `evt-failure-001`.
- В записи о вызове отражены две попытки и ошибка функции.

Дождись итоговой записи в SQS:

```bash
../scripts/receive-failure.sh \
  "$FAILURE_QUEUE_URL" \
  "$AWS_REGION" \
  ../evidence/failure-record.json \
  evt-failure-001
```

Скрипт использует long polling. Пока Lambda завершает цикл повторов, ожидание
может занять несколько минут. Скрипт получает сообщение с visibility timeout
`0`, выбирает запись с указанным `event_id` и не удаляет её. Фильтр не даёт
перепутать текущий результат с сообщениями от предыдущих упражнений.

Посмотри оболочку сообщения:

```bash
jq '.Messages[0] | {
  MessageId,
  Attributes,
  Body
}' ../evidence/failure-record.json
```

Раскодируй destination record из поля `Body`:

```bash
jq -r '.Messages[0].Body' ../evidence/failure-record.json |
  jq '{
    requestContext,
    requestPayload,
    responseContext,
    responsePayload
  }'

or

jq -r '.Messages[0].Body' ../evidence/failure-record.json |
  jq '{
    event_id: .requestPayload.event_id,
    approximateInvokeCount: .requestContext.approximateInvokeCount,
    condition: .requestContext.condition,
    functionError: .responseContext.functionError,
    statusCode: .responseContext.statusCode,
    responsePayload: .responsePayload
  }'
```

Убедись, что:

| Поле | Ожидаемое значение | Что это доказывает |
|---|---|---|
| `requestPayload.event_id` | `evt-failure-001` | получена запись нужного события |
| `requestContext.approximateInvokeCount` | `2` | была первая попытка и один повтор |
| `requestContext.condition` | `RetriesExhausted` | лимит попыток исчерпан |
| `responseContext.functionError` | `Unhandled` | обработчик завершился необработанным исключением |

## 10. Метрики и alarms

Для асинхронной обработки полезны разные группы метрик:

| Метрика | Что она показывает |
|---|---|
| `AsyncEventsReceived` | события, успешно поставленные во внутреннюю очередь Lambda |
| `Invocations` | реальные запуски обработчика, включая повторы |
| `Errors` | попытки выполнения обработчика, завершившиеся ошибкой функции |
| `AsyncEventAge` | время ожидания события перед очередной попыткой |
| `AsyncEventsDropped` | события, отброшенные после истечения возраста или попыток |
| `DestinationDeliveryFailures` | Lambda не смогла отправить итоговую запись в destination |

Лаборатория создаёт alarms для `Errors` и `DestinationDeliveryFailures`, потому
что их можно осмысленно проверить одним неудачным событием. Для постоянной
системы также обычно задают пороги на возраст очереди и число отброшенных
событий.

Схема:

```text
handler
  -> RuntimeError
  -> Errors metric increases
  -> function errors alarm

retries exhausted
  -> Lambda sends record to SQS
  -> delivery succeeds
  -> DestinationDeliveryFailures remains 0
  -> destination alarm stays OK
```

Посмотри состояние alarms:

```bash
aws cloudwatch describe-alarms \
  --region "$AWS_REGION" \
  --alarm-names \
    "$(terraform output -raw function_errors_alarm_name)" \
    "$(terraform output -raw destination_delivery_failure_alarm_name)" \
  --query 'MetricAlarms[*].[AlarmName,StateValue,StateReason]' \
  --output table
```

Ожидаемая интерпретация:

- alarm ошибок может перейти в `ALARM` после неудачных попыток;
- alarm доставки в destination должен остаться в `OK`;
- до получения полного периода CloudWatch может показать
  `INSUFFICIENT_DATA`.

Второй alarm не сообщает об ошибках обработчика. Он срабатывает, когда Lambda не
смогла отправить итоговую запись в настроенный destination.

## 11. Практические упражнения

### Упражнение 1. Нарушение контракта события

В `../events/invalid.json` есть `event_id`, но значение `mode` нарушает контракт.

Схема:

```text
caller
  -> Lambda async queue
  <- 202 Accepted

Lambda async queue
  -> attempt 1
  -> ValueError

Lambda async queue
  -> retry 1
  -> ValueError

retries exhausted
  -> SQS failure destination
  -> invocation record
```

Асинхронно вызови функцию:

```bash
../scripts/invoke-async.sh \
  "$FUNCTION_NAME" \
  "$AWS_REGION" \
  ../events/invalid.json \
  ../evidence/invalid-acceptance.json
```

Следи за попытками:

```bash
aws logs tail "/aws/lambda/$FUNCTION_NAME" \
  --region "$AWS_REGION" \
  --since 10m \
  --follow \
  --format short
```

Получи итоговую запись:

```bash
../scripts/receive-failure.sh \
  "$FAILURE_QUEUE_URL" \
  "$AWS_REGION" \
  ../evidence/invalid-failure-record.json \
  evt-invalid-001
```
Просмотри:

```bash
jq -r '.Messages[0].Body' ../evidence/invalid-failure-record.json |
  jq '{
    event_id: .requestPayload.event_id,
    approximateInvokeCount: .requestContext.approximateInvokeCount,
    condition: .requestContext.condition,
    functionError: .responseContext.functionError,
    statusCode: .responseContext.statusCode,
    responsePayload: .responsePayload
  }'
```

До запуска предскажи результат:

- API примет событие: `202`;
- обработчик завершится с `ValueError`;
- Lambda выполнит повтор в пределах установленного лимита;
- итоговая запись попадёт в SQS destination.

### Упражнение 2. Повторное событие

Подготовь отдельное событие и отправь его дважды, не меняя `event_id`:

```bash
jq '.event_id = "evt-duplicate-001"' \
  ../events/success.json > /tmp/lab80-duplicate.json

for attempt in 1 2; do
  ../scripts/invoke-async.sh \
    "$FUNCTION_NAME" \
    "$AWS_REGION" \
    /tmp/lab80-duplicate.json \
    "../evidence/duplicate-${attempt}-acceptance.json"
done
```

Схема:

```text
caller invoke 1
  -> Lambda async queue
  -> handler
  -> async_event_processed

caller invoke 2
  -> Lambda async queue
  -> handler
  -> async_event_processed
```

Найди события в журнале:

```bash
aws logs tail "/aws/lambda/$FUNCTION_NAME" \
  --region "$AWS_REGION" \
  --since 10m \
  --format short |
  grep 'async_event_processed' |
  grep 'evt-duplicate-001'
```

Ожидаются две записи `async_event_processed`: обработчик выполнит обе копии,
потому что в лаборатории нет хранилища идемпотентности.
У них должен совпадать `event_id`, но различаться `request_id`, созданный для
каждого отдельного вызова.

### Упражнение 3. Отключение повторов

Установи:

```hcl
maximum_retry_attempts = 0
```

Схема:

```text
caller
  -> Lambda async queue
  <- 202 Accepted

Lambda async queue
  -> handler attempt 1
  -> RuntimeError

maximum_retry_attempts = 0
  -> повтора нет
  -> SQS failure destination
```

Создай и примени новый сохранённый план:

```bash
terraform plan -out=tfplan-no-retry
terraform apply tfplan-no-retry
```

Подготовь событие с новым идентификатором и отправь его:

```bash
jq '.event_id = "evt-no-retry-001"' \
  ../events/failure.json > /tmp/lab80-no-retry.json

../scripts/invoke-async.sh \
  "$FUNCTION_NAME" \
  "$AWS_REGION" \
  /tmp/lab80-no-retry.json \
  ../evidence/no-retry-acceptance.json

../scripts/receive-failure.sh \
  "$FAILURE_QUEUE_URL" \
  "$AWS_REGION" \
  ../evidence/no-retry-failure-record.json \
  evt-no-retry-001
```

Убедись, что `requestContext.approximateInvokeCount` равен `1`, а не `2`.

После упражнения верни значение `1`, создай новый сохранённый план и примени
его:

```bash
terraform plan -out=tfplan-restore-retry
terraform apply tfplan-restore-retry
```

### Упражнение 4. Нет права на отправку в destination

Прочитай runtime policy и найди точное право, необходимое для отправки в SQS:

```text
sqs:SendMessage
```

Это аналитическое упражнение. Во время обычного прохождения не удаляй
разрешение вручную: такой эксперимент создаст IAM drift и потребует отдельного
восстановления через Terraform.

Схема при отсутствии разрешения:

```text
handler
  -> RuntimeError
  -> retry
  -> RetriesExhausted

Lambda
  -> пытается отправить invocation record
  -> AccessDenied на sqs:SendMessage
  -> SQS остаётся пустой
  -> DestinationDeliveryFailures увеличивается
```

## 12. Разбор типовых проблем

### `No valid credential sources found`

Сессия AWS могла завершиться между локальными проверками и `terraform plan`.
Повтори вход и проверь, от чьего имени выполняются команды:

```bash
export AWS_PROFILE=YOUR_PROFILE
aws sso login --profile "$AWS_PROFILE"
aws sts get-caller-identity
```

### AWS CLI вернул `202`, но журнала нет

Проверь:

```text
202 получен
  -> проверить имя функции и регион
  -> проверить конфигурацию асинхронного вызова
  -> проверить CloudWatch Logs
  -> проверить Errors / Invocations / Throttles
  -> проверить execution role
```

Помни, что асинхронная обработка может начаться с задержкой.

### В SQS нет сообщения

Запись об отказе появляется в SQS не сразу после первой ошибки обработчика, а
после завершения всего цикла асинхронной обработки.

Проверь:

```text
SQS пустая
  -> обработчик действительно завершился ошибкой?
  -> все повторы уже завершились?
  -> настроен OnFailure destination?
  -> разрешён `sqs:SendMessage`?
  -> правильные URL очереди и регион?
  -> `DestinationDeliveryFailures` увеличилась?
```

Также убедись, что случайно не использовал синхронный `RequestResponse`.

### Одно сообщение появляется снова и снова

`receive-failure.sh` намеренно устанавливает visibility timeout в `0` и не
удаляет сообщения. Это сделано для лаборатории, чтобы диагностическая запись не
исчезла после первой проверки.

После проверки можно удалить одно конкретное сообщение по его receipt handle:

```bash
RECEIPT_HANDLE="$(
  jq -r '.Messages[0].ReceiptHandle' ../evidence/failure-record.json
)"

aws sqs delete-message \
  --region "$AWS_REGION" \
  --queue-url "$FAILURE_QUEUE_URL" \
  --receipt-handle "$RECEIPT_HANDLE"
```

Используй только receipt handle из последнего ответа нужной очереди.

### `DestinationDeliveryFailures` остаётся в `OK`

Это ожидаемо, если доставка в SQS прошла успешно. Ошибки обработчика отражаются в
метрике `Errors`, а ошибка destination является отдельным уровнем отказа.

Схема:

```text
handler
  -> RuntimeError
  -> Errors > 0
  -> function errors alarm может перейти в ALARM

Lambda
  -> sqs:SendMessage
  -> сообщение доставлено
  -> DestinationDeliveryFailures = 0
  -> destination alarm остаётся OK
```

## 13. Проверка результата

Перед очисткой убедись, что:

- Python tests и Terraform native tests прошли;
- успешное событие вернуло `202` и появилось в журнале;
- неудачное событие также вернуло `202`;
- ошибка обработчика привела к повтору;
- SQS содержит раскодированную запись о вызове;
- ты правильно объяснил alarms ошибок и доставки;
- execution role ограничивает `sqs:SendMessage` одной очередью;
- временные учётные данные AWS не записаны в результаты;
- ты можешь объяснить, почему обработчик пока не идемпотентен.

Файлы в `lab_80/evidence/` являются временными результатами. Не коммить их без
проверки и маскирования служебных метаданных.

## 14. Очистка

Перед `destroy` сохрани идентификаторы:

```bash
FUNCTION_NAME="$(terraform output -raw function_name)"
FAILURE_QUEUE_URL="$(terraform output -raw failure_queue_url)"
AWS_REGION="$(terraform output -raw aws_region)"
```

Создай и просмотри сохранённый destroy plan, затем примени именно его:

```bash
terraform plan -destroy -out=tfplan-destroy
terraform show tfplan-destroy
terraform apply tfplan-destroy
```

Проверь результат:

```bash
aws lambda get-function \
  --region "$AWS_REGION" \
  --function-name "$FUNCTION_NAME"

aws sqs get-queue-attributes \
  --region "$AWS_REGION" \
  --queue-url "$FAILURE_QUEUE_URL" \
  --attribute-names QueueArn
```

Обе команды должны сообщить, что соответствующего ресурса больше нет.

## 15. Итоговая модель

```text
202 Accepted
    -> событие попало в систему асинхронной доставки Lambda

handler success
    -> доказывается выполнением, а не приёмом запроса

handler failure
    -> может привести к повторам и повторной обработке

retries exhausted
    -> итоговая запись отправляется в failure destination

destination delivery failure
    -> отдельный эксплуатационный отказ со своей метрикой
```

Главные выводы:

1. Приём события и завершение бизнес-операции — разные состояния.
2. Retry count задаёт дополнительные, а не все попытки.
3. Повторяемая обработка требует идемпотентности на границе бизнес-операции.
4. Failure destination сохраняет больше контекста, чем обычная DLQ.
5. Журналы, метрики функции, метрики destination и записи SQS отвечают на разные
   диагностические вопросы.
6. Ограничения повторов и возраста события не дают обрабатывать задачу бесконечно
   или слишком поздно.

## 16. Официальные источники

- [Асинхронный вызов Lambda](https://docs.aws.amazon.com/lambda/latest/dg/invocation-async.html)
- [Настройка обработки ошибок](https://docs.aws.amazon.com/lambda/latest/dg/invocation-async-error-handling.html)
- [Lambda destinations](https://docs.aws.amazon.com/lambda/latest/dg/invocation-async-retain-records.html)
- [Метрики Lambda](https://docs.aws.amazon.com/lambda/latest/dg/monitoring-metrics-types.html)
- [Разбор повторных вызовов Lambda](https://repost.aws/knowledge-center/lambda-function-duplicate-invocations)
- [Terraform event invoke configuration](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function_event_invoke_config)
