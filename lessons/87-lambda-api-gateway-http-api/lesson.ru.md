# Урок 87: HTTP API через API Gateway и Lambda

## 1. Зачем нужен этот урок

В уроках 82–86 обработка была асинхронной т.е. отправитель передавал сообщение или
событие, а обработчик выполнял работу позже. Теперь клиент отправляет HTTP-запрос
и ждёт результат в том же соединении. Эта модель нужна для API, с которыми работают
сайты, приложения и внутренние инструменты.

```html
HTTP-клиент → API Gateway → Lambda → HTTP-ответ
```

Соберём небольшой API расчёта стоимости: клиент передаёт цену в центах и количество,
Lambda возвращает сумму.

Клиент держит соединение открытым и ожидает результат. Поэтому нужно различать:

- API Gateway не допустил запрос;
- API Gateway не смог вызвать Lambda;
- Lambda штатно отклонила входные данные;
- Lambda завершилась с исключением;
- клиент сам прервал ожидание по тайм-ауту.

Главный навык урока: проследить запрос от клиента до функции и понять, кто вернул ошибку.

```text
клиент сформировал HTTP-запрос:

- маршрут API Gateway найден
- авторизация маршрута пройдена
- API Gateway получил право вызвать Lambda
- Lambda обработала входные данные
- API Gateway сформировал HTTP-ответ
- клиент получил ожидаемый статус и body
```

## 2. Результаты урока

- Создать HTTP API, маршруты, интеграцию Lambda и stage через Terraform.
- Разобрать формат события `2.0` и собрать явный HTTP-ответ.
- Разделить права клиента, API Gateway и роли выполнения Lambda.
- Подписать запрос SigV4 через текущий AWS-профиль.
- Проверить положительные и отрицательные запросы.
- Найти один запрос в логах API Gateway и Lambda.
- Воспроизвести ошибку разрешения вызова и восстановить рабочую конфигурацию.
- Объяснить ограничения тайм-аутов, повторов и throttling.

В лаборатории мы подтвердим полный синхронный путь:

```text
HTTP request

- route
- AWS_IAM authorization
- Lambda integration
- HTTP response
- access log + Lambda log
```

### 2.1. Словарь RU ↔ EN

| По-русски | English term | Значение |
|---|---|---|
| HTTP API | HTTP API | Тип API Gateway, выбранный в лаборатории |
| маршрут | route | Сочетание метода и пути, например `POST /quotes` |
| интеграция | integration | Способ вызова Lambda для маршрута |
| этап развёртывания | stage | Настройки опубликованного API; здесь `$default` |
| синхронный вызов | synchronous invocation | Клиент ждёт ответ функции |
| формат события | payload format version | Контракт между API Gateway и Lambda |
| тело запроса/ответа | request/response body | Передаваемые данные HTTP |
| подпись запроса | SigV4 request signing | Подтверждение AWS-идентичности клиента |
| журнал доступа | access log | Запись API Gateway о запросе и результате |
| идентификатор запроса | request ID | Связь HTTP-ответа и записей в логах |
| ограничение частоты | throttling | Ограничение нагрузки с возможным ответом `429` |
| всплеск запросов | burst | Кратковременная нагрузка сверх обычного темпа |

## 3. Ментальная модель

### 3.1. HTTP API, маршрут, интеграция и stage

API Gateway предлагает HTTP API, REST API и WebSocket API. Здесь используется **HTTP API**
с ресурсами Terraform `aws_apigatewayv2_*`.
Это важно: HTTP API и REST API — разныепродукты API Gateway. Настройки `aws_api_gateway_*`
для REST API нельзя механически переносить в HTTP API.

Запрос проходит через три сущности:

```text
route -> integration -> Lambda
```

Route выбирается по методу и пути:

```text
GET  /health
POST /quotes
```

`auto_deploy = true` автоматически публикует изменения API в этой лаборатории.
Это удобство разработки, а не процедура согласования production-релиза.

Маршруты отличаются авторизацией:

```text
GET /health  -> NONE    -> публичный
POST /quotes -> AWS_IAM -> требуется SigV4
```

Integration определяет, какой backend вызвать. Оба маршрута используют одну Lambda
через proxy integration.

Stage публикует конфигурацию API. Здесь используется `$default`, поэтому URL выглядит так:

```text
https://API_ID.execute-api.REGION.amazonaws.com/health
```

Ментальная модель:

```text
route отвечает «какой запрос?»
integration отвечает «какой backend?»
stage отвечает «какая опубликованная конфигурация доступна клиенту?»
```

### 3.2. Что получает и возвращает Lambda

Клиент отправляет обычное HTTP-тело:

```json
{
  "unit_price_cents": 1250,
  "quantity": 3
}
```

Но Lambda получает не только это тело. API Gateway создаёт событие формата `2.0`:

```json
{
  "version": "2.0",
  "routeKey": "POST /quotes",
  "headers": {
    "content-type": "application/json"
  },
  "requestContext": {
    "requestId": "api-request-id",
    "http": {
      "method": "POST",
      "path": "/quotes"
    }
  },
  "body": "{\"unit_price_cents\":1250,\"quantity\":3}",
  "isBase64Encoded": false
}
```

Поле `body` здесь является строкой. Поэтому обработчик сначала разбирает envelope,
а затем отдельно декодирует JSON из `body`.

Если:

```json
"isBase64Encoded": true
```

обработчик сначала выполняет base64-декодирование, затем UTF-8 и только потом JSON parsing.

Файлы из `lab_87/events/` содержат полное событие API Gateway для локальных тестов.
Их нельзя отправлять клиентом как HTTP body. Клиентские тела находятся в `lab_87/requests/`.

Lambda возвращает proxy response:

```json
{
  "statusCode": 200,
  "headers": {
    "content-type": "application/json"
  },
  "body": "{\"currency\":\"EUR\",\"total_cents\":3750}",
  "isBase64Encoded": false
}
```

API Gateway преобразует эту структуру в настоящий HTTP-ответ:

```http
HTTP/1.1 200 OK
content-type: application/json

{"currency":"EUR","total_cents":3750}
```

Клиент не видит внешний объект с `statusCode` и `body`; он получает статус,
заголовки и декодированное содержимое `body`.

Ментальная модель:

```text
HTTP request

-> API Gateway event envelope
-> Lambda proxy response
-> HTTP response
```

### 3.3. Три разных набора прав

В запросе участвуют три субъекта, и каждому нужны свои разрешения.

| Кто         | Нужное право             | Где проверяется        |
| ------------|--------------------------|------------------------|
| HTTP-клиент | `execute-api:Invoke`     | IAM клиента            |
| API Gateway | `lambda:InvokeFunction`  | resource policy Lambda |
| Lambda      | запись в CloudWatch Logs | execution role Lambda  |

#### Клиент → API Gateway

Маршрут:

```text
POST /quotes
```

использует `AWS_IAM`. Клиент должен:

1. подписать запрос SigV4;
2. иметь IAM-разрешение `execute-api:Invoke` для этого route.

Право клиента напрямую вызывать Lambda здесь не помогает — клиент обращается к API Gateway.

Маршрут:

```text
GET /health
```

использует `NONE`, поэтому доступен без AWS-подписи.

#### API Gateway → Lambda

После успешной проверки клиента API Gateway должен получить отдельное разрешение:

```text
Principal = apigateway.amazonaws.com
Action    = lambda:InvokeFunction
```

Оно задаётся ресурсом `aws_lambda_permission` в resource policy функции и
ограничивается `source_arn` этого API.

#### Lambda → CloudWatch Logs

Execution role функции разрешает Lambda записывать собственные журналы.
Эта роль не авторизует HTTP-клиента и не даёт API Gateway право вызвать функцию.

Terraform выводит пример минимальной caller policy, но не прикрепляет её текущему
SSO-профилю. Для практики профиль уже должен иметь `execute-api:Invoke`.

Ментальная модель:

```text
IAM клиента    -> можно ли войти через защищённый route
policy Lambda  -> может ли API Gateway вызвать функцию
execution role -> что функция может делать после запуска
```

### 3.4. HTTP-статус и успешный вызов Lambda

| Результат | Кто обычно отвечает в этой лаборатории |
|---|---|
| `200` | Lambda вернула состояние или расчёт |
| `400` | Lambda отклонила некорректный JSON |
| `403` | API Gateway отклонил неподписанный/неразрешённый запрос |
| `404` | API Gateway не нашёл маршрут |
| `413` | Обработчик отклонил тело больше 4096 байт |
| `415` | Обработчик не получил `application/json` |
| `422` | JSON корректен, но параметры расчёта недопустимы |
| `429` | API Gateway ограничил частоту запросов |
| `500` | Например, API Gateway не получил право вызвать Lambda |
| `502` | Например, функция выбросила исключение или вернула неверный ответ |

Возврат `statusCode=422` не означает исключение Lambda: вызов завершился штатно,
а HTTP-клиент получил отказ по данным. Метрика Lambda `Errors` может оставаться
нулевой, пока в API появляются `4xx`.

Нужно также различать HTTP status и exit code клиента: `curl https://example/api`.

Обычный `curl` может завершиться с кодом `0`, даже если сервер вернул HTTP `500`.

Опция: `--fail-with-body` оставляет тело ошибки, но делает exit code ненулевым для
HTTP `4xx` и `5xx`.

Для диагностики одновременно проверяем:

- HTTP status и response body;
- access log API Gateway;
- Lambda log и метрику `Errors`.

### 3.5. Тайм-ауты и повторные запросы

Лаборатория задаёт:

```text
Момент запроса принимаем за `0 секунд`:

0 s                  6 s                  10 s                 15 s
│                    │                    │                    │
запрос отправлен     Lambda timeout       integration timeout  curl --max-time
                     функция остановлена  API Gateway          клиент прекращает
                     клиент получает 502  прекращает ожидание  ожидание
```

Это три независимых предела, а не последовательные стадии одного запроса.

Если Lambda работает дольше `6` секунд, Lambda останавливает выполнение. Функция
не возвращает корректный proxy response, поэтому API Gateway отвечает клиенту
`502 Bad Gateway`.

Предел API Gateway в `10` секунд в этом сценарии не достигается: Lambda уже
завершилась ошибкой на шестой секунде. Клиентский предел `15` секунд также не
достигается, потому что клиент раньше получает `502`.

Если бы интеграция оставалась активной дольше `10` секунд, уже API Gateway
прекратил бы ожидание. Если бы ответа не было дольше `15` секунд, `curl`
завершился бы по собственному тайм-ауту; это не HTTP-статус от API.

API Gateway не повторяет вызов Lambda автоматически при её ошибке. Здесь нет SQS, DLQ
и настроек асинхронных повторов из урока 80. Повтор решает выполнять клиент.

Тайм-аут клиента не доказывает, что сервер остановился: операция могла завершиться
после разрыва соединения. Для операций с записью нужен бизнес-ключ идемпотентности
из урока 81. Повторный расчёт безопасен, потому что ничего не записывает.

### 3.6. CORS и доступ из браузера

Короткая модель:

```text
CORS          = разрешение браузеру читать ответ
Authorization = разрешение серверу выполнить запрос
```

CORS действует только в браузере:

- JavaScript с другого origin может быть остановлен браузером;
- `curl`, Postman и серверные клиенты CORS не ограничивает;
- успешный CORS не даёт права вызвать защищённый маршрут;
- `POST /quotes` всё равно требует `AWS_IAM` и SigV4-подпись.

Например, frontend с `https://app.example.com`, обращаясь к API на другом origin,
может сначала отправить preflight-запрос `OPTIONS`. Разрешённый CORS позволит
JavaScript прочитать ответ, но не отменит авторизацию маршрута:

```text
CORS разрешён + авторизация успешна   -> запрос выполнен, ответ доступен JavaScript
CORS разрешён + авторизация отклонена -> API вернёт 401/403
CORS запрещён + API вернул ответ      -> браузер не отдаст ответ JavaScript
curl/Postman                          -> правила CORS не применяются
```

В лаборатории браузерного клиента нет, поэтому CORS не нужен.

Для пользовательского приложения отдельно проектируют авторизацию, например
JWT authorizer; не встраивают AWS секреты в браузер.

## 4. Архитектура лаборатории

```text
client
  -> HTTPS HTTP API / $default stage
     -> GET /health  (public)
     -> POST /quotes (AWS_IAM + SigV4)
        -> Lambda proxy integration, payload 2.0
           -> http-function execution role
              -> own CloudWatch Logs group

API access log: request ID, route, status, integration error
Lambda log:     API request ID, Lambda request ID, route, status
```

В лаборатории один HTTP API и одна Lambda, но два маршрута:

```text
GET /health   -> публичный -> Lambda
POST /quotes  -> AWS_IAM   -> Lambda
```

Оба маршрута используют:

- stage `$default`, поэтому в URL нет имени stage;
- Lambda proxy integration;
- payload format `2.0`;
- одну функцию, которая различает маршруты по `routeKey`.

Есть два независимых журнала:

- API Gateway access log показывает принятие запроса, выбранный маршрут,
HTTP-статус и ошибку интеграции;
- Lambda log показывает, была ли функция действительно запущена и как она
обработала запрос.

Один запрос связывается между слоями через API Gateway request ID:

```text
client
  <- response header: apigw-requestid

API Gateway access log
  requestId=<api-request-id>

Lambda event
  requestContext.requestId=<api-request-id>

Lambda log
  api_request_id=<api-request-id>
  lambda_request_id=<invocation-request-id>
```

`api_request_id` одинаков в API Gateway и Lambda.

`lambda_request_id` относится только к конкретному запуску функции.

Что доказывает каждый уровень:

```text
Клиент получил HTTP-ответ
→ API Gateway обработал запрос

Есть API access log
→ запрос достиг API Gateway и был классифицирован

Есть Lambda log с тем же API request ID
→ API Gateway действительно вызвал Lambda

Есть корректный status/body
→ Lambda сформировала ожидаемый бизнес-результат
```

Один только HTTP `200` ещё не объясняет весь путь — доказательство собирается
из ответа и двух журналов.

## 5. Разбор реализации

### 5.1. Функция и валидация

Ментальная модель функции:

```text
API Gateway event

-> проверить envelope версии 2.0
-> определить routeKey
-> прочитать и декодировать body
-> проверить бизнес-поля
-> выполнить расчёт
-> вернуть proxy response
```

`app/lambda_function.py` разделяет разбор события, проверку JSON, расчёт и
формирование ответа. `TypedDict` описывает ответ для редактора; проверки `isinstance`
и диапазонов работают во время выполнения.

Главные части кода:

- `HttpResponse` описывает ожидаемую форму ответа. Это подсказка анализатору типов, а не runtime-валидация.
- `as_object()` проверяет, что внешнее значение действительно является JSON-объектом.
- `read_json_body()` проверяет `Content-Type`, наличие тела, base64, UTF-8, JSON и лимит 4096 байт.
- `calculate_quote()` принимает строго два поля и считает сумму в центах.
- `response()` всегда сериализует `body` в строку — именно этого требует proxy integration.
- `lambda_handler()` выбирает обработку по `routeKey`.

Цена задана целым числом центов, чтобы не использовать округление `float`.

`True` отклоняется отдельно: в Python `bool` является подклассом `int`. Иначе такой JSON
мог бы пройти проверку:

```JSON
{"unit_price_cents": true, "quantity": 2}
```

Поля должны быть ровно `unit_price_cents` и `quantity`.

Программа принимает UTF-8 JSON, в том числе тело base64, и ограничивает его
4096 байтами. Это ограничение приложения, не изменение квоты API Gateway.

Ожидаемые ошибки данных становятся HTTP `4xx`. Неожиданные ошибки
пробрасываются наружу, а не превращаются в ложный `200`. Логи содержат
идентификаторы и результат, без полного события, заголовков авторизации и тела.

Важно различать ошибку HTTP-запроса и ошибку запуска Lambda:

| Ситуация                       | Результат Lambda               | HTTP-ответ |
|--------------------------------|--------------------------------|----------: |
| Нет JSON-тела                  | handler возвращает response    | `400`      |
| Неверный `Content-Type`        | handler возвращает response    | `415`      |
| Тело больше 4096 байт          | handler возвращает response    | `413`      |
| Неверные поля или диапазоны    | handler возвращает response    | `422`      |
| Нарушен envelope payload `2.0` | handler выбрасывает исключение | `502`      |
| Неожиданная ошибка программы   | handler выбрасывает исключение | `502`      |

Ответ `4xx` здесь является успешно выполненным invocation Lambda: функция сама
распознала ошибку клиента и сформировала HTTP-ответ. `502` означает, что корректный
proxy response от функции не был получен.

Важное разделение ошибок:

```text
RequestError
-> ожидаемая ошибка клиента
-> Lambda возвращает корректный proxy response
-> HTTP 400/413/415/422
-> Lambda invocation считается успешным

ValueError или другая неожиданная ошибка
-> исключение выходит из handler
-> Lambda invocation считается ошибочным
-> API Gateway возвращает 502
```

`GET /health` не читает тело. `POST /quotes` проходит полный цикл проверки.

### 5.2. Terraform и связи ресурсов

| Файл | Что искать |
|---|---|
| `http_api.tf` | API, интеграция, два маршрута, stage и журнал доступа |
| `api_invoke_permissions.tf` | Право API Gateway вызывать функцию по точным маршрутам |
| `function_execution_role.tf` | Trust policy через `aws_iam_policy_document` и право писать логи |
| `function.tf` | Функция, runtime, память и тайм-аут |
| `package.tf` | ZIP из одного Python-файла |
| `monitoring.tf` | Сигналы API `5xx` и Lambda `Errors` |
| `locals.tf` / `outputs.tf` | Имена, карта маршрутов и команды доступа |

Связи Terraform-ресурсов:

```text
local.routes
  ├─ health: GET /health, NONE
  └─ quotes: POST /quotes, AWS_IAM
       │
       ├─ aws_apigatewayv2_route.http
       │    └─ оба маршрута используют одну AWS_PROXY integration
       │
       └─ aws_lambda_permission.api_route
            └─ отдельный source ARN для каждого method/path

aws_apigatewayv2_integration.function
  └─ aws_lambda_function.http
       └─ aws_iam_role.function_execution
            └─ запись только в собственную CloudWatch log group
```

Главная цепочка Terraform:

```text
aws_apigatewayv2_api
  → aws_apigatewayv2_route
  → aws_apigatewayv2_integration
  → aws_lambda_function
```

#### `locals.tf`

`local.routes` — единый список маршрутов:

```hcl
routes = {
  health = { method = "GET",  path = "health", authorization = "NONE" }
  quotes = { method = "POST", path = "quotes", authorization = "AWS_IAM" }
}
```

Из него создаются:

- два `aws_apigatewayv2_route`;
- два точных `aws_lambda_permission`.

#### `http_api.tf`

`aws_apigatewayv2_api` создаёт сам HTTP API.

Одна integration используется обоими маршрутами:

```hcl
integration_type       = "AWS_PROXY"
integration_method     = "POST"
payload_format_version = "2.0"
```

Не путай два значения `POST`:

| Настройка            | Значение         | Что означает                                  |
|----------------------|------------------|-----------------------------------------------|
| `route_key`          | `POST /quotes`   | запрос клиента к HTTP API                     |
| `integration_method` | `POST`           | внутренний вызов Lambda Invoke API            |
| `GET /health`        | клиентский `GET` | внутри всё равно вызывает Lambda через `POST` |

`aws_apigatewayv2_stage.default`:

- использует `$default`, поэтому stage отсутствует в URL;
- автоматически публикует изменения через `auto_deploy`;
- задаёт общий throttling;
- отправляет access logs в отдельную log group.

#### `api_invoke_permissions.tf`

Для каждого маршрута создаётся отдельное разрешение:

```text
API + stage + method + path → lambda:InvokeFunction
```

Например:

```text
.../$default/POST/quotes
```

`$default` присутствует в permission ARN, хотя в публичном URL его нет.

#### Остальные файлы

- `package.tf` собирает Python-файл в ZIP.
- `function.tf` создаёт log group и Lambda.
- `function_execution_role.tf` разрешает функции писать только в собственный журнал.
- `monitoring.tf` создаёт отдельные сигналы для API `5xx` и Lambda `Errors`.

Это разные метрики: API может вернуть `5xx`, даже если Lambda вообще не была запущена.

### 5.3. Зачем нужен invoke-api.sh

Маршрут `POST /quotes` использует `AWS_IAM`, поэтому обычный неподписанный
`curl` получит HTTP `403`.

Скрипт выполняет следующую цепочку:

```text
AWS CLI credentials
→ SigV4-подпись
→ POST /quotes
→ сохранение status, headers и body
```

#### Получение credentials

Обычный `curl` не читает AWS-профиль или SSO-сессию. Скрипт получает временные
учётные данные командой:

```bash
aws configure export-credentials --format process
```

Временный `SessionToken` обязателен для credentials, полученных через SSO или STS.

Скрипт защищает учётные данные:

- `set +x` отключает shell tracing;
- `umask 077` ограничивает права создаваемых файлов;
- credentials передаются `curl` через stdin-конфигурацию, а не через аргументы;
- endpoint ограничен доменом `execute-api.amazonaws.com` нужного региона;
- после запроса переменные с credentials удаляются;
- redirects и автоматические повторы `POST` не используются.

Не запускай экспорт credentials вручную для публикации его вывода.

#### SigV4-подпись

```bash
--aws-sigv4 "aws:amz:$api_region:execute-api"
```

Здесь:

- `aws:amz` — схема подписи AWS SigV4;
- `$api_region` — регион API;
- `execute-api` — имя сервиса API Gateway.

#### Результаты запуска

Скрипт разделяет транспортный и HTTP-результат:

```text
curl exit code
  └─ результат выполнения запроса на стороне клиента

<prefix>.status.txt
  └─ HTTP-статус API Gateway

<prefix>.headers.txt
  └─ заголовки и идентификаторы ответа

<prefix>.body.json
  └─ результат приложения или сообщение об ошибке
```

Для HTTP `4xx` и `5xx` параметр `--fail-with-body` сохраняет тело ответа, но
`curl` возвращает ненулевой exit code, обычно `22`. DNS, TLS, соединение и
тайм-ауты имеют собственные коды `curl`.

Пример запуска из каталога `terraform`:

```bash
../scripts/invoke-api.sh \
  "$API_ENDPOINT" \
  "$AWS_REGION" \
  ../requests/quote.json \
  ../evidence/quote
```

Проверка сохранённых результатов:

```bash
cat ../evidence/quote.status.txt
cat ../evidence/quote.headers.txt
jq . ../evidence/quote.body.json
```

Ненулевой exit code сам по себе не объясняет причину: нужно проверить HTTP-status,
body и сообщение `curl`.

Скрипт намеренно не повторяет `POST`: потеря соединения не доказывает, что сервер
не успел обработать запрос.

## 6. Локальные проверки

Нужны Python 3.10+, Terraform `~> 1.14.0`, AWS CLI v2 с
`configure export-credentials`, `jq`, Bash, ShellCheck и curl 7.76+ с
`--aws-sigv4` и `--fail-with-body`.

Из корня репозитория:

```bash
python3 -m unittest discover \
  -s lessons/87-lambda-api-gateway-http-api/lab_87/tests -v
bash -n lessons/87-lambda-api-gateway-http-api/lab_87/scripts/invoke-api.sh
shellcheck lessons/87-lambda-api-gateway-http-api/lab_87/scripts/invoke-api.sh

cd lessons/87-lambda-api-gateway-http-api/lab_87/terraform
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform fmt -check -recursive
terraform validate
terraform test
```

Ожидается 19 локальных проверок Python/скрипта и 10 native-тестов Terraform.
Они не обращаются к ресурсам AWS: скрипт использует поддельные `aws/curl`,
а Terraform использует mock provider. `init` скачивает провайдеры.

## 7. Вход и развёртывание

Все последующие команды запускаются из `lab_87/terraform`.
Используй свой профиль вместо `YOUR_PROFILE`. Для SSO:

```bash
export AWS_PROFILE=YOUR_PROFILE
export AWS_REGION=eu-west-1
export AWS_PAGER=""
aws sso login --profile "$AWS_PROFILE"
aws sts get-caller-identity

terraform plan -out=tfplan
terraform show -no-color tfplan | less
terraform apply tfplan

export AWS_REGION="$(terraform output -raw aws_region)"
export API_ENDPOINT="$(terraform output -raw api_endpoint)"
export API_ID="$(terraform output -raw api_id)"
export FUNCTION_NAME="$(terraform output -raw function_name)"
export API_LOG_GROUP="$(terraform output -json log_group_names | jq -r '.api')"
export FUNCTION_LOG_GROUP="$(terraform output -json log_group_names | jq -r '.function')"
mkdir -p ../evidence
```

Профиль развёртывания должен уметь управлять API Gateway, Lambda, IAM, логами
и сигналами CloudWatch, включая передачу роли функции через `iam:PassRole`.

Для журнала доступа HTTP API прав роли Lambda недостаточно: при настройке нужны
права на доставку логов, в том числе `logs:CreateLogDelivery` и `logs:PutResourcePolicy`.

## 8. Проверка инфраструктурного контракта

Проверяем конфигурацию слоями, не одним общим утверждением:

```text
routes
→ integration
→ stage
→ Lambda resource policy
→ caller IAM policy
```

### 8.1. Маршруты и авторизация

```bash
aws apigatewayv2 get-routes \
  --api-id "$API_ID" \
  --region "$AWS_REGION" \
  --query 'Items[].{Route:RouteKey,Auth:AuthorizationType,Target:Target}' \
  --output table
```

Эта команда доказывает только:

- маршруты созданы в нужном API;
- `/health` публичный;
- `/quotes` требует IAM-авторизацию;
- маршруты связаны с integration.

### 8.2. Integration

```bash
aws apigatewayv2 get-integrations \
  --api-id "$API_ID" \
  --region "$AWS_REGION" \
  --query 'Items[].{
    Id:IntegrationId,
    Type:IntegrationType,
    Method:IntegrationMethod,
    Version:PayloadFormatVersion,
    Timeout:TimeoutInMillis
  }' \
  --output table
```

Integration настроена правильно если :

- `integrations/id` совпадает с target обоих маршрутов;
- `AWS_PROXY` означает Lambda proxy integration;
- `POST` — внутренний вызов Lambda;
- payload `2.0` определяет envelope события и формат ответа;
- timeout равен `10000` мс.

### 8.3. Stage $default

```bash
aws apigatewayv2 get-stage \
  --api-id "$API_ID" \
  --stage-name '$default' \
  --region "$AWS_REGION" \
  --query '{
    Stage:StageName,
    AutoDeploy:AutoDeploy,
    RateLimit:DefaultRouteSettings.ThrottlingRateLimit,
    BurstLimit:DefaultRouteSettings.ThrottlingBurstLimit,
    LogDestination:AccessLogSettings.DestinationArn,
    LogFormat:AccessLogSettings.Format
  }' \
  --output json
```

`Stage` должен соответствовать контракту:

- используется `$default`, поэтому URL не содержит `/dev` или другого stage;
- `AutoDeploy=true` автоматически публикует изменения;
- throttling настроен как 5 запросов/с с burst до 10;
- access logs направлены в отдельную группу `/aws/apigateway/lab87-dev-http-api`;
- формат содержит все пять диагностических полей.

### 8.4. Resource policy Lambda

```bash
aws lambda get-policy \
  --function-name "$FUNCTION_NAME" \
  --region "$AWS_REGION" \
  --query Policy \
  --output text |
jq '.Statement[] | {
  Sid,
  Effect,
  Principal,
  Action,
  Resource,
  SourceArn: .Condition.ArnLike."AWS:SourceArn",
  SourceAccount: .Condition.StringEquals."AWS:SourceAccount"
}'
```

Lambda resource policy правильная если:

- есть ровно два разрешения;
- principal — только `apigateway.amazonaws.com`;
- оба разрешения относятся к функции `lab87-dev-http-function`;
- `SourceAccount` ограничен твоим аккаунтом;
- `SourceArn` ограничены API;
- методы и пути заданы точно, без общего wildcard.

### 8.5. Пример caller policy

```bash
terraform output -json caller_policy_example | jq .
```

Эти проверки подтверждают конфигурацию ресурсов, но не runtime-путь:

```text
get-routes
  -> маршруты и типы авторизации настроены

get-integrations
  -> AWS_PROXY, payload 2.0 и timeout настроены

get-stage
  -> $default, auto deploy, throttling и назначение access log настроены

lambda get-policy
  -> API Gateway разрешено вызывать Lambda с точных маршрутов

terraform output caller_policy_example
  -> показан требуемый IAM-документ, но не доказано его прикрепление к caller
```

Полный runtime-путь будет доказан отдельно:

```text
client authorized
-> API Gateway accepted request
-> Lambda invoked
-> handler returned response
-> client received correct business result
```

## 9. Первый запрос и расчёт

### 9.1. Открытая проверка состояния

```bash
curl -sS --fail-with-body --connect-timeout 5 --max-time 15 \
  -D ../evidence/health.headers.txt \
  -o ../evidence/health.body.json \
  -w '%{http_code}\n' "$API_ENDPOINT/health"
jq . ../evidence/health.body.json
```

Ожидается HTTP `200`, `status: "ok"` и `request_id`.

### 9.2. Подписанный POST

```bash
../scripts/invoke-api.sh \
  "$API_ENDPOINT" \
  "$AWS_REGION" \
  ../requests/quote.json \
  ../evidence/quote

cat ../evidence/quote.status.txt
jq . ../evidence/quote.body.json
jq -e \
  '.total_cents == 3750 and
   .currency == "EUR" and
   .unit_price_cents == 1250 and
   .quantity == 3 and
   (.request_id | type == "string" and length > 0)' \
  ../evidence/quote.body.json
```

Вход: цена 1250 центов, количество 3. Ответ: 3750 центов, то есть 37,50 EUR.
Не ожидай `201 Created`: сохранённый ресурс здесь не создаётся.

Повтори вызов с префиксом `../evidence/quote-repeat`. Сумма останется прежней,
а `request_id` изменится. Это новый HTTP-запрос с таким же расчётом.

### 9.3. Связь ответа и логов

```bash
REQUEST_ID="$(jq -r '.request_id' ../evidence/quote-repeat.body.json)"

aws logs tail "$API_LOG_GROUP" \
  --since 10m \
  --region "$AWS_REGION" \
  --format short \
  > ../evidence/api.log

aws logs tail "$FUNCTION_LOG_GROUP" \
  --since 10m \
  --region "$AWS_REGION" \
  --format short \
  > ../evidence/function.log

printf 'REQUEST_ID=%s\n' "$REQUEST_ID"

printf '%s\n' '===== API Gateway ====='
rg -F "$REQUEST_ID" ../evidence/api.log

printf '%s\n' '===== Lambda ====='
rg -F "$REQUEST_ID" ../evidence/function.log
```

Ожидается:

- в API log — `request_id`, маршрут `POST /quotes` и статус `200`;
- в Lambda log — тот же `api_request_id`, маршрут `POST /quotes`, статус `200`;
- только в Lambda log будет отдельный `lambda_request_id`.

Сохраняй эти файлы локально: журналы могут содержать технические идентификаторы и
сообщения интеграции.

Для одного успешного запроса evidence связывается так:

| Уровень         | Поле                | Ожидаемое значение          |
|-----------------|---------------------|-----------------------------|
| Response body   | `request_id`        | общий API request ID        |
| Response header | `x-request-id`      | тот же API request ID       |
| Response header | `apigw-requestid`   | тот же API request ID       |
| API access log  | `request_id`        | тот же API request ID       |
| Lambda log      | `api_request_id`    | тот же API request ID       |
| Lambda log      | `lambda_request_id` | отдельный ID запуска Lambda |

Например:

```text
API request ID:    Dsvlzj0rjoEEJPw=
Lambda request ID: d40e964a-2de6-442d-b5ff-ceba4cf74ef3
```

Совпадение API request ID доказывает, что HTTP-ответ и записи двух журналов
относятся к одному запросу. `lambda_request_id` идентифицирует конкретный
запуск функции и не должен совпадать с API request ID.

Значение `integration_error: "-"` в access log означает, что API Gateway
не зарегистрировал ошибку интеграции.

Итог раздела:

```text
подписанный запрос принят

→ маршрут выбран
→ API Gateway вызвал Lambda
→ Lambda выполнила расчёт
→ API Gateway вернул ответ
→ клиент получил правильный результат
```

## 10. Ошибки клиента

### 10.1. Неподписанный запрос

Отправим тот же `POST /quotes`, но без SigV4:

```bash
rc=0

curl -sS --fail-with-body \
  --connect-timeout 5 \
  --max-time 15 \
  -H 'Content-Type: application/json' \
  --data-binary @../requests/quote.json \
  -D ../evidence/unsigned.headers.txt \
  -o ../evidence/unsigned.body.json \
  -w 'HTTP=%{http_code}\n' \
  "$API_ENDPOINT/quotes" || rc=$?

printf 'curl_exit=%s\n' "$rc"
cat ../evidence/unsigned.body.json
printf '\n'
rg -i '^(x-request-id|apigw-requestid):' \
  ../evidence/unsigned.headers.txt
```

Ожидается HTTP `403`, exit code `22`. API Gateway отклоняет запрос до
вызова функции. Успешный `/health` не доказывает доступ к `/quotes`.

Теперь докажем, что Lambda не запускалась. Новый запрос не нужен:

```bash
UNSIGNED_REQUEST_ID="$(
  awk '
    tolower($1) == "apigw-requestid:" {
      gsub("\r", "", $2)
      print $2
    }
  ' ../evidence/unsigned.headers.txt
)"

aws logs tail "$API_LOG_GROUP" \
  --since 10m \
  --region "$AWS_REGION" \
  --format short \
  > ../evidence/unsigned-api.log

aws logs tail "$FUNCTION_LOG_GROUP" \
  --since 10m \
  --region "$AWS_REGION" \
  --format short \
  > ../evidence/unsigned-function.log

printf 'REQUEST_ID=%s\n' "$UNSIGNED_REQUEST_ID"

printf '%s\n' '===== API Gateway ====='
rg -F "$UNSIGNED_REQUEST_ID" ../evidence/unsigned-api.log

printf '%s\n' '===== Lambda ====='
if rg -F "$UNSIGNED_REQUEST_ID" ../evidence/unsigned-function.log; then
  echo 'UNEXPECTED: Lambda была вызвана'
else
  echo 'EXPECTED: Lambda не была вызвана'
fi
```

### 10.2. Ошибка параметров и сломанный JSON

Файл `invalid-quote.json` синтаксически правильный, но `quantity` нарушает диапазон `1–100`.

```bash
rc=0

../scripts/invoke-api.sh \
  "$API_ENDPOINT" \
  "$AWS_REGION" \
  ../requests/invalid-quote.json \
  ../evidence/invalid-quote || rc=$?

printf 'script_exit=%s\n' "$rc"
printf 'HTTP='
cat ../evidence/invalid-quote.status.txt
jq . ../evidence/invalid-quote.body.json

rg -i '^(x-request-id|apigw-requestid):' \
  ../evidence/invalid-quote.headers.txt
```

Здесь ожидаемая модель другая:

```text
AWS_IAM пропустил запрос
-> API Gateway вызвал Lambda
-> Lambda распознала ошибку клиента
-> Lambda вернула корректный proxy response
-> клиент получил HTTP 422
```

`script_exit=22` означает только, что `curl --fail-with-body` получил HTTP `4xx`.
Это не код завершения Lambda.

Подтвердим нормальное выполнение handler по журналам:

```bash
INVALID_REQUEST_ID="$(
  jq -r '.request_id' ../evidence/invalid-quote.body.json
)"

aws logs tail "$API_LOG_GROUP" \
  --since 10m \
  --region "$AWS_REGION" \
  --format short \
  > ../evidence/invalid-quote-api.log

aws logs tail "$FUNCTION_LOG_GROUP" \
  --since 10m \
  --region "$AWS_REGION" \
  --format short \
  > ../evidence/invalid-quote-function.log

printf 'REQUEST_ID=%s\n' "$INVALID_REQUEST_ID"

printf '%s\n' '===== API Gateway ====='
rg -F "$INVALID_REQUEST_ID" ../evidence/invalid-quote-api.log

printf '%s\n' '===== Lambda ====='
rg -F "$INVALID_REQUEST_ID" ../evidence/invalid-quote-function.log
```

Следовательно:

```text
HTTP 422 ≠ ошибка запуска Lambda
HTTP 422 = штатный результат её валидации
```

### 10.3. Сломанный JSON

Теперь тело нарушает синтаксис JSON, а не бизнес-правила:

```bash
printf '{' > ../evidence/malformed.json

rc=0

../scripts/invoke-api.sh \
  "$API_ENDPOINT" \
  "$AWS_REGION" \
  ../evidence/malformed.json \
  ../evidence/malformed-response || rc=$?

printf 'script_exit=%s\n' "$rc"
printf 'HTTP='
cat ../evidence/malformed-response.status.txt
jq . ../evidence/malformed-response.body.json

rg -i '^(x-request-id|apigw-requestid):' \
  ../evidence/malformed-response.headers.txt

INVALID_REQUEST_ID="$(
  jq -r '.request_id' ../evidence/malformed-response.body.json
)"

aws logs tail "$API_LOG_GROUP" \
  --since 10m \
  --region "$AWS_REGION" \
  --format short \
  > ../evidence/malformed-response-api.log

aws logs tail "$FUNCTION_LOG_GROUP" \
  --since 10m \
  --region "$AWS_REGION" \
  --format short \
  > ../evidence/malformed-response-function.log

printf 'REQUEST_ID=%s\n' "$INVALID_REQUEST_ID"

printf '%s\n' '===== API Gateway ====='
rg -F "$INVALID_REQUEST_ID" ../evidence/malformed-response-api.log

printf '%s\n' '===== Lambda ====='
rg -F "$INVALID_REQUEST_ID" ../evidence/malformed-response-function.log
```

Сломанный JSON обработан правильно:

```text
HTTP=400
error=invalid_json
x-request-id = apigw-requestid
API log: status 400
Lambda log: request_completed, 400
```

### 10.4. Неизвестный маршрут

`POST /quotes` существует, но `GET /quotes` — это другой маршрут.

```bash
curl -sS -i --connect-timeout 5 --max-time 15 "$API_ENDPOINT/missing"
curl -sS -i --connect-timeout 5 --max-time 15 "$API_ENDPOINT/quotes"
```

Оба неизвестных route key отклонены API Gateway: `404`

В обоих ответах:
- есть `apigw-requestid` — запрос обработал API Gateway;
- нет `x-request-id` — ответ не формировала наша Lambda;
- `GET /quotes` не проходит проверку `AWS_IAM`, потому что защищён только существующий
маршрут `POST /quotes`;
- `$default` — имя stage, а не универсальный маршрут.

Ошибки возникают на разных уровнях:

| Запрос                           | HTTP  | Кто сформировал ответ | Lambda запущена        |
|----------------------------------|------:|-----------------------|------------------------|
| Неподписанный `POST /quotes`     | `403` | API Gateway           | нет                    |
| `POST /quotes` с `quantity: 0`   | `422` | Lambda                | да, завершилась штатно |
| `POST /quotes` со сломанным JSON | `400` | Lambda                | да, завершилась штатно |
| `GET /missing`                   | `404` | API Gateway           | нет                    |
| `GET /quotes`                    | `404` | API Gateway           | нет                    |

Признаки ответа API Gateway:

```text
apigw-requestid присутствует
x-request-id отсутствует
```

Признаки ответа обработчика:

```text
apigw-requestid присутствует
x-request-id присутствует
body.request_id совпадает с обоими заголовками
```

## 11. Упражнение на ошибку интеграции

Измени только этот переход:

```text
client → API Gateway              остаётся
route и integration               остаются
API Gateway → Lambda permission   временно удаляется
```

В `terraform.tfvars` должно оставаться `enable_api_invoke_permission = true`.
Значение через `-var` ниже действует только для команды, но применённое изменение
в AWS остаётся до восстановления.

```bash
terraform plan -var='enable_api_invoke_permission=false' -out=tfplan-deny
terraform show -no-color tfplan-deny | less
terraform apply tfplan-deny
```

В плане должны удаляться только две записи `aws_lambda_permission.api_route`.

Не должно изменяться ничего из этого:

```text
API Gateway
routes
integration
Lambda
IAM execution role
log groups
```

Затем проверь фактическую resource policy Lambda:

```bash
policy_rc=0

aws lambda get-policy \
  --function-name "$FUNCTION_NAME" \
  --region "$AWS_REGION" \
  --output json || policy_rc=$?

printf 'get-policy exit=%s\n' "$policy_rc"
```

Ожидается:

```text
ResourceNotFoundException:
The resource you requested does not exist.
get-policy exit=254
```

Здесь `ResourceNotFoundException` не означает отсутствие Lambda. Оно означает, что у
существующей функции больше нет resource-based policy: обе её записи были удалены.

Запрос при отсутствии permission:

```bash
rc=0

curl -sS --fail-with-body \
  --connect-timeout 5 \
  --max-time 15 \
  -D ../evidence/integration-denied.headers.txt \
  -o ../evidence/integration-denied.body.json \
  -w 'HTTP=%{http_code}\n' \
  "$API_ENDPOINT/health" || rc=$?

printf 'curl_exit=%s\n' "$rc"
jq . ../evidence/integration-denied.body.json

rg -i '^(x-request-id|apigw-requestid):' \
  ../evidence/integration-denied.headers.txt
```

Ожидается:

```text
HTTP=500
curl_exit=22
```

Тело должно быть общей ошибкой API Gateway:

```json
{
  "message": "Internal Server Error"
}
```

Заголовки:

```text
apigw-requestid присутствует
x-request-id отсутствует
```

Разница с предыдущими ошибками:

```text
403 → запрос остановлен авторизацией
404 → маршрут не найден
500 → маршрут и integration найдены, но API Gateway не может вызвать Lambda
```

Теперь докажем причину по access log и отсутствие запуска Lambda.

```bash
DENIED_REQUEST_ID="$(
  awk '
    tolower($1) == "apigw-requestid:" {
      gsub("\r", "", $2)
      print $2
    }
  ' ../evidence/integration-denied.headers.txt
)"

aws logs tail "$API_LOG_GROUP" \
  --since 10m \
  --region "$AWS_REGION" \
  --format short \
  > ../evidence/integration-denied-api.log

aws logs tail "$FUNCTION_LOG_GROUP" \
  --since 10m \
  --region "$AWS_REGION" \
  --format short \
  > ../evidence/integration-denied-function.log

printf 'REQUEST_ID=%s\n' "$DENIED_REQUEST_ID"

printf '%s\n' '===== API Gateway ====='
rg -F "$DENIED_REQUEST_ID" ../evidence/integration-denied-api.log

printf '%s\n' '===== Lambda ====='
if rg -F "$DENIED_REQUEST_ID" ../evidence/integration-denied-function.log; then
  echo 'UNEXPECTED: Lambda была вызвана'
else
  echo 'EXPECTED: Lambda не была вызвана'
fi
```

Ошибка интеграции доказана полностью:

```text
API Gateway принял GET /health
маршрут найден
integration выбрана
API Gateway не имеет permission вызвать Lambda
API Gateway вернул 500
Lambda не запускалась
```

Восстанови разрешения даже при неудачной демонстрации:

```bash
terraform plan -out=tfplan-restore
terraform show -no-color tfplan-restore | less
terraform apply tfplan-restore

curl -sS --fail-with-body \
  --connect-timeout 5 \
  --max-time 15 \
  -o ../evidence/restored-health.body.json \
  -w 'health HTTP=%{http_code}\n' \
  "$API_ENDPOINT/health"

../scripts/invoke-api.sh \
  "$API_ENDPOINT" \
  "$AWS_REGION" \
  ../requests/quote.json \
  ../evidence/restored-quote

printf 'quote HTTP='
cat ../evidence/restored-quote.status.txt

jq . ../evidence/restored-health.body.json
jq . ../evidence/restored-quote.body.json

plan_rc=0
terraform plan \
  -detailed-exitcode \
  -no-color \
  > ../evidence/final-plan.txt || plan_rc=$?

printf 'terraform_plan_exit=%s\n' "$plan_rc"
tail -n 5 ../evidence/final-plan.txt
```

Восстановление подтверждено:

```text
GET /health → HTTP 200
POST /quotes → HTTP 200
расчёт 1250 × 3 = 3750
оба запроса получили новые request_id
Terraform plan exit 0
остаточного drift нет
```

Controlled drift выполняется в четыре обязательных этапа:

```text
1. Ограниченный plan
   -> удаляются только две aws_lambda_permission

2. Демонстрация отказа
   -> API Gateway возвращает 500
   -> integration_error сообщает об отсутствии permission
   -> Lambda не запускается

3. Восстановление обычной конфигурацией
   -> enable_api_invoke_permission=true из terraform.tfvars
   -> обе permissions создаются заново

4. Финальная проверка
   -> GET /health возвращает 200
   -> POST /quotes возвращает 200
   -> terraform plan -detailed-exitcode возвращает 0
```

### Итог раздела

Эксперимент разделил два типа ошибок:

```text
Lambda permission отсутствует
-> API Gateway находит маршрут
-> API Gateway не может вызвать Lambda
-> клиент получает 500
-> integration_error содержит причину
-> Lambda log отсутствует
-> Lambda Errors расти не обязана
```

После восстановления:

```text
две permissions созданы заново
-> оба маршрута снова работают
-> финальный plan пуст
```

## 12. Ограничение нагрузки

В stage заданы rate `5` и burst `10` для каждого маршрута.

Ментальная модель:

- `burst=10` позволяет кратковременный всплеск;
- `rate=5` определяет скорость последующего пополнения доступной ёмкости;
- при превышении API Gateway может вернуть `429 Too Many Requests`.

Это ограничение API Gateway, а не Lambda concurrency и не финансовый лимит.

Эксперимент: отправь ровно `40` запросов к собственному `/health`.
Он может показать `429`, но не обязан: результат зависит от скорости запросов,
burst и лимитов аккаунта. Не увеличивай нагрузку бесконечно ради ожидаемой цифры.

```bash
for _ in {1..40}; do
  curl -sS --connect-timeout 5 --max-time 15 -o /dev/null \
    -w '%{http_code}\n' "$API_ENDPOINT/health"
done | sort | uniq -c
```

Если появится `429`, дай API восстановиться перед следующими проверками.
При настоящих повторах используют ограниченное число попыток, backoff и jitter.
Для POST сначала нужно знать, безопасен ли повтор операции.

Результат эксперимента интерпретируется только так:

| Результат                     | Что доказано                               |
|-------------------------------|--------------------------------------------|
| Присутствует `429`            | API Gateway фактически применил throttling |
| Все ответы `200`              | Эта серия запросов не вызвала throttling   |
| `get-stage` показывает `5/10` | Throttling сконфигурирован                 |

Все ответы `200` не доказывают отсутствие ограничения. Последовательные запросы
могут выполняться достаточно медленно, чтобы доступная ёмкость успевала
восстанавливаться.

Клиентская стратегия при `429`:

```text
ограниченное количество попыток
→ exponential backoff
→ случайный jitter
→ прекращение повторов после установленного предела
```

## 13. Разбор типовых проблем

| Симптом | Что проверить |
|---|---|
| Подписанный POST даёт `403` | IAM `execute-api:Invoke`, профиль, регион подписи, время компьютера и session token |
| URL с `/dev` возвращает `404` | Здесь stage `$default`, используй `api_endpoint` без суффикса |
| POST даёт `400/422` | Передавай `requests/quote.json`, не оболочку из `events/` |
| API даёт `500`, логи Lambda пусты | `get-policy`, `enable_api_invoke_permission`, `integration_error` |
| API даёт `502` | Исключение функции, runtime-логи и контракт proxy-ответа |
| Тело ответа пустое, HTTP `000` | DNS/TLS/сеть/тайм-аут; это не статус API |
| Нет журнала доступа | `get-stage`, ARN log group и права развёртывания на доставку логов |
| В браузере ошибка CORS | Это отдельная браузерная политика; `curl` не проверяет CORS |

Используй следующий порядок диагностики:

```text
1. curl показывает HTTP 000?
   └─ проверить DNS, TLS, сеть и клиентский timeout

2. Есть HTTP-ответ и apigw-requestid?
   └─ запрос достиг API Gateway

3. Есть x-request-id?
   ├─ да  → ответ сформировала Lambda
   └─ нет → ответ сформирован до обработчика

4. Есть API access log по request ID?
   └─ проверить status, route и integration_error

5. Есть Lambda log с тем же api_request_id?
   ├─ да  → анализировать handler и lambda_request_id
   └─ нет → проверять route, authorization и Lambda resource policy
```

Ограничения текущей лаборатории

- успешный health доказывает только работу `GET /health` в момент запроса;
- CloudWatch metrics приходят с задержкой;
- alarms созданы, но `alarm_actions` не настроены — уведомлений нет;
- это dev-конфигурация, а не готовая production-модель.

## 14. Проверка результата

- [ ] 19 локальных проверок и 10 native-тестов проходят.
- [ ] Видны два явных HTTP-маршрута и IAM-защита quotes.
- [ ] Health возвращает `200`; подписанный расчёт возвращает `3750`.
- [ ] Неподписанный POST возвращает `403`.
- [ ] Некорректные JSON/значения дают `400/422`.
- [ ] Неизвестный путь и неверный метод дают `404`.
- [ ] Один request ID найден в HTTP-ответе и обеих группах логов.
- [ ] Ошибка разрешения вызова воспроизведена и устранена.
- [ ] После восстановления оба маршрута работают, plan exit равен `0`.

## 15. Очистка

```bash
terraform plan -destroy -out=tfplan-destroy
terraform show -no-color tfplan-destroy | less
terraform apply tfplan-destroy
```

Проверь, что в state не осталось ресурсов:

```bash
terraform state list
```

## 16. Итоговая модель

Клиент проходит авторизацию маршрута. API Gateway должен отдельно получить право
вызвать Lambda. Функция выполняет расчёт и возвращает HTTP-контракт; API Gateway
передаёт его клиенту. Роль выполнения задаёт доступ самой функции к AWS.

Для диагностики сначала найди слой ошибки: сеть, маршрут, IAM клиента,
интеграция или обработчик. Затем свяжи HTTP-ответ и логи по request ID.

## 17. Официальные источники

- [HTTP API Lambda proxy integration and payload v2](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-develop-integrations-lambda.html)
- [HTTP API IAM authorization](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-access-control-iam.html)
- [IAM policy for invoking an API](https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-control-access-using-iam-policies-to-invoke-api.html)
- [Lambda errors through API Gateway](https://docs.aws.amazon.com/lambda/latest/dg/services-apigateway-errors.html)
- [HTTP API integration troubleshooting](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-troubleshooting-lambda.html)
- [HTTP API throttling](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-throttling.html)
- [HTTP API metrics](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-metrics.html)
- [AWS CLI credential export](https://docs.aws.amazon.com/cli/latest/reference/configure/export-credentials.html)
