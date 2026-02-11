# lesson_02

# Файлы, Nano и Права в Linux

**Date:** 2025-08-20  
**Topic:** Работа с файлами и правами  
**Daily goal:** Закрепить файловые операции, попрактиковать `nano` и понять базу прав доступа и владения.

---

## 1. Повторение + Новые Команды

### `ls -la`

Показать содержимое директории в длинном формате, включая скрытые файлы.

```bash
leprecha@Ubuntu-DevOps:~$ ls -la
drwxr-x--- 18 leprecha sysadmin 4096 Aug 20 17:07 .
drwxr-xr-x  3 root     root     4096 Aug 19 15:19 ..
-rw-------  1 leprecha sysadmin 8217 Aug 20 17:07 .bash_history
```

Флаги:

- `-l` - длинный формат
- `-a` - показывать скрытые файлы

---

### `cd`

Сменить текущую директорию.

```bash
leprecha@Ubuntu-DevOps:~$ cd /etc
leprecha@Ubuntu-DevOps:/etc$
```

---

### `pwd`

Показать текущую рабочую директорию.

```bash
leprecha@Ubuntu-DevOps:~$ pwd
/home/leprecha
```

---

### `tree` (опциональная утилита)

Показать структуру директорий в виде дерева.

```bash
leprecha@Ubuntu-DevOps:~$ tree /etc | head -n 5
/etc
|-- adduser.conf
|-- alsa
|   `-- conf.d
|       `-- 10-rate-lav.conf -> /usr/share/alsa/alsa.conf.d/10-rate-lav.conf
```

Если `tree` не установлен, используй:

```bash
leprecha@Ubuntu-DevOps:~$ find /etc -maxdepth 2 | head -n 10
```

---

### `stat`

Показать подробные метаданные файла.

```bash
leprecha@Ubuntu-DevOps:~$ stat /etc/passwd
  File: /etc/passwd
  Size: 2959       Blocks: 8          IO Block: 4096 regular file
Device: 259,2      Inode: 5507826     Links: 1
Access: (0644/-rw-r--r--)  Uid: (0/root)  Gid: (0/root)
Access: 2025-08-20 16:58:14.464296261 +0100
Modify: 2025-08-19 15:51:08.037927698 +0100
Change: 2025-08-19 15:51:08.038485928 +0100
 Birth: 2025-08-19 15:51:08.037485933 +0100
```

---

## 2. Работа с Nano

`nano` - простой текстовый редактор в терминале для быстрых правок файлов.

Открыть или создать файл:

```bash
leprecha@Ubuntu-DevOps:~$ nano filename.txt
```

Полезные клавиши:

| Key | Action |
| --- | --- |
| `Ctrl + O` | Сохранить файл |
| `Ctrl + X` | Выйти из nano |
| `Ctrl + G` | Помощь |
| `Ctrl + W` | Поиск |
| `Ctrl + K` | Вырезать строку |
| `Ctrl + U` | Вставить строку |
| `Ctrl + C` | Позиция курсора |
| `Ctrl + _` | Перейти к строке/колонке |

### Практика

1. Создай `filename.txt` в домашней директории.
2. Напиши 2-3 предложения о себе на английском.
3. Сохрани файл и выйди.
4. Скопируй файл в `/tmp`.
5. Проверь содержимое через `cat`.

```bash
leprecha@Ubuntu-DevOps:~$ nano filename.txt
leprecha@Ubuntu-DevOps:~$ cp filename.txt /tmp/filename.txt
leprecha@Ubuntu-DevOps:~$ cat /tmp/filename.txt
How are you today? I am fine.
```

---

## 3. Копирование, Перемещение и Удаление

| Command | Description |
| --- | --- |
| `cp file.txt backup.txt` | Копировать файл в новый файл |
| `cp file.txt /home/user/` | Копировать файл в директорию |
| `cp -r myfolder /home/user/` | Копировать директорию рекурсивно |
| `mv file.txt /home/user/` | Переместить файл |
| `mv old.txt new.txt` | Переименовать файл |
| `rm file.txt` | Удалить файл |
| `rm file1 file2` | Удалить несколько файлов |
| `rm -r myfolder` | Удалить директорию рекурсивно |
| `rm -rf myfolder` | Принудительно удалить директорию (опасно) |

### Копирование (`cp`)

```bash
leprecha@Ubuntu-DevOps:~$ cp filename.txt backup.txt
leprecha@Ubuntu-DevOps:~$ cat backup.txt
How are you today? I am fine.
```

Копирование директории с содержимым:

```bash
leprecha@Ubuntu-DevOps:~$ cp -r Folder /home/leprecha/Documents/
```

### Перемещение и переименование (`mv`)

```bash
leprecha@Ubuntu-DevOps:~$ mv filename.txt /home/leprecha/Documents/Folder/
leprecha@Ubuntu-DevOps:~$ mv /home/leprecha/Documents/Folder/filename.txt /home/leprecha/Documents/Folder/newfile.txt
```

### Удаление (`rm`)

```bash
leprecha@Ubuntu-DevOps:~$ rm newfile.txt
leprecha@Ubuntu-DevOps:~$ rm backup.txt file.txt
```

Опасная команда:

```bash
leprecha@Ubuntu-DevOps:~$ rm -rf /home/leprecha/Music/Folder/
```

Примечания:

- `-r` - удалять рекурсивно
- `-f` - удалять принудительно, без подтверждений
- у `rm` нет настоящего dry-run режима

Более безопасный вариант:

```bash
leprecha@Ubuntu-DevOps:~$ rm -ri /home/leprecha/Music/Folder/
leprecha@Ubuntu-DevOps:~$ rm -I /home/leprecha/Music/Folder/
```

Если нужен предварительный просмотр перед удалением:

```bash
leprecha@Ubuntu-DevOps:~$ find /home/leprecha/Music/Folder -maxdepth 2 -print
```

### Практика

1. Создай `~/lab2_files`.
2. Создай `file1.txt`, `file2.txt`, `file3.txt`.
3. Скопируй `file1.txt` в `/tmp`.
4. Перемести `file2.txt` в `/tmp/file2_moved.txt`.
5. Удали `file3.txt`.
6. Удали `~/lab2_files`.

```bash
leprecha@Ubuntu-DevOps:~$ mkdir ~/lab2_files
leprecha@Ubuntu-DevOps:~$ touch ~/lab2_files/file1.txt ~/lab2_files/file2.txt ~/lab2_files/file3.txt
leprecha@Ubuntu-DevOps:~$ cp ~/lab2_files/file1.txt /tmp/
leprecha@Ubuntu-DevOps:~$ mv ~/lab2_files/file2.txt /tmp/file2_moved.txt
leprecha@Ubuntu-DevOps:~$ rm ~/lab2_files/file3.txt
leprecha@Ubuntu-DevOps:~$ rm -r ~/lab2_files
```

---

## 4. Права Доступа и Владение

Права в Linux определяют, кто и что может делать с файлом или директорией.

Группы прав:

1. Владелец (`u`)
2. Группа (`g`)
3. Остальные (`o`)

Биты прав:

- `r` - чтение
- `w` - запись
- `x` - выполнение (для директорий: вход/проход)

### Чтение вывода `ls -l`

```bash
leprecha@Ubuntu-DevOps:~$ ls -l
drwxr-xr-x 2 leprecha sysadmin 4096 Aug 20 17:23 Desktop
drwx------ 6 leprecha sysadmin 4096 Aug 19 21:00 snap
-rw-rw-r-- 1 leprecha sysadmin  492 Aug 20 19:31 learnlinux.spec
```

Разбор примера `-rw-rw-r--`:

- первый символ `-` = обычный файл
- владелец `rw-`
- группа `rw-`
- остальные `r--`

### Изменение прав через `chmod`

Символьный режим:

- `chmod u+x file` - добавить execute владельцу
- `chmod g-w file` - убрать write у группы
- `chmod o+r file` - добавить read для остальных

Числовой режим:

- `r = 4`, `w = 2`, `x = 1`
- `7 = rwx`, `6 = rw-`, `5 = r-x`, `4 = r--`

Примеры:

```bash
leprecha@Ubuntu-DevOps:~$ chmod u+x learnlinux.spec
leprecha@Ubuntu-DevOps:~$ chmod 555 learnlinux.spec
leprecha@Ubuntu-DevOps:~$ ls -l learnlinux.spec
-r-xr-xr-x 1 leprecha sysadmin 0 Aug 20 19:09 learnlinux.spec
```

Популярные режимы:

| Mode | Meaning |
| --- | --- |
| `644` | owner `rw-`, group `r--`, others `r--` |
| `600` | owner `rw-`, group `---`, others `---` |
| `755` | owner `rwx`, group `r-x`, others `r-x` |
| `740` | owner `rwx`, group `r--`, others `---` |

### Смена владельца/группы

- `chown user file` - сменить владельца
- `chgrp group file` - сменить группу
- `chown user:group file` - сменить владельца и группу

Пример:

```bash
leprecha@Ubuntu-DevOps:~$ sudo chown helpme learnlinux.spec
leprecha@Ubuntu-DevOps:~$ ls -l learnlinux.spec
-r-xr-xr-x 1 helpme sysadmin 0 Aug 20 19:09 learnlinux.spec
```

Рекурсивная смена владельца:

```bash
leprecha@Ubuntu-DevOps:~$ sudo chown -Rv helpme /path/to/dir
```

Рекурсивный режим используй аккуратно: всегда проверяй путь перед запуском.

### Практика

1. Создай `test_permissions.txt`.
2. Проверь исходные права.
3. Установи права: владелец полный доступ, группа только чтение, остальные без доступа.
4. Проверь итоговые права.
5. Смени владельца (если пользователь `helpme` существует).

```bash
leprecha@Ubuntu-DevOps:~$ touch test_permissions.txt
leprecha@Ubuntu-DevOps:~$ ls -l test_permissions.txt
-rw-r--r-- 1 leprecha sysadmin 0 Aug 20 19:25 test_permissions.txt
leprecha@Ubuntu-DevOps:~$ chmod 740 test_permissions.txt
leprecha@Ubuntu-DevOps:~$ sudo chown helpme test_permissions.txt
leprecha@Ubuntu-DevOps:~$ ls -l test_permissions.txt
-rwxr----- 1 helpme sysadmin 0 Aug 20 19:25 test_permissions.txt
```

---

## 5. Итоги Урока

- **Что изучил:** навигацию и просмотр файловой системы (`ls`, `cd`, `pwd`, `tree`, `stat`), основы редактора (`nano`), жизненный цикл файлов (`cp`, `mv`, `rm`) и управление правами/владением (`chmod`, `chown`, `chgrp`).
- **Что отработал на практике:** создавал файлы, копировал в `/tmp`, перемещал и переименовывал файлы, удалял файлы/директории, применял числовые права (`740`, `555`).
- **Ключевые концепции:** модель прав (`u/g/o`, `r/w/x`), разница между символьным и числовым `chmod`, безопасный подход к рекурсивному удалению и смене владельца.
- **Что нужно повторить:** быстрая конвертация числовых прав в символьные; безопасный порядок удаления (`предпросмотр -> подтверждение -> удаление`).
- **Следующий шаг:** написать небольшой скрипт, который автоматически готовит практическую директорию и выставляет нужные права.
