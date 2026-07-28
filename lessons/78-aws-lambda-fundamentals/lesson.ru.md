# Урок 78. Основы AWS Lambda

## 1. Зачем нужен этот урок

Terraform-трек научил безопасно описывать, проверять и применять
инфраструктуру. Теперь начинаем отдельный трек по AWS Lambda и бессерверным
операциям.

Lambda - отдельная вычислительная модель, которой можно управлять через Terraform.

В этом уроке намеренно создадим только одну функцию:

```text
JSON event
    |
    v
AWS Lambda -> Python handler -> JSON response
    |
    v
CloudWatch Logs
```

Здесь пока нет API Gateway, SQS, EventBridge, VPC и CI. Если добавить их сразу,
будет трудно понять, какая часть системы отвечает за событие, выполнение кода,
ответ и журналы.

## 2. Результаты урока

После урока ты сможешь:

- объяснить, чем Lambda отличается от постоянно работающего EC2 instance;
- различать функцию, runtime, handler, event, context и execution environment;
- локально протестировать основную логику Python-функции;
- развернуть функцию и её execution role через Terraform;
- синхронно вызвать функцию через AWS CLI;
- найти invocation в CloudWatch Logs;
- отличить успешный вызов Lambda API от успешного выполнения handler;
- безопасно удалить ресурсы лаборатории.

## 3. Ментальная модель

### 3.1. Lambda не является сервером без имени

Для EC2 мы обычно думаем так:

```text
создать instance -> запустить процесс -> держать процесс работающим
```

Для Lambda модель другая:

```text
получить event -> подготовить execution environment -> вызвать handler ->
вернуть результат -> сохранить environment для возможного повторного использования
```

Ты не управляешь операционной системой и не поддерживаешь постоянно работающий
процесс. AWS управляет вычислительной средой, а ты отвечаешь за:

- код функции;
- runtime;
- память и timeout;
- IAM-права;
- источники событий;
- обработку ошибок и повторов;
- наблюдаемость;
- стоимость и concurrency.

### 3.2. Основные понятия

| Понятие | Что означает |
|---|---|
| Function | Настройки Lambda и развёрнутый код: `lab78-dev-hello`, его конфигурация и ZIP-архив с кодом |
| Runtime | Среда выполнения языка, например `python3.14` |
| Handler | Точка входа, которую вызывает Lambda: `lambda_function.lambda_handler` |
| Event | Входные данные вызова, например JSON с `"name": "Valerii"` |
| Context | Метаданные текущего вызова, например `aws_request_id` |
| Execution environment | Изолированная среда, в которой выполняется код |
| Invocation | Один запрос на выполнение функции |
| Execution role | IAM role, которую использует код функции; здесь она может писать логи в CloudWatch |

Для файла `lambda_function.py` и функции `lambda_handler` имя handler будет:

```text
lambda_function.lambda_handler
```

Первая часть указывает Python-модуль, вторая — функцию внутри него.

### 3.3. Event и context

При вызове Lambda AWS передаёт в handler два аргумента:

```python
def lambda_handler(event, context):
```

event — данные, с которыми нужно работать:

```json
{
  "name": "Valerii"
}
```

Python runtime преобразует JSON object в словарь `dict` и передаёт его первым аргументом
handler:

```python
def lambda_handler(event, context):
```

`context` создаёт AWS. В нём находятся, например:

- `aws_request_id`;
- имя и версия функции;
- ARN вызванной функции;
- оставшееся до timeout время.

В нашей функции берётся только request ID:

```python
request_id = getattr(context, "aws_request_id", "local")
```

Не нужно самостоятельно создавать настоящий context в AWS. В unit tests мы
используем небольшой тестовый объект context только для проверки логики.

### 3.4. Холодный и тёплый запуск

Когда приходит event, Lambda нужна среда, где будет работать Python-код.

Если готовой среды нет, AWS:

```text
создаёт execution environment
-> запускает runtime Python
-> импортирует код
-> вызывает handler
```

Это cold start. На первом вызове часто будет дополнительная задержка и в CloudWatch Logs может появиться `Init Duration`.

После вызова AWS не обязана сразу уничтожать среду. Она может оставить её и использовать повторно:

```text
следующий event
-> та же execution environment
-> сразу вызвать handler
```

Это warm invocation. Обычно он быстрее, потому что не нужно заново запускать runtime и импортировать модуль.

Но повторное использование не гарантировано. Поэтому нельзя делать так:

```python
last_user = "Valerii"  # надеяться, что переживёт следующий вызов
```

Память процесса может сохраниться, а может исчезнуть в любой момент. Для состояния нужны внешние хранилища: DynamoDB, S3, RDS, ElastiCache и так далее, в зависимости от задачи.

Код вне handler допустим для инициализации того, что можно безопасно переиспользовать: например HTTP client, SDK client или загруженная конфигурация. Но он не должен хранить критичное состояние конкретного пользователя.

### 3.5. Синхронный вызов имеет два результата

Когда выполняешь:

```bash
aws lambda invoke ...
```

происходит два разных этапа:

```text
1. AWS Lambda API принял запрос
2. Python handler обработал event
```

Они не равны.

Например, когда передал:

```json
{
  "name": 42
}
```

AWS Lambda нормально примет JSON и запустит функцию. Поэтому AWS CLI может завершиться с кодом `0`.

Но внутри handler будет:

```python
name = event.get("name", "world")
message = build_greeting(name)
```

А `build_greeting(42)` выбросит:

```text
ValueError: name must be a string
```

То есть:

```text
AWS CLI exit code = 0
FunctionError = Unhandled
handler execution = failed
```

Для автоматизации недостаточно проверить только `$?`. Нужно отдельно проверить metadata ответа Lambda:

```json
{
  "StatusCode": 200,
  "FunctionError": "Unhandled"
}
```

`StatusCode: 200` здесь означает: Lambda API обработал запрос.  
`FunctionError: Unhandled` означает: Python-код завершился исключением.

## 4. Код функции

Открой:

```text
lab_78/app/lambda_function.py
```

Код разделён на две части:

- `build_greeting()` содержит обычную бизнес-логику;
  - принимает строку;
  - отбрасывает пробелы по краям;
  - не принимает пустую строку;
  - возвращает приветствие.
- `lambda_handler()` адаптирует Lambda event и context к этой логике.
  - берёт name из входного event
  - передаёт его в основную логику
  - берёт request ID от Lambda
  - берёт environment из configuration
  - возвращает JSON-совместимый Python dict

Так основную логику можно тестировать без AWS и Lambda runtime.
Handler считает `event` недоверенными входными данными и до вызова `.get()`
проверяет, что верхний уровень JSON является object.

Функция не пишет весь event в журнал. Event может содержать токены, персональные
данные или другие чувствительные значения. Вместо этого журнал содержит только
заранее выбранные поля.

## 5. Локальные тесты

Из каталога урока выполни:

```bash
python3 -m unittest discover -s lab_78/tests -v
```

Тесты проверяют:

- обычное имя;
- значение по умолчанию;
- неверный тип;
- пустое имя;
- event, который не является object;
- форму ответа handler.

Это не эмуляция AWS Lambda. Unit tests проверяют код, но не доказывают, что IAM,
ZIP package, runtime и CloudWatch настроены правильно. Для этого далее будет
реальное развёртывание.

## 6. Terraform-лаборатория

Перейди в каталог:

```bash
cd lessons/78-aws-lambda-fundamentals/lab_78/terraform
```

Создай локальный файл параметров:

```bash
cp terraform.tfvars.example terraform.tfvars
```

До `plan` выбери аутентифицированный AWS profile. Например, для AWS IAM
Identity Center (SSO):

```bash
export AWS_PROFILE=aws-sso-admin
aws sso login --profile "$AWS_PROFILE"
aws sts get-caller-identity
```

Замени `aws-sso-admin` на имя своего profile. Если profile не использует SSO,
выполни предусмотренную для него аутентификацию и всё равно проверь caller
identity. Затем проверь `aws_region` и выполни:

```bash
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan -out=tfplan
```

`terraform init`, форматирование и `validate` могут работать без AWS credentials.
`terraform plan` не может: AWS provider должен аутентифицироваться и прочитать
текущее состояние ресурсов в AWS, прежде чем построить полный plan.

### 6.1. Что создаёт Terraform

В `main.tf` описаны четыре AWS-ресурса и два вспомогательных data source.

Сначала Terraform собирает ZIP:

```hcl
data "archive_file" "function" {
  type        = "zip"
  source_file = "../app/lambda_function.py"
  output_path = ".terraform/lambda_function.zip"
}
```

`archive_file` ничего не создаёт в AWS. Он локально упаковывает Python-файл в
пакет развёртывания.

Дальше создаётся trust policy:

```hcl
data "aws_iam_policy_document" "lambda_trust"
```

Она отвечает на вопрос:

```text
Кто может принять эту IAM role?
```

Ответ: сервис `lambda.amazonaws.com`.

На основании этой policy создаётся:

```hcl
resource "aws_iam_role" "lambda"
```

Это execution role функции. AWS Lambda принимает её во время запуска handler.

Отдельно создаётся CloudWatch log group:

```hcl
resource "aws_cloudwatch_log_group" "function"
```

Имя будет:

```text
/aws/lambda/lab78-dev-hello
```

Затем создаётся узкая IAM policy:

```hcl
resource "aws_iam_role_policy" "logs"
```

Она разрешает только:

```text
logs:CreateLogStream
logs:PutLogEvents
```

И только внутри log group этой функции. `logs:CreateLogGroup` не нужен, потому что log group заранее создаёт Terraform.

Последний AWS-ресурс:

```hcl
resource "aws_lambda_function" "hello"
```

Он связывает:

```text
ZIP + runtime + handler + execution role + environment variables
```

В `depends_on` явно указано, что log group и log policy должны быть готовы до создания функции. Это уменьшает риск первого запуска без нужного места или прав для журналов.

| Ресурс | Назначение |
|---|---|
| `archive_file.function` | Создаёт ZIP-архив из Python-файла |
| `aws_iam_role.lambda` | Trust policy разрешает сервису Lambda использовать role |
| `aws_iam_role_policy.logs` | Разрешает писать только в log group этой функции |
| `aws_cloudwatch_log_group.function` | Хранит журналы ограниченное время |
| `aws_lambda_function.hello` | Код и настройки функции |

Важно: здесь используется локальный Terraform state.

### 6.2. Почему нужен `source_code_hash`

Terraform не анализирует Python-код внутри ZIP как инфраструктурный ресурс.
`source_code_hash` связывает содержимое архива с `aws_lambda_function`.

Когда код меняется:

```text
Python file -> новый ZIP hash -> Terraform видит update function code
```

Без hash можно получить ситуацию, когда код изменён, а Terraform не планирует
обновление функции. `source_code_hash` решает именно локальную задачу: связывает подготовленный Terraform архив с функцией.

### 6.3. Execution role и caller identity

Не путай две identity:

- твоя AWS CLI profile / SSO role / CI role создаёт и вызывает функцию;
- Lambda execution role использует Python-код во время выполнения.

```text
твоя identity
    |
    | создаёт и вызывает функцию
    v
Lambda service
    |
    | принимает execution role
    v
Python handler
    |
    | CreateLogStream / PutLogEvents
    v
CloudWatch Logs
```

Execution role этой лаборатории не может создавать EC2, читать S3 или получать
секреты. Она может только писать журналы своей функции.
  - trust policy определяет, кто может принять role;
  - permissions policy определяет, что разрешено делать после принятия role.

### 6.4. Защитные ограничения

В лаборатории заданы:

- `timeout = 5`;
- `memory_size = 128`;
- reservation concurrency по умолчанию не задан;
- log retention — 7 дней;
- архитектура `arm64`;
- нет публичного endpoint;
- нет VPC.

Значения ограничивают стоимость и радиус воздействия учебной функции.

## 7. Развёртывание

Перед применением ещё раз проверь текущую identity:

```bash
aws sts get-caller-identity
```

Примени сохранённый план:

```bash
terraform apply tfplan
```

Посмотри outputs:

```bash
terraform output
```

## 8. Первый вызов

Выполни из каталога `lab_78/terraform`:

```bash
aws lambda invoke \
  --region "$(terraform output -raw aws_region)" \
  --function-name "$(terraform output -raw function_name)" \
  --cli-binary-format raw-in-base64-out \
  --payload fileb://../events/hello.json \
  ../evidence/invoke-success-response.json \
  | tee ../evidence/invoke-success-metadata.json
aws_cli_exit_code=${PIPESTATUS[0]}
echo "aws_cli_exit_code=$aws_cli_exit_code"
```

Проверь отдельно метаданные и ответ функции:

```bash
jq . ../evidence/invoke-success-metadata.json
jq . ../evidence/invoke-success-response.json
```

Ожидаемый смысл ответа:

```json
{
  "message": "Hello, Valerii!",
  "environment": "dev",
  "request_id": "..."
}
```

`request_id` будет отличаться при каждом invocation.

## 9. CloudWatch Logs

Посмотри последние записи:

```bash
aws logs tail "$(terraform output -raw log_group_name)" \
  --region "$(terraform output -raw aws_region)" \
  --since 10m \
  --format short
```

Там должны быть:

```text
START RequestId: ...
{"event": "greeting_created", ...}
END RequestId: ...
REPORT RequestId: ...
```

START, END и REPORT добавляет Lambda runtime.
greeting_created добавляет Python logger.

`Init Duration` может отсутствовать при тёплом вызове, это не ошибка: Lambda могла использовать уже подготовленную execution environment.

## 10. Отрицательное упражнение

Вызови функцию с неверным типом `name: 42`:

```bash
aws lambda invoke \
  --region "$(terraform output -raw aws_region)" \
  --function-name "$(terraform output -raw function_name)" \
  --cli-binary-format raw-in-base64-out \
  --payload fileb://../events/invalid-name.json \
  ../evidence/invoke-error-response.json \
  | tee ../evidence/invoke-error-metadata.json
aws_cli_exit_code=${PIPESTATUS[0]}
echo "aws_cli_exit_code=$aws_cli_exit_code"
```

`PIPESTATUS[0]` сохраняет exit code AWS CLI из pipeline. Обычный `$?` показал бы
только результат `tee`. Теперь проверь оба результата вызова Lambda:

```bash
jq . ../evidence/invoke-error-metadata.json
jq . ../evidence/invoke-error-response.json
```

Обрати внимание:

- AWS CLI, вернул `0`;
- метаданные содержат `FunctionError`;
- ответ содержит сведения об исключении;
- CloudWatch Logs содержит stack trace.

Надёжная автоматизация должна проверять не только exit code команды, но и
`FunctionError`:

```bash
jq -e 'has("FunctionError") | not' \
  ../evidence/invoke-error-metadata.json
```

Эта проверка должна завершиться ненулевым кодом, потому что ошибка ожидаема.

Теперь проверь контракт верхнего уровня event с JSON `null`:

```bash
aws lambda invoke \
  --region "$(terraform output -raw aws_region)" \
  --function-name "$(terraform output -raw function_name)" \
  --cli-binary-format raw-in-base64-out \
  --payload fileb://../events/invalid-event.json \
  ../evidence/invoke-invalid-event-response.json \
  | tee ../evidence/invoke-invalid-event-metadata.json
aws_cli_exit_code=${PIPESTATUS[0]}
echo "aws_cli_exit_code=$aws_cli_exit_code"
```

Ответ должен содержать `ValueError: event must be a JSON object`, а не
случайный `AttributeError` из-за вызова `.get()` у `None`.

## 11. Практические упражнения

### Упражнение 1. Значение по умолчанию

Создай event:

```bash
printf '{}\n' > /tmp/lambda-default-event.json
```

Вызови функцию `aws lambda invoke` и докажи, что она возвращает приветствие для `world`.

### Упражнение 2. Обновление кода

Измени только текст приветствия в `build_greeting()`, затем выполни:

```bash
terraform plan
```

Почему Terraform увидел изменение `aws_lambda_function.hello`, хотя HCL не менялся.

Это доказывает цепочку:

```text
Python change
-> ZIP hash change
-> Terraform detects code update
-> Lambda code update in-place
```

После проверки верни исходный текст либо примени изменение осознанно.

### Упражнение 3. Caller против execution role

Ответь:

- какая identity выполнила `terraform apply`;
- какая role появилась в конфигурации Lambda;
- почему это не одна и та же identity.

Ответы:

`aws sts get-caller-identity` - это caller identity;
`terraform output -raw execution_role_arn` - role, которую принимает сервис Lambda во время запуска Python-кода.

Проверь execution role:

```bash
aws lambda get-function-configuration \
  --region "$(terraform output -raw aws_region)" \
  --function-name "$(terraform output -raw function_name)" \
  --query '{FunctionName:FunctionName,Runtime:Runtime,Handler:Handler,Role:Role,MemorySize:MemorySize,Timeout:Timeout,Architectures:Architectures}' \
  --output table
```

Должен увидеть:

```text
Runtime: python3.14
Handler: lambda_function.lambda_handler
Role: ...lab78-dev-hello-role
MemorySize: 128
Timeout: 5
Architectures: arm64
```

## 12. Разбор типовых проблем

### `No valid credential sources found`

AWS provider не нашёл активную локальную identity. Выбери нужный profile,
при необходимости обнови сессию и проверь её до повторного plan:

```bash
export AWS_PROFILE=aws-sso-admin
aws sso login --profile "$AWS_PROFILE"
aws sts get-caller-identity
terraform plan -out=tfplan
```

Не считай частичный вывод до этой ошибки корректным plan.

### `ReservedConcurrentExecutions ... below its minimum value of [10]`

Региональная account quota слишком мала, чтобы зарезервировать запрошенную
concurrency и одновременно сохранить обязательный AWS minimum unreserved pool.
Для этой лаборатории не задавай `reserved_concurrent_executions`, затем создай
новый plan:

```bash
terraform plan -out=tfplan
terraform apply tfplan
```

Не используй старый `tfplan`: он был построен для другой конфигурации.

### `Runtime.ImportModuleError`

Проверь:

- что `lambda_function.py` находится в корне ZIP;
- что handler равен `lambda_function.lambda_handler`;
- что имя файла и функции совпадают с handler.

Правильно:

```text
lambda_function.zip
└── lambda_function.py
```

### `AccessDeniedException` при invoke

Caller identity не имеет `lambda:InvokeFunction`. Это permission вызывающей
identity, а не execution role функции.

### `ResourceNotFoundException`

Обычно означает одно из трёх:

- неверное имя функции;
- указан другой регион;
- функция ещё не создана или уже удалена.

Проверь:

```bash
aws lambda get-function \
  --function-name "$(terraform output -raw function_name)" \
  --region "$(terraform output -raw aws_region)"
```

### Вызов успешен, но в ответе ошибка

Проверь `FunctionError` в metadata и stack trace в CloudWatch Logs. Не ограничивайся `$?`.

### После изменения Python-кода план пуст

Проверь, что:

- изменён файл внутри lab_78/app/;
- Terraform использует data.archive_file.function;
- у aws_lambda_function есть source_code_hash.

В этой лабе Terraform пересчитывает хэш ZIP-архива. Изменение кода меняет хэш, и Terraform планирует обновление Lambda.

### Журналы пока не появились

CloudWatch Logs может обновиться с небольшой задержкой. Повтори `aws logs tail` через несколько секунд и проверь Region и имя log group.

### Checkov требует VPC, KMS, DLQ, X-Ray или code signing

Эти `generic findings` требуют контекста, а не автоматического подавления.
Урок 78 обьясняет основы AWS Lambda и не добавляет несвязанные ресурсы:

- VPC нужен, только если функция должна обращаться к приватным ресурсам VPC;
- в лаборатории хранится несекретная конфигурация и используется шифрование под
  управлением AWS;
- DLQ относится к асинхронным вызовам, а в этом уроке вызовы синхронные;
- X-Ray, code signing, customer-managed KMS keys и более длительный срок
  хранения журналов являются обоснованными решениями для рабочей среды, но относятся
  к следующим урокам по надёжности и delivery.

## 13. Проверка результата

Перед очисткой убедись, что:

- все локальные unit tests пройдены;
- Terraform format и validate завершились успешно;
- сохранённый plan был проверен до apply;
- успешный invocation не содержит `FunctionError`;
- отрицательные invocations содержат `FunctionError`, хотя AWS CLI вернул `0`;
- request ID связывает response с соответствующими записями CloudWatch Logs.

Проверка логов:

```bash
aws logs filter-log-events \
  --log-group-name "$(terraform output -raw log_group_name)" \
  --region "$(terraform output -raw aws_region)" \
  --output json | jq '.events[].message'
```

Файлы в `lab_78/evidence/` являются временными результатами упражнений.

## 14. Очистка

Удаление ресурсов является частью лаборатории. Сохрани имя функции и регион, чтобы после
удаления проверить AWS:

```bash
FUNCTION_NAME="$(terraform output -raw function_name)"
AWS_REGION="$(terraform output -raw aws_region)"
terraform plan -destroy
terraform destroy
aws lambda get-function --region "$AWS_REGION" --function-name "$FUNCTION_NAME"
```

Последняя команда должна вернуть `ResourceNotFoundException`.

## 15. Итоговая модель

```text
caller identity
    |
    | lambda:InvokeFunction
    v
Lambda service
    |
    | assumes execution role
    v
Python handler(event, context)
    |
    +-> response
    |
    +-> CloudWatch Logs
```

Главные выводы:

1. Lambda выполняет handler по событию, а не поддерживает процесс постоянно работающим.
2. Event содержит входные данные, context — метаданные invocation.
3. Caller identity и execution role решают разные задачи.
4. Успех Lambda API не гарантирует успех handler.
5. Unit tests, Terraform checks и реальный invocation проверяют разные слои.
6. Первый урок намеренно прост; event sources, retries, packaging и delivery появятся дальше.

## 16. Официальные источники

- [AWS Lambda runtimes](https://docs.aws.amazon.com/lambda/latest/dg/lambda-runtimes.html)
- [Python handler в AWS Lambda](https://docs.aws.amazon.com/lambda/latest/dg/python-handler.html)
- [Lambda context object](https://docs.aws.amazon.com/lambda/latest/dg/python-context.html)
- [Lambda quotas](https://docs.aws.amazon.com/lambda/latest/dg/gettingstarted-limits.html)
- [Terraform `aws_lambda_function`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function)
- [Terraform `archive_file`](https://registry.terraform.io/providers/hashicorp/archive/latest/docs/data-sources/file)
