# Helm - это менеджер пакетов для Kubernetes

***Что это, зачем нужен, как устроен и где реально помогает.***

- **Что это:** пакетный менеджер для приложений в Kubernetes (шаблоны + values + релизы).
- **Зачем нужен:** чтобы не управлять десятками YAML вручную, а деплоить/обновлять/откатывать приложение как единый пакет.
- **Как устроен:** чарт (Chart.yaml + values + templates) → Helm генерит манифесты → пишет состояние релиза в кластере → даёт историю и rollback.
- **Где помогает:**
    - многократные окружения (dev/stage/prod) с одними и теми же шаблонами;
    - типовые штуки вроде Postgres/Redis/Nginx/Prometheus — через чужие чарты;
    - CI/CD и GitOps: `helm upgrade --install` + `--wait --atomic`, версия чарта, история релизов;
    - когда у тебя уже не «одна YAMLка», а нормальный зоопарк микросервисов.

---

## 1. Что такое Helm в одном предложении

Helm — это инструмент, который позволяет:

- упаковать Kubernetes-манифесты в **чарт (chart)**,
- **устанавливать, обновлять, удалять и настраивать** приложения в Kubernetes как единое целое,
- хранить версии и **делать откаты** (rollback) как у нормального софта.

---

## 2. В чём вообще проблема без Helm

Представь приложение из 5–10 микросервисов. Для каждого нужны:

- Deployment
- Service
- ConfigMap
- Secret
- Ingress
- иногда CronJob, ServiceAccount, Role, RoleBinding, и т.д.

В итоге:

- десятки YAML-файлов,
- куча копипасты,
- для dev/stage/prod разные значения (URL, реплики, ресурсы),
- обновление = ручное редактирование YAML’ов и `kubectl apply -f ...`.

Проблемы:

- легко ошибиться (не тот namespace, не та версия образа);
- сложно **повторяемо** разворачивать одно и то же в разных окружениях;
- неудобно обновлять и **откатывать** изменения;
- тяжело делиться конфигурацией с другими командами.

Helm решает все эти проблемы.

---

## 3. Основные понятия Helm

### 3.1. Chart (чарт)

**Chart** — это “пакет приложения для Kubernetes”. Состоит из:

- `Chart.yaml` — метаданные (имя, версия, описание).
- `values.yaml` — значения по умолчанию (конфиг для чарта).
- `templates/` — шаблоны Kubernetes-манифестов (Deployment, Service и т.д.) с переменными (`{{ .Values.image.tag }}` и т.д.).
- иногда:
    - `values-*.yaml` — разные комплекты значений (prod, dev),
    - `templates/_helpers.tpl` — функции и общие шаблоны.

Один раз описываешь шаблоны, а настройки под разные окружения задаёшь через values.

---

### 3.2. Release (релиз)

Когда ты устанавливаешь чарт в кластер:

```bash
helm install my-app ./my-chart
```

Helm создаёт **release** — конкретный установленный экземпляр чарта с набором values.

Можно поставить один и тот же чарт много раз:

- `my-app-dev`
- `my-app-staging`
- `my-app-prod`

Все — разные релизы, с разными values.

---

### 3.3. Repository (репозиторий чартов)

Как у `apt` есть репозитории пакетов, так у Helm есть **репозитории чартов**.

Примеры:

- официальный `https://charts.helm.sh/stable` (раньше, сейчас больше сторонние),
- Bitnami charts.

Можно:

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm search repo postgresql
helm install my-db bitnami/postgresql

```

PostgreSQL будет развернут в кластере со стандартной конфигурацией.

---

### 3.4. Values (values.yaml и override values)

Helm жёстко разделяет:

- **шаблон** (что развернуть — структура ресурсов),
- **values** (как именно — ресурсы, теги образов, URL, фичи).

Можно брать один и тот же чарт и подставлять разные values:

```bash
helm install my-app ./my-chart -f values-dev.yaml
helm install my-app-prod ./my-chart -f values-prod.yaml

```

Разные окружения — один чарт.

---

## 4. Зачем Helm нужен на практике

### 4.1. Повторяемость и стандарт

- **Один чарт — много окружений.**
    
    Не надо держать три разных набора YAML’ов.
    
- Новому разработчику проще:
    
    `helm install` / `helm upgrade`.
    

### 4.2. Упрощённые деплой и обновление

Можно:

```bash
helm upgrade my-app ./my-chart -f values-prod.yaml

```

Helm:

- считает diff с текущим состоянием,
- применит изменения к нужным ресурсам,
- сохранит новую ревизию релиза.

Если всё сломалось:

```bash
helm rollback my-app 3

```

Возвращение к рабочей версии.

### 4.3. Версионирование

У чарта есть версия, у релиза есть ревизии.

Всегда знаешь:

- какая версия чарта,
- с какими values,
- в какой ревизии сейчас стоит в кластере.

---

### 4.4. Переиспользование и шаринг

- Один раз сделали чарт для своего сервиса — все команды деплоят его одинаково.
- Можно сделать **базовый чарт** и наследоваться от него в других (через dependencies, subchart’ы).

---

### 4.5. Интеграция в CI/CD и GitOps

В CI/CD часто делают:

- билд Docker образа,
- пуш в registry,
- обновление values (tag образа),
- `helm upgrade` в нужное окружение.

С GitOps (Argo CD, Flux):

- в репозитории лежат values и ссылки на чарты,
- GitOps-оператор сам применяет/обновляет релизы по git-коммитам.

---

## 5. Основные команды helm

```bash
# установка чарта
helm install <release-name> <chart> -f values.yaml

# обновление релиза
helm upgrade <release-name> <chart> -f values-prod.yaml

# просмотр установленных релизов
helm list

# посмотреть values текущего релиза
helm get values <release-name>

# посмотреть все манифесты, которые применяет релиз
helm get manifest <release-name>

# откат на предыдущую/конкретную ревизию
helm rollback <release-name> [revision]

# удалить релиз
helm uninstall <release-name>

# сгенерировать манифесты, не применяя в кластер
helm template <chart> -f values.yaml

```

`helm template` часто используют, чтобы увидеть итоговые YAML’ы, которые попадут в k8s.

---

## 6. Внутреннее устройство (упрощённо)

Сейчас **Helm 3**:

- это обычный CLI-инструмент,
- работает напрямую с Kubernetes API (как `kubectl`),
- **нет Tiller’а**, всё клиент-сайд + объекты в `ConfigMap/Secret` в кластере,
- хранит состояние релизов в кластере (обычно в `kube-system` или другом namespace).

Helm при установке/обновлении делает почти то же, что и `kubectl apply`, только:

- генерит манифесты из шаблонов,
- хранит историю,
- даёт обновления/откаты из коробки.

---

## 7. Как Helm выглядит в реальной жизни (мини-сценарий)

Типичный сценарий деплоя сервиса через Helm:

1. **Один раз делаешь чарт:**

```bash
helm create lab-web
# правишь templates/* и values.yaml под свой сервис

```

1. **В dev-кластер:**

```bash
helm upgrade --install lab-web-dev ./lab-web \
  -f values-dev.yaml

```

`--install` — если релиза нет, сделает install, если есть — upgrade. В `values-dev.yaml` — dev-URL, мало реплик, минимальные ресурсы.

1. **В prod:**

```bash
helm upgrade --install lab-web-prod ./lab-web \
  -f values-prod.yaml \
  --namespace lab-prod \
  --create-namespace

```

В `values-prod.yaml` — больше реплик, другие limtis/requests, другие хосты в Ingress и т.п.

1. **Обновили образ:**
- CI собрал Docker-image: `lab-web:v1.4.7`.
- CI меняет тег в `values-prod.yaml` (или в отдельном values-файле только для image tag).
- CI делает:

```bash
helm upgrade --install lab-web-prod ./lab-web \
  -f values-prod.yaml \
  --atomic --wait

```

`--wait` — ждать, пока поды станут Ready. `--atomic` — если не взлетело — откатит релиз.

---

## 8. Полезные команды и флаги

```bash
# создать каркас чарта
helm create my-chart

# посмотреть доступные репозитории
helm repo list

# добавить репозиторий и обновить индексы
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# поиск чарта в репах
helm search repo postgres

# посмотреть значения по умолчанию у чарта
helm show values bitnami/postgresql > values-postgres.yaml

# проверить чарт на ошибки (lint)
helm lint ./my-chart

# история релиза (ревизии)
helm history my-app

# подробная инфа по релизу
helm status my-app

# dry-run + показать что именно применит
helm upgrade --install my-app ./my-chart \
  -f values.yaml \
  --dry-run --debug

# упаковка чарта в tgz (как пакет)
helm package ./my-chart

# зависимостями чарта (subcharts)
helm dependency update ./my-chart

```

Отдельно стоит выделить:

- `helm template` + `--debug` — дебаг шаблонов без реального деплоя.
- `helm lint` — очень полезно в CI.

---

## 9. Dependencies / subcharts (когда у сервиса есть «подсервисы»)

Когда есть сервис, который **зависит** от других (например, web-сервис и рядом Redis/Postgres), можно не писать Postgres/Redis самому, а подтягивать готовые чарты как зависимости.

В `Chart.yaml`:

```yaml
apiVersion: v2
name: lab-web
version: 0.1.0

dependencies:
  - name: postgresql
    version: 15.5.0
    repository: "https://charts.bitnami.com/bitnami"

```

Дальше:

```bash
helm dependency update ./lab-web

```

Helm скачает subchart в `charts/`.

В `values.yaml` нужно настроить:

```yaml
postgresql:
  auth:
    username: lab
    password: supersecret
    database: labdb

```

И всё: один `helm upgrade --install lab-web ...` — поднимет и web, и Postgres.

---

## 10. Hooks (pre/post install/upgrade) — когда нужно выполнить что-то «до/после»

Helm умеет выполнять ресурсы как **хуки**:

- `pre-install`, `post-install`,
- `pre-upgrade`, `post-upgrade`,
- `pre-delete`, `post-delete`, и т.п.

Пример: миграции БД перед rollout’ом нового образа.

В шаблоне Job:

```yaml
metadata:
  name: db-migrate
  annotations:
    "helm.sh/hook": pre-upgrade,pre-install
    "helm.sh/hook-weight": "0"
    "helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded

```

Идея:

- Перед установкой/обновлением Helm запустит job с миграцией.
- Если миграция падает — релиз не обновится.