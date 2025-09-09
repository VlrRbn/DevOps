# systemd

---

- **`systemctl`** — пульт управления systemd-юнитами (сервисы, таймеры, сокеты, таргеты). Старт/стоп/автозапуск/статус/редактирование.
- **`journalctl`** — просмотрщик логов systemd-журнала. Фильтрует, показывает, «хвостит» и чистит логи.

---

### Базовые команды (`systemctl`)

| Command | Что делает | Зачем/Пример |
| --- | --- | --- |
| `systemctl status <unit>` | Показать состояние юнита и хвост лога | Быстрая диагностика: `systemctl status ssh` |
| `systemctl start/stop/restart <unit>` | Запуск/останов/перезапуск | Управление сервисом: `systemctl restart nginx` |
| `systemctl enable/disable <unit> [--now]` | Включить/выключить автозапуск (и сразу старт) | Сделать постоянным: `systemctl enable --now cron` |
| `systemctl is-enabled  <unit>` | Проверить, включён ли автозапуск | Быстрый чек |
| `systemctl is-active/is-failed <unit>` | Проверить активность/аварию | Условные проверки в скриптах CI/healthcheck |
| `systemctl reset-failed [<unit>]` | Сбросить состояние «failed» | После фикса ошибок убрать «красное» в списках |
| `systemctl daemon-reload` | Перечитать юнит-файлы | После изменений drop-in/юнита |
| `systemctl reload [<unit>]`  | Перечитать конфиг без остановки | Где поддерживается (nginx, sshd) |

### Информация и поиск

| Command | Что делает | Зачем/Пример |
| --- | --- | --- |
| `systemctl list-units --type=service` | Активные сервисы | Срез по типам: `--type=timer`, `--type=socket` |
| `systemctl list-unit-files` | Все юниты и их «enabled/disabled» | Быстрая ревизия автозапуска |
| `systemctl show <unit>` | Все свойства юнита | Скриптовая инспекция/отладка |
| `systemctl show -p FragmentPath -p DropInPaths <unit>` | Где лежит основной файл и drop-in | Находит правду при конфликте |
| `systemctl cat <unit>` | Показать финальный конфиг с drop-ins | Убедиться, что override применился |
| `systemctl list-dependencies <unit>` | Дерево зависимостей |  |

### Логи (`journalctl`)

| Command | Что делает | Зачем/Пример |
| --- | --- | --- |
| `journalctl -u <unit>` | Логи юнита, по умолчанию за всё время | История: `journalctl -u nginx` |
| `journalctl -xeu <unit>` | Последние ошибки с деталями | «Почему упал прямо сейчас?» |
| `journalctl -b -1` | Логи прошлой загрузки | Дебаг проблем на старте |
| `journalctl --since "-1h" -p warning` | Фильтр по окну и приоритету | Быстро найти важное за час |
| `journalctl --disk-usage` | Занимаемый объём журналом | Контроль ретеншна |
| `journalctl --vacuum-time=7d` | Очистить старше 7 дней |  |

**Постоянный журнал:** `/etc/systemd/journald.conf` → `Storage=persistent`, лимиты `SystemMaxUse`, `RuntimeMaxUse`.

### Типы юнитов — когда что использовать

| Тип | Когда выбирать | Пример |
| --- | --- | --- |
| `service` | Долгоживущие процессы/одноразовые задачи | `nginx.service`, backup-скрипт (`Type=oneshot`) |
| `timer` | Планирование вместо `cron` | Горизонтальные обновления/бэкапы |
| `socket` | Автозапуск по сокету | Экономия ресурсов для редких демонов |
| `path` | Триггер по файлу/директории | Конвертер при появлении файла |
| `mount/automount` | Точки монтирования | Автомаунт NFS |
| `target` | Логические группы/этапы | `multi-user.target`, `network-online.target` |
| `slice/scope` | Cgroups/внешние процессы | Ограничение ресурсов служб |

### Работа с юнит-файлами

| Command | Что делает | Зачем/Пример |
| --- | --- | --- |
| `systemctl edit <unit>` | Создать/править drop-in | Без правки оригинала из `/usr/lib` |
| `systemctl edit --full <unit>` | Полная копия юнита в `/etc/systemd/system` | Клонировать для серьёзных правок |
| `systemctl revert <unit>` | Убрать overrides | Вернуться к системному дефолту |

**Приоритет путей:** `/etc/systemd` (админ) → `/run/systemd` (временное) → `/usr/lib/systemd` (пакет). *Оригиналы не редактируем, используем drop-in в `/etc`.*

### Сетевые зависимости

| Command | Что делает | Зачем/Пример |
| --- | --- | --- |
| `Wants=network-online.target` + `After=network-online.target` | Ждать реальной сети | Для сервисов, требующих доступности сети |
| `systemctl enable systemd-networkd-wait-online.service` | Включить ожидание сети (networkd) | Или `NetworkManager-wait-online.service` при NM |

### Таймеры (замена cron) — анти-дубли и точность

| Command/Опция | Что делает | Зачем/Пример |
| --- | --- | --- |
| `OnCalendar=` | Расписание как `cron`, но читабельнее | `OnCalendar=daily`, `Mon..Fri 03:15` |
| `OnBootSec=`/`OnUnitActiveSec=` | От старта/от прошлого запуска | Бэкап каждые 6ч: `OnUnitActiveSec=6h` |
| `RandomizedDelaySec=` | Размазывает старт | Снизить пики на кластере |
| `AccuracySec=` | Грубость времени | Меньше будить систему |
| `flock`/`RuntimeDirectory=` | Взаимоисключение/каталог | Не запускать второй инстанс |

---

### Пример сервиса (с хардненингом и каталогами)

```bash
# /etc/systemd/system/myapp.service
[Unit]
Description=My App
Documentation=man:systemd.service(5)
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=myapp
Group=myapp
# Каталоги под данные/кэш/логи/рантайм создадутся и будут принадлежать User/Group
RuntimeDirectory=myapp
StateDirectory=myapp
CacheDirectory=myapp
LogsDirectory=myapp
# Безопасность
NoNewPrivileges=yes
PrivateTmp=yes
PrivateDevices=yes
ProtectSystem=strict
ProtectHome=read-only
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
RestrictSUIDSGID=yes
RestrictAddressFamilies=AF_INET AF_INET6
SystemCallFilter=@system-service
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=
LockPersonality=yes
UMask=027
# Ресурсы
MemoryMax=300M
CPUQuota=50%
# Поведение
ExecStart=/usr/local/bin/myapp --config /etc/myapp/config.yaml
ExecStartPre=/usr/bin/test -r /etc/myapp/config.yaml
Restart=on-failure
RestartSec=5s
StartLimitIntervalSec=60
StartLimitBurst=5
TimeoutStartSec=30s
TimeoutStopSec=30s
KillMode=control-group

[Install]
WantedBy=multi-user.target
```

### Пара таймер+сервис

```bash
# /etc/systemd/system/backup.service
[Unit]
Description=Nightly backup (service)

[Service]
Type=oneshot
User=root
Group=root
RuntimeDirectory=backup
ExecStart=/usr/bin/flock -n /run/backup/lock -- /usr/local/sbin/backup.sh
```

```bash
# /etc/systemd/system/backup.timer
[Unit]
Description=Nightly backup (timer)

[Timer]
OnCalendar=03:00
RandomizedDelaySec=20m
AccuracySec=1m
Unit=backup.service

[Install]
WantedBy=timers.target
```

---

## Подводные камни

- **Не править** файлы в `/usr/lib/systemd/...` — только drop-in в `/etc/systemd/system/<unit>.d/*.conf` или полная копия через `edit --full`.
- `Restart=` vs `Type=oneshot`: одноразовые задачи не должны «зацикливаться» рестартом.
- Шторм рестартов: лимитировать `StartLimitIntervalSec/StartLimitBurst`.
- Сеть «есть», но недоступна: подключить *wait-online* службу для своего стека (networkd/NM).
- Перекрытия таймеров: использовать `flock` и/или `RefuseManualStart/Stop` при необходимости.
- Журнал пропадает после ребута: включить `Storage=persistent` и лимиты в `journald.conf`.
- `ExecStartPre=/bin/false` помечает сервис failed — удобно для теста, но не забыть `reset-failed`.
- `KillMode=` влияет на остановку дочерних процессов; по умолчанию `control-group` безопаснее.

---

## Практикум

1. **Сервис-эхо**: создать `/usr/local/bin/hello.sh` с `#!/usr/bin/env bash; echo "$(date) hello" >> /var/log/hello.log` и сделать `chmod +x`.

```bash
leprecha@Ubuntu-DevOps:~$ sudo tee /usr/local/bin/hello.sh > /dev/null <<'EOF'
#!/usr/bin/env bash
echo "$(date) hello" >> /var/log/hello.log
EOF
leprecha@Ubuntu-DevOps:~$ sudo chmod +x /usr/local/bin/hello.sh
leprecha@Ubuntu-DevOps:~$ sudo /usr/local/bin/hello.sh && tail -n 5 /var/log/hello.log
Tue Sep  9 12:52:32 PM IST 2025 hello
```

1. **Юнит:** скопировать шаблон `myapp.service`, адаптировать под `hello` (минимум: `User=root`, `LogsDirectory=hello`, `ExecStart=/usr/local/bin/hello.sh`).

```bash
leprecha@Ubuntu-DevOps:~$ sudo tee /etc/systemd/system/hello.service > /dev/null <<'EOF'
# /etc/systemd/system/hello.service
[Unit]
Description=Hello echo service
Documentation=man:systemd.service(5)
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=root
Group=root

# Каталоги под данные/кэш/логи/рантайм (создаются systemd)
RuntimeDirectory=hello
StateDirectory=hello
CacheDirectory=hello
LogsDirectory=hello

# Безопасность
NoNewPrivileges=yes
PrivateTmp=yes
PrivateDevices=yes
ProtectSystem=strict
ProtectHome=read-only
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
RestrictSUIDSGID=yes
RestrictAddressFamilies=AF_INET AF_INET6
SystemCallFilter=@system-service
CapabilityBoundingSet=
AmbientCapabilities=
LockPersonality=yes
UMask=027
# Разрешить запись ровно в файл лога, т.к. скрипт пишет в /var/log/hello.log
ReadWritePaths=/var/log/hello.log

# Ресурсы
MemoryMax=300M
CPUQuota=50%

# Поведение
ExecStart=/usr/local/bin/hello.sh
Restart=on-failure
RestartSec=5s
StartLimitIntervalSec=60
StartLimitBurst=5
TimeoutStartSec=30s
TimeoutStopSec=30s
KillMode=control-group

[Install]
WantedBy=multi-user.target
EOF

leprecha@Ubuntu-DevOps:~$ sudo systemctl daemon-reload
leprecha@Ubuntu-DevOps:~$ sudo systemctl enable --now hello.service
Created symlink /etc/systemd/system/multi-user.target.wants/hello.service → /etc/systemd/system/hello.service.
leprecha@Ubuntu-DevOps:~$ systemctl status hello.service --no-pager -l && tail -n 5 /var/log/hello.log
○ hello.service - Hello echo service
     Loaded: loaded (/etc/systemd/system/hello.service; enabled; preset: enabled)
     Active: inactive (dead) since Tue 2025-09-09 19:51:30 IST; 20s ago
   Duration: 29ms
       Docs: man:systemd.service(5)
    Process: 7875 ExecStart=/usr/local/bin/hello.sh (code=exited, status=0/SUCCESS)
   Main PID: 7875 (code=exited, status=0/SUCCESS)
        CPU: 27ms

Sep 09 19:51:30 Ubuntu-DevOps systemd[1]: Started hello.service - Hello echo service.
Sep 09 19:51:30 Ubuntu-DevOps systemd[1]: hello.service: Deactivated successfully.
Tue Sep  9 12:53:48 PM IST 2025 hello
Tue Sep  9 07:51:30 PM IST 2025 hello
```

1. `systemctl daemon-reload && systemctl enable --now hello.service && systemctl status hello`.

```bash
leprecha@Ubuntu-DevOps:~$ systemctl daemon-reload && systemctl enable --now hello.service && systemctl status hello
● hello.service - Hello echo service
     Loaded: loaded (/etc/systemd/system/hello.service; enabled; preset: enabled)
     Active: active (running) since Tue 2025-09-09 19:54:51 IST; 11ms ago     # поймал момент «пока бежит»
       Docs: man:systemd.service(5)
   Main PID: 8247 ((hello.sh))
      Tasks: 1 (limit: 18465)
     Memory: 388.0K (max: 300.0M available: 299.6M peak: 392.0K)
        CPU: 8ms
     CGroup: /system.slice/hello.service
             └─8247 "(hello.sh)"

Sep 09 19:54:51 Ubuntu-DevOps systemd[1]: Started hello.service - Hello echo service.
```

1. **Сломать намеренно:** добавить `ExecStartPre=/bin/false`, перезапустить и посмотреть `journalctl -xeu hello` → `systemctl reset-failed hello`.

```bash
leprecha@Ubuntu-DevOps:~$ sudo mkdir -p /etc/systemd/system/hello.service.d
leprecha@Ubuntu-DevOps:~$ sudo tee /etc/systemd/system/hello.service.d/99-break.conf > /dev/null <<'EOF'
[Service]
ExecStartPre=
ExecStartPre=/bin/false
EOF
leprecha@Ubuntu-DevOps:~$ sudo systemctl daemon-reload
leprecha@Ubuntu-DevOps:~$ sudo systemctl restart hello || true
Job for hello.service failed because the control process exited with error code.
See "systemctl status hello.service" and "journalctl -xeu hello.service" for details.
leprecha@Ubuntu-DevOps:~$ systemctl status hello --no-pager -l
● hello.service - Hello echo service
     Loaded: loaded (/etc/systemd/system/hello.service; enabled; preset: enabled)
    Drop-In: /etc/systemd/system/hello.service.d
             └─99-break.conf
     Active: activating (auto-restart) (Result: exit-code) since Tue 2025-09-09 19:59:28 IST; 4s ago
       Docs: man:systemd.service(5)
    Process: 8468 ExecStartPre=/bin/false (code=exited, status=1/FAILURE)
        CPU: 32ms
```

1. **Таймер:** создать `hello.timer` с `OnUnitActiveSec=1min`, включить `-now`, проверить в `systemctl list-timers` и хвост лога.

```bash
leprecha@Ubuntu-DevOps:~$ sudo tee /etc/systemd/system/hello.timer > /dev/null <<'EOF'
[Unit]
Description=Run hello.service every minute

[Timer]
OnBootSec=30s
OnUnitActiveSec=1min
Unit=hello.service
Persistent=true

[Install]
WantedBy=timers.target
EOF
leprecha@Ubuntu-DevOps:~$ sudo systemctl daemon-reload
leprecha@Ubuntu-DevOps:~$ sudo systemctl enable --now hello.timer
Created symlink /etc/systemd/system/timers.target.wants/hello.timer → /etc/systemd/system/hello.timer.
leprecha@Ubuntu-DevOps:~$ systemctl status hello.timer --no-pager
● hello.timer - Run hello.service every minute
     Loaded: loaded (/etc/systemd/system/hello.timer; enabled; preset: enabled)
     Active: active (waiting) since Tue 2025-09-09 20:06:38 IST; 9s ago
    Trigger: Tue 2025-09-09 20:07:38 IST; 50s left
   Triggers: ● hello.service

Sep 09 20:06:38 Ubuntu-DevOps systemd[1]: Started hello.timer - Run hello.service every minute.
leprecha@Ubuntu-DevOps:~$ systemctl list-timers --all | grep hello
Tue 2025-09-09 20:07:38 IST      42s Tue 2025-09-09 20:06:38 IST      17s ago hello.timer                    hello.service
leprecha@Ubuntu-DevOps:~$ LOG=/var/log/hello/hello.log; [ -f "$LOG" ] || LOG=/var/log/hello.log
echo "Лог: $LOG"
tail -n 5 "$LOG"
Лог: /var/log/hello.log
Tue Sep  9 12:57:10 PM IST 2025 hello
Tue Sep  9 07:51:30 PM IST 2025 hello
Tue Sep  9 07:54:51 PM IST 2025 hello
Tue Sep  9 08:02:15 PM IST 2025 hello
Tue Sep  9 08:06:38 PM IST 2025 hello
leprecha@Ubuntu-DevOps:~$ watch -n 5 "tail -n 3 $LOG"
```

---

## Security Checklist (службы)

- `NoNewPrivileges=yes`, `ProtectSystem=strict`, `ProtectHome=read-only`
- `PrivateTmp=yes`, `PrivateDevices=yes`, `ProtectKernel*`, `ProtectControlGroups=yes`
- `CapabilityBoundingSet=...` (минимум), `AmbientCapabilities=` (пусто если не нужен ambient)
- `SystemCallFilter=@system-service` (+ `@network-io`/микросписки при необходимости)
- `UMask=027`, ограничение прав на созданные файлы
- Ограничения ресурсов: `MemoryMax`, `CPUQuota`, `TasksMax`
- Пользователь/группа: выделенный `User=`/`Group=`, каталоги через `Directory=`

---

## Быстрые блоки

```bash
# Где реально лежит юнит и его drop-ins
systemctl show -p FragmentPath -p DropInPaths nginx

# Свежие ошибки юнита
journalctl -xeu nginx | tail -50

# Разбор проблем при загрузке
systemd-analyze blame | head -20
systemd-analyze critical-chain

# Работа с таймерами
systemctl list-timers --all

# Постоянный журнал и вакуум
sudo sed -i 's/^#\?Storage=.*/Storage=persistent/' /etc/systemd/journald.conf
sudo systemctl restart systemd-journald
journalctl --vacuum-time=7d
```