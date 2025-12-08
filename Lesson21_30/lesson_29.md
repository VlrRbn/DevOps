# lesson_29

---

# Kubernetes Monitoring: Prometheus + kube-state-metrics for lab27

**Date:** 2025-12-03

**Topic:** Deploy **Prometheus + kube-state-metrics** *inside kind cluster* to monitor the **`lab27`** namespace (web + redis). Learn basic k8s-focused PromQL and simple alerts about Deployments/Pods.

> Reuses: kind cluster lab27 and namespace lab27 from lesson_27–28.
> 
> 
> Prometheus is **inside** k8s, not Docker Compose this time.
> 

---

## Goals

- Understand the role of **kube-state-metrics** vs “node” metrics.
- Run a **Prometheus Deployment** in k8s, scraping kube-state-metrics.
- Explore **PromQL** focused on Deployments/Pods for `lab27`.
- Add a small **alert rules** file (deployment not ready / pod restarts).
- Access Prometheus via `kubectl port-forward` and optionally hook it to existing Grafana.

---

## Pocket Cheat

| Thing / File | What it does | Why |
| --- | --- | --- |
| `monitoring-namespace.yaml` | Namespace `monitoring` | Isolate monitoring stack |
| `kube-state-metrics-rbac.yaml` | SA + RBAC for kube-state-metrics | Read cluster state |
| `kube-state-metrics-deployment.yaml` | Deployment + Service | Exposes k8s object metrics |
| `prometheus-config.yaml` | ConfigMap with `prometheus.yml` | Scrape config + rules |
| `prometheus-deployment.yaml` | Prometheus in k8s | In-cluster monitoring |
| `prometheus-service.yaml` | ClusterIP service | Port-forward entrypoint |
| `kubectl port-forward svc/lab29-prometheus 9090:9090 -n monitoring` | Access Prom UI | Explore metrics |
| `kube_deployment_status_replicas_available` | Available replicas | Check app health |
| `kube_pod_container_status_restarts_total` | Container restarts | Detect flapping pods |

---

## Notes

- **kube-state-metrics** is not about CPU/RAM — it’s about **k8s objects**: Deployments, Pods, ReplicaSets, etc.
- Prometheus will scrape only **kube-state-metrics (KSM)** (and itself); that’s enough to see the state of `lab27-web` / `lab27-redis`.
- This is the first step towards full k8s observability; later add node-exporter, cAdvisor, etc.

---

## Security Checklist

- Monitoring has its own Namespace (`monitoring`) — we don’t interfere with other workloads.
- kube-state-metrics gets **read-only** RBAC.
- Prometheus is only accessible via `kubectl port-forward` (ClusterIP), not exposed to the outside world.
- We do not put tokens/secrets into manifests — only ServiceAccount + RBAC.

---

## Pitfalls

- If kube-state-metrics is not running (RBAC/namespace issues), no `kube_*` metrics will appear in Prometheus.
- Wrong `namespace` in PromQL selectors → you either see everything mixed together or nothing at all.
- Forgot to add `rule_files` to `prometheus.yml` → alert rules are not loaded.
- Mixing up the old Docker Compose Prometheus with the new k8s Prometheus — double-check which port/URL Grafana is using.

---

## Layout

```
labs/lesson_29/k8s/monitoring/
├─ monitoring-namespace.yaml
├─ kube-state-metrics-rbac.yaml
├─ kube-state-metrics-deployment.yaml
├─ prometheus-config.yaml
├─ prometheus-deployment.yaml
└─ prometheus-service.yaml
```

---

## 1) Namespace for monitoring stack

`labs/lesson_29/k8s/monitoring/monitoring-namespace.yaml`:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: monitoring
  labels:
    app: monitoring
    env: lab
```

Apply:

```bash
kubectl apply -f monitoring-namespace.yaml
kubectl get ns
```

---

## 2) kube-state-metrics: RBAC + Deployment + Service

### 2.1 RBAC (read-only access)

`labs/lesson_29/k8s/monitoring/kube-state-metrics-rbac.yaml`:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: kube-state-metrics
  namespace: monitoring

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: kube-state-metrics
rules:
  - apiGroups: [""]
    resources:
      - pods
      - nodes
      - namespaces
      - services
      - resourcequotas
      - replicationcontrollers
      - limitranges
      - persistentvolumeclaims
      - persistentvolumes
    verbs: ["list", "watch"]
  - apiGroups: ["apps"]
    resources:
      - deployments
      - daemonsets
      - statefulsets
      - replicasets
    verbs: ["list", "watch"]
  - apiGroups: ["batch"]
    resources:
      - cronjobs
      - jobs
    verbs: ["list", "watch"]
  - apiGroups: ["autoscaling"]
    resources:
      - horizontalpodautoscalers
    verbs: ["list", "watch"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: kube-state-metrics
roleRef:
  kind: ClusterRole
  name: kube-state-metrics
  apiGroup: rbac.authorization.k8s.io
subjects:
  - kind: ServiceAccount
    name: kube-state-metrics
    namespace: monitoring
```

Apply:

```bash
kubectl apply -f kube-state-metrics-rbac.yaml

# kubectl get serviceaccount -n monitoring
# kubectl get clusterrole kube-state-metrics
# kubectl get clusterrolebinding kube-state-metrics
```

### 2.2 Deployment + Service

`labs/lesson_29/k8s/monitoring/kube-state-metrics-deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kube-state-metrics
  namespace: monitoring
  labels:
    app: kube-state-metrics
spec:
  replicas: 1
  selector:
    matchLabels:
      app: kube-state-metrics
  template:
    metadata:
      labels:
        app: kube-state-metrics
    spec:
      serviceAccountName: kube-state-metrics
      containers:
        - name: kube-state-metrics
          image: registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.14.0
          ports:
            - name: http
              containerPort: 8080

---
apiVersion: v1
kind: Service
metadata:
  name: kube-state-metrics
  namespace: monitoring
  labels:
    app: kube-state-metrics
spec:
  type: ClusterIP
  selector:
    app: kube-state-metrics
  ports:
    - name: http
      port: 8080
      targetPort: 8080
```

DNS-name would be `kube-state-metrics.monitoring.svc.cluster.local`

Apply:

```bash
kubectl apply -f kube-state-metrics-deployment.yaml

kubectl get deploy,svc -n monitoring
kubectl get pods -n monitoring

# kubectl logs deploy/kube-state-metrics -n monitoring | head
```

Check if `kube-state-metrics-*` in `Running`.

---

## 3) Prometheus ConfigMap (prometheus.yml + rule_files)

`labs/lesson_29/k8s/monitoring/prometheus-config.yaml`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: lab29-prometheus-config
  namespace: monitoring
data:
  prometheus.yml: |
    global:
      scrape_interval: 30s
      evaluation_interval: 30s

    rule_files:
      - /etc/prometheus/alert.rules.yml

    scrape_configs:
      - job_name: 'prometheus'
        static_configs:
          - targets: ['127.0.0.1:9090']

      - job_name: 'kube-state-metrics'
        static_configs:
          - targets: ['kube-state-metrics.monitoring.svc.cluster.local:8080']

  alert.rules.yml: |
    groups:
      - name: lab27-k8s
        rules:
          - alert: Lab27DeploymentNotReady
            expr: kube_deployment_status_replicas_available{namespace="lab27"} < kube_deployment_spec_replicas{namespace="lab27"}
            for: 2m
            labels:
              severity: warning
              service: lab27
            annotations:
              summary: "Deployment in lab27 not fully available"
              description: "Some replicas are not available in namespace lab27."

          - alert: Lab27PodRestarts
            expr: increase(kube_pod_container_status_restarts_total{namespace="lab27"}[5m]) > 0
            for: 1m
            labels:
              severity: warning
              service: lab27
            annotations:
              summary: "Pod container restart detected in lab27"
              description: "One or more containers in namespace lab27 restarted in the last 5 minutes."
```

Apply:

```bash
kubectl apply -f prometheus-config.yaml

# kubectl get configmap -n monitoring
# kubectl describe configmap lab29-prometheus-config -n monitoring | sed -n '1,80p'
```

---

## 4) Prometheus Deployment + Service

`labs/lesson_29/k8s/monitoring/prometheus-deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: lab29-prometheus
  namespace: monitoring
  labels:
    app: lab29-prometheus
spec:
  replicas: 1
  selector:
    matchLabels:
      app: lab29-prometheus
  template:
    metadata:
      labels:
        app: lab29-prometheus
    spec:
      containers:
        - name: prometheus
          image: prom/prometheus:v2.54.0
          args:
            - "--config.file=/etc/prometheus/prometheus.yml"
            - "--storage.tsdb.path=/prometheus"
          ports:
            - name: http
              containerPort: 9090
          volumeMounts:
            - name: config
              mountPath: /etc/prometheus
      volumes:
        - name: config
          configMap:
            name: lab29-prometheus-config
            items:
              - key: prometheus.yml
                path: prometheus.yml
              - key: alert.rules.yml
                path: alert.rules.yml
```

`labs/lesson_29/k8s/monitoring/prometheus-service.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: lab29-prometheus
  namespace: monitoring
  labels:
    app: lab29-prometheus
spec:
  type: ClusterIP
  selector:
    app: lab29-prometheus
  ports:
    - name: http
      port: 9090
      targetPort: 9090
```

Apply:

```bash
kubectl apply -f prometheus-deployment.yaml
kubectl apply -f prometheus-service.yaml

kubectl get deploy,svc -n monitoring
kubectl get pods -n monitoring

# kubectl logs deploy/lab29-prometheus -n monitoring | head -n 30
```

---

## 5) Access Prometheus UI

Port-forward:

```bash
kubectl port-forward svc/lab29-prometheus -n monitoring 9090:9090
```

Open: `http://127.0.0.1:9090/`.

Check:

- **Status → Targets**:
    - `prometheus` should be `UP`.
    - `kube-state-metrics` same `UP`.
- **Status → Rules**:
    - There should be a group `lab27-k8s` with two alerts.

---

## 6) Basic PromQL for lab27

Try in Prom UI → **Graph → Expression**:

### Deployments

```
kube_deployment_spec_replicas{namespace="lab27"}
kube_deployment_status_replicas_available{namespace="lab27"}
```

Expect to see:

- Rows for `lab27-web` and `lab27-redis` (assuming the Redis Deployment is in the same namespace).
- Values of `1` (or another number if changed the replicas).

### Pods

```
kube_pod_container_status_ready{namespace="lab27"}
kube_pod_container_status_restarts_total{namespace="lab27"}
```

Check:

- `Ready = 1` → the container is ready.
- `restarts_total > 0` → there have been restarts.

### Alerts

If everything is fine, alerts should be `Inactive`:

```
ALERTS{alertname="Lab27DeploymentNotReady"}
ALERTS{alertname="Lab27PodRestarts"}
```

---

## 7) Simulate failure (for alerts)

### 7.1 Deployment not ready

Change `web` Deployment, to break the image:

```bash
kubectl patch deployment lab27-web -n lab27 \
  -p '{"spec":{"template":{"spec":{"containers":[{"name":"web","image":"ghcr.io/VlrRbn/lab25-web:nonexistent"}]}}}}'
```

Wait 1-2 min.

Check:

```bash
kubectl get pods -n lab27
kubectl describe deploy lab27-web -n lab27
```

In Prometheus:

- `kube_deployment_status_replicas_available{namespace="lab27",deployment="lab27-web"}` will drop to `0`.
- The `Lab27DeploymentNotReady` alert should go from `Pending` to `Firing` (after the `for: 2m` period).

Revert to the normal image (patch it back or run `kubectl rollout undo deployment lab27-web -n lab27`) and wait for the alert to move to `Resolved`.

### 7.2 Pod restarts

You can either force the application to crash (a temporary bug), or:

- Manually delete the Pod:

```bash
kubectl delete pod -l app=lab27-web -n lab27
```

What happens:

- The old Pod is deleted.
- The ReplicaSet creates a new Pod.

This is **not** a container restart inside the same Pod, it’s a brand new Pod, so `restarts_total` will **not** increase. This is important.

---

## 8) Grafana runs in Docker/Compose.

Idea:

Prometheus lives on the host at `127.0.0.1:9090` (via `kubectl port-forward`).

Grafana lives in a container inside Docker Compose.

Possible URLs for the data source:

- `http://host.docker.internal:9090` — if Docker supports this.
- Or `http://<HOST_IP>:9090` (for example, `http://192.168.x.x:9090`).

```bash
kubectl port-forward svc/lab29-prometheus -n monitoring 9090:9090

#inside grafana
docker compose exec grafana sh
apk add curl 2>/dev/null || true
curl -v http://host.docker.internal:9090/-/ready | head

# or from host
curl -sS http://localhost:9090/-/ready | head
```

Next steps:

- Create a new Prometheus data source in Grafana → point the URL to that port.
- Build a couple of panels:
    - `kube_deployment_status_replicas_available{namespace="lab27"}`
        
        (lines, grouped by `deployment`)
        
    - `increase(kube_pod_container_status_restarts_total{namespace="lab27"}[5m])`
        
        (stacked bar, grouped by `pod`)
        

This closes the loop:

`k8s → kube-state-metrics → Prometheus in k8s → Grafana outside the cluster`.

---

## Core

- [ ]  The `monitoring` namespace is created.
- [ ]  The kube-state-metrics Pod is `Running` and its Service is reachable.
- [ ]  The Prometheus Deployment + Service (`lab29-prometheus`) are running and the Targets are `UP`.
- [ ]  Can see `kube_*` k8s metrics for the `lab27` namespace.
- [ ]  The `Lab27DeploymentNotReady` and `Lab27PodRestarts` alerts actually go `Firing` / `Resolved` during simulations.
- [ ]  Understand which exact KSM metrics are used in the expressions (`spec_replicas`, `status_replicas_available`, `restarts_total`).
- [ ]  Have a simple Grafana dashboard for `lab27` (using this Prometheus).
- [ ]  Can explain how k8s-level monitoring (via kube-state-metrics) differs from app-level monitoring (via Nginx/blackbox/HTTP SLIs from previous lessons).

---

## Acceptance Criteria

- [ ]  A dedicated Prometheus is running **inside** the k8s cluster and scraping kube-state-metrics.
- [ ]  Can see the state of `lab27` Deployments and Pods via PromQL.
- [ ]  Basic alerts for “Deployment not healthy” and “Pod is restarting” are working.
- [ ]  Can simulate a failure and, based on metrics/alerts, understand what exactly is broken.

---

## Summary

- Added **k8s-native monitoring** to the cluster: now can see not only logs and system metrics, but also the **state of k8s objects**.
- Deployed kube-state-metrics and Prometheus, and wrote first **k8s-focused alerts**.
- Now have the full chain:
    - App-level observability (Nginx/HTTP golden signals)
    - k8s-level observability (Deployments/Pods via kube-state-metrics).

---

## Artifacts

- `lesson_29.md`
- `labs/lesson_29/k8s/monitoring/monitoring-namespace.yaml`
- `labs/lesson_29/k8s/monitoring/kube-state-metrics-rbac.yaml`
- `labs/lesson_29/k8s/monitoring/kube-state-metrics-deployment.yaml`
- `labs/lesson_29/k8s/monitoring/prometheus-config.yaml`
- `labs/lesson_29/k8s/monitoring/prometheus-deployment.yaml`
- `labs/lesson_29/k8s/monitoring/prometheus-service.yaml`
- `labs/lesson_29/k8s/compose/docker-compose.yml`
- `labs/lesson_29/k8s/compose/provisioning/datasource/lab29-prometheus.yml`