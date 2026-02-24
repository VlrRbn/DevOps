# lesson_15

# Linux Capstone: Incident Runbook, Evidence-First Triage, Handoff

**Date:** 2026-02-22
**Topic:** финальная Linux-практика: объединение boot/process/storage/network навыков в единый incident workflow.  
**Daily goal:** пройти end-to-end сценарий: health gate -> triage -> snapshot -> выводы и handoff без guesswork.

---

## 0. Prerequisites

Проверь базовые зависимости:

```bash
command -v bash awk free df uptime nproc vmstat ip ss lsblk findmnt journalctl tar
```

Опционально для расширенного анализа:

```bash
command -v systemctl iostat pidstat dmesg || echo "optional tools missing"
```

Операционные правила:

- сначала собрать evidence, потом править систему;
- не смешивать диагностику и remediation в одном шаге;
- перед risky-change всегда делать snapshot.

---

## 1. Базовые Концепции

### 1.1 Что такое capstone

Capstone — это не новая тема, а интеграция предыдущих:

- boot/systemd сигналы;
- process/resource pressure;
- storage/mount consistency;
- network reachability и listeners;
- reproducible evidence bundle.

### 1.2 Почему нужен единый runbook

Без runbook разбор превращается в хаотичный набор команд.
С runbook ты получаешь:

- предсказуемую последовательность;
- одинаковый quality bar для каждого инцидента;
- понятный handoff другому инженеру.

### 1.3 Evidence-first подход

Ключевая практика:

1. собрать текущее состояние;
2. зафиксировать симптомы и тайминг;
3. только потом менять конфиги/сервисы.

### 1.4 Минимальный набор сигналов

Для первичной локализации обычно хватает:

- run state + failed units;
- load/memory/disk pressure;
- сеть: default route + listeners;
- journal warnings/errors + kernel hints.

---

## 2. Приоритет Команд (Что Учить Сначала)

### Core (обязательно сейчас)

- `systemctl is-system-running`
- `systemctl list-units --failed --no-pager --plain`
- `uptime`, `free -h`, `df -h /`, `vmstat 1 5`
- `ip route`, `ss -tulpen`
- `journalctl --since "-2h" -p warning..alert --no-pager`

### Optional (после core)

- `iostat -xz 1 5`
- `pidstat 1 5`
- `findmnt --verify`
- `dmesg --level=err,warn`

### Advanced (уровень эксплуатации)

- script-based strict health gate
- triage report для инцидента/тикета
- snapshot + archive для handoff и postmortem

---

## 3. Core Команды: Что / Зачем / Когда

### `systemctl is-system-running`

- **Что:** общий system state (`running/degraded/...`).
- **Зачем:** быстро понять, есть ли системная деградация.
- **Когда:** первая команда в incident flow.

```bash
systemctl is-system-running
```

### `systemctl list-units --failed`

- **Что:** список failed units.
- **Зачем:** перейти от симптома к объектам.
- **Когда:** сразу после run state.

```bash
systemctl list-units --failed --no-pager --plain
```

### `uptime/free/df/vmstat`

- **Что:** core resource pressure snapshot.
- **Зачем:** увидеть CPU/RAM/disk картину в одном месте.
- **Когда:** базовый ресурсный check до deep dive.

```bash
uptime
free -h
df -h /
vmstat 1 5
```

### `ip route` и `ss -tulpen`

- **Что:** route/listener состояние.
- **Зачем:** отличить network path issue от service bind issue.
- **Когда:** при симптомах "не отвечает".

```bash
ip route
ss -tulpen | sed -n '1,80p'
```

### `journalctl --since ... -p warning..alert`

- **Что:** ошибки/предупреждения за окно времени.
- **Зачем:** связать симптомы с таймлайном событий.
- **Когда:** после базовых checks.

```bash
journalctl --since "-2h" -p warning..alert --no-pager | sed -n '1,200p'
```

---

## 4. Optional Команды (После Core)

### `iostat -xz 1 5`

- **Что:** латентность/утилизация дисков.
- **Зачем:** подтвердить/исключить IO bottleneck.

```bash
iostat -xz 1 5
```

### `pidstat 1 5`

- **Что:** sampled процессная нагрузка.
- **Зачем:** поймать короткие spikes и noisy processes.

```bash
pidstat 1 5
```

### `findmnt --verify`

- **Что:** consistency-check mount/fstab.
- **Зачем:** быстро поймать mount-конфликт до reboot.

```bash
findmnt --verify
```

### `dmesg --level=err,warn`

- **Что:** kernel-level ошибки и предупреждения.
- **Зачем:** low-level подтверждение проблем устройств/FS/driver.

```bash
sudo dmesg --level=err,warn | tail -n 80
```

---

## 5. Advanced Темы (Ops-Grade)

### 5.1 Структура incident report

Минимум, который должен быть в handoff:

- symptom + impact;
- timeframe;
- key metrics and logs;
- hypothesis;
- next action / owner.

### 5.2 Strict checks как quality gate

`--strict` не "чинит" систему, но останавливает pipeline/скрипт, если базовый bar не пройден.

### 5.3 Snapshot discipline

Snapshot делается до changes и cleanup, чтобы постфактум не потерять исходную картину.

---

## 6. Скрипты в Этом Уроке

### `capstone-health-check.sh`

**Что делает:** быстрый gate по состоянию системы, ресурсам и базовой сети.  
**Зачем:** получить “go/no-go” за 30-60 секунд.  
**Когда запускать:** в начале разбора и в automation (`--strict`).

```bash
./lessons/15-linux-capstone-incident-runbook/scripts/capstone-health-check.sh
./lessons/15-linux-capstone-incident-runbook/scripts/capstone-health-check.sh --strict
./lessons/15-linux-capstone-incident-runbook/scripts/capstone-health-check.sh --json
```

### `capstone-triage.sh`

**Что делает:** расширенный triage report по system/resource/network/log слоям.  
**Зачем:** собрать доказательства и упростить handoff.  
**Когда запускать:** когда нужен разбор причины и timeline.

```bash
./lessons/15-linux-capstone-incident-runbook/scripts/capstone-triage.sh --seconds 8 --since "-4h"
./lessons/15-linux-capstone-incident-runbook/scripts/capstone-triage.sh --seconds 8 --since "-4h" --save-dir /tmp/lesson15-reports
./lessons/15-linux-capstone-incident-runbook/scripts/capstone-triage.sh --seconds 8 --since "-4h" --json --save-dir /tmp/lesson15-reports
./lessons/15-linux-capstone-incident-runbook/scripts/capstone-triage.sh --strict --save-dir /tmp/lesson15-reports
```

### `capstone-snapshot.sh`

**Что делает:** полный evidence bundle + архив `.tar.gz`.  
**Зачем:** зафиксировать состояние до изменений и для postmortem.  
**Когда запускать:** до remediation и cleanup.

```bash
./lessons/15-linux-capstone-incident-runbook/scripts/capstone-snapshot.sh
./lessons/15-linux-capstone-incident-runbook/scripts/capstone-snapshot.sh --out-dir /tmp/lesson15-artifacts --since "-4h" --seconds 8
```

---

## 7. Практика (Manual Flow)

### Шаг 1. Быстрый baseline

```bash
systemctl is-system-running
systemctl list-units --failed --no-pager --plain
uptime
free -h
df -h /
ip route
```

### Шаг 2. Локализация и лог-таймлайн

```bash
vmstat 1 5
ss -tulpen | sed -n '1,80p'
journalctl --since "-2h" -p warning..alert --no-pager | sed -n '1,200p'
```

### Шаг 3. Скриптовый flow

```bash
./lessons/15-linux-capstone-incident-runbook/scripts/capstone-health-check.sh --strict
./lessons/15-linux-capstone-incident-runbook/scripts/capstone-triage.sh --seconds 8 --since "-4h" --save-dir /tmp/lesson15-reports
./lessons/15-linux-capstone-incident-runbook/scripts/capstone-snapshot.sh --out-dir /tmp/lesson15-artifacts --since "-4h" --seconds 8
```

---

## 8. Troubleshooting

### "`systemctl` недоступен/не отвечает"

Запусти core resource/network команды и triage script вне systemd-секции.
На контейнерных/ограниченных окружениях часть unit-checks может быть недоступна.

### "`dmesg` пустой или permission denied"

Ожидаемо без root-прав на hardened системах.
Запусти triage/snapshot под `sudo`, если нужен kernel контекст.

### "`iostat`/`pidstat` не найдены"

Это optional блоки. Установи `sysstat`, если нужна deep sampling диагностика:

```bash
sudo apt-get update
sudo apt-get install -y sysstat
```

### "Strict mode падает, но сервисы вроде живы"

`--strict` проверяет базовые пороги и operational readiness.
Это сигнал для проверки, а не автоматический verdict "все сломано".

---

## 9. Итоги Урока

- **Что изучил:** как объединять Linux-навыки из 1-14 в единый incident runbook.
- **Что практиковал:** evidence-first triage, strict checks, и reproducible snapshot/handoff flow.
- **Продвинутые навыки:** symptom-driven анализ с разделением signal/noise и фиксацией hypothesis до изменений.
- **Операционный фокус:** минимальный риск, предсказуемый workflow и качество артефактов.
- **Артефакты в репозитории:** `lessons/15-linux-capstone-incident-runbook/scripts/`, `lessons/15-linux-capstone-incident-runbook/scripts/README.md`.
