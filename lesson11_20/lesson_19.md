# lesson_19

---

# Alertmanager Notifications: Email/Telegram, Routing, Silences, Templates

**Date:** 2025-11-04

**Topic:** Alertmanager receivers (email/Telegram), label-based routing, grouping, silences/inhibition, templates, test alerts with `amtool`, hot-reload

---

## Goals

- Wire **real notifications**: SMTP email and Telegram (via webhook bot).
- Organize routing by **severity** / **service** with grouping and **inhibition**.
- Use **silences** and **durations** to pause noisy alerts safely.
- Add **template** for concise messages.
- Validate with `amtool` and forced-firing tests.

---

## Pocket Cheat

| Command / File | What it does | Why |
| --- | --- | --- |
| `docker compose up -d` | Start/refresh stack | One command |
| `curl -X POST 127.0.0.1:9090/-/reload` | Hot-reload Prom | No restart |
| `amtool --alertmanager.url=http://127.0.0.1:9093 alert add ...` | Inject test alert | E2E test |
| `amtool silence add --duration=2h alertname=…` | Silence alerts | Mute noise |
| `amtool silence query` | List silences | See what’s muted |
| `amtool check-config alertmanager.yml` | Validate AM config | Catch typos |
| `route / receivers / inhibit_rules` | AM config keys | Control flow |
| `templates/*.tmpl` | Message templates | Clean notifications |

---

## Notes

- Alertmanager routes alerts using **labels** (e.g., `severity`, `service`).
- **Grouping** reduces spam: batch many similar alerts into one notification.
- **Inhibition**: suppress child alerts when a parent (e.g., `NodeDown`) is firing.
- **Silences**: time-based mute with a comment and matchers — safer, auditable.
- **Telegram:** use the popular **alertmanager-bot webhook** or any compatible shim; if that’s not available, fall back to email (SMTP app password).
- **Keep secrets** in **`.env`**/Vault; do not commit them to Git.

---

## Security Checklist

- Secrets (SMTP auth, Telegram tokens) — в `.env` or Docker secrets; not in git.
- Alertmanager UI on `127.0.0.1`.
- Lock down permissions on `alertmanager.yml` and `.env` (`0600`).
- Add clear comments to silences (who/why/until when).

---

## Pitfalls

- Labels don’t match route matchers → notifications never arrive.
- Missing `group_by`/`group_wait` → tons of emails for every tiny event.
- Telegram: wrong webhook URL/token → no 200 OK, no messages.
- `for:` too short → flapping alerts, lots of noise.

---

## Layout

```
labs/lesson_19/compose/
├─ alert.rules.yml
├─ alertmanager.yml
├─ blackbox.yml
├─ docker-compose.yml
├─ prometheus.yml
├─ templates/
│  └─ msg.tmpl
└─ .env            # secrets (not in git)
```

> Use `labs/lesson_18/compose` as the base and copy it to `labs/lesson_19/compose`, then replace the files listed below.
> 

---

## 0) Node Exporter (systemd on host) from lesson_17

```bash
# Create user & dirs
sudo useradd --no-create-home --system --shell /usr/sbin/nologin nodeexp || true
sudo mkdir -p /opt/node_exporter /var/lib/node_exporter
cd /opt/node_exporter

# Download & install
ver="1.8.1"
curl -fsSL "https://github.com/prometheus/node_exporter/releases/download/v${ver}/node_exporter-${ver}.linux-amd64.tar.gz" -o /tmp/ne.tgz
sudo mv /tmp/ne.tgz /opt/node_exporter/
sudo tar -xzf ne.tgz --strip-components=1
sudo chown -R nodeexp:nodeexp /opt/node_exporter
sudo rm -f ne.tgz

# Env file (flags)
sudo tee /etc/default/node_exporter >/dev/null <<'ENV'
NODE_EXPORTER_OPTS='
  --collector.systemd
  --collector.tcpstat
  --web.listen-address=0.0.0.0:9100
  --collector.disable-defaults
  --collector.cpu
  --collector.meminfo
  --collector.filesystem
  --collector.loadavg
  --collector.netdev
  --collector.diskstats
'
ENV

# Systemd unit
sudo tee /etc/systemd/system/node_exporter.service >/dev/null <<'UNIT'
[Unit]
Description=Prometheus Node Exporter
After=network-online.target
Wants=network-online.target

[Service]
User=nodeexp
Group=nodeexp
EnvironmentFile=/etc/default/node_exporter
ExecStart=/opt/node_exporter/node_exporter $NODE_EXPORTER_OPTS
Restart=on-failure
RestartSec=5
# Hardening
NoNewPrivileges=yes
ProtectSystem=full
ProtectHome=yes
PrivateTmp=yes
ProtectControlGroups=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectClock=yes
LockPersonality=yes

[Install]
WantedBy=multi-user.target
UNIT

sudo systemctl daemon-reload
sudo systemctl enable --now node_exporter
systemctl --no-pager --full status node_exporter | sed -n '1,60p'
curl -s 127.0.0.1:9100/metrics | head
```

---

## 1) Compose with Prometheus, env & templates

`labs/lesson_19/compose/docker-compose.yml`

```yaml
services:
  alertmanager:
    image: prom/alertmanager:latest
    container_name: lab19-alertmanager
    environment:
      TELEGRAM_TOKEN: "${TELEGRAM_TOKEN}"
      TELEGRAM_CHAT_ID: "${TELEGRAM_CHAT_ID}"
    volumes:
      - ./alertmanager.yml:/etc/alertmanager/alertmanager.yml
      - ./templates:/etc/alertmanager/templates:ro
    ports:
      - "9093:9093"
    command:
      - "--config.file=/etc/alertmanager/alertmanager.yml"
    restart: always
    
  nginx_exporter:
    image: nginx/nginx-prometheus-exporter:latest
    container_name: lab19-nginx-exporter
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
    container_name: lab19-blackbox
    networks: [monitoring]
    command:
      - "--config.file=/etc/blackbox/blackbox.yml"
      - "--web.listen-address=0.0.0.0:9115"
    ports:
      - "127.0.0.1:9115:9115"
    volumes:
      - ./blackbox.yml:/etc/blackbox/blackbox.yml:ro
    restart: unless-stopped
  
  prometheus:
    image: prom/prometheus:latest
    container_name: lab19-prometheus
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
      - ./test-alert.yml:/etc/prometheus/test-alert.yml
    ports:
      - "127.0.0.1:9090:9090"
    depends_on:
      - alertmanager
      - blackbox
      - nginx_exporter
    restart: unless-stopped
  
networks:
  monitoring:
    driver: bridge
```

`labs/lesson_19/compose/prometheus.yml`

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - /etc/prometheus/alert.rules.yml
  - /etc/prometheus/test-alert.yml
  
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
      - targets: ['lab19-nginx-exporter:9113']
        labels:
          instance: 'local'
```

`labs/lesson_19/compose/.env` (stop git.)

```
# SMTP
AM_SMTP_FROM=post@mail.com
AM_SMTP_SMARTHOST=smtp.post.com:587
AM_SMTP_USER=post@mail.com
AM_SMTP_PASS=******

# Telegram (via webhook-compatible bridge)
# AM_TG_WEBHOOK_URL=https://telegram-bridge.local/alert
```

---

## 2) Alertmanager config: routes, email, telegram, inhibition; Alertrules and Blackbox

`labs/lesson_19/compose/alert.rules.yml`

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

`labs/lesson_19/compose/alertmanager.yml`

```yaml
global:
  resolve_timeout: 5m
  
templates:
  - '/etc/alertmanager/templates/*.tmpl'

route:
  receiver: 'telegram'
  group_by: ['alertname','job','instance']
  group_wait: 10s
  group_interval: 1m
  repeat_interval: 2h

receivers:
  - name: 'telegram'
    telegram_configs:
      - bot_token: '***********'
        chat_id: ***********
        parse_mode: 'HTML'
        message: '{{ template "body_html" . }}'
```

---

`labs/lesson_19/compose/blackbox.yml`

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

## 3) Templates

`labs/lesson_19/compose/templates/msg.tmpl`

```
{{ define "body_html" }}
<b>{{ .CommonLabels.alertname }}</b> ({{ .Status }})
{{ range .Alerts }}
<b>{{ .Annotations.summary }}</b>
{{ .Annotations.description }}
Labels: {{ .Labels }}
{{ end }}
{{ end }}
```

---

Run:

```bash
docker compose up -d
docker compose ps
docker compose logs -f prometheus | sed -n '1,80p'

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

## 4) Validate

```bash
# Validate AM config
docker exec -it lab19-alertmanager amtool check-config /etc/alertmanager/alertmanager.yml

# List routes/receivers in UI
xdg-open http://127.0.0.1:9093 || true
```

> If email isn’t delivered: check the SMTP host/port, the app password, and the `lab19-alertmanager` container logs.
> 

---

## 5) Fire test alerts (with labels)

Let’s inject synthetic alerts:

```bash
# sudo apt-get install -y alertmanager

# amtool --alertmanager.url=http://127.0.0.1:9093 alert add TestWarning \
#  alertname=TestWarning severity=warning service=nginx instance=local \
#  --annotation summary="Warning test" --annotation description="Synthetic warn"

# Docker + --entrypoint /bin/amtool
docker run --rm --network host \
  --entrypoint /bin/amtool \
  prom/alertmanager:latest \
  --alertmanager.url=http://127.0.0.1:9093 \
  alert add TestWarning severity=warning service=nginx instance=local \
  --annotation summary="Warning test" \
  --annotation description="Synthetic warn"

# amtool --alertmanager.url=http://127.0.0.1:9093 alert add TestCritical \
#  alertname=TestCritical severity=critical service=infra instance=local \
#  --annotation summary="Critical test" --annotation description="Synthetic crit"

# Docker + --entrypoint /bin/amtool
docker run --rm --network host \
  --entrypoint /bin/amtool \
  prom/alertmanager:latest \
  --alertmanager.url=http://127.0.0.1:9093 \
  alert add TestCritical severity=critical service=infra instance=local \
  --annotation summary="Critical test" \
  --annotation description="Synthetic crit"
  
curl -s http://127.0.0.1:9093/api/v2/alerts | jq .
```

Resolve this alert:

```bash
curl -sS -X POST -H 'Content-Type: application/json' \
  -d '[{
    "labels": {
      "alertname": "TestWarning",
      "severity": "warning",
      "service": "nginx",
      "instance": "local"
    },
    "status": { "state": "resolved" },
    "endsAt": "'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'"
  }]' \
  http://127.0.0.1:9093/api/v2/alerts

  
curl -sS -X POST -H 'Content-Type: application/json' \
  -d '[{
    "labels": {
      "alertname": "TestCritical",
      "severity": "critical",
      "service": "infra",
      "instance": "local"
    },
    "status": { "state": "resolved" },
    "endsAt": "'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'"
  }]' \
  http://127.0.0.1:9093/api/v2/alerts
```

Check:

- **Alertmanager UI:** both alerts are **firing**; verify the **receiver** (warning → `mail-warning`; critical → `telegram-critical`).
- **Webhook/email logs:** a notification was received.

```bash
# amtool --alertmanager.url=http://127.0.0.1:9093 alert query

docker run --rm --network host \
  --entrypoint /bin/amtool \
  prom/alertmanager:latest \
  --alertmanager.url=http://127.0.0.1:9093 \
  alert query --active
```

---

## 6) Silences & inhibition sanity

Create a 30-minute silence (all nginx warnings):

```bash
# amtool --alertmanager.url=http://127.0.0.1:9093 silence add --duration=30m \
#  --comment="maintenance nginx" --author="you" severity=warning service=nginx

# Docker + --entrypoint /bin/amtool
docker run --rm --network host \
  --entrypoint /bin/amtool \
  prom/alertmanager:latest \
  --alertmanager.url=http://127.0.0.1:9093 \
  silence add --duration=30m \
  --comment="maintenance nginx" --author="you" \
  severity=warning service=nginx

  
# amtool --alertmanager.url=http://127.0.0.1:9093 silence query
docker run --rm --network host --entrypoint /bin/amtool prom/alertmanager:latest \
  --alertmanager.url=http://127.0.0.1:9093 \
  silence query
  
# amtool --alertmanager.url=http://127.0.0.1:9093 --output=json silence query | jq .     # JSON (easy for parsing)
docker run --rm --network host --entrypoint /bin/amtool prom/alertmanager:latest \
  --alertmanager.url=http://127.0.0.1:9093 --output=json \
  silence query
  
# Expire silence by ID
docker run --rm --network host --entrypoint /bin/amtool prom/alertmanager:latest \
  --alertmanager.url=http://127.0.0.1:9093 \
  silence expire <SILENCE_ID>

```

Testing inhibition is simple: stop `node_exporter` (as in lesson_18), and in parallel trigger the `RootFS80Percent` condition — the latter will be inhibited when the `instance` label matches.

---

## Acceptance Criteria

- [ ]  **Email receiver:** test alert with `severity=warning` delivered to inbox.
- [ ]  **Telegram/webhook receiver:** message received for `severity=critical`.
- [ ]  **Routes:** `warning → mail-warning`, `service=nginx` also → `mail-nginx` (fan-out), `critical → telegram-critical`.
- [ ]  **Silences:** can be added, visible, and effective (no notification arrives).
- [ ]  **Inhibition:** when `NodeExporterDown` fires, “child” alerts on the same `instance` are suppressed.
- [ ]  **Templates:** applied — emails have a clean subject and body.

---

## Summary

- Alertmanager is configured with email/Telegram (webhook) and label-based routing.
- Grouping, silences, and inhibition are in place to tame noise.
- Message templates make alerts easier to read.
- E2E tests run via `amtool` and the “real” alerts from lesson_18.

## To repeat

- Add distinct channels per service/team (DB, web).
- Split **receivers** into separate files and `include` them (when the config grows).
- Set up on-call rotation (use `team`/`oncall` labels).
- Keep a “silence template” for maintenance windows.

## Pitfalls

- Don’t keep real passwords in Git; use `.env`/Vault.
- Stick to a **single label schema** (`service`, `severity`, `team`) — otherwise routing will drift.
- Don’t set `repeat_interval` too small — you’ll get spam.
- Always document silences (who/why/until when).

---

## Artifacts

- `lesson_19.md` (this file)
- `labs/lesson_19/compose/{docker-compose.yml,alertmanager.yml,templates/msg.tmpl}`