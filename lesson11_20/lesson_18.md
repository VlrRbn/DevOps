# lesson_18

---

# Alerts & Probes: Alertmanager + Blackbox + Nginx Exporter

**Date:** 2025-11-01

**Topic:** Wire **Alertmanager**, add **blackbox_exporter** (HTTP probes) and **nginx-prometheus-exporter** (Nginx), create actionable alerts, and verify end-to-end

---

## Goals

- Add **Alertmanager** to lesson_17 stack and route alerts.
- Probe endpoints with **blackbox_exporter** (HTTP/HTTPS).
- Expose Nginx metrics via **nginx-prometheus-exporter** + `/nginx_status`.
- Create useful alerts (node, HTTP probes, Nginx 5xx/rate).
- Prove alert lifecycle: **Pending → Firing → Resolved**.

---

## Pocket Cheat

| Command / File | What it does | Why |
| --- | --- | --- |
| `docker compose up -d` | Start/refresh stack | One command |
| `http://127.0.0.1:9093` | Alertmanager UI | See alerts/routes |
| `http://127.0.0.1:9115/probe?module=http_2xx&target=...` | Blackbox probe | Debug probes |
| `curl -s 127.0.0.1:9113/metrics | head` | Nginx exporter metrics | Metrics |
| `promtool check config` | Validate Prom config | Catch typos |
| `curl -X POST 127.0.0.1:9090/-/reload` | Hot-reload Prom | Apply changes |

---

## Notes

- **Alertmanager** handles notifications and dedup/silences. We’ll set up basic **stdout** logging. Integrations (email/Telegram) will be next.
- **blackbox_exporter** performs active probes (HTTP, ICMP, TCP). We’ll probe `/health` and the site root.
- **nginx-prometheus-exporter** reads **`/nginx_status`** (stub_status) and exposes metrics on `:9113`.
- Principle: **each new service = a new scrape job + an alert + a check**.

---

## Security Checklist

- Access to `/nginx_status` — only from `127.0.0.1`.
- Alertmanager/Prometheus/Grafana — listen on `127.0.0.1` (don’t expose them publicly without protection).
- Blackbox: don’t enable the `icmp` module unless needed/authorized.
- Keep versions pinned in (Docker) Compose.

---

## Pitfalls

- The Prometheus container can’t see the host’s `127.0.0.1` — use `host.docker.internal` or the actual `HOST_IP`.
- If `/nginx_status` is forgotten, the exporter returns zeros/errors.
- Blackbox probes without a correct `module` will always fail.
- Alerts “stuck in pending” — either the `for:` hasn’t elapsed yet, or the metric is too noisy/flappy.

---

## Layout

```
labs/lesson_18/
└─ compose/
   ├─ alert.rules.yml
   ├─ alertmanager.yml
   ├─ blackbox.yml         # modules for blackbox_exporter
   ├─ docker-compose.yml
   └─ prometheus.yml
```

> Use `lesson_17` as the base: you can copy `labs/lesson_17/compose → labs/lesson_18/compose` and replace the files below.
> 

---

## 1) Enable Nginx stub_status (host)

Add the block to `/etc/nginx/sites-available/lesson_18.conf` and reload:

```
# Allow local metrics endpoint
server {
    listen 127.0.0.1:8080;
    server_name localhost;
    
    location = /nginx_status {
        stub_status;              # enables Nginx counters (active, reading, writing, waiting)
        access_log off;           # don’t spam logs for every metrics hit
        allow 127.0.0.1;          # allow only localhost
        deny all;                 # deny everyone else (must-have protection)
    }
}
```

```bash
sudo nginx -t && sudo systemctl reload nginx
curl -s http://127.0.0.1:8080/nginx_status
```

---

## 2) Compose stack (Prometheus + Alertmanager + Blackbox + Nginx exporter)

`labs/**lesson_18**/compose/docker-compose.yml`

```yaml
services:
  prometheus:
    image: prom/prometheus:latest
    container_name: lab18-prometheus
    ##network_mode: host
    networks: [monitoring]
    extra_hosts:
      - "host.docker.internal:host-gateway"
    command:
      - "--config.file=/etc/prometheus/prometheus.yml"
      - "--storage.tsdb.path=/prometheus"
      - "--storage.tsdb.retention.time=15d"
      - "--storage.tsdb.wal-compression"
      - "--web.listen-address=0.0.0.0:9090"
      - "--web.enable-lifecycle"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - ./alert.rules.yml:/etc/prometheus/alert.rules.yml:ro
      - promdata:/prometheus
    ports:
      - "127.0.0.1:9090:9090"
    depends_on:
      - alertmanager
      - blackbox
      - nginx_exporter
    restart: unless-stopped
    
  alertmanager:
    image: prom/alertmanager:latest
    container_name: lab18-alertmanager
    ##network_mode: host
    networks: [monitoring]
    command:
      - "--config.file=/etc/alertmanager/alertmanager.yml"
      - "--log.level=info"
      - "--web.listen-address=0.0.0.0:9093"
    volumes:
      - ./alertmanager.yml:/etc/alertmanager/alertmanager.yml:ro
    ports:
      - "127.0.0.1:9093:9093"
    restart: unless-stopped
    
  nginx_exporter:
    image: nginx/nginx-prometheus-exporter:latest
    container_name: lab18-nginx-exporter
    ##network_mode: host
    networks: [monitoring]
    extra_hosts:
      - "host.docker.internal:host-gateway"
    command:
      - "--nginx.scrape-uri=http://host.docker.internal:8080/nginx_status"
      - "--web.listen-address=0.0.0.0:9113"
    ports:
      - "127.0.0.1:9113:9113"
    restart: unless-stopped

  blackbox:
    image: prom/blackbox-exporter:latest
    container_name: lab18-blackbox
    networks: [monitoring]
    ##network_mode: host
    command:
      - "--config.file=/etc/blackbox/blackbox.yml"
      - "--web.listen-address=0.0.0.0:9115"
    ports:
      - "127.0.0.1:9115:9115"
    volumes:
      - ./blackbox.yml:/etc/blackbox/blackbox.yml:ro
    restart: unless-stopped

volumes:
  promdata:
  grafdata:
  
networks:
  monitoring:
    driver: bridge
```

---

## 3) Blackbox modules

`labs/**lesson_18**/compose/blackbox.yml`

```yaml
modules:
  http_2xx:
    prober: http
    timeout: 5s
    http:
      method: GET
      preferred_ip_protocol: "ip4"
      valid_http_versions: ["HTTP/1.1", "HTTP/2"]
      fail_if_not_ssl: false
      follow_redirects: true

  http_200_health:
    prober: http
    timeout: 3s
    http:
      method: GET
      valid_status_codes: [200]
      no_follow_redirects: true
```

---

## 4) Prometheus config (jobs & alerts & AM)

`labs/**lesson_18**/compose/prometheus.yml`

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - /etc/prometheus/alert.rules.yml
  
alerting:
  alertmanagers:
    - static_configs:
        - targets: ["alertmanager:9093"]

scrape_configs:

  - job_name: prometheus
    static_configs:
      - targets: ['127.0.0.1:9090']

  - job_name: 'node'
    static_configs:
      - targets: ['host.docker.internal:9100']
        labels:
          instance: 'local'
          
  - job_name: 'blackbox_http'
    metrics_path: /probe
    params:
      module: ["http_2xx"]
    static_configs:
      - targets:
        - http://prometheus:9090/-/healthy
        - http://alertmanager:9093/-/ready
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
        
      - source_labels: [__param_target]
        target_label: instance
        
      - target_label: __address__
        replacement: blackbox:9115
          
  - job_name: 'nginx'
    static_configs:
      ##- targets: ['127.0.0.1:9113']
      - targets: ['lab18-nginx-exporter:9113']
        labels:
          instance: 'local'
```

---

## 5) Alerts (practical & testable)

`labs/lesson_18/compose/alert.rules.yml`

```yaml
groups:
  - name: node-and-http
    interval: 30s
    rules:
      - alert: NodeExporterDown
        expr: up{job="node"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "{{ $labels.job }} on {{ $labels.instance }} is down"
          description: "No scrape data for >1m."
          
      - alert: NginxExporterDown
        expr: up{job="nginx"} == 0
        for: 1m
        labels:
          severity: warning
        annotations:
          summary: "Nginx exporter DOWN on {{ $labels.instance }}"
      
      - alert: HTTPProbeFailed
        expr: probe_success{job="blackbox_http"} == 0
        for: 1m
        labels: { severity: critical }
        annotations:
          summary: "HTTP probe failed ({{ $labels.instance }})"
          description: "Blackbox probe failed."
          
      - alert: NginxHigh5xxRate
        expr: |
          rate(nginx_http_requests_total{status=~"5.."}[2m]) > 0.5  # >0.5 rps 5xx за 2 минуты
        for: 2m
        labels: { severity: warning }
        annotations:
          summary: "Nginx 5xx elevated"
          description: "5xx rate > 0.5 rps for 2m."
          
  - name: fs
    rules:
    - alert: RootFS80Percent
      expr: (1 - node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) > 0.80
      for: 2m
      labels: { severity: warning }
      annotations:
        summary: "Root FS > 80%"
```

---

## 6) Alertmanager (stdout receiver + grouping)

`labs/lesson_18/compose/alertmanager.yml`

```yaml
route:
  group_by: ["alertname", "instance"]
  group_wait: 10s
  group_interval: 2m
  repeat_interval: 2h
  receiver: "stdout"

receivers:
  - name: "stdout"
    webhook_configs:
      - url: "http://httpbin.org/post"   # loopback for demo; AM logs events

# For next lesson: add real receivers (email, telegram) here.
```

> Here we’re using a “pseudo-receiver”: Alertmanager will still log events (and show them in the UI).
> 

---

## 7) Run

```bash
cd labs/lesson_18/compose
docker compose up -d
docker compose ps
# Prom
curl -s http://127.0.0.1:9090/-/ready
# AM
curl -s http://127.0.0.1:9093/-/ready
# Blackbox ping
curl -s "http://127.0.0.1:9115/probe?module=http_2xx&target=http://127.0.0.1/health" | head
# Nginx exporter
curl -s 127.0.0.1:9113/metrics | head
```

---

## 8) Validate (UI + queries)

- Prometheus: `http://127.0.0.1:9090/targets` — all **UP**.
- Alertmanager: `http://127.0.0.1:9093` — empty or active (alerts).
- Queries:
    - `probe_success{job="blackbox_http"}` → `1`
    - `nginx_http_requests_total` → the counter should be increasing (make a couple of requests: `curl /` and `curl /health`).
    - `up` → all `1`.

---

## 9) Force alerts (firing test)

- **HTTPProbeFailed**: temporarily break `/health`:
    
    ```bash
    sudo nginx -t && sudo sed -i 's/return 200/return 500/' /etc/nginx/sites-available/lab18.conf
    sudo systemctl reload nginx
    sleep 40
    # AM UI should show Firing; restore 200 and reload
    sudo git checkout -- /etc/nginx/sites-available/lab18.conf || true
    sudo systemctl reload nginx
    ```
    
- **NodeExporterDown**: `sudo systemctl stop node_exporter && sleep 70 && sudo systemctl start node_exporter`

Check the statuses at `http://127.0.0.1:9090/alerts` and in the Alertmanager UI.

---

## Pitfalls

- Don’t leave `/nginx_status` exposed to the public.
- Don’t forget `web.enable-lifecycle` for Prometheus hot reload.
- Mind the `for:` — short windows make alerts flap.

---

## Summary

- Hooked up **Alertmanager** and set up basic routing.
- Added **blackbox_exporter** for active HTTP checks.
- Brought up **nginx-prometheus-exporter** and enabled `stub_status`.
- Built practical alerts and tested the full cycle from firing to recovery.

---

## Artifacts

- `lesson_18.md` (this file)
- `labs/lesson_18/compose/{docker-compose.yml,prometheus.yml,blackbox.yml,alert.rules.yml,alertmanager.yml}`

---

## To repeat

- Add more blackbox targets (internal services/ports).
- Enable **latency** alerts via `probe_duration_seconds`.
- In next lesson — real notifications (email/Telegram) and alert labels.

---

## Acceptance Criteria (self-check)

- [ ]  **Alertmanager UI** is reachable; Prometheus sees it as an **alerting target**.
- [ ]  **blackbox_exporter** exposes metrics; `probe_success==1` for `/` and `/health`.
- [ ]  **nginx-prometheus-exporter** metrics are available; `/nginx_status` is not accessible externally.
- [ ]  Forcing a `/health` failure triggers **HTTPProbeFailed (Firing)** and then **Resolved**.
- [ ]  **NodeExporterDown** is easily reproducible by stopping the systemd unit and clears after starting it back up.