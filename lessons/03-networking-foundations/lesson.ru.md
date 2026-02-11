# lesson_03

# Сетевые Основы: IP, DNS, Маршруты и Диагностика

**Date:** 2025-08-21  
**Topic:** IP-адресация, DNS, маршрутизация и базовая сетевая диагностика  
**Daily goal:** Понять ключевые сетевые концепции и пройти минимальный, практичный сценарий диагностики сети.

---

## 1. Базовые Сетевые Концепции

### IP-адрес

IP-адрес идентифицирует узел в сети.

- **IPv4** пример: `192.168.1.12`
- **IPv6** пример: `2001:db8:1::12`

У хоста может быть несколько адресов на одном интерфейсе.

### Приватные и публичные адреса

- **Приватные диапазоны IPv4** (не маршрутизируются напрямую в интернет):
  - `10.0.0.0/8`
  - `172.16.0.0/12`
  - `192.168.0.0/16`
- **Публичный IPv4**: глобально маршрутизируемый адрес.

### DNS - Domain Name System

DNS переводит доменные имена (например, `google.com`) в IP-адреса.

Упрощенный порядок резолвинга:

1. Локальные источники (`/etc/hosts`)
2. Настроенный DNS-резолвер
3. DNS-серверы

### Маршрутизация и default gateway

Маршрутизация определяет, куда отправлять пакеты.

- В рамках той же подсети трафик идет напрямую.
- Внешний трафик идет через default gateway.

---

## 2. Приоритет Команд (Что Учить Сначала)

### Core (обязательно сейчас)

- `ip -br addr`
- `ip route`
- `ping -c 4 1.1.1.1`
- `ping -c 4 google.com`
- `traceroute -n 1.1.1.1`
- `dig +short google.com` **или** `nslookup google.com`

### Optional (после core)

- `ip link`
- `resolvectl status`
- `curl -I https://example.com`
- `wget --spider https://example.com`
- временный override через `/etc/hosts`

### Advanced (позже)

- `dig google.com A/AAAA/NS/MX`
- `dig +trace google.com`
- `mtr -rw -c 10 1.1.1.1`

---

## 3. Core Команды: Зачем и Когда

### `ip -br addr`

- **Что показывает:** интерфейсы, их состояние и IP-адреса.
- **Зачем нужно:** первый чек, когда "сеть не работает".
- **Когда использовать:** нужно подтвердить, что у активного интерфейса есть IP.

```bash
leprecha@Ubuntu-DevOps:~$ ip -br addr
lo               UNKNOWN        127.0.0.1/8 ::1/128
wlo1             UP             192.168.1.12/24 2001:db8:1::12/64 fe80::e02:7af1:917b:6b02/64
```

### `ip route`

- **Что показывает:** таблицу маршрутизации и default gateway.
- **Зачем нужно:** нет default route -> интернет обычно недоступен.
- **Когда использовать:** ping до внешнего IP не проходит.

```bash
leprecha@Ubuntu-DevOps:~$ ip route
default via 192.168.1.254 dev wlo1 proto dhcp src 192.168.1.12 metric 600
192.168.1.0/24 dev wlo1 proto kernel scope link src 192.168.1.12 metric 600
```

### `ping`

- **Что показывает:** доступность узла и задержку.
- **Зачем нужно:** отделяет "сеть не работает" от "DNS не работает".
- **Когда использовать:** самый первый тест связности.

```bash
leprecha@Ubuntu-DevOps:~$ ping -c 4 1.1.1.1
leprecha@Ubuntu-DevOps:~$ ping -c 4 google.com
```

Интерпретация:

- ping до IP работает, до домена нет -> скорее всего проблема DNS.
- оба не работают -> проблема канала/маршрута/firewall.

### `traceroute -n`

- **Что показывает:** путь (hops) до целевого узла.
- **Зачем нужно:** помогает понять, где трафик останавливается.
- **Когда использовать:** ping не проходит или задержка нестабильна.

```bash
leprecha@Ubuntu-DevOps:~$ traceroute -n 1.1.1.1
traceroute to 1.1.1.1 (1.1.1.1), 30 hops max, 60 byte packets
 1  192.168.1.254  4.4 ms  4.2 ms  4.1 ms
 2  95.44.248.1    6.6 ms  6.8 ms  7.0 ms
 3  1.1.1.1        8.9 ms  9.1 ms  9.0 ms
```

`* * *` на отдельных хопах может быть нормой (фильтрация/rate-limit).

### `dig +short` или `nslookup`

- **Что показывает:** DNS-ответ (домен -> IP).
- **Зачем нужно:** подтверждает, работает ли резолвинг имен.
- **Когда использовать:** домен не открывается, но интернет может быть доступен.

```bash
leprecha@Ubuntu-DevOps:~$ dig +short google.com
leprecha@Ubuntu-DevOps:~$ nslookup google.com
```

Правило:

- `dig` -> удобнее для диагностики и скриптов.
- `nslookup` -> быстрый человекочитаемый ответ.

---

## 4. Optional Команды (После Core)

Эти команды не обязательны для первого прохода, но делают диагностику точнее.

### `ip link`

- **Что показывает:** низкоуровневые детали интерфейсов (состояние, MAC, MTU, флаги).
- **Зачем нужно:** помогает, когда интерфейс есть, но ведет себя нестабильно.
- **Когда использовать:** интерфейс виден в `ip -br addr`, но трафик все равно не проходит.

```bash
leprecha@Ubuntu-DevOps:~$ ip link
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 state UNKNOWN mode DEFAULT group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
2: wlo1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 state UP mode DORMANT group default qlen 1000
    link/ether e4:2d:56:e5:3f:14 brd ff:ff:ff:ff:ff:ff
```

### `resolvectl status`

- **Что показывает:** активный DNS-резолвер, DNS-серверы и DNS-scopes по интерфейсам.
- **Зачем нужно:** видно, какой DNS реально используется системой прямо сейчас.
- **Когда использовать:** DNS работает нестабильно или по-разному в разных сетях.

```bash
leprecha@Ubuntu-DevOps:~$ resolvectl status
Global
       Protocols: -LLMNR -mDNS -DNSOverTLS DNSSEC=no/unsupported
resolv.conf mode: stub

Link 3 (wlo1)
    Current Scopes: DNS
         Protocols: +DefaultRoute -LLMNR -mDNS -DNSOverTLS DNSSEC=no/unsupported
Current DNS Server: 192.168.1.254
       DNS Servers: 192.168.1.254 2001:4860:4860::8888
```

### `curl -I`

- **Что показывает:** только HTTP-заголовки ответа (статус, редирект, тип контента).
- **Зачем нужно:** подтверждает связность на уровне приложения, а не только ICMP.
- **Когда использовать:** ping работает, но поведение сайта непонятно.

```bash
leprecha@Ubuntu-DevOps:~$ curl -I https://google.com
HTTP/2 301
location: https://www.google.com/
content-type: text/html; charset=UTF-8
```

### `wget --spider`

- **Что показывает:** доступность URL без скачивания содержимого.
- **Зачем нужно:** быстрый check для автоматизации и мониторинга endpoint.
- **Когда использовать:** нужен быстрый up/down тест URL.

```bash
leprecha@Ubuntu-DevOps:~$ wget --spider https://example.com
Spider mode enabled. Check if remote file exists.
HTTP request sent, awaiting response... 200 OK
Remote file exists.
```

### Локальный override через `/etc/hosts` (временно)

- **Что делает:** принудительно задает локальный резолвинг имени на выбранный IP.
- **Зачем нужно:** удобно для теста до внесения реальной DNS-записи.
- **Когда использовать:** нужно локально проверить имя, которого еще нет в DNS.

Добавить запись:

```bash
echo "1.2.3.4 mytest.local" | sudo tee -a /etc/hosts
```

Проверить сопоставление:

```bash
getent hosts mytest.local
```

Удалить запись (безопасно для новичка, вручную):

```bash
sudo nano /etc/hosts
# удалить строку с mytest.local, сохранить, выйти
```

---

## 5. Advanced Команды (Глубокая Диагностика)

### `dig` с фокусом на типы записей

- **Что показывает:** полный DNS-ответ с типом записи, TTL и данными сервера.
- **Зачем нужно:** помогает диагностировать проблему по конкретному типу записи, а не только name->IP.
- **Когда использовать:** сервис частично работает (например, web есть, mail нет).

```bash
leprecha@Ubuntu-DevOps:~$ dig google.com A
leprecha@Ubuntu-DevOps:~$ dig google.com AAAA
leprecha@Ubuntu-DevOps:~$ dig google.com NS
leprecha@Ubuntu-DevOps:~$ dig google.com MX
leprecha@Ubuntu-DevOps:~$ dig +short google.com
```

### Запрос к конкретному DNS-серверу `dig @server`

- **Что показывает:** ответ выбранного резолвера (не системного по умолчанию).
- **Зачем нужно:** можно сравнить результаты разных DNS-серверов.
- **Когда использовать:** один DNS-сервер резолвит, другой нет.

```bash
leprecha@Ubuntu-DevOps:~$ dig @1.1.1.1 google.com A
leprecha@Ubuntu-DevOps:~$ dig @8.8.8.8 google.com A
```

### `dig +trace`

- **Что показывает:** полный путь DNS-делегирования от root до authoritative серверов.
- **Зачем нужно:** помогает найти, на каком этапе ломается резолвинг.
- **Когда использовать:** обычный `dig` возвращает ошибку или странный результат.

```bash
leprecha@Ubuntu-DevOps:~$ dig +trace google.com
```

### `mtr`

- **Что показывает:** живую статистику потерь и задержки по каждому hop.
- **Зачем нужно:** лучше одноразового traceroute при плавающих проблемах сети.
- **Когда использовать:** периодические лаги или случайные packet loss.

```bash
leprecha@Ubuntu-DevOps:~$ mtr -rw -c 10 1.1.1.1
```

---

## 6. Минимальная Практика (Core Path)

### Цель

Пройти самый полезный troubleshooting-сценарий без перегруза.

### Шаги

1. Сохранить локальное сетевое состояние.
2. Проверить связность до IP и домена.
3. Проверить маршрут.
4. Проверить DNS-резолвинг.

```bash
mkdir -p ~/net-lab

ip -br addr > ~/net-lab/ip_addr.txt
ip route > ~/net-lab/ip_route.txt

ping -c 4 1.1.1.1
ping -c 4 google.com
traceroute -n 1.1.1.1

dig +short google.com
# альтернатива:
# nslookup google.com
```

Чеклист проверки:

- существует `~/net-lab/ip_addr.txt`
- существует `~/net-lab/ip_route.txt`
- хотя бы одна DNS-команда возвращает IP-адреса

---

## 7. Расширенная Практика (Optional + Advanced)

1. Сохранить статус DNS-резолвера:

```bash
resolvectl status > ~/net-lab/dns_status.txt
```

2. Проверить HTTP-доступность:

```bash
curl -I https://google.com
wget --spider https://example.com
```

3. Протестировать локальный override через `/etc/hosts`:

```bash
echo "1.2.3.4 mytest.local" | sudo tee -a /etc/hosts
getent hosts mytest.local
sudo nano /etc/hosts
```

4. Выполнить углубленные DNS-проверки:

```bash
dig google.com A
dig google.com NS
dig google.com MX
dig @1.1.1.1 google.com A
dig +trace google.com
```

5. Снять snapshot качества маршрута:

```bash
mtr -rw -c 10 1.1.1.1 > ~/net-lab/mtr_1_1_1_1.txt
```

---

## 8. Итоги Урока

- **Что изучил:** основы IP, private/public адреса, базовый путь DNS-резолвинга и роль default gateway.
- **Что отработал на практике:** core-диагностику (`ip`, `ping`, `traceroute`, DNS-check), а также optional и advanced команды для глубокой проверки.
- **Ключевая идея:** сначала проверяем link и route, затем DNS, потом поведение приложения и путь резолвинга.
- **Что нужно повторить:** чтение вывода резолвера, сравнение типов DNS-запросов и интерпретацию потерь/задержек в `mtr`.
- **Следующий шаг:** сделать скрипт с двумя режимами: `core-check` и `deep-check`.
