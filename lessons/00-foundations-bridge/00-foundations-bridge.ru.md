# 00 Foundations Bridge (После Уроков 1-4)

**Цель:** Закрыть практические пробелы перед более глубокими Linux-уроками.

Этот файл не заменяет уроки 1-4.  
Это компактное дополнение с темами, которые часто предполагаются “по умолчанию”.

---

## 1. I/O Основы: stdin, stdout, stderr, редиректы, пайпы

### Что это

- `stdout` (fd `1`) - обычный вывод
- `stderr` (fd `2`) - вывод ошибок
- `stdin` (fd `0`) - входной поток

### Зачем это

Без редиректов и пайпов админская работа и скрипты становятся медленными и ручными.

### Минимум команд

```bash
echo "ok" > out.txt
echo "one more" >> out.txt
ls /not-exists 2> err.txt
ls /not-exists > all.txt 2>&1
cat out.txt | wc -l
```

### Мини-практика

```bash
mkdir -p ~/bridge/io && cd ~/bridge/io
echo "line1" > app.log
echo "line2" >> app.log
ls /tmp /nope > scan.txt 2> scan.err
cat scan.txt scan.err > scan.all
wc -l scan.all
```

---

## 2. Поиск + фильтрация: `find` и `grep`

### Что это

- `find` ищет файлы и директории
- `grep` ищет текст по шаблону

### Зачем это

Это стандартная связка для поиска файлов и разбора логов/конфигов.

### Минимум команд

```bash
find ~/bridge -type f -name "*.log"
grep -n "line2" ~/bridge/io/app.log
grep -R --line-number "PermitRootLogin" /etc/ssh 2>/dev/null
```

### Мини-практика

```bash
mkdir -p ~/bridge/search && cd ~/bridge/search
printf "alpha\nbeta\nerror: timeout\n" > app.log
printf "ok\nerror: denied\n" > worker.log
find . -type f -name "*.log"
grep -n "error" ./*.log
```

---

## 3. Ссылки: symlink vs hardlink

### Что это

- hardlink: еще одно имя для того же inode
- symlink: специальный файл-указатель на путь

### Зачем это

Ссылки активно используются в деплоях, versioned-конфигах и организации ФС.

### Минимум команд

```bash
echo "v1" > file.txt
ln file.txt file.hard
ln -s file.txt file.sym
ls -li file.txt file.hard file.sym
```

### Мини-практика

```bash
mkdir -p ~/bridge/links && cd ~/bridge/links
echo "hello" > original.txt
ln original.txt original.hard
ln -s original.txt original.sym
echo "world" >> original.hard
cat original.txt
cat original.sym
```

---

## 4. Архивы: `tar`, `gzip`

### Что это

- `tar` упаковывает файлы/директории
- `gzip` сжимает данные

### Зачем это

Бэкапы, перенос артефактов и ротация логов часто завязаны на архивах.

### Минимум команд

```bash
tar -czf backup.tgz ~/bridge/io
tar -tf backup.tgz
mkdir -p /tmp/restore && tar -xzf backup.tgz -C /tmp/restore
```

### Мини-практика

```bash
mkdir -p ~/bridge/archive/src
echo "a" > ~/bridge/archive/src/a.txt
echo "b" > ~/bridge/archive/src/b.txt
tar -czf ~/bridge/archive/src.tgz -C ~/bridge/archive src
tar -tf ~/bridge/archive/src.tgz
```

---

## 5. Environment: переменные, export, PATH, shell init

### Что это

- shell-переменные живут в текущем shell
- экспортированные переменные наследуются дочерними процессами
- `PATH` определяет, где shell ищет команды

### Зачем это

Много инструментов и скриптов “ломаются” из-за переменных окружения или неправильного `PATH`.

### Минимум команд

```bash
MY_VAR="demo"
echo "$MY_VAR"
export APP_ENV=dev
env | grep "^APP_ENV="
echo "$PATH"
```

### Мини-практика

```bash
mkdir -p ~/bridge/env/bin
cat > ~/bridge/env/bin/hello-env <<'EOF'
#!/usr/bin/env bash
echo "APP_ENV=${APP_ENV:-unset}"
EOF
chmod +x ~/bridge/env/bin/hello-env
export PATH="$HOME/bridge/env/bin:$PATH"
export APP_ENV=lab
hello-env
```

---

## 6. Диск: `df`, `du`, `lsblk`

### Что это

- `df -h` - свободное/занятое место на ФС
- `du -sh` - размер директории
- `lsblk` - блочные устройства и разделы

### Зачем это

Проблемы с диском - одна из самых частых production-причин инцидентов.

### Минимум команд

```bash
df -h
du -sh ~/bridge
lsblk
```

### Мини-практика

```bash
mkdir -p ~/bridge/space
dd if=/dev/zero of=~/bridge/space/blob.bin bs=1M count=20 status=none
du -sh ~/bridge/space
df -h ~
```
