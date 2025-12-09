# kube-state-metrics

---

## 1. Что это вообще такое

**kube-state-metrics (KSM)** — это сервис в кластере, который:

- смотрит в **Kubernetes API** (Deployment, Pod, Node, PVC, Job и т.д.),
- берёт оттуда *состояние* и метаданные этих объектов,
- конвертит это в **Prometheus-метрики** и отдаёт на `/metrics` (по умолчанию порт 8080/80).

Он **не собирает CPU/память**, не лезет на ноды, не заменяет Metrics Server или node_exporter. Он именно “переводчик `kubectl get/describe` → метрики”.

---

## 2. Какие именно метрики даёт

Примеры семейств метрик (все начинаются с `kube_...`):

- **Deployment’ы**
    - `kube_deployment_spec_replicas` — сколько реплик *запрошено*.
    - `kube_deployment_status_replicas_available` — сколько *доступно*.
- **Pod’ы**
    - `kube_pod_status_phase` — Running / Pending / Failed и т.п.
    - `kube_pod_status_ready{condition="true|false"}` — готов/не готов.
- **Ноды**
    - `kube_node_status_condition{condition="Ready",status="true|false"}` — нода Ready/NotReady.
- **Контейнеры в подах**
    - `kube_pod_container_status_restarts_total` — сколько раз рестартовал контейнер.
- **ConfigMap/Secret/Job/CronJob/PVC/etc.**
    - Есть куча метрик по статусам, времени создания, bound/unbound, succeeded/failed и т.д.

Это ровно таже инфа, что и `kubectl` только в виде метрик для Prometheus:

```bash
kubectl get deploy
kubectl describe pod ...
kubectl get nodes

```

---

## 3. KSM vs Metrics Server vs node_exporter (кто за что отвечает)

Очень важно не путать:

| Инструмент | Про что | Для чего | Кто обычно читает |
| --- | --- | --- | --- |
| **node_exporter** | Linux-метрики ноды: CPU, RAM, диск, сеть | “Железо / VM жива? не упёрлись ли в ресурсы?” | Prometheus |
| **metrics-server** | CPU/память Pod/Node в виде **Metrics API** | `kubectl top`, HPA/VPA, autoscaling | k8s (HPA/VPA), человек через `kubectl` |
| **kube-state-metrics** | Состояние k8s-объектов: Deployment, Pod, Node, Job, PVC | “Сколько реплик? Pod застрял? Job упал? PVC не примонтирован?” | Prometheus / Grafana  |

Они **дополняют** друг друга:

- node_exporter → *ресурсы ноды*,
- metrics-server → *онлайн CPU/RAM для автоскейлинга*,
- kube-state-metrics → *логика и состояние объектов Kubernetes*.

---

## 4. Как работает внутри (упрощённо)

Архитектура:

- ksm — обычный **Pod/Deployment** в кластере.
- Через client-go он:
    - подписывается на события Kubernetes API,
    - держит *in-memory snapshot* состояния объектов,
    - по запросу на `/metrics` генерит метрики из этого снапшота.
- Он **ничего не хранит сам** — историю хранит Prometheus, который его скрейпит.

По сути, это “бот, который постоянно делает `kubectl get/describe` в RAM и выдаёт это как метрики”.

---

## 5. Зачем он нужен на практике

### 5.1. Алёрты “k8s жив, но всё плохо”

PromQL-примеры на базе ksm: 

**1) Pods не готовы**

```
count by (namespace) (
  kube_pod_status_ready{condition="false"}
)

```

**2) Deployment не выкатился как ожидалось**

```
kube_deployment_status_replicas_available{namespace="lab27", deployment="lab27-web"}
  < kube_deployment_spec_replicas{namespace="lab27", deployment="lab27-web"}

```

→ алерт “у `lab27-web` меньше доступных реплик, чем запрошено”.

**3) Нода NotReady**

```
kube_node_status_condition{condition="Ready", status="false"}

```

→ видно, какая нода умерла.

**4) CrashLoopBackOff / слишком много рестартов**

```
increase(kube_pod_container_status_restarts_total[5m]) > 0

```

→ алерт “за последние 5 минут контейнеры начали падать”.

### 5.2. Дашборды Grafana

На ksm строят панели:

- “Сколько pod’ов в каждом namespace и в каких фазах”.
- “Deployment desired vs available replicas”.
- “Сколько Job’ов failed/succeeded”.
- “Сколько PVC в состоянии Pending”.

В стеке “kind + Prometheus + Grafana” ksm как раз отвечает за эту часть “**k8s объекты как система**”, в то время как node_exporter → железо, а HTTP/blackbox → доступность сервисов.

---

## 6. Как его обычно ставят

Чаще всего — **через Helm**:

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install kube-state-metrics prometheus-community/kube-state-metrics \
  --namespace monitoring --create-namespace

```

Prometheus’у добавляешь джоб:

```yaml
scrape_configs:
  - job_name: 'kube-state-metrics'
    static_configs:
      - targets: ['kube-state-metrics.monitoring.svc.cluster.local:8080']

```

(адрес/порт зависят от чарта и namespace).

---

## 7. Как посмотреть метрики

## 7.1. В живом кластере

Когда kube-state-metrics уже стоит в кластере, он — обычный HTTP-endpoint, который отдаёт все метрики как текст.

### Вариант 1: через `kubectl port-forward`

1. Найти pod:

```bash
kubectl get pods -n monitoring
# или в своём namespace, куда ставил:
# kubectl get pods -A | grep kube-state-metrics

```

2. Пробросить порт:

```bash
kubectl port-forward -n monitoring deploy/kube-state-metrics 8080:8080
# или pod/kube-state-metrics-xxxx 8080:8080

```

3. В браузере или curl:

```bash
curl http://127.0.0.1:8080/metrics | less

```

Там будет **полный список всех метрик**, которые сейчас доступны, с help’ами:

```
# HELP kube_pod_status_phase The pods current phase.
# TYPE kube_pod_status_phase gauge
kube_pod_status_phase{namespace="lab27",pod="lab27-web-123",phase="Running"} 1
...

```

---

### Вариант 2: напрямую через Service

Если Prometheus уже его скрейпит и есть Service:

```bash
kubectl get svc -A | grep kube-state-metrics

```

Допустим, есть `kube-state-metrics.monitoring.svc.cluster.local:8080`.

Можно сделать port-forward сразу сервису:

```bash
kubectl port-forward -n monitoring svc/kube-state-metrics 8080:8080
curl http://127.0.0.1:8080/metrics | less

```

---

## 7.2. В самом Prometheus

Когда ksm уже подключён как target:

1. Открыть веб-UI Prometheus (`/graph`).
2. Вбить в поле **“Insert metric at cursor”**: `kube_` — и смотреть **autocomplete**.
3. Можно листать, выбирать метрики, смотреть `Help` и `Type`.

---

## 7.3. Ну или

Для конспекта / лабораторки:

1. Поднять kube-state-metrics через Helm (или манифест).
2. Сделать:

```bash
kubectl port-forward -n monitoring deploy/kube-state-metrics 8080:8080
curl http://127.0.0.1:8080/metrics > ksm-metrics.txt

```

И потом:
    - искать по файлу `grep kube_deployment`,
    - `grep kube_pod_container_status_restarts_total`,