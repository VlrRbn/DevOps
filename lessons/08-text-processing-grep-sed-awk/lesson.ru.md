# lesson_08

# Обработка Текста для Ops: `grep`, `sed`, `awk`

**Date:** 2025-08-30  
**Topic:** Фильтрация и разбор логов, безопасные правки конфигов, мини-отчеты и переиспользуемые пайплайны.  
**Daily goal:** Не просто повторять команды, а понимать, почему именно эта команда, этот флаг и этот порядок шагов.
**Bridge:** [08-11 Networking + Text Bridge](../00-foundations-bridge/08-11-networking-text-bridge.ru.md) — расширенные пояснения и troubleshooting для уроков 8-11.

---

## 1. Базовые Концепции

### 1.1 Pipeline-модель: что реально происходит

Пайплайн `A | B | C` — это не "одна команда", а три независимых шага:

1. `A` генерирует поток строк в `stdout`.
2. `B` получает эти строки из `stdin`, отбирает нужные.
3. `C` получает уже отфильтрованные строки и делает агрегат/отчет.

Пример мышления:

- `journalctl -u ssh -o cat` -> источник
- `grep -E 'Failed password|Accepted'` -> фильтр
- `awk '{...}'` -> разбор структуры

Если пайплайн не работает, диагностируй по частям: сначала `A`, потом `A|B`, потом весь `A|B|C`.

### 1.2 `grep`: где заканчивается "поиск" и начинается "регулярка"

`grep` отвечает на вопрос: "Какие строки подходят под паттерн?".

- `-E`: включить extended regex (почти всегда удобнее)
- `-n`: добавить номер строки
- `-i`: без учета регистра
- `-v`: показать строки, которые НЕ совпали
- `-r`: идти рекурсивно по директории

Практический шаблон:

```bash
grep -nE "pattern1|pattern2" file.log
```

Когда это удобно:

- в triage сначала берешь широкую выборку,
- потом сужаешь паттерн, убирая шум.

### 1.3 `sed`: безопасное редактирование без риска

`sed` лучше использовать в двух режимах:

1. **просмотр** (`sed -n '1,80p' file`) — понять контекст,
2. **правка с backup** (`sed -ri.bak 's/.../.../' file`) — иметь быстрый откат.

Критично: в учебных шагах правим копию конфига, не `/etc` напрямую.

### 1.4 `awk`: когда нужен, а когда нет

`awk` нужен, если надо:

- брать конкретные поля (`$1`, `$7`, `$9`),
- считать группы (`codes[$9]++`),
- печатать итог в `END`.

`awk` не нужен, если задача просто "найти строки" — для этого лучше `grep`.

### 1.5 Источники логов: файл vs journal

- `auth.log` удобен как "файл на диске", включая ротации.
- `journalctl` удобен, когда хочешь фильтровать по unit/tag и времени.

Обычно на практике полезно уметь оба пути.

### 1.6 Важный exit-code момент (`grep`)

`grep` коды:

- `0`: совпадение найдено
- `1`: совпадений нет (это не всегда ошибка бизнеса)
- `2+`: ошибка запуска/чтения

Из-за этого в некоторых ops-скриптах встречается `|| true` после `grep` — чтобы ожидаемое "ничего не найдено" не валило весь скрипт.

### 1.7 Мини-шпаргалка regex для урока

- `A|B` -> либо `A`, либо `B`
- `^...` -> начало строки
- `...$` -> конец строки
- `\s+` -> один или больше пробельных символов
- `#?` -> символ `#` может быть, а может не быть

Пример из урока:

```bash
'^#?PasswordAuthentication\s+.+'
```

Читается как: строка начинается с опционального `#`, дальше `PasswordAuthentication`, дальше пробелы и значение.

---

## 2. Приоритет Команд (Что Учить Сначала)

### Core

- `grep -nE "..." <file>`
- `journalctl -u <unit> -o cat | grep -E ...`
- `sed -n 'start,endp' <file>`
- `sed -ri.bak 's/old/new/' <copy>`
- `awk '{print ...}' <file>`
- `awk`-счетчики с `END`

### Optional

- `zgrep` по ротациям
- `grep -rEn --include='*.log'`
- `sort | uniq -c | sort -nr`
- `tee` для одновременного просмотра/сохранения

### Advanced

- унифицированные helper-скрипты (`log-grep.v2.sh`, `log-ssh-fail-report.v2.sh`)
- точечная фильтрация шума
- стабильные повторяемые отчеты

---

## 3. Core Команды с разбором: Что / Зачем / Когда

### 3.1 SSH triage через `grep`

- **Что:** поиск строк с SSH auth-событиями в `auth.log`.
- **Зачем:** быстро увидеть неуспешные и успешные входы.
- **Когда:** первичная проверка проблем с доступом и базовый audit входов.

```bash
sudo grep -nE "Failed password|Accepted password" /var/log/auth.log | head -n 20
```

Разбор:

- `sudo` — файл часто недоступен обычному пользователю;
- `-nE` — номера строк + regex;
- `"Failed password|Accepted password"` — сразу два типа событий;
- `| head` — ограничиваем объем вывода.

### 3.2 То же через journal

- **Что:** тот же triage, но по `journalctl`, а не файловому логу.
- **Зачем:** работать в systemd-потоке и не зависеть от формата файловых логов.
- **Когда:** на хостах, где journal — основной источник событий.

```bash
journalctl -u ssh --since "today" -o cat | grep -nE "Failed password|Accepted|Invalid user" | head -n 20
```

Разбор:

- `-u ssh` — только unit SSH;
- `--since "today"` — ограничение по времени;
- `-o cat` — только сообщение (без лишнего форматирования);
- дальше `grep` и `head` как во file-flow.

### 3.3 Безопасный просмотр перед правкой

- **Что:** чтение фрагмента файла без изменений.
- **Зачем:** проверить контекст перед редактированием.
- **Когда:** всегда перед `sed -i` / `sed -ri.bak`.

```bash
sed -n '1,80p' labs/mock/sshd_config
```

### 3.4 Контролируемая правка ключа

- **Что:** in-place замена параметра `PasswordAuthentication` с backup-файлом.
- **Зачем:** перевести ключ в целевое состояние одной регуляркой и иметь быстрый откат.
- **Когда:** тестовые правки копии конфига и повторяемые конфиг-изменения.

```bash
sed -ri.bak 's/^#?PasswordAuthentication\s+.*/PasswordAuthentication no/' labs/mock/sshd_config
```

Разбор regex:

- `^` — начало строки,
- `#?` — опциональный комментарий,
- `PasswordAuthentication` — имя ключа,
- `\s+` — пробел(ы),
- `.*` — текущее значение,
- замена на целевую строку.

Почему так удобно:

- ловит и закомментированную, и незакомментированную форму,
- делает одно понятное целевое состояние,
- оставляет backup (`.bak`).

### 3.5 Проверка результата и откат

- **Что:** проверка измененной строки и diff до/после.
- **Зачем:** убедиться, что поменялось только ожидаемое место.
- **Когда:** сразу после любой автоматизированной правки.

```bash
grep -nE '^#?PasswordAuthentication' labs/mock/sshd_config
diff -u labs/mock/sshd_config{.bak,} | sed -n '1,40p'
```

### 3.6 `awk`-отчет по nginx access

- **Что:** агрегация по status/path/ip из access-лога.
- **Зачем:** получить мини-отчет (тотал, статусы, уникальные IP) без внешних инструментов.
- **Когда:** smoke-check сервиса, быстрый triage, проверка после изменений.

```bash
awk '{status=$9; path=$7; ip=$1; total++; codes[status]++; hits[path]++; ips[ip]++}
END {
  printf "Total: %d\n", total;
  for (c in codes) printf "code %s: %d\n", c, codes[c];
  printf "Unique IPs: %d\n", length(ips);
}' labs/logs/sample/nginx_access.log
```

Откуда `$1/$7/$9`:

- в типичном nginx combined log:
- `$1` = IP,
- `$7` = path (часть запроса),
- `$9` = HTTP status.

Что делает логика:

- `total++` — общее число строк,
- `codes[status]++` — счетчик статусов,
- `hits[path]++` — популярность путей,
- `ips[ip]++` — множество IP (через ключи массива).

---

## 4. Optional: команды с объяснением

### 4.1 `zgrep -hE "Failed password" /var/log/auth.log*`

- **Что:** поиск по `auth.log`, включая ротации и `.gz`.
- **Зачем:** не потерять старые события, когда текущий `auth.log` уже маленький.
- **Когда:** расследуешь попытки входа за период больше одного дня.

```bash
sudo zgrep -hE "Failed password|Invalid user" /var/log/auth.log* | tail -n 30
```

### 4.2 `grep -rEn --include='*.log' ... <dir>`

- **Что:** рекурсивный поиск по директории только в нужных типах файлов.
- **Зачем:** не сканировать всё подряд и уменьшить шум.
- **Когда:** анализируешь каталог с разными файлами, но интересуют только логи.

```bash
grep -rEn --include='*.log' "error|fail|critical" ./labs
```

### 4.3 `sort | uniq -c | sort -nr`

- **Что:** частотный подсчет значений.
- **Зачем:** быстро получить \"топ\" без отдельного языка/БД.
- **Когда:** нужно понять, какой IP/путь/статус встречается чаще всего.

```bash
journalctl -u ssh --since "today" -o cat |
grep -E "Failed password" |
awk '{for(i=1;i<=NF;i++) if($i=="from"){print $(i+1); break}}' |
sort | uniq -c | sort -nr | head -n 10
```

### 4.4 `awk -F` и `printf`

- **Что:** явный разделитель полей и управляемый вывод.
- **Зачем:** сделать отчет стабильно читаемым.
- **Когда:** нужно сравнивать вывод между запусками или вставлять в заметки/отчеты.

```bash
awk -F' ' '{printf "ip=%-15s status=%-3s path=%s\n", $1, $9, $7}' \
  labs/sample/nginx_access.log
```

### 4.5 `tee` для сохранения промежуточного результата

- **Что:** дублирует поток в терминал и файл.
- **Зачем:** не потерять результат triage.
- **Когда:** делаешь расследование и хочешь оставить артефакт.

```bash
journalctl -u ssh --since "today" -o cat |
grep -E "Failed password|Accepted|Invalid user" |
tee /tmp/ssh_events_today.txt
```

---

## 5. Advanced: не просто команды, а рабочие инструменты

### 5.1 Почему выносить в скрипты

- ad-hoc команда легко ломается при повторе;
- флаги забываются;
- сложно передать другому человеку.

Скрипт фиксирует интерфейс и ожидаемый результат.

### 5.2 `log-ssh-fail-report.v2.sh`

- **Что:** отчет по IP с SSH-fail событиями.
- **Зачем:** получить топ источников за выбранный период.
- **Когда:** brute-force triage, базовый security review.

Ключевые флаги:

- `--source journal|auth` источник;
- `--since "today"` окно времени (для journal);
- `--top N` лимит;
- `--all` включить ротации auth.log.

```bash
./lessons/08-text-processing-grep-sed-awk/scripts/log-ssh-fail-report.v2.sh --source auth --all --top 20
```

### 5.3 `log-grep.v2.sh`

- **Что:** единый grep-интерфейс для file/dir/journal.
- **Зачем:** не переключаться между разными синтаксисами вручную.
- **Когда:** регулярный triage разных источников.

Ключевые флаги:

- `--unit` фильтр по unit в journal;
- `--tag` фильтр по тегу;
- `--sshd-only` убрать лишние строки.

```bash
./lessons/08-text-processing-grep-sed-awk/scripts/log-grep.v2.sh \
  "Failed password|Invalid user" journal --tag sshd --sshd-only
```

### 5.4 `log-nginx-report.sh`

- **Что:** мини-аналитика nginx access (total/error-rate/codes/top paths/unique IPs).
- **Зачем:** получить быстрый health-снимок.
- **Когда:** после деплоя, во время smoke-check, в кратком инциденте.

```bash
./lessons/08-text-processing-grep-sed-awk/scripts/log-nginx-report.sh \
  lessons/08-text-processing-grep-sed-awk/labs/sample/nginx_access.log
```

### 5.5 Практический advanced workflow

1. Собери выборку (`journalctl` или `auth.log*`).
2. Сузь шум через `grep`.
3. Агрегируй через `awk`/`sort|uniq`.
4. Сохрани вывод в файл (`tee`).
5. Если команда повторяется, вынеси в `scripts/`.

---

## 6. Частые ошибки (и быстрые фиксы)

1. Ошибка: "ничего не вывелось — значит команда сломана".  
Факт: возможно просто нет совпадений (`grep` вернул `1`).

2. Ошибка: сразу `sed -i` по рабочему конфигу.  
Фикс: сначала копия + `.bak`.

3. Ошибка: слишком общий regex (`error|fail`) и много шума.  
Фикс: начать широко, потом сужать паттерн по источнику и контексту.

4. Ошибка: запускать длинный пайплайн целиком без промежуточной проверки.  
Фикс: проверять этапы отдельно (`A`, `A|B`, `A|B|C`).

---

## 7. Скрипты Урока

- `lessons/08-text-processing-grep-sed-awk/scripts/`
- `lessons/08-text-processing-grep-sed-awk/scripts/README.md`

Подготовка:

```bash
chmod +x lessons/08-text-processing-grep-sed-awk/scripts/*.sh
```

---

## 8. Разбор скриптов (что именно мы написали)

### 8.1 `log-ssh-fail-report.sh`

- **Что:** простой отчет по IP-адресам из SSH fail-событий.
- **Зачем:** быстро получить топ источников неудачных входов.
- **Когда:** нужен быстрый triage без множества флагов.

Как читать логику:

1. `src="${1:-journal}"` — по умолчанию берем journal.
2. Если `auth` и есть `/var/log/auth.log`, читаем `auth.log*` через `zgrep`.
3. Иначе читаем journal (`-t sshd`) и фильтруем нужные строки.
4. `awk` вытаскивает token после слова `from` (IP).
5. `sort | uniq -c | sort -nr | head` — строит топ.

### 8.2 `log-ssh-fail-report.v2.sh`

- **Что:** расширенная версия отчета (`--source`, `--since`, `--top`, `--all`).
- **Зачем:** управлять источником, периодом и объемом вывода.
- **Когда:** рабочий вариант для повторяемого расследования.

Ключевая логика:

- блок `while/case` разбирает флаги;
- `--source auth` переключает на файловые логи;
- `--all` включает ротации;
- `awk` извлекает и IPv4, и IPv6;
- финальный pipeline считает частоту и сортирует по убыванию.

### 8.3 `log-grep.sh`

- **Что:** базовый helper для grep по файлу или директории.
- **Зачем:** один интерфейс вместо ручного выбора `grep -E` и `grep -rEn`.
- **Когда:** быстрый ручной поиск в лабе.

Логика:

- проверка аргументов (`<pattern> <file_or_dir>`);
- если цель — директория, включается рекурсивный режим;
- если цель — файл, обычный режим с номерами строк;
- `--` защищает от проблем с путями, начинающимися с `-`.

### 8.4 `log-grep.v2.sh`

- **Что:** расширенный helper для `file|dir|journal`.
- **Зачем:** одинаковый UX для разных источников логов.
- **Когда:** регулярный ops-triage, где часть данных в файлах, часть в journal.

Ключевая логика:

- режим `journal` строит команду `journalctl` динамически через массив `cmd=(...)`;
- опции `--unit` и `--tag` добавляются только если заданы;
- `--sshd-only` делает post-filter для строк `sshd[`;
- `--` позволяет передать дополнительные опции напрямую в `grep`.

### 8.5 `log-nginx-report.sh`

- **Что:** мини-отчет по access log (total, error rate, status codes, top paths, unique IPs).
- **Зачем:** быстро оценить состояние трафика без внешней аналитики.
- **Когда:** smoke-check после деплоя, быстрый разбор инцидента.

Как читать awk-блок:

1. `match(...)` вытаскивает метод и путь из `"GET /path HTTP/1.1"`.
2. Поля `$9`, `$7`, `$1` дают статус, path и IP.
3. Счетчики в массивах накапливают агрегаты.
4. `END` печатает финальный summary, включая `4xx/5xx` error rate.

---

## 9. Мини-Лаба (Core Path)

```bash
mkdir -p labs/mock labs/logs/sample
cp /etc/ssh/sshd_config labs/mock/sshd_config 2>/dev/null || true

sudo grep -nE "Failed password|Accepted password" /var/log/auth.log | tail -n 20 || true
journalctl -u ssh --since "today" -o cat | grep -nE "Failed password|Accepted|Invalid user" | tail -n 20 || true

sed -ri.bak 's/^#?PasswordAuthentication\s+.*/PasswordAuthentication no/' labs/mock/sshd_config
grep -nE '^#?PasswordAuthentication' labs/mock/sshd_config
diff -u labs/mock/sshd_config{.bak,} | sed -n '1,40p'

./lessons/08-text-processing-grep-sed-awk/scripts/log-nginx-report.sh
```

Проверка понимания:

- можешь объяснить каждый символ в sed-regex;
- можешь объяснить, почему в awk именно `$1/$7/$9`;
- можешь объяснить, где file-flow лучше journal-flow и наоборот.

---

## 10. Расширенная Лаба (Advanced)

```bash
./lessons/08-text-processing-grep-sed-awk/scripts/log-ssh-fail-report.v2.sh --source journal --since "today" --top 10
./lessons/08-text-processing-grep-sed-awk/scripts/log-ssh-fail-report.v2.sh --source auth --all --top 10

./lessons/08-text-processing-grep-sed-awk/scripts/log-grep.v2.sh "Failed password|Invalid user" journal --tag sshd
./lessons/08-text-processing-grep-sed-awk/scripts/log-grep.v2.sh "Accepted" journal --unit ssh.service

./lessons/08-text-processing-grep-sed-awk/scripts/log-nginx-report.sh | tee /tmp/nginx_report.txt
```

---

## 11. Итоги Урока

- **Что изучил:** практику text-processing в Linux через `grep`, `sed`, `awk` и безопасные пайплайны для логов.
- **Что практиковал:** фильтрацию SSH-событий, редактирование конфигов через `.bak`, построение мини-отчетов по Nginx и упаковку команд в скрипты.
- **Продвинутые навыки:** разбор источников `file vs journal`, управление шумом в regex, агрегация данных через `awk + sort + uniq`.
- **Операционный фокус:** работать от безопасного потока `read -> filter -> aggregate -> save`, проверять изменения через `diff`, не делать слепых `sed -i` в боевых файлах.
- **Артефакты в репозитории:** `lessons/08-text-processing-grep-sed-awk/scripts/`, `lessons/08-text-processing-grep-sed-awk/scripts/README.md`.
