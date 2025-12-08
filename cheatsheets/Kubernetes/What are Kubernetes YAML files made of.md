# Из чего вообще состоят YAML’ы Kubernetes

---

## 1. Общая структура любого манифеста

Почти все ресурсы k8s выглядят так:

```yaml
apiVersion: ...
kind: ...
metadata: ...
spec: ...

```

Иногда вместо `spec` что-то своё (`data`, `stringData`, `type` и т.п.), но логика одна.

---

## 2. `apiVersion` — какой API мы используем

```yaml
apiVersion: apps/v1

```

Это:

- **к какому API-группе и версии относится объект**;
- зависит от **kind**.

Примеры:

- `v1` — базовые объекты: `Pod`, `Service`, `ConfigMap`, `Secret`, `Namespace`.
- `apps/v1` — `Deployment`, `StatefulSet`, `DaemonSet`, `ReplicaSet`.
- `batch/v1` — `Job`, `CronJob`.
- `networking.k8s.io/v1` — `Ingress`.

Как правило:

- **это значение не выдумывается**;
- брать из доки/генератора/`kubectl create` или `kubectl api-resources`.

---

## 3. `kind` — что это вообще

```yaml
kind: Deployment

```

Это **тип ресурса**:

- `Deployment`
- `Service`
- `Pod`
- `ConfigMap`
- `Ingress`
- и т.д.

`kind` + `apiVersion` → Kubernetes понимает, как интерпретировать остальное.

---

## 4. `metadata` — кто это и какие у него ярлыки

```yaml
metadata:
  name: demo-app
  namespace: demo
  labels:
    app: demo-app
    tier: backend
  annotations:
    my-company/owner: "team-a"

```

Важно:

### 4.1. Обязательные вещи

- `name` — **обязателен** почти всегда.
- `namespace` — если не указать, будет `default`.

### 4.2. Часто используемые

- `labels` — **ключевые штуки в k8s**:
    - Service выбирает Pod’ы по labels;
    - Deployment/ReplicaSet связываются через labels;
    - HPA, NetworkPolicy и т.д. тоже используют labels;
    - придумываешь систему `labels` (app, env, tier и т.п.).
    
    Пример:
    
    ```yaml
    labels:
      app: my-app
      env: prod
    
    ```
    
- `annotations` — доп. инфа для людей или контроллеров:
    - подсказки для ingress-контроллера,
    - настройки логирования,
    - что угодно.

---

## 5. `spec` — «как должно быть»

Это **desired state** — нужное состояние ресурса.

У каждого `kind` свой формат `spec`.

То есть у:

- `Deployment.spec` — одно устройство,
- `Service.spec` — другое,
- `Pod.spec` — третье.

---

## 6. Пример: структура Pod

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-pod
spec:
  containers:
    - name: app
      image: nginx:1.27
      ports:
        - containerPort: 80
      env:
        - name: APP_ENV
          value: "prod"
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      emptyDir: {}

```

Разбор:

- `spec.containers` — список контейнеров (обязателен).
    - у каждого `name` + `image` — обязательные.
    - остальное — опционально (ports, env, resources, probes...).
- `spec.volumes` — опционально.
- `restartPolicy` — по умолчанию `Always` (для Pod).

---

## 7. Пример: структура Deployment (и откуда берётся `template`)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-deployment
spec:
  replicas: 3
  selector:
    matchLabels:
      app: my-app              # кого он считает «своими» Pod'ами
  template:                    # вот темплейт
    metadata:
      labels:
        app: my-app
    spec:                      # это spec Pod'а
      containers:
        - name: app
          image: nginx:1.27
          ports:
            - containerPort: 80

```

### 7.1. Почему есть `template`?

Потому что Deployment **не запускает Pod сам по себе**, он:

- держит желаемое число Pod’ов (через ReplicaSet),
- а **Pod’ы он создаёт по шаблону** → **`template`**.

`spec.template` = **шаблон Pod’а**:

- внутри него **снова**:
    - `metadata` (labels),
    - `spec` (как у Pod).

### 7.2. Обязательные поля в `Deployment.spec`

Минимум:

- `selector` — как находить «свои» Pod’ы:
    
    ```yaml
    selector:
      matchLabels:
        app: my-app
    
    ```
    
- `template` — как создавать Pod’ы:
    
    ```yaml
    template:
      metadata:
        labels:
          app: my-app
      spec:
        containers: ...
    
    ```
    
- В `template.spec` у контейнеров минимум:
    - `name`
    - `image`

---

## 8. Пример: Service и его структура

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-service
spec:
  type: ClusterIP        # по умолчанию, можно не писать
  selector:
    app: my-app
  ports:
    - port: 80           # порт сервиса
      targetPort: 80     # порт контейнера

```

Тут нет `template`, потому что Service:

- **ничего не создаёт**,
- он просто **находит уже существующие Pod’ы по labels** (`selector`)
- и даёт к ним сетевой доступ.

Обязательное:

- `ports` (хотя бы один),
- либо `selector`, либо что-то другое.

---

## 9. Где есть `template`, а где нет

`template` есть у тех, кто **создаёт Pod’ы**:

- `Deployment`
- `StatefulSet`
- `DaemonSet`
- `Job`
- `CronJob` (у него ещё слой `jobTemplate` → `template`)

Пример для Job:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: my-job
spec:
  template:          # опять шаблон Pod'а
    spec:
      restartPolicy: OnFailure
      containers:
        - name: job
          image: busybox
          command: ["echo", "hello"]

```

`template` **нет** у ресурсов, которые:

- сами по себе являются объектом (Pod, ConfigMap, Secret),
- или описывают что-то другое (Service, Ingress, PVC, Namespace).

---

## 10. Пример: ConfigMap vs Secret

Они используют **не `spec`, а `data`**:

### ConfigMap:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: my-config
data:
  APP_ENV: "prod"
  APP_LOG_LEVEL: "info"

```

### Secret:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: my-secret
type: Opaque
data:
  DB_USER: dXNlcg==
  DB_PASSWORD: cGFzc3dvcmQ=

```

Здесь:

- `metadata` — как обычно,
- потом идут специфичные поля (`data`, `type` и т.п.),
- `spec` не нужен, потому что это просто хранилище данных, а не описания поведения.

---

## 11. Что обязательно, а что нет (практически)

### Всегда есть:

- `apiVersion`
- `kind`
- `metadata.name`

### В 99% случаев:

- `metadata.namespace` (кроме `Namespace` самого)
- `metadata.labels`

### Для Pod/Deployment/StatefulSet и т.п.:

- `spec.template.spec.containers` или `spec.containers`
    - у контейнеров: `name`, `image` обязательно
- остальное — опционально, но **желательно**:
    - `resources` (requests/limits)
    - `probes` (liveness/readiness)
    - `env`, `volumeMounts`, `volumes` при необходимости

### Для Service:

- `spec.ports`
- `spec.selector` в обычном случае
- `spec.type` — по умолчанию `ClusterIP`, но часто указывают явно

---

---

## 12. Как самому разбираться что куда входит

Очень полезная штука — `kubectl explain`.

Например:

```bash
kubectl explain deployment
kubectl explain deployment.spec
kubectl explain deployment.spec.template
kubectl explain deployment.spec.template.spec.containers

```

Там будет:

- описание поля,
- required/optional,
- тип,
- вложенные поля.