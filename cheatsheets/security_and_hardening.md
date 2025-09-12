# security_and_hardening

---

## SSH (безопасная базовая конфигурация)

**Цель:** только ключи, ограничение перебора, аккуратные группы доступа, единообразие в systemd (юнит — `ssh.service`).

**Файл:** `/etc/ssh/sshd_config` — **серверный** конфиг демона **sshd**

| Command | Что делает | Зачем/Пример |
| --- | --- | --- |
| `sudo addgroup sshusers && sudo usermod -aG sshusers $USER` | Группа для доступа по SSH | Управлять доступом группой, а не списком логинов |
| `sudoedit /etc/ssh/sshd_config` | Редактировать конфиг | Включить безопасные директивы |
| `sudo systemctl reload ssh` | Перечитать конфиг | Применить изменения без обрыва сессии |
| `sudo systemctl status ssh` | Статус демона | Проверка что запущен и без ошибок |
| `journalctl -u ssh -n 50 --no-pager` | Логи SSH (юнит — ssh) | Единообразие: не `sshd`, а `ssh` в systemd |
| `ss -tnlp | grep :22` | Смотрим, кто слушает 22/tcp | Быстрая верификация |

**Рекомендуемые директивы `sshd_config`:**

```bash
# Аутентификация и доступ
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no

# Ограничения и перехваты
MaxAuthTries 3
LoginGraceTime 20s
AllowGroups sshusers

# Криптополитика (Можно ужесточить при необходимости)
X11Forwarding no
AllowTcpForwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
```

### Не путать: sshd_config vs ssh_config

| Файл | Роль | Когда править | Применение |
| --- | --- | --- | --- |
| `/etc/ssh/sshd_config` | Серверный конфиг демона `sshd` (входящие на этот хост) | Закрыть root, запретить пароли, ограничить попытки, задать AllowGroups | `sshd -t` (проверка) → `sudo systemctl reload ssh` → `journalctl -u ssh -n 50` |
| `/etc/ssh/ssh_config` | Глобальный клиентский конфиг (`ssh`, `scp` с этого хоста) | Задать дефолты `Host`, `User`, `IdentityFile`, `ProxyJump` для исходящих сессий | Применяется к новым подключениям, перезапуск не нужен |
| `~/.ssh/config` | Персональный клиентский конфиг пользователя | Настройки только для текущего пользователя | Применяется к новым подключениям |

**Памятка:** юнит в systemd — `ssh.service`, процесс называется `sshd`. В Fail2ban jail — `sshd`, в `systemctl` — `ssh`.

**Совет:** вместо правки `/etc/ssh/sshd_config` добавлять drop-in в `/etc/ssh/sshd_config.d/10-hardening.conf`.

---

## Брандмауэр (UFW) + IPv6 + rate‑limit SSH

| Command | Что делает | Зачем/Пример |
| --- | --- | --- |
| `sudo ufw default deny incoming` | Запрет по умолчанию | Минимизируем поверхность |
| `sudo ufw default allow outgoing` | Разрешить исходящие | Типичный baseline |
| `sudo ufw allow 22/tcp` | Разрешаем SSH | Доступ админам |
| `sudo ufw limit 22/tcp` | Лимит на соединения | Тормозит перебор паролей/ключей |
| `sudo ufw allow "Nginx Full"` | Пример сервиса | 80/443 для веба |
| `sudoedit /etc/default/ufw` → `IPV6=yes` | Включить IPv6 в UFW | Без этого IPv6 остаётся без фильтра |
| `sudo ufw enable && sudo ufw status numbered` | Включить/проверить | Контроль правил |

---

## Пользователи, sudo, базовая аудитность

| Command | Что делает | Зачем/Пример |
| --- | --- | --- |
| `sudo visudo` | Безопасное редактирование sudoers | Избежать синтаксических ошибок |
| `sudo tail -n 50 /var/log/auth.log` | Проверка входов/эскалаций | Базовая аудитность |
| `getent group sudo` | Кто в группе `sudo` | Быстрый аудит прав |

Рекомендация: включить запись команд через журнал (по умолчанию PAM пишет в `auth.log`), а для чувствительных сред — включить `auditd`и syslog‑агент на SIEM.

---

## Fail2ban (включённые jail’ы, а не только сервис)

| Command | Что делает | Зачем/Пример |
| --- | --- | --- |
| `sudo apt install -y fail2ban` | Установка | Подготовка |
| `sudo systemctl enable --now fail2ban` | Запуск | Автостарт |
| `sudoedit /etc/fail2ban/jail.local` | Локальная конфигурация | Включить нужные jail’ы |
| `sudo systemctl restart fail2ban` | Применить изменения | Перезапуск |
| `sudo fail2ban-client status sshd` | Статус jail | Проверка банов |

**Минимальный `jail.local` :**

```bash
[sshd]
enabled = true
port = 22
filter = sshd
backend = systemd
logpath = /var/log/auth.log
maxretry = 4
findtime = 10m
bantime = 1h
# Необязательно, но полезно:
bantime.increment = true
bantime.rndtime = 10m
```

---

## Auditd (постоянные правила через augenrules)

| Command | Что делает | Зачем/Пример |
| --- | --- | --- |
| `sudo apt install -y auditd audispd-plugins` | Установка | Базовый аудит |
| `sudo systemctl enable --now auditd` | Запуск | Автостарт |
| `sudoedit /etc/audit/rules.d/hardening.rules` | Постоянные правила | Сохраняются между перезагрузками |
| `sudo augenrules --load && sudo auditctl -s` | Загрузить/проверить | Применение правил |

**Пример `hardening.rules`:**

```bash
## Изменения в критичных файлах и каталогах
-w /etc/passwd -p wa -k etc_passwd
-w /etc/shadow -p wa -k etc_shadow
-w /etc/group  -p wa -k etc_group
-w /etc/sudoers -p wa -k sudoers
-w /etc/ssh/ -p wa -k ssh_config

## Бинарь sshd и логи
-w /usr/sbin/sshd -p x -k sshd_exec
-w /var/log/ -p wa -k logs_changes
```

---

## Journald (persistent + лимиты)

| Command | Что делает | Зачем/Пример |
| --- | --- | --- |
| `sudoedit /etc/systemd/journald.conf` | Настроить журнал | Постоянное хранение |
| `sudo systemctl restart systemd-journald` | Применить | Перезапуск демона |
| `journalctl --disk-usage` | Объём логов | Контроль места |

**Минимум в `journald.conf`:**

```bash
Storage=persistent
SystemMaxUse=500M
RuntimeMaxUse=200M
Compress=yes
```

---

## Unattended‑Upgrades (security‑only + проверка)

| Command | Что делает | Зачем/Пример |
| --- | --- | --- |
| `sudo apt update && sudo apt install -y unattended-upgrades` | Установка | Базовая защита |
| `sudo dpkg-reconfigure --priority=low unattended-upgrades` | Включить автообновления | Простая активация |
| `sudoedit /etc/apt/apt.conf.d/50unattended-upgrades` | AllowedOrigins/blacklist | Security‑only/тонкая настройка |
| `systemctl list-timers --all | grep -i apt` | Проверка таймеров | Когда запускается |
| `sudo unattended-upgrade --dry-run --debug | sed -n '1,120p’` | Пробный прогон | Что обновится |
| `journalctl -u apt-daily-upgrade.service -n 100 --no-pager` | Логи | Аудит |

**Подсказка:** в `50unattended-upgrades` проверить строки с `${distro_id}:${distro_codename}-security` и при желании отключить не‑security источники.

---

## AppArmor (enforce) — пример для nginx

| Command | Что делает | Зачем/Пример |
| --- | --- | --- |
| `aa-status` | Состояние профилей | Кто в enforce/complain |
| `sudo aa-enforce /etc/apparmor.d/usr.sbin.nginx` | Перевод в enforce | Cтрогий режим для nginx, чтобы всё неподписанное в профиле блокировалось |
| `sudo aa-complain /etc/apparmor.d/usr.sbin.nginx` | Переводит в complain | Удобно для отладки: видим, что нарушается, но не блокируем работу |
| `sudo systemctl restart nginx` | Применить | Перезапуск сервиса |
| `journalctl -t apparmor` | Смотреть логи AppArmor | Проверить, что именно заблокировалось или ушло в complain |

Путь профиля на Ubuntu: usr.sbin.nginx (а не usr.bin.nginx).

---

## Лимиты ресурсов для сервисов (systemd drop‑in)

| Command | Что делает | Зачем/Пример |
| --- | --- | --- |
| `sudo systemctl edit <service>` | Создать drop‑in | Без правки пакета |
| `sudo systemctl daemon-reload` | Перечитать юниты | Применение настроек |
| `systemctl show <service> -p MemoryMax,LimitNOFILE` | Проверить | Убедиться, что применилось |

**Пример drop‑in (`/etc/systemd/system/<service>.service.d/override.conf`):**

```bash
[Service]
MemoryMax=500M
LimitNOFILE=65535
```

---

## Файловая система (noexec/nosuid/nodev)

- **noexec** — нельзя запускать бинарники/скрипты из точки монтирования.
- **nosuid** — игнорируются setuid/setgid биты (сложнее эскалировать привилегии).
- **nodev** — спец-устройства внутри ФС не работают.

| Command | Что делает | Зачем/Пример |
| --- | --- | --- |
| `sudoedit /etc/fstab` | Монт‑опции | Включить `noexec,nosuid,nodev` на /tmp,/dev/shm |
| `sudo mount -o remount,noexec,nosuid,nodev /tmp` | Временное включение | Тест перед постоянным применением |
| `findmnt -no TARGET,OPTIONS /tmp /var/tmp /dev/shm` | Проверка | Контроль опций |

**Пример фрагментов `fstab`:**

```bash
# /tmp и /var/tmp (использовать отдельные tmpfs при возможности)
tmpfs /tmp     tmpfs defaults,noatime,nosuid,nodev,noexec,mode=1777 0 0
tmpfs /var/tmp tmpfs defaults,noatime,nosuid,nodev,noexec,mode=1777 0 0
# /dev/shm
tmpfs /dev/shm tmpfs defaults,noatime,nosuid,nodev,noexec,mode=1777 0 0
```

---

## Сетевой hardening (sysctl)

| Command | Что делает | Зачем/Пример |
| --- | --- | --- |
| `sudoedit /etc/sysctl.d/99-hardening.conf` | Создать профиль | Постоянные параметры |
| `sudo sysctl -p /etc/sysctl.d/99-hardening.conf` | Применить | Немедленное включение |
| `sysctl -a | egrep 'rp_filter|syncookies|redirects|source_route’` | Проверка | Верификация ключевых флагов |

**Рекомендуемый минимум:**

```bash
# IPv4
net.ipv4.conf.all.rp_filter=1                   #Защита от IP spoofing
net.ipv4.tcp_syncookies=1                       #DoS на TCP handshake
net.ipv4.conf.all.accept_redirects=0            # апрещает принимать ICMP redirect
net.ipv4.conf.default.accept_redirects=0
net.ipv4.conf.all.send_redirects=0              #Запрещает ядру самому рассылать redirect
net.ipv4.conf.default.send_redirects=0
net.ipv4.conf.all.accept_source_route=0         #Запрещает source routing
net.ipv4.conf.default.accept_source_route=0
net.ipv4.conf.all.log_martians=1                #Может заспамить логи, если трафика много
net.ipv4.conf.default.log_martians=1

# IPv6
net.ipv6.conf.all.accept_redirects=0            #Запрет на ICMPv6 Redirect
net.ipv6.conf.default.accept_redirects=0
```

---

## Аудит SUID/SGID и периодические проверки

| Command | Что делает | Зачем/Пример |
| --- | --- | --- |
| `sudo find / -perm -4000 -type f 2>/dev/null` | Все SUID | Поиск опасных бинарей |
| `sudo find / -perm -2000 -type f 2>/dev/null` | Все SGID | Аудит групповых привилегий |
| `sudo dpkg -S $(which <bin>)` | Чей файл | Понять, из какого пакета |
| `sudo chmod u-s <bin>` | Снять SUID | Только если понимаете последствия |

Рекомендуется скрипт‑отчёт раз в день/неделю с diff от прошлого состояния.

---

## PAM: сложность паролей, блокировки, опционально TOTP для SSH

| Component | Что делает | Зачем |
| --- | --- | --- |
| `libpam-pwquality` | Правила сложности | Если пароли всё же используются |
| `pam_faillock.so` | Блокировка после N ошибок | Снижает брутфорс на локальном входе |
| `libpam-google-authenticator` / `libpam-oath` | 2FA (TOTP) для SSH | Доп. фактор для привилегированных учёток |

Для SSH с ключами и `PasswordAuthentication no` 2FA обычно не нужно. Если включить — то обязательно протестировать «break‑glass» доступ отдельно.

---

## Резервные копии и «break‑glass»

| Command | Что делает | Зачем/Пример |
| --- | --- | --- |
| `sudo tar --xattrs --acls -czf /root/etc_$(date +%F).tgz /etc` | Снапшот `/etc` | Быстро вернуть конфиги после кривой настройки |
| `rsync -aHAX --delete /var/backups/ /mnt/backup/host/` | Каталожные бэкапы | Регулярность важнее идеала |
| `ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_backup -C "break-glass"` | Резервный ключ | Держать офлайн (на флешке) |
| `chmod 600 ~/.ssh/id_ed25519_backup` | Права на ключ | Безопасность |

---

## Подводные камни

- Заблокировал себя: выключил `PasswordAuthentication`, но не проверил вход по ключу.
- Неполный фаервол: UFW не фильтрует IPv6, если не включить `IPV6=yes`.
- Не путаем юниты: `ssh` (systemd) vs `sshd` (процесс/фильтр в fail2ban). В логах jail — `sshd`, в `systemctl` — `ssh`.
- AppArmor: профиль nginx — `usr.sbin.nginx`, а не `usr.bin.nginx`.
- Systemd drop‑in: директивы должны быть на отдельных строках, иначе игнорируются.
- Journald: без `Storage=persistent` логи теряются после перезагрузки.

---

## Практикум

1. **SSH:** новый терминал → зайти по ключу; ввести 3 неверных логина — увидеть реакцию (`MaxAuthTries`).
2. **UFW:** с внешней машины — скан `nmap -Pn -p22,80,443 <host>`; убедиться, что только нужные порты.
3. **Fail2ban:** 5 неудачных попыток SSH с тестового IP → `fail2ban-client status sshd` покажет бан.
4. **Auditd:** `sudoedit /etc/hosts` → сохранить → проверить `ausearch -k logs_changes`/`etc_*`.
5. **Journald:** перезагрузка хоста → `journalctl --boot -1` доступен (значит persistent работает).
6. **Unattended‑Upgrades:** `--dry-run` и просмотр лога сервиса после следующего запуска таймера.
7. **Sysctl:** `sysctl -p /etc/sysctl.d/99-hardening.conf` и повторная проверка значений.
8. **FS:** `mount | grep -E "(/tmp|/var/tmp|/dev/shm)"` — убедиться в `noexec,nosuid,nodev`.

---

## Security Checklist

- **SSH**: проверить ключи, `PasswordAuthentication no`, `PermitRootLogin no`, `MaxAuthTries 3`, `AllowGroups sshusers`.
- **UFW**: deny‑by‑default, `limit 22/tcp`, `IPV6=yes`.
- **Fail2ban**: jail `sshd` включён.
- **Auditd**: правила загружены через `augenrules`.
- **Journald**: `Storage=persistent`, лимиты заданы.
- **Unattended‑Upgrades**: security‑only c dry‑run’ом.
- **AppArmor**: ключевые сервисы в `enforce`.
- **Systemd drop‑in**: лимиты применились (`systemctl show`).
- **FS**: `noexec,nosuid,nodev` на `/tmp`, `/var/tmp`, `/dev/shm`.
- **Sysctl**: включены `rp_filter`, `syncookies`, запреты `redirects/source_route`.
- **SUID/SGID**: аудит и diff от прошлого запуска.
- **Бэкапы**: свежий `tar` `/etc` и рабочий сценарий восстановления.
- **Break‑glass ключ**: создан, хранится офлайн, проверять вход.