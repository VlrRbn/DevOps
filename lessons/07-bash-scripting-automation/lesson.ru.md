# lesson_07

# Bash Скриптинг: Безопасные Паттерны и Практическая Автоматизация

**Date:** 2025-08-27  
**Topic:** Безопасные шаблоны Bash, парсинг аргументов, файловая автоматизация, бэкапы и journal/systemd хелперы  
**Daily goal:** Писать надежные Bash-скрипты, которые безопасны по умолчанию и полезны в ежедневной эксплуатации.
**Bridge:** [05-07 Operations Bridge](../00-foundations-bridge/05-07-operations-bridge.ru.md) — компенсация недостающих практических тем после уроков 5-7.

---

## 1. Базовые Концепции

### 1.1 Базовая безопасность скриптов

Надежный Bash-скрипт обычно начинается с:

- strict mode (`set -Eeuo pipefail`)
- безопасного `IFS` (`IFS=$'\n\t'`)
- диагностики ошибок (`trap ... ERR`)

Это помогает ловить тихие ошибки как можно раньше.

### 1.2 Дисциплина входа и выхода

Для предсказуемого поведения:

- валидируем аргументы
- всегда аккуратно экранируем переменные (`"$var"`)
- используем массивы для сборки сложных команд
- печатаем явные success/error сообщения

### 1.3 Идемпотентность и dry-run мышление

Операционные скрипты лучше делать:

- повторяемыми (повторный запуск не ломает состояние)
- с режимом предпросмотра (`-n` / `--dry-run`)
- явными по отношению к потенциально опасным действиям

### 1.4 Зачем нужен ShellCheck

`shellcheck` ловит типичные ошибки Bash до выполнения:

- незаквоченные переменные
- хрупкие циклы по файлам
- скрытые ошибки в пайплайнах
- опасные подстановки

### 1.5 Что у нас за что отвечает?

- **Core:** минимальный набор для безопасного написания и проверки простых скриптов.
- **Optional:** рост скорости и устойчивости в реальных кейсах с файлами/логами.
- **Advanced:** эксплуатационные паттерны (lock, rotation, follow-mode, лучший CLI).

### 1.6 Мини-шпаргалка по синтаксису shell (для этого урока)

Если строка в скрипте выглядит "непонятно", чаще всего это вопрос синтаксиса:

- `$var` - значение переменной.
- `${var}` - то же, но удобнее рядом с текстом (`"${base}_$ts"`).
- `$(command)` - подстановка результата команды.
- `printf '%s\n' "$name"` - `%s` это строка, `\n` это перевод строки.
- `2>/dev/null` - скрыть stderr (ошибки) команды.
- `cmd || true` - не падать в месте, где ошибка ожидаема.
- `cmd1 && cmd2` - запускать `cmd2`, только если `cmd1` успешна.
- `--` - конец опций, дальше только аргументы (полезно для "странных" имен файлов).

---

## 2. Приоритет Команд (Что Учить Сначала)

### Core (обязательно сейчас)

- `bash -n <script.sh>`
- `shellcheck <script.sh>`
- `chmod +x <script.sh>`
- `./<script.sh> --help`
- паттерн `set -Eeuo pipefail`
- базовый `getopts`

### Optional (после core)

- `find ... -print0` + `read -r -d ''`
- `xargs -0`
- `tar -C ... -czf ...`
- `journalctl -u <unit> --since ... -n ...`
- `systemctl status <unit> --no-pager`

### Advanced (уровень эксплуатации)

- `flock` для single-instance выполнения
- `logger -t <tag>` для trail в syslog/journal
- массивы команд для безопасной динамической сборки
- флаги `dry-run/verbose/follow/priority`
- retention и валидация backup-артефактов

---

## 3. Core Команды и Паттерны: Что / Зачем / Когда

### `bash -n <script.sh>`

- **Что:** проверка синтаксиса без запуска.
- **Зачем:** быстро ловит parse-ошибки.
- **Когда:** после любого редактирования скрипта.

```bash
bash -n lessons/07-bash-scripting-automation/scripts/rename-ext.sh
```

### `shellcheck <script.sh>`

- **Что:** статический анализ shell-скрипта.
- **Зачем:** ранний поиск проблем с quoting/splitting/логикой.
- **Когда:** перед коммитом и перед использованием в прод-потоке.

```bash
shellcheck lessons/07-bash-scripting-automation/scripts/backup-dir.sh
```

### `chmod +x <script.sh>` + прямой запуск

- **Что:** делаем скрипт исполняемым и запускаем напрямую.
- **Зачем:** стандартный путь для переиспользуемых тулзов.
- **Когда:** после создания/обновления скрипта.

```bash
chmod +x lessons/07-bash-scripting-automation/scripts/*.sh
./lessons/07-bash-scripting-automation/scripts/rename-ext.sh --help
```

### Safe template baseline

- **Что:** минимальный шаблон с strict mode, IFS и ERR trap.
- **Зачем:** снижает количество тихих и сложных для диагностики ошибок.
- **Когда:** в начале любого нового ops-скрипта.

```bash
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
trap 'echo "ERR:$? at ${BASH_SOURCE[0]}:${LINENO}" >&2' ERR
```

### Базовый `getopts` для флагов

- **Что:** надежный парсинг CLI-флагов (`-n`, `-v` и т.д.).
- **Зачем:** чистый интерфейс и предсказуемое поведение.
- **Когда:** если у скрипта есть режимы/опции.

```bash
dry=0
while getopts ":nv" opt; do
  case "$opt" in
    n) dry=1 ;;
    v) verbose=1 ;;
    *) echo "Usage..."; exit 1 ;;
  esac
done
shift $((OPTIND-1))
```

---

## 4. Optional Команды и Зачем Они Нужны

### `find ... -print0` + `read -r -d ''`

- **Что:** безопасная итерация файлов через NUL-разделитель.
- **Зачем:** корректно работает с пробелами и нестандартными символами в именах.
- **Когда:** рекурсивные операции по пользовательским файлам.

```bash
find "$dir" -type f -name "*.txt" -print0 |
while IFS= read -r -d '' f; do
  echo "$f"
done
```

### `xargs -0`

- **Что:** безопасно читает NUL-разделенный ввод.
- **Зачем:** надежные batch-операции без ошибок word-splitting.
- **Когда:** cleanup и rotation пайплайны.

```bash
find "$out" -type f -name '*.tar.gz' -print0 | xargs -0 -r rm -f
```

Анти-паттерн, которого лучше избегать:

```bash
for f in $(find "$dir" -type f); do
  echo "$f"
done
```

Почему плохо:

- ломается на пробелах в именах файлов;
- ломается на переводах строк в именах файлов.

Предпочтительный подход в этом уроке: `find -print0` + `read -d ''` или `xargs -0`.

### `tar -C ... -czf ...`

- **Что:** создает архив из контролируемой базовой директории.
- **Зачем:** не тянет абсолютные пути, архив получается предсказуемым.
- **Когда:** backup, артефакты, миграционные пакеты.

```bash
tar -C "$(dirname -- "$dir")" -czf "$tarball" "$(basename -- "$dir")"
```

### `systemctl status` + `journalctl -u`

- **Что:** быстрый снимок статуса сервиса и его логов.
- **Зачем:** ускоряет диагностику после изменений.
- **Когда:** проверка сервисов после деплоя/автоматизации.

```bash
systemctl status cron --no-pager | sed -n '1,12p'
journalctl -u cron --since "15 min ago" -n 50 --no-pager
```

---

## 5. Advanced Темы (Ops-Grade Паттерны)

Эти паттерны влияют на надежность на уровне эксплуатации:

- защита от параллельных запусков
- наблюдаемость действий через системные логи
- режимы CLI, снижающие риск слепых изменений

### 5.1 Single-instance через `flock`

- **Что:** блокирует параллельный запуск скрипта на один ресурс.
- **Зачем:** защищает от гонок и порчи backup-артефактов.
- **Когда:** cron/systemd timers и любые shared-ресурсы.

Шаблон:

```bash
lock="/tmp/backup-$base.lock"
{
  flock -n 9 || { echo "Another run in progress" >&2; exit 1; }
  # critical section
} 9> "$lock"
```

### 5.2 Audit trail через `logger`

- **Что:** пишет событие скрипта в syslog/journal.
- **Зачем:** действия скрипта становятся видимыми в системной телеметрии.
- **Когда:** backup/deploy/rotation/maintenance скрипты.

```bash
logger -t backup "Created $tarball"
```

### 5.3 Массивы команд для безопасной динамики

- **Что:** собираем команду как массив Bash.
- **Зачем:** меньше ошибок с quoting при условных аргументах.
- **Когда:** у команды есть опциональные флаги.

```bash
cmd=(tar -C "$base_dir" -czf "$tarball")
[[ -n "$exclude" ]] && cmd+=("--exclude=$exclude")
cmd+=("$base")
"${cmd[@]}"
```

### 5.4 Валидация архива до rotation/delete

- **Что:** проверяем архив до удаления старых копий.
- **Зачем:** не потерять рабочие копии после невалидного нового backup.
- **Когда:** любые скрипты с retention-политикой.

```bash
tar -tzf "$tarball" >/dev/null
```

### 5.5 Гибкие флаги log-helper (`-s/-n/-f/-p`)

- **Что:** настраиваемый просмотр логов по времени, количеству, приоритету и follow.
- **Зачем:** один helper заменяет частые ручные команды.
- **Когда:** triage инцидентов и быстрая проверка сервисов.

Пример:

```bash
./lessons/07-bash-scripting-automation/scripts/devops-tail.v2.sh cron -s "1 hour ago" -n 200 -p warning
```

---

## 6. Скрипты в Этом Уроке

Готовые артефакты лежат в:

- `lessons/07-bash-scripting-automation/scripts/`

Выставить execute-бит один раз:

```bash
chmod +x lessons/07-bash-scripting-automation/scripts/*.sh
```

---

## 7. Мини-Лаба (Core Path)

### Цель

Закрепить безопасный workflow скриптов: syntax -> lint -> run -> verify.

### Шаги

1. Проверить синтаксис и lint.
2. Протестировать простое переименование расширений.
3. Создать backup-архив.
4. Проверить systemd/journal helper.

```bash
bash -n lessons/07-bash-scripting-automation/scripts/rename-ext.sh
shellcheck lessons/07-bash-scripting-automation/scripts/rename-ext.sh

mkdir -p /tmp/lab7 && : > /tmp/lab7/a.txt && : > /tmp/lab7/b.txt
./lessons/07-bash-scripting-automation/scripts/rename-ext.sh txt md /tmp/lab7
ls -1 /tmp/lab7

./lessons/07-bash-scripting-automation/scripts/backup-dir.sh /tmp/lab7 --keep 3
ls -1t "$HOME"/backups/lab7_* | head -n 3

./lessons/07-bash-scripting-automation/scripts/devops-tail.sh cron --since "15 min ago" || true
```

Checklist:

- скрипт проходит syntax/lint
- rename отрабатывает корректно
- backup создается
- helper показывает статус и логи

---

## 8. Расширенная Лаба (Optional + Advanced)

### 8.1 Recursive rename с dry-run/verbose

```bash
mkdir -p "/tmp/lab7 deep/path one"
: > "/tmp/lab7 deep/path one/file one.txt"
: > "/tmp/lab7 deep/path one/file two.txt"

./lessons/07-bash-scripting-automation/scripts/rename-ext.v2.sh -nv txt md "/tmp/lab7 deep"
./lessons/07-bash-scripting-automation/scripts/rename-ext.v2.sh -v txt md "/tmp/lab7 deep"
```

### 8.2 Backup lock и retention

```bash
./lessons/07-bash-scripting-automation/scripts/backup-dir.v2.sh /tmp/lab7 --keep 2
./lessons/07-bash-scripting-automation/scripts/backup-dir.v2.sh /tmp/lab7 --keep 2 --exclude 'lab7/*.md'
ls -1t "$HOME"/backups/lab7_* | head -n 5
```

### 8.3 Гибкий journal helper

```bash
./lessons/07-bash-scripting-automation/scripts/devops-tail.v2.sh cron -s "1 hour ago" -n 100 || true
./lessons/07-bash-scripting-automation/scripts/devops-tail.v2.sh cron -f || true
```

Follow-режим останавливается через `Ctrl+C`.

### 8.4 Self-check

- запусти каждый скрипт с некорректными аргументами и проверь качество ошибок/usage
- прогони скрипты на путях с пробелами
- убедись, что потенциально опасные действия имеют preview-режим

---

## 9. Очистка

```bash
rm -rf /tmp/lab7 "/tmp/lab7 deep"
```

---

## 10. Итоги Урока

- **Что изучил:** безопасный baseline Bash, парсинг аргументов и надежные паттерны файловой/логовой автоматизации.
- **Что практиковал:** syntax/lint workflow, rename, backup rotation, journal helper.
- **Продвинутые навыки:** locking, syslog trail, массивы команд, безопасная retention-логика.
- **Операционный фокус:** избегать тихих ошибок, давать preview перед рисковыми действиями, делать скрипты наблюдаемыми.
- **Артефакты в репозитории:** `lessons/07-bash-scripting-automation/scripts/`.
