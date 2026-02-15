# lesson_09

# Networking Deep Dive: `iproute2`, `ss`, `dig`, `tcpdump`, `ufw`, `netns`

**Date:** 2025-09-15  
**Topic:** Глубокая диагностика сети: сокеты, DNS, packet capture, базовый firewall и изолированные сети через namespaces.  
**Daily goal:** Научиться разбирать сетевую проблему по цепочке `interface -> route -> socket -> dns -> packet -> policy` и безопасно воспроизводить сценарии в лабе.
**Bridge:** [05-07 Operations Bridge](../00-foundations-bridge/05-07-operations-bridge.ru.md) — база shell/systemd-практик, которая используется в этом уроке.
**Legacy:** исходный старый конспект сохранен в `lessons/09-networking-deep-dive/lesson_09(legacy).md`.

---

## 1. Базовые Концепции

### 1.1 Диагностическая цепочка: от симптома к причине

Практичный порядок для triage:

1. Есть ли интерфейс/адрес/маршрут (`ip`)?
2. Кто слушает порт (`ss`)?
3. Резолвится ли имя (`dig`/`resolvectl`)?
4. Что реально летит по сети (`tcpdump`)?
5. Не режет ли policy (`ufw`)?

Такой порядок снижает хаотичный перебор команд.

### 1.2 Почему `iproute2` — основа

`iproute2` (`ip`, `ss`) заменил legacy-инструменты (`ifconfig`, `netstat`):

- единый стиль вывода;
- лучше фильтры;
- лучше подходит для современных Linux-систем.

### 1.3 Сокеты vs порты

- порт — это номер endpoint (например `:22`);
- сокет — сочетание протокола, локального/удаленного адреса и порта;
- процесс может слушать порт, но проблема может быть в DNS/маршруте/firewall.

### 1.4 DNS как часть цепочки, а не отдельный мир

Если сервис "не открывается", проблема часто не в HTTP, а раньше:

- неверный DNS-ответ;
- неправильный resolver;
- недоступность UDP/TCP 53;
- stale cache.

### 1.5 Packet capture: зачем нужен `tcpdump`

`tcpdump` нужен, когда логов мало и нужно увидеть факт трафика:

- был ли SYN/ответ;
- уходит ли DNS-запрос;
- есть ли retry/timeouts.

Важно: capture должен быть коротким и с фильтрами.

### 1.6 Firewall безопасность

`ufw` полезен, но опасен при удаленной работе:

- сначала формируем правила,
- затем включаем,
- сразу проверяем критичные каналы доступа.

На удаленном сервере без out-of-band доступа включать firewall нужно особенно аккуратно.

### 1.7 Зачем `netns` в этом уроке

`ip netns` дает безопасную песочницу для сетевых экспериментов:

- отдельные интерфейсы и маршруты;
- повторяемый стенд "два хоста" без VM;
- можно быстро создать/удалить лабу.

---

## 2. Приоритет Команд (Что Учить Сначала)

### Core (обязательно сейчас)

- `ip -br a`
- `ip r`
- `ss -tulpn`
- `ss -tan state established`
- `dig +short A/AAAA <domain>`
- `resolvectl status`
- `tcpdump -i <if> -w <file.pcap> 'filter'`
- `ufw status verbose`

### Optional (после core)

- `ss` с фильтрами `( sport = :N or dport = :N )`
- `curl -w` для timing-метрик
- `dig +noall +answer`
- `dig +trace`
- `tcpdump -r <file.pcap>`

### Advanced (уровень эксплуатации)

- аккуратный baseline policy в `ufw` + проверка после apply
- `ip netns` + `veth` как мини-сеть для воспроизводимых тестов
- вынос повторяемых проверок в CLI-скрипты

---

## 3. Core Команды: Что / Зачем / Когда

### `ip -br a`

- **Что:** краткий список интерфейсов и адресов.
- **Зачем:** проверить L3-базу хоста за один взгляд.
- **Когда:** всегда в начале сетевого triage.

```bash
ip -br a
```

### `ip r`

- **Что:** таблица маршрутизации.
- **Зачем:** понять default route и пути в подсети.
- **Когда:** если сервис недоступен по IP.

```bash
ip r
```

### `ss -tulpn`

- **Что:** кто слушает TCP/UDP-порты и каким процессом.
- **Зачем:** проверить "поднят ли сервис" на нужном порту.
- **Когда:** после проверки интерфейсов/маршрутов.

```bash
sudo ss -tulpn | head -n 30
```

### `ss -tan state established`

- **Что:** активные TCP-сессии.
- **Зачем:** увидеть реальные peer-соединения.
- **Когда:** анализ "кто с кем общается".

```bash
sudo ss -tan state established | head -n 30
```

### `dig +short A/AAAA <domain>`

- **Что:** быстрый DNS-ответ по нужному типу записи.
- **Зачем:** проверить базовую резолюцию без лишнего вывода.
- **Когда:** если доступ по имени не работает.

```bash
dig +short A google.com
dig +short AAAA google.com
```

### `resolvectl status`

- **Что:** текущие resolvers/search-domains (systemd-resolved).
- **Зачем:** понять, кто именно отвечает за DNS на хосте.
- **Когда:** при спорных/нестабильных DNS-результатах.

```bash
resolvectl status | sed -n '1,120p'
```

### `tcpdump` capture to file

- **Что:** запись пакетов в pcap.
- **Зачем:** зафиксировать сетевые факты для offline-разбора.
- **Когда:** когда логов приложений недостаточно.

```bash
IF="$(ip -o route show to default | awk '{print $5; exit}')"
sudo timeout 8 tcpdump -i "$IF" -nn -s 0 -w /tmp/lesson09_https.pcap 'tcp port 443'
tcpdump -nn -r /tmp/lesson09_https.pcap | head -n 20
```

### `ufw status verbose`

- **Что:** текущее состояние firewall и policy.
- **Зачем:** убедиться, что правила соответствуют ожиданиям.
- **Когда:** до и после любых firewall-изменений.

```bash
sudo ufw status verbose
```

---

## 4. Optional Команды (После Core)

### `ss` по порту/процессу

- **Что:** точечная фильтрация по порту/процессу.
- **Зачем:** быстро убрать шум в большом выводе.
- **Когда:** расследование конкретного сервиса.

```bash
sudo ss -tulpn '( sport = :22 or sport = :80 )'
sudo ss -tulpn | grep -Ei 'nginx|ssh|docker' || true
```

### `curl -w` для timing

- **Что:** time-to-first-byte и этапы DNS/connect/TLS.
- **Зачем:** понять, где задержка в HTTP-цепочке.
- **Когда:** "сайт медленно открывается".

```bash
curl -sS -o /dev/null -L \
  -w '{"code":%{http_code},"dns":%{time_namelookup},"connect":%{time_connect},"tls":%{time_appconnect},"ttfb":%{time_starttransfer},"total":%{time_total}}\n' \
  https://google.com
```

### `dig +noall +answer` и `dig +trace`

- **Что:** компактный ответ и трассировка DNS-делегации.
- **Зачем:** понять не только что ответили, но и где ломается цепочка.
- **Когда:** спорные DNS-кейсы, split-horizon, подозрение на resolver.

```bash
dig +noall +answer A google.com
dig +trace google.com | sed -n '1,60p'
```

### `tcpdump` по DNS

- **Что:** capture только DNS-пакетов.
- **Зачем:** проверить, уходит ли запрос и есть ли ответ.
- **Когда:** DNS вроде настроен, но резолюция нестабильна.

```bash
IF="$(ip -o route show to default | awk '{print $5; exit}')"
sudo timeout 10 tcpdump -i "$IF" -vv -n 'udp port 53 or tcp port 53'
```

---

## 5. Advanced Темы (Ops-Grade)

### 5.1 Безопасный baseline UFW

Схема apply:

1. проверить текущий статус;
2. выставить default policy;
3. добавить явные allow-правила для критичных потоков;
4. включить firewall;
5. сразу проверить доступ.

```bash
sudo ufw status verbose || true
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow in on lo
sudo ufw allow out on lo
sudo ufw allow 22/tcp
sudo ufw enable
sudo ufw status numbered
```

Ограничение:

- на удаленном сервере делай это только при наличии безопасного плана отката.

### 5.2 Namespace-лаба как воспроизводимый стенд

Через `ip netns` + `veth` можно быстро поднять "два хоста":

- проверить ping между ними;
- поднять сервис в одной namespace;
- проверить доступ из второй namespace;
- удалить всё без следов в основной сети.

### 5.3 Скриптизация повторяемого triage

Повторяемые задачи из урока вынесены в скрипты:

- фильтрация сокетов;
- DNS quick-query;
- короткий packet capture;
- namespace mini-lab.

Это уменьшает риск ручных ошибок и ускоряет проверку.

---

## 6. Скрипты в Этом Уроке

Артефакты лежат в:

- `lessons/09-networking-deep-dive/scripts/`

Выставить execute-бит один раз:

```bash
chmod +x lessons/09-networking-deep-dive/scripts/*.sh
```

Проверка справки:

```bash
./lessons/09-networking-deep-dive/scripts/net-ports.sh --help
./lessons/09-networking-deep-dive/scripts/dns-query.sh --help
./lessons/09-networking-deep-dive/scripts/capture-http.sh --help
./lessons/09-networking-deep-dive/scripts/netns-mini-lab.sh --help
```

Короткие примеры запуска:

```bash
./lessons/09-networking-deep-dive/scripts/net-ports.sh --listen --process ssh
./lessons/09-networking-deep-dive/scripts/dns-query.sh google.com @1.1.1.1
./lessons/09-networking-deep-dive/scripts/capture-http.sh 6
./lessons/09-networking-deep-dive/scripts/netns-mini-lab.sh
```

---

## 7. Мини-Лаба (Core Path)

```bash
mkdir -p lessons/09-networking-deep-dive/labs/captures

ip -br a
ip r

sudo ss -tulpn | head -n 20
sudo ss -tan state established | head -n 20

dig +short A google.com
resolvectl status | sed -n '1,60p'

IF="$(ip -o route show to default | awk '{print $5; exit}')"
sudo timeout 5 tcpdump -i "$IF" -nn -s 0 -w /tmp/lesson09_core.pcap 'tcp port 443'
tcpdump -nn -r /tmp/lesson09_core.pcap | head -n 20
```

Checklist:

- видишь default route и активный интерфейс;
- понимаешь, какой процесс слушает нужный порт;
- можешь подтвердить, что DNS возвращает ожидаемый ответ;
- умеешь записать короткий pcap и прочитать его без root.

---

## 8. Расширенная Лаба (Optional + Advanced)

```bash
# 1) HTTP timing
curl -sS -o /dev/null -L \
  -w '{"code":%{http_code},"dns":%{time_namelookup},"connect":%{time_connect},"tls":%{time_appconnect},"ttfb":%{time_starttransfer},"total":%{time_total}}\n' \
  https://google.com

# 2) DNS deep checks
./lessons/09-networking-deep-dive/scripts/dns-query.sh google.com
./lessons/09-networking-deep-dive/scripts/dns-query.sh google.com @8.8.8.8

# 3) UFW baseline (только если понимаешь риск)
sudo ufw status verbose || true
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp
sudo ufw enable
sudo ufw status numbered

# 4) namespace mini-lab
./lessons/09-networking-deep-dive/scripts/netns-mini-lab.sh
```

---

## 9. Очистка

```bash
sudo ufw disable || true
sudo ip netns del blue 2>/dev/null || true
sudo ip netns del red 2>/dev/null || true
rm -f /tmp/lesson09_core.pcap
```

---

## 10. Итоги Урока

- **Что изучил:** рабочий flow глубокой сетевой диагностики через `ip`, `ss`, `dig`, `tcpdump`, `ufw`, `netns`.
- **Что практиковал:** triage сокетов/маршрутов, DNS-проверки, короткие packet captures, базовую firewall-политику и изолированную сетевую лабу.
- **Продвинутые навыки:** переход от ad-hoc команд к воспроизводимым скриптам и structured-debugging подходу.
- **Операционный фокус:** сначала сбор фактов, потом изменения; firewall-правки только с планом отката; capture с фильтрами и ограничением по времени.
- **Артефакты в репозитории:** `lessons/09-networking-deep-dive/scripts/`, `lessons/09-networking-deep-dive/scripts/README.md`.
