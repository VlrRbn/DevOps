# network

---

## Интерфейсы и адреса

| Команда | Что делает | Пример/Почему |
| --- | --- | --- |
| `ip a` | Показать интерфейсы и IP | Быстрый обзор адресов |
| `ip -br a` | Краткий вывод адресов | Быстрее смотреть статус |
| `ip -br link` | Краткий статус линка | Видно `UP/LOWER_UP`, carrier |
| `sudo ip link set <IFNAME> up` | Поднять интерфейс | Включить карту |
| `sudo ip addr add 192.168.1.10/24 dev <IFNAME>` | Добавить адрес | Ручной статический IP |
| `ip route` | Таблица маршрутов | Проверить gateway/метрики |
| `ip route get 1.1.1.1` | Какой маршрут сработает | Покажет iface/шлюз |
| `ip -6 route` | IPv6-маршруты | Консистентно с IPv6 |
| `ip -s link` | RX/TX, ошибки/дропы | Диагностика L2 |
| `ip neigh` | ARP/ND таблица | Видно ли шлюз |
| `iw dev <IFNAME> link` | Статус Wi‑Fi линка | SSID, сигнал, bitrate |
| `ethtool eth0` | Линк‑скорость/дуплекс/дропы | Дополнение к `ip -s link` |
| `resolvectl status` | DNS, search‑домен | Проверка резолвера |

`ls /sys/class/net` — список интерфейсов

`nmcli device status` — статус устройств в NetworkManager

---

## Проверка соединений

| Команда | Что делает | Пример/Почему |
| --- | --- | --- |
| `ping -c3 8.8.8.8` | ICMP до IP | Есть ли доступ в интернет |
| `ping -c3 google.com` | DNS+ICMP | Работает ли имя |
| `ping -6 -c3 ipv6.google.com` | IPv6 ICMP | Проверка IPv6 |
| `resolvectl query example.com` | Чистая проверка DNS | Альт: `dig +short example.com` |
| `resolvectl flush-caches` | Сброс кэша DNS | После правок/тестов |
| `nc -vz -w3 host 22` | Проверка TCP‑порта (SSH) | Доступность SSH |
| `curl -I https://site.com` | HTTP‑заголовки | Быстрая проверка веба |
| `wget --spider https://site.com` | Проверка URL | Удобно в скриптах |
| `traceroute host` | Маршрут до хоста (UDP) | Где обрыв |
| `traceroute -T -p 443 host` | TCP‑трассировка к 443 | Полезнее при фильтрах |
| `mtr -rw host` | Трассировка + статистика | Живая диагностика |
| `mtr --tcp host` | TCP‑MTR | К 443/22 и т.п. |

---

## Сокеты и процессы

Примечание: без sudo PID/имя процесса могут не показываться.

| Команда | Что делает | Пример/Почему |
| --- | --- | --- |
| `ss -tulpn` | TCP/UDP + порты + PID | Кто слушает |
| `ss -ltnp` | Только **TCP LISTEN** + PID | Серверные TCP‑порты |
| `ss -lunp` | Только **UDP** + PID | UDP‑службы |
| `ss -H state established` | Активные TCP‑сессии | Кто общается сейчас |
| `ss -H state established '( dport = :443 )'` | Фильтр по dport | Живые HTTPS‑сессии |
| `ss -6 -ltn` | IPv6‑слушатели | Быстрая IPv6‑проверка |
| `ss -o state listening '( sport = :22 )'` | Фильтр по *sport* | Проверка «слушает ли SSH» |
| `lsof -i :80` | Кто держит порт 80 | Видно путь к бинарю |
| `fuser -n tcp 80` | PID процесса на порту | Альтернатива |

---

## DNS

| Команда | Что делает | Пример/Почему |
| --- | --- | --- |
| `dig example.com` | A‑запись с деталями | IP + TTL/сервер |
| `dig +short example.com` | Краткий вывод | Удобно для скриптов |
| `dig @8.8.8.8 site.com` | Указать сервер | Обойти локальный DNS |
| `dig AAAA site.com` | IPv6‑адрес | Проверка IPv6 |
| `dig MX site.com +short` | Почтовые сервера | Приоритеты MX |
| `dig TXT site.com +short` | TXT (SPF/и т.д.) | Быстрый просмотр |
| `dig NS site.com +short` | Авторитетные NS | Верификация делегирования |
| `resolvectl query site.com` | Через systemd‑resolved | Кто ответил и что |
| `nslookup site.com` | Старый способ | Иногда нужен |
| `ls -l /etc/resolv.conf` | Кто управляет резолвером | symlink → resolved/NM |

---

## Firewall / Ports

### UFW (Ubuntu‑friendly)

```bash
# убедиться, что стоит
sudo apt install -y ufw

# IPv6 тоже фильтруем
grep ^IPV6= /etc/ufw/ufw.conf || true
sudo sed -i 's/^IPV6=.*/IPV6=yes/' /etc/ufw/ufw.conf

# политика по умолчанию
sudo ufw default deny incoming
sudo ufw default allow outgoing

# доступ к себе
sudo ufw allow OpenSSH          # или: sudo ufw allow 22/tcp
sudo ufw limit 22/tcp           # лёгкий rate‑limit
sudo ufw allow 80,443/tcp       # если гоняешь nginx

# включаем и смотрим
sudo ufw enable
sudo ufw logging on
sudo ufw status numbered

# удалить правило по номеру
sudo ufw delete <N>

# если что‑то пошло не так
sudo ufw disable
sudo ufw reset   # полностью очистить правила (спросит подтверждение)
```

### nftables (современный стек)

```bash
# посмотреть реальную картину правил
sudo nft list ruleset

# Важно: не мешать руками iptables и nftables одновременно.
# На новых Ubuntu iptables может быть «мостом» к nft, что путает вывод.
# Warning: table ip filter is managed by iptables-nft, do not touch!
```

---

## Troubleshooting

| Ситуация | Команда |
| --- | --- |
| Нет интернета, пингуем IP | `ping -c3 8.8.8.8` |
| IP есть, DNS не работает | `dig google.com @8.8.8.8 +short` |
| Сервис не слушает | `sudo ss -ltnp '( sport = :8080 )'` |
| Подозрение на firewall | `sudo ufw status verbose` / `sudo nft list ruleset` |
| Проверить MTU | `ping -M do -s 1472 8.8.8.8` |
| Проверить скорость | `iperf3 -c host` / `iperf3 -R -c host` |
| Сниффинг DNS/UDP | `sudo tcpdump -n -i <iface> port 53 -vvv -c 20` |

---

## Network Manager / systemd‑networkd

| Инструмент | Где |
| --- | --- |
| `nmcli` | NetworkManager (desktop/server Ubuntu) |
| `nmtui` | TUI для NM |
| `systemctl status systemd-networkd` | Минималистичные серверы |
| Конфиги | `/etc/netplan/*.yaml` |

**Кто управляет сетью сейчас**

```bash
systemctl is-active NetworkManager
systemctl is-active systemd-networkd
sudo netplan get | sed -n '1,80p'     # какой renderer указан
nmcli device status                   # если NM активен
networkctl list                       # если networkd активен
resolvectl status                     # DNS/домен поиска

#**Desktop** renderer: NetworkManager
#**Server** renderer: networkd
```

**Безопасное применение netplan (удалённые сервера):**

```bash
sudo netplan try       # применит и откатит, если связь упадёт
sudo netplan apply     # если всё ок — закрепляем
```

---

## Подводные камни

- Без `sudo` `ss`/`lsof` могут не показать PID/имя процесса.
- `traceroute` по умолчанию UDP — для реальных сервисов лучше `T -p <port>`.
- На новых Ubuntu `iptables` часто через nft — проверять `nft list ruleset`.
- `netplan apply` удалённо может отрубить сеть. Сначала `netplan try`.
- `ping` может быть фильтрован — проверять TCP‑доступ `nc -vz`.

---

## Практикум

1. **Кто слушает на 22‑м порту**
    
    ```bash
    ss -tulpn | grep :22
    ```
    

2. **Проверить сайт**
    
    ```bash
    curl -I https://example.com
    ```
    

3. **Проверка правил firewall**
    
    ```bash
    sudo ufw status numbered
    # при необходимости открыть порт сервиса
    sudo ufw allow 8080/tcp
    ```
    

4. **Диагностика DNS**
    
    ```bash
    dig +trace site.com
    resolvectl query site.com
    ```
    

5. **Трассировка до Google**
    
    ```bash
    mtr --tcp 8.8.8.8
    ```
    

6. **Проверить реальный маршрут**
    
    ```bash
    ip route get 1.1.1.1
    ```
    

7. **Применить сетевые изменения безопасно (netplan)**
    
    ```bash
    sudo netplan try && sudo netplan apply
    ```
    

---

## Security Checklist

- Не слушать сервисы на `0.0.0.0`, если это не нужно.
- Минимизировать открытые порты (проверять `ss -tulpn`).
- Включить UFW с политикой *deny incoming*, вести логирование (`ufw logging on`).
- Не мешать вручную iptables и nftables одновременно.
- Ограничить SSH: `ufw limit 22/tcp`, ключевая аутентификация, смена порта ≠ безопасность.
- Следить за `:443/:80` — только необходимые сервисы.

---

## Быстрые блоки

```bash
# Все сетевые соединения
ss -tulpn

# Кратко об интерфейсах
ip -br a

# Проверка DNS
dig +short github.com
resolvectl flush-caches

# Проверить маршрут и кто его обслужит
traceroute 8.8.8.8
ip route get 1.1.1.1

# Диагностика firewall
sudo ufw status numbered
sudo nft list ruleset

# Wi‑Fi список сетей
nmcli dev wifi list
```