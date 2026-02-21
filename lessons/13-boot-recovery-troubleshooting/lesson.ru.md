# lesson_13

# Boot и Recovery: `journalctl -b`, `systemctl --failed`, `dmesg`, `rescue/emergency`

**Date:** 2026-02-20
**Topic:** диагностика проблем после загрузки, безопасный triage и подготовка к recovery-действиям.  
**Daily goal:** Научиться быстро отвечать на вопрос "почему система загрузилась в degraded/неподнятом состоянии" и действовать по воспроизводимому runbook.

---

## 0. Prerequisites

Проверь базовые зависимости:

```bash
command -v systemctl journalctl findmnt lsblk dmesg
```

Опционально для расширенной диагностики:

```bash
command -v grubby update-grub || echo "grub tools differ by distro"
```

Критичные правила безопасности:

- `rescue`/`emergency` режимы запускаем только через локальную консоль/VM;
- на удаленном сервере без out-of-band доступа не делаем `systemctl isolate rescue.target`;
- перед risky-change делаем snapshot конфигов.

---

## 1. Базовые Концепции

### 1.1 Что значит "система загрузилась"

Успешная загрузка не равна "все идеально".

Система может загрузиться, но быть:

- `degraded` (есть failed units);
- с проблемным `fstab` mount;
- с сервисами в crash-loop.

### 1.2 Почему `journalctl -b` главный источник

`journalctl -b` показывает события текущей загрузки, а `journalctl -b -1` — предыдущей.

Это ключ к post-reboot проблемам: ты видишь, что происходило именно в момент boot.

### 1.3 `systemd` run state и failed units

Две быстрые проверки:

- `systemctl is-system-running` — общий статус (`running/degraded/...`);
- `systemctl list-units --failed` — конкретные провалившиеся unit-ы.

### 1.4 Где роль `dmesg`

`journalctl` показывает user-space и service-события, а `dmesg` — kernel/message bus слой.

Если есть проблемы драйвера, диска, fs, kernel path — часто они первыми видны в `dmesg`.

### 1.5 `findmnt --verify` и `fstab`

Неправильная строка в `/etc/fstab` может дать долгий boot, degraded state, или emergency-mode.

`findmnt --verify` — быстрый способ проверить consistency mount-метаданных.

### 1.6 Rescue vs Emergency

- `rescue.target` — минимальный multi-user rescue (обычно с базовыми сервисами и root shell);
- `emergency.target` — максимально минимальный режим (почти без сервисов).

Практический смысл:

- rescue — когда надо чинить сервисы/mount при работающем минимуме;
- emergency — когда нужно максимально "чистое" окружение для repair.

### 1.7 Общий triage workflow

1. run state + failed units;
2. boot journal (`-b`, при необходимости `-b -1`);
3. kernel errors (`dmesg`);
4. mount/fstab verify;
5. только после этого — corrective actions.

---

## 2. Приоритет Команд (Что Учить Сначала)

### Core (обязательно сейчас)

- `systemctl is-system-running`
- `systemctl list-units --failed --no-pager --plain`
- `journalctl -b -p err..alert --no-pager`
- `journalctl -b -1 -p err..alert --no-pager`
- `findmnt --verify`
- `dmesg --level=err,warn`

### Optional (после core)

- `systemctl status <unit>`
- `journalctl -u <unit> --since ...`
- `systemctl list-dependencies rescue.target`
- `cat /proc/cmdline`

### Advanced (уровень эксплуатации)

- controlled switch в `rescue/emergency` (только local console)
- rollback-safe правки boot-конфигов
- инцидентный runbook: symptom -> check -> action

---

## 3. Core Команды: Что / Зачем / Когда

### `systemctl is-system-running`

- **Что:** общий state systemd.
- **Зачем:** понять "здорова" система или уже degraded.
- **Когда:** первая команда в triage.

```bash
systemctl is-system-running
```

### `systemctl list-units --failed --no-pager --plain`

- **Что:** список unit-ов с ошибками.
- **Зачем:** сразу перейти от симптома к конкретным объектам.
- **Когда:** сразу после run-state.

```bash
systemctl list-units --failed --no-pager --plain
```

### `journalctl -b -p err..alert --no-pager`

- **Что:** ошибки текущего boot.
- **Зачем:** отфильтровать шум и увидеть критичные события.
- **Когда:** после failed units.

```bash
journalctl -b -p err..alert --no-pager | sed -n '1,120p'
```

### `journalctl -b -1 -p err..alert --no-pager`

- **Что:** ошибки предыдущей загрузки.
- **Зачем:** если проблема проявилась "после reboot ночью".
- **Когда:** когда текущий boot малоинформативен.

```bash
journalctl -b -1 -p err..alert --no-pager | sed -n '1,120p'
```

### `findmnt --verify`

- **Что:** верификация mount/fstab метаданных.
- **Зачем:** быстро поймать типовые ошибки в fstab-схеме.
- **Когда:** если есть mount-related alerts или degraded после boot.

```bash
findmnt --verify
```

### `dmesg --level=err,warn`

- **Что:** kernel warnings/errors.
- **Зачем:** увидеть драйвер/диск/fs/kernel проблемы.
- **Когда:** если по journal видно low-level issue или IO проблемы.

```bash
sudo dmesg --level=err,warn | tail -n 80
```

---

## 4. Optional Команды (После Core)

Optional блок нужен, чтобы от общего статуса перейти к root cause конкретного unit.

### 4.1 `systemctl status <unit>`

- **Что:** state + recent logs конкретного сервиса.
- **Зачем:** понять почему unit failed/restarting.
- **Когда:** после `list-units --failed`.

```bash
systemctl status ssh --no-pager | sed -n '1,40p'
```

### 4.2 `journalctl -u <unit> --since ...`

- **Что:** unit-specific timeline.
- **Зачем:** выделить только релевантные логи.
- **Когда:** для crash-loop/service timeout разборов.

```bash
journalctl -u ssh --since "-30 min" --no-pager | tail -n 80
```

### 4.3 `systemctl list-dependencies rescue.target`

- **Что:** dependencies rescue target.
- **Зачем:** понимать, что реально поднимется в rescue.
- **Когда:** перед planned recovery drills.

```bash
systemctl list-dependencies rescue.target --no-pager
```

### 4.4 `cat /proc/cmdline`

- **Что:** активные kernel boot parameters.
- **Зачем:** проверить, какие параметры реально применились.
- **Когда:** при расследовании boot-param regressions.

```bash
cat /proc/cmdline
```

### Что делать в Optional на практике

1. Выбери один failed unit.
2. Сними `status` + `journalctl -u`.
3. Сопоставь время ошибки с boot journal.
4. Зафиксируй hypothesis перед изменениями.

---

## 5. Advanced Темы (Ops-Grade)

### 5.1 Recovery snapshot перед изменениями

Перед правкой boot/fstab/systemd-конфигов делай snapshot:

- `/etc/fstab`, `/etc/default/grub`, `/etc/systemd/system/*`;
- current boot diagnostics;
- список failed units.

Это снижает время rollback и потери контекста.

### 5.2 Controlled recovery flow

Стандартный flow:

1. diagnose (read-only);
2. isolate one likely root cause;
3. apply smallest safe fix;
4. verify (`is-system-running`, `--failed`, boot journal);
5. document outcome.

### 5.3 `rescue/emergency` только с безопасным доступом

Режимы recovery могут разорвать SSH-сессию.

Правило:

- если нет local console/VM console/IPMI/SSM-like access — не переключаем target на удаленном хосте.

### 5.4 Что делать, если `fstab` сломан

Быстрый safe-путь:

1. получить shell (rescue/emergency/local console);
2. откатить problematic строки;
3. `findmnt --verify`;
4. `systemctl daemon-reload`;
5. reboot и проверка run-state.

### 5.5 Симптомы и диагностика

| Симптом | Проверка | Типичная причина | Действие |
|---|---|---|---|
| `degraded` после boot | `is-system-running`, `--failed` | один/несколько unit failed | triage конкретных unit + fix |
| долгий boot | `journalctl -b`, `findmnt --verify` | mount timeout/fstab issue | поправить fstab, проверить nofail/x-systemd opts |
| сервис в restart loop | `status`, `journalctl -u` | bad config/env/permission | исправить config и проверить dependency chain |
| "непонятный" boot fail | `dmesg`, `journalctl -b -1` | kernel/fs/device уровень | локализовать слой и чинить точечно |

### 5.6 Что делать в Advanced пошагово

```bash
# 1) baseline
systemctl is-system-running
systemctl list-units --failed --no-pager --plain

# 2) boot errors
journalctl -b -p err..alert --no-pager | sed -n '1,120p'

# 3) mount/fstab
findmnt --verify

# 4) kernel layer
sudo dmesg --level=err,warn | tail -n 80
```

---

## 6. Скрипты в Этом Уроке

Скрипты здесь — ускорители triage и документации, не замена пониманию ручного flow.

### 6.1 Ручной Core-проход (1 раз сделать без скрипта)

```bash
# 1) global state
systemctl is-system-running
systemctl list-units --failed --no-pager --plain

# 2) boot errors (current + previous boot)
journalctl -b -p err..alert --no-pager | sed -n '1,120p'
journalctl -b -1 -p err..alert --no-pager | sed -n '1,120p'

# 3) mount/fstab consistency
findmnt --verify

# 4) kernel warnings/errors
sudo dmesg --level=err,warn | tail -n 80
```

### 6.2 Скрипты (automation)

```bash
chmod +x lessons/13-boot-recovery-troubleshooting/scripts/*.sh

lessons/13-boot-recovery-troubleshooting/scripts/boot-health-check.sh
lessons/13-boot-recovery-troubleshooting/scripts/boot-triage.sh --boot 0 --since "-2h"
lessons/13-boot-recovery-troubleshooting/scripts/recovery-snapshot.sh --out-dir /tmp
```

### 6.3 Что делает каждый скрипт

| Скрипт | Что делает | Когда запускать |
|---|---|---|
| `boot-health-check.sh` | быстрый health baseline | первым шагом triage |
| `boot-triage.sh` | расширенный boot-report (journal + failed units + dmesg + findmnt) | когда нужно собрать доказательства и timeline |
| `recovery-snapshot.sh` | сохраняет конфиги и диагностику в snapshot-папку | перед risky изменениями и для incident records |

---

## 7. Мини-Лаба (Core Path)

Цель: пройти полный boot-triage cycle без изменений в системе.

```bash
# quick health
lessons/13-boot-recovery-troubleshooting/scripts/boot-health-check.sh

# focused triage
lessons/13-boot-recovery-troubleshooting/scripts/boot-triage.sh --boot 0 --since "-1h"

# collect snapshot
lessons/13-boot-recovery-troubleshooting/scripts/recovery-snapshot.sh --out-dir /tmp
```

Критерии успеха:

- есть явный run-state и список failed units (или факт их отсутствия);
- есть boot-level evidence из `journalctl -b`;
- snapshot артефактов сохранен в `/tmp/recovery-snapshot_*`.

---

## 8. Расширенная Лаба (Optional + Advanced)

### 8.1 Предыдущая загрузка

```bash
lessons/13-boot-recovery-troubleshooting/scripts/boot-triage.sh --boot -1 --strict
```

### 8.2 Unit-level drill

```bash
# заменяй ssh на реальный failed unit
systemctl status ssh --no-pager | sed -n '1,60p'
journalctl -u ssh --since "-2h" --no-pager | tail -n 120
```

### 8.3 Recovery mode drill (только VM/local console)

```bash
# WARNING: на remote host можно потерять сессию
sudo systemctl isolate rescue.target
# после проверки/работ вернуться:
sudo systemctl default
```

### 8.4 Snapshot before change

```bash
lessons/13-boot-recovery-troubleshooting/scripts/recovery-snapshot.sh --out-dir /tmp/lesson13-artifacts
ls -la /tmp/lesson13-artifacts
```

---

## 9. Очистка

Для этого урока cleanup минимальный (изменений почти нет).

Опционально удалить собранные артефакты:

```bash
rm -rf /tmp/recovery-snapshot_* /tmp/lesson13-artifacts/recovery-snapshot_* 2>/dev/null || true
```

---

## 10. Итоги Урока

- **Что изучил:** как читать boot-проблемы через `systemd` + `journalctl -b` + `dmesg` + `findmnt --verify`.
- **Что практиковал:** reproducible triage workflow и сбор recovery-снимков до изменений.
- **Что теперь смогу сделать вручную:** быстро локализовать boot/degraded проблему до конкретного слоя (unit/mount/kernel).
- **Следующий шаг:** урок 14 (performance triage) — CPU/RAM/IO bottleneck analysis и операционные метрики без guesswork.
- **Артефакты в репозитории:** `lessons/13-boot-recovery-troubleshooting/scripts/`, `lessons/13-boot-recovery-troubleshooting/scripts/README.md`.