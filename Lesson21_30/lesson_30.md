# lesson_30

---

# Kubernetes Observability for lab30-web: App Metrics & Dashboard

**Date:** 2025-12-09

**Topic:** Instrument `lab30-web` with **Prometheus metrics**, scrape them from the **in-cluster Prometheus** (lesson_29), and build a **Grafana dashboard** focusing on lab30 web in k8s.

> Reuses: kind cluster lab27, namespace lab27, Prometheus + kube-state-metrics in monitoring (lesson_29), Ingress lab27.local (lesson_28), and lab25 web image as base.
> 

---

## Goals

- Add **/metrics endpoint** to your lab30 Flask app using `prometheus_client`.
- Rebuild/publish image and update lab30**-web Deployment** in k8s.
- Configure Prometheus-in-k8s to **scrape** lab30**-web /metrics**.
- Create a **Grafana dashboard** with app-level metrics (RPS, errors, latency) for lab30-web in k8s.
- Combine app metrics with k8s state metrics (restarts, replicas) into one view.

---

## Pocket Cheat

| Thing / Command | What it does | Why |
| --- | --- | --- |
| `prometheus_client` | Python lib for /metrics | Expose app metrics |
| `/metrics` endpoint | Exports counters/histograms | Prometheus scrape |
| `labweb_http_requests_total` | Custom Counter | RPS + error rate |
| `labweb_http_request_duration_seconds` | Histogram | Latency distribution |
| `kube_pod_container_status_restarts_total` | KSM metric | Pod restarts |
| `kubectl rollout restart deploy/lab30-prometheus -n monitoring` | Reload Prom config | Pick up new job |
| `rate(labweb_http_requests_total[5m])` | RPS by label | Traffic |
| `increase(labweb_http_requests_total{status="5xx"}[5m])` | Error volume | Errors |

---

## Notes

- Already monitoring k8s objects (Deployments/Pods) via kube-state-metrics. Now add **app-level** metrics.
- Idea: every HTTP request to the lab web app increments counters/histograms, Prometheus scrapes them, Grafana visualizes them.
- Use the **same Prometheus** from lesson_29 (`lab29-prometheus` in the `monitoring` namespace) and the existing Grafana (from Docker Compose).

---

## Security Checklist

- Do not log or export any private data in metrics (logins, tokens, user IP addresses).
- `/metrics` must be accessible only inside the cluster (via a Service), not exposed externally via Ingress.
- When updating the Docker image, use a new tag (don’t overwrite `latest`).

---

## Pitfalls

- Forgot to add `prometheus_client` to `requirements.txt` → the app crashes on startup.
- Didn’t update the image tag in the Deployment → k8s keeps running the old image without `/metrics`.
- Didn’t add a scrape job in Prometheus → the metrics exist in the app, but Prometheus doesn’t see them.
- In Grafana, the data source still points to the **old** Prometheus from Docker Compose instead of the k8s Prometheus (or vice versa) — always double-check which URL it’s using.

---

## Layout

```
labs/lesson_30/
		├─ app/
		|  ├─ app.py
		|  ├─ Docerfile
		|  └─ requirements.txt
		├─ grafana/
		|   ├─ dashboards/
		|		|  └─ Lab30_Dashboards/
		|		|     └─ lab30-web-k8s.json
		|   ├─ provisioning/
		|   |  ├─ dashboards/
		|   |  |  └─ dashboards.yml
		|   |  └─ datasources/
		|   |     └─ lab30-prometheus.yml
		|   └─ docker-compose.yml
		├─── k8s/
		|		 ||└─ monitoring/
		|		 ||   ├─ kube-state-metrics-deployment.yaml
		|		 ||   ├─ kube-state-metrics-rbac.yaml
		|		 ||   ├─ prometheus-config.yaml
		|		 ||   ├─ prometheus-deployment.yaml
		|		 ||   └─ prometheus-service.yaml
		|    |└─ namespaces/
		|    |   ├─ lab30-namespace.yaml
		|    |   └─  monitoring-namespace.yaml
		|    ├─ redis-deployment.yaml
		|    ├─ redis-service.yaml
		|    ├─ web-config.yaml
		|    ├─ web-deployment.yaml
		|    ├─ web-ingress.yaml
		|    └─ web-service.yaml
		└─ kind/
				└─ kind-config.yaml
```

---

## 1) Instrument lab25 app with Prometheus metrics

We’ll extend the Flask app from lesson_25 and reuse its image for k8s.

### 1.1 Add prometheus_client to requirements

`labs/lesson_30/app/requirements.txt` — add line:

```
flask==3.1
redis==7.1
prometheus-client==0.23
packaging>=23.0

```

### 1.2 Update app.py with metrics

`labs/lesson_30/app/app.py` — minimum add:

```python
from flask import Flask, jsonify, request, current_app
import os
import socket
import time

try:
    import redis
except ImportError:
    redis = None

from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST

app = Flask(__name__)
start_time = time.time()

_redis_client = None

# --- Prometheus

HTTP_REQUEST = Counter(
    "labweb_http_requests_total",
    "HTTP request",
    ["method", "endpoint", "status"],
)

HTTP_LATENCY = Histogram(
    "labweb_http_request_duration_seconds",
    "HTTP request latency (seconds)",
    ["endpoint"],
)

@app.before_request
def start_timer():
    request._start_time = time.time()

@app.after_request
def record_metrics(response):
    endpoint = request.endpoint or "unknown"
    elapsed = time.time() - getattr(request, "_start_time", time.time())
    status = str(response.status_code)

    try:
        HTTP_REQUEST.labels(
            method=request.method,
            endpoint=endpoint,
            status=status,
        ).inc()

        HTTP_LATENCY.labels(endpoint=endpoint).observe(elapsed)
    except Exception as e:
        current_app.logger.exception("Failed to record metrics")
        pass

    return response

def get_redis_client():
    """Return Redis client or None if not configured/available."""
    global _redis_client
    if not redis:
        return None
    if _redis_client is not None:
        return _redis_client

    host = os.getenv("REDIS_HOST")
    if not host:
        return None

    port = int(os.getenv("REDIS_PORT", "6379"))
    db = int(os.getenv("REDIS_DB", "0"))
    try:
        _redis_client = redis.Redis(host=host, port=port, db=db)
        _redis_client.ping()
    except Exception:
        _redis_client = None
    return _redis_client

@app.get("/metrics")
def metrics():
    """Prometheus metrics endpoint."""
    return app.response_class(
        generate_latest(),
        mimetype=CONTENT_TYPE_LATEST,
    )

@app.get("/health")
def health():
    uptime = int(time.time() - start_time)
    client = get_redis_client()
    redis_ok = False
    if client is not None:
        try:
            client.ping()
            redis_ok = True
        except Exception:
            redis_ok = False

    return jsonify(
        status="ok",
        uptime_seconds=uptime,
        hostname=socket.gethostname(),
        env=os.getenv("LAB_ENV", "dev"),
        redis_ok=redis_ok,
    )

@app.get("/")
def index():
    client = get_redis_client()
    hit_count = None
    redis_error = None

    if client is not None:
        try:
            hit_count = client.incr("lab30_hits")
        except Exception as exc:
            redis_error = str(exc)

    return jsonify(
        message="Hello from lab30 (metrics enabled)",
        path=request.path,
        host=request.host,
        env=os.getenv("LAB_ENV", "dev"),
        hit_count=hit_count,
        redis_error=redis_error,
    )

if __name__ == "__main__":
    port = int(os.getenv("PORT", "8080"))
    app.run(host="0.0.0.0", port=port)

```

Fast check (no k8s):

```bash
cd labs/lesson_30/app
docker build -t lab30-web-metrics:dev .

docker run --rm -p 8080:8080 lab30-web-metrics:dev
# other terminal:
curl -s http://127.0.0.1:8080/ | jq
curl -s http://127.0.0.1:8080/metrics | head

```

Make sure that `/metrics` returns text in Prometheus format.

---

## 2) New image tag & pushing / loading into kind

### 2.1 Build with new tag

```bash
cd labs/lesson_30/app

docker build \
  --build-arg BUILD_VERSION=0.2.0 \
  --build-arg BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  -t lab30-web-metrics:0.2.0 .

# docker image ls
```

### Next to GHCR

```bash
docker tag lab30-web-metrics:0.2.0 ghcr.io/vlrrbn/lab30-web-metrics:0.2.0
docker push ghcr.io/vlrrbn/lab30-web-metrics:0.2.0
```

---

## 3) Update lab27-web Deployment to use new image

`labs/lesson_28/k8s/web-deployment.yaml` (or new `labs/lesson_30/k8s/web-deployment.yaml`).

Change:

```yaml
containers:
  - name: web
    image: ghcr.io/vlrrbn/lab30-web-metrics:0.2.0
    imagePullPolicy: IfNotPresent
```

The remaining env vars are wired the same way as before via ConfigMap.

Apply it:

```bash
kubectl apply -f web-deployment.yaml

kubectl rollout status deploy/lab30-web -n lab30
kubectl get pods -n lab30

```

Repeat:

```bash
POD=$(kubectl get pod -n lab30 -l app=lab30-web -o jsonpath='{.items[0].metadata.name}')
kubectl exec -it "$POD" -n lab30 -- curl -s http://127.0.0.1:8080/metrics | head

```

---

## 4) Configure Prometheus to scrape lab27-web /metrics

Editing `labs/lesson_29/k8s/monitoring/prometheus-config.yaml` or add create new.

Inside`data.prometheus.yml` add new `scrape_config`:

```yaml
    scrape_configs:
      - job_name: "prometheus"
        static_configs:
          - targets: ["127.0.0.1:9090"]

      - job_name: "kube-state-metrics"
        static_configs:
          - targets: ["kube-state-metrics.monitoring.svc.cluster.local:8080"]

      - job_name: "lab30-web-metrics"
        metrics_path: /metrics
        static_configs:
          - targets: ["lab30-web.lab30.svc.cluster.local:8080"]
            labels:
              service: labweb
              env: lab
```

Apply ConfigMap and reload Prometheus:

```bash
kubectl apply -f prometheus-config.yaml

kubectl rollout restart deploy/lab30-prometheus -n monitoring
kubectl rollout status deploy/lab30-prometheus -n monitoring

```

Then:

```bash
kubectl port-forward svc/lab30-prometheus -n monitoring 9090:9090
# kubectl port-forward svc/lab30-prometheus -n monitoring --address 0.0.0.0 9090:9090
# kubectl port-forward svc/lab30-prometheus -n monitoring --address 127.0.0.1,172.17.0.1 9090:9090
```

Prom UI → **Status → Targets**: should appear job `lab30-web` in status `UP`.

---

## 5) PromQL for app metrics

В Prometheus UI:

### Traffic & errors

```bash
labweb_http_requests_total
labweb_http_request_duration_seconds_count

```

→ you’ll see a time series with labels `method`, `endpoint`, `status`.

Examples:

- RDS & RPS endpoint’:

```bash
sum by (endpoint) (rate(labweb_http_requests_total[5m]))

sum by (endpoint) (rate(labweb_http_request_duration_seconds_count[5m]))

POD=$(kubectl get pod -n lab30 -l app=lab30-web -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n lab30 "$POD" -- \
  curl -s http://127.0.0.1:8080/metrics | grep labweb_http || true

```

- Rate (2xx):

```
sum by (status) (rate(labweb_http_requests_total{status=~"2.."}[5m]))

```

### Latency

```
histogram_quantile(
  0.99,
  sum by (le) (rate(labweb_http_request_duration_seconds_bucket[5m]))
)

```

---

## 6) Grafana dashboard: lab27-web in k8s

Create `labs/lesson_30/grafana/dashboards/lab30-web-k8s.json`.

The structure is similar to the previous dashboards, a minimal example:

```json
{
  "uid": "lab30-web-k8s",
  "title": "Lab30-Web (k8s) - App & K8s",
  "tags": ["lab", "k8s", "lab30", "labweb"],
  "schemaVersion": 39,
  "version": 1,
  "refresh": "10s",
  "panels": [
    {
      "type": "timeseries",
      "title": "HTTP RPS by endpoint",
      "datasource": {"type": "prometheus", "uid": "ds_prom"},
      "targets": [
        {
          "expr": "sum by (endpoint) (rate(labweb_http_requests_total[5m]))",
          "legendFormat": "{{endpoint}}"
        }
      ],
      "gridPos": {"h": 6, "w": 12, "x": 0, "y": 0}
    },
    {
      "type": "timeseries",
      "title": "HTTP 2xx rate",
      "datasource": {"type": "prometheus", "uid": "ds_prom"},
      "targets": [
        {
          "expr": "sum by (status) (rate(labweb_http_requests_total{status=~\"2..\"}[5m]))",
          "legendFormat": "{{status}}"
        }
      ],
      "gridPos": {"h": 6, "w": 12, "x": 12, "y": 0}
    },
    {
      "type": "timeseries",
      "title": "Request latency p99",
      "datasource": {"type": "prometheus", "uid": "ds_prom"},
      "targets": [
        {
          "expr": "histogram_quantile(0.99, sum by (le) (rate(labweb_http_request_duration_seconds_bucket[5m])))",
          "legendFormat": "p99 latency"
        }
      ],
      "gridPos": {"h": 6, "w": 12, "x": 0, "y": 6}
    },
    {
      "type": "timeseries",
      "title": "Pod restarts (lab30 namespace)",
      "datasource": {"type": "prometheus", "uid": "ds_prom"},
      "targets": [
        {
          "expr": "increase(kube_pod_container_status_restarts_total{namespace=\"lab30\"}[10m])",
          "legendFormat": "{{pod}}"
        }
      ],
      "gridPos": {"h": 6, "w": 12, "x": 12, "y": 6}
    }
  ]
}

```

Next:

1. In Grafana (Docker Compose), add or verify the Prometheus data source pointing to `http://127.0.0.1:9090` (port-forwarded Prometheus from k8s).
2. Put the JSON file into the path where Grafana already looks for dashboards.
3. Restart the Grafana container (`docker compose restart grafana`).
4. Open the `Lab30 Web (k8s) - App & K8s` dashboard.

---

## 7) Logs: quick kubectl triage

Even without Loki in k8s you can set up a small log triage for yourself:

```bash
# last logs web
kubectl logs -l app=lab27-web -n lab30 --tail=100

# watch logs live
kubectl logs -l app=lab27-web -n lab30 -f

# only errors (just grep, accurate)
kubectl logs -l app=lab27-web -n lab30 --tail=500 | grep -i "error" || true

```

---

## Core

- [ ]  The app (lab25 web) is updated with `/metrics` and the Prometheus client.
- [ ]  An image with the new tag (`0.2.1`) is built and available to k8s (via `kind load` or a registry).
- [ ]  The `lab30-web` Deployment uses the new image, and `/metrics` is reachable inside the Pod.
- [ ]  Prometheus in k8s scrapes the `lab30-web` job, and the `labweb_http_requests_total` / `labweb_http_request_duration_seconds_*` metrics are visible.
- [ ]  A Grafana dashboard `lab30-web-k8s` is created with panels for RPS, errors, p99 latency, and Pod restarts.
- [ ]  Simulated load (a loop with `curl`) and saw the RPS/latency graphs change.
- [ ]  Simulated an error (temporarily making `/health` return `200`) and saw a spike in 2xx responses.

---

## Acceptance Criteria

- [ ]  Open Prometheus and see **app-level metrics** for `lab-web` running in k8s.
- [ ]  Grafana shows a summary for `lab30-web`: traffic, errors, latency, and Pod restarts.
- [ ]  Understand which metrics come from the **application** and which come from **kube-state-metrics**.
- [ ]  When simulate problems (errors, load), saw changes on the dashboard and can explain what is happening.

---

## Summary

- Added **real Prometheus metrics** to the app and wired them all the way through to a dashboard.
- Connected the **k8s layer** (Pods/Deployments) and the **app layer** (HTTP/latency) in a single observability stack.
- Now `lab30` is an **observable service** you can look at with an SRE mindset.

---

## Artifacts

- `labs/lesson_30/app/app.py`
- `labs/lesson_30/grafana/{dashboards/,provisioning/}`
- `labs/lesson_30/k8s/{monitoring/,namespace/}`