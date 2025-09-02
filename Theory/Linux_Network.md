# Linux_Network

---

## Интерфейсы и адреса

| Команда | Что делает | Пример |
| --- | --- | --- |
| `ip a` | Показать интерфейсы и IP | Быстрый обзор адресов |
| `ip -br a` | Краткий вывод адресов | Быстрее смотреть статус |
| `ip -br link` | Краткий статус линка | Видно `UP/LOWER_UP`, carrier |
| `sudo ip link set wlo1 up` | Поднять интерфейс | Включить карту |
| `sudo ip addr add 192.168.1.10/24 dev wlo1` | Добавить адрес | Ручной статический IP |
| `sudo ip route replace default via 192.168.1.1 dev wlo1` | Назначить шлюз | Добавить/заменить default |
| `ip route` | Таблица маршрутов | Проверить gateway/метрики |
| `ip route get 1.1.1.1` | Какой маршрут сработает | Покажет iface/шлюз |
| `ip -s link` | RX/TX, ошибки/дропы | Диагностика L2 |
| `ip neigh` | ARP/ND таблица | Видно ли шлюз |
| `iw dev wlo1 link` | Статус Wi-Fi линка | SSID, сигнал, bitrate |
| `resolvectl status` | DNS, search-домен | Проверка резолвера |

`ls /sys/class/net` —  список интерфейсов

`nmcli device status` — посмотреть статус с NetworkManager

---

## Проверка соединений

| Команда | Что делает | Пример |
| --- | --- | --- |
| `ping -c3 8.8.8.8` | Проверить ICMP до IP | Есть ли доступ в интернет |
| `ping -c3 google.com` | Проверить DNS+ICMP | Работает ли имя |
| `resolvectl query host` | Чистая проверка DNS | Альт: `dig +short host` |
| `nc -vz -w3 host 22` | Проверка TCP-порта (SSH) | Доступность ssh |
| `curl -I https://site.com` | HTTP-заголовки | Проверка веба |
| `wget --spider https://site.com` | Проверка доступности URL | Легко в скриптах |
| `traceroute host` | Маршрут до хоста | Где обрыв |
| `mtr -rw host` | Трассировка + статистика | Живая диагностика |

---

## Сокеты и процессы

| Команда | Что делает | Пример |
| --- | --- | --- |
| `ss -tulpn` | TCP/UDP + порты + PID | Кто слушает |
| `ss -ltnp` | Только **TCP LISTEN** + PID | Серверные TCP-порты |
| `ss -lunp` | Только **UDP** + PID |  |
| `ss -H state established` | Активные соединения | Живые TCP-сессии, dport = :443 |
| `ss -o state listening '( sport = :22 )'` | Фильтр по порту | Проверка SSH: слушает ли локально `:22`. |
| `lsof -i :80` | Кто держит порт 80 | Удобно увидеть путь к бинарю |
| `fuser -n tcp 80` | PID процесса на порту |  |

---

## DNS

| Команда | Что делает | Пример |
| --- | --- | --- |
| `dig google.com` | A-запись с деталями | IP адрес + TTL/сервер |
| `dig +short google.com` | Краткий вывод | Удобно для скриптов |
| `dig @8.8.8.8 site.com` | Указать сервер | Обходим локальный DNS |
| `dig AAAA site.com` | IPv6-адрес |  |
| `dig MX site.com +short` | Почтовые сервера | Приоритеты MX |
| `dig TXT site.com +short` | TXT (SPF/всякое) | Быстро посмотреть значение |
| `dig NS site.com +short` | Авторитетные NS |  |
| `resolvectl query site.com` | Через systemd-resolved | Кто отвечает, что ответил |
| `nslookup site.com` | Старый способ | Иногда всё ещё нужен |

---

## Firewall / Ports

### UFW (Ubuntu-friendly)

```bash
#убедиться, что стоит
sudo apt install -y ufw

#IPv6 тоже фильтруем
grep ^IPV6= /etc/ufw/ufw.conf || true
sudo sed -i 's/^IPV6=.*/IPV6=yes/' /etc/ufw/ufw.conf

#политика по умолчанию
sudo ufw default deny incoming
sudo ufw default allow outgoing

#доступ к себе
sudo ufw allow OpenSSH          # или: sudo ufw allow 22/tcp
sudo ufw limit 22/tcp           # лёгкий rate-limit
sudo ufw allow 80,443/tcp       # если гоняешь nginx

#включаем
sudo ufw enable
sudo ufw status verbose

#если что-то пошло не так
sudo ufw disable
sudo ufw reset   # полностью очистить правила (спросит подтверждение)
```

---

## Troubleshooting

| Ситуация | Команда |
| --- | --- |
| Нет интернета, пингуем IP | `ping -c3 8.8.8.8` |
| IP есть, DNS не работает | `dig google.com @8.8.8.8 +short` |
| Сервис не слушает | `sudo ss -ltnp '( sport = :8080 )’` |
| Подозрение на firewall | `sudo ufw status verbose` / `sudo iptables -L -n -v` |
| Проверить MTU | `ping -M do -s 1472 8.8.8.8` |
| Проверить скорость | `iperf3 -c host` |

---

## Network Manager / systemd-networkd

| Инструмент | Где |
| --- | --- |
| `nmcli` | NetworkManager (desktop/server Ubuntu) |
| `nmtui` | TUI для NM |
| `systemctl status systemd-networkd` | Минималистичные серверы |
| Конфиги | `/etc/netplan/*.yaml` |

Кто управляет сетью сейчас

```bash
systemctl is-active NetworkManager
systemctl is-active systemd-networkd
sudo netplan get | sed -n '1,80p'     # какой renderer указан
nmcli device status                   # если NM активен
networkctl list                       # если networkd активен
resolvectl status                     # DNS/домен поиска
```

- **Desktop** обычно: `renderer: NetworkManager`
- **Server (минималка)**: `renderer: networkd`

---

## Практикум

1. **Кто слушает на 22-м порту:**

```bash
ss -tulpn | grep :22
```

1. **Проверить сайт:**

```bash
curl -I https://example.com
```

1. **Проброс порта для сервиса:**

```bash
sudo ufw status verbose
```

1. **Диагностика DNS:**

```bash
dig +trace site.com
```

1. **Трассировка до Google:**

```bash
mtr -rw 8.8.8.8
```

---

## 🛡️ Security Checklist

- Не слушать сервисы на `0.0.0.0`, если это не нужно.
- Минимизировать открытые порты (проверять `ss -tulpn`).
- Использовать UFW/nftables для базовой защиты.
- DNS лучше задавать явный (`1.1.1.1`, `8.8.8.8`).

---

## Быстрые блоки

```bash
# Все сетевые соединения
ss -tulpn

# Кратко об интерфейсах
ip -br a

# Проверка DNS
dig +short github.com

# Проверить маршрут
traceroute 8.8.8.8

# Диагностика firewall
sudo ufw status verbose
```