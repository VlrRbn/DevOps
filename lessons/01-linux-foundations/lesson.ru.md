# lesson_01

# Основы Linux: Окружение, Команды, FHS и Права

**Date:** 2025-08-19  
**Topic:** Подготовка окружения  
**Daily goal:** Подготовить окружение для изучения Linux и отработать базовые операции с файлами.
**Bridge:** [01-05 Foundations Bridge](../00-foundations-bridge/01-05-foundations-bridge.ru.md) — компенсация недостающих базовых тем после уроков 1-4.

---

## 1. Изученный Материал

### `pwd`

Показывает текущую рабочую директорию (`print working directory`).

```bash
leprecha@Ubuntu-DevOps:~$ pwd
/home/leprecha
```

---

### `ls -la`

Показывает список файлов в длинном формате (`-l`) и включает скрытые элементы (`-a`).

```bash
leprecha@Ubuntu-DevOps:~$ ls -la
drwxr-x--- 18 leprecha sysadmin 4096 Aug 19 16:32 .
drwxr-xr-x  3 root     root     4096 Aug 19 15:19 ..
-rw-------  1 leprecha sysadmin 2791 Aug 19 15:54 .bash_history
drwxr-xr-x  2 leprecha sysadmin 4096 Aug 19 15:19 Desktop
```

Как читать одну строку:

1. `-rw-------` - права доступа (`d` означает директорию, `-` обычный файл).
2. `1` - количество hard links.
3. `leprecha` - владелец.
4. `sysadmin` - группа.
5. `2791` - размер в байтах.
6. `Aug 19 15:54` - время последнего изменения.
7. `.bash_history` - имя файла.

---

### `cd /etc`

Меняет текущую директорию.

```bash
leprecha@Ubuntu-DevOps:~$ cd /etc
leprecha@Ubuntu-DevOps:/etc$
```

---

### `mkdir demo`

Создает директорию с именем `demo`.

- `mkdir` - создать директорию.
- `demo` - имя новой директории.

```bash
leprecha@Ubuntu-DevOps:~$ mkdir demo
leprecha@Ubuntu-DevOps:~$ ls -ld demo
drwxrwxr-x 2 leprecha sysadmin 4096 Aug 19 16:32 demo
```

---

### `touch demo/file.txt`

Создает пустой файл, если его нет, или обновляет временную метку, если файл уже существует.

```bash
leprecha@Ubuntu-DevOps:~$ touch demo/file.txt
leprecha@Ubuntu-DevOps:~$ ls -la demo
drwxrwxr-x  2 leprecha sysadmin 4096 Aug 19 16:34 .
drwxr-x--- 18 leprecha sysadmin 4096 Aug 19 16:32 ..
-rw-rw-r--  1 leprecha sysadmin    0 Aug 19 16:34 file.txt
```

---

### `cp demo/file.txt demo/file.bak`

Копирует файл.

- Первый аргумент: источник.
- Второй аргумент: место назначения.

```bash
leprecha@Ubuntu-DevOps:~$ cp demo/file.txt demo/file.bak
leprecha@Ubuntu-DevOps:~$ ls -la demo
-rw-r--r--  1 leprecha sysadmin    0 Aug 19 16:46 file.bak
-rw-rw-r--  1 leprecha sysadmin    0 Aug 19 16:34 file.txt
```

---

### `mv demo/file.bak demo/file.old`

Перемещает или переименовывает файл.

- Если меняется путь: перемещение.
- Если меняется только имя в том же пути: переименование.

```bash
leprecha@Ubuntu-DevOps:~$ mv demo/file.bak demo/file.old
leprecha@Ubuntu-DevOps:~$ ls -la demo
drwxrwxr-x  2 leprecha sysadmin 4096 Aug 19 16:54 .
drwxr-x--- 18 leprecha sysadmin 4096 Aug 19 16:32 ..
-rw-r--r--  1 leprecha sysadmin    0 Aug 19 16:46 file.old
-rw-rw-r--  1 leprecha sysadmin    0 Aug 19 16:34 file.txt
```

---

### `rm demo/file.old`

Удаляет файл.

- `rm` - удалить файл.
- `rm -r` - удалить директорию рекурсивно.
- `rm -ri` - интерактивное рекурсивное удаление (с подтверждением).

```bash
leprecha@Ubuntu-DevOps:~$ rm demo/file.old
leprecha@Ubuntu-DevOps:~$ ls -la demo
drwxrwxr-x  2 leprecha sysadmin 4096 Aug 19 16:58 .
drwxr-x--- 18 leprecha sysadmin 4096 Aug 19 16:32 ..
-rw-rw-r--  1 leprecha sysadmin    0 Aug 19 16:34 file.txt
```

---

### `man ls`

Открывает manual-страницу команды `ls`.

---

### `whoami`

Показывает текущего пользователя.

```bash
leprecha@Ubuntu-DevOps:~$ whoami
leprecha
```

---

### `hostname`

Показывает имя хоста системы.

```bash
leprecha@Ubuntu-DevOps:~$ hostname
Ubuntu-DevOps
```

---

### `date`

Показывает текущие дату и время системы.

```bash
leprecha@Ubuntu-DevOps:~$ date
Tue Aug 19 09:04:25 PM IST 2025
```

---

### `clear`

Очищает экран терминала.

---

### `uname -a`

Показывает информацию о ядре и системе.

```bash
leprecha@Ubuntu-DevOps:~$ uname -a
Linux Ubuntu-DevOps 6.14.0-28-generic #28~24.04.1-Ubuntu SMP PREEMPT_DYNAMIC Fri Jul 25 10:47:01 UTC 2025 x86_64 x86_64 x86_64 GNU/Linux
```

---

### `exit`

Закрывает текущую shell-сессию.

### Быстрый справочник по командам

| Command | Description |
| --- | --- |
| `pwd` | Показать путь текущей директории |
| `ls -la` | Показать файлы с деталями, включая скрытые |
| `cd /etc` | Перейти в директорию `/etc` |
| `mkdir demo` | Создать директорию `demo` |
| `touch demo/file.txt` | Создать пустой файл |
| `cp demo/file.txt demo/file.bak` | Скопировать файл |
| `mv demo/file.bak demo/file.old` | Переименовать или переместить файл |
| `rm demo/file.old` | Удалить файл |
| `man ls` | Открыть manual для `ls` |
| `whoami` | Показать имя текущего пользователя |
| `hostname` | Показать hostname |
| `date` | Показать дату и время |
| `clear` | Очистить терминал |
| `uname -a` | Показать информацию о системе и ядре |
| `exit` | Выйти из shell |

---

## 2. Работа с `nano` и Файловой Системой

Создай `hello.txt`, отредактируй в `nano`, сохрани и проверь содержимое.

```bash
leprecha@Ubuntu-DevOps:~$ mkdir -p ~/practice
leprecha@Ubuntu-DevOps:~$ cd ~/practice
leprecha@Ubuntu-DevOps:~/practice$ nano hello.txt
# введи: Hello world!
# сохранить: Ctrl+O, Enter
# выйти: Ctrl+X
leprecha@Ubuntu-DevOps:~/practice$ cat hello.txt
Hello world!
```

Шаги:

1. Создать директорию: `mkdir -p ~/practice`
2. Перейти в директорию: `cd ~/practice`
3. Открыть и отредактировать файл: `nano hello.txt`
4. Проверить содержимое: `cat hello.txt`

---

### Практика: копирование, переименование, удаление

Копирование:

```bash
leprecha@Ubuntu-DevOps:~/practice$ cp hello.txt hello_new.txt
leprecha@Ubuntu-DevOps:~/practice$ ls -la
drwxr-xr-x  2 leprecha sysadmin 4096 Aug 19 21:13 .
drwxr-x--- 19 leprecha sysadmin 4096 Aug 19 21:08 ..
-rw-r--r--  1 leprecha sysadmin   13 Aug 19 21:08 hello.txt
-rw-r--r--  1 leprecha sysadmin   13 Aug 19 21:13 hello_new.txt
```

Переименование:

```bash
leprecha@Ubuntu-DevOps:~/practice$ mv hello_new.txt renamed.txt
leprecha@Ubuntu-DevOps:~/practice$ ls -la
drwxr-xr-x  2 leprecha sysadmin 4096 Aug 19 21:14 .
drwxr-x--- 19 leprecha sysadmin 4096 Aug 19 21:08 ..
-rw-r--r--  1 leprecha sysadmin   13 Aug 19 21:08 hello.txt
-rw-r--r--  1 leprecha sysadmin   13 Aug 19 21:13 renamed.txt
```

Удаление:

```bash
leprecha@Ubuntu-DevOps:~/practice$ rm hello.txt
leprecha@Ubuntu-DevOps:~/practice$ ls -la
drwxr-xr-x  2 leprecha sysadmin 4096 Aug 19 21:15 .
drwxr-x--- 19 leprecha sysadmin 4096 Aug 19 21:08 ..
-rw-r--r--  1 leprecha sysadmin   13 Aug 19 21:13 renamed.txt
```

---

## 3. Базовая Структура FHS (`/etc`, `/var`, `/usr`, `/home`)

### `/etc`

Конфигурационные файлы системы и сервисов.

Примеры:

- `/etc/hosts` - локальные соответствия hostname/IP
- `/etc/passwd` - список пользовательских аккаунтов
- `/etc/ssh/sshd_config` - конфигурация SSH-сервера

### `/var`

Переменные данные, которые часто меняются.

- `/var/log` - логи
- `/var/cache` - кэш приложений
- `/var/spool` - очереди задач (почта, печать и т.д.)

### `/usr`

Установленное ПО пользовательского пространства и общие ресурсы.

- `/usr/bin` - исполняемые команды
- `/usr/lib` - библиотеки
- `/usr/share` - общие данные и документация

### `/home`

Домашние директории пользователей с личными файлами и настройками.

Пример: `/home/leprecha`

```text
/                  -> корень файловой системы
├─ etc/            -> системные и сервисные конфиги
├─ var/            -> переменные данные (логи, кэш, очереди)
├─ usr/            -> приложения, библиотеки, общие данные
├─ home/           -> домашние каталоги пользователей
├─ tmp/            -> временные файлы
├─ bin/, sbin/     -> базовые системные команды
└─ root/           -> домашний каталог root
```

Запомнить:

- `/etc` - настройки
- `/var` - часто изменяемые данные
- `/usr` - программы и общие ресурсы
- `/home` - личные данные пользователей

---

## 4. Практика

### 1. Создать структуру директорий

Задача: создать `projects` с поддиректориями `scripts`, `configs`, `logs`.

```bash
leprecha@Ubuntu-DevOps:~$ mkdir -p ~/projects/{scripts,configs,logs}
leprecha@Ubuntu-DevOps:~$ cd ~/projects
leprecha@Ubuntu-DevOps:~/projects$ ls -la
drwxr-xr-x 2 leprecha sysadmin 4096 Aug 19 21:22 configs
drwxr-xr-x 2 leprecha sysadmin 4096 Aug 19 21:22 logs
drwxr-xr-x 2 leprecha sysadmin 4096 Aug 19 21:22 scripts
```

Разбор команды:

- `mkdir` - создать директорию
- `-p` - создать недостающие родительские каталоги при необходимости
- `~` - домашняя директория (`/home/<user>`)
- `{scripts,configs,logs}` - brace expansion для создания нескольких директорий

---

### 2. Работа с файлами

Задача: создать два конфигурационных файла и записать стартовое сообщение в лог.

```bash
leprecha@Ubuntu-DevOps:~$ touch ~/projects/configs/{nginx.conf,ssh_config}
leprecha@Ubuntu-DevOps:~$ ls -la ~/projects/configs
-rw-r--r-- 1 leprecha sysadmin 0 Aug 19 21:26 nginx.conf
-rw-r--r-- 1 leprecha sysadmin 0 Aug 19 21:26 ssh_config
```

```bash
leprecha@Ubuntu-DevOps:~$ echo "Hello DevOps" > ~/projects/logs/startup.log
leprecha@Ubuntu-DevOps:~$ cat ~/projects/logs/startup.log
Hello DevOps
```

Примечания:

- `touch` - создает пустые файлы или обновляет timestamp
- `>` - перезапись файла через redirect
- `>>` - дозапись в конец файла
- `cat` - вывод содержимого файла

---

### 3. Копирование и резервная копия

Задача: создать резервную копию `startup.log`.

```bash
leprecha@Ubuntu-DevOps:~$ cp ~/projects/logs/startup.log ~/projects/logs/startup.log.bak
leprecha@Ubuntu-DevOps:~$ ls -la ~/projects/logs
-rw-r--r-- 1 leprecha sysadmin 13 Aug 19 21:28 startup.log
-rw-r--r-- 1 leprecha sysadmin 13 Aug 19 21:36 startup.log.bak
```

Полезные опции `cp`:

- `-r` - рекурсивно копировать директории
- `-i` - спрашивать подтверждение перед перезаписью
- `-v` - подробный вывод

---

### 4. Поиск файлов

Задача: найти все `.conf` файлы в `~/projects`.

```bash
leprecha@Ubuntu-DevOps:~$ find ~/projects -name "*.conf"
/home/leprecha/projects/configs/nginx.conf
```

Разбор команды:

- `find` - поиск файлов и директорий
- `~/projects` - путь поиска
- `-name "*.conf"` - совпадение с именем, оканчивающимся на `.conf`

---

### 5. Права доступа

Задача: установить права на `ssh_config`, чтобы только владелец мог читать и писать.

```bash
leprecha@Ubuntu-DevOps:~$ chmod 600 ~/projects/configs/ssh_config
leprecha@Ubuntu-DevOps:~$ ls -l ~/projects/configs/ssh_config
-rw------- 1 leprecha sysadmin 0 Aug 19 21:26 /home/leprecha/projects/configs/ssh_config
```

Объяснение:

- `chmod` - изменить права доступа файла
- `600`:
  - владелец: `rw-` (`6`)
  - группа: `---` (`0`)
  - остальные: `---` (`0`)

Дополнительная проверка:

```bash
leprecha@Ubuntu-DevOps:~$ ls -R ~/projects
```

---

## 5. Итоги Урока

- **Что изучил:** навигацию и файловые операции (`pwd`, `ls`, `cd`, `mkdir`, `touch`, `cp`, `mv`, `rm`), базовые команды справки (`man`) и системные команды (`whoami`, `hostname`, `date`, `uname -a`).
- **Что отработал на практике:** создал рабочую структуру (`~/projects/{scripts,configs,logs}`), создал конфигурационные файлы, записал лог, сделал backup, искал файлы через `find`, применял права через `chmod 600`.
- **Ключевые концепции:** базовая карта FHS (`/etc`, `/var`, `/usr`, `/home`) и чтение вывода `ls -l`.
- **Что нужно повторить:** числовые права (`chmod` modes), безопасные привычки удаления (`rm -i`) и быстрое чтение permission-строк.
- **Следующий шаг:** написать небольшой bootstrap-скрипт для автоматического создания структуры проекта и стартовых файлов.
