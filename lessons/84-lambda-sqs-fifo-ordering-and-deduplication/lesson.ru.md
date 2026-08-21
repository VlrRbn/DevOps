# Урок 84. Lambda с SQS FIFO: порядок, дедупликация и группы сообщений

## 1. Зачем нужен этот урок

В уроках 82 и 83 мы использовали стандартную очередь SQS. Она обеспечивала надёжную
буферизацию, частичный ответ по пакету (`ReportBatchItemFailures`) и ограничение
одновременных вызовов (`concurrency`), но не гарантировала строгий порядок обработки.

Некоторым процессам нужна дополнительная гарантия:

```text
обновление 1 для одной сущности
-> обновление 2 для той же сущности
-> обновление 3 для той же сущности
```

Если обработать третье обновление раньше второго, состояние может повредиться,
даже когда каждое сообщение само по себе корректно. Очередь SQS FIFO решает эту
задачу с помощью групп сообщений:

```text
одинаковый MessageGroupId -> строгий порядок и один активный вызов для группы
разные MessageGroupId     -> возможна параллельная обработка
```

FIFO также подавляет повторную отправку (`duplication`) на стороне производителя (`producer`).
Это полезная возможность, но она не превращает обработку в exactly-once и не заменяет
границу идемпотентности с DynamoDB из урока 81.

В этом уроке построим полный контракт:

```text
производитель (`producer`) выбирает стабильный ключ группы (`MessageGroupId`)
-> назначает явный идентификатор дедупликации (`MessageDeduplicationId`)
-> SQS FIFO сохраняет порядок внутри группы
-> Lambda параллельно обрабатывает разные группы
-> обработчик останавливается после первой ошибки в пакете
-> ошибочная и необработанные записи отправляются на повтор
```

Что нового относительно Standard SQS:

| Standard SQS                                | FIFO SQS                                      |
| ------------------------------------------- | --------------------------------------------- |
| строгий порядок не гарантирован             | порядок внутри `MessageGroupId`               |
| группы не являются основой concurrency      | разные группы дают parallelism                |
| нет FIFO producer deduplication             | есть `MessageDeduplicationId`                 |
| записи batch можно рассматривать независимо | после ошибки потребуется FIFO failure barrier |

## 2. Результаты урока

После урока ты сможешь:

- объяснить, почему порядок FIFO ограничен одним `MessageGroupId`;
- выбирать ключ группы по бизнес-сущности, а не по случайному запросу;
- отличать порядок очереди от идемпотентности приложения;
- объяснить пятиминутный интервал дедупликации FIFO;
- передавать явный `MessageDeduplicationId`;
- вычислять предел одновременных вызовов по числу активных групп;
- сохранять порядок при включённом `ReportBatchItemFailures`;
- находить перегруженную группу;
- развернуть исходную FIFO-очередь с FIFO DLQ;
- проверить порядок, параллельность групп, подавление дублей и блокировку после ошибки;
- отклонять неверный размер пакета, лимит мощности и тайм-аут видимости;

Карта доказательств:

| Что доказываем | Чем подтверждается |
|---|---|
| Исходная очередь и DLQ относятся к FIFO | AWS CLI показывает `FifoQueue = true`, а оба имени заканчиваются на `.fifo` |
| Контракт производителя явный | Скрипт передаёт идентификаторы группы и дедупликации |
| Одна группа сохраняет порядок | В журналах `work_completed` последовательность одной группы равна `1, 2, 3...` |
| Разные группы могут пересекаться | Временные интервалы работы групп A и B перекрываются в журналах |
| Повторная отправка подавляется | Две отправки приняты с одним идентификатором, но в журнал попало только первое задание |
| Барьер после ошибки работает | Ошибочный и необработанные ID есть в `batchItemFailures` и журналах отложенных записей |
| Поведение DLQ объяснено | Проблемная и возвращённая необработанная запись расходуют собственные лимиты получения и могут вместе попасть в FIFO DLQ |
| Ограничения инфраструктуры соблюдены | Проходят девять native-тестов Terraform |

Главные результаты можно собрать в 6 блоков:

```text
1. ordering
   - порядок только внутри MessageGroupId

2. grouping
   - стабильный business key
   - не случайный ID

3. deduplication
   - явный MessageDeduplicationId
   - окно 5 минут
   - не exactly-once

4. concurrency
   - зависит от числа активных групп
   - MaximumConcurrency только ограничивает сверху

5. failure handling
   - после первой ошибки не идём дальше по batch
   - сохраняем FIFO order

6. recovery
   - каждая возвращённая запись расходует свой receive budget
   - при BatchSize > 1 poison message и отложенный хвост могут вместе уйти в DLQ
   - после удаления этого барьера новые задания группы могут продолжить работу
```

### 2.1. Словарь RU ↔ EN

| Английский термин | Как используем по-русски | Точный смысл в этом уроке |
|---|---|---|
| `FIFO` | первым пришло — первым обработано | Упорядоченная доставка внутри одной группы сообщений SQS |
| `MessageGroupId` | ключ группы сообщений | Сообщения с одинаковым значением обрабатываются последовательно |
| `MessageDeduplicationId` | идентификатор дедупликации | Подавляет повторную отправку с тем же значением в интервале дедупликации |
| `deduplication interval` | интервал дедупликации | Пять минут, в течение которых SQS помнит идентификатор |
| `SequenceNumber` | транспортный номер SQS | Большое непоследовательное число, которое SQS назначает FIFO-сообщению |
| `business sequence` | бизнес-последовательность | Порядковый номер приложения для обновлений сущности |
| `hot group` | перегруженная группа | Одна группа, чья последовательная очередь определяет общую задержку |
| `failure barrier` | барьер после ошибки | Правило вернуть ошибочную и все ещё не обработанные записи |
| `head-of-line blocking` | блокировка последующих сообщений | Более ранняя ошибка не даёт продвигаться следующим сообщениям группы |
| `partial batch response` | частичный ответ по пакету | `batchItemFailures`, который обработчик возвращает сопоставлению источника Lambda |

## 3. Ментальная модель

### 3.1. FIFO сохраняет порядок внутри группы, а не во всей очереди

Представим два счёта клиентов:

```text
группа customer-100: debit-1 -> debit-2 -> debit-3
группа customer-200: credit-1 -> credit-2
```

SQS FIFO обязана сохранять порядок внутри каждой строки, но не обязана выстраивать
обе строки в один общий глобальный порядок.:

```text
вызов Lambda A -> customer-100
вызов Lambda B -> customer-200
```

Поэтому ключ группы — архитектурное решение. Хороший ключ обозначает наименьшую
бизнес-сущность, которой действительно нужен строгий порядок:

| Требование | Возможный ключ группы (`MessageGroupId`) |
|---|---|
| Упорядочить изменения одного счёта | `account_id` |
| Упорядочить команды одного устройства | `device_id` |
| Упорядочить события одного агрегата | `aggregate_id` |
| Сохранить глобальный порядок всего потока | Один постоянный ID и очень низкая параллельность |

Случайный ID разрушает порядок: связанные сообщения оказываются в разных группах.
Один постоянный ID сохраняет глобальный порядок, но оставляет только одну активную
группу и, следовательно, один активный вызов Lambda от этого источника.

### 3.2. Группы сообщений ограничивают одновременные вызовы

Для FIFO-источника SQS фактическое число одновременных вызовов приблизительно равно:

```text
effective concurrency
= minimum(
    active MessageGroupId count,
    event source MaximumConcurrency,
    available Lambda/account concurrency,
    demand
  )
```

Примеры:

```text
1 активная группа, MaximumConcurrency = 4  -> не более 1 вызова
2 активные группы, MaximumConcurrency = 4 -> не более 2 вызовов
8 активных групп, MaximumConcurrency = 4 -> не более 4 вызовов
```

Повышение `MaximumConcurrency` не ускорит одну перегруженную группу. Для параллельности
нагрузка должна делиться на несколько независимых групп, если бизнес-порядок это допускает.

### 3.3. Дедупликация защищает производителя (`producer`), но не даёт exactly-once

В лаборатории отключена дедупликация по содержимому и требуется явный идентификатор:

```text
MessageDeduplicationId = стабильная идентичность одной операции производителя (`producer`)
```

Если две отправки используют один идентификатор в течение пяти минут:

```text
первый SendMessage  -> принят и доступен для доставки
второй SendMessage  -> принят, но повторно не доставлен
```

```text
операция:
charge-order-123-v2

MessageDeduplicationId:
charge-order-123-v2
```

Если producer из-за retry отправит её ещё раз с тем же ID — FIFO сможет распознать повтор.

SQS продолжает помнить идентификатор даже после получения и удаления первого
сообщения. Но потребителю всё равно нужна идемпотентность, потому что:

- уже доставленное сообщение может повториться, если обработка не подтверждена;
- производитель может отправить ту же бизнес-операцию с другим идентификатором;
- пятиминутный интервал может закончиться;
- побочный эффект может сохраниться, а его подтверждение — завершиться ошибкой.

Правильная модель:

```text
дедупликация FIFO -> уменьшает повторную постановку сообщения производителем
идемпотентность потребителя -> защищает бизнес-эффект во время обработки
```

### 3.4. SequenceNumber не является бизнес-версией

```text
SequenceNumber
  - назначает SQS
  - транспортные метаданные

sequence
  - задаёт наше приложение
  - бизнес-порядок
```

SQS назначает каждому FIFO-сообщению `SequenceNumber`. Это полезные транспортные метаданные,
но значение представляет собой большое непоследовательное число и не должно заменять
версию приложения.

Тело сообщения лаборатории содержит явную последовательность:

```json
{
  "task_id": "group-a-run-1-task-2",
  "sequence": 2,
  "work_seconds": 1,
  "should_fail": false
}
```

Не смешиваем три вещи:

```text
MessageGroupId
  - кому принадлежит последовательность

SequenceNumber
  - transport metadata от SQS

sequence
  - какой это шаг внутри бизнес-последовательности
```

Бизнес-последовательность делает журналы и тесты понятными. В реальной системе потребитель
также может сравнивать входящую версию с текущей версией сущности перед изменением состояния.

### 3.5. Частичному ответу FIFO нужен барьер после ошибки

В стандартной очереди урока 82 каждая запись обрабатывалась независимо, а в ответ
попадали только неудачные записи. Если бездумно повторить это для FIFO, порядок
может нарушиться:

```text
запись 1 успешна
запись 2 завершилась ошибкой
запись 3 успешна  <- опасно, если запись 3 зависит от записи 2
```

То есть FIFO вроде доставила сообщения в правильном порядке, но consumer сам нарушил
бизнес-порядок обработки. Поэтому после первой ошибки появляется `failure barrier`.

Безопасный ответ FIFO:

```text
обработать запись 1
запись 2 завершается ошибкой
остановить обработку
вернуть запись 2 и запись 3 в batchItemFailures
```

Обработчик намеренно жертвует частью пропускной способности пакета, чтобы
сохранить порядок. Следующая попытка начинается с ошибочной границы.

### 3.6. Проблемное сообщение блокирует следующие сообщения группы

Если одно сообщение всегда завершается ошибкой, следующие сообщения той же
группы не могут его обогнать:

```text
группа A: sequence 1 -> sequence 2 (ошибка) -> sequence 3
                              |
                              +-> повторы, затем FIFO DLQ
```

Из-за FIFO 3 и 4 не могут обогнать 2. Это и есть `head-of-line blocking`.

Другие группы в это время могут работать параллельно. Но для уже полученного пакета
есть важное следствие: третья запись возвращается в `batchItemFailures` вместе со
второй. SQS увеличивает `ApproximateReceiveCount` обеих записей, даже если бизнес-логика
третьей ни разу не запускалась.

При `BatchSize = 5` повторные попытки обычно снова получают один и тот же хвост:

```text
попытка 1: sequence 2 failed, sequence 3 deferred -> вернуть 2 + 3
попытка 2: sequence 2 failed, sequence 3 deferred -> вернуть 2 + 3
попытка 3: sequence 2 failed, sequence 3 deferred -> вернуть 2 + 3
следующее получение превышает maxReceiveCount -> 2 и 3 могут уйти в DLQ
```

Это не нарушение FIFO и не ошибка обработчика. Так сохраняется порядок ценой
возможного переноса исправного хвоста пакета в DLQ. Если требуется, чтобы в DLQ
попадала только непосредственно ошибочная запись, используй `BatchSize = 1`.
Тогда следующая запись группы не будет получена в одном пакете с проблемной, но
пакетная эффективность снизится.

Поэтому для FIFO важно следить за возрастом старейшего сообщения и глубиной DLQ.
Общей мощности может быть достаточно, но одна важная группа останется заблокированной.

DLQ для FIFO не только изоляция ошибки, но и способ снять `head-of-line blocking`
после исчерпания попыток.

Главное:

```text
failure barrier
  - не даёт последующим сообщениям обогнать ошибку

head-of-line blocking
  - следствие этого порядка при повторяющейся ошибке

FIFO DLQ
  - после исчерпания retries убирает возвращённые записи из source queue
  - при BatchSize > 1 это могут быть poison message и исправный отложенный хвост
  - новые сообщения группы снова могут двигаться после удаления барьера
```

### 3.7. Выбор между стандартной очередью и FIFO зависит от бизнеса

| Вопрос | Стандартная очередь | FIFO-очередь |
|---|---|---|
| Нужен строгий порядок? | Нет | Внутри каждой группы |
| Есть интервал дедупликации производителя? | Нет | Да |
| Что определяет параллельность? | Мощность очереди и Lambda | Число активных групп и доступная мощность |
| Есть риск перегруженного ключа? | Ниже | Одна группа может сделать поток последовательным |
| Как обрабатывать ошибку пакета? | Независимо обрабатывать записи | Остановиться после первой ошибки |
| Типичный сценарий | Независимые фоновые задания | Упорядоченные команды или изменения сущности |

Не выбирай FIFO только потому, что порядок звучит безопаснее. Эта очередь вводит контракт
и форму нагрузки, которые должны понимать производитель, потребитель, мониторинг и процедура
восстановления.

## 4. Архитектура лаборатории

```text
send-fifo-sequence.sh / send-dedup-pair.sh
                 |
                 | MessageGroupId + MessageDeduplicationId
                 v
+--------------------------------+
| исходная очередь SQS FIFO       |
| явная дедупликация              |
| тайм-аут видимости = 40s        |
+----------------+---------------+
                 |
                 | BatchSize = 5
                 | MaximumConcurrency = 4
                 | ReportBatchItemFailures
                 v
+--------------------------------+
| обработчик Lambda FIFO          |
| остановка после первой ошибки   |
| тайм-аут = 6s                   |
+----------------+---------------+
                 |
                 +----> структурированные журналы CloudWatch

исчерпавшее повторы сообщение
                 |
                 v
+--------------------------------+
| SQS FIFO DLQ                   |
+--------------------------------+
```

Вся схема одним взглядом:

```text
Producer
│
│ MessageGroupId
│ MessageDeduplicationId
V
SQS FIFO source
│
│ BatchSize = 5
│ MaximumConcurrency = 4
│ ReportBatchItemFailures
V
Lambda
│
├─ success - message completed
│
├─ first failure
│    - failure barrier
│    - failed + deferred records retry
│
└─ poison message
     - retries exhausted
     - FIFO DLQ
```

Обе очереди относятся к FIFO. Стандартную DLQ нельзя подключить к исходной FIFO-очереди.
Роль выполнения функции читает только исходную очередь и не может просматривать или удалять
записи из DLQ.

## 5. Разбор реализации

### 5.1. Проверяй транспортные и бизнес-поля отдельно

Открой:

```text
sed -n '1,280p' \
  lessons/84-lambda-sqs-fifo-ordering-and-deduplication/lab_84/app/lambda_function.py
```

Обработчик проверяет транспортные метаданные:

```text
messageId
attributes.MessageGroupId
attributes.MessageDeduplicationId
```

Их смысл:

```text
messageId
  - конкретное сообщение SQS
  - понадобится для batchItemFailures

MessageGroupId
  - к какой FIFO-последовательности относится сообщение

MessageDeduplicationId
  - какой deduplication ID передал producer
```

Важно: это **не данные нашей бизнес-задачи**. Это метадата транспорта.

Затем он проверяет JSON-тело:

```text
task_id
sequence
work_seconds
should_fail
```

Важно: это **данные нашей бизнес-задачи**. Это бизнесс контракт.

`TypedDict` не проверяет данные во время выполнения: реальный контракт по-прежнему
обеспечивают `isinstance()` и явные проверки диапазонов.

### 5.2. Проверяй все messageId до начала работы

`batchItemFailures` может обозначить запись только через `messageId`. Поэтому обработчик
сначала проверяет идентификаторы всех записей и лишь потом запускает бизнес-логику:

```python
message_ids = [get_message_id(record) for record in records]
```

Допустим, batch такой:

```text
record 1 -> valid messageId
record 2 -> valid messageId
record 3 -> broken / missing messageId
```

Поэтому порядок другой:

1. Проверить `messageId` всех records
2. Убедиться, что batch можно корректно описать в response
3. Только потом запускать business logic

То есть сначала проверяем транспортный контракт всего batch.

Без этого шага функция могла бы выполнить ранний побочный эффект, а затем найти
повреждённую запись, которую невозможно представить в ответе.

Если предварительная проверка `messageId` не проходит:

```text
handler не начинает частичную business processing
  - invocation завершается ошибкой целиком
  - некорректный batch будет повторён
```

### 5.3. Остановись после первой ошибки

Главное правило FIFO видно прямо в коде:

```python
failed_and_unprocessed = message_ids[index:]
failures.extend(
    {"itemIdentifier": failed_message_id}
    for failed_message_id in failed_and_unprocessed
)
break
```

В ответ попадают ошибочное сообщение и все записи после него.
`work_deferred_after_failure` отличает необработанные записи от записи, чья
бизнес-операция действительно завершилась ошибкой.

### 5.4. Передавай явные идентификаторы группы и дедупликации

`send-fifo-sequence.sh` собирает пакеты максимум по десять записей SQS. Каждая
запись содержит:

```text
MessageGroupId         -> область порядка, выбранная вызывающей стороной
MessageDeduplicationId -> уникальный идентификатор операции производителя
sequence               -> понятный приложению порядок внутри тела
```

Скрипт добавляет ID запуска, поэтому повтор упражнения в течение пяти минут не
подавляет новую последовательность случайно.

### 5.5. Проверяй подавление дублей намеренно

`send-dedup-pair.sh` делает обратное: отправляет два разных тела с одним явным
идентификатором дедупликации. Оба API-вызова могут завершиться успешно, но в
течение интервала дедупликации Lambda должна получить только первое тело.

Это доказывает гарантию производителя, но не exactly-once для побочных эффектов.

## 6. Локальные проверки

Из корня репозитория:

```bash
python3 -m unittest discover \
  -s lessons/84-lambda-sqs-fifo-ordering-and-deduplication/lab_84/tests -v

for script in lessons/84-lambda-sqs-fifo-ordering-and-deduplication/lab_84/scripts/*.sh; do
  bash -n "$script"
done
```

Ожидаемый результат:

```text
Ran 8 tests
OK
```

Тесты подтверждают разбор записи, запланированную ошибку, порядок вызовов, остановку после
первой ошибки и проверку транспортных ID до начала работы. Они не доказывают поведение
доставки FIFO внутри AWS.

## 7. Проверка и развёртывание Terraform

Перейди в корень Terraform:

```bash
cd lessons/84-lambda-sqs-fifo-ordering-and-deduplication/lab_84/terraform
cp terraform.tfvars.example terraform.tfvars
```

Запусти локальные проверки:

```bash
terraform init
terraform fmt -check -recursive
terraform validate
terraform test
```

Ожидаемый результат native-тестов:

```text
Success! 9 passed, 0 failed.
```

Войди в AWS и проверь активную учётную запись:

```bash
export AWS_PROFILE=YOUR_PROFILE
aws sso login --profile "$AWS_PROFILE"
aws sts get-caller-identity
```

Создай, проверь и примени сохранённый план:

```bash
terraform plan -out=tfplan
terraform show -no-color tfplan | less
terraform apply tfplan
```

Экспортируй значения для проверки:

```bash
export AWS_REGION="$(terraform output -raw aws_region)"
export FUNCTION_NAME="$(terraform output -raw function_name)"
export SOURCE_QUEUE_URL="$(terraform output -raw source_queue_url)"
export DLQ_URL="$(terraform output -raw dead_letter_queue_url)"
export MAPPING_UUID="$(terraform output -raw event_source_mapping_uuid)"
mkdir -p ../evidence
```

## 8. Проверка инфраструктурного контракта FIFO

Проверь атрибуты исходной очереди:

```bash
aws sqs get-queue-attributes \
  --region "$AWS_REGION" \
  --queue-url "$SOURCE_QUEUE_URL" \
  --attribute-names FifoQueue ContentBasedDeduplication RedrivePolicy \
  --query 'Attributes' \
  --output json

aws sqs get-queue-attributes \
  --queue-url "$DLQ_URL" \
  --attribute-names FifoQueue
```

Ожидаемые свойства:

```text
FifoQueue = true
ContentBasedDeduplication = false
RedrivePolicy указывает на FIFO DLQ

FifoQueue = true
```

Что именно это докажет:

```text
FifoQueue=true
  - source queue действительно FIFO

ContentBasedDeduplication=false
  - автоматическая deduplication по body отключена
  - producer обязан передавать MessageDeduplicationId

RedrivePolicy
  - source queue связана с DLQ

FifoQueue=true
  - DLQ_URL действительно FIFO
```

Проверь сопоставление источника событий:

```bash
aws lambda get-event-source-mapping \
  --region "$AWS_REGION" \
  --uuid "$MAPPING_UUID" \
  --query '{State:State,BatchSize:BatchSize,MaximumConcurrency:ScalingConfig.MaximumConcurrency,ResponseTypes:FunctionResponseTypes}' \
  --output table
```

Ожидаемые значения:

```text
State = Enabled
BatchSize = 5
MaximumConcurrency = 4
ResponseTypes содержит ReportBatchItemFailures
```

Здесь важно, что мы доказываем четыре разные вещи:

```text
Enabled
  - mapping активен

BatchSize = 5
  - до 5 records в Lambda batch

MaximumConcurrency = 4
  - ceiling = 4 concurrent invocations
  - НЕ обещание, что их всегда будет 4

ReportBatchItemFailures
  - Lambda mapping принимает partial batch response
```

## 9. Упражнение 1. Проверь порядок внутри одной группы

Отправь пять сообщений в одну группу:

```bash
../scripts/send-fifo-sequence.sh \
  "$SOURCE_QUEUE_URL" "$AWS_REGION" \
  group-a 5 1 0 ../evidence/group-a.json
```

Аргументы после региона означают:

```text
group-a -> MessageGroupId
5       -> число сообщений
1       -> продолжительность работы одного сообщения в секундах
0       -> запланированной ошибки нет
```

Дождись обработки и проверь журналы:

```bash
sleep 10
aws logs tail "/aws/lambda/${FUNCTION_NAME}" \
  --region "$AWS_REGION" \
  --since 10m \
  --format short | grep 'group-a' | grep 'work_completed'
```

Или отфильтруем конкретно этот `group_id` + `run_id` и проверим:

```bash
export RUN_ID="20261234T567890-12345"

aws logs tail "/aws/lambda/${FUNCTION_NAME}" \
  --region "$AWS_REGION" \
  --since 10m \
  --format short \
  | grep '"group_id": "group-a"' \
  | grep "$RUN_ID" \
  | grep '"event": "work_completed"'
```

Внутри этого запуска бизнес-последовательность должна завершиться так:

```text
1 -> 2 -> 3 -> 4 -> 5
```

При этом у каждой записи свой:

```text
message_id -> идентичность SQS message
task_id    -> конкретная задача нашего запуска
sequence   -> 1, 2, 3, 4, 5
request_id -> конкретный Lambda invocation
group_id   -> group-a
```

Не делай вывод о глобальном порядке по перемешанным потокам CloudWatch.
Сначала отфильтруй одну группу и ID заданий конкретного запуска.

### Упражнение 2. Проверь параллельность разных групп

Почти одновременно отправь две независимые группы:

```bash
../scripts/send-fifo-sequence.sh \
  "$SOURCE_QUEUE_URL" "$AWS_REGION" \
  group-parallel-a 3 1 0 ../evidence/group-parallel-a.json &
export GROUP_A_PID=$!

../scripts/send-fifo-sequence.sh \
  "$SOURCE_QUEUE_URL" "$AWS_REGION" \
  group-parallel-b 3 1 0 ../evidence/group-parallel-b.json &
export GROUP_B_PID=$!

wait "$GROUP_A_PID" "$GROUP_B_PID"
```

Проверь начало и завершение работы:

```bash
sleep 8

aws logs tail "/aws/lambda/${FUNCTION_NAME}" \
  --region "$AWS_REGION" \
  --since 10m \
  --format short | grep -E 'group-parallel-(a|b)' \
  | grep -E 'work_started|work_completed'
```

Ожидаемая модель:

```text
последовательность группы A сохраняется
последовательность группы B сохраняется
работа A и B может перекрываться
одновременных вызовов около 2, потому что активны только 2 группы
```

`MaximumConcurrency = 4` — только верхняя граница.
Она не создаёт четыре параллельных вызова, когда в очереди находятся две
активные группы.

```text
group A → максимум 1 активный invocation для этой группы
group B → максимум 1 активный invocation для этой группы

итого → до 2 concurrent invocations
```

### Упражнение 3. Проверь дедупликацию производителя

Создай свежий идентификатор и отправь с ним два разных тела:

```bash
export DEDUP_ID="dedup-$(date -u +%Y%m%dT%H%M%S)"

../scripts/send-dedup-pair.sh \
  "$SOURCE_QUEUE_URL" "$AWS_REGION" \
  group-dedup "$DEDUP_ID" ../evidence/dedup-pair.json
```

Скрипт сообщает о двух принятых API-запросах. Проверь сохранённые ответы SQS:

```bash
jq '.' ../evidence/dedup-pair.json
```

Затем найди идентификатор дедупликации в журналах:

```bash
sleep 8
aws logs tail "/aws/lambda/${FUNCTION_NAME}" \
  --region "$AWS_REGION" \
  --since 10m \
  --format short | grep "$DEDUP_ID"
```

Ожидаемый результат:

```text
два вызова SendMessage подтверждены
доставлено только задание task_id = dedup-first
задание task_id = dedup-second отсутствует

Оба SendMessage получили успешные ответы от SQS, и при этом у них:
 - одинаковый MessageId
 - одинаковый SequenceNumber
```

То есть SQS распознала второй запрос как дубль той же FIFO-операции в пределах
deduplication window.

### Упражнение 4. Проверь барьер после ошибки FIFO

Отправь три записи с запланированной ошибкой во второй позиции:

```bash
../scripts/send-fifo-sequence.sh \
  "$SOURCE_QUEUE_URL" "$AWS_REGION" \
  group-poison 3 0 2 ../evidence/group-poison.json

export RUN_ID="$(jq -r '.run_id' ../evidence/group-poison.json)"
```

Забираем логи эксперимента:

```bash
aws logs tail "/aws/lambda/${FUNCTION_NAME}" \
  --region "$AWS_REGION" \
  --since 30m \
  --format short \
  > ../evidence/group-poison-runtime.log
```

Локально фильтруем этот файл:

```bash
grep "$RUN_ID" ../evidence/group-poison-runtime.log
```

Нашли `request_id` первой попытки: `1ea1a12f-1234-123a-bfaf-c12ddd12345`

Локально:

```bash
grep '1ea1a12f-1234-123a-bfaf-c12ddd12345' \
  ../evidence/group-poison-runtime.log \
  > ../evidence/group-poison-first-attempt.log
```

Ожидаемое поведение первой попытки:

```text
sequence 1 -> completed
sequence 2 -> work_failed
sequence 3 -> work_deferred_after_failure
batchItemFailures -> messageId второй и третьей записи
```

Но ключевой момент: несмотря на то что sequence 3 сама исправна, в первой попытке
она не должна выполняться вообще.

Вторая и третья записи возвращаются вместе. Поэтому обе расходуют собственный
лимит получений и после его исчерпания могут попасть в FIFO DLQ. Тайм-аут
видимости равен 40 секундам, поэтому полная последовательность переноса может
занять несколько минут.

У нас `poison message`: `message_id = 1d12bfe1-123b-12bc-1aac-1234a0e12acf`

Повторные попытки `poison message`:

```bash
export POISON_MESSAGE_ID="1d12bfe1-123b-12bc-1aac-1234a0e12acf"

aws logs tail "/aws/lambda/${FUNCTION_NAME}" \
  --region "$AWS_REGION" \
  --since 30m \
  --format short \
  | grep "$POISON_MESSAGE_ID" \
  > ../evidence/group-poison-retries.log
```

В итоге сейчас:

```text
group-poison.json
  - что отправили

group-poison-first-attempt.log
  - failure barrier:
   1 success
   2 failed
   3 deferred
   batchItemFailures = 2 + 3

group-poison-retries.log
  - poison message повторяется
  - исправная sequence 3 остаётся отложенной и тоже возвращается
```

Наблюдай глубину очереди, не получая исходные сообщения:

```bash
watch -n 10 "aws sqs get-queue-attributes \
  --region '$AWS_REGION' \
  --queue-url '$SOURCE_QUEUE_URL' \
  --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible \
  --query 'Attributes' --output table"
```

После удаления возвращённого хвоста из исходной очереди группа разблокируется,
но уже отправленная `sequence 3` не завершится: при одинаковом числе получений она
может оказаться в DLQ вместе с `sequence 2`. Проверь глубину DLQ:

```bash
aws sqs get-queue-attributes \
  --region "$AWS_REGION" \
  --queue-url "$DLQ_URL" \
  --attribute-names ApproximateNumberOfMessages \
  --query 'Attributes.ApproximateNumberOfMessages' \
  --output text
```

Чтобы проверить все записи этого запуска в DLQ без удаления:

```bash
aws sqs receive-message \
  --region "$AWS_REGION" \
  --queue-url "$DLQ_URL" \
  --max-number-of-messages 10 \
  --visibility-timeout 0 \
  --attribute-names All \
  --message-attribute-names All \
  --output json > ../evidence/dlq-snapshot.json

jq --arg run "$RUN_ID" '
  .Messages[]?
  | (.Body | fromjson) as $body
  | select($body.task_id | contains($run))
  | {
      message_id: .MessageId,
      receive_count: .Attributes.ApproximateReceiveCount,
      group_id: .Attributes.MessageGroupId,
      task_id: $body.task_id,
      sequence: $body.sequence,
      should_fail: $body.should_fail
    }
' ../evidence/dlq-snapshot.json
```

Ожидаем увидеть `sequence 2` и `sequence 3`. При `maxReceiveCount = 3` значение
`ApproximateReceiveCount = 4` нормально: перенос выполняется, когда число
получений **превышает** настроенный предел. `receive-message` может вернуть меньше
записей, чем запрошено, поэтому при необходимости повтори снимок.

```text
2 -> реально падает
3 -> не выполняется из-за failure barrier
|
обе возвращаются через batchItemFailures
|
обе получают собственные ReceiveCount
|
обе могут исчерпать receive budget
|
обе -> FIFO DLQ
```

Теперь отправь новое исправное задание в ту же группу и убедись, что группа снова
обрабатывается:

```bash
../scripts/send-fifo-sequence.sh \
  "$SOURCE_QUEUE_URL" "$AWS_REGION" \
  group-poison 1 0 0 ../evidence/group-poison-after-dlq.json
```

После выполнения получи новый `run_id`:

```bash
export AFTER_DLQ_RUN_ID="$(jq -r '.run_id' ../evidence/group-poison-after-dlq.json)"

printf 'run_id=%s\n' "$AFTER_DLQ_RUN_ID"
```

Затем:

```bash
sleep 5

aws logs tail "/aws/lambda/${FUNCTION_NAME}" \
  --region "$AWS_REGION" \
  --since 10m \
  --format short \
  | grep '"group_id": "group-poison"' \
  | grep "$AFTER_DLQ_RUN_ID" \
  | grep -E 'work_started|work_completed'
```

Ожидаем:

```text
new sequence 1 -> work_started
new sequence 1 -> work_completed
```

Это доказывает разблокировку группы, но не восстановление старой `sequence 3`
Для записей из DLQ нужна отдельная проверяемая процедура восстановления.

Вызов получения изменяет метаданные попыток DLQ, хотя и не удаляет сообщение.
Не выполняй эту команду для активной исходной очереди.

## 10. Guardrails Terraform

### Guardrail 1. Отклони пакет FIFO больше десяти записей

```bash
terraform plan -var='batch_size=11'
```

Ожидаемый результат:

```text
batch_size must be an integer between 1 and 10 for an SQS FIFO source.
```

### Guardrail 2. Отклони лимит функции ниже лимита сопоставления

```bash
terraform plan \
  -var='event_source_maximum_concurrency=4' \
  -var='function_reserved_concurrency=3'
```

Ожидаемый результат:

```text
function_reserved_concurrency must be at least event_source_maximum_concurrency.
```

### Guardrail 3. Отклони опасный тайм-аут видимости

```bash
terraform plan \
  -var='function_timeout_seconds=6' \
  -var='queue_visibility_timeout_seconds=35'
```

Ожидаемый результат:

```text
queue_visibility_timeout_seconds must be at least six times the Lambda timeout.
```

Все три ошибки возникают до изменения инфраструктуры.

## 11. Разбор типовых проблем

### Сообщения одной группы выполняются параллельно

Убедись, что производитель (`producer`) действительно повторно использует один
`MessageGroupId`. Похожие задания в разных группах не имеют общей границы порядка.

### При высоком лимите сопоставления работает только один вызов

Посчитай активные группы. Одна перегруженная группа (`hot group`) допускает один активный
вызов Lambda для этой группы. Увеличивай число групп только тогда, когда бизнес-порядок
можно безопасно разделить.

### Второе сообщение с тем же ID всё равно появилось

Проверь, что обе отправки использовали точно одинаковый `MessageDeduplicationId`,
одну FIFO-очередь и произошли в пределах пяти минут. Сравнивать только поля тела
недостаточно.

### После ошибки обработались следующие записи

Убедись, что развёрнутый пакет содержит обработчик FIFO, а сопоставление включает
`ReportBatchItemFailures`. Обработчик должен выйти (`break`) после первой ошибки и вернуть
идентификаторы всех оставшихся записей.

### В DLQ попала исправная запись после проблемной

Это ожидаемо при `BatchSize > 1`, если обе записи были получены одним пакетом.
Обработчик вернул исправную запись как необработанную для сохранения порядка,
поэтому её `ApproximateReceiveCount` рос вместе со счётчиком проблемной записи.
Сравни `message_id`, `sequence`, `should_fail` и число получений в снимке DLQ.

Выбор зависит от контракта:

- установи `BatchSize > 1`, если важнее эффективность и процедура DLQ умеет
  отделять проблемную запись от исправного хвоста;
- установи `BatchSize = 1`, если DLQ должна изолировать только непосредственно
  ошибочную запись и снижение пакетной эффективности допустимо.

### Группа долго остаётся заблокированной

Проверь `work_failed`, число попыток получения, возраст старейшего сообщения и
глубину FIFO DLQ. Детерминированную проблемную запись нужно исправить или
изолировать: повышение одновременных вызовов не разблокирует её группу.

### Журналы CloudWatch выглядят перемешанными

Разные группы и среды выполнения пишут в разные потоки журналов. Отфильтруй
`group_id` и префикс `task_id` одного запуска. Порядок между группами не
гарантируется, поэтому его нельзя восстанавливать по общему времени появления строк.

### Последовательность диагностики

```text
определить group_id и run_id
-> проверить состояние сопоставления (`event source mapping`)
-> найти work_failed и work_deferred в журналах
-> проверить возраст и глубину исходной очереди
-> проверить глубину FIFO DLQ
-> исправить проблемное сообщение или обработчик
-> повторить обработку только по утверждённой процедуре восстановления
```

## 12. Стоимость и эксплуатационные границы

Лаборатория создаёт:

- одну функцию Lambda;
- одну исходную FIFO-очередь и одну FIFO DLQ;
- одно сопоставление источника событий;
- одну IAM-роль и встроенную политику;
- одну группу журналов CloudWatch;
- три сигнала тревоги CloudWatch.

Запросы FIFO, время работы Lambda, журналы, метрики и сигналы тревоги CloudWatch
могут стоить денег.

Для оценки мощности боевой системы учитывай:

```text
Какая бизнес-сущность определяет порядок?
Сколько активных групп бывает на пике?
Может ли одна группа стать перегруженной?
Как создаётся и хранится MessageDeduplicationId?
Какая граница идемпотентности защищает побочный эффект?
Как долго одна группа может оставаться заблокированной?
Кто утверждает повтор из DLQ и в каком порядке?
```

## 13. Проверка результата

Урок завершён, если:

- проходят 8 тестов Python;
- проходят 9 native-тестов Terraform;
- исходная очередь и DLQ относятся к FIFO;
- дедупликация по содержимому отключена;
- сопоставление использует `BatchSize = 5` и `MaximumConcurrency = 4`;
- одна группа завершается в порядке бизнес-последовательности;
- две группы сохраняют собственный порядок и работают с перекрытием;
- пара дублей приводит к доставке только одного задания;
- первая ошибка возвращает ошибочную и необработанные записи;
- проблемная и исправная отложенная записи могут вместе попасть в FIFO DLQ;
- новое исправное задание подтверждает, что после этого группа разблокирована;
- все три неверные конфигурации Terraform отклоняются;
- ты можешь объяснить, почему FIFO всё равно нужна идемпотентность.

## 14. Очистка

Дождись опустошения исходной очереди и проверь план удаления:

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

1. Порядок FIFO ограничен одним `MessageGroupId`.
2. Разные группы дают параллельность без нарушения порядка внутри группы.
3. Одну перегруженную группу нельзя ускорить только повышением `MaximumConcurrency`.
4. Идентификатор дедупликации подавляет дубли производителя (`producer`) на пять минут.
5. Дедупликация FIFO не заменяет идемпотентность потребителя.
6. `SequenceNumber` SQS -> транспортные метаданные, а не версия приложения.
7. Обработчик частичного ответа FIFO останавливается после первой ошибки.
8. Ошибочную и необработанные записи нужно вернуть вместе.
9. Каждая возвращённая необработанная запись расходует свой лимит получений и
   может попасть в DLQ вместе с проблемной записью.
10. `BatchSize = 1` точнее изолирует ошибку, а пакет больше одного эффективнее,
    но требует разбирать исправный хвост в DLQ.
11. Восстановление FIFO должно сохранять те же гарантии порядка, что обычная доставка.

## 16. Официальные источники

- [Основные термины очередей SQS FIFO](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/FIFO-key-terms.html)
- [Очереди SQS FIFO и одновременные вызовы Lambda](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/fifo-queue-lambda-behavior.html)
- [Настройка масштабирования Lambda для SQS](https://docs.aws.amazon.com/lambda/latest/dg/services-sqs-scaling.html)
- [Обработка ошибок SQS и частичный ответ Lambda](https://docs.aws.amazon.com/lambda/latest/dg/services-sqs-errorhandling.html)
- [Использование DLQ в Amazon SQS](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-dead-letter-queues.html)
- [Параметры сопоставления источника SQS](https://docs.aws.amazon.com/lambda/latest/dg/services-sqs-parameters.html)
- [Терминология exactly-once для SQS FIFO](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/FIFO-queues-exactly-once-processing.html)
