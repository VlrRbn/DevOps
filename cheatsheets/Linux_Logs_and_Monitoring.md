# Linux_Logs_and_Monitoring

---

## Системные логи (journalctl)

| Команда | Что делает |
| --- | --- |
| `journalctl -xe` | Последние ошибки |
| `journalctl -b` | Логи с текущей загрузки |
| `journalctl -k` | Логи ядра (dmesg) |
| `journalctl -u nginx` | Логи конкретного сервиса |
| `journalctl -u ssh -n 100` | Последние 100 строк |
| `journalctl -u ssh -f` | Follow (как tail -f) |
| `journalctl --since "2025-09-01 10:00"` | С фильтром по времени |
| `journalctl -p err` | Только ошибки |
| `journalctl --disk-usage` | Размер базы логов |
| `journalctl --vacuum-time=7d` | Чистка старше 7 дней |

---

## Классические логи (/var/log)

| Файл | Что в нём |
| --- | --- |
| `/var/log/syslog` | Общая система (Ubuntu/Debian) |
| `/var/log/auth.log` | Лог авторизаций (ssh, sudo) |
| `/var/log/kern.log` | Лог ядра |
| `/var/log/dpkg.log` | Установка пакетов |
| `/var/log/nginx/access.log` | Доступы к nginx |
| `/var/log/nginx/error.log` | Ошибки nginx |

Читать логи:

```bash
less /var/log/syslog
tail -n 50 /var/log/auth.log
tail -f /var/log/nginx/error.log
```

---

## Поиск в логах

| Команда | Что делает |
| --- | --- |
| `grep -i error /var/log/syslog` | Ищем ошибки |
| `grep -E "error|fail" file.log` | Несколько паттернов |
| `zgrep ssh /var/log/auth.log.*.gz` | Поиск в сжатых логах |
| `awk '{print $1,$2,$3}' /var/log/syslog` | Разбор по колонкам |
| `less +F file.log` | Следить за обновлением |

---

## Мониторинг ресурсов

| Инструмент | Что показывает |
| --- | --- |
| `top` | CPU, память, процессы |
| `htop` | Красиво + дерево процессов |
| `atop` | CPU, RAM, диски, сеть (история) |
| `glances` | Всё в одном |
| `vmstat 1` | CPU, память, IO |
| `iostat -x 1` | Диски (sysstat) |
| `sar -u 1 5` | CPU нагрузка (sysstat) |
| `sar -r 1 5` | Память |

---

## Мониторинг сети

| Инструмент | Что показывает |
| --- | --- |
| `iftop` | Трафик по соединениям |
| `nload` | Входящий/исходящий трафик |
| `ip -s link` | Ошибки, дропы по интерфейсам |
| `ss -s` | Статистика TCP/UDP |
| `netstat -i` | Интерфейсы (устарело, но встречается) |

---

## Мониторинг сервисов

| Инструмент | Что делает |
| --- | --- |
| `systemctl status nginx` | Статус сервиса |
| `journalctl -u nginx -f` | Логи в реальном времени |
| `curl -I http://localhost` | Проверить HTTP |
| `ss -tulpn | grep :80` | Проверить, слушает ли порт |

---

## Практикум

1. Смотреть ошибки systemd за сегодня:

```bash
journalctl -p err --since today
```

1. Найти все ssh-авторизации:

```bash
grep "Accepted" /var/log/auth.log
```

1. Найти все ошибки nginx:

```bash
grep -i error /var/log/nginx/error.log
```

1. Смотреть трафик по соединениям:

```bash
sudo iftop -i wlo1
```

1. Проверить нагрузку по CPU и памяти:

```bash
htop
```

---

## Security Checklist

- Логи должны храниться **persistently** (`/var/log/journal`).
- Не давать «ротироваться» критичным логам слишком быстро.
- Проверять `/var/log/auth.log` каждый день.
- Использовать `fail2ban` для sshd.
- Следить за размером логов (`du -sh /var/log/*`).

---

## Быстрые блоки

```bash
# Последние ошибки в системе
journalctl -p err -n 50

# Логи ядра
dmesg | tail -n 20

# Смотреть лог с обновлением
tail -f /var/log/syslog

# CPU/память
top

# Сеть по соединениям
sudo iftop -i wlo1
```