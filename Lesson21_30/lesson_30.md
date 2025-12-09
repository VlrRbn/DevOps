# lesson_30

---

# Kubernetes Observability for lab27-web: App Metrics & Dashboard

**Date:** 2025-12-09

**Topic:** Instrument `lab27-web` with **Prometheus metrics**, scrape them from the **in-cluster Prometheus** (lesson_29), and build a **Grafana dashboard** focusing on lab27 web in k8s.

> Reuses: kind cluster lab27, namespace lab27, Prometheus + kube-state-metrics in monitoring (lesson_29), Ingress lab27.local (lesson_28), and lab25 web image as base.
> 

---

## Goals

- Add **/metrics endpoint** to your lab25 Flask app using `prometheus_client`.
- Rebuild/publish image and update **lab27-web Deployment** in k8s.
- Configure Prometheus-in-k8s to **scrape lab27-web /metrics**.
- Create a **Grafana dashboard** with app-level metrics (RPS, errors, latency) for lab27-web in k8s.
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
| `kubectl rollout restart deploy/lab29-prometheus -n monitoring` | Reload Prom config | Pick up new job |
| `rate(labweb_http_requests_total[5m])` | RPS by label | Traffic |
| `increase(labweb_http_requests_total{status="5xx"}[5m])` | Error volume | Errors |

---

## Notes

- We’re already monitoring k8s objects (Deployments/Pods) via kube-state-metrics. Now we’ll add **app-level** metrics.
- Idea: every HTTP request to the lab web app increments counters/histograms, Prometheus scrapes them, Grafana visualizes them.
- We’ll use the **same Prometheus** from lesson_29 (`lab29-prometheus` in the `monitoring` namespace) and the existing Grafana (from Docker Compose).

---

## Security Checklist

- Do not log or export any private data in metrics (logins, tokens, user IP addresses).
- `/metrics` must be accessible only inside the cluster (via a Service), not exposed externally via Ingress.
- When updating the Docker image, use a new tag (don’t overwrite `latest` unless you really know what you’re doing).

---

## Pitfalls

- Forgot to add `prometheus_client` to `requirements.txt` → the app crashes on startup.
- Didn’t update the image tag in the Deployment → k8s keeps running the old image without `/metrics`.
- Didn’t add a scrape job in Prometheus → the metrics exist in the app, but Prometheus doesn’t see them.
- In Grafana, the data source still points to the **old** Prometheus from Docker Compose instead of the k8s Prometheus (or vice versa) — always double-check which URL it’s using.

---