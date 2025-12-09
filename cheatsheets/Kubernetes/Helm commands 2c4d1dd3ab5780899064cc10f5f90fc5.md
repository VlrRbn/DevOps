# Helm commands

---

## Базовые команды

| Команда | Что делает | Зачем / пример |
| --- | --- | --- |
| `helm version` | Показывает версию Helm и режим (Helm 3) | Быстро понять, что установлен за Helm |
| `helm help` | Общая справка | Вспомнить синтаксис подкоманд |
| `helm create my-app` | Создаёт каркас чарта | Быстрый старт: готовая структура `Chart.yaml`, `values.yaml`, `templates/` |

---

## Репозитории чартов

| Команда | Что делает | Зачем / пример |
| --- | --- | --- |
| `helm repo list` | Показывает добавленные репозитории | Проверить, откуда вообще берутся чарты |
| `helm repo add bitnami https://charts.bitnami.com/bitnami` | Добавляет репозиторий чартов | Подключить внешний репо (Postgres, Redis, Nginx, Prometheus, etc.) |
| `helm repo update` | Обновляет индекс всех репозиториев | Подтянуть новые версии чартов |
| `helm search repo postgresql` | Ищет чарты в локально настроенных репо | Найти чарт Postgres/Redis/Prometheus вместо написания с нуля |
| `helm search hub nginx` | Ищет чарты в общедоступном Helm Hub | Поиск чартов в глобальном каталоге |

---

## Инспекция чужих чартов

| Команда | Что делает | Зачем / пример |
| --- | --- | --- |
| `helm show chart bitnami/postgresql` | Показывает метаданные чарта | Посмотреть версию, описание, авторов |
| `helm show values bitnami/postgresql` | Показывает `values.yaml` по умолчанию | Слить в файл и отредактировать под себя: `helm show values ... > values-postgres.yaml` |
| `helm show readme bitnami/postgresql` | Показывает README чарта | Быстро понять, какие есть фичи/флаги |

---

## Установка / обновление / удаление релизов

| Команда | Что делает | Зачем / пример |
| --- | --- | --- |
| `helm install my-db bitnami/postgresql -f values-postgres.yaml` | Устанавливает чарт как релиз `my-db` | Развернуть Postgres с нужными параметрами |
| `helm upgrade my-db bitnami/postgresql -f values-prod.yaml` | Обновляет уже установленный релиз | Применить обновлённые values или новую версию чарта |
| `helm upgrade --install my-app ./my-chart -f values-dev.yaml` | install, если нет релиза, иначе upgrade | Команда для CI/CD: один скрипт и для первого деплоя, и для обновления |
| `helm uninstall my-db` | Удаляет релиз и все его ресурсы | Снести приложение из кластера (но PV/данные БД могут остаться) |
| `helm list` | Показывает список релизов в namespace | Видно, что сейчас установлено и под какими именами |
| `helm list -A` | Релизы во всех namespaces | Удобно для отладки и ревизии |

---

## Values и окружения

| Команда | Что делает | Зачем / пример |
| --- | --- | --- |
| `helm install my-app ./my-chart -f values.yaml` | Установка с кастомным `values.yaml` | Базовая установка своего сервиса |
| `helm install my-app-dev ./my-chart -f values-dev.yaml` | Установка dev-окружения | Меньше реплик, другие URLs, тестовые ресурсы |
| `helm install my-app-prod ./my-chart -f values-prod.yaml` | Установка prod-окружения | Больше реплик, лимиты, другие домены и т.д. |
| `helm get values my-app` | Показывает, с какими values релиз реально запущен | Проверить, что в кластере стоит именно то, что ты думаешь |
| `helm get values my-app -o yaml > current-values.yaml` | Сохранить текущие values релиза | Удобно для отладки/миграции: взять то, что уже работает |

---

## Инспекция и отладка релиза

| Команда | Что делает | Зачем / пример |
| --- | --- | --- |
| `helm status my-app` | Краткое состояние релиза | Быстро понять, жив ли релиз, какие ревизии, какие ошибки |
| `helm history my-app` | История ревизий релиза | Смотреть, какие обновления были, и на какую ревизию откатываться |
| `helm get manifest my-app` | Показать все YAML, применённые этим релизом | Удобно для отладки: какие ресурсы реально созданы |
| `helm get all my-app` | Максимально подробная инфа по релизу | Полный дамп для разборов полётов |

---

## Rollback и безопасные апдейты

| Команда | Что делает | Зачем / пример |
| --- | --- | --- |
| `helm rollback my-app 3` | Откатить релиз к ревизии 3 | Вернуться к предыдущей рабочей версии после фейла |
| `helm upgrade my-app ./my-chart -f values.yaml --wait` | Ждёт, пока все ресурсы станут Ready | В CI не считается успехом, пока поды реально не поднялись |
| `helm upgrade my-app ./my-chart -f values.yaml --atomic --wait` | Авто-rollback при неуспехе | Прод-режим: либо всё поднялось, либо кластер вернулся к прошлой ревизии |

---

## Шаблоны и dry-run

| Команда | Что делает | Зачем / пример |
| --- | --- | --- |
| `helm template ./my-chart -f values.yaml` | Генерит итоговые YAML без применения в кластер | Проверить, что шаблоны рендерятся корректно |
| `helm upgrade my-app ./my-chart -f values.yaml --dry-run --debug` | Прогон upgrade без применения, с подробным логом | Отловить ошибки шаблонов/values до реального деплоя |
| `helm lint ./my-chart` | Статическая проверка чарта | Ловит базовые ошибки и кривые шаблоны |

---

## Зависимости (subcharts)

| Команда | Что делает | Зачем / пример |
| --- | --- | --- |
| `helm dependency update ./my-chart` | Скачивает/обновляет зависимости из `Chart.yaml` | Подтянуть Postgres/Redis как под-чарты |
| `helm dependency list ./my-chart` | Показывает список зависимостей | Проверить, какие под-чарты ждёт твой чарт |
| `helm package ./my-chart` | Упаковывает чарт в `.tgz` | Распространение чарта как «пакета» через свой репо |

---

## Быстрые блоки

### 1. Типичный dev-деплой

```bash
helm upgrade --install lab27-web-dev ./lab27-web \
  -f values-dev.yaml \
  --namespace lab27-dev \
  --create-namespace \
  --wait

```

### 2. Типичный prod-деплой (CI/CD)

```bash
helm upgrade --install lab27-web-prod ./lab27-web \
  -f values-prod.yaml \
  --namespace lab27-prod \
  --create-namespace \
  --wait \
  --atomic

```

### 3. Генерация манифестов в файл для ревью

```bash
helm template ./lab27-web -f values-dev.yaml > rendered-dev.yaml
less rendered-dev.yaml

```

### 4. Узнать актуальные values из кластера и доработать

```bash
helm get values lab27-web-prod -o yaml > current-prod-values.yaml
# правим current-prod-values.yaml и деплоим:
helm upgrade lab27-web-prod ./lab27-web -f current-prod-values.yaml --wait --atomic

```

### 5. Установка Postgres из Bitnami

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

helm show values bitnami/postgresql > values-postgres.yaml
# правишь имя БД, пользователя, пароль

helm upgrade --install lab-db bitnami/postgresql \
  -f values-postgres.yaml \
  --namespace lab-db \
  --create-namespace \
  --wait

```