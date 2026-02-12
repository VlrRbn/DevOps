# 05-07 Operations Bridge (После Уроков 5-7)

**Цель:** Закрыть практические пробелы перед уроками по text-processing и более глубокой автоматизацией.

Этот файл не заменяет уроки 5-7.  
Это компактное дополнение с темами, которые часто подразумеваются в следующих шагах.

---

## 1. Контекст запуска скрипта: Shebang, PATH, `./`

### Что это

- Shebang (`#!/usr/bin/env bash`) выбирает интерпретатор.
- execute-bit (`chmod +x`) разрешает прямой запуск.
- `script.sh` и `./script.sh` не всегда эквивалентны.

### Зачем это

Многие ошибки "No such file" / "command not found" связаны с контекстом запуска, а не с логикой скрипта.

### Минимум команд

```bash
chmod +x ./my-script.sh
./my-script.sh

echo "$PATH"
command -v bash
```

### Мини-практика

```bash
mkdir -p ~/bridge57/bin
cat > ~/bridge57/bin/hello <<'EOF'
#!/usr/bin/env bash
echo "hello from script"
EOF
chmod +x ~/bridge57/bin/hello

# запуск по относительному пути
~/bridge57/bin/hello

# добавили в PATH и запускаем по имени
export PATH="$HOME/bridge57/bin:$PATH"
hello
```

---

## 2. Коды возврата и поток выполнения (`&&`, `||`, `set -e`)

### Что это

- `0` = успех, не-ноль = ошибка.
- `cmd1 && cmd2` запускает `cmd2`, только если `cmd1` успешна.
- `cmd1 || cmd2` запускает `cmd2`, только если `cmd1` упала.

### Зачем это

Скрипты из уроков 5-7 опираются на понятный flow успех/ошибка.

### Минимум команд

```bash
true; echo $?
false; echo $?

mkdir -p /tmp/demo && echo "ok"
ls /not-here || echo "fallback"
```

### Мини-практика

```bash
file=/tmp/bridge57.txt
[[ -f "$file" ]] || echo "missing"

touch "$file"
[[ -f "$file" ]] && echo "exists"
```

---

## 3. Quoting, word splitting и массивы

### Что это

- переменная без кавычек может неожиданно разбиться на слова
- переменная в кавычках сохраняет точное значение
- массивы безопасны для динамической сборки команд

### Зачем это

Пути с пробелами и опциональные аргументы - стандартный кейс в ops-скриптах.

### Минимум команд

```bash
name="a_b.txt"
printf '%s\n' "$name"

cmd=(echo "file:$name")
"${cmd[@]}"
```

Как читать этот фрагмент:

- `printf` печатает текст по шаблону (format string).
- `%s` означает: подставить строку (string).
- `\n` означает: перевод строки (newline).
- `printf '%s\n' "$name"` = вывести значение `name` и перейти на новую строку.
- `cmd=(...)` создает массив команды (отдельные элементы, а не одна длинная строка).
- `"${cmd[@]}"` запускает массив как команду безопасно, сохраняя пробелы в аргументах.

### Мини-практика

```bash
dir="/tmp/bridge_57"
mkdir -p "$dir"
: > "$dir/file_one.txt"

for f in "$dir"/*.txt; do
  printf 'found: %s\n' "$f"
done
```

---

## 4. Безопасный обход файлов: `find -print0`, `read -d ''`, `xargs -0`

### Что это

- NUL-разделители делают поток файлов устойчивым к спецсимволам в именах
- `find ... -print0` работает в паре с `read -d ''` или `xargs -0`

### Зачем это

Это защищает от опасных багов в bulk rename/backup/cleanup.

### Минимум команд

```bash
find /tmp -maxdepth 1 -type f -name "*.log" -print0 |
  xargs -0 -r ls -l
```

### Мини-практика

```bash
mkdir -p "/tmp/bridge57_files"
: > "/tmp/bridge57_files/a_one.log"
: > "/tmp/bridge57_files/b_two.log"

find "/tmp/bridge57_files" -type f -name "*.log" -print0 |
  while IFS= read -r -d '' f; do
    printf '%s\n' "$f"
  done
```

---

## 5. Базовое чтение systemd/journald для автоматизации

### Что это

- `systemctl status` дает снимок состояния unit
- `journalctl -u <unit>` дает историю логов unit
- приоритеты `0..7` (`0=emerg`, `3=err`, `4=warning`, `6=info`)

### Зачем это

Автоматизированная диагностика становится быстрее, когда фильтры логов применяются осознанно.

### Минимум команд

```bash
systemctl status cron --no-pager | sed -n '1,12p'
journalctl -u cron --since "30 min ago" -n 50 --no-pager
journalctl -u cron -p warning --since "1 hour ago" --no-pager
```

### Мини-практика

```bash
unit=cron
systemctl is-active "$unit"
journalctl -u "$unit" -n 20 --no-pager | tail -n 5
```

---

## 6. Безопасный пакетный workflow (сначала simulation)

### Что это

- `apt update` обновляет индекс
- `apt-get -s upgrade` симулирует обычный апгрейд
- `apt-get -s full-upgrade` симулирует апгрейд с возможным add/remove пакетов

### Зачем это

Пакетные изменения high-impact; simulation-first снижает риск неожиданных изменений.

### Минимум команд

```bash
sudo apt update
sudo apt-get -s upgrade | sed -n '1,30p'
sudo apt-get -s full-upgrade | sed -n '1,30p'
```

### Мини-практика

```bash
apt-cache policy bash
apt-mark showhold
```

---

## 7. Безопасный restore: selections и контроль drift

### Что это

- snapshot selections позволяет контролируемое восстановление
- перед apply восстановление нужно симулировать

### Зачем это

Это уменьшает время восстановления после неудачных апдейтов и package drift.

### Минимум команд

```bash
dpkg --get-selections > packages.list
sudo dpkg --set-selections < packages.list
sudo apt-get -s dselect-upgrade | sed -n '1,30p'
```

### Мини-практика

```bash
mkdir -p ~/bridge57/state
dpkg --get-selections > ~/bridge57/state/packages.list
wc -l ~/bridge57/state/packages.list
```
