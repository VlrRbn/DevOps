# Урок 81. Идемпотентная Lambda с DynamoDB

## 1. Зачем нужен этот урок

В уроке 78 разобрали выполнение Lambda.
В уроке 79 отделили права вызывающей стороны от прав execution role.
Урок 80 показал, что при асинхронной обработке Lambda может повторить событие и что
повторная доставка нормальна для распределённых систем.

Теперь нужно ответить на вопрос:

> Как сделать так, чтобы Lambda не повторяла одно и то же бизнес-действие,
> когда событие приходит несколько раз?

```text
асинхронное событие доставлено
-> Lambda начала обработку
-> результат доставки оказался неопределённым или обработка завершилась ошибкой
-> то же событие доставлено повторно
```

В этом уроке добавим таблицу идемпотентности в DynamoDB. Функция использует условную
запись, чтобы один вызов получил право обрабатывать `idempotency_key`. Другой вызов
с тем же ключом не сможет одновременно войти в секцию обработки. Когда первый вызов
завершится, повторы получат сохранённый результат.

```text
повторная доставка
-> новый запуск Lambda
-> RequestId может быть новым или сохраниться при автоматической повторной попытке асинхронного вызова
-> новый owner_token для этой попытки выполнения handler
-> тот же `idempotency_key`
-> то же бизнес-действие не должно выполняться повторно
```

Задача — понять:

- от чего защищает идемпотентность;
- чего она не может гарантировать сама по себе;
- почему ключ является частью бизнес-контракта;
- как условная запись устраняет гонку check-then-act;
- зачем активному захвату (claim) нужны срок действия и владелец;
- почему DynamoDB TTL отвечает за очистку, а не за точное расписание.

## 2. Результаты урока

После урока ты сможешь:

- объяснить повторную доставку и идемпотентную обработку;
- отличить идентификатор вызова от бизнес-ключа идемпотентности;
- создать таблицу DynamoDB со строковым partition key и TTL;
- атомарно захватить ключ с помощью condition expression;
- вернуть сохранённый результат без повторного запуска бизнес-обработчика;
- отклонить повторное использование ключа с другой полезной нагрузкой;
- не дать старому воркеру завершить уже перехваченную запись;
- проверить запись с помощью строго согласованного чтения (strongly consistent read);
- объяснить проблему side-effect gap и более надёжные подходы для production-систем;
- локально протестировать автомат состояний без AWS.

Схема результата всего урока:

```text
понять повторную доставку
-> выбрать стабильный бизнес-ключ
-> атомарно создать IN_PROGRESS
-> выполнить бизнес-обработчик
-> безопасно записать COMPLETED
-> сохранить result_json
-> вернуть его при replay
-> объяснить side-effect gap
```
Схема связывающая результат урока с конкретным доказательством:

| Результат                              | Чем подтверждается                   |
| -------------------------------------- | ------------------------------------ |
| Claim создаётся атомарно               | `PutItem` и `ConditionExpression`    |
| Первый вызов обработан                 | `idempotency_status = PROCESSED`     |
| Повтор не запускает бизнес-обработчик  | `REPLAYED`, тот же `report_id`, логи |
| Результат сохранён                     | `result_json` в DynamoDB             |
| Старый воркер ограничен                | ошибка условного завершения          |
| Истёкший claim перехватывается         | новый `owner_token`                  |
| Ровно одно выполнение не гарантируется | объяснение side-effect gap           |

### 2.1. Словарь RU ↔ EN

| Английский термин | Как используем по-русски | Точный смысл в этом уроке |
|---|---|---|
| `consumer` | потребитель событий | Компонент, который принимает событие; в лаборатории эту роль выполняет Lambda |
| `worker` | воркер | Одна конкурирующая попытка выполнения Lambda |
| `handler` | handler Lambda | Точка входа `lambda_handler`, которая проверяет событие и управляет обработкой |
| `processor` | бизнес-обработчик | Функция бизнес-логики, запускаемая после успешного захвата ключа |
| `idempotency key` | ключ идемпотентности | Стабильный бизнес-ключ, связывающий повторные доставки одной операции |
| `claim` | захват права обработки | Атомарно созданная запись `IN_PROGRESS`, закрепляющая ключ за одним воркером |
| `replay` | возврат сохранённого результата | Ответ из записи `COMPLETED` без повторного запуска бизнес-обработчика |
| `payload hash` | хеш полезной нагрузки | Отпечаток входных данных для обнаружения повторного использования ключа с другим содержимым |
| `owner token` | токен владельца | Уникальный идентификатор воркера, которому принадлежит активный claim |
| `fencing token` | fencing-токен | Значение владельца, не позволяющее старому воркеру завершить перехваченный claim |
| `conditional write` | условная запись | Операция DynamoDB, выполняемая только при истинном `ConditionExpression` |
| `strongly consistent read` | строго согласованное чтение | Чтение DynamoDB, возвращающее все подтверждённые записи на момент запроса |
| `time to live (TTL)` | срок жизни записи | Атрибут для фонового удаления устаревших записей DynamoDB, а не точный таймер |
| `side-effect gap` | разрыв между внешним эффектом и записью результата | Окно сбоя после бизнес-действия, но до сохранения `COMPLETED` |
| `exactly-once` | ровно одно выполнение | Желаемая семантика, которую одна таблица идемпотентности полностью не гарантирует |

## 3. Ментальная модель

### 3.1. Повторная доставка — ожидаемое поведение

Повторы могут возникнуть, когда:

- отправитель не получил подтверждение и отправил событие снова;
- очередь повторно доставила сообщение;
- Lambda повторила неудачный асинхронный вызов;
- клиент повторил запрос после тайм-аута;
- оператор заново отправил событие;
- два отправителя передали одну бизнес-операцию.

Поэтому событие может прийти несколько раз, даже если все компоненты работают штатно.

Без идемпотентности:

```text
одно событие пришло дважды
-> бизнес-действие выполнено дважды
-> два письма, списания, тикета или деплоя
```

С записью идемпотентности:

```text
одна бизнес-операция доставлена дважды
-> первый вызов получает право обработки (claim)
-> выполняет обработку
-> сохраняет результат

повторный вызов
-> не выполняет действие заново
-> получает сохранённый результат
```

Лаборатория не запрещает повторные вызовы Lambda. Она контролирует бизнес-обработку
внутри этих вызовов:

```text
повторная доставка
-> одно событие доставлено повторно

повторный вызов Lambda
-> handler запущен ещё раз

повторное бизнес-действие
-> нежелательный эффект, который должна остановить идемпотентность
```

### 3.2. Idempotency key — это бизнес-ключ

Lambda `RequestId` обозначает один жизненный цикл вызова. Он полезен в журналах,
но не является стабильным идентификатором бизнес-операции, отправленной дважды.

Ключ идемпотентности должен отвечать на вопрос:

> Какую операцию нельзя выполнить дважды?

Примеры:

- `payment-order-847-attempt-1`;
- `invoice-2026-07-customer-42`;
- `provision-environment-request-9831`;
- стабильный ID события, который отправитель создал один раз.

В лаборатории используется событие:

```json
{
  "idempotency_key": "report-2026-08-customer-42",
  "customer_id": "customer-42",
  "report_date": "2026-08-01"
}
```

Контракт отправителя:

```text
отправитель создаёт idempotency_key один раз
-> сохраняет его
-> использует при всех повторных попытках той же операции
```

При повторе той же операции отправитель обязан передать тот же ключ. Если при
каждой попытке создавать новый случайный ключ, идемпотентность не сработает.

Сравнительная таблица:

| Идентификатор      | Что обозначает                                             | Основная задача   |
| ------------------ | ----------------------------------------------------------- | ----------------- |
| Lambda `RequestId` | Один жизненный цикл вызова; автоматическая повторная попытка может сохранить этот ID | Диагностика       |
| `idempotency_key`  | Одну бизнес-операцию                                        | Дедупликация      |
| `owner_token`      | Одну фактическую попытку выполнения handler                  | Проверка владельца claim |

### 3.3. Почему read-then-write небезопасен

Чтение и запись — две отдельные операции. Между ними другой воркер может
выполнить такую же проверку:

```text
время ----------------------------------------------------------->

Воркер A: GetItem(пусто) -------- обработка -------- PutItem
Воркер B:       GetItem(пусто) -------- обработка -------- PutItem
```

Оба воркера увидели отсутствие записи до того, как один из них успел её создать.

Поэтому лаборатория начинает с одного условного `PutItem`:

```text
attribute_not_exists(idempotency_key) OR expires_at < :now
```

DynamoDB атомарно проверяет условие и записывает элемент. Только одна из
конкурирующих попыток сможет создать действующий claim в этой неделимой операции.

Поэтому при одновременном вызове:

```text
воркер A
  -> conditional PutItem
  -> условие истинно
  -> claim создан

воркер B
  -> conditional PutItem
  -> условие уже ложно
  -> ConditionalCheckFailedException
```

Что именно гарантирует условная запись:

```text
гарантирует:
-> только один воркер успешно изменит элемент при данной проверке

не гарантирует:
-> что Lambda запустится только один раз
-> что внешний побочный эффект выполнится ровно один раз
-> что воркер, получивший claim, обязательно завершится
```

### 3.4. Состояние записи

Первый успешный claim сохраняет:

```text
idempotency_key = какую бизнес-операцию защищаем
status          = на каком этапе находится операция: IN_PROGRESS
payload_hash    = соответствуют ли данные исходной операции
owner_token     = UUID попытки выполнения handler, которая владеет claim
expires_at      = до какого момента claim считается активным
```

При каждом входе в handler лаборатория создаёт новый UUID для `owner_token`.
Lambda `RequestId` записывается в журналы отдельно: автоматическая повторная попытка асинхронного вызова
может сохранить один Request ID для нескольких запусков handler.

После успешной работы бизнес-обработчика владелец обновляет запись:

```text
status       = COMPLETED
result_json  = сохранённый бизнес-результат
expires_at   = срок хранения завершённой записи
```

Условие завершения проверяет:

```text
status = IN_PROGRESS
AND payload_hash = expected hash
AND owner_token = current execution attempt
```

Таблица состояний:

| `status`                     | Значение                               | Что делает повторный воркер       |
| ---------------------------- | -------------------------------------- | ------------------------------------- |
| Записи нет                   | Операция ещё не захвачена              | Пытается создать claim                |
| `IN_PROGRESS`, claim активен | Другой воркер выполняет операцию   | Получает ошибку «already in progress» |
| `IN_PROGRESS`, claim истёк   | Предыдущий воркер считается потерянным | Может перехватить claim               |
| `COMPLETED`                  | Результат уже сохранён                 | Возвращает `result_json`              |

Для чего нужен `owner_token`?

Представь, что воркер A завис, его claim истёк, а воркер B перехватил ключ.

```text
воркер A
-> получил claim
-> owner_token = A
-> завис

claim A истёк

воркер B
-> перехватил ключ
-> owner_token = B
-> начал новую обработку
```

Воркер A не должен позже продолжить работу и перезаписать результат B.

```text
воркер A
-> UpdateItem с условием owner_token = A

текущая запись
-> owner_token = B

результат
-> условие не выполнено
-> воркер A не может перезаписать запись B
```

Эта fencing-проверка защищает запись DynamoDB, но не останавливает воркер
A и не отменяет уже выполненное внешнее действие. Время жизни claim должно с
запасом превышать обычное время обработки.

Схема fencing-проверки:

```text
claim воркера A истёк
-> воркер B перехватывает ключ
-> owner_token становится B

воркер A продолжает работу
-> conditional completion проверяет owner_token = A
-> условие не проходит
-> результат B не перезаписан
```

### 3.5. Хеш полезной нагрузки

Один ключ идемпотентности не должен незаметно обозначать две разные операции.
Функция считает хеш канонической бизнес-нагрузки:

```text
customer_id + report_date
-> канонический JSON
-> SHA-256
-> payload_hash
```

`idempotency_key` отвечает: "Это та же операция?"

`payload_hash` проверяет: "Данные этой операции не изменились?"

Если ключ уже существует, но хеш отличается, функция выбрасывает `IdempotencyConflict`.

```text
тот же idempotency_key
+ другой payload_hash
-> это не replay
-> ключ использован для другой операции
-> IdempotencyConflict
```

Так ошибка отправителя становится заметной, а функция не возвращает результат от другого запроса.

Таблица решений:

| Сравнение               | Значение                     |
| ----------------------- | ---------------------------- |
| Ключ новый              | Можно пытаться создать claim |
| Ключ тот же, хеш тот же | Replay той же операции       |
| Ключ тот же, хеш другой | `IdempotencyConflict`        |

### 3.6. У TTL две задачи

В лаборатории один атрибут `expires_at` используется для двух периодов:

| Состояние записи | Что означает `expires_at` |
|---|---|
| `IN_PROGRESS` | когда другой воркер сможет перехватить брошенный claim |
| `COMPLETED` | сколько времени повторы смогут получить сохранённый результат |

`expires_at` для `IN_PROGRESS`

Когда воркер получает claim:

```text
status = IN_PROGRESS
expires_at = now + claim_ttl_seconds
```

Пока срок не истёк:

```text
status = IN_PROGRESS
+ expires_at > now
-> claim активен
-> другой воркер не получает право обработки
-> processing already in progress
```

Если срок истёк:

```text
status = IN_PROGRESS
+ expires_at < now
-> предыдущий воркер считается потерянным
-> новый воркер может попытаться перехватить claim
```

Схема перехвата:

```text
воркер A
-> создал IN_PROGRESS
-> expires_at = 1000
-> завис

текущее время = 1001
-> элемент всё ещё существует
-> expires_at < now

воркер B
-> conditional PutItem
-> условие проходит
-> owner_token заменяется на B
```

`expires_at` для `COMPLETED`

После успешной обработки значение меняется:

```text
status = COMPLETED
result_json = сохранённый результат
expires_at = now + record_ttl_seconds
```

Теперь `expires_at` определяет, сколько времени повторный запрос сможет получить replay:

```text
повтор до expires_at
-> запись COMPLETED существует
-> result_json возвращается
-> idempotency_status = REPLAYED
```

После окончания этого периода ключ снова может стать доступен для обработки.

```text
COMPLETED expires_at < now
-> окно идемпотентности закончилось
-> тот же ключ потенциально может быть захвачен заново
-> бизнес-действие может выполниться повторно
```

DynamoDB удаляет записи по TTL асинхронно. Истёкший элемент может оставаться видимым часы
или дни. Поэтому условие claim само считает запись с `expires_at < now` доступной для перехвата.
Функция не ждёт физического удаления записи службой TTL.

После истечения срока хранения завершённой записи тот же ключ можно будет
захватить и обработать заново. Поэтому `record_ttl_seconds` определяет окно
идемпотентности, а не только срок очистки хранилища.

| Параметр             | Для чего нужен                                                                  |
| -------------------- | ------------------------------------------------------------------------------- |
| `claim_ttl_seconds`  | Максимальное время владения активным claim                                      |
| `record_ttl_seconds` | Период, в течение которого завершённая операция защищена от повторной обработки |

### 3.7. Идемпотентность не равна exactly-once

Общая последовательность в production-среде выглядит так:

```text
создать claim IN_PROGRESS
-> выполнить внешнее действие
-> записать COMPLETED
```

Процесс может упасть после успешного вызова внешней системы, но до обновления DynamoDB.
После восстановления функция не сможет понять, произошло ли внешнее действие.

Это и есть **side-effect gap**.

```text
claim IN_PROGRESS
-> внешняя операция успешно выполнена
-> Lambda упала до UpdateItem(COMPLETED)
-> запись осталась IN_PROGRESS
-> claim истёк
-> другой воркер перехватил ключ
-> внешняя операция выполнена повторно
```

В зависимости от системы используют:

1. Сквозной ключ идемпотентности во внешней системе

Если внешний API поддерживает идемпотентность, ему передают тот же бизнес-ключ:

```text
Lambda idempotency_key
-> payment API idempotency key
```

При повторном вызове внешняя система сама распознаёт операцию:

```text
payment-order-847-attempt-1
-> первый запрос создаёт платёж
-> повтор возвращает результат того же платежа
```

Ключ должен оставаться стабильным через всю границу системы.

2. `DynamoDB transaction`

Когда и idempotency-запись, и бизнес-изменение находятся в DynamoDB, их иногда можно выполнить одной транзакцией:

```text
TransactWriteItems
-> изменить бизнес-запись
-> записать COMPLETED
```

Это помогает только тогда, когда все необходимые изменения находятся внутри поддерживаемой транзакционной границы DynamoDB.

3. `Outbox/inbox`

Изменение состояния и запись сообщения выполняются атомарно в одной системе хранения:

```text
бизнес-транзакция
-> обновить состояние
-> записать outbox event

отдельный воркер
-> доставить outbox event
```

Получатель может применять inbox-дедупликацию.

4. `Workflow с reconciliation`

Workflow хранит явные этапы и при неопределённом результате проверяет внешнюю систему:

```text
вызов внешней операции
-> результат неизвестен
-> запросить текущий бизнес-статус
-> продолжить, повторить или передать оператору
```

5. `Проверка бизнес-состояния`

Перед повторным действием система проверяет его реальный результат:

```text
claim истёк
-> проверить, существует ли уже платёж или отчёт
-> не повторять действие вслепую
```

В лаборатории `generate_report` детерминирован и не вызывает внешнюю систему.

Границы гарантий:

| Механизм                    | Что защищает                    | Чего не гарантирует              |
| --------------------------- | ------------------------------- | -------------------------------- |
| Conditional `PutItem`       | Единственного владельца claim   | Единственный внешний побочный эффект |
| `owner_token`               | Элемент DynamoDB от старого воркера | Остановку старого процесса |
| `COMPLETED` + `result_json` | Replay сохранённого результата  | Атомарность с внешним API        |
| DynamoDB TTL                | Очистку истёкших записей        | Точное время удаления            |
| Сквозной ключ идемпотентности | Дедупликацию во внешней системе | Общую распределённую транзакцию |

## 4. Архитектура лаборатории

```text
синхронный вызов через AWS CLI
        |
        v
Идемпотентный воркер Lambda
        |
        +--> условный PutItem(IN_PROGRESS)
        |
        +--> детерминированная генерация отчёта
        |
        +--> условный UpdateItem(COMPLETED)
        |
        +--> CloudWatch Logs и Errors alarm

DynamoDB в режиме on-demand:
partition key: idempotency_key;
TTL attribute: expires_at;
режим оплаты: PAY_PER_REQUEST.
```

Lambda выполняет три основных шага:

1. получить право обработки
2. выполнить бизнес-обработчик
3. сохранить завершённый результат

Execution role Lambda может выполнять только:

```text
logs:CreateLogStream
logs:PutLogEvents
dynamodb:GetItem
dynamodb:PutItem
dynamodb:UpdateItem
```

У неё нет `Scan`, `Query`, `DeleteItem`, прав на управление таблицей или
шаблонных разрешений `*` для ресурсов DynamoDB.

Схема полного взаимодействия:

```text
AWS CLI
  |
  | Invoke
  v
Lambda handler
  |
  | conditional PutItem
  v
DynamoDB: IN_PROGRESS
  |
  | бизнес-обработчик
  v
generate_report
  |
  | conditional UpdateItem
  v
DynamoDB: COMPLETED + result_json
  |
  v
Ответ Lambda: PROCESSED
```

Границы компонентов:

```text
AWS CLI
-> Инициирует и сохраняет доказательства вызова

Lambda
-> Проверка события и переходы автомата состояний

DynamoDB
-> Claim, состояние, fencing-проверка и сохранённый результат

CloudWatch
-> Хранит журналы и метрики ошибок

IAM
-> Ограничивает действия Lambda
```

## 5. Разбор реализации

### 5.1. Проверка события

Открой:

```bash
sed -n '1,34p' ../app/lambda_function.py
```

`parse_event` отклоняет данные, которые не являются объектом, и проверяет
обязательные бизнес-поля до создания claim.

Правильный порядок:

```text
получить event
-> проверить, что event является JSON-объектом
-> проверить обязательные бизнес-поля
-> только после этого обращаться к DynamoDB
```

Схема:

```text
event
  |
  v
parse_event
  |
  +-> event не объект --------> ошибка
  |
  +-> нет обязательного поля -> ошибка
  |
  v
валидные бизнес-данные
  |
  v
создание claim
```

### 5.2. Claim и replay

Открой:

```bash
sed -n '57,120p' ../app/lambda_function.py
```

Обрати внимание на:

- условный `put_item`;
- strongly consistent `get_item` после отклонённого claim;
- сравнение `payload_hash`;
- возврат сохранённого `result_json`;
- если запись не `COMPLETED` -> считаем её активной `IN_PROGRESS`.

```text
попытка создать claim
        |
        +-> PutItem успешен
        |   -> текущий воркер владеет операцией
        |   -> можно запускать бизнес-обработчик
        |
        +-> ConditionalCheckFailed
            -> запись уже существует
            -> прочитать её через strongly consistent GetItem
            -> определить replay, конфликт или активный claim
```

Таблица решений:

| Существующая запись          | Решение функции                              |
| ---------------------------- | -------------------------------------------- |
| `payload_hash` отличается    | `IdempotencyConflict`                        |
| `IN_PROGRESS`, claim активен | Ошибка `processing already in progress`      |
| `COMPLETED`, хеш совпал      | Вернуть `result_json` как `REPLAYED`         |
| Запись истекла               | Новый условный claim может её перехватить    |

### 5.3. Проверка владельца при завершении

Открой:

```bash
sed -n '122,153p' ../app/lambda_function.py
```

Особенно важна логика:

```text
бизнес-обработчик завершился
-> conditional UpdateItem
-> только текущий владелец завершает claim
```

Для завершающего обновления требуется исходный `owner_token`. В автомате состояний
этой лаборатории он выполняет роль fencing-проверки.

Поведения при отказе:

```text
любая часть ConditionExpression не совпала
-> DynamoDB отклоняет UpdateItem целиком
-> старый воркер не может изменить status, result_json или expires_at
```

## 6. Локальные проверки

Из корня репозитория:

```bash
python3 -m unittest discover \
  -s lessons/81-lambda-dynamodb-idempotency/lab_81/tests -v
```

Ожидаемый результат:

```text
Ran 12 tests

OK
```

Тесты доказывают, что:

- валидация происходит до claim;
- `payload_hash` стабилен;
- первый вызов сохраняет результат;
- replay не запускает бизнес-обработчик повторно;
- конфликт полезной нагрузки обнаруживается;
- активный claim блокирует другой воркер;
- истёкший claim перехватывается;
- ошибка бизнес-обработчика оставляет `IN_PROGRESS`;
- старый `owner_token` не может завершить перехваченный claim;
- каждый запуск handler получает новый UUID в качестве `owner_token`;
- повреждённый `result_json` отклоняется.

## 7. Проверка и развёртывание Terraform

```bash
cd lessons/81-lambda-dynamodb-idempotency/lab_81/terraform
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform fmt -check -recursive
terraform validate
terraform test
```

Четыре native-теста Terraform проверяют:

1. DynamoDB
-> строковый partition key
-> `PAY_PER_REQUEST`
-> TTL по `expires_at`

2. Lambda
-> получает точное имя таблицы
-> получает настройки claim TTL и record TTL

3. Наблюдаемость
-> срок хранения журналов ограничен
-> настроен alarm для ошибок

4. Переопределения TTL
-> допустимые значения передаются в переменные окружения функции

Перед чтением AWS-данных и созданием Terraform plan авторизуйся:

```bash
export AWS_PROFILE=YOUR_PROFILE
aws sso login --profile "$AWS_PROFILE"
aws sts get-caller-identity
```

Создай, проверь и примени сохранённый план:

```bash
terraform plan -out=tfplan
terraform show tfplan
terraform apply tfplan
```

Экспортируй значения созданных ресурсов:

```bash
export FUNCTION_NAME="$(terraform output -raw function_name)"
export TABLE_NAME="$(terraform output -raw idempotency_table_name)"
export AWS_REGION="$(terraform output -raw aws_region)"
export LOG_GROUP="/aws/lambda/${FUNCTION_NAME}"

printf 'function=%s\ntable=%s\nregion=%s\nlog_group=%s\n' \
  "$FUNCTION_NAME" "$TABLE_NAME" "$AWS_REGION" "$LOG_GROUP"
```

## 8. Первый вызов: claim и завершение

Цепочка доказательств первого вызова:

```text
Метаданные Invoke без FunctionError
-> handler завершился успешно

ответ = PROCESSED
-> вызов пошёл по ветке нового claim

DynamoDB status = COMPLETED
-> claim действительно завершён

result_json присутствует
-> результат сохранён для replay
```

Перейди в корень лаборатории:

```bash
cd ..
```

Вызови функцию синхронно:

```bash
./scripts/invoke-sync.sh \
  "$FUNCTION_NAME" \
  "$AWS_REGION" \
  events/report.json \
  evidence/first-metadata.json \
  evidence/first-response.json
```

Проверь оба файла:

```bash
jq . evidence/first-metadata.json
jq . evidence/first-response.json
```

Ожидаемая структура ответа:

```json
{
  "report_id": "12-character-id",
  "customer_id": "customer-42",
  "report_date": "2026-08-01",
  "status": "generated",
  "idempotency_status": "PROCESSED"
}
```

Успешный Invoke API докажет:

```text
AWS CLI
-> нашла Lambda
-> Lambda приняла синхронный вызов
-> handler завершился без необработанной ошибки
```

Точное значение `report_id` детерминировано ключом.

Проверь элемент в DynamoDB:

```bash
./scripts/inspect-record.sh \
  "$TABLE_NAME" \
  "$AWS_REGION" \
  report-2026-08-customer-42 \
  evidence/first-record.json
```

Выведи нужные поля:

```bash
jq '{
  idempotency_key: .Item.idempotency_key.S,
  status: .Item.status.S,
  payload_hash: .Item.payload_hash.S,
  owner_token: .Item.owner_token.S,
  expires_at: .Item.expires_at.N,
  result_json: (.Item.result_json.S | fromjson)
}' evidence/first-record.json
```

Ожидается:

```text
status = COMPLETED
result_json содержит один сохранённый бизнес-результат
```

## 9. Повторный вызов: replay

Ещё раз отправь то же событие:

```bash
./scripts/invoke-sync.sh \
  "$FUNCTION_NAME" \
  "$AWS_REGION" \
  events/report.json \
  evidence/replay-metadata.json \
  evidence/replay-response.json
```

Второй вызов должен пройти другой путь:

```text
conditional PutItem
-> ConditionExpression не выполнено
-> claim отклонён
-> strongly consistent GetItem
-> payload_hash совпал
-> status = COMPLETED
-> вернуть сохранённый result_json
-> idempotency_status = REPLAYED
```

Проверь ответ:

```bash
jq . evidence/replay-response.json
```

Ожидается:

```text
тот же report_id
idempotency_status = REPLAYED
```

Проверка метаданных и явное сравнение двух ответов:

```bash
jq -s '{
  first_report_id: .[0].report_id,
  replay_report_id: .[1].report_id,
  same_report_id: (.[0].report_id == .[1].report_id),
  first_status: .[0].idempotency_status,
  replay_status: .[1].idempotency_status
}' \
  evidence/first-response.json \
  evidence/replay-response.json
```

Второй вызов запустил handler, но не вызвал `generate_report` ещё раз. Функция
вернула сохранённый `result_json`.

Посмотри прикладные журналы:

```bash
aws logs tail "$LOG_GROUP" \
  --region "$AWS_REGION" \
  --since 10m \
  --format short
```

Найди:

```text
idempotency_claimed
idempotency_completed
idempotency_replay
```

Для этой последовательности должна быть одна пара claim/completion и один replay.
Это два отдельных синхронных вызова Invoke API, поэтому их `RequestId` должны
отличаться. Каждый запуск handler также получает собственный `owner_token`.

Полная цепочка доказательств replay:

```text
первый RequestId
-> idempotency_claimed
-> idempotency_completed
-> DynamoDB status = COMPLETED
-> result_json сохранён
-> ответ = PROCESSED

второй RequestId
-> idempotency_replay
-> тот же report_id
-> ответ = REPLAYED
```

## 10. Конфликтующая полезная нагрузка

`events/conflicting-report.json` намеренно использует тот же ключ, но другой `customer_id`.

Вызови функцию:

```bash
./scripts/invoke-sync.sh \
  "$FUNCTION_NAME" \
  "$AWS_REGION" \
  events/conflicting-report.json \
  evidence/conflict-metadata.json \
  evidence/conflict-response.json
```

AWS CLI может завершиться с кодом `0`, потому что сам Lambda Invoke API
сработал успешно. Проверь метаданные вызова:

```bash
jq . evidence/conflict-metadata.json
jq . evidence/conflict-response.json
```

Ожидается:

```text
FunctionError = Unhandled
errorMessage содержит "already used for another payload"
```

Это не безобидный повтор, а нарушение контракта отправителя. Ошибка должна оставаться заметной.

## 11. Практические упражнения

### Упражнение 1. Некорректное событие

Файл `events/invalid.json` не содержит обязательного поля `report_date`.

Отправь событие без `report_date`:

```bash
./scripts/invoke-sync.sh \
  "$FUNCTION_NAME" \
  "$AWS_REGION" \
  events/invalid.json \
  evidence/invalid-metadata.json \
  evidence/invalid-response.json

jq . evidence/invalid-metadata.json
jq . evidence/invalid-response.json
```

Ожидаемый поток:

```text
invalid event
-> parse_event обнаруживает отсутствие report_date
-> handler завершается ошибкой
-> conditional PutItem не вызывается
-> элемент DynamoDB не создаётся
```

Убедись, что:

- Lambda вернула `FunctionError`: Invoke API сработал, но код функции отклонил событие;
- запись для `report-invalid-001` не создана: ошибка возникла на этапе Python-валидации, а не в DynamoDB или IAM;
- проверка данных происходит до claim.

Проверь отсутствие записи:

```bash
./scripts/inspect-record.sh \
  "$TABLE_NAME" \
  "$AWS_REGION" \
  report-invalid-001 \
  evidence/invalid-record.json

jq '.Item // "record absent"' evidence/invalid-record.json
```

### Упражнение 2. Активный claim

Создай новое событие:

```bash
jq '.idempotency_key = "report-active-claim-001"' \
  events/report.json > /tmp/lab81-active.json
```

Вычисли канонический `payload_hash`: handler хеширует только `customer_id` и `report_date`:

```bash
payload_json="$(jq -cS '{customer_id,report_date}' /tmp/lab81-active.json)"
payload_digest="$(printf '%s' "$payload_json" | sha256sum | awk '{print $1}')"
now_epoch="$(date +%s)"
claim_expires_at="$((now_epoch + 300))"
```

Проверка локальных значений:

```bash
printf 'payload=%s\nhash=%s\nnow=%s\nexpires=%s\n' \
  "$payload_json" \
  "$payload_digest" \
  "$now_epoch" \
  "$claim_expires_at"
```

Добавь имитацию действующего claim:

```bash
aws dynamodb put-item \
  --table-name "$TABLE_NAME" \
  --region "$AWS_REGION" \
  --item "$(jq -cn \
    --arg key "report-active-claim-001" \
    --arg digest "$payload_digest" \
    --arg owner "simulated-other-worker" \
    --argjson now "$now_epoch" \
    --argjson expires "$claim_expires_at" \
    '{
      idempotency_key: {S: $key},
      status: {S: "IN_PROGRESS"},
      payload_hash: {S: $digest},
      owner_token: {S: $owner},
      created_at: {N: ($now | tostring)},
      updated_at: {N: ($now | tostring)},
      expires_at: {N: ($expires | tostring)}
    }')"
```

Прямая проверка элемента DynamoDB сразу после `put-item`:

```bash
./scripts/inspect-record.sh \
  "$TABLE_NAME" \
  "$AWS_REGION" \
  report-active-claim-001 \
  evidence/active-record-before-invoke.json
jq '{
  status: .Item.status.S,
  payload_hash: .Item.payload_hash.S,
  owner_token: .Item.owner_token.S,
  expires_at: .Item.expires_at.N,
  result_json: (.Item.result_json.S // null)
}' evidence/active-record-before-invoke.json
```

Отправь соответствующее событие:

```bash
./scripts/invoke-sync.sh \
  "$FUNCTION_NAME" \
  "$AWS_REGION" \
  /tmp/lab81-active.json \
  evidence/active-metadata.json \
  evidence/active-response.json

jq . evidence/active-metadata.json
jq . evidence/active-response.json
```

Ожидаемый поток:

```text
ручной PutItem
-> активный IN_PROGRESS уже существует

Lambda
-> conditional PutItem отклонён
-> strongly consistent GetItem
-> payload_hash совпал
-> status не COMPLETED
-> IdempotencyInProgress
-> бизнес-обработчик не запускается
```

Интерпретация:

```text
StatusCode = 200
-> Invoke API успешно вызвал Lambda

FunctionError = Unhandled
-> handler завершился ошибкой

processing already in progress
-> существующий payload_hash совпал
-> запись не была COMPLETED
-> Lambda не получила право обработки
```

| Шаг                     | Уровень                 | Что доказывает                           |
| ----------------------- | ----------------------- | ---------------------------------------- |
| Создание нового события | `jq` / локальный файл   | Используется отдельный `idempotency_key` |
| Расчёт хеша             | Shell / контракт Python | Хеш соответствует алгоритму handler      |
| `put-item`              | DynamoDB                 | Создан активный claim другого воркера |
| Метаданные Invoke       | Lambda Invoke API        | Handler завершился ошибкой               |
| Полезная нагрузка ответа | Python / Lambda         | Ошибка относится к активной обработке    |

Ожидается:

```text
FunctionError = Unhandled
processing already in progress
```

Второй воркер не должен обрабатывать событие одновременно.

Схема:

```text
имитация другого воркера
-> PutItem(IN_PROGRESS)
-> owner_token = simulated-other-worker
-> expires_at = now + 300

воркер Lambda
-> conditional PutItem
-> ConditionalCheckFailed
-> strongly consistent GetItem
-> payload_hash совпал
-> processing already in progress
```

### Упражнение 3. Перехват истёкшего claim

Схема:

```text
старый claim
-> status = IN_PROGRESS
-> expires_at < now
-> элемент всё ещё существует

новый вызов Lambda
-> conditional PutItem разрешён
-> owner_token заменяется
-> бизнес-обработчик выполняется
-> запись становится COMPLETED
```

Сделай созданную запись просроченной:

```bash
expired_epoch="$(( $(date +%s) - 1 ))"

aws dynamodb update-item \
  --table-name "$TABLE_NAME" \
  --region "$AWS_REGION" \
  --key '{"idempotency_key":{"S":"report-active-claim-001"}}' \
  --update-expression 'SET expires_at = :expired' \
  --expression-attribute-values \
    "{\":expired\":{\"N\":\"${expired_epoch}\"}}"
```

Физически существующий, но логически истёкший элемент можно перехватить,
не жди удаления через DynamoDB TTL. Сразу вызови функцию:

```bash
./scripts/invoke-sync.sh \
  "$FUNCTION_NAME" \
  "$AWS_REGION" \
  /tmp/lab81-active.json \
  evidence/reclaimed-metadata.json \
  evidence/reclaimed-response.json

jq . evidence/reclaimed-response.json
```

Ожидается:

```text
StatusCode = 200
idempotency_status = PROCESSED
```

Проверь нового владельца:

```bash
./scripts/inspect-record.sh \
  "$TABLE_NAME" \
  "$AWS_REGION" \
  report-active-claim-001 \
  evidence/reclaimed-record.json

jq '{
  status: .Item.status.S,
  owner: .Item.owner_token.S,
  expires_at: .Item.expires_at.N
}' evidence/reclaimed-record.json
```

Ожидается:

```text
status = COMPLETED
owner_token != simulated-other-worker
result_json сохранён
```

Владельцем больше не должен быть `simulated-other-worker`.

Ожидаемая цепочка:

```text
expires_at установлен в прошлое
-> старая запись физически осталась
-> новый conditional PutItem прошёл
-> новый воркер получил owner_token
-> бизнес-обработчик выполнился
-> status стал COMPLETED
-> result_json сохранён
```

### Упражнение 4. Объясни side-effect gap

Не ломай работающую функцию. Проанализируй последовательность:

```text
1. создать claim IN_PROGRESS
2. внешняя оплата прошла успешно
3. процесс упал до записи COMPLETED
4. claim истёк
5. другой вызов перехватил ключ
6. платёж может быть выполнен повторно
```

Схема:

```text
claim IN_PROGRESS
-> payment API: success
-> Lambda crash
-> COMPLETED не записан
-> expires_at < now
-> новый воркер получает claim
-> повторно вызывает payment API
```

`side-effect gap` — разрыв между успешным внешним действием и фиксацией его результата в DynamoDB.

Таблица неопределённых состояний:

| DynamoDB      | Внешняя система            | Что известно                      |
| ------------- | -------------------------- | --------------------------------- |
| `IN_PROGRESS` | Операция не выполнялась    | DynamoDB сама этого не доказывает |
| `IN_PROGRESS` | Операция успешно выполнена | Возможен side-effect gap          |
| `COMPLETED`   | Результат сохранён         | Локальный автомат состояний завершён |

Правильная модель:

- DynamoDB не знает о результате внешнего побочного эффекта;
- безусловное удаление claim может привести к повторному действию;
- во внешнюю систему должен передаваться тот же бизнес-ключ;
- неопределённый результат требует бизнес-сверки.

Границы механизмов:

```text
условный PutItem
-> защищает получение claim

owner_token
-> защищает элемент DynamoDB от старого воркера

оба механизма
!= доказывают состояние внешней оплаты
!= отменяют выполненный платёж
!= гарантируют exactly-once
```

Для внешнего API предпочтительна сквозная идемпотентность:

```text
бизнес-ключ Lambda
-> передать payment API как idempotency key
-> повторный запрос с тем же ключом
-> payment API возвращает результат прежней операции
```

## 12. Метрики и стоимость

Проверь alarm:

```bash
export ALARM_NAME="$(
  terraform -chdir=terraform output -raw function_errors_alarm_name
)"

aws cloudwatch describe-alarms \
  --region "$AWS_REGION" \
  --alarm-names "$ALARM_NAME" \
  --query 'MetricAlarms[0].[AlarmName,StateValue,StateReason]' \
  --output table
```

Интерпретация полей:

```text
AlarmName
-> проверяется нужный alarm лаборатории

StateValue
-> OK, ALARM или INSUFFICIENT_DATA

StateReason
-> почему CloudWatch установил текущее состояние
```

Упражнения с конфликтом и активным claim намеренно создают ошибки Lambda,
поэтому после публикации метрики alarm может перейти в `ALARM`.

### DynamoDB `PAY_PER_REQUEST`

Таблица использует режим оплаты `PAY_PER_REQUEST` — пропускная способность не резервируется заранее, а стоимость зависит от фактически выполненных операций чтения и записи.

Для этой лаборатории режим подходит, потому что нагрузка небольшая и нерегулярная:

```text
нет постоянной нагрузки
-> не нужно настраивать RCU/WCU
-> оплачиваются фактические запросы
```

Операции автомата состояний идемпотентности также потребляют ресурсы DynamoDB:

```text
первый вызов
-> PutItem(IN_PROGRESS)
-> UpdateItem(COMPLETED)

replay, конфликт или активный claim
-> отклонённый conditional PutItem
-> strongly consistent GetItem
```

На стоимость влияют:

- количество вызовов и повторных доставок;
- размер элемента DynamoDB, включая `result_json`;
- использование строго согласованных чтений;
- срок хранения завершённых записей;
- резервное копирование и межрегиональная репликация.

## 13. Разбор типовых проблем

### `No valid credential sources found`

Авторизуй тот же профиль, который используют Terraform и AWS CLI:

```bash
export AWS_PROFILE=YOUR_PROFILE
aws sso login --profile "$AWS_PROFILE"
aws sts get-caller-identity
```

### `AccessDeniedException` для DynamoDB

Эта ошибка означает:

```text
Lambda handler
-> попытался выполнить операцию DynamoDB
-> execution role не получила нужного разрешения
-> DynamoDB отклонила запрос
```

Проверь execution role функции и inline policy:

```bash
terraform -chdir=terraform output -raw function_execution_role_arn
terraform -chdir=terraform output -raw function_runtime_policy_name
```

Роли нужны операции над элементами для точного ARN таблицы.

### Повтор получает `IN_PROGRESS`

```text
воркер A
-> получил claim
-> status = IN_PROGRESS
-> ещё выполняет бизнес-обработчик

воркер B
-> conditional PutItem отклонён
-> прочитал IN_PROGRESS
-> processing already in progress
```

Возможные причины:

- первый вызов ещё работает;
- он упал после создания claim;
- claim TTL слишком велик для ожидаемого времени восстановления;
- обработка длится почти столько же или дольше, чем claim TTL.

Перед изменением или удалением записи проверь:

- сам элемент DynamoDB;
- время `expires_at`;
- `owner_token`;
- CloudWatch Logs первого воркера.

Используй скрипт для проверки:

```bash
./scripts/inspect-record.sh \
  "$TABLE_NAME" \
  "$AWS_REGION" \
  <IDEMPOTENCY_KEY> \
  evidence/in-progress-diagnostic-record.json
```

Для журналов точная команда:

```bash
aws logs tail "$LOG_GROUP" \
  --region "$AWS_REGION" \
  --since 60m \
  --format short
```

Если штатная обработка может длиться дольше claim, другой воркер сможет войти в бизнес-секцию.
`owner_token` не даст старому воркеру записать завершение, но не сможет отменить повторную внешнюю работу.

### Истёкший элемент всё ещё виден

Это нормальное поведение DynamoDB TTL. DynamoDB удаляет записи по TTL асинхронно. Приложение должно
само учитывать срок действия, а не полагаться на немедленное физическое удаление.

- `expires_at` -> логическое решение приложения
- DynamoDB TTL -> асинхронная физическая очистка

Схема:

```text
элемент существует
-> expires_at > now
   -> запись ещё действительна

-> expires_at < now
   -> запись логически истекла
   -> TTL может ещё не удалить её
   -> приложение применяет reclaim-логику
```

### Повтор завершается конфликтом

Сравни бизнес-данные. Один ключ был использован с разной полезной нагрузкой.

```text
тот же idempotency_key
+ другой payload_hash
-> функция считает запрос другой бизнес-операцией
```

Проблемный поток:

```text
первый запрос
-> key = report-2026-08-customer-42
-> payload = customer-42 + 2026-08-01
-> payload_hash = A
-> COMPLETED

повторный запрос
-> тот же key
-> изменён customer_id или report_date
-> payload_hash = B

A != B
-> IdempotencyConflict
```

Исправь контракт отправителя, а не обходи проверку `payload_hash`.

```text
это повтор той же операции
-> вернуть исходные бизнес-данные
-> использовать прежний idempotency_key

это новая операция
-> сформировать новый idempotency_key
```

Схема диагностики:

```text
получен IdempotencyConflict
-> сравнить полезную нагрузку первого и повторного события
-> определить, одна ли это бизнес-операция

да, одна
-> отправитель ошибочно изменил полезную нагрузку

нет, разные
-> отправитель ошибочно повторно использовал старый ключ
```

Таблица решений:

| Ситуация                                             | Правильное действие                             |
| ---------------------------------------------------- | ----------------------------------------------- |
| Повтор той же операции, данные случайно изменились   | Исправить отправителя и передать исходные данные |
| Новая операция использовала старый ключ              | Создать новый бизнес-ключ                       |
| Старый `result_json` не соответствует новому запросу | Не возвращать его                               |
| Хеш конфликтует из-за изменения важного поля         | Проверить состав канонической полезной нагрузки |

### Сохранённый результат не декодируется

Запись `COMPLETED` без корректного `result_json` повреждена или создана другой версией схемы.

Схема:

```text
claim rejected
-> GetItem
-> payload_hash совпал
-> status = COMPLETED
-> прочитать result_json

result_json корректен
-> REPLAYED

result_json отсутствует или повреждён
-> RuntimeError
-> старый результат не возвращается
-> бизнес-обработчик заново не запускается
```

### Alarm остаётся в `OK`

CloudWatch публикует метрики не мгновенно. Дождись окончания периода и проверь:

```bash
aws logs tail "$LOG_GROUP" \
  --region "$AWS_REGION" \
  --since 60m \
  --format short
```

Схема:

```text
конкретный Invoke
-> FunctionError = Unhandled

через некоторое время
-> Lambda Errors datapoint

CloudWatch alarm
-> сравнивает datapoint с threshold
-> OK или ALARM
```

## 14. Проверка результата

Перед очисткой убедись, что:

- проходят 12 локальных тестов Python;
- проходят 4 native-теста Terraform;
- первый вызов возвращает `PROCESSED`;
- повтор возвращает `REPLAYED` с тем же `report_id`;
- конфликт приводит к заметной ошибке функции;
- некорректное событие не создаёт запись;
- действующий claim блокирует другого воркера;
- истёкший claim можно перехватить до физического удаления через TTL;
- права IAM среды выполнения ограничены одной таблицей;
- ты можешь объяснить side-effect gap.

## 15. Очистка

Вернись в Terraform root:

```bash
cd terraform
```

Создай и проверь точный destroy plan:

```bash
terraform plan -destroy -out=tfplan-destroy
terraform show tfplan-destroy
terraform apply tfplan-destroy
```

Убедись, что state пуст:

```bash
terraform state list
```

Команда не должна вывести ресурсы под управлением Terraform.

## 16. Итоговая модель

Запомни:

1. Повторная доставка нормальна, поэтому потребитель событий должен быть идемпотентным.
2. Ключ обозначает бизнес-операцию, а не отдельный вызов.
3. Условный `PutItem` устраняет гонку read-then-write.
4. `payload_hash` защищает от небезопасного повторного использования ключа.
5. `owner_token` не даёт старому воркеру завершить перехваченный claim.
6. Strongly consistent read полезен сразу после отклонённого claim.
7. TTL — асинхронная очистка, а не точный таймер блокировки.
8. Таблица идемпотентности не делает внешний побочный эффект атомарным.

## 17. Официальные источники

- [Рекомендации AWS по Lambda](https://docs.aws.amazon.com/lambda/latest/dg/best-practices.html)
- [Condition expressions в DynamoDB](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/Expressions.OperatorsAndFunctions.html)
- [Read consistency в DynamoDB](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/HowItWorks.ReadConsistency.html)
- [DynamoDB TTL](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/TTL.html)
- [Работа с истёкшими элементами в DynamoDB](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/ttl-expired-items.html)
