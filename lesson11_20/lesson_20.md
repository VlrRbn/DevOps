# lesson_20

---

# Centralized Logs: Loki + Promtail + Grafana (Nginx JSON)

**Date:** 2025-11-07

**Topic:** Loki (log store) + Promtail (shipper) + Grafana (explore/alerts) for local JSON logs (Nginx), labels/parsers, LogQL queries, and alerting on 5xx spikes

Assumes you already have **Nginx JSON access log** (`/var/log/nginx/access.json`).

---

## Pocket Cheat

| Command / File | What it does | Why |
| --- | --- | --- |
| `docker compose up -d` | Start Loki/Promtail/Grafana | One-liner |
| `http://127.0.0.1:3100/ready` | Loki ready probe | Sanity |
| `http://127.0.0.1:3000` | Grafana UI | Explore & alert |
| `labels {job="nginx"}` | LogQL labels view | See streams |
| `docker compose logs -f promtail` | Tail shipper logs | Debug paths/labels |

---

## Notes

- **Loki** stores logs by **labels** (for example, `job`, `host`, `app`). Queries are made using **LogQL**.
- **Promtail** reads files/journals, assigns labels, and sends them to Loki.
- The JSON logs from Nginx in *lesson_13* are parsed with the `| json` filter and fields like (`status`, `request`, `upstream_*`).
- **Don’t** expose anything externally — everything runs on `127.0.0.1`.

---

## Security Checklist

- Bind Grafana/Loki to `127.0.0.1`.
- Don’t mount extra paths in Promtail; `/var/log/nginx` is enough.
- In production, store log data on a separate disk/partition and set up log rotation.
- Use labels wisely: avoid high-cardinality ones (for example, using the full URL as a label → bad idea).

---

## Pitfalls

- Promtail doesn’t see the file → check the **path** and **pattern** (`/var/log/nginx/access.json`).
- Logs aren’t parsed as JSON → make sure the format from *lesson_13* is clean and consistent.
- Too many labels → slow queries.
- A log alert in Grafana requires **Grafana Alerting**, not Alertmanager.

---

## Layout

```
labs/lesson_20/compose_loki/
├─ positions
   └─ positions.yaml
├─ docker-compose.yml
├─ loki-config.yml
└─ promtail-config.yml
```

---

## 1) Docker Compose stack

`labs/lesson_20/compose/docker-compose.yml`

```yaml
services:
  loki:
    image: grafana/loki:2.9.8
    container_name: lab20-loki
    command: -config.file=/etc/loki/loki-config.yml
    volumes:
      - ./loki-config.yml:/etc/loki/loki-config.yml:ro
      - lokidata:/loki
    ports:
      - "127.0.0.1:3100:3100"     # http://loki:3100
    restart: unless-stopped

  promtail:
    image: grafana/promtail:2.9.8
    container_name: lab20-promtail
    command: -config.file=/etc/promtail/promtail-config.yml
    volumes:
      - ./promtail-config.yml:/etc/promtail/promtail-config.yml:ro
      - /var/log/nginx:/var/log/nginx:ro
      - /var/log/auth.log:/hostlog/auth.log:ro
      - ./positions:/positions
      - /var/log:/hostlog:ro
    depends_on:
      - loki
    restart: unless-stopped

  grafana:
    image: grafana/grafana-oss:latest
    container_name: lab20-grafana
    environment:
      - GF_SERVER_HTTP_ADDR=0.0.0.0
      - GF_SERVER_HTTP_PORT=3000
      - GF_SERVER_ROOT_URL=http://localhost:3000
    ports:
      - "127.0.0.1:3000:3000"
    volumes:
      - grafdata:/var/lib/grafana
    depends_on:
      - loki
    restart: unless-stopped

volumes:
  grafdata:
  lokidata:
```

---

## 2) Loki config (single process, local FS)

`labs/lesson_20/compose/loki-config.yml`

```yaml
auth_enabled: false

server:
  http_listen_port: 3100
  grpc_listen_port: 0

common:
  path_prefix: /loki
  replication_factor: 1
  ring:
    kvstore:
      store: inmemory
  storage:
    filesystem:
      chunks_directory: /loki/chunks
      rules_directory: /loki/rules

schema_config:
  configs:
    - from: 2024-01-01
      store: boltdb-shipper
      object_store: filesystem
      schema: v12
      index:
        prefix: index_
        period: 24h

storage_config:
  boltdb_shipper:
    active_index_directory: /loki/index
    cache_location: /loki/boltdb-cache
    shared_store: filesystem
  filesystem:
    directory: /loki/chunks

ruler:
  rule_path: /loki/rules
  storage:
    type: local
    local:
      directory: /loki/rules
  ring:
    kvstore:
      store: inmemory

limits_config:
  retention_period: 168h
  max_cache_freshness_per_query: 10m

query_range:
  parallelise_shardable_queries: true
```

---

## 3) Promtail config (targets & labels)

`labs/lesson_20/compose/promtail-config.yml`

```yaml
server:
  http_listen_port: 9080
  grpc_listen_port: 0

clients:
  - url: http://loki:3100/loki/api/v1/push

positions:
  filename: /positions/positions.yaml

scrape_configs:

  - job_name: nginx
    static_configs:
      - targets: [localhost]
        labels:
          job: nginx
          __path__: /var/log/nginx/access.json
    pipeline_stages:
      - json:
          expressions:
            time: time
            remote_addr: remote_addr
            request: request
            status: status
            bytes_sent: bytes_sent
            upstream_addr: upstream_addr
            upstream_status: upstream_status
            request_time: request_time
            upstream_response_time: upstream_response_time
      - labels:
          status:
          upstream_status:
      - timestamp:
          source: time
          format: RFC3339Nano
          fallback_formats:
            - RFC3339
            - Unix
            
  - job_name: auth
    static_configs:
      - targets: [localhost]
        labels:
          job: auth
          __path__: /hostlog/auth.log
    pipeline_stages:
      - match:
          selector: '{job="auth"} |= "Failed password"'
          stages:
            - regex:
                expression: 'Failed password for(?: invalid user)? (?P<user>\S+) from (?P<ip>\S+)'
            - labels:
                user:
                ip:
```

---

## 4) Run & sanity

```bash
cd labs/lesson_20/compose
docker compose up -d
docker compose up ps
curl -s 127.0.0.1:3100/ready && echo " ← Loki ready"
docker compose logs -f promtail | sed -n '1,80p'
```

- Go to **Grafana** → Data sources → **Add data source** → **Loki** → URL: `http://loki:3100` → Save & test (should show OK).
- In **Explore**, try these queries:
    - `labels {job="nginx"}` → shows the label set.
    - `{job="nginx"} | json | line_format "{{.request}} {{.status}}"` → displays live log lines.

Generate traffic:

```bash
curl -sI http://127.0.0.1/ >/dev/null
curl -sI http://127.0.0.1/health >/dev/null
```

Update Explore.

---

## 5) Grafana alert (on logs)

Create **Grafana Alert rule** (Alerting → Alert rules → New):

- **Query A (Loki):**
    
    ```
    count_over_time({job="nginx"} | json | status=~"5.." [5m])
    ```
    
- **Condition:** `A > 20` for `5m`.
- **Contact point:** email/telegram from lesson_19.
- **Test:** Get 5xx quickly (change it temporarily `/health` on `return 500;` like in lesson_18) → change back.

---

## 6) Retention & size notes

- Now retention = **7 days** (`loki-config.yml`), change.
- Disk: volume `lokidata:`; look at the size `docker system df -v` and the volume catalog.

---

## Acceptance Criteria

- [ ]  Loki is `ready` OK; Grafana data source **Loki** is green.
- [ ]  `{job="nginx"} | json` displays lines from `/var/log/nginx/access.json`.
- [ ]  You can see `status`, `request`, and `upstream_status` as JSON keys.
- [ ]  The query `count_over_time(... status=~"5.." [5m])` returns a value > 0 when artificial 5xx responses are generated.
- [ ]  Grafana alert for 5xx triggers (Test → Fire), and the notification is received.

---

## Summary

- Deployed **Loki + Promtail + Grafana** for local JSON logs.
- Connected the Nginx JSON access log, parsed fields, and added labels.
- Executed **LogQL** queries and set up a **Grafana alert** for 5xx spikes.
- Ready to expand: add system logs, application logs, and environment labels (`env`, `service`).

## To repeat

- Add more log paths to `promtail-config.yml` (application JSON logs).
- Introduce common labels `env="lab"` and `service="web"` via `static_configs.labels`.
- Create a `dashboards/` directory to store exported dashboard JSON files.
- Later: ship logs from remote hosts (Promtail on those hosts → Loki on this one).

## Pitfalls

- Don’t turn every field into a label — keep fields inside JSON, not as labels.
- Watch log file permissions (Promtail must have read access).
- Large query ranges + too many labels = slow performance. Work with 5–15 minute.

---

## Artifacts

- `lesson_20.md`(this file)
- `labs/lesson_20/compose/{docker-compose.yml,loki-config.yml,promtail-config.yml}`