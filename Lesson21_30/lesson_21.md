# lesson_21

---

# Grafana as Code: Provisioning Datasources, Dashboards & Alerts

**Date:** 2025-11-10

**Topic:** File-based provisioning for Grafana (datasources, dashboards, alert rules), folder structure, versioning, export/import helpers, zero-downtime reload (container restart)

---

## Pocket Cheat

| Command / File | What it does | Why |
| --- | --- | --- |
| `provisioning/datasources/datasource.yml` | Declares Prometheus/Loki | No UI clicks |
| `provisioning/dashboards/*.yml` | Auto-load dashboards from folder/git | Dashboards as code |
| `dashboards/*.json` | Versioned dashboards | Reviewable diffs |
| `provisioning/alerting/alerts.yml` | File-based Grafana alerts | CI-friendly |
| `docker compose restart grafana` | Apply provisioning | Quick reload |
| `tools/grafana-export-dashboard.sh` | Export current dashboard JSON | Keep in repo |

---

## Notes

- Grafana scans `GF_PATHS_PROVISIONING=/etc/grafana/provisioning` on start/restart.
- Dashboards: YAML “providers” → point to a folder with JSON files that auto-load.
- Alerts (Unified Alerting): provision **contact points**, **notification policies**, **alert rules**.
- Everything lives in repo (`labs/lesson_21/…`) → works on any machine.

---

## What we’re doing

We’re getting rid of UI clicking: data sources, dashboards, and alerts are born from files.

On restart, Grafana reads `/etc/grafana/provisioning/**` and the folder with JSON dashboards.

We keep everything in the repo: provisioning YAML + panel JSON → clear diffs and 100% reproducibility.

---

## Security Checklist

- Grafana still bound to `127.0.0.1:3000`.
- **No secrets** inside JSON/YAML. SMTP/Telegram creds — like in lesson_19.
- Review JSON dashboards diff’s before merge.

---

## Pitfalls

- Wrong provider path → “dashboard not found on disk”.
- UID conflict: the dashboard must have a stable `"uid"` in its JSON, otherwise duplicates will be created.
- Alert provisioning uses a single YAML file: schema errors break everything (check the `grafana` logs).
- When using AM and Grafana Alerting together, don’t duplicate rules.

---

## Layout

```
labs/lesson_21/compose_loki/
├─ grafana/
│  ├─ dashboards/
│  │  ├─ nginx-mini.json
│  │  └─ node-mini.json
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
├─blackbox.yml
├─docker-compose.yml
├─grafana.ini
├─loki-config.yml
├─prometheus.yml
├─promtail-config.yml
└─ positions/
```

---

## 1) Datasources provisioning

`labs/lesson_21/compose_loki/grafana/provisioning/datasources/datasource.yml`

```yaml
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    uid: ds_prom
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    jsonData:
      httpMethod: GET

  - name: Loki
    type: loki
    uid: ds_loki
    access: proxy
    url: http://loki:3100
    jsonData:
      maxLines: 1000
```

> Use docker-compose networks: prometheus:9090, loki:3100.
> 

Checks / errors:

If the `uid` doesn’t match what’s in the JSON / alert YAML, the panels/rules will “go blind” (stop working).

Wrong `url` → the panels will show red errors / no data.

---

## 2) Dashboards provider → folder

`labs/lesson_21/compose_loki/grafana/provisioning/dashboards/dashboards.yml`

```yaml
apiVersion: 1
providers:
  - name: 'lab-dashboards'
    orgId: 1
    folder: 'Lab Dashboards'
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    allowUiUpdates: false
    options:
      path: /var/lib/grafana/dashboards
      foldersFromFilesStructure: true
```

Put the JSON dashboards themselves into `labs/lesson_21/compose_loki/grafana/dashboards/…` and mount them to `/var/lib/grafana/dashboards`.

Key points:

- The folder will be created automatically if it doesn’t exist.
- `allowUiUpdates: false` enforces “truth on disk” — the right approach for Git-driven workflows.
- `path` must match the container’s volume mount.

### `node-mini.json` (mini CPU/Mem)

```json
{
  "uid": "node-mini",
  "title": "Node Mini",
  "tags": ["lab", "node"],
  "timezone": "browser",
  "schemaVersion": 39,
  "version": 1,
  "refresh": "10s",
  "panels": [
    {
      "type": "timeseries",
      "title": "CPU by mode",
      "datasource": {"type":"prometheus","uid":"ds_prom"},
      "targets": [
        {"expr":"avg by (mode) (rate(node_cpu_seconds_total[2m]))","legendFormat":"{{mode}}"}
      ],
      "gridPos": {"h":8,"w":24,"x":0,"y":0}
    },
    {
      "type": "timeseries",
      "title": "Memory used %",
      "datasource": {"type":"prometheus","uid":"ds_prom"},
      "targets": [
        {"expr":"(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100","legendFormat":"used%"}
      ],
      "gridPos": {"h":8,"w":24,"x":0,"y":8}
    }
  ]
}
```

### `nginx-mini.json` (RPS + 5xx + logs link)

```json
{
  "uid": "nginx-mini",
  "title": "Nginx Mini",
  "tags": ["lab","nginx"],
  "schemaVersion": 39,
  "version": 1,
  "refresh": "10s",
  "panels": [
    {
      "type":"timeseries",
      "title":"Nginx requests (rate)",
      "datasource":{"type":"prometheus","uid":"ds_prom"},
      "targets":[
        {"expr":"rate(nginx_http_requests_total[2m])","legendFormat":"all"}
      ],
      "gridPos":{"h":8,"w":24,"x":0,"y":0}
    },
    {
      "type":"timeseries",
      "title":"5xx rate",
      "datasource":{"type":"prometheus","uid":"ds_prom"},
      "targets":[
        {"expr":"rate(nginx_http_requests_total{status=~\"5..\"}[2m])","legendFormat":"5xx"}
      ],
      "gridPos":{"h":8,"w":24,"x":0,"y":8}
    },
    {
      "type":"logs",
      "title":"Nginx logs (Loki)",
      "datasource":{"type":"loki","uid":"ds_loki"},
      "targets":[
        {"expr":"{job=\"nginx\"} | json"}
      ],
      "gridPos":{"h":10,"w":24,"x":0,"y":16}
    }
  ]
}
```

---

## 3) Grafana Alerts provisioning (Unified Alerting)

`labs/lesson_21/compose_loki/grafana/provisioning/alerting/alerts.yml`

```yaml
apiVersion: 1

contactPoints:
  - orgId: 1
    name: lab-default
    receivers:
      - uid: cp_email
        type: email
        settings:
          addresses: "ysu***@gmail.com"
          singleEmail: false

policies:
  - orgId: 1
    receiver: lab-default
    group_by: ["alertname","instance","service","severity"]
    routes: []

groups:
  - orgId: 1
    name: lab-rules
    folder: "Lab Alerts"
    interval: "1m"
    rules:
      - uid: rule_node_down
        title: NodeDown (Grafana)
        condition: A
        data:
          - refId: A
            relativeTimeRange: {from: 300, to: 0}
            datasourceUid: ds_prom
            model:
              editorMode: code
              expr: "up{job=\"node\"} == 0"
              instant: true
              intervalMs: 1000
              legendFormat: ""
              maxDataPoints: 43200
        annotations:
          summary: "Node exporter down"
        labels:
          severity: warning
        for: "1m"
        isPaused: false

      - uid: rule_http_probe_failed
        title: HTTP Probe Failed (Grafana)
        condition: A
        data:
          - refId: A
            relativeTimeRange: {from: 120, to: 0}
            datasourceUid: ds_prom
            model:
              editorMode: code
              expr: "probe_success{job=\"blackbox_http\"} == 0"
              instant: true
        annotations:
          summary: "HTTP probe failed"
        labels:
          severity: critical
        for: "30s"
        isPaused: false
```

> The mini contact point is email. To add more (a Telegram webhook) in the same way or via the UI.
> 

---

## 4) Mount provisioning into Grafana (compose)

Either add Grafana volume mounts to the `lesson_20` compose, or create a separate compose file for `lesson_21`.

```yaml
# in labs/lesson_20/compose/docker-compose.yml (grafana service)
    volumes:
      - grafdata:/var/lib/grafana
      - ./grafana/provisioning:/etc/grafana/provisioning:ro
      - ./grafana/dashboards:/var/lib/grafana/dashboards:ro
      - ./grafana.ini:/etc/grafana/grafana.ini:ro
```

Apply:

```bash
cd labs/lesson_21/compose_loki
docker compose restart grafana
```

Verification:

- Grafana → **Dashboards** → **Lab Dashboards** folder (the **Node Mini** and **Nginx Mini** dashboards should appear).
- Alerting → **Contact points**: `lab-default`.
- Alerting → **Alert rules**: two **rules** from the YAML file.
- Data sources: **Prometheus (uid=ds_prom)** and **Loki (uid=ds_loki)**.

---

## 5) Export helper (keep UI-created dashboards in git)

`tools/grafana-export-dashboard.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail
# Usage: ./tools/grafana-export-dashboard.sh <dashboard_uid> <outfile.json>

DASH_UID="${1:?dashboard uid}"
OUT="${2:?outfile}"
API="http://127.0.0.1:3000/api/dashboards/uid/${DASH_UID}"

CURL_AUTH=()
if [[ -n "${GRAFANA_TOKEN:-}" ]]; then
  CURL_AUTH=(-H "Authorization: Bearer $GRAFANA_TOKEN")
fi

curl -fsSL "${CURL_AUTH[@]}" "$API" | jq '.dashboard' > "$OUT"
echo "Exported to $OUT"
```

Make executable:

```bash
chmod +x tools/grafana-export-dashboard.sh
```

---

## Practice

1. Create the `labs/lesson_21/compose_loki/grafana/...` structure and add the files from steps 1–3.
2. Mount the folders into Grafana (volumes) and run `docker compose restart grafana`.
3. Open Grafana:
    - **Dashboards** → both mini dashboards are present, data is coming in.
    - **Alerting** → contact point `lab-default` and 2 rules → green.
4. Simulate a `node_exporter` failure (`lesson_18`) → check that **NodeDown (Grafana)** goes into Firing.
5. Bring the service back up — verify that it goes to **Resolved**.

---

## Acceptance Criteria

- [ ]  On restart, Grafana automatically picks up datasources/dashboards/alerts from files.
- [ ]  `Node Mini` and `Nginx Mini` show data without any manual configuration.
- [ ]  Alert rules are visible in the UI as **provisioned**, and firing/resolve works.
- [ ]  The incident (stopping `node_exporter`) triggers a notification.

---

## Summary

- Switched Grafana to a **fully declarative** setup: data sources, dashboards, and alerts are all managed from files.
- Added an export helper to save changes from the UI back into git.
- Now the workflow is “sketch → export → commit” — consistent environments on any hosts.

---

## To repeat

- Split providers into folders (prod/stage), add labels/tags to panels.
- Introduce a CI check: use `jq` to validate JSON and a linter for YAML.
- Add log-based rules (Loki) for 5xx, like in lesson_20, but **via provisioning**.

---

## Pitfalls

- Watch the `uid` in JSON — it’s the identity key.
- Don’t put secrets into YAML; config only.
- If provisioning breaks, check the logs.

---

## Artifacts

- `lesson_21.md`
- `labs/lesson_21/compose_loki/grafana/provisioning/{datasources/datasource.yml,dashboards/dashboards.yml,alerting/alerts.yml}`
- `labs/lesson_21/grafana/dashboards/{node-mini.json,nginx-mini.json}`
- `tools/grafana-export-dashboard.sh`