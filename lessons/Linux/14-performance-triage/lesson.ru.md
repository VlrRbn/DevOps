# lesson_14

# Performance Triage: CPU/RAM/IO, `vmstat`/`iostat`/`pidstat`, snapshot workflow

**Date:** 2026-02-21
**Topic:** практическая диагностика производительности Linux без guesswork: где упирается система (CPU, память, диск, процессы) и как собрать доказательства.  
**Daily goal:** пройти reproducible triage flow: быстрый health-check -> расширенный triage-отчет -> полноценный snapshot-архив для инцидента.

---

## 0. Prerequisites

Проверь базовые зависимости:

```bash
command -v bash awk nproc free ps uptime vmstat journalctl tar
```

Опционально для более глубокого анализа:

```bash
command -v iostat pidstat mpstat || echo "install sysstat for extended metrics"
```

Критичные правила безопасности:

- сначала снимаем метрики и факты, потом меняем конфиг;
- не делаем "слепой тюнинг" по одной цифре;
- если расследуешь инцидент, сохраняй snapshot до cleanup/restart.

---

## 1. Базовые Концепции

### 1.1 Что такое performance triage

Performance triage — это не "оптимизация", а **поиск узкого места**:

- CPU saturation;
- memory pressure и swap thrashing;
- disk IO wait/latency;
- noisy process/service.

### 1.2 Почему порядок важен

Правильный порядок экономит время:

1. общий фон (uptime/load/memory);
2. топ процессов;
3. time-sampled метрики (`vmstat`, `iostat`, `pidstat`);
4. архив артефактов для повторной проверки.

### 1.3 Почему `load average` нельзя читать в отрыве

`load` сам по себе не говорит "все плохо".
Нужно смотреть **load на ядро** (`load_per_core`):

- `~1.0` на ядро может быть нормой под нагрузкой;
- заметно выше `1.0` долгое время — признак очереди задач и contention.

### 1.4 Почему `MemAvailable` важнее "free"

`free` память может быть почти нулевой и это нормально (кэш).
Сигнал реального давления — низкий `MemAvailable` + рост swap + рост задержек.

### 1.5 Что дает `vmstat 1 N`

`vmstat` за короткий интервал показывает динамику:

- `r` — очередь runnable задач;
- `si/so` — swap in/out;
- `wa` — IO wait (процессы ждут диск).

### 1.6 Где помогают `iostat` и `pidstat`

- `iostat -xz` показывает latency/util по устройствам;
- `pidstat` показывает процессы, которые реально создают CPU/IO нагрузку.

### 1.7 Зачем нужен snapshot в архив

В инциденте важно сохранить точку времени:

- чтобы сравнить с "после фикса";
- чтобы не потерять контекст после перезапуска сервисов.

---

## 2. Приоритет Команд (Что Учить Сначала)

### Core (обязательно сейчас)

- `uptime`
- `free -h`
- `ps -eo ... --sort=-%cpu`
- `ps -eo ... --sort=-%mem`
- `vmstat 1 5`
- `journalctl --since "-30 min" -p warning..alert`

### Optional (после core)

- `iostat -xz 1 5`
- `pidstat 1 5`
- `mpstat -P ALL 1 5`
- `top -b -n 1`

### Advanced (уровень эксплуатации)

- strict health-check для cron/CI сигнализации
- triage report с файлами доказательств
- snapshot + tar.gz как incident artifact

---

## 3. Core Команды: Что / Зачем / Когда

### `uptime`

- **Что:** uptime и 1/5/15 min load.
- **Зачем:** мгновенный фон системы.
- **Когда:** первая команда triage.

```bash
uptime
```

### `free -h`

- **Что:** RAM/swap в человекочитаемом виде.
- **Зачем:** увидеть memory pressure и факт использования swap.
- **Когда:** сразу после load.

```bash
free -h
```

### `ps ... --sort=-%cpu`

- **Что:** топ процессов по CPU.
- **Зачем:** найти горячие процессы.
- **Когда:** если load высокий.

```bash
ps -eo pid,ppid,comm,%cpu,%mem,state --sort=-%cpu | head -n 15
```

### `ps ... --sort=-%mem`

- **Что:** топ процессов по памяти.
- **Зачем:** выявить memory hogs.
- **Когда:** если падает `MemAvailable` или растет swap.

```bash
ps -eo pid,ppid,comm,%cpu,%mem,state --sort=-%mem | head -n 15
```

### `vmstat 1 5`

- **Что:** семплирование CPU/memory/IO каждые 1s.
- **Зачем:** увидеть не статичный снимок, а поведение во времени.
- **Когда:** всегда после базового `ps`.

```bash
vmstat 1 5
```

### `journalctl --since "-30 min" -p warning..alert`

- **Что:** предупреждения/ошибки последних 30 минут.
- **Зачем:** сопоставить нагрузку с системными симптомами.
- **Когда:** параллельно с метриками.

```bash
journalctl --since "-30 min" -p warning..alert --no-pager | tail -n 120
```

---

## 4. Optional Команды (После Core)

Optional нужен, когда core уже показал "что-то не так", и надо локализовать глубже.

### 4.1 `iostat -xz 1 5`

- **Что:** extended disk stats (await/svctm/util и др.).
- **Зачем:** понять, утыкаемся ли в диск/очереди IO.
- **Когда:** при высоком `wa` в `vmstat`.

```bash
iostat -xz 1 5
```

### 4.2 `pidstat 1 5`

- **Что:** поминутная (по секундам) статистика по процессам.
- **Зачем:** отследить, кто генерирует нагрузку прямо сейчас.
- **Когда:** если обычный `ps` не ловит кратковременные пики.

```bash
pidstat 1 5
```

### 4.3 `mpstat -P ALL 1 5`

- **Что:** загрузка по каждому CPU ядру.
- **Зачем:** обнаружить перекос нагрузки по ядрам.
- **Когда:** если общий CPU вроде норм, но приложение лагает.

```bash
mpstat -P ALL 1 5
```

### 4.4 `top -b -n 1`

- **Что:** одноразовый batch dump `top`.
- **Зачем:** удобный снимок для отчета/вложения.
- **Когда:** при сборе артефактов инцидента.

```bash
top -b -n 1 | sed -n '1,40p'
```

### Что делать в Optional на практике

1. Если `vmstat` показывает высокий `wa` -> запускай `iostat`.
2. Если spike короткий -> снимай `pidstat`.
3. Если проблема "одно ядро в 100%" -> проверяй `mpstat -P ALL`.
4. Все результаты сохраняй в один triage/report файл.

---

## 5. Advanced Темы (Ops-Grade)

### 5.1 Health-check с порогами

Пороговая проверка (`--strict`) нужна для cron/CI, где нужен machine-readable результат:

- exit code `0` = ок;
- exit code `1` = detected pressure;
- можно вешать алерты/нотификации.

### 5.2 Репорт как runbook-артефакт

Extended triage report полезен для handoff:

- видно окружение, тайминг, процесс-листы и sample-метрики;
- не нужно "вручную вспоминать" что запускали.

### 5.3 Snapshot + archive

Snapshot нужен как "заморозка состояния":

- позволяет позже пересмотреть incident;
- можно приложить к задаче/тикету;
- исключает потерю данных после рестарта/cleanup.

---

## 6. Скрипты в Этом Уроке

```bash
chmod +x lessons/14-performance-triage/scripts/*.sh

lessons/14-performance-triage/scripts/perf-health-check.sh
lessons/14-performance-triage/scripts/perf-triage.sh
lessons/14-performance-triage/scripts/perf-snapshot.sh
```

### `perf-health-check.sh`

**Что делает:** быстрый check load/memory/swap/iowait + топ процессов.  
**Зачем:** за 30-60 секунд понять, есть ли явные признаки давления.  
**Когда запускать:** в начале расследования и в cron (с `--strict`).

```bash
./lessons/14-performance-triage/scripts/perf-health-check.sh
./lessons/14-performance-triage/scripts/perf-health-check.sh --strict
```

### `perf-triage.sh`

**Что делает:** расширенный triage-репорт с time-sampling (`vmstat`, опционально `iostat/pidstat`).  
**Зачем:** получить воспроизводимый отчет для анализа/передачи.  
**Когда запускать:** когда health-check не ок или есть жалобы на лаги.

```bash
./lessons/14-performance-triage/scripts/perf-triage.sh --seconds 8
./lessons/14-performance-triage/scripts/perf-triage.sh --seconds 8 --save-dir /tmp/lesson14-reports
./lessons/14-performance-triage/scripts/perf-triage.sh --strict --save-dir /tmp/lesson14-reports
```

### `perf-snapshot.sh`

**Что делает:** собирает системные артефакты и упаковывает в `tar.gz`.  
**Зачем:** сохранить доказательства инцидента "как было".  
**Когда запускать:** перед изменениями и перед cleanup/restart.

```bash
./lessons/14-performance-triage/scripts/perf-snapshot.sh
./lessons/14-performance-triage/scripts/perf-snapshot.sh --out-dir /tmp/lesson14-artifacts --seconds 8
```

---

## 7. Практика (Manual Flow)

### Шаг 1. Быстрый baseline

```bash
uptime
free -h
ps -eo pid,ppid,comm,%cpu,%mem,state --sort=-%cpu | head -n 12
vmstat 1 5
```

### Шаг 2. Глубже (если нужно)

```bash
iostat -xz 1 5
pidstat 1 5
journalctl --since "-30 min" -p warning..alert --no-pager | tail -n 120
```

### Шаг 3. Скриптовый triage + snapshot

```bash
./lessons/14-performance-triage/scripts/perf-triage.sh --seconds 8 --save-dir /tmp/lesson14-reports
./lessons/14-performance-triage/scripts/perf-snapshot.sh --out-dir /tmp/lesson14-artifacts --seconds 8
```

---

## 8. Troubleshooting

### "Нет `iostat`/`pidstat`"

Поставь `sysstat`:

```bash
sudo apt-get update
sudo apt-get install -y sysstat
```

### "`perf-health-check --strict` падает"

Это ожидаемо: strict-режим специально возвращает non-zero при признаках давления.

### "Высокий load, но CPU вроде не 100%"

Проверь:

- `vmstat` (поля `r`, `wa`);
- `iostat` (диск может быть bottleneck);
- blocked tasks в `ps state`.

### "Snapshot не содержит `dmesg`"

Это ожидаемо при запуске без root-прав: скрипт сохраняет доступные данные и пишет `INFO` в `dmesg-err-warn.txt`.
Запусти snapshot под `sudo`, если нужен полный kernel-контекст.

---

## 9. Итоги Урока

- **Что изучил:** как проводить performance triage по слоям CPU/RAM/IO и не ставить диагноз по одной метрике.
- **Что практиковал:** baseline-проверки (`uptime/free/ps/vmstat`), углубление через `iostat/pidstat`, и сбор отчета/снапшота скриптами.
- **Продвинутые навыки:** symptom-driven локализация bottleneck по метрикам и логам с отделением причины от косвенных симптомов.
- **Операционный фокус:** evidence-first подход (сначала данные, потом изменения), reproducible отчеты и безопасный handoff артефактов.
- **Артефакты в репозитории:** `lessons/14-performance-triage/scripts/`, `lessons/14-performance-triage/scripts/README.md`.
