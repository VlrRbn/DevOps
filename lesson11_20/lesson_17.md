# lesson_17

---

# Monitoring Basics: Prometheus + Node Exporter (+ Grafana)

**Date:** 2025-10-19

**Topic:** Linux host metrics via **node_exporter**, Prometheus scrape, local Grafana, minimal alerting, service hardening, idempotent setup

---

## Goals

- Run **node_exporter** as a systemd service (host metrics).
- Run **Prometheus** (Docker Compose) scraping my node.
- Verify metrics via `/metrics` and Prometheus UI (`/graph`).
- Run **Grafana** (Docker Compose) and add a minimal dashboard.
- Add **basic alert** (instance down) with clear firing test & cleanup.

---

## Pocket Cheat

| Command / File | What it does | Why |
| --- | --- | --- |
| `curl -s 127.0.0.1:9100/metrics | head` | Sanity for node_exporter | Metrics |
| `docker compose up -d` | Start Prometheus/Grafana | One-liner |
| `http://127.0.0.1:9090/graph` | Prometheus UI | Query / debug |
| `avg(rate(node_cpu_seconds_total[2m])) by (mode)` | CPU usage trend | Quick check |
| `node_filesystem_avail_bytes` | Free space bytes | Disk free |
| `node_network_receive_bytes_total` | RX bytes | Network |
| `systemctl status node_exporter` | Service health | Unit status |
| `promtool check config` | Validate Prom config | Catch typos |

---

## Notes

- **node_exporter** exposes host metrics on `:9100`.
- **Prometheus** scrapes targets on intervals and stores time series.
- Keep scrape interval reasonable.
- Use Docker Compose for Prometheus/Grafana; keep **node_exporter on host**.
- Security: bind UIs to `127.0.0.1` by default.

---

## Security Checklist

- Bind Prometheus & Grafana to **localhost** unless needed externally.
- If exposing, protect with UFW and/or Nginx basic auth (from previous lessons).
- Run `node_exporter` as dedicated user; restrict service with `ProtectSystem=yes` etc.
- Don’t mount host root into containers unless necessary.

---

## Pitfalls

- Prometheus can’t reach `node_exporter` (wrong target or bind only to loopback while Prometheus in container) → use `host.docker.internal` or host IP; or run Prometheus on host network.
- Port conflicts (9090/3000/9100) → pick free ports.
- Query returns nothing because **time range** isn’t set (in UI).
- Too aggressive intervals blow up local disk.

---

## Layout

```
labs/lesson_17/
├─ systemd/
│  ├─ node_exporter.service
│  └─ node_exporter.env
└─ compose/
   ├─ docker-compose.yml
   ├─ prometheus.yml
   └─ alert.rules.yml
```

---

## 1) Node Exporter (systemd on host)

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
  --web.listen-address=127.0.0.1:9100
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

## 2) Prometheus (+ Grafana) via Docker Compose

```bash
mkdir -p labs/lesson_17/compose
cd labs/lesson_17/compose
```

### `docker-compose.yml`

```yaml
services:
  prometheus:
    image: prom/prometheus:latest                 # официальный образ
    container_name: lab17-prometheus
    network_mode: host
    command:
      - "--config.file=/etc/prometheus/prometheus.yml"
      - "--web.listen-address=127.0.0.1:9090"     # внутри контейнера
      - "--web.enable-lifecycle"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml:ro     # конфиг
      - ./alert.rules.yml:/etc/prometheus/alert.rules.yml:ro
      - promdata:/prometheus                                   # данные
    restart: unless-stopped

  grafana:
    image: grafana/grafana-oss:latest
    container_name: lab17-grafana
    network_mode: host
    environment:
      - GF_SERVER_HTTP_ADDR=127.0.0.1
      - GF_SERVER_HTTP_PORT=3000
      - GF_SERVER_ROOT_URL=http://localhost:3000
    volumes:
      - grafdata:/var/lib/grafana                             # сохранит дашборды
    restart: unless-stopped

volumes:
  promdata:
  grafdata:
```

### `prometheus.yml`

```yaml
global:
  scrape_interval: 15s           # как часто опрашиваем
  evaluation_interval: 30s       # как часто считаем правила/запросы

rule_files:
  - /etc/prometheus/alert.rules.yml

scrape_configs:
  - job_name: 'node'
    static_configs:
      - targets: ['127.0.0.1:9100']
        labels:
          instance: 'local'
```

Узнать IP хоста:

```bash
IF=$(ip -o route show to default | awk '{print $5;exit}')
HOST_IP=$(ip -4 -o addr show "$IF" | awk '{print $4}' | cut -d/ -f1 | head -1)
echo $HOST_IP   # например 192.168.1.22
```

и поставить `targets: ["192.168.1.22:9100"]`, затем: `docker compose restart prometheus`

### `alert.rules.yml`

```yaml
groups:
  - name: basic-alerts
    rules:
      - alert: NodeExporterDown
        expr: up{job="node"} == 0
        for: 1m
        labels:
          severity: warning
        annotations:
          summary: "Node exporter is down"
          description: "No scrape data from node_exporter for >1m."
```

Запуск:

```bash
docker compose up -d
docker compose ps
docker compose logs -f prometheus | sed -n '1,80p'
```

Проверка UI:

- Prometheus: `http://127.0.0.1:9090/graph` → попробовать `up{job="node"}` (должен быть `1`).
- Grafana: `http://127.0.0.1:3000/` (default admin/admin; заставит сменить пароль).

---

## 3) Quick Queries (Prometheus UI)

В `http://127.0.0.1:9090/graph`:

- CPU usage (per mode):
    
    ```
    avg by (mode) (rate(node_cpu_seconds_total[2m]))
    ```
    
- Memory used (rough):
    
    ```
    1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)
    ```
    
- Root FS free (bytes):
    
    ```
    node_filesystem_avail_bytes{mountpoint="/"}
    ```
    
- Network RX/TX (per-iface):
    
    ```
    rate(node_network_receive_bytes_total[2m])
    rate(node_network_transmit_bytes_total[2m])
    ```
    

---

## 4) Alert sanity (firing test)

Пустить алерт в `firing` для теста: временно **остановить node_exporter** и подождать > 1 минуту.

```bash
sudo systemctl stop node_exporter
sleep 70
# In Prometheus UI → "Alerts": NodeExporterDown should be firing
sudo systemctl start node_exporter
```

---

## 5) Grafana quick start

- Add **Prometheus data source**:  `http://127.0.0.1:9090`.
- Create simple dashboard:
    - Panel 1: `avg by (mode) (rate(node_cpu_seconds_total[2m])) * 100` (CPU).
    - Panel 2: `node_filesystem_avail_bytes{mountpoint="/"} / 1024^3` (GiB).
    - Panel 3: `rate(node_network_receive_bytes_total{device!="lo"}[2m])` / `rate(node_network_transmit_bytes_total{device!="lo"}[2m])` (RX/TX).
- Save dashboard → `labs/lesson_17/grafana-screens/`.

---

## 6) Cleanup

```bash
# Stop Prom/Grafana
cd labs/lesson_17/compose
docker compose down

# Stop node_exporter
sudo systemctl disable --now node_exporter
# Remove (if you want clean host)
# sudo rm -rf /opt/node_exporter /etc/systemd/system/node_exporter.service /etc/default/node_exporter
# sudo systemctl daemon-reload
```

---

## Pitfalls

- Prom in container can’t scrape `127.0.0.1` of host → use `host.docker.internal` or host IP.
- Don’t bind UIs to `0.0.0.0` unless firewalling properly.
- Don’t forget systemd hardening for node_exporter.

---

## Summary

- Deployed **node_exporter** (systemd) and **Prometheus** (Compose) for local host monitoring.
- Verified scrapes/queries and tested a basic alert.
- Added Grafana for visualization; kept exposure on localhost for safety.
- Laid groundwork for multi-target/prometheus-as-code.

---

## Artifacts

- `lesson_17.md` (this file)
- `labs/lesson_17/systemd/node_exporter.service`, `node_exporter.env`
- `labs/lesson_17/compose/docker-compose.yml`, `prometheus.yml`, `alert.rules.yml`

---

## To repeat

- Add more targets to `prometheus.yml` (e.g., remote host or another netns node).
- Tweak `scrape_interval` and retention.
- Secure access via Nginx reverse proxy + basic auth.
- Next days: **Alertmanager**, **Node Exporter on remote**, **exporters for Nginx**, **dashboard as code**.

---

## Acceptance Criteria (self-check)

- [ ]  `node_exporter` runs as systemd service on `127.0.0.1:9100`; `/metrics` responds.
- [ ]  Prometheus UI available at `http://127.0.0.1:9090/graph`; query `up{job="node"}==1`.
- [ ]  3 queries return data (CPU, memory, filesystem).
- [ ]  Temporary stop of node_exporter → **NodeExporterDown** alert turns **firing**; restarts back to **inactive**.
- [ ]  Grafana shows a simple dashboard with node metrics.