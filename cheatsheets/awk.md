# awk

# Базовая форма

```bash
awk 'pattern { action }' file
```

- Если `pattern` не указан → правило срабатывает на каждую строку.
- Если `action` не указан → по умолчанию `print $0` (печать строки).

# Поля и записи

- `$0` — вся строка
- `$1, $2, ...` — поля (разделяются `FS`, по умолчанию — любое кол-во пробелов/табов)
- `$NF` — последнее поле, `$(NF-1)` — предпоследнее
- `NR` — номер текущей строки (глобально), `FNR` — номер строки в текущем файле
- `NF` — количество полей в строке

Полезные опции запуска:

```bash
awk -F: '...' file         # задать разделитель входных полей
awk -v var=42 '...'        # передать переменную в скрипт
awk -f script.awk file     # вынести правила в файл
```

# Жизненный цикл

```bash
BEGIN { FS="\t"; OFS="," }     # до чтения строк (настройки)
{ ... }                        # для каждой строки
END   { ... }                  # после всех строк (итоги)
```

- `FS` — входной разделитель полей (regex)
- `OFS` — разделитель полей при `print`
- `RS` / `ORS` — разделители записей (вход/выход)

# Сопоставление/фильтрация

```bash
awk '/ERROR/' file                    # строки, где regex совпал
awk '$3 > 100' file                   # по условию на поле
awk 'NR==1' file                      # только первая строка
awk 'NR>1' file                       # пропустить заголовок
awk '/start/,/stop/' file             # диапазон строк от шаблона до шаблона
awk '!/DEBUG/' file                   # инверсия
```

# Печать и форматирование

```bash
awk '{ print $1, $3 }' file                     # печать полей через OFS
awk '{ printf "%-10s %8.2f\n", $1, $2 }' file
```

# Строки и регекспы (встроенные функции)

```bash
{ sub(/foo/,"bar",$1) }                           # заменить первое вхождение в $1
{ gsub(/foo/,"bar") }                             # заменить все вхождения в $0
{ n=split($0, a, ":") }                           # разбить строку в массив a
{ if (match($0,/id=([0-9]+)/,m)) print m[1] }     # захват группы
{ print length($0), tolower($1), toupper($2), substr($3,2,5) }
```

# Математика и логика

```bash
{ sum += $2 } END { print sum }
{ count[$1]++ } END { for (k in count) print k, count[k] }     # частоты
{ max = (NR==1||$2>max)?$2:max } END { print max }
```

# Ассоциативные массивы

```bash
# Группировка и агрегации
awk -F, '{ sum[$1]+=$3; cnt[$1]++ } END { for (k in sum) print k, sum[k], sum[k]/cnt[k] }' data.csv
```

Сортировка результатов (GNU awk):

```bash
awk '{ cnt[$1]++ } END { for (k in cnt) print cnt[k], k }' file | sort -nr

# или прямо в gawk:
gawk 'END{ n=asorti(cnt, idx); for(i=1;i<=n;i++) print idx[i], cnt[idx[i]] }'
```

# Частые однострочники

Фильтр по условию:

```bash
awk -F'\t' '$3=="OK"{ print $1,$5 }' OFS='\t' file
```

Удалить дубли (по всей строке):

```bash
awk '!seen[$0]++' file
```

Топ-N по частоте в первом поле:

```bash
awk '{ c[$1]++ } END{ for(k in c) print c[k],k }' file | sort -nr | head
```

Сумма/среднее/мин/макс по столбцу 2:

```bash
awk '{ s+=$2; if (NR==1||$2<min) min=$2; if ($2>max) max=$2 } END{ print "sum",s,"avg",s/NR,"min",min,"max",max }' file
```

Фильтр по диапазону дат (простые строки YYYY-MM-DD):

```bash
awk '$1>="2025-10-01" && $1<="2025-10-20"' log.txt
```

Слияние как `JOIN` (левое объединение по ключу 1-го поля, GNU awk):

```bash
# index.csv: key, val
# data.csv:  key, other
gawk -F, 'FNR==NR{ map[$1]=$2; next } { print $0, ( $1 in map ? map[$1] : "" ) }' OFS=, index.csv data.csv
# gawk -F, 'FNR==NR{m[$1]=$2; next} {print $0, m[$1]}' OFS=, index.csv data.csv
```

Выбор строк по множеству ключей:

```bash
awk 'FNR==NR{ ok[$1]; next } ($1 in ok)' keys.txt data.txt
```

Нумерация строк/переупаковка:

```bash
nl -ba file | awk '{print $1 ":" $2}'     # или чисто awk:
awk '{print NR ":" $0}' file
```

CSV “по-быстрому” (без кавычек/эскейпов):

```bash
awk -F, '{ print $2 }' data.csv
```

CSV с кавычками (трюк с FPAT для gawk):

```bash
gawk -v FPAT='([^,]+)|(\"([^\"]|\"\")*\")' '{ print $2 }' data.csv
```

# Переменные окружения и время (gawk)

```bash
gawk 'BEGIN{ print ENVIRON["HOME"]; print strftime("%F %T", systime()) }'
```

# Производительность и аккуратность

- `LC_ALL=C` ускоряет сортировки/сравнения: `LC_ALL=C awk '...' file`
- Явно задавать `FS` и `OFS`, чтобы убрать сюрпризы с пробелами.
- Для больших файлов избегать `print` в каждой итерации без нужды — агрегируй и печатай в `END`.
- Регулярки быстрее/яснее, чем куча `index()`/`substr()`.

# Мини-рецепты логов

HTTP логи (NCSA):

```bash
# ТОП-10 IP
awk '{ ip[$1]++ } END{ for(i in ip) print ip[i],i }' access.log | sort -nr | head

# Ошибки 5xx
awk '$9 ~ /^5/ { print }' access.log

# Средний размер ответа по коду
awk '{ bytes[$9]+=$10; cnt[$9]++ } END{ for(c in bytes) printf "%s %.1f\n", c, bytes[c]/cnt[c] }' access.log
```

# Мини-отладка/печать

```bash
{ print "DBG>", NR, $0 > "/dev/stderr" }     # печать в stderr
{ if ($2=="") { next } }                     # пропустить пустые значения
{ if (!($1 ~ /^[0-9]+$/)) { next } }         # валидировать вход
```