# lesson_22

---

# End-to-End Observability: Golden Signals, SLOs & Runbook

**Date:** 2025-11-14

**Topic:** Use existing stack (Nginx + Prometheus + Alertmanager + Loki + Grafana) to build **golden-signals dashboard**, basic **SLO math**, recording rules, alerts, and a small **runbook** for incidents.

> No new tools. Only wiring together all what built.
> 

---

## Goals

- Tag service (`service="labweb"`, `env="lab"`) consistently in metrics & logs.
- Define **golden signals** for `labweb`: latency, traffic, errors, saturation.
- Add **recording rules** in Prometheus for SLI metrics (rates, latencies).
- Configure **SLO-style alerts** (fast burn + slow burn).
- Create a **Grafana dashboard**.
- Simulate failures and walk through diagnose → verify → close.

---

## Pocket Cheat

| Thing | Example | Why |
| --- | --- | --- |
| Labeling | `service="labweb", env="lab"` | Tie metrics/logs together |
| Traffic | `rate(nginx_http_requests_total{service="labweb"}[5m])` | RPS |
| Errors | `rate(nginx_http_requests_total{service="labweb",status=~"5.."}[5m])` | Error rate |
| Latency (99th) | `histogram_quantile(0.99, sum by (le) (rate(http_request_duration_seconds_bucket{service="labweb"}[5m])))` | Tail latency (if you add histogram) |
| Recording rule | `- record: labweb:http_5xx_rate_5m` | Reuse in alerts/dashboards |
| SLO alert | `labweb:http_error_ratio_5m > 0.02` | >2% errors |

---

## Notes

- The four golden signals (SRE classic): **Latency, Traffic, Errors, Saturation**.
- **SLI** = a “quality” metric (for example, the proportion of successful requests).
- **SLO** = the target value for an SLI (for example, ≥ 99% successful requests over 30 days).
- Use a **short SLO evaluation window for alerting** (5–30 minutes).

---

## Security Checklist

- Do not add extra labels such as `user_id` — that is already PII.
- SLOs and alerts must not rely on raw IPs/logins, only on aggregated data.
- Do not include sensitive fields from logs (passwords, tokens, etc.) in dashboards.

---

## Pitfalls

- Without consistent labels (e.g. `service`, `env`), it’s hard to correlate metrics and logs.
- SLO windows that are too short → “flapping” alerts and constant noise.
- No recording rules → complex expressions everywhere and hard to maintain.

---

## Layout

```
labs/lesson_22/compose_golden/
├─ alertmanager/
│  └─ entrypoint.sh
├─ grafana/
│  ├─ dashboards/
│  │  └─ Lab_Dashboards/
│  │     ├─ labweb-golden-signals.json
│  │     ├─ nginx-mini.json
│  │     └─ node-mini.json
│  ├─ provisioning/
│  │  ├─ alerting/
│  │  │  └─ alerts.yml
│  │  ├─ dashboards/
│  │  │  └─ dashboards.yml
│  │  ├─ datasources/
│  │  │  └─ datasource.yml
│  │  └─ plugins/
│  └─ tools/
│     └─ grafana-export-dashboard.sh
├─ positions/
│  └─ positions.yaml
├─ rules/
│  └─ alert.rules.yml
├─ templates/
│  └─ msg.tmpl
├─ blackbox.yml
├─ docker-compose.yml
├─ grafana.ini
├─ loki-config.yml
├─ prometheus.yml
├─ promtail-config.yml
└─ recording.rules.yml
```

---

## 1) Label `service="labweb"` & `env="lab"`

### 1.1 Nginx metrics

In the Nginx exporter (the `nginx_http_requests_total` metric) there are already standard labels (`status`, `instance`, etc.).

We’ll add `service`/`env` via Prometheus relabeling.

В `prometheus.yml` (job `nginx`):

```yaml
  - job_name: 'nginx'
    static_configs:
      - targets: ['nginx_exporter:9113']
        labels:
          instance: 'local'
          service: 'labweb'
          env: 'lab'
```

Restart or reload Prometheus:

```bash
# web.enable-lifecycle
curl -X POST http://127.0.0.1:9090/-/reload
# or docker compose restart prometheus
```

### 1.2 Logs (Loki / Promtail)

In `promtail-config.yml` (nginx job):

```yaml
  - job_name: nginx
    static_configs:
      - targets: [localhost]
        labels:
          job: nginx
          service: labweb
          env: lab
          __path__: /var/log/nginx/access.json
```

Restart promtail:

```bash
docker compose restart promtail
```

Check:

- Prometheus: `rate(nginx_http_requests_total{service="labweb"}[5m])`.
- Loki (Grafana Explore): `{service="labweb"} | json | line_format "{{.request}} {{.status}}"`.

---

## 2) Recording rules (SLI)

Create `labs/lesson_22/compose_golden/recording.rules.yml`:

```yaml
groups:
- name: labweb-sli
  interval: 30s
  rules:
    # Traffic (RPS)
    - record: labweb:http_requests_total_5m
      expr: sum(rate(nginx_http_requests_total{service="labweb"}[5m]))

    # 5xx errors (RPS)
    - record: labweb:http_5xx_rate_5m
      expr: sum(rate(nginx_http_requests_total{service="labweb",status=~"5.."}[5m]))

    # Error ratio (5xx / all)
    - record: labweb:http_error_ratio_5m
      expr: labweb:http_5xx_rate_5m / clamp_min(labweb:http_requests_total_5m, 0.0001)

    # Rough saturation: CPU usage (node)
    - record: labweb:cpu_usage_ratio_5m
      expr: 1 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m]))
```

Include the file in Prometheus:

`prometheus.yml`:

```yaml
rule_files:
  - /etc/prometheus/rules/*.yml
  - /etc/prometheus/recording.rules.yml
```

And add it to the docker-compose mounts:

```yaml
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - ./rules:/etc/prometheus/rules:ro
      - ./recording.rules.yml:/etc/prometheus/recording.rules.yml:ro
```

Restart prometheus:

```bash
docker compose restart prometheus
```

Check:

- In Prometheus UI: **Status → Rules** → group`labweb-sli` exist.
- Query:
    - `labweb:http_requests_total_5m`
    - `labweb:http_5xx_rate_5m`
    - `labweb:http_error_ratio_5m`
    - `labweb:cpu_usage_ratio_5m`

---

## 3) SLO-style alerts (Prometheus side)

Include in `alert.rules.yml` (lesson_17/18):

```yaml
  - name: labweb-slo
    rules:
    - alert: LabwebHighErrorRateFast
      expr: labweb:http_error_ratio_5m > 0.1
      for: 5m
      labels:
        severity: critical
        service: labweb
        slo_window: "fast"
      annotations:
        summary: "labweb error ratio {{ $value | humanizePercentage }} (>10%, 5m)"
        description: "More than 10% of requests are 5xx over the last 5 minutes."

    - alert: LabwebHighErrorRateSlow
      expr: labweb:http_error_ratio_5m > 0.02
      for: 30m
      labels:
        severity: warning
        service: labweb
        slo_window: "slow"
      annotations:
        summary: "labweb error ratio {{ $value | humanizePercentage }} (>2%, 30m)"
        description: "Sustained elevated 5xx ratio; check deployment or backend health."

    - alert: LabwebHighCpu
      expr: labweb:cpu_usage_ratio_5m > 0.85
      for: 10m
      labels:
        severity: warning
        service: labweb
      annotations:
        summary: "labweb CPU {{ $value | humanizePercentage }} (>85%, 5m avg)"
        description: "Node CPU usage is above 85% for 10 minutes."
```

Reload prometheus:

```bash
curl -X POST http://127.0.0.1:9090/-/reload
```

Check:

- `http://127.0.0.1:9090/rules` — group `labweb-slo`.
- `http://127.0.0.1:9090/alerts` — all **Inactive**.

---

## 4) Dashboard: `labweb-golden-signals.json`

 `labs/lesson_22/compose_golden/grafana/dashboards/labweb-golden-signals.json` :

```json
{
  "uid": "labweb-golden",
  "title": "Labweb Golden Signals",
  "tags": ["lab", "labweb", "golden"],
  "schemaVersion": 39,
  "version": 1,
  "refresh": "10s",
  "panels": [
    {
      "type": "timeseries",
      "title": "Traffic (RPS)",
      "datasource": {"type": "prometheus", "uid": "ds_prom"},
      "targets": [
        {"expr": "labweb:http_requests_total_5m", "legendFormat": "RPS"}
      ],
      "gridPos": {"h": 6, "w": 12, "x": 0, "y": 0}
    },
    {
      "type": "timeseries",
      "title": "Error ratio (5m)",
      "datasource": {"type": "prometheus", "uid": "ds_prom"},
      "targets": [
        {"expr": "labweb:http_error_ratio_5m", "legendFormat": "5xx ratio"}
      ],
      "gridPos": {"h": 6, "w": 12, "x": 12, "y": 0}
    },
    {
      "type": "timeseries",
      "title": "CPU usage (node)",
      "datasource": {"type": "prometheus", "uid": "ds_prom"},
      "targets": [
        {"expr": "labweb:cpu_usage_ratio_5m * 100", "legendFormat": "CPU %"}
      ],
      "gridPos": {"h": 6, "w": 12, "x": 0, "y": 6}
    },
    {
      "type": "timeseries",
      "title": "5xx rate",
      "datasource": {"type": "prometheus", "uid": "ds_prom"},
      "targets": [
        {"expr": "labweb:http_5xx_rate_5m", "legendFormat": "5xx rps"}
      ],
      "gridPos": {"h": 6, "w": 12, "x": 12, "y": 6}
    },
    {
      "type": "logs",
      "title": "Labweb logs (5xx only)",
      "datasource": {"type": "loki", "uid": "ds_loki"},
      "targets": [
        {"expr": "{service=\"labweb\"} | json | status=~\"5..\""}
      ],
      "gridPos": {"h": 9, "w": 24, "x": 0, "y": 12}
    }
  ]
}
```

Restart Grafana (with provisioning from `lesson_21`):

```bash
docker compose restart grafana
```

Check:

- Dashboards → in directory `Lab_Dashboards` appeared `Labweb Golden Signals`.
- We can see traffic, error ratio, CPU, 5xx rate, and logs.

---

## 5) Failure drills

### Drill 1 — Error burst

- In the Nginx config, temporarily change `/health` to `return 500;`, as in `lesson_18`.

Or in Nginx conf `/health` do:

```bash
location /health {
    return 500;
}
```

- Generate traffic:

```bash
for i in {1..200}; do curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1/health; done
```

- Wait 5–10 minutes:
    - `LabwebHighErrorRateFast` should go **Firing**.
    - The `Error ratio` and `5xx rate` dashboards spike, and the logs are full of 5xx.
- Revert `/health` back → reload → wait for the alert to go **Resolved**.

### Drill 2 — High CPU

- Start a CPU-heavy workload (compress a large file, run `yes > /dev/null`, etc. for a while).
- Monitor `labweb:cpu_usage_ratio_5m`.
- Adjust the threshold/window if needed so that the alert reliably fires and then clears.

---

## Core

- [ ]  `service="labweb"` and `env="lab"` labels are added in Prometheus and Loki.
- [ ]  `labweb:*` recording rules are created and visible in Prometheus.
- [ ]  The SLO alert `LabwebHighErrorRateFast` is verified to go Firing/Resolved.
- [ ]  The `Labweb Golden Signals` dashboard shows data.
- [ ]  Both fast & slow SLO alerts work (with different windows and severities).
- [ ]  The CPU alert is tuned to a reasonable threshold.
- [ ]  All changes are committed to git (rules, dashboard JSON).

---

## Acceptance Criteria

- [ ]  Metrics and logs are correlated using a single pair of labels (`service="labweb"`, `env="lab"`).
- [ ]  Recording rules exist for traffic, errors, and CPU, and they are used in the dashboard and alerts.
- [ ]  SLO alerts fire during the simulation and go to Resolved after the issue is fixed.

---

## Summary

- Combined the previously set up components (Nginx, Prometheus, Alertmanager, Loki, Grafana) into a single **production-ready observability stack** for the `labweb` service.
- Introduced unified labels, golden signals, recording rules, and SLO-based alerts.
- Can be presented as a mini-project: “Observability for a Single Service”.

---

## Artifacts

- `lesson_22.md` (this file)
- `labs/lesson_22/compose_golden/`