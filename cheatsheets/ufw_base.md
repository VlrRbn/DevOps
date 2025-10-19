# ufw_base (uncomplicated firewall)

---

## Основное

| Команда | Что делает |
| --- | --- |
| `sudo ufw status` | Проверить состояние (вкл/выкл + правила) |
| `sudo ufw status verbose` | Подробный статус |
| `sudo ufw enable` | Включить UFW |
| `sudo ufw disable` | Выключить UFW |
| `sudo ufw reload` | Перезагрузить правила без отключения |
| `sudo ufw reset` | Сбросить всё к заводским настройкам |

---

## Базовые правила

| Команда | Пример | Что делает |
| --- | --- | --- |
| `sudo ufw allow <порт>` | `sudo ufw allow 22` | Разрешить порт |
| `sudo ufw deny <порт>` | `sudo ufw deny 23` | Запретить порт |
| `sudo ufw delete allow <порт>` | `sudo ufw delete allow 22` | Удалить правило |
| `sudo ufw allow from <IP>` | `sudo ufw allow from 192.168.1.10` | Разрешить доступ от IP |
| `sudo ufw deny from <IP>` | `sudo ufw deny from 203.0.113.5` | Заблокировать IP |
| `sudo ufw allow from <IP> to any port <порт>` | `sudo ufw allow from 192.168.1.0/24 to any port 22` | Разрешить подсеть к порту |

---

## Протоколы

| Команда | Пример |
| --- | --- |
| `sudo ufw allow 80/tcp` | HTTP |
| `sudo ufw allow 53/udp` | DNS |
| `sudo ufw allow 443/tcp` | HTTPS |
| `sudo ufw allow 60000:61000/udp` | Диапазон портов (например, для FTP passive) |

---

## Полезные штуки

| Команда | Что делает |
| --- | --- |
| `sudo ufw default deny incoming` | Блокировать всё входящее по умолчанию |
| `sudo ufw default allow outgoing` | Разрешить всё исходящее по умолчанию |
| `sudo ufw app list` | Список доступных профилей приложений |
| `sudo ufw allow <имя_приложения>` | Например: `sudo ufw allow "OpenSSH"` |
| `sudo ufw logging on` | Включить логирование |
| `sudo ufw logging off` | Выключить логирование |

---

## Примеры боевых конфигов

### Минимальная конфигурация для SSH и веб-сервера

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow OpenSSH
sudo ufw allow 80,443/tcp
sudo ufw enable
sudo ufw status verbose
```

### Разрешить SSH только с конкретного IP

```bash
sudo ufw allow from 203.0.113.10 to any port 22 proto tcp
```

### Заблокировать всю подсеть

```bash
sudo ufw deny from 10.0.0.0/8
```

---

После каждого изменения:

```bash
sudo ufw reload
sudo ufw status numbered
```

Можно потом удалить конкретное правило по номеру:

```bash
sudo ufw delete <номер>
```