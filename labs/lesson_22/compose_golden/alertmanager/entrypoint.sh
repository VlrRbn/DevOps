#!/bin/sh
set -e

cat >/etc/alertmanager/alertmanager.yml <<EOF
global:
  resolve_timeout: 5m

route:
  receiver: "telegram"
  group_by: ['alertname']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 3h

receivers:
  - name: "telegram"
    telegram_configs:
      - bot_token: "${TELEGRAM_TOKEN}"
        chat_id: ${TELEGRAM_CHAT_ID}
        parse_mode: "Markdown"
        send_resolved: true
        message: |-
          [{{ .Status | toUpper }}] {{ .CommonLabels.alertname }}
          {{ range .Alerts -}}
          *Instance:* \`{{ .Labels.instance }}\`
          *Summary:* {{ .Annotations.summary }}
          {{ end }}

templates:
  - "/etc/alertmanager/templates/*.tmpl"
EOF

exec /bin/alertmanager \
  --config.file=/etc/alertmanager/alertmanager.yml \
  --log.level=info \
  --web.listen-address=0.0.0.0:9093
