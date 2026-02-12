# lesson_05

# Процессы, Systemd Сервисы, Таймеры и Journalctl

**Date:** 2025-08-25  
**Topic:** Диагностика процессов, сигналы, жизненный цикл systemd-unit, таймеры и логирование через journald  
**Daily goal:** Научиться проверять процессы, управлять systemd-сервисами и таймерами, а также разбирать поведение системы через логи.
**Bridge:** [05-07 Operations Bridge](../00-foundations-bridge/05-07-operations-bridge.ru.md) — компенсация недостающих практических тем после уроков 5-7.

---

## 1. Базовые Концепции

### 1.1 База по процессам

Процесс - это запущенный экземпляр программы с:

- PID (ID процесса)
- PPID (ID родительского процесса)
- состоянием (`R`, `S`, `D`, `Z` и т.д.)
- потреблением CPU/памяти

### 1.2 Сигналы

Сигналы - это асинхронные управляющие сообщения процессу.

- `SIGTERM` (15): аккуратная просьба завершиться
- `SIGKILL` (9): принудительное завершение (перехватить/игнорировать нельзя)

Правило: сначала всегда пробуем `SIGTERM`.

### 1.3 systemd units

`systemd` управляет unit-объектами (`.service`, `.timer`, `.socket` и др.).

Типовые состояния сервиса:

- `active (running)`
- `inactive (dead)`
- `failed`
- `activating` / `deactivating`

#### Где лежат unit-файлы и скрипты

- `/usr/local/bin` - исполняемые скрипты/бинарники (что именно запускать).
- `/etc/systemd/system` - unit-файлы и override-конфиги администратора (как и когда запускать).

В этом уроке связка такая:

- скрипт: `/usr/local/bin/hello.sh`
- unit: `/etc/systemd/system/hello.service`
- timer: `/etc/systemd/system/hello.timer`

После изменения unit-файлов нужен `systemctl daemon-reload`, чтобы systemd перечитал конфигурацию.

### 1.4 journald

`journald` хранит структурированные логи systemd-unit и системных событий.

Самые полезные фильтры:

- `-u <unit>` фильтр по unit
- `-p <priority>` фильтр по уровню
- `-b` фильтр по boot
- `-f` follow-режим
- `-t` фильтр по identifier/tag

---

## 2. Приоритет Команд (Что Учить Сначала)

### Core (обязательно сейчас)

- `ps aux --sort=-%cpu`, `ps aux --sort=-%mem`
- `ps -p <pid> -o ...`
- `pstree -p`
- `kill -SIGTERM <pid>`, затем `kill -SIGKILL <pid>` при необходимости
- `systemctl status <unit>`
- `systemctl cat <unit>`
- `systemctl show -p ... <unit>`
- `journalctl -u <unit> -n 20 --no-pager`
- `journalctl -fu <unit>`

### Optional (полезно после core)

- `hostnamectl`
- `systemctl list-units --type=service --state=running`
- `systemctl is-system-running`
- `systemctl list-timers --all`
- `systemctl --failed`
- `systemd-analyze time|blame|critical-chain`

### Advanced (более глубокие операции)

- drop-in override в `/etc/systemd/system/<unit>.service.d/`
- свой `oneshot` service + timer
- политика рестартов (`Restart=on-failure`)
- базовые/расширенные hardening-директивы
- transient unit через `systemd-run`
- persistent-хранение journald

---

## 3. Core Команды: Что / Зачем / Когда

### `ps aux --sort=-%cpu` и `ps aux --sort=-%mem`

- **Что:** список процессов, отсортированный по CPU или памяти.
- **Зачем:** быстро найти прожорливые процессы.
- **Когда:** система тормозит, есть подозрение на CPU/RAM bottleneck.

```bash
ps aux --sort=-%cpu | head
ps aux --sort=-%mem | head
```

### `pstree -p`

- **Что:** дерево процессов с родителями, дочерними процессами и PID.
- **Зачем:** видеть, кто кого запустил.
- **Когда:** разбираем цепочку процессов сервиса или зависшие воркеры.

```bash
pstree -p | head -n 20
```

### `ps -p <pid> -o ...`

- **Что:** точечная информация по одному PID.
- **Зачем:** точная диагностика без шума полного списка.
- **Когда:** после того как нашли интересный процесс.

```bash
S=$(sleep 300 & echo $!)
ps -p "$S" -o pid,ppid,stat,etime,cmd
```

### `kill -SIGTERM`, затем `kill -SIGKILL`

- **Что:** мягкая остановка процесса, затем жесткая при необходимости.
- **Зачем:** снижает риск повреждения данных по сравнению с немедленным `-9`.
- **Когда:** надо остановить зависший процесс или проверить поведение на сигналы.

```bash
kill -SIGTERM "$S"
sleep 1
ps -p "$S" -o pid,stat || echo "terminated"

# только если процесс все еще жив
kill -SIGKILL "$S"
```

### `systemctl status <unit>`

- **Что:** текущее состояние, PID, последние логи, статус загрузки unit.
- **Зачем:** первая точка входа в диагностику сервиса.
- **Когда:** сервис не стартует, падает или ведет себя странно.

```bash
systemctl status cron
```

### `systemctl cat <unit>`

- **Что:** итоговая конфигурация unit + drop-in файлы.
- **Зачем:** понять, что именно читает systemd.
- **Когда:** поведение сервиса не совпадает с ожиданием.

```bash
systemctl cat cron
```

### `systemctl show -p ... <unit>`

- **Что:** выбранные machine-readable свойства unit.
- **Зачем:** быстро и удобно для скриптов.
- **Когда:** нужно вытащить PID, политику рестартов, путь unit, состояние.

```bash
systemctl show -p FragmentPath,UnitFileState,ActiveState,SubState,MainPID,ExecStart,Restart,RestartUSec cron
```

### `journalctl -u ...` и `journalctl -fu ...`

- **Что:** история логов и поток логов в реальном времени по unit.
- **Зачем:** основной источник причины ошибок и последовательности событий.
- **Когда:** сервис падает, перезапускается, зависает или работает не так.

```bash
journalctl -u cron --since "15 min ago" --no-pager
journalctl -fu cron
```

---

## 4. Optional Команды (После Core)

### `hostnamectl`

- **Что:** информация об имени хоста и метаданных системы.
- **Зачем:** удобно фиксировать окружение в диагностике.
- **Когда:** перед началом troubleshooting.

```bash
hostnamectl
```

### `systemctl list-units --type=service --state=running`

- **Что:** список активных сервисов.
- **Зачем:** быстрый обзор работающих unit.
- **Когда:** проверка базового состояния после загрузки/изменений.

```bash
systemctl list-units --type=service --state=running | head -n 5
```

### `systemctl is-system-running`

- **Что:** общее состояние systemd (`running`, `degraded` и др.).
- **Зачем:** короткий health-сигнал системы.
- **Когда:** быстрая проверка после boot.

```bash
systemctl is-system-running
```

### `systemctl list-timers --all`

- **Что:** расписание таймеров + время последнего/следующего запуска.
- **Зачем:** проверить планировщик заданий через systemd timers.
- **Когда:** таймер не сработал или сработал не тогда.

```bash
systemctl list-timers --all | head -n 10
```

### `systemctl --failed`

- **Что:** список unit в состоянии `failed`.
- **Зачем:** быстрый triage после инцидента.
- **Когда:** система `degraded` или есть жалобы на сервисы.

```bash
systemctl --failed
```

### `systemd-analyze time|blame|critical-chain`

- **Что:** метрики времени загрузки и dependency-цепочка.
- **Зачем:** искать узкие места boot-процесса.
- **Когда:** медленная загрузка или долгий старт сервисов.

```bash
systemd-analyze time
systemd-analyze blame | head -n 15
systemd-analyze critical-chain
```

---

## 5. Advanced Темы (Сервисы, Таймеры, Hardening)

### 5.1 Безопасная кастомизация unit через drop-in override

Не редактируй unit из пакета напрямую. Используй drop-in:

```bash
sudo mkdir -p /etc/systemd/system/cron.service.d
printf "[Service]\nEnvironment=HELLO=world\n" | sudo tee /etc/systemd/system/cron.service.d/override.conf >/dev/null
sudo systemctl daemon-reload
sudo systemctl restart cron
systemctl cat cron
```

Почему так лучше:

- обновления пакетов не затрут твой файл
- изменения изолированы и легко откатываются

### 5.2 Создаем свой service + timer (hello logger каждые 5 минут)

#### Скрипт

```bash
sudo tee /usr/local/bin/hello.sh >/dev/null <<'SH'
#!/usr/bin/env bash
echo "[hello] $(date '+%F %T') $(hostname)" | systemd-cat -t hello -p info
SH
sudo chmod +x /usr/local/bin/hello.sh
```

#### Service unit (`oneshot`)

```bash
sudo tee /etc/systemd/system/hello.service >/dev/null <<'UNIT'
[Unit]
Description=Hello logger (oneshot)

[Service]
Type=oneshot
ExecStart=/usr/local/bin/hello.sh
UNIT
```

#### Timer unit

```bash
sudo tee /etc/systemd/system/hello.timer >/dev/null <<'UNIT'
[Unit]
Description=Run hello.service every 5 minutes

[Timer]
OnBootSec=1min
OnUnitActiveSec=5min
Unit=hello.service

[Install]
WantedBy=timers.target
UNIT
```

#### Включаем и проверяем

```bash
sudo systemctl daemon-reload
sudo systemctl start hello.service
sudo systemctl enable --now hello.timer
systemctl list-timers --all | grep hello || systemctl list-timers --all | head -n 5
journalctl -u hello.service --since "10 min ago" -n 20 --no-pager
journalctl -t hello -n 20 --no-pager
```

### 5.3 Демонстрация авто-восстановления (`Restart=on-failure`)

```bash
sudo tee /etc/systemd/system/flaky.service >/dev/null <<'UNIT'
[Unit]
Description=Flaky demo (restarts on failure)

[Service]
Type=simple
ExecStart=/bin/bash -lc 'echo start; sleep 2; echo crash >&2; exit 1'
Restart=on-failure
RestartSec=3s
UNIT

sudo systemctl daemon-reload
sudo systemctl start flaky
sleep 7
systemctl show -p NRestarts,ExecMainStatus flaky
journalctl -u flaky -n 20 --no-pager
```

### 5.4 Быстрый hardening-набор для `hello.service`

```ini
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
NoNewPrivileges=yes
```

Смысл:

- более строгие ограничения на файловую систему
- запрет доступа к домашним директориям
- изолированный `/tmp`
- запрет на повышение привилегий через exec

Расширенные примеры hardening (использовать с проверкой):

```ini
SystemCallFilter=@system-service @basic-io @file-system @network-io
SystemCallArchitectures=native
CapabilityBoundingSet=
AmbientCapabilities=
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
RestrictNamespaces=yes
LockPersonality=yes
ProtectClock=yes
ProtectProc=invisible
ProcSubset=pid
```

### 5.5 Transient unit (без файла на диске)

```bash
sudo systemd-run --unit=now-echo --property=MemoryMax=50M \
  /bin/bash -lc 'echo transient $(date) | systemd-cat -t now-echo'

journalctl -u now-echo -n 10 --no-pager
journalctl -t now-echo -n 10 --no-pager
```

### 5.6 Persistent хранение journald

```bash
sudo mkdir -p /var/log/journal
sudo mkdir -p /etc/systemd/journald.conf.d
sudo tee /etc/systemd/journald.conf.d/persistent.conf >/dev/null <<'CFG'
[Journal]
Storage=persistent
SystemMaxUse=200M
RuntimeMaxUse=50M
SystemMaxFileSize=50M
MaxFileSec=1month
Compress=yes
Seal=yes
CFG

sudo systemctl restart systemd-journald
journalctl --disk-usage
```

---

## 6. Мини-Лаба (Core Path)

### Цель

Пройти базовую диагностику процессов/сервисов/логов минимальным набором команд.

### Шаги

1. Найти процессы с высоким CPU и памятью.
2. Запустить тестовый процесс и проверить его по PID.
3. Завершить процесс корректно.
4. Проверить состояние и логи `cron`.

```bash
ps aux --sort=-%cpu | head
ps aux --sort=-%mem | head

sleep 300 &
S=$!
ps -p "$S" -o pid,ppid,stat,etime,cmd
kill -SIGTERM "$S"
sleep 1
ps -p "$S" -o pid,stat || echo "terminated"

systemctl status cron | sed -n '1,15p'
systemctl cat cron
journalctl -u cron --since "15 min ago" --no-pager | tail -n 20
```

Checklist:

- умею находить процессы-лидеры по `%CPU` и `%MEM`
- умею проверять и завершать конкретный PID
- умею смотреть состояние сервиса и связанные логи

---

## 7. Расширенная Лаба (Optional + Advanced)

### 7.1 Собираем и запускаем hello service/timer

Выполни команды из секции 5.2 и проверь:

- `hello.timer` виден в `list-timers`
- в `journalctl -u hello.service` есть события запуска/завершения
- в `journalctl -t hello` есть строка из нашего скрипта

### 7.2 Политика рестартов для flaky service

Выполни секцию 5.3 и проверь:

- растет `NRestarts`
- `ExecMainStatus=1`
- в логах видно crash и перезапуск

После проверки останови цикл:

```bash
sudo systemctl stop flaky
```

### 7.3 Hardening-проход

1. Добавь быстрые hardening-директивы в `hello.service`.
2. Выполни reload и запусти сервис.
3. Проверь успешный запуск и `ExecMainStatus=0`.

```bash
sudo systemctl daemon-reload
sudo systemctl restart hello.service
systemctl show -p ExecMainStatus hello.service
```

### 7.4 Проверка transient unit

Выполни секцию 5.5 и проверь логи и по unit, и по тэгу.

### 7.5 Включение persistent journald

Выполни секцию 5.6 и проверь, что хранение non-volatile и видно использование диска.

---

## 8. Очистка

```bash
sudo systemctl disable --now hello.timer 2>/dev/null || true
sudo systemctl stop hello.service flaky now-echo 2>/dev/null || true
sudo rm -f /etc/systemd/system/{hello.service,hello.timer,flaky.service}
sudo rm -f /usr/local/bin/hello.sh
sudo rm -f /etc/systemd/journald.conf.d/persistent.conf
sudo systemctl daemon-reload
```

---

## 9. Итоги Урока

- **Что изучил:** поток диагностики процессов, стратегию сигналов и базовую диагностику systemd/journalctl.
- **Что практиковал:** introspection сервиса (`status/cat/show`), фильтрацию логов и автоматизацию через timers.
- **Продвинутые навыки:** drop-in override, политика рестартов, transient units и persistent journald.
- **Фокус по безопасности:** hardening-директивы и принцип наименьших привилегий.
- **Артефакты в репозитории:** готовые скрипты и шаблоны unit-файлов в `lessons/05-processes-systemd-services/scripts/`.
- **Следующий шаг:** упаковать свои unit-файлы и скрипты в артефакты `lessons/05-processes-systemd-services/`.
