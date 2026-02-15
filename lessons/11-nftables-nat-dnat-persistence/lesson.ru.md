# lesson_11

# Networking (Part 3): `nftables` NAT/DNAT + Persistence

**Date:** 2025-09-21  
**Topic:** `nftables` ruleset, NAT/DNAT/hairpin, counters/trace и сохранение правил между перезагрузками.  
**Daily goal:** Перейти от ad-hoc `iptables` правил к чистому `nftables`-подходу с понятной диагностикой и контролируемой persistence.
**Bridge:** [05-07 Operations Bridge](../00-foundations-bridge/05-07-operations-bridge.ru.md) — shell/systemd-практики, используемые в этом уроке.
**Legacy:** исходный конспект сохранен в `lessons/11-nftables-nat-dnat-persistence/lesson_11(legacy).md`.

---

## 0. Prerequisites

Перед началом проверь базовые зависимости:

```bash
command -v nft ip iptables sysctl curl python3
nft --version
```

Опционально для pcap:

```bash
command -v tcpdump || echo "install tcpdump if needed"
```

---

## 1. Базовые Концепции

### 1.1 Что меняется относительно урока 10

В уроке 10 мы делали NAT/DNAT через `iptables`. В 11-м — делаем то же через `nftables`, но как единый ruleset:

- проще читать и поддерживать;
- проще хранить/восстанавливать;
- удобнее видеть counters и трассировку rule match.

### 1.2 Таблица, chain, hook, priority

`nftables` модель:

- `table` — логическая группа правил;
- `chain` — список правил для конкретного hook;
- `hook` — точка в packet path (`prerouting`, `output`, `postrouting`);
- `priority` — порядок срабатывания внутри hook.

### 1.3 NAT-поток в nft

- `prerouting`: DNAT для входящего трафика;
- `output`: DNAT для локальных запросов host (`127.0.0.1`/hairpin);
- `postrouting`: MASQUERADE/SNAT для исходящего/ответного трафика.

### 1.4 Counter-first troubleshooting

`counter` прямо в правилах дает факт попадания пакетов, а не только "правило вроде есть".

### 1.5 `nft monitor trace`

Trace режим показывает точный путь пакета по chain/rule. Это самый быстрый способ понять, где трафик отрезается.

### 1.6 Persistence после reboot

Runtime-правила исчезнут после перезагрузки, если их не сохранить в конфиге и не загрузить сервисом `nftables.service`.

### 1.7 Безопасность и область изменений

Для лаб лучше удалять/обновлять только нужную таблицу (`table ip nat`), а не делать глобальный `flush ruleset`, чтобы не ломать чужие правила.

### 1.8 Нюанс про `FORWARD` policy

NAT-правил в `nft` недостаточно, если на хосте `FORWARD` policy = `DROP` (частый случай на Docker/UFW-хостах).
В этом случае нужны явные allow-правила в `iptables FORWARD` для трафика `veth` <-> outbound-интерфейса.

---

## 2. Приоритет Команд (Что Учить Сначала)

### Core (обязательно сейчас)

- `nft list ruleset`
- `nft list table ip nat`
- `nft -f <file.nft>`
- `nft delete table ip nat`
- `sysctl net.ipv4.ip_forward=1`
- `ip netns ...` + `veth`
- `iptables -C/-A FORWARD ...` (для хостов с `FORWARD=DROP`)

### Optional (после core)

- `nft -a list ruleset` (handles)
- `nft monitor trace`
- `tcpdump` для packet proof
- `systemctl enable --now nftables`

### Advanced (уровень эксплуатации)

- design ruleset без смешивания стека (`nft` vs `iptables`)
- persistence workflow: backup/validate/apply
- state-driven cleanup и rollback

---

## 3. Core Команды: Что / Зачем / Когда

### `nft list ruleset`

- **Что:** полный активный ruleset.
- **Зачем:** понять текущую сетевую policy-картину.
- **Когда:** до и после apply.

```bash
sudo nft list ruleset
```

### `nft -f /tmp/lesson11.nft`

- **Что:** загрузка ruleset из файла.
- **Зачем:** повторяемость и аудит изменений.
- **Когда:** apply после подготовки файла.

```bash
sudo nft -f /tmp/lesson11.nft
```

### Откуда берется `/tmp/lesson11.nft`

Есть два рабочих пути:

1. **Через скрипт** (рекомендуемый для урока):  
`./lessons/11-nftables-nat-dnat-persistence/scripts/setup-nft-netns.sh`  
Скрипт сам собирает ruleset и пишет его в `/tmp/lesson11.nft`, потом выполняет `sudo nft -f /tmp/lesson11.nft`.

2. **Вручную** (чтобы понять механику):

```bash
IF="$(ip -o route show to default | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
NS_IP="10.10.0.2"
PORT=8080

cat > /tmp/lesson11.nft <<EOF
table ip nat {
  chain prerouting {
    type nat hook prerouting priority dstnat; policy accept;
    iifname "$IF" tcp dport $PORT counter dnat to $NS_IP:$PORT
  }
  chain output {
    type nat hook output priority dstnat; policy accept;
    ip daddr 127.0.0.1 tcp dport $PORT counter dnat to $NS_IP:$PORT
  }
  chain postrouting {
    type nat hook postrouting priority srcnat; policy accept;
    ip daddr $NS_IP tcp dport $PORT counter snat to 10.10.0.1
    ip saddr 10.10.0.0/24 oifname != "lo" counter masquerade
  }
}
EOF

sudo nft -f /tmp/lesson11.nft
sudo nft list table ip nat
```

Смысл manual-пути: ты видишь, как текст ruleset превращается в активные правила, и уже потом используешь скрипт как автоматизацию этого же процесса.

### `nft delete table ip nat`

- **Что:** удалить только NAT-таблицу урока.
- **Зачем:** аккуратный cleanup без тотального flush.
- **Когда:** перезапуск lab или завершение практики.

```bash
sudo nft delete table ip nat 2>/dev/null || true
```

### `ip_forward` + `route_localnet`

- **Что:** включение маршрутизации и localhost hairpin support.
- **Зачем:** без этого NAT/DNAT path может не работать.
- **Когда:** до проверки доступа.

```bash
sudo sysctl -w net.ipv4.ip_forward=1
sudo sysctl -w net.ipv4.conf.veth0.route_localnet=1
```

---

## 4. Optional Команды (После Core)

Optional блок нужен для уверенной диагностики: ты видишь не только факт ошибки, но и точное место в packet path.

### 4.1 `nft -a list ruleset`

- **Что:** выводит ruleset с `handle` у каждого правила.
- **Зачем:** handle нужен для точечного удаления/замены одного правила без пересборки всей таблицы.
- **Когда:** когда rule надо убрать выборочно в runtime.

```bash
sudo nft -a list ruleset
```

Пример чтения:

- в конце строки правила будет `# handle 17`;
- это значит, что правило можно удалить адресно: `sudo nft delete rule ip nat prerouting handle 17`.

### 4.2 `nft monitor trace`

- **Что:** live-трассировка прохождения пакета по hooks/chains.
- **Зачем:** быстро понять, почему правило "есть", но трафик не проходит.
- **Когда:** при любом "curl/ping не работает, а правила вроде правильные".
- **Разбор команды:** `nft` (CLI) + `monitor` (поток событий) + `trace` (только события трассировки пакетов).

```bash
sudo nft monitor trace
```

Во второй консоли генерируй трафик:

```bash
curl -sI http://127.0.0.1:8080 >/dev/null
```

Если trace "молчит", это обычно значит, что для пакета не выставлен `nftrace`.
Для ручного flow включи его временным правилом:

```bash
# включить трассировку для localhost:8080
sudo nft insert rule ip nat output ip daddr 127.0.0.1 tcp dport 8080 meta nftrace set 1

# сгенерировать трафик
curl -sI http://127.0.0.1:8080 >/dev/null

# найти handle временного trace-правила
sudo nft -a list chain ip nat output

# удалить временное правило после теста
sudo nft delete rule ip nat output handle <HANDLE>
```

Остановка trace:

```bash
# в терминале с monitor
Ctrl+C
```

Как интерпретировать:

- если видишь прохождение через `output` и `postrouting` — локальный DNAT path активен;
- если trace не доходит до expected chain, ищи mismatch по интерфейсу/адресу/порту.

### 4.3 `tcpdump` как packet-proof

- **Что:** захват реальных пакетов на интерфейсе.
- **Зачем:** подтвердить, что трафик физически выходит/входит (а не только логически матчится rule).
- **Когда:** когда нужно доказательство на уровне wire (для отчета/разбора инцидента).

```bash
# sudo tcpdump -D
IF="$(ip -o route show to default | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
sudo timeout 8 tcpdump -i "$IF" -nn -w /tmp/lesson11_8080.pcap 'tcp port 8080'
```

Для localhost/hairpin-проверок чаще полезнее `-i any`:

```bash
sudo timeout 8 tcpdump -i any -nn -w /tmp/lesson11_8080_any.pcap 'tcp port 8080'
```

### 4.4 Что делать в Optional на практике

1. Проверить, что базовый `curl` работает.
2. Запустить `nft monitor trace`, повторить `curl`.
3. Проверить, что trace идет через ожидаемые hooks/chains.
4. Сравнить counters до/после запроса.
5. При спорном кейсе снять короткий `tcpdump` и сохранить `.pcap`.

---

## 5. Advanced Темы (Ops-Grade)

Advanced блок отвечает на вопрос "как это безопасно сопровождать в эксплуатации, а не только запускать в лабе".

### 5.1 Карта packet path

```text
external client -> prerouting(dnat) -> forward -> postrouting(snat/masquerade) -> namespace
host localhost -> output(dnat) -> postrouting(snat hairpin) -> namespace
namespace -> postrouting(masquerade) -> WAN
```

Зачем эта карта: по ней быстро определяется, в каком hook искать проблему для конкретного симптома.

### 5.2 Симптомы и диагностика

| Симптом | Где смотреть | Частая причина | Что сделать |
|---|---|---|---|
| `curl 127.0.0.1:8080` не работает | `chain output`, `postrouting` | нет output dnat/sn​at | добавить output DNAT и hairpin SNAT |
| `ns -> internet` не работает | `ip_forward`, `postrouting` | нет forwarding/masquerade | включить sysctl + MASQUERADE |
| rules есть, но трафик не идет | counters/trace | rule не матчится | проверить интерфейс/адрес/порт матчи |

Быстрая логика чтения:

- counter у правила = `0` после теста -> пакет не попал в это правило;
- counter растет, но сессии нет -> искать следующий этап path (обычно return path/SNAT).

### 5.3 Persistence workflow (с откатом)

1. Сделать backup:

```bash
sudo cp -a /etc/nftables.conf /etc/nftables.conf.bak.$(date +%F_%H%M%S)
```

2. Проверить синтаксис до apply (`-c` = check only):

```bash
sudo nft -c -f /etc/nftables.conf
```

3. Применить конфиг:

```bash
sudo nft -f /etc/nftables.conf
```

4. Включить автозагрузку:

```bash
sudo systemctl enable --now nftables
```

5. Проверить после reboot, что правила восстановились.

Rollback для persistence:

```bash
# если нужен откат:
# sudo cp /etc/nftables.conf.bak.YYYY-MM-DD_HHMMSS /etc/nftables.conf
# sudo nft -c -f /etc/nftables.conf
# sudo systemctl restart nftables
```

### 5.4 `iptables` vs `nft` backend

Не смешивай unmanaged-правила из обоих стеков в одной лабе. Выбери один контрольный путь и держи его консистентным.

### 5.5 UFW + nft: как не конфликтовать

В этом уроке управляем `nft` напрямую только для `table ip nat`.  
Если у тебя активен UFW:

1. не делай глобальный `flush ruleset`;
2. меняй только lesson-specific NAT table;
3. после лабы проверь `sudo ufw status verbose`, что baseline не сломан.

### 5.6 Что делать в Advanced пошагово

1. Поднять лабу:
`./lessons/11-nftables-nat-dnat-persistence/scripts/setup-nft-netns.sh`
2. Проверить доступ и counters:
`./lessons/11-nftables-nat-dnat-persistence/scripts/check-nft-netns.sh`
3. Прогнать trace и короткий pcap.
4. Пройти persistence цикл (`backup -> nft -c -> nft -f -> systemctl enable`).
5. Очистить стенд:
`./lessons/11-nftables-nat-dnat-persistence/scripts/cleanup-nft-netns.sh`

---

## 6. Скрипты в Этом Уроке

Скрипты в этом уроке — это **автоматизация**, а не обязательный старт.
Правильный порядок обучения: сначала пройти руками, потом сравнить со скриптом.

### 6.1 Ручной Core-проход (1 раз сделать без скрипта)

```bash
# 1) netns + veth
sudo ip netns del lab11 2>/dev/null || true
sudo ip netns add lab11
sudo ip link add veth0 type veth peer name veth1
sudo ip link set veth1 netns lab11

# 2) адреса + route
sudo ip addr add 10.10.0.1/24 dev veth0
sudo ip link set veth0 up
sudo ip -n lab11 addr add 10.10.0.2/24 dev veth1
sudo ip -n lab11 link set veth1 up
sudo ip -n lab11 link set lo up
sudo ip -n lab11 route add default via 10.10.0.1

# 3) forwarding + hairpin support
sudo sysctl -w net.ipv4.ip_forward=1
sudo sysctl -w net.ipv4.conf.veth0.route_localnet=1

# 3.1) FORWARD allow (обязательно, если у хоста policy FORWARD=DROP)
IF="$(ip -o route show to default | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
sudo iptables -C FORWARD -i veth0 -o "$IF" -s 10.10.0.0/24 -j ACCEPT 2>/dev/null || \
  sudo iptables -A FORWARD -i veth0 -o "$IF" -s 10.10.0.0/24 -j ACCEPT
sudo iptables -C FORWARD -i "$IF" -o veth0 -d 10.10.0.0/24 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || \
  sudo iptables -A FORWARD -i "$IF" -o veth0 -d 10.10.0.0/24 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# 4) сервис в namespace
sudo ip netns exec lab11 bash -lc 'echo nameserver 1.1.1.1 >/etc/resolv.conf'
sudo ip netns exec lab11 bash -lc 'python3 -m http.server 8080 --bind 10.10.0.2 >/tmp/lab11_http.log 2>&1 & echo $! >/tmp/lab11_http.pid'

# 5) ruleset -> apply
cat > /tmp/lesson11.nft <<EOF
table ip nat {
  chain prerouting {
    type nat hook prerouting priority dstnat; policy accept;
    iifname "$IF" tcp dport 8080 counter dnat to 10.10.0.2:8080
  }
  chain output {
    type nat hook output priority dstnat; policy accept;
    ip daddr 127.0.0.1 tcp dport 8080 counter dnat to 10.10.0.2:8080
  }
  chain postrouting {
    type nat hook postrouting priority srcnat; policy accept;
    ip daddr 10.10.0.2 tcp dport 8080 counter snat to 10.10.0.1
    ip saddr 10.10.0.0/24 oifname != "lo" counter masquerade
  }
}
EOF

sudo nft delete table ip nat 2>/dev/null || true
sudo nft -f /tmp/lesson11.nft
```

### 6.2 Скрипты (automation)

Артефакты:

- `lessons/11-nftables-nat-dnat-persistence/scripts/`

```bash
chmod +x lessons/11-nftables-nat-dnat-persistence/scripts/*.sh

./lessons/11-nftables-nat-dnat-persistence/scripts/setup-nft-netns.sh --help
./lessons/11-nftables-nat-dnat-persistence/scripts/check-nft-netns.sh --help
./lessons/11-nftables-nat-dnat-persistence/scripts/check-nft-netns.sh --trace-once
./lessons/11-nftables-nat-dnat-persistence/scripts/cleanup-nft-netns.sh --help
```

`setup-nft-netns.sh` автоматически добавляет FORWARD allow-правила для lab subnet, если это требуется на текущем хосте.

---

## 7. Мини-Лаба (Core Path, Manual First)

Если уже прошёл manual flow из раздела 6.1, просто выполни проверки:

```bash
sudo ip netns exec lab11 ping -c 1 10.10.0.1
sudo ip netns exec lab11 ping -c 1 1.1.1.1
curl -sI http://127.0.0.1:8080 | head -n 5

sudo nft list table ip nat
```

Если ICMP наружу режется аплинком, проверяй egress через TCP:

```bash
sudo ip netns exec lab11 curl -sS --max-time 5 https://ifconfig.io/ip
```

Если хочешь полностью автоматизированный путь, вместо manual flow используй:

```bash
./lessons/11-nftables-nat-dnat-persistence/scripts/setup-nft-netns.sh
./lessons/11-nftables-nat-dnat-persistence/scripts/check-nft-netns.sh
```

Checklist:

- namespace пингует gateway;
- namespace выходит наружу;
- localhost DNAT отдает HTTP 200;
- counters в nat-правилах растут.

---

## 8. Расширенная Лаба (Optional + Advanced)

```bash
# Trace в одной консоли
sudo nft monitor trace

# Трафик в другой
./lessons/11-nftables-nat-dnat-persistence/scripts/check-nft-netns.sh --trace-once

# Pcap proof
IF="$(ip -o route show to default | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
sudo timeout 12 tcpdump -i any -nn -w /tmp/lesson11_8080_any.pcap 'tcp port 8080' &
sleep 1
curl -sI http://127.0.0.1:8080 >/dev/null
HOST_EXT_IP="$(ip -4 -o addr show "$IF" | awk '{print $4}' | cut -d/ -f1 | head -1)"
curl -sI "http://$HOST_EXT_IP:8080" >/dev/null
wait

# Persistence checks
sudo nft -c -f /etc/nftables.conf
sudo systemctl enable --now nftables
```

---

## 9. Очистка

```bash
./lessons/11-nftables-nat-dnat-persistence/scripts/cleanup-nft-netns.sh
rm -f /tmp/lesson11_8080.pcap /tmp/lesson11_8080_any.pcap
```

---

## 10. Итоги Урока

- **Что изучил:** как собирать NAT/DNAT flow через `nftables` с counters и trace.
- **Что практиковал:** netns+veth topology, localhost/external DNAT, runtime и persistence-проверки.
- **Продвинутые навыки:** symptom-driven debugging через `nft monitor trace` и счётчики правил.
- **Операционный фокус:** минимальная область изменений (table-level), проверка до/после, безопасный cleanup.
- **Артефакты в репозитории:** `lessons/11-nftables-nat-dnat-persistence/scripts/`, `lessons/11-nftables-nat-dnat-persistence/scripts/README.md`.
