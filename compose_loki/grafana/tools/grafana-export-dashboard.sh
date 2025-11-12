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