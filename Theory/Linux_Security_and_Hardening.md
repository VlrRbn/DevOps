# Linux_Security_and_Hardening

---

## Пользователи и группы

| Команда | Что делает |
| --- | --- |
| `adduser alice` | Создать пользователя |
| `usermod -aG sudo alice` | Добавить в группу |
| `id alice` | Инфо о пользователе |
| `passwd alice` | Сменить пароль |
| `chage -l alice` | Проверить срок действия пароля |

Проверка ненужных пользователей:

```bash
cat /etc/passwd
```

---

## Пароли и sudo

- Настройки в `/etc/login.defs`: минимальная длина, срок действия.
- Модуль PAM `pam_pwquality.so` (правила сложности пароля).
- `sudo visudo` — редактировать `/etc/sudoers`.

Примеры:

```
Defaults logfile=/var/log/sudo.log
alice ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart nginx
```

---

## SSH hardening

Файл `/etc/ssh/sshd_config`:

```
Port 22
PermitRootLogin no
PasswordAuthentication no
AllowUsers alice
```

Применить:

```bash
sudo systemctl restart sshd
```

Проверить логи:

```bash
journalctl -u ssh -f
```

---

## Firewall

### UFW

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp
sudo ufw enable
```

---

## AppArmor / SELinux

Проверка AppArmor:

```bash
sudo aa-status
```

Пример профиля: `/etc/apparmor.d/usr.bin.nginx`

---

## Обновления и патчи

- Автоматические обновления: `unattended-upgrades`.
- Проверка доступных: `apt list --upgradable`.
- Следи за CVE: [https://cve.mitre.org](https://cve.mitre.org/).

---

## Resource limits (ulimit, systemd)

Файл `/etc/security/limits.conf`:

```
alice hard nofile 4096
alice soft nofile 1024
```

systemd override:

```
[Service]LimitNOFILE=65535MemoryMax=500M
```

---

## Audit и логи

### **auditd** — про аудит и «кто что сделал» (forensics, compliance, логирование)

→ добавляем правило:

- `-w /etc/passwd` → следить за файлом `/etc/passwd`;
- `-p wa` → события записи (`w`) и изменения атрибутов (`a`);
- `-k passwd_changes` → ключ, по которому потом удобно искать в логах.

```bash
sudo apt install auditd
sudo auditctl -w /etc/passwd -p wa -k passwd_changes
ausearch -k passwd_changes
```

### **fail2ban** — про превентивную защиту от атак (брутфорс, DoS)

```bash
sudo apt install fail2ban
sudo systemctl enable --now fail2ban
sudo cat /var/log/fail2ban.log
```

---

## Практикум

1. Запретить root-вход по ssh:

```bash
sudo nano /etc/ssh/sshd_config
PermitRootLogin no
sudo systemctl restart sshd
```

1. Включить firewall (только ssh):

```bash
sudo ufw default deny incoming
sudo ufw allow 22/tcp
sudo ufw enable
```

1. Настроить ограничение памяти для сервиса:

```
[Service]MemoryMax=200M
```

1. Проверить sudo-доступы:

```bash
sudo -l -U alice
```

1. Проверить неудачные входы:

```bash
grep "Failed password" /var/log/auth.log
```

---

## Security Checklist

- Отключить root-login по SSH.
- Выключить парольный вход (оставить только ключи).
- Минимизировать sudo-доступы.
- Обновлять систему (`unattended-upgrades`).
- Использовать firewall.
- Включить auditd + fail2ban.
- Хранить логи persistently (`/var/log/journal`).

---

## Быстрые блоки

```bash
# Добавить пользователя
sudo adduser bob

# Запрет root по ssh
sudo sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config && sudo systemctl restart sshd

# Firewall: только ssh и http
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw enable

# Проверить sudoers
sudo -l -U alice

# Логи неудачных ssh-входов
grep "Failed" /var/log/auth.log
```