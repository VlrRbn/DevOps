# lesson_04

# Пользователи, Группы, ACL, Umask и Sudoers

**Date:** 2025-08-23  
**Topic:** Управление локальными учетными записями, модель групповой работы, контроль доступа и sudo по принципу наименьших привилегий  
**Daily goal:** Построить практическую модель совместной работы нескольких пользователей с безопасными правами доступа и ограниченным админ-доступом.
**Bridge:** [00 Foundations Bridge](../00-foundations-bridge/00-foundations-bridge.ru.md) — компенсация недостающих базовых тем после уроков 1-4.

---

## 1. Базовые Концепции

### 1.1 Модель идентичности в Linux

Решения о доступе в Linux основаны на:

- **User ID (UID)**
- **Primary Group ID (GID)**
- **Дополнительных группах (supplementary groups)**
- **Битах прав и ACL-записях**

Полезные файлы:

- `/etc/passwd` - пользователи (метаданные аккаунта, shell, home)
- `/etc/group` - группы и их состав
- `/etc/shadow` - хэши паролей и политика старения паролей (читается root)

### 1.2 Владение и права

У каждого файла/директории есть:

- владелец (user)
- группа
- права для `user/group/others`

Дополнительные механики для командных директорий:

- **SGID на директории** (`chmod 2xxx`) - новые файлы наследуют группу директории
- **Default ACL** (`setfacl -d`) - наследуемая ACL-политика для новых объектов
- **Sticky bit** (`chmod +t`) - удалять чужие файлы может только владелец файла или root
- **umask** - фильтр прав по умолчанию при создании файлов
- **ACL mask** - верхняя граница эффективных прав ACL для групп/именованных пользователей

---

## 2. Приоритет Команд (Что Учить Сначала)

### Core (обязательно сейчас)

- `whoami`, `id`, `groups`
- `getent passwd`, `getent group`
- `adduser`, `userdel` (или `deluser`)
- `groupadd`, `groupdel`
- `usermod -aG`
- `chown`, `chgrp`, `chmod`

### Optional (после core)

- `gpasswd -a`, `gpasswd -d`
- `chage -l`, `chage -m/-M/-W/-E`
- `usermod -L`, `usermod -U`, `usermod -s /usr/sbin/nologin`
- `newgrp`

### Advanced (глубже для администрирования)

- `setfacl`, `getfacl`
- тюнинг ACL mask (`setfacl -m m::...`)
- `visudo -cf`
- ограниченные sudo-правила в `/etc/sudoers.d/*`

---

## 3. Core Команды: Что / Зачем / Когда

### `whoami`, `id`, `groups`

- **Что:** текущая идентичность и групповой контекст
- **Зачем:** первый sanity-check при проблемах с правами
- **Когда:** до диагностики проблем доступа

```bash
whoami
id
groups
```

### `getent passwd`, `getent group`

- **Что:** записи пользователей/групп из NSS-источников
- **Зачем:** надежнее, чем смотреть только локальные файлы
- **Когда:** нужно подтвердить, что пользователь/группа реально существует

```bash
getent passwd alice
getent group project
```

### `adduser` и `userdel`

- **Что:** создание/удаление аккаунта пользователя
- **Зачем:** стандартный lifecycle аккаунтов
- **Когда:** onboarding/offboarding

```bash
sudo adduser alice
sudo adduser bob
sudo userdel -r bob   # -r удаляет home и почтовый spool
```

### `groupadd`, `usermod -aG`

- **Что:** создание группы и добавление в дополнительные группы
- **Зачем:** выдача общего доступа через групповую модель
- **Когда:** настройка доступа к проектным ресурсам

```bash
sudo groupadd project
sudo usermod -aG project alice
sudo usermod -aG project bob
id alice
id bob
```

### `chgrp`, `chmod`, `chown`

- **Что:** установка группы, прав и владельца
- **Зачем:** задает правила доступа в shared-директориях
- **Когда:** подготовка директорий для совместной работы

```bash
sudo chgrp project /project_data
sudo chmod 2770 /project_data
sudo chown root:project /project_data
```

---

## 4. Mini-lab 1: Совместная Работа Alice и Bob

### 4.1 Цель

Создать общую директорию, где участники проекта могут читать/писать файлы друг друга, а новые файлы наследуют проектную группу.

### 4.2 Настройка

```bash
sudo adduser alice
sudo adduser bob
sudo groupadd -f project
sudo usermod -aG project alice
sudo usermod -aG project bob

sudo mkdir -p /project_data
sudo chown root:project /project_data
sudo chmod 2770 /project_data
sudo setfacl -d -m g:project:rwx /project_data
```

Смысл:

- `2770` = `rwxrws---` (включен SGID)
- default ACL обеспечивает наследуемые права группы

### 4.3 Проверка с обоими пользователями

```bash
sudo -u alice bash -lc 'echo "hello from alice" > /project_data/alice.txt && ls -l /project_data/alice.txt'
sudo -u bob bash -lc 'cat /project_data/alice.txt && echo "and bob was here" >> /project_data/alice.txt && tail -n1 /project_data/alice.txt'
sudo -u bob bash -lc 'mkdir /project_data/bob_dir && echo "bob file" > /project_data/bob_dir/note.txt && ls -ld /project_data/bob_dir && ls -l /project_data/bob_dir'
```

Ожидаемо:

- созданные объекты получают группу `project`
- оба участника могут изменять shared-файлы

---

## 5. Механика Прав Под Микроскопом

### 5.1 umask

**umask** убирает биты прав из базовых режимов создания.

Базовые режимы:

- для файла: `666`
- для директории: `777`

Примеры:

- `umask 022` -> файлы `644`, директории `755`
- `umask 002` -> файлы `664`, директории `775`
- `umask 077` -> файлы `600`, директории `700`

### 5.2 ACL mask

ACL `mask::` - это верхняя граница эффективных прав для:

- `group::`
- именованных пользователей (`user:...`)
- именованных групп (`group:...`)

То есть запись может выглядеть как `rwx`, но фактические права будут ниже из-за mask.

### 5.3 Практическая проверка

```bash
sudo -u alice bash -lc 'umask 077; echo A > /project_data/u_077.txt'
sudo -u bob bash -lc 'umask 022; echo B > /project_data/u_022.txt'
sudo bash -lc 'ls -l /project_data/u_*.txt'
sudo getfacl /project_data/u_077.txt
```

### 5.4 Тюнинг ACL mask

```bash
sudo setfacl -m m::rx /project_data
sudo getfacl /project_data | sed -n '1,20p'

# вернуть более широкую mask для совместной работы
sudo setfacl -m m::rwx /project_data
```

### 5.5 Поведение sticky bit

Sticky bit защищает от удаления чужих файлов в shared-директориях.

```bash
sudo chmod +t /project_data
ls -ld /project_data
```

Без sticky bit пользователь с правом записи в директорию может удалить чужой файл.
Со sticky bit удалять файл может только его владелец или root.

---

## 6. Mini-lab 2: Командная Папка DevOps

### 6.1 Цель

Настроить командный shared-каталог для нескольких пользователей с наследованием группы и безопасным удалением.

### 6.2 Настройка

```bash
sudo groupadd -f devops
for u in dev1 dev2 dev3; do
  sudo adduser --disabled-password --gecos "" "$u"
  sudo usermod -aG devops "$u"
done

sudo mkdir -p /devops_share
sudo chown root:devops /devops_share
sudo chmod 2770 /devops_share
sudo setfacl -d -m g:devops:rwx /devops_share
sudo chmod +t /devops_share
```

### 6.3 Проверка поведения

```bash
sudo -u dev1 bash -lc 'echo "from dev1" > /devops_share/dev1.txt && ls -l /devops_share/dev1.txt'
sudo -u dev2 bash -lc 'cat /devops_share/dev1.txt && echo "dev2 was here" >> /devops_share/dev1.txt && tail -n1 /devops_share/dev1.txt'
sudo -u dev3 bash -lc 'mkdir /devops_share/dev3_dir && echo note > /devops_share/dev3_dir/note.txt && ls -ld /devops_share/dev3_dir && ls -l /devops_share/dev3_dir'
```

---

## 7. Политики Учетных Записей

### 7.1 Старение пароля (`chage`)

```bash
sudo chage -l alice
sudo chage -m 1 -M 60 -W 7 alice
sudo chage -l alice
```

### 7.2 Блокировка и разблокировка аккаунта

```bash
sudo usermod -L bob && sudo passwd -S bob
sudo usermod -U bob && sudo passwd -S bob
```

### 7.3 Отключение интерактивного shell

```bash
sudo usermod -s /usr/sbin/nologin bob
```

### 7.4 Дата истечения аккаунта

```bash
sudo chage -E 2025-12-31 dev2
sudo chage -E "$(date -d '+90 days' +%Y-%m-%d)" dev1
sudo chage -l dev2
sudo chage -l dev1
```

---

## 8. Ограниченный Sudoers (Least Privilege)

### 8.1 Цель

Разрешить support-группе смотреть статус сервисов и логи без выдачи полного root-shell.

### 8.2 Настройка группы и членства

```bash
sudo groupadd -f devopsadmin
sudo usermod -aG devopsadmin alice
groups alice
```

### 8.3 Создание ограниченной sudo-политики

```bash
cat <<'SUDO_EOF' | sudo tee /etc/sudoers.d/devopsadmin >/dev/null
Cmnd_Alias DEVOPS_SAFE = /usr/bin/systemctl status *, /usr/bin/journalctl -u *
%devopsadmin ALL=(root) NOPASSWD: DEVOPS_SAFE
SUDO_EOF

sudo chmod 440 /etc/sudoers.d/devopsadmin
sudo visudo -cf /etc/sudoers.d/devopsadmin
sudo -l -U alice
```

### 8.4 Тест от имени целевого пользователя

```bash
su - alice
newgrp devopsadmin
sudo -l
sudo systemctl status cron | head -n3
sudo journalctl -u cron --since "5 min ago" | tail -n5
exit
```

---

## 9. Автоматизация: Скрипт Подготовки Shared-Директории

Путь к скрипту:

- `lessons/04-users-groups-acl-sudoers/scripts/mkshare.sh`

Что автоматизирует:

1. Проверяет/создает целевую группу.
2. Создает целевую директорию.
3. Устанавливает владение `root:<group>`.
4. Ставит SGID-права (`2770`).
5. Ставит ACL для rwx группе (effective + default).
6. Опционально включает sticky bit.

Пример запуска:

```bash
chmod +x lessons/04-users-groups-acl-sudoers/scripts/mkshare.sh
lessons/04-users-groups-acl-sudoers/scripts/mkshare.sh devs /srv/shared/dev --sticky
ls -ld /srv/shared/dev
getfacl /srv/shared/dev | sed -n '1,20p'
```

---

## 10. Очистка (Опционально)

Если это лабораторная/временная машина, можно удалить объекты, созданные в уроке.

```bash
sudo userdel -r alice 2>/dev/null || true
sudo userdel -r bob 2>/dev/null || true
for u in dev1 dev2 dev3; do sudo userdel -r "$u" 2>/dev/null || true; done

sudo groupdel project 2>/dev/null || true
sudo groupdel devops 2>/dev/null || true
sudo groupdel devopsadmin 2>/dev/null || true

sudo rm -rf /project_data /devops_share
sudo rm -f /etc/sudoers.d/devopsadmin
```

---

## 11. Итоги Урока

- **Что изучил:** как Linux связывает идентичность пользователя, группы и контроль доступа.
- **Что отработал на практике:** создание пользователей/групп, настройка shared-директорий, проверка кросс-пользовательского доступа.
- **Ключевые концепции:** SGID-наследование, default ACL, ACL mask, sticky bit и политика жизненного цикла аккаунтов.
- **Фокус по безопасности:** ограниченные sudo-права на уровне команд вместо полного root-доступа.
- **Следующий шаг:** сделать переиспользуемые админ-скрипты и применять ту же модель к сервисным директориям.
