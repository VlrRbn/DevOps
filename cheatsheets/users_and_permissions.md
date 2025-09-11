# users_and_permissions

---

## Базовая диагностика

| Команда | Что делает | Зачем / Пример |
| --- | --- | --- |
| `id` | UID/GID, группы | Понять, кем видит система |
| `who` / `w` | Активные сессии | Кто залогинен/что делает |
| `logname` | Имя пользователя сессии | Когда `sudo` путает контекст |
| `getent passwd USER` | Запись из базы NSS | Универсально (локально/LDAP/AD) |
| `getent group GROUP` | Инфа о группе | Проверить членство |
| `groups USER` | Список групп | Быстрое членство |
| `last` | История логинов | Кто/когда заходил (по журналам) |
| `lastlog` | Последний логин по всем | Выявить «мертвые» учётки |

---

## Пользователи: создание, изменение, удаление

> Есть удобная обёртка adduser (интерактивная). Низкоуровневые — useradd/usermod/userdel.
> 

| Задача | Команда | Пояснение |
| --- | --- | --- |
| Создать пользователя с домашним и shell | `sudo useradd -m -s /bin/bash alice` | `-m` создаёт `$HOME`, `-s` задаёт шелл |
| Установить пароль | `sudo passwd alice` | Интерактивно |
| Сменить основной (primary) GID | `sudo usermod -g developers alice` | Основная группа |
| Добавить во вспомогательные группы | `sudo usermod -aG sudo,docker alice` | `-aG` = добавить, не затирая |
| Переименовать пользователя (логин) | `sudo usermod -l newname oldname` | Осторожно с `$HOME` |
| Переместить/переименовать домашний | `sudo usermod -d /home/newname -m newname` | `-m` перенесёт файлы |
| Заблокировать/разблокировать вход паролем | `sudo usermod -L alice` / `-U` | Блокирует вход **по паролю** |
| Установить дату истечения | `sudo usermod -e 2025-12-31 alice` | Авто-отключение |
| Удалить пользователя | `sudo userdel alice` | Аккаунт без домашнего |
| Удалить с домашним | `sudo userdel -r alice` | Удалит `$HOME` и почту |

**Подводные камни**

- **НЕ** путать `-G` и `-aG` в `usermod`: без `-a` перезапишется список групп.
- При переименовании `$HOME` использовать `-d NEW -m` для переноса.
- В домене смотреть через `getent`, а не через `/etc/passwd`.

**Рецепт «переименовать логин и дом» + починить владельцев (если меняли UID/GID)**

```bash
old=alice; new=alicia
sudo usermod -l "$new" "$old"
sudo usermod -d "/home/$new" -m "$new"

# Если меняли UID/GID: найти «осиротевшие» и починить владельцев
OLDUID=12345; NEWUSER="$new"
sudo find / -xdev -uid "$OLDUID" -exec chown -h "$NEWUSER" {} +
```

---

## Группы: создание и управление

| Задача | Команда | Пояснение |
| --- | --- | --- |
| Создать группу | `sudo groupadd developers` |  |
| Переименовать группу | `sudo groupmod -n devs developers` |  |
| Удалить группу | `sudo groupdel developers` |  |
| Добавить пользователя в группу | `sudo usermod -aG developers alice` | Типичный кейс |
| Сменить пароль группы | `sudo gpasswd developers` | Редко используется |
| Войти во вновь выданную группу без relogin | `newgrp developers` | Обновляет эффективные группы в текущем шелле |

**Лайфхак:** `adduser alice developers` — удобная альтернатива `usermod -aG`.

---

## Права доступа: rwx и «спецбиты»

Формат `-rwxr-x---` / `750` (владелец / группа / остальные).

| Приём | Команда | Пояснение |
| --- | --- | --- |
| Числовые права | `chmod 640 file` | `6`=rw-, `4`=r–, `0`=— |
| Символьные | `chmod u+rw,g+r,o- file` | Точно добавить/убрать |
| Сменить владельца | `sudo chown user:group path -R` | Рекурсивно |
| Только группа | `sudo chgrp group path` | Когда владелец тот же |
| Маска по умолчанию | `umask` / `umask 027` | Влияет на **новые** файлы/папки |

| Цифра | Символ | Значение |
| --- | --- | --- |
| 7 | `rwx` | все права |
| 6 | `rw-` | read + write |
| 5 | `r-x` | read + execute |
| 4 | `r--` | только read |
| 3 | `-wx` | write + execute |
| 2 | `-w-` | только write |
| 1 | `--x` | только execute |
| 0 | `---` | нет прав |

### Спецбиты: setuid, setgid, sticky

| Бит | Число | Где | Эффект |
| --- | --- | --- | --- |
| setuid (`s`) | `4xxx` | Файлы | Процесс получает EUID владельца |
| setgid (`s`) | `2xxx` | Файлы/директории | Директория: новые файлы наследуют **группу** |
| sticky (`t`) | `1xxx` | Директории | Удалять может только владелец файла или root |

**Примеры**

```bash
# SGID на «общей»: всё внутри с одной группой
sudo chgrp devs /srv/shared
sudo chmod 2775 /srv/shared

# Sticky на «песочнице»
sudo chmod 1777 /srv/scratch
```

Подводные камни: `chmod 2775` → первая цифра `2`=setgid; `1`=sticky; `4`=setuid.

---

## ACL (расширенные разрешения)

| Команда | Что делает | Пример |
| --- | --- | --- |
| `getfacl path` | Показать ACL | Диагностика |
| `setfacl -m u:alice:rw file` | Разрешение для пользователя | Точечно |
| `setfacl -m g:devs:rwx dir` | Разрешение для группы | Совместная папка |
| `setfacl -d -m g:devs:rwx dir` | **Default ACL** | Наследование |
| `setfacl -x u:alice file` | Удалить правило | Чистка ACL |

**Важно про `mask`:**

ACL-маска может ограничить эффективные права групп/записей. Если «не срабатывает», проверить `getfacl` и при необходимости расширить маску:

```bash
setfacl -m m::rwx dir
```

**Замечание:** ACL может «переехать» поверх обычных прав — нужно документировать места, где они включены.

---

## Sudo, su, sudoers

| Приём | Команда | Пояснение |
| --- | --- | --- |
| Проверить права sudo | `sudo -l` | Что разрешено |
| Безопасное редактирование | `sudo visudo` | Проверка синтаксиса |
| Правила по файлам | `/etc/sudoers.d/90-admins` | Разнести правила |
| Сменить пользователя | `su - USER` | Полная сессия как `USER` |
| Команда от имени | `sudo -u USER cmd` | Без входа |

**Пример (точечный, безопаснее):**

`/etc/sudoers.d/90-restart-nginx`

```bash
alice ALL=(root) NOPASSWD:/bin/systemctl restart nginx
```

(Выдаёт право **только** на рестарт nginx, без пароля.)

**Анти-пример (широкий, опаснее):**

```bash
%admins ALL=(ALL) NOPASSWD: /usr/bin/systemctl *, /usr/bin/journalctl *
```

Опасно: открывает все аргументы. Лучше дробить на конкретные сервисы/команды.

**Подводные камни:** всегда через `visudo`; следить, чтобы `Defaults env_reset` не ломал нужные переменные окружения.

---

## Пароли, срок действия и блокировки

| Задача | Команда | Пояснение |
| --- | --- | --- |
| Установить/сменить пароль | `sudo passwd USER` |  |
| Массово задать пароли | `echo 'user:pass' | sudo chpasswd` |  |
| Политики паролей | `/etc/login.defs`, `pam_pwquality` | Длина/сложность |
| Посмотреть сроки | `sudo chage -l USER` |  |
| Изменить сроки | `sudo chage -E 2025-12-31 -M 90 -m 1 -W 7 USER` |  |
| Заблокировать/разблокировать вход паролем | `sudo passwd -l USER` / `-u` | Ставит `!` в `/etc/shadow` |

**PAM коротко:** `pam_faillock` (блокировка после X неудач), `pam_pwquality` (сложность). Настройки в `/etc/pam.d/*`.

---

## Системные пользователи и `/etc/skel`

| Тема | Ключевые моменты |
| --- | --- |
| Системные пользователи | UID обычно <1000, shell `/usr/sbin/nologin` |
| Создать сервисную учётку | `sudo useradd -r -s /usr/sbin/nologin -M -d /nonexistent svc_foo` |
| Шаблоны | `/etc/skel` копируется в `$HOME` при `useradd -m` |
| Диапазоны UID/GID | `grep -E '^(UID|GID)_MIN|_MAX' /etc/login.defs` |

---

## Capabilities (вместо setuid)

| Команда | Что делает | Пример |
| --- | --- | --- |
| `getcap /path/to/bin` | Показать capabilities |  |
| `sudo setcap cap_net_bind_service=+ep /usr/local/bin/myapp` | Слушать <1024 без root | Безопаснее, чем setuid |

---

## Атрибуты файловой системы (ext4)

| Команда | Что делает | Пример |
| --- | --- | --- |
| `lsattr file` | Показать атрибуты |  |
| `chattr +i file` | «Нерушимый» | Защита от удаления |
| `chattr +a dir` | Только добавления | Логи/журналы |

**Осторожно:** `+i` может ломать апдейты/скрипты; нужна привилегия root.

---

## Поиск по правам / владельцам (аудит)

| Задача | Команда |
| --- | --- |
| Найти SUID файлы | `sudo find / -xdev -perm -4000 -type f -printf '%M %u %p\n' 2>/dev/null` |
| Файлы удалённого UID | `sudo find / -xdev -uid 12345 -ls 2>/dev/null` |
| Миро-читаемые файлы | `find . -type f -perm -o=r -printf '%m %p\n'` |
| Несовпадение владельца/группы | `find /srv/app -not -user app -o -not -group app -ls` |
| **World-writable директории без sticky** | `sudo find / -xdev -type d -perm -0002 ! -perm -1000 -print` |

---

## Практикум

1. **Общая директория с SGID + ACL**

```bash
sudo groupadd devs
sudo mkdir -p /srv/shared
sudo chgrp devs /srv/shared
sudo chmod 2775 /srv/shared                   # SGID: группа наследуется
sudo setfacl -d -m g:devs:rwx /srv/shared     # default ACL для новых файлов
sudo usermod -aG devs alice
sudo usermod -aG devs bob
```

Проверка: `touch /srv/shared/test && ls -l /srv/shared/test` → группа `devs`.

2. **Выдать право рестартовать nginx без пароля**

```bash
# /etc/sudoers.d/90-restart-nginx
alice ALL=(root) NOPASSWD:/bin/systemctl restart nginx
```

Проверка: `sudo -l -U alice` → затем `sudo systemctl restart nginx`.

3. **Блок учётной записи по требованию**

```bash
sudo usermod -L alice              # Блок входа по паролю:
sudo passwd -l alice               # или:
sudo chage -E 2025-09-30 alice     # Полное отключение к дате (истечение):
```

4. **Найти все SUID-бинарники и проверить целостность**

```bash
sudo find / -xdev -perm -4000 -type f -print0 2>/dev/null | xargs -0 ls -l
sudo find / -xdev -type d -perm -0002 ! -perm -1000 -print     # Проверить world-writable директории без sticky
```

---

## Security Checklist

- Минимизировать SUID; по возможности заменять на `setcap`.
- `umask 027` для админов/серверов по умолчанию; **где задать системно:** `/etc/login.defs` и `pam_umask.so` в `/etc/pam.d/common-session`.
- Перед админ-действиями сверять `id`/`groups`.
- ACL — мощно, но падает прозрачность; документировать точки применения.
- `sudoers` править **через `visudo`**; правила дробить в `/etc/sudoers.d/`.
- Широкие wildcard-правила () не использовать без крайней необходимости — точечно разрешать конкретные команды/сервисы.

---

## Быстрые блоки

```bash
# 1) Добавить пользователя и выдать sudo
sudo useradd -m -s /bin/bash alice
echo 'alice:StrongP@ss!' | sudo chpasswd
sudo usermod -aG sudo alice

# 2) Общая папка для команды devs
sudo groupadd -f devs
sudo mkdir -p /srv/shared && sudo chgrp devs /srv/shared
sudo chmod 2775 /srv/shared
sudo setfacl -d -m g:devs:rwx /srv/shared

# 3) Запретить вход паролем (только ключи/sudo)
sudo usermod -L alice
# или:
sudo passwd -l alice

# 4) Проверить «дырявые» права в проекте
find /srv/app -type f -perm -o=w -printf '%m %p\n'
```