# 08-11 Networking + Text Bridge (После Уроков 8-11)

**Цель:** закрыть все практические пробелы между текстовой обработкой, сетевой диагностикой, NAT/DNAT и `nftables` persistence.

Этот bridge не заменяет уроки 8-11.
Он нужен как рабочая опора, когда не просто повторяешь команды, а разбираешь реальный инцидент.

---

## 0. Как использовать этот файл

Порядок работы:

1. Берешь симптом.
2. Идешь в соответствующий раздел (08/09/10/11).
3. Прогоняешь минимальный чеклист из раздела.
4. Сохраняешь артефакт (лог, pcap, ruleset dump).
5. Делаешь cleanup и фиксируешь выводы.

Базовый принцип: **source of truth = наблюдаемые факты** (counters, trace, pcap, status).

---

## 1. Единая диагностическая модель (для 8-11)

Цепочка проверки:

1. `input` (что именно не работает: DNS, HTTP, порт, маршрут).
2. `state` (интерфейсы, адреса, маршруты, сокеты, policy).
3. `path` (куда пакет должен пройти по hooks/chains).
4. `proof` (counter/trace/pcap/log).
5. `rollback` (как безопасно вернуть состояние).

Практический шаблон команд:

```bash
# 1) Network state
ip -br a
ip route
ss -tulpn

# 2) DNS + app
getent hosts example.com || true
curl -sS --max-time 5 https://example.com >/dev/null || true

# 3) Firewall/NAT state
sudo iptables -L -v -n
sudo iptables -t nat -L -v -n
sudo nft list ruleset
```

---

## 2. Урок 08 Bridge: `grep` / `sed` / `awk`

### 2.1 `grep`: три режима, которые нужны чаще всего

```bash
# 1) Найти паттерн + номер строки
grep -nE 'error|failed|timeout' app.log

# 2) Инверсия (убрать шум)
grep -vE '^$|^#' config.conf

# 3) Рекурсивный поиск по дереву
grep -R --line-number --color=never 'PermitRootLogin' /etc/ssh 2>/dev/null
```

Когда использовать:

- triage логов;
- поиск нужного параметра в конфиге;
- быстрый pre-check перед `sed` правкой.

### 2.2 `sed`: безопасная правка

```bash
# сначала просмотр
sed -n '1,120p' file.conf

# потом правка с backup
sed -ri.bak 's/^#?PermitRootLogin .*/PermitRootLogin no/' file.conf

# проверка
grep -n '^PermitRootLogin' file.conf
```

Правило: без `*.bak` в учебном и боевом потоке правки делать не стоит.

### 2.3 `awk`: когда `grep` уже мало

Примеры:

```bash
# 1) Частота IP по access.log
awk '{print $1}' access.log | sort | uniq -c | sort -nr | head

# 2) Статусы HTTP
awk '{print $9}' access.log | sort | uniq -c | sort -nr

# 3) Простая фильтрация по коду
awk '$9 ~ /^5/ {print $1, $7, $9}' access.log | head
```

Если нужно считать/группировать — обычно это зона `awk`, не `grep`.

### 2.4 Pipeline-debug (почему пайплайн "не работает")

Всегда режь по этапам:

```bash
# A
journalctl -u ssh -o cat -n 50

# A|B
journalctl -u ssh -o cat -n 50 | grep -E 'Failed|Accepted'

# A|B|C
journalctl -u ssh -o cat -n 50 | grep -E 'Failed|Accepted' | awk '{print $1, $2, $3, $0}'
```

---

## 3. Урок 09 Bridge: диагностика сети от сокета до пакета

### 3.1 Мини-чеклист "сервис не открывается"

```bash
# интерфейс/адрес/route
ip -br a
ip route

# слушает ли процесс
ss -tulpn | grep -E ':80|:443|:8080|:22' || true

# DNS
dig +short example.com

# policy
sudo ufw status verbose || true

# packet proof
IF="$(ip -o route show to default | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
sudo timeout 8 tcpdump -i "$IF" -nn 'tcp port 443'
```

### 3.2 `tcpdump`: почему часто пусто

Частые причины:

- выбран не тот интерфейс;
- трафик локальный (`localhost`) и на внешнем IF его не видно;
- фильтр слишком узкий.

Быстрый fallback:

```bash
sudo timeout 8 tcpdump -i any -nn 'tcp port 8080'
```

### 3.3 DNS vs транспорт

Если `curl` пишет `Resolving timed out`:

- это ещё не "нет интернета";
- часто это DNS-path (UDP/TCP 53) или resolver.

Проверяй отдельно:

```bash
dig +short example.com
curl -sS --max-time 5 https://1.1.1.1 >/dev/null || true
```

---

## 4. Урок 10 Bridge: NAT/DNAT через `iptables`

### 4.1 Три потока, которые нужно различать

1. Namespace -> internet (egress):

```text
ns -> veth -> FORWARD -> nat/POSTROUTING(MASQUERADE) -> WAN
```

2. External -> host:8080 -> namespace:

```text
client -> nat/PREROUTING(DNAT) -> FORWARD -> ns
```

3. Host localhost -> namespace (hairpin):

```text
host -> nat/OUTPUT(DNAT) -> nat/POSTROUTING(SNAT) -> ns
```

### 4.2 Почему "NAT есть, но не работает"

Потому что NAT не заменяет filter policy.
Если `FORWARD=DROP`, нужен explicit allow.

Диагностика:

```bash
sudo iptables -S FORWARD
sudo iptables -L FORWARD -v -n
```

### 4.3 Идемпотентный паттерн

```bash
sudo iptables -C FORWARD ... 2>/dev/null || sudo iptables -A FORWARD ...
```

Зачем:

- повторный запуск setup без дубликатов;
- предсказуемый автоматизированный apply.

### 4.4 Counters: как читать правильно

```bash
sudo iptables -t nat -L -v -n --line-numbers
sudo iptables -L FORWARD -v -n --line-numbers
```

Снял baseline -> сделал 1-2 запроса -> снял снова -> сравнил рост нужных правил.

---

## 5. Урок 11 Bridge: `nftables` NAT/DNAT + trace + persistence

### 5.1 `nft` структура

- `table` -> логическая область;
- `chain` -> список правил;
- `hook` -> место в packet path;
- `counter` -> факт матчинга.

### 5.2 Runtime и файл ruleset

Рабочий паттерн:

1. сформировать файл (`/tmp/lesson11.nft`);
2. `sudo nft -f /tmp/lesson11.nft`;
3. проверить `sudo nft list table ip nat`.

### 5.3 Почему `nft monitor trace` может молчать

`trace` виден только если пакету выставлен `nftrace`.

Мини-flow:

```bash
# terminal A
sudo nft monitor trace

# terminal B
./lessons/11-nftables-nat-dnat-persistence/scripts/check-nft-netns.sh --trace-once
```

`--trace-once` временно добавляет правило `meta nftrace set 1`, делает один запрос и удаляет правило.

### 5.4 `FORWARD=DROP` кейс (Docker/UFW hosts)

Даже с корректным `nft` NAT egress может не работать без allow в `iptables FORWARD`.
В актуальном `setup-nft-netns.sh` это уже автоматизировано.

### 5.5 Persistence + rollback

Минимум:

```bash
sudo cp -a /etc/nftables.conf /etc/nftables.conf.bak.$(date +%F_%H%M%S)
sudo nft -c -f /etc/nftables.conf
sudo nft -f /etc/nftables.conf
sudo systemctl enable --now nftables
```

Rollback:

```bash
# sudo cp /etc/nftables.conf.bak.YYYY-MM-DD_HHMMSS /etc/nftables.conf
# sudo nft -c -f /etc/nftables.conf
# sudo systemctl restart nftables
```

---

## 6. ICMP vs TCP egress (критичный практический момент)

Если `ping 1.1.1.1` не проходит, это не всегда поломка NAT.

Причины:

- ICMP режется аплинком;
- policy допускает TCP, но режет ICMP;
- DNS broken отдельно от transport.

Проверка egress через TCP:

```bash
sudo ip netns exec lab11 curl -sS --max-time 5 https://ifconfig.io/ip
```

Критерий "egress OK":

- либо успешный `ping`,
- либо успешный TCP-check (`curl`).

---

## 7. Симптом -> проверка -> действие

### 7.1 Namespace не выходит наружу

Проверить:

```bash
ip netns exec lab11 ip route
sudo sysctl net.ipv4.ip_forward
sudo iptables -S FORWARD
sudo nft list table ip nat
```

Действие:

- включить `ip_forward`;
- добавить/проверить FORWARD allow;
- убедиться, что `masquerade` counter растет.

### 7.2 `nft monitor trace` пустой

Проверить:

```bash
sudo nft -a list chain ip nat output
```

Действие:

- использовать `--trace-once`;
- либо временно вручную добавить `meta nftrace set 1`.

### 7.3 `tcpdump` ничего не ловит

Проверить:

- правильный интерфейс;
- есть ли трафик в окно capture;
- не слишком ли узкий filter.

Действие:

- fallback на `-i any`;
- удлинить `timeout`;
- сгенерировать трафик вручную в capture window.

---

## 8. Быстрый командный шортлист

```bash
# text
grep -nE 'error|failed|timeout' app.log
sed -n '1,120p' file.conf
awk '{print $1}' access.log | sort | uniq -c | sort -nr | head

# network state
ip -br a
ip route
ss -tulpn

# firewall/nat
sudo iptables -L FORWARD -v -n
sudo iptables -t nat -L -v -n
sudo nft list table ip nat

# trace + packet
sudo nft monitor trace
sudo timeout 8 tcpdump -i any -nn 'tcp port 8080'

# lesson11 helpers
./lessons/11-nftables-nat-dnat-persistence/scripts/setup-nft-netns.sh
./lessons/11-nftables-nat-dnat-persistence/scripts/check-nft-netns.sh --trace-once
./lessons/11-nftables-nat-dnat-persistence/scripts/cleanup-nft-netns.sh
```

---

## 9. Границы ответственности

- Урок 08: обработка текста и логов.
- Урок 09: общая сеть и диагностика path/policy.
- Урок 10: `iptables` NAT/DNAT, netns, hairpin.
- Урок 11: `nftables` NAT/DNAT, trace, persistence.
