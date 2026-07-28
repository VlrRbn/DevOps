# Урок 79. IAM и права на вызов AWS Lambda

## 1. Зачем нужен этот урок

В уроке 78 мы создали Lambda-функцию, вызвали её через AWS CLI и увидели, что
вызывающая сторона и execution role выполняют разные задачи. В этом уроке
разберём границу между ними подробнее.

Главный вопрос:

```text
Почему одна IAM identity может вызвать функцию, а другая получает AccessDenied?
```

Для ответа недостаточно посмотреть только на execution role. Решение AWS может
зависеть от:

- identity-based policy вызывающей стороны;
- resource-based policy Lambda-функции;
- trust policy роли, принимаемой через STS;
- permissions boundary, session policy и AWS Organizations SCP;
- явного `Deny` в любой применимой политике.

В лаборатории последовательно проверим три режима:

```text
none     -> AccessDenied
lambda_caller_identity_policy -> Allow в Lambda caller role
function_resource_policy -> Allow в resource-based policy функции
```

## 2. Результаты урока

После урока ты сможешь:

- различать operator identity, Lambda caller role и function execution role;
- объяснить разницу между аутентификацией и авторизацией;
- различать trust policy, identity-based policy и resource-based policy;
- безопасно принять IAM role через `sts:AssumeRole`;
- воспроизвести и диагностировать `AccessDeniedException`;
- выдать `lambda:InvokeFunction` только для одной функции;
- проверить политику роли и resource-based policy Lambda через AWS CLI;
- объяснить, почему вызов между аккаунтами требует больше разрешений, чем вызов
  внутри одного аккаунта.

## 3. Ментальная модель

### 3.1. Четыре участника

В лаборатории участвуют четыре разные сущности:

| Сущность | Задача |
|---|---|
| Operator identity | Запускает Terraform и принимает Lambda caller role |
| Lambda caller role | Вызывает Lambda и проходит проверку прав |
| Lambda service | Принимает API-запрос и запускает функцию |
| Function execution role | Даёт Python-коду права во время выполнения |

Имена в лаборатории:

| Назначение | Terraform address | Имя в AWS |
|---|---|---|
| Lambda-функция | `aws_lambda_function.greeting` | `lab79-dev-lambda-function` |
| Вызывающая роль | `aws_iam_role.lambda_caller` | `lab79-dev-role-lambda-caller` |
| Политика вызова на этой роли | `aws_iam_role_policy.lambda_caller_invoke_access` | `lab79-dev-policy-for-role-lambda-caller-allow-invoke-function` |
| Разрешение на самой функции | `aws_lambda_permission.function_allows_lambda_caller` | statement `AllowLambdaCallerInvoke` |
| Роль работающей функции | `aws_iam_role.function_execution` | `lab79-dev-role-lambda-execution` |
| Политика записи журналов | `aws_iam_role_policy.function_log_access` | `lab79-dev-policy-for-role-lambda-execution-allow-write-logs` |

Поток выглядит так:

```text
operator identity
    | terraform apply
    | sts:AssumeRole
    v
Lambda caller role
    |
    | lambda:InvokeFunction
    v
Lambda service
    | IAM проверяет вызов
    | sts:AssumeRole
    v
function execution role
    | запускается handler
    | logs:CreateLogStream / logs:PutLogEvents
    v
CloudWatch Logs
```

Function execution role не вызывает функцию. Сервис Lambda принимает эту роль после
начала вызова, чтобы handler мог обращаться к разрешённым AWS API.

### 3.2. Аутентификация и авторизация

Аутентификация отвечает на вопрос:

```text
Кто отправил запрос?
```

Авторизация отвечает:

```text
Разрешено ли этой identity выполнить это действие над этим ресурсом?
```

Команда:

```bash
aws sts get-caller-identity
```

показывает текущую identity, но не доказывает, что ей разрешено выполнять
`lambda:InvokeFunction`.

### 3.3. Три вида политик в лаборатории

Trust policy находится в IAM role и определяет, кто может выполнить `sts:AssumeRole`.

```text
Lambda caller role trust policy:
Principal = operator IAM role

Function execution role trust policy:
Principal = lambda.amazonaws.com
```

Identity-based policy прикрепляется к IAM user или IAM role и определяет, какие
действия AWS API разрешены этой identity.

Resource-based policy прикрепляется к ресурсу. Для Lambda она определяет, каким
principal разрешено вызывать функцию.

Важно: trust policy роли IAM технически тоже является resource-based policy,
но она защищает другой ресурс и другое действие:

```text
role trust policy      -> кто может выполнить sts:AssumeRole
Lambda resource policy -> кто может выполнить lambda:InvokeFunction
```

### 3.4. Как AWS принимает решение

Упрощённая модель для вызова внутри одного аккаунта:

```text
есть подходящий Allow
+ нет применимого explicit Deny
= запрос разрешён
```

Если подходящего `Allow` нет, действует implicit deny.

Explicit deny имеет приоритет над allow. Поэтому разрешение в resource-based
policy Lambda не поможет, если запрос запрещён SCP, permissions boundary или
другой применимой политикой.

Для вызова между аккаунтами обычно нужны оба разрешения:

```text
identity-based policy в аккаунте вызывающей стороны
+ resource policy функции в аккаунте владельца
```

В этой лаборатории оба участника находятся в одном аккаунте, поэтому мы можем
сравнить identity-based и resource-based разрешения по отдельности.

Какие политики участвуют на каждом переходе:

| Переход                         | Что проверяется                                    |
| ------------------------------- | -------------------------------------------------- |
| Operator → Terraform APIs       | Policies operator/deployment identity              |
| Operator → Lambda caller role   | Trust policy Lambda caller role и применимые ограничения |
| Lambda caller role → Lambda     | Identity policy роли и/или resource policy функции |
| Lambda service → Function execution role | Trust policy function execution role          |
| Handler → CloudWatch Logs       | Identity policy function execution role            |

Что доказывает каждый успешный шаг:

| Успешная операция         | Что она действительно доказывает          |
| ------------------------- | ----------------------------------------- |
| `terraform apply`         | Operator может создавать/изменять ресурсы |
| `sts:AssumeRole`          | Operator может принять Lambda caller role |
| `sts get-caller-identity` | AWS распознал текущие credentials         |
| `lambda invoke`           | Текущей identity разрешён invocation      |
| Появился ответ handler    | Handler действительно был запущен         |
| Появился CloudWatch log   | Execution role имела нужные права на Logs |

## 4. Архитектура лаборатории

Terraform создаёт:

- одну Python Lambda-функцию;
- отдельную function execution role только для CloudWatch Logs;
- отдельную Lambda caller role;
- один из двух способов выдать `lambda:InvokeFunction`.

Режим задаётся переменной:

```hcl
invoke_permission_mode = "none"
```

Допустимые значения:

| Режим | Политика Lambda caller role | Resource policy Lambda | Результат |
|---|---:|---:|---|
| `none` | нет | нет | `AccessDeniedException` |
| `lambda_caller_identity_policy` | есть | нет | вызов разрешён |
| `function_resource_policy` | нет | есть | вызов разрешён в том же аккаунте |

Terraform native tests проверяют, что режимы не смешиваются.

## 5. Локальные тесты

Из корня репозитория выполни:

```bash
python3 -m unittest discover \
  -s lessons/79-lambda-iam-invocation-permissions/lab_79/tests -v

for script in lessons/79-lambda-iam-invocation-permissions/lab_79/scripts/*.sh; do
    echo "Checking $script"
    bash -n "$script" || exit 1
done
```

Затем:

```bash
cd lessons/79-lambda-iam-invocation-permissions/lab_79/terraform
terraform init
terraform fmt -check -recursive
terraform validate
terraform test
```

`terraform test` использует подменённый AWS provider. Он проверяет структуру
Terraform-конфигурации, но не распространение изменений IAM и не фактический
вызов Lambda.

## 6. Подготовка ARN оператора

### 6.1. Почему нельзя использовать ARN сессии STS

После SSO-входа `aws sts get-caller-identity` часто возвращает:

```text
arn:aws:sts::123456789012:assumed-role/ROLE_NAME/SESSION_NAME
```

Это ARN временной сессии STS. Для trust policy нужен постоянный ARN роли IAM:

```text
arn:aws:iam::123456789012:role/PATH/ROLE_NAME
```

Вспомогательный скрипт определяет текущую identity и при необходимости получает
ARN роли IAM:

```bash
chmod +x ../scripts/*.sh
../scripts/resolve-operator-principal.sh
```

Скрипт ничего не изменяет в AWS. Для роли SSO он выполняет только чтение через
`iam:GetRole`.

### 6.2. Подготовка tfvars

Создай локальный файл:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Вставь полученный ARN:

```hcl
operator_iam_principal_arn = "arn:aws:iam::123456789012:role/REAL_ROLE_PATH/ROLE_NAME"
invoke_permission_mode     = "none"
```

Не коммить `terraform.tfvars`: ARN раскрывает структуру аккаунта, а в других
лабораториях этот файл может содержать чувствительные значения.

## 7. Фаза 1: ожидаемый AccessDenied

### 7.1. План и применение

Проверь текущую identity:

```bash
aws sts get-caller-identity
```

Создай и примени сохранённый план:

```bash
terraform plan -out=tfplan-none
terraform apply tfplan-none
```

```bash
terraform show -json tfplan-none |
  jq -r '
    .resource_changes[] |
    "\(.change.actions | join(",")) \(.address)"
  '
```

В режиме `none` функция и обе роли существуют, но Lambda caller role не имеет
`lambda:InvokeFunction`, а у функции нет разрешающей resource-based policy.


### 7.2. Вызов через Lambda caller role

Вспомогательный скрипт:

1. принимает Lambda caller role через STS;
2. хранит временные учётные данные только в своём процессе;
3. вызывает Lambda от имени этой роли;
4. сохраняет метаданные и ответ в разные файлы.

Запусти:

```bash
../scripts/invoke-as-role.sh \
  "$(terraform output -raw lambda_caller_role_arn)" \
  "$(terraform output -raw function_name)" \
  "$(terraform output -raw aws_region)" \
  ../events/greeting.json \
  ../evidence/none-response.json \
  ../evidence/none-metadata.json

echo "invoke_exit_code=$?"
```

Ожидаемый результат:

```text
AccessDeniedException
... is not authorized to perform: lambda:InvokeFunction ...
```

Ненулевой код завершения здесь означает успех упражнения: мы доказали, что
отсутствие `Allow` приводит к implicit deny.

Проверить отсутствие identity policy:

```text
LAMBDA_CALLER_ROLE_NAME="$(
  terraform output -raw lambda_caller_role_arn |
    awk -F/ '{print $NF}'
)"

aws iam list-role-policies \
  --role-name "$LAMBDA_CALLER_ROLE_NAME" \
  --output json |
  jq .
```

Проверить отсутствие Lambda resource policy:

```text
aws lambda get-policy \
  --region "$(terraform output -raw aws_region)" \
  --function-name "$(terraform output -raw function_name)"
```

Полная цепочка фазы 1:

```text
Operator credentials
        |
        | terraform apply
        v
Lambda + roles созданы
        |
        | sts:AssumeRole
        v
Сессия Lambda caller role создана
        |
        | lambda:InvokeFunction
        v
IAM policy evaluation
        |
        | identity Allow?  нет
        | resource Allow?  нет
        | explicit Deny?   необязательно
        v
Implicit deny
        |
        v
AccessDeniedException
        |
        v
Handler не запускается
```

Правильная классификация ошибок:

```text
| Ошибка                                             | На каком этапе           | Что означает                             |
| -------------------------------------------------- | ------------------------ | ---------------------------------------- |
| `Unable to locate credentials`                     | До AWS                   | AWS CLI не нашёл credentials             |
| `ExpiredToken`                                     | Аутентификация           | Временная сессия истекла                 |
| `AccessDenied` на `sts:AssumeRole`                 | Принятие роли            | Operator не может принять Lambda caller role |
| `AccessDeniedException` на `lambda:InvokeFunction` | Invocation authorization | Lambda caller role не имеет права вызова |
| `ResourceNotFoundException`                        | Поиск Lambda             | Функция не найдена в указанном контексте |
| `InvalidRequestContentException`                   | Разбор запроса           | Некорректный payload                     |
| `FunctionError` в metadata                         | Handler уже запускался   | Ошибка внутри функции                    |
```

## 8. Фаза 2: разрешение через identity-based policy

Измени:

```hcl
invoke_permission_mode = "lambda_caller_identity_policy"
```

Создай новый план:

```bash
terraform plan -out=tfplan-identity
terraform apply tfplan-identity
```

Не используй `tfplan-none`: сохранённый план создан для прежних входных данных.

Terraform добавит inline policy в Lambda caller role:

```json
{
  "Effect": "Allow",
  "Action": "lambda:InvokeFunction",
  "Resource": "arn:aws:lambda:REGION:ACCOUNT:function:lab79-dev-lambda-function"
}
```

Повтори вызов:

```bash
../scripts/invoke-as-role.sh \
  "$(terraform output -raw lambda_caller_role_arn)" \
  "$(terraform output -raw function_name)" \
  "$(terraform output -raw aws_region)" \
  ../events/greeting.json \
  ../evidence/identity-response.json \
  ../evidence/identity-metadata.json
```

Ожидаемый ответ:

```json
{
  "message": "Hello, Valerii!",
  "environment": "dev",
  "request_id": "..."
}
```

Проверь политику:

```bash
LAMBDA_CALLER_ROLE_NAME="$(
  terraform output -raw lambda_caller_role_arn | awk -F/ '{print $NF}'
)"

aws iam get-role-policy \
  --role-name "$LAMBDA_CALLER_ROLE_NAME" \
  --policy-name "$(terraform output -raw caller_invoke_policy_name)" \
  --output json | jq .
```

Убедись, что `Action` содержит только `lambda:InvokeFunction`, а `Resource`
указывает только на функцию этой лаборатории.

Полная цепочка фазы 2:

```text
Operator identity
    |
    | sts:AssumeRole
    | разрешено trust policy Lambda caller role
    v
Lambda caller role session
    |
    | lambda:InvokeFunction
    | разрешено identity-based policy роли
    v
Lambda service
    |
    | sts:AssumeRole
    | разрешено trust policy execution role
    v
Execution role session
    |
    | запускается handler
    | logs:PutLogEvents
    v
CloudWatch Logs
```

## 9. Фаза 3: разрешение через resource-based policy Lambda

Теперь сравним другой путь авторизации. Измени:

```hcl
invoke_permission_mode = "function_resource_policy"
```

В новом плане должны быть два важных изменения:

```text
- удалить inline policy вызова из Lambda caller role
+ добавить aws_lambda_permission к функции
```

Примени:

```bash
terraform plan -out=tfplan-resource
terraform apply tfplan-resource
```

Докажи, что роль больше не содержит inline policy:

```bash
aws iam list-role-policies \
  --role-name "$LAMBDA_CALLER_ROLE_NAME" \
  --output json | jq .
```

Посмотри resource-based policy функции:

```bash
aws lambda get-policy \
  --region "$(terraform output -raw aws_region)" \
  --function-name "$(terraform output -raw function_name)" \
  --query Policy \
  --output text | jq .
```

В политике должны быть principal с ARN Lambda caller role и действие
`lambda:InvokeFunction`.

Повтори вызов:

```bash
../scripts/invoke-as-role.sh \
  "$(terraform output -raw lambda_caller_role_arn)" \
  "$(terraform output -raw function_name)" \
  "$(terraform output -raw aws_region)" \
  ../events/greeting.json \
  ../evidence/resource-response.json \
  ../evidence/resource-metadata.json
```

Вызов снова должен пройти, но теперь `Allow` находится на функции, а не в роли.

Почему важно удалить identity-based policy?

Представим, что Terraform оставил policy на роли и дополнительно создал resource policy:

```text
Lambda caller role:
Allow lambda:InvokeFunction

Lambda:
Allow Lambda caller role
```

Вызов прошёл бы, но мы не смогли бы доказать, какое разрешение его пропустило.

Возможно:

- достаточно было identity-based policy;
- достаточно было resource-based policy;
- сработали оба механизма;
- один из них вообще был настроен неправильно.

## 10. Какие права не нужны execution role

Проверь execution role:

```bash
FUNCTION_EXECUTION_ROLE_NAME="$(
  terraform output -raw function_execution_role_arn | awk -F/ '{print $NF}'
)"

aws iam list-role-policies \
  --role-name "$FUNCTION_EXECUTION_ROLE_NAME" \
  --output json | jq .
```

У неё должна быть только политика для журналов. Посмотри её:

```bash
aws iam get-role-policy \
  --role-name "$FUNCTION_EXECUTION_ROLE_NAME" \
  --policy-name "$(terraform output -raw function_logs_policy_name)" \
  --output json | jq .
```

Execution role не требуется `lambda:InvokeFunction`, потому что Python-код не
вызывает функцию. Если позже функция должна вызвать другую Lambda, право нужно
выдать на ARN именно той функции, а не на `*`.

## 11. Практические упражнения

Подготовка:

```bash
cd lessons/79-lambda-iam-invocation-permissions/lab_79/terraform

terraform plan -out=tfplan-identity
terraform apply tfplan-identity

CALLER_ROLE_ARN="$(terraform output -raw lambda_caller_role_arn)"
FUNCTION_NAME="$(terraform output -raw function_name)"
REGION="$(terraform output -raw aws_region)"
EVENT="../events/greeting.json"

../scripts/invoke-as-role.sh \
  "$CALLER_ROLE_ARN" \
  "$FUNCTION_NAME" \
  "$REGION" \
  "$EVENT" \
  ../evidence/control-response.json \
  ../evidence/control-metadata.json
```

### Упражнение 1. Неверный ARN функции

От имени принятой Lambda caller role попробуй вызвать несуществующую функцию.

С текущей политикой, ограниченной ARN `lab79-dev-lambda-function`, ожидай
`AccessDeniedException`: разрешение не распространяется на другое имя функции.

```bash
WRONG_FUNCTION="${FUNCTION_NAME}-does-not-exist"

set +e

../scripts/invoke-as-role.sh \
  "$CALLER_ROLE_ARN" \
  "$WRONG_FUNCTION" \
  "$REGION" \
  "$EVENT" \
  ../evidence/exercise-1-response.json \
  ../evidence/exercise-1-metadata.json \
  >../evidence/exercise-1.log 2>&1

set -e

cat ../evidence/exercise-1.log
```

Объясни, чем этот результат отличается от `ResourceNotFoundException`:

- `AccessDeniedException` означает, что запрос остановлен авторизацией;
- `ResourceNotFoundException` возможен, когда применимая политика разрешила
  запрос к указанному ARN, но такой функции нет в выбранном регионе.

Не во всех IAM-сценариях AWS раскрывает существование ресурса одинаково: сервис
может намеренно вернуть access denied, чтобы не раскрывать данные.

### Упражнение 2. Проверка области действия

Создай вторую временную Lambda-функцию чтобы временно расширить лабораторию.
Докажи, что политика, ограниченная ARN `lab79-dev-lambda-function`, не позволяет вызвать
другую функцию.

Не расширяй `Resource` до `*` ради удобства.

Скрипт создаёт временную функцию с существующей execution role, проверяет запрет и удаляет её:

```bash
TEMP_FUNCTION="lab79-dev-temp-$(date +%s)"
BUILD_DIR="$(mktemp -d)"

EXECUTION_ROLE_ARN="$(
  terraform output -raw function_execution_role_arn
)"

RUNTIME="$(
  aws lambda get-function-configuration \
    --region "$REGION" \
    --function-name "$FUNCTION_NAME" \
    --query Runtime \
    --output text
)"

cat >"$BUILD_DIR/handler.py" <<'PY'
def lambda_handler(event, context):
    return {
        "message": "Temporary Lambda was invoked",
        "request_id": context.aws_request_id,
    }
PY

(
  cd "$BUILD_DIR"
  python3 -m zipfile -c function.zip handler.py
)

aws lambda create-function \
  --region "$REGION" \
  --function-name "$TEMP_FUNCTION" \
  --runtime "$RUNTIME" \
  --role "$EXECUTION_ROLE_ARN" \
  --handler handler.lambda_handler \
  --zip-file "fileb://$BUILD_DIR/function.zip" \
  >/dev/null

aws lambda wait function-active-v2 \
  --region "$REGION" \
  --function-name "$TEMP_FUNCTION"

echo "Temporary function created: $TEMP_FUNCTION"
```

Вызов от имени Lambda caller role:

```bash
set +e

../scripts/invoke-as-role.sh \
  "$CALLER_ROLE_ARN" \
  "$TEMP_FUNCTION" \
  "$REGION" \
  "$EVENT" \
  ../evidence/exercise-2-response.json \
  ../evidence/exercise-2-metadata.json \
  >../evidence/exercise-2.log 2>&1

set -e

cat ../evidence/exercise-2.log
```

Удаление временной функции:

```bash
aws lambda delete-function \
  --region "$REGION" \
  --function-name "$TEMP_FUNCTION"

rm -rf "$BUILD_DIR"

echo "Temporary function deleted"
```
Проверка удаления:

```bash
set +e

aws lambda get-function \
  --region "$REGION" \
  --function-name "$TEMP_FUNCTION"

set -e
```

### Упражнение 3. Верни режим `none`

После успешной фазы `function_resource_policy` снова установи:

```bash
terraform plan -var='invoke_permission_mode=none' -out=tfplan-none
terraform apply tfplan-none
```

Примени новый план и докажи, что вызов снова запрещён. Это подтверждает, что
успех был вызван конкретным `Allow`, а не остаточным доступом.

Проверяем отсутствие inline policy:

```bash
LAMBDA_CALLER_ROLE_NAME="$(
  terraform output -raw lambda_caller_role_arn |
    awk -F/ '{print $NF}'
)"

aws iam list-role-policies \
  --role-name "$LAMBDA_CALLER_ROLE_NAME" \
  --output json |
  jq .
```

Проверяем отсутствие resource policy:

```bash
set +e

aws lambda get-policy \
  --region "$REGION" \
  --function-name "$FUNCTION_NAME"

POLICY_RC=$?

set -e

echo "get_policy_exit_code=$POLICY_RC"
```

Финальная проверка вызова:

```bash
set +e

../scripts/invoke-as-role.sh \
  "$CALLER_ROLE_ARN" \
  "$FUNCTION_NAME" \
  "$REGION" \
  "$EVENT" \
  ../evidence/exercise-3-response.json \
  ../evidence/exercise-3-metadata.json \
  >../evidence/exercise-3.log 2>&1

INVOKE_RC=$?

set -e

cat ../evidence/exercise-3.log
echo "invoke_exit_code=$INVOKE_RC"
```

## 12. Разбор типовых проблем

### `operator_iam_principal_arn must be an IAM role or user ARN`

Ты передал ARN сессии STS:

```text
arn:aws:sts::...:assumed-role/...
```

Запусти `resolve-operator-principal.sh` или найди ARN исходной роли IAM:

```bash
aws iam get-role --role-name ROLE_NAME --query Role.Arn --output text
```

### `AccessDenied` при `sts:AssumeRole`

Проверь:

- совпадает ли текущая operator identity со значением `operator_iam_principal_arn`;
- применён ли последний план Terraform;
- не запрещает ли `sts:AssumeRole` permissions boundary, session policy или SCP;
- не была ли роль IAM пересоздана с другим ARN.

Посмотри trust policy роли:

```bash
aws sts get-caller-identity

CALLER_ROLE_NAME="$(
  terraform output -raw lambda_caller_role_arn |
  awk -F/ '{print $NF}'
)"

aws iam get-role \
  --role-name "$LAMBDA_CALLER_ROLE_NAME" \
  --query 'Role.AssumeRolePolicyDocument' \
  --output json | jq .
```

### Вызов всё ещё получает `AccessDenied` после применения

Изменения IAM распространяются не мгновенно. Подожди несколько секунд и повтори
вызов с новой сессией STS. Вспомогательный скрипт создаёт новую сессию при
каждом запуске.

Также проверь:

```bash
terraform output -raw invoke_permission_mode
```

### `aws lambda get-policy` возвращает `ResourceNotFoundException`

В режимах `none` и `lambda_caller_identity_policy` у функции нет resource-based policy,
поэтому такой ответ ожидаем. Команда должна вернуть политику только в режиме
`function_resource_policy`.

### Политика роли существует, но вызов запрещён

Проверь:

- точный function ARN в `Resource`;
- регион;
- qualifier, если вызывается version или alias;
- permissions boundary;
- session policy;
- Organizations SCP;
- explicit deny.

```bash
aws iam get-role-policy \
  --role-name "$CALLER_ROLE_NAME" \
  --policy-name "$(terraform output -raw caller_invoke_policy_name)" \
  --output json |
  jq '.PolicyDocument.Statement'
```

Policy evaluator рассматривает не один документ, а все применимые ограничения.

### Вспомогательный скрипт не показывает метаданные

При `AccessDenied` на уровне API сервис Lambda не принял вызов, поэтому
метаданных успешного ответа Lambda API нет. Проверь stderr AWS CLI и код
завершения `echo $?`.

### Checkov требует VPC, KMS, DLQ, X-Ray или code signing

Это ожидаемые `generic findings` для небольшой синхронной учебной функции.
Урок 79 проверяет IAM authorization path и не добавляет несвязанные ресурсы:

- VPC нужен, только если функция должна обращаться к приватным ресурсам VPC;
- в лаборатории хранится несекретная конфигурация и используется шифрование под
  управлением AWS;
- DLQ относится к асинхронным вызовам, а в этом уроке вызовы синхронные;
- X-Ray, code signing, customer-managed KMS keys и более длительный срок
  хранения журналов являются обоснованными решениями для рабочей среды, но относятся
  к следующим урокам по надёжности и delivery.

## 13. Проверка результата

Перед очисткой убедись, что:

- Python unit tests прошли;
- `terraform validate` и `terraform test` прошли;
- `none` завершился ожидаемым `AccessDeniedException`;
- `lambda_caller_identity_policy` успешно вызвал функцию через политику роли;
- `function_resource_policy` успешно вызвал функцию через политику Lambda;
- execution role содержит только права на журналы;
- временные учётные данные STS не записаны в результаты.

Файлы в `lab_79/evidence/` являются временными результатами. Не коммить их без
проверки и маскирования служебных метаданных.

## 14. Очистка

Удаление всех режимов выполняется одним Terraform root. До `destroy` сохрани
имя функции и регион:

```bash
FUNCTION_NAME="$(terraform output -raw function_name)"
LAB_AWS_REGION="$(terraform output -raw aws_region)"

terraform destroy

aws lambda get-function \
  --region "$LAB_AWS_REGION" \
  --function-name "$FUNCTION_NAME"
```

Последняя команда должна вернуть `ResourceNotFoundException`.

## 15. Итоговая модель

```text
trust policy
    -> кто может принять role

identity-based policy
    -> что может делать IAM identity

Lambda resource-based policy
    -> какой principal может вызвать функцию

execution role
    -> что может делать handler после запуска
```

Главные выводы:

1. Развёртывание, вызов и выполнение функции используют разные identity.
2. Наличие учётных данных доказывает аутентификацию, но не авторизацию.
3. Отсутствие подходящего `Allow` приводит к implicit deny.
4. Explicit deny имеет приоритет над `Allow`.
5. Вызов Lambda внутри одного аккаунта можно разрешить через identity-based
   policy или resource-based policy; для вызова между аккаунтами обычно нужны
   обе.
6. Least privilege означает минимальные `Action`, `Resource` и доверенный
   principal, а не просто короткую JSON policy.

## 16. Официальные источники

- [AWS Lambda permissions](https://docs.aws.amazon.com/lambda/latest/dg/lambda-permissions.html)
- [Identity-based и resource-based policies](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_identity-vs-resource.html)
- [IAM policy evaluation logic](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_evaluation-logic.html)
- [IAM role trust policies](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_manage_modify.html)
- [AWS CLI `lambda invoke`](https://docs.aws.amazon.com/cli/latest/reference/lambda/invoke.html)
- [Terraform `aws_lambda_permission`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_permission)
