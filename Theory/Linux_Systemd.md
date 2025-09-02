# Linux_Systemd

---

- **`systemctl`** — пульт управления systemd-юнитами (сервисы, таймеры, сокеты, таргеты). Старт/стоп/автозапуск/статус/редактирование.
- **`journalctl`** — просмотрщик логов systemd-журнала. Фильтрует, показывает, «хвостит» и чистит логи.

---

## Базовые команды systemctl

| Команда | Что делает | Зачем |
| --- | --- | --- |
| `systemctl status nginx` | Статус сервиса | Проверка состояния |
| `systemctl start nginx` | Запуск | Вручную включить |
| `systemctl stop nginx` | Остановить | Остановить без отключения |
| `systemctl restart nginx` | Перезапуск | Применить изменения в конфиге |
| `systemctl reload nginx` | Перечитать конфиг без остановки | Где поддерживается (nginx, sshd) |
| `systemctl enable nginx` | Автозапуск при старте | Настроить автозагрузку |
| `systemctl disable nginx` | Убрать из автозагрузки | Контроль запуска |
| `systemctl is-enabled nginx` | Проверить, включён ли автозапуск | Быстрый чек |
| `systemctl daemon-reload` | Перечитать юниты после изменения | Обновить конфиги |

---

## Информация и поиск

| Команда | Что делает |
| --- | --- |
| `systemctl list-units --type=service` | Список активных сервисов |
| `systemctl list-unit-files --type=service` | Все сервисы + enabled/disabled |
| `systemctl show nginx` | Все параметры юнита |
| `systemctl cat nginx` | Показать юнит + drop-ins |
| `systemctl edit nginx` | Создать override-конфиг (safe way) |
| `systemctl list-dependencies nginx` | Дерево зависимостей |

---

## Логи (journalctl)

| Команда | Что делает |
| --- | --- |
| `journalctl -u nginx` | Логи юнита |
| `journalctl -u nginx -n 100 --no-pager` | Последние 100 строк |
| `journalctl -u nginx -f` | Follow (как tail -f) |
| `journalctl -p warning` | Все warning+ |
| `journalctl -b` | Логи с текущей загрузки |
| `journalctl --since "2025-09-01 12:00"` | Фильтр по времени |
| `journalctl --disk-usage` | Сколько места занимают логи |
| `journalctl --vacuum-time=7d` | Чистка логов старше 7 дней |

---

## Типы юнитов

- **service** — сервисы/демоны (nginx, sshd)
- **socket** — сокеты, которые запускают сервисы при обращении
- **timer** — планировщик задач (замена cron)
- **target** — группы юнитов (multi-user.target)
- **mount/automount** — точки монтирования
- **path** — запуск при изменении файлов

---

## Работа с юнитами

Пример **сервиса** `/etc/systemd/system/myapp.service`:

```bash
[Unit]
Description=My App Service
After=network.target

[Service]
ExecStart=/usr/local/bin/myapp --flag
Restart=on-failure
User=app
Group=app

[Install]
WantedBy=multi-user.target
```

### Override-конфиги

```bash
sudo systemctl edit nginx
```

→ создаст `/etc/systemd/system/nginx.service.d/override.conf`:

```bash
[Service]
Environment="ENV=production"
LimitNOFILE=65535
```

Применить если поменял:

```bash
sudo systemctl daemon-reload
sudo systemctl restart nginx
```

Практичный шаблон

```bash
[Unit]
Description=My App Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/srv/myapp
EnvironmentFile=-/etc/myapp/env
Environment="ENV=production"
ExecStart=/usr/local/bin/myapp --flag
Restart=always
RestartSec=2
User=app
Group=app
# Безопасность/ресурсы
NoNewPrivileges=yes
AmbientCapabilities=CAP_NET_BIND_SERVICE
LimitNOFILE=65535
# systemd создаст директории с нужными правами:
RuntimeDirectory=myapp
StateDirectory=myapp
CacheDirectory=myapp
LogsDirectory=myapp

[Install]
WantedBy=multi-user.target
```

---

## Таймеры (замена cron)

Пример таймера `/etc/systemd/system/backup.timer`:

```bash
[Unit]
Description=Daily backup timer

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
```

И связанный сервис `/etc/systemd/system/backup.service`:

```bash
[Unit]
Description=Run backup script

[Service]
Type=oneshot
ExecStart=/usr/bin/flock -n /run/backup/lock -- /usr/local/bin/backup.sh
#flock не даст запуститься второй копии, если предыдущая ещё идёт
```

Запуск:

```bash
sudo systemctl enable --now backup.timer
systemctl list-timers --all
```

---

## Security/Resource options в юнитах

В `[Service]` можно задать:

- `Type=oneshot`  —  запустить один раз
- `User=` и `Group=` — запуск от конкретного пользователя

- `Nice=10` — понизить или повысить приоритет

- `NoNewPrivileges=yes` — запрет повышения привилегий

- `TimeoutStartSec=1h` — не висим вечно

- `PrivateTmp=yes` — отдельный /tmp

- `ReadOnlyPaths=/etc` — монтировать каталог только для чтения

- `LimitNOFILE=65535` — лимит открытых файлов

---

## Практикум

1. **Посмотреть активные сервисы:**

```bash
systemctl list-units --type=service --state=running
```

1. **Создать тестовый сервис:**

```bash
leprecha@Ubuntu-DevOps:~$ sudo tee /etc/systemd/system/sleeper.service >/dev/null <<'UNIT'
[Unit]
Description=Sleep demo
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/bin/sleep 300

[Install]
WantedBy=multi-user.target
UNIT
```

1. **Запустить и проверить:**

```bash
leprecha@Ubuntu-DevOps:~$ sudo chmod 644 /etc/systemd/system/sleeper.service
leprecha@Ubuntu-DevOps:~$ sudo systemctl daemon-reload
leprecha@Ubuntu-DevOps:~$ sudo systemctl enable --now sleeper.service
Created symlink /etc/systemd/system/multi-user.target.wants/sleeper.service → /etc/systemd/system/sleeper.service.
leprecha@Ubuntu-DevOps:~$ systemctl status sleeper.service
● sleeper.service - Sleep demo
     Loaded: loaded (/etc/systemd/system/sleeper.service; enabled; preset: enab>
     Active: active (running) since Tue 2025-09-02 21:27:09 IST; 9s ago
   Main PID: 7191 (sleep)
      Tasks: 1 (limit: 18465)
     Memory: 220.0K (peak: 512.0K)
        CPU: 1ms
     CGroup: /system.slice/sleeper.service
             └─7191 /bin/sleep 300

Sep 02 21:27:09 Ubuntu-DevOps systemd[1]: Started sleeper.service - Sleep demo.
```

1. **Удалить за ненадобностью:**

```bash
leprecha@Ubuntu-DevOps:~$ sudo systemctl disable --now sleeper.service
Removed "/etc/systemd/system/multi-user.target.wants/sleeper.service".
leprecha@Ubuntu-DevOps:~$ systemctl cat sleeper.service
# /etc/systemd/system/sleeper.service
[Unit]
Description=Sleep demo
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/bin/sleep 300

[Install]
WantedBy=multi-user.target
leprecha@Ubuntu-DevOps:~$ sudo rm -f /etc/systemd/system/sleeper.service
leprecha@Ubuntu-DevOps:~$ sudo systemctl daemon-reload
leprecha@Ubuntu-DevOps:~$ systemctl status sleeper.service
Unit sleeper.service could not be found.
```

---

## Security Checklist

- Никогда не редактировать системные юниты в `/usr/lib/systemd/system/` → использовать `systemctl edit`.
- Ограничивай сервисы юзером (`User=`), а не запускай всё под root.
- Используй `systemctl is-enabled` для проверки автозагрузки.
- Для планирования задач лучше таймеры systemd, чем cron → логи централизованно в journal.
- Мониторить `systemctl list-timers` и чистить старые override-файлы.

---

## Быстрые блоки

```bash
#Перезапустить сервис и смотреть логи
sudo systemctl restart nginx && journalctl -u nginx -f

#Список таймеров
systemctl list-timers --all

#Найти все юниты с ошибками
systemctl --failed

#Показать дерево зависимостей multi-user.target
systemctl list-dependencies multi-user.target
```