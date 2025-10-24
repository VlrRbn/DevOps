# node_exporter на systemd & docker/compose

---

# Хостовый (systemd) — «видет хост даже если Docker умер»

## Шаги установки

**Таблица-шейт**

| Команда | Что делает | Почему/пример |
| --- | --- | --- |
| `sudo useradd --no-create-home --system --shell /usr/sbin/nologin nodeexp` | Сервисный юзер | Без логина, минимум прав |
| `sudo mkdir -p /opt/node_exporter` | Каталог под бинарь | Чистая раскладка |
| `ver="1.8.1"; curl -fsSL -o /tmp/ne.tgz "https://github.com/prometheus/node_exporter/releases/download/v${ver}/node_exporter-${ver}.linux-amd64.tar.gz"` | Скачиваем релиз | Пин версия |
| `sudo tar -xzf /tmp/ne.tgz -C /opt/node_exporter --strip-components=1` | Распаковка | Бинарь и LICENSE |
| `sudo chown -R nodeexp:nodeexp /opt/node_exporter` | Права | Запуск под nodeexp |
| `sudo rm -f /tmp/ne.tgz` | Уборка | Гигиена |

**Флаги в env-файле** `/etc/default/node_exporter`:

```bash
sudo tee /etc/default/node_exporter >/dev/null <<'ENV'
NODE_EXPORTER_OPTS='
  --collector.systemd
  --collector.tcpstat
  --web.listen-address=127.0.0.1:9100
'
ENV
```

**Юнит** `/etc/systemd/system/node_exporter.service`:

```
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

```

**Старт и автозагрузка**

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now node_exporter
systemctl --no-pager --full status node_exporter | sed -n '1,40p'
```

**Проверка**

```bash
curl -s 127.0.0.1:9100/metrics | head
sudo ss -ltnp | grep ':9100'
```

## Интеграция в Prometheus

`prometheus.yml`:

```yaml
scrape_configs:
  - job_name: 'node'
    static_configs:
      - targets: ['127.0.0.1:9100']
        labels: { instance: 'local' }
```

Reload:

```bash
curl -X POST http://127.0.0.1:9090/-/reload
```

## Алерт

```yaml
- alert: NodeExporterDown
  expr: absent(up{job="node"}) OR up{job="node"} == 0
  for: 1m
  labels: { severity: critical }
  annotations:
    summary: "node_exporter DOWN on {{ $labels.instance }}"
```

## Подводные камни

- Порт **9100** может занять кто-то ещё → смотреть `ss -ltnp`, `lsof -iTCP:9100`.
- Не запускать контейнерный экспортер на том же порту — будет гонка.

## Удаление/выключение

```bash
sudo systemctl disable --now node_exporter
sudo systemctl mask node_exporter
sudo rm -f /etc/systemd/system/node_exporter.service /etc/default/node_exporter
sudo systemctl daemon-reload
sudo rm -rf /opt/node_exporter
```

---

# Контейнерный (Docker/Compose) — «удобно, всё в одном стеке»

## docker-compose.yml (фрагмент)

```yaml
services:
  node_exporter:
    image: quay.io/prometheus/node-exporter:latest
    container_name: lab17-node-exporter
    network_mode: host        # чтобы слушать 127.0.0.1:9100
    pid: host                 # видеть хостовые /proc
    command:
      - --path.rootfs=/host   # корректный префикс к rootfs
      # - --collector.systemd # обычно требует доп. маунтов dbus; чаще выключаем в контейнере
      # - --collector.tcpstat # можно включить, если устраивают привилегии
    volumes:
      - /:/host:ro,rslave
    restart: unless-stopped
```

**Старт/проверка**

```bash
docker compose up -d node_exporter
sudo ss -ltnp | grep ':9100'
curl -s 127.0.0.1:9100/metrics | head
```

**Prometheus тот же блок `job_name: 'node'`**, reload такой же.

## Подводные камни

- Если Docker «лежит» — **контейнерный** экспортер не даст метрики (поэтому в проде ставят **хостовый**).
- Для `--collector.systemd` в контейнере нужны дополнительные маунты (dbus), проще выключить или оставить хостовый вариант.

---

# Диагностика

| Что проверить | Команда |
| --- | --- |
| Кто слушает 9100 | `sudo ss -ltnp | grep ':9100'` |
| Откуда метрики | `curl -s 127.0.0.1:9100/metrics | head` |
| Есть ли два экспорта | `pgrep -fa 'node[-_]?exporter'` и `docker ps | grep node-exporter` |
| Серия в Prometheus | `curl -sG 'http://127.0.0.1:9090/api/v1/query' --data-urlencode 'query=up{job="node"}'` |

---

# Security Checklist

- Хостовый: `--web.listen-address=127.0.0.1:9100`, юзер `nodeexp`, hardening в unit.
- Контейнерный: `network_mode: host` только если нужно слушать `127.0.0.1`. Иначе пробрасывать порт как `"9100:9100"` и слушать `0.0.0.0:9100` **только за reverse-proxy/VPN**.
- Никогда не светить `/metrics` наружу без ACL/фаервола.

---

# Что выбрать и когда

- **Лабы/демо/всё в одном compose** → контейнерный. Быстро, удобно.
- **Прод/надо видеть хост при падении Docker** → хостовый systemd.
- Хочешь и то, и то: держать **разные порты и job-имена**:
    - host: `127.0.0.1:9100`, `job: node_host`
    - container: `127.0.0.1:9101`, `job: node_docker`

Пример двух джобов:

```yaml
scrape_configs:
  - job_name: 'node_host'
    static_configs: [ { targets: ['127.0.0.1:9100'], labels: { instance: 'local' } } ]
  - job_name: 'node_docker'
    static_configs: [ { targets: ['127.0.0.1:9101'], labels: { instance: 'local' } } ]
```

И два алерта аналогично.