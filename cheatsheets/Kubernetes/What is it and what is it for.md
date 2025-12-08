# Что это и зачем

---

## 1. Pod — кирпичик всего

**Что это:**

Минимальная сущность, которую запускает k8s. Внутри — один или несколько контейнеров.

- обычно Pod’ами управляют Deployment/Job/DaemonSet/StatefulSet

**Пример:**

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-pod
  labels:
    app: my-app
spec:
  containers:
    - name: app
      image: nginx:1.27
      ports:
        - containerPort: 80

```

---

## 2. Deployment — как мы обычно разворачиваем приложения

**Что это:**

Контроллер, который:

- держит нужное число Pod’ов,
- обновляет их по стратегии (rolling update и т.д.).

**Зачем:**

- масштабирование (replicas)
- обновления без даунтайма
- откаты релиза

**Пример:**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  replicas: 3
  selector:                  # какими label'ами искать Pod'ы
    matchLabels:
      app: my-app
  template:                  # шаблон Pod'а
    metadata:
      labels:
        app: my-app
    spec:
      containers:
        - name: my-app
          image: nginx:1.27
          ports:
            - containerPort: 80
          resources:         # очень желательно задавать
            requests:
              cpu: "100m"
              memory: "128Mi"
            limits:
              cpu: "500m"
              memory: "256Mi"
          livenessProbe:     # жив ли контейнер
            httpGet:
              path: /
              port: 80
            initialDelaySeconds: 10
            periodSeconds: 10
          readinessProbe:    # готов ли принимать трафик
            httpGet:
              path: /
              port: 80
            initialDelaySeconds: 5
            periodSeconds: 5

```

---

## 3. ReplicaSet — внутренности Deployment

**Что это:**

Объект, который следит за количеством Pod’ов. Deployment **создаёт/обновляет ReplicaSet**.

---

## 4. Service — стабильный доступ к Pod’ам

**Что это:**

Абстракция сети. Даёт стабильный IP/имя, за которыми стоят Pod’ы по label'ам.

**Типы:**

- `ClusterIP` — только внутри кластера (по умолчанию)
- `NodePort` — открывает порт на каждой ноде
- `LoadBalancer` — даёт внешний IP (обычно в облаке)

**Пример ClusterIP:**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-app
spec:
  selector:
    app: my-app        # должен совпасть с Pod'ами
  ports:
    - port: 80         # порт сервиса внутри кластера
      targetPort: 80   # порт внутри Pod'а

```

**Пример NodePort:**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-app-nodeport
spec:
  type: NodePort
  selector:
    app: my-app
  ports:
    - port: 80
      targetPort: 80
      nodePort: 30080  # на этот порт можно ходить на любую ноду

```

---

## 5. Ingress — маршрутизация HTTP/HTTPS

**Что это:**

Набор правил: какой домен/путь → в какой Service.

**Нюанс:**

Работает **через Ingress-controller** (Nginx, и др.).

**Пример:**

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /  # пример для nginx'а
spec:
  ingressClassName: nginx
  rules:
    - host: app.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: my-app
                port:
                  number: 80

```

---

## 6. ConfigMap — конфиги приложения

**Что это:**

Некритичные данные (настройки, флаги, ENV).

**Пример:**

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: my-config
data:
  APP_ENV: "prod"
  APP_LOG_LEVEL: "info"

```

**Использование в Deployment:**

```yaml
envFrom:
  - configMapRef:
      name: my-config

```

или как файл:

```yaml
volumes:
  - name: config-volume
    configMap:
      name: my-config

containers:
  - name: app
    ...
    volumeMounts:
      - name: config-volume
        mountPath: /app/config

```

---

## 7. Secret — пароли и токены

**Что это:**

Похоже на ConfigMap, но для секретов, base64 — это не шифрование, но лучше, чем в YAML открыто.

**Пример:**

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: db-secret
type: Opaque
data:
  DB_USER: dXNlcg==          # "user" в base64
  DB_PASSWORD: cGFzc3dvcmQ=  # "password" в base64

```

**В Deployment:**

```yaml
envFrom:
  - secretRef:
      name: db-secret

```

---

## 8. Volumes, PV и PVC — постоянные диски

**Идея:**

- **Pod живёт/умирает** → его файловая система временная.
- Если нужны данные между рестартами → **PersistentVolume (PV)** + **PersistentVolumeClaim (PVC)**.

**PVC (приложение просит диск):**

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
  storageClassName: standard

```

**Использование в Pod/Deployment:**

```yaml
volumes:
  - name: data
    persistentVolumeClaim:
      claimName: my-pvc

containers:
  - name: app
    ...
    volumeMounts:
      - name: data
        mountPath: /var/lib/app

```

PV обычно создаётся динамически через `StorageClass` (в облаках так почти всегда).

---

## 9. StatefulSet — для «stateful» сервисов

**Что это:**

Как Deployment, но:

- Pod’ы имеют **стабильные имена** (`app-0`, `app-1`, …),
- у каждого — свой PVC (если задан volumeClaimTemplates),
- перезапуск происходит аккуратнее (подходит для БД, очередей).

**Пример:**

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: my-db
spec:
  serviceName: "my-db-headless"   # обычно headless service
  replicas: 3
  selector:
    matchLabels:
      app: my-db
  template:
    metadata:
      labels:
        app: my-db
    spec:
      containers:
        - name: db
          image: postgres:16
          ports:
            - containerPort: 5432
          volumeMounts:
            - name: data
              mountPath: /var/lib/postgresql/data
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 10Gi

```

---

## 10. DaemonSet — по Pod’у на ноду

**Что это:**

Запускает по одному Pod’у **на каждой ноде** (или на части нод).

**Для чего:**

- лог-агенты (fluentd, filebeat),
- мониторинг (node-exporter),
- сетевые демоны.

**Пример:**

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-exporter
spec:
  selector:
    matchLabels:
      app: node-exporter
  template:
    metadata:
      labels:
        app: node-exporter
    spec:
      containers:
        - name: node-exporter
          image: prom/node-exporter

```

---

## 11. Job и CronJob — одноразовые задачи и по расписанию

### Job

**Что это:**

Запускает Pod, ждёт успешного завершения.

**Пример: миграция БД:**

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: db-migrate
spec:
  template:
    spec:
      restartPolicy: OnFailure
      containers:
        - name: migrate
          image: my-app:latest
          command: ["python", "manage.py", "migrate"]

```

### CronJob

**По расписанию (как cron):**

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: cleanup-job
spec:
  schedule: "0 3 * * *"     # каждый день в 03:00
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers:
            - name: cleanup
              image: my-app:latest
              command: ["python", "cleanup.py"]

```

---

## 12. Namespace — логическое разделение

**Что это:**

Пространство имён для объектов:

- `dev`, `stage`, `prod`,
- или по командам/проектам.

**Команды:**

```bash
kubectl get ns
kubectl create ns my-project
kubectl get pods -n my-project

```

Часто ещё вешают:

- `ResourceQuota` — лимиты на ресурсы в namespace,
- `LimitRange` — дефолтные requests/limits.

---

## 13. HPA — Horizontal Pod Autoscaler

**Что это:**

Авто-скейлер, который меняет `replicas` в Deployment/StatefulSet по метрикам (CPU, custom).

**Пример:**

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: my-app-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: my-app
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70

```

---

## 14. ServiceAccount, RBAC

Для полноты картины:

- **ServiceAccount** — аккаунты для Pod’ов, чтобы они ходили в API.
- **Role/ClusterRole + RoleBinding/ClusterRoleBinding** — кто что может делать в кластере.

---

## Как всё связывается в реальном сервисе

Типичный минимум:

1. `Namespace` — окружение/проект
2. `Deployment` — код приложения
3. `Service` (ClusterIP) — доступ к Pod’ам
4. `Ingress` — внешний доступ по домену
5. `ConfigMap` + `Secret` — настройки и секреты
6. `PVC` — если нужно хранить данные
7. `HPA` — если нужен авто-скейл