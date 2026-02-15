# lesson_10

# Networking (Part 2): NAT / DNAT / `netns` / UFW

**Date:** 2025-09-18  
**Topic:** `ip netns`, `veth`, IPv4 forwarding, `iptables` NAT/DNAT и безопасная работа с UFW.  
**Daily goal:** Научиться поднимать изолированную сеть в namespace, дать ей Интернет через NAT, пробросить сервис через DNAT и корректно всё убрать после эксперимента.
**Bridge:** [08-11 Networking + Text Bridge](../00-foundations-bridge/08-11-networking-text-bridge.ru.md) — расширенные пояснения и troubleshooting для уроков 8-11.
**Legacy:** исходный старый конспект сохранен в `lessons/10-networking-nat-dnat-netns-ufw/lesson_10(legacy).md`.

---

## 0. Prerequisites

Перед стартом проверь, что есть нужные утилиты:

```bash
command -v ip iptables sysctl curl python3
```

Опционально (для pcap):

```bash
command -v tcpdump || echo "install tcpdump if needed"
```

---

## 1. Базовые Концепции

### 1.1 Что именно решает этот урок

Мы строим локальный стенд "host <-> namespace" и проходим полный поток:

1. L3-связность внутри lab-сети;
2. выход namespace в Интернет (NAT/MASQUERADE);
3. вход на сервис namespace через хост (DNAT);
4. верификация пакетами/счетчиками;
5. безопасный cleanup.

### 1.2 NAT vs DNAT

- `SNAT/MASQUERADE`: меняет source адрес исходящего трафика (namespace -> WAN).
- `DNAT`: меняет destination адрес входящего трафика (host:8080 -> ns:8080).

### 1.3 Почему нужен `ip_forward`

Без `net.ipv4.ip_forward=1` хост не маршрутизирует пакеты между интерфейсами, и namespace не выйдет в Интернет через host.

### 1.4 FORWARD цепочка критична

Даже если NAT настроен, пакеты могут падать в `FORWARD`, если нет явного `ACCEPT` для нужных направлений.

### 1.5 Hairpin (localhost DNAT)

Чтобы `curl http://127.0.0.1:8080` на самом host попадал в namespace, нужен `DNAT` в `OUTPUT` и обычно `SNAT` в `POSTROUTING` на `veth0`.

### 1.6 UFW и удаленный доступ

UFW удобен для policy, но на remote-хостах опасен без плана отката. Сначала allow для SSH, потом enable.

### 1.7 Проверка успеха — только через факты

Успех подтверждаем не "кажется работает", а:

- ping/curl из namespace;
- `curl` на `127.0.0.1:8080`;
- counters в `iptables -L -v`.

---

## 2. Приоритет Команд (Что Учить Сначала)

### Core (обязательно сейчас)

- `ip netns add|exec|del`
- `ip link add ... type veth peer ...`
- `ip -n <ns> addr|route|link`
- `sysctl net.ipv4.ip_forward=1`
- `iptables -t nat -A POSTROUTING ... MASQUERADE`
- `iptables -t nat -A PREROUTING ... DNAT`
- `iptables -L -v -n` / `iptables -t nat -L -v -n`

### Optional (после core)

- `ufw status numbered`
- `ufw default deny incoming` + точечные allow
- `tcpdump -i <if> -w <pcap> 'filter'`
- `curl -I` smoke-check сервиса

### Advanced (уровень эксплуатации)

- идемпотентные apply-скрипты (`-C || -A`)
- state file для безопасного cleanup
- явное восстановление sysctl после лабы

---

## 3. Core Команды: Что / Зачем / Когда

### `ip netns add lab10`

- **Что:** создает изолированный network namespace.
- **Зачем:** безопасный стенд без VM.
- **Когда:** старт лаборатории.

```bash
sudo ip netns del lab10 2>/dev/null || true
sudo ip netns add lab10
```

### `ip link add veth0 type veth peer name veth1`

- **Что:** виртуальный Ethernet-кабель между host и namespace.
- **Зачем:** соединить две сетевые области.
- **Когда:** после создания namespace.

```bash
sudo ip link add veth0 type veth peer name veth1
sudo ip link set veth1 netns lab10
```

### Адресация и маршрут

- **Что:** даем IP обеим сторонам и default route в namespace.
- **Зачем:** базовая L3-связность.
- **Когда:** до NAT.

```bash
sudo ip addr add 10.10.0.1/24 dev veth0
sudo ip link set veth0 up

sudo ip -n lab10 addr add 10.10.0.2/24 dev veth1
sudo ip -n lab10 link set veth1 up
sudo ip -n lab10 link set lo up
sudo ip -n lab10 route add default via 10.10.0.1

sudo ip netns exec lab10 ping -c 1 10.10.0.1
```

### `sysctl` forwarding

- **Что:** включает маршрутизацию IPv4 и route_localnet для hairpin-сценария.
- **Зачем:** трафик должен проходить между интерфейсами host.
- **Когда:** до NAT/DNAT.

```bash
sudo sysctl -w net.ipv4.ip_forward=1
sudo sysctl -w net.ipv4.conf.veth0.route_localnet=1
```

### NAT (MASQUERADE)

- **Что:** подмена source адреса namespace-трафика на host WAN.
- **Зачем:** дать namespace выход в Интернет.
- **Когда:** после настройки маршрутизации.

```bash
IF="$(ip -o -4 route show default table main | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
sudo iptables -t nat -C POSTROUTING -s 10.10.0.0/24 -o "$IF" -j MASQUERADE 2>/dev/null || \
  sudo iptables -t nat -A POSTROUTING -s 10.10.0.0/24 -o "$IF" -j MASQUERADE
```

### DNAT (host:8080 -> ns:8080)

- **Что:** проброс входа на host порт в namespace сервис.
- **Зачем:** публикация сервиса из ns.
- **Когда:** после запуска сервиса в ns.

```bash
sudo iptables -t nat -C PREROUTING -p tcp --dport 8080 -j DNAT --to-destination 10.10.0.2:8080 2>/dev/null || \
  sudo iptables -t nat -A PREROUTING -p tcp --dport 8080 -j DNAT --to-destination 10.10.0.2:8080

sudo iptables -C FORWARD -p tcp -d 10.10.0.2 --dport 8080 -j ACCEPT 2>/dev/null || \
  sudo iptables -A FORWARD -p tcp -d 10.10.0.2 --dport 8080 -j ACCEPT
```

Почему команды выглядят "повторяющимися":

- это один и тот же идемпотентный шаблон: `-C` (check) + `|| -A` (append);
- если правило уже есть, `-C` успешен и `-A` не выполняется;
- если правила нет, `-C` падает и срабатывает `-A`;
- так setup можно запускать повторно без дубликатов.

---

## 4. Optional Команды (После Core)

### `OUTPUT` DNAT для localhost

Если тестируешь с host на `127.0.0.1:8080`, добавь:

```bash
sudo iptables -t nat -C OUTPUT -p tcp --dport 8080 -d 127.0.0.1 -j DNAT --to-destination 10.10.0.2:8080 2>/dev/null || \
  sudo iptables -t nat -A OUTPUT -p tcp --dport 8080 -d 127.0.0.1 -j DNAT --to-destination 10.10.0.2:8080
```

### Hairpin SNAT

```bash
sudo iptables -t nat -C POSTROUTING -o veth0 -p tcp -d 10.10.0.2 --dport 8080 -j SNAT --to-source 10.10.0.1 2>/dev/null || \
  sudo iptables -t nat -A POSTROUTING -o veth0 -p tcp -d 10.10.0.2 --dport 8080 -j SNAT --to-source 10.10.0.1
```

### UFW numbered rules

```bash
sudo ufw status verbose || true
sudo ufw status numbered || true
```

### Быстрый pcap

```bash
sudo timeout 10 tcpdump -i "$IF" -nn -w /tmp/lesson10_8080.pcap 'tcp port 8080'
```

### Что делать в Optional на практике

1. Сначала проверь базовый сценарий: `curl -I http://127.0.0.1:8080`.
2. Если не работает только localhost-путь, добавь `OUTPUT` DNAT.
3. Если после `OUTPUT` DNAT всё еще нестабильно, добавь hairpin `SNAT`.
4. Сделай контрольный `curl -I` и посмотри counters в NAT/FORWARD.
5. При работе с UFW: только чтение (`status numbered`) или точечные allow, без резкого `deny` на remote-host.

---

## 5. Advanced Темы (Ops-Grade)

### 5.1 Идемпотентный apply

Паттерн `iptables -C ... || iptables -A ...` позволяет повторно запускать сценарий без дублирования правил.

### 5.2 State file для cleanup

Сохраняем параметры (`NS`, `IF`, `SUBNET`, старые `sysctl`) в файл, чтобы cleanup знал, что именно убирать.

### 5.3 Policy-first

Сначала читаем текущие rules/policy/counters, потом меняем. После apply сразу делаем smoke-check.

### 5.4 Что делать в Advanced пошагово

1. Применить стенд скриптом:
`./lessons/10-networking-nat-dnat-netns-ufw/scripts/setup-netns-nat.sh`
2. Проверить связь и правила:
`./lessons/10-networking-nat-dnat-netns-ufw/scripts/check-netns-nat.sh`
3. Снять pcap на целевой порт и повторить запросы.
4. Сравнить counters до/после (увидеть рост в MASQUERADE/DNAT/FORWARD).
5. Полностью убрать стенд и вернуть sysctl:
`./lessons/10-networking-nat-dnat-netns-ufw/scripts/cleanup-netns-nat.sh`

### 5.5 Карта пути пакета (что где срабатывает)

Интернет из namespace:

```text
lab10 (10.10.0.2) -> veth1 -> veth0(host) -> FORWARD -> nat/POSTROUTING(MASQUERADE) -> WAN(IF)
```

Вход снаружи на host:8080:

```text
client -> host:8080 -> nat/PREROUTING(DNAT to 10.10.0.2:8080) -> FORWARD -> veth0 -> lab10
```

Локальный вызов на host `127.0.0.1:8080`:

```text
host process -> nat/OUTPUT(DNAT) -> routing -> nat/POSTROUTING(SNAT hairpin) -> veth0 -> lab10
```

### 5.6 Что делает `route_localnet=1` и когда он нужен

`net.ipv4.conf.veth0.route_localnet=1` разрешает special-case маршрут для локальных адресов (127/8) в hairpin-сценариях.  
Без него localhost-DNAT часто работает нестабильно или не работает вообще.

Проверка:

```bash
sysctl net.ipv4.conf.veth0.route_localnet
```

### 5.7 Диагностика по симптомам (быстрый выбор следующего шага)

| Симптом | Где смотреть | Частая причина | Что сделать |
|---|---|---|---|
| `ns -> gateway` не пингуется | `ip -n lab10 addr`, `ip link`, `ip route` | интерфейс/адрес/route не поднят | перепроверить адреса `10.10.0.1/24`, `10.10.0.2/24`, `default via 10.10.0.1` |
| `ns -> internet` не работает | `sysctl ip_forward`, `nat POSTROUTING`, `FORWARD` | нет forwarding/NAT/allow в FORWARD | включить `ip_forward`, добавить MASQUERADE и FORWARD ACCEPT |
| `curl 127.0.0.1:8080` не работает, а service в ns живой | `nat OUTPUT`, hairpin SNAT | отсутствует OUTPUT DNAT или SNAT | добавить OUTPUT DNAT и SNAT на `veth0` |
| DNAT rule есть, но трафик не доходит | `FORWARD -v`, `nat -v`, `tcpdump` | rule не матчится, неверный IF/порт | сверить интерфейс/порт, снять короткий pcap |
| После reboot "всё пропало" | `iptables -S`, `sysctl` | правила/параметры были временные | повторно применить setup или использовать persist-механику |

### 5.8 Как читать counters правильно

Шаблон:

1. Снять counters до теста:
`sudo iptables -t nat -L -v -n --line-numbers`
2. Выполнить 1-2 контрольных запроса (`curl`, `ping`).
3. Снять counters повторно.
4. Сравнить рост именно в целевых правилах (`DNAT`, `MASQUERADE`, `FORWARD ACCEPT`).

Если counters не растут:

- правило не матчится по интерфейсу/адресу/порту;
- трафик идёт по другому пути;
- пакет режется раньше по цепочке.

### 5.9 `iptables` backend: legacy vs nft

На современных системах `iptables` может работать поверх nft backend.  
Проблемы начинаются, когда правила вносятся одновременно через разные стеки без понимания текущего backend.

Проверить backend:

```bash
iptables --version
update-alternatives --display iptables 2>/dev/null || true
```

Практическое правило урока: в рамках одной лабы использовать один стек консистентно.

### 5.10 Что происходит после reboot

В этом уроке правила и sysctl применяются временно (runtime).  
После reboot они могут сброситься к системным defaults.

### 5.11 Безопасность DNAT (минимальный baseline)

Не делать слишком широкий проброс "для всех и отовсюду", если это не нужно.

Что ограничивать:

- ingress интерфейс (`-i "$IF"` где уместно);
- source сети/адреса для доступа;
- конкретный порт и протокол;
- временное окно правила (удалять после теста).

---

## 6. Скрипты в Этом Уроке

### Ручной Core-проход (1 раз сделать без скрипта)

Этот блок нужен, чтобы понять механику руками, а потом уже запускать автоматизацию.

```bash
# 1) netns + veth
sudo ip netns del lab10 2>/dev/null || true
sudo ip netns add lab10
sudo ip link add veth0 type veth peer name veth1
sudo ip link set veth1 netns lab10

# 2) адреса + route
sudo ip addr add 10.10.0.1/24 dev veth0
sudo ip link set veth0 up
sudo ip -n lab10 addr add 10.10.0.2/24 dev veth1
sudo ip -n lab10 link set veth1 up
sudo ip -n lab10 link set lo up
sudo ip -n lab10 route add default via 10.10.0.1

# 3) forwarding
sudo sysctl -w net.ipv4.ip_forward=1
sudo sysctl -w net.ipv4.conf.veth0.route_localnet=1

# 4) NAT/DNAT
IF="$(ip -o -4 route show default table main | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
sudo iptables -t nat -A POSTROUTING -s 10.10.0.0/24 -o "$IF" -j MASQUERADE
sudo iptables -t nat -A PREROUTING -p tcp --dport 8080 -j DNAT --to-destination 10.10.0.2:8080
sudo iptables -A FORWARD -p tcp -d 10.10.0.2 --dport 8080 -j ACCEPT

# 5) сервис + проверка
sudo ip netns exec lab10 bash -lc 'python3 -m http.server 8080 --bind 10.10.0.2 >/tmp/lab10_http.log 2>&1 &'
curl -sI http://127.0.0.1:8080 | head -n 5 || true
sudo iptables -t nat -L -v -n
```

После этого запусти скрипт `setup-netns-nat.sh` и сравни: скрипт делает те же шаги, но идемпотентно и с state-file для cleanup.

Артефакты лежат в:

- `lessons/10-networking-nat-dnat-netns-ufw/scripts/`

Выставить execute-бит:

```bash
chmod +x lessons/10-networking-nat-dnat-netns-ufw/scripts/*.sh
```

Проверка справки:

```bash
./lessons/10-networking-nat-dnat-netns-ufw/scripts/setup-netns-nat.sh --help
./lessons/10-networking-nat-dnat-netns-ufw/scripts/check-netns-nat.sh --help
./lessons/10-networking-nat-dnat-netns-ufw/scripts/cleanup-netns-nat.sh --help
```

---

## 7. Мини-Лаба (Core Path)

```bash
./lessons/10-networking-nat-dnat-netns-ufw/scripts/setup-netns-nat.sh

sudo ip netns exec lab10 ping -c 1 10.10.0.1
sudo ip netns exec lab10 ping -c 1 1.1.1.1
curl -sI http://127.0.0.1:8080 | head -n 5

sudo iptables -t nat -L -v -n --line-numbers | sed -n '1,80p'
sudo iptables -L FORWARD -v -n --line-numbers | sed -n '1,80p'
```

Checklist:

- namespace пингует gateway;
- namespace выходит во внешнюю сеть;
- localhost:8080 открывает HTTP из namespace;
- counters в NAT/FORWARD увеличиваются.

---

## 8. Расширенная Лаба (Optional + Advanced)

```bash
# DNS + внешний IP из namespace
sudo ip netns exec lab10 bash -lc 'echo nameserver 1.1.1.1 >/etc/resolv.conf'
sudo ip netns exec lab10 curl -sS https://ifconfig.io | head -n 1

# UFW (только с планом отката)
sudo ufw status verbose || true
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp
sudo ufw allow 8080/tcp
sudo ufw enable
sudo ufw status numbered

# pcap на 8080
IF="$(ip -o -4 route show default table main | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
sudo timeout 10 tcpdump -i "$IF" -nn -w /tmp/lesson10_8080.pcap 'tcp port 8080'
```

---

## 9. Очистка

```bash
./lessons/10-networking-nat-dnat-netns-ufw/scripts/cleanup-netns-nat.sh
sudo ufw disable || true
rm -f /tmp/lesson10_8080.pcap
```

---

## 10. Итоги Урока

- **Что изучил:** поток `netns -> routing -> NAT -> DNAT -> verification` для реальной сетевой диагностики.
- **Что практиковал:** поднятие namespace-сети, проброс порта, проверка counters и безопасный cleanup.
- **Продвинутые навыки:** идемпотентные iptables-правила и state-driven rollback.
- **Операционный фокус:** сначала validate/state capture, потом apply; не оставлять lab-правила в системе после практики.
- **Артефакты в репозитории:** `lessons/10-networking-nat-dnat-netns-ufw/scripts/`, `lessons/10-networking-nat-dnat-netns-ufw/scripts/README.md`.
