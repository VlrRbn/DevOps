# nftables

---

## Что такое `nftables`

`nftables` — это **новый фреймворк фильтрации пакетов**, пришедший на смену `iptables`, а `iptables` на самом деле просто прокси для `nft`.

То есть: iptables → xtables → ядро

`nft` → `nf_tables` (новый движок ядра, быстрее и проще)

---

## Базовый синтаксис

```bash
sudo nft list ruleset         # показать все таблицы и правила
sudo nft flush ruleset        # очистить всё (осторожно!)
sudo nft add table inet filter
sudo nft add chain inet filter input { type filter hook input priority 0 \; }
sudo nft add rule inet filter input counter accept
```

`inet` — работает и с IPv4, и с IPv6.

---

## NAT с `nftables`

Вот прямой аналог твоей iptables-конфигурации MASQUERADE для `10.200.0.0/24` → `ens3`:

```bash
sudo nft add table nat
sudo nft add chain nat postrouting { type nat hook postrouting priority 100 \; }
sudo nft add rule nat postrouting ip saddr 10.200.0.0/24 oif "ens3" masquerade
```

Проверим:

```bash
sudo nft list table nat
```

Всё, NAT готов. Теперь трафик из `10.200.0.0/24` будет ходить наружу через `ens3`.

---

## DNAT (проброс портов внутрь)

Пример: пробросить `80` с внешнего интерфейса на внутренний хост `10.200.0.2:8080`.

```bash
sudo nft add chain nat prerouting { type nat hook prerouting priority -100 \; }
sudo nft add rule nat prerouting iif "ens3" tcp dport 80 dnat to 10.200.0.2:8080
sudo nft add rule nat postrouting oif "veth-host" ip daddr 10.200.0.2 snat to 10.200.0.1
```

---

## Разрешим forwarding

Создаём таблицу для фильтрации (если ещё нет):

```bash
sudo nft add table inet filter
sudo nft add chain inet filter forward { type filter hook forward priority 0 \; policy accept \; }
```

Теперь пакеты между `veth-host` и `ens3` будут проходить.

---

## Сохранение правил навсегда

Сохраняем текущий набор правил:

```bash
sudo nft list ruleset > /etc/nftables.conf
```

И активируем при старте:

```bash
sudo systemctl enable nftables
sudo systemctl start nftables
```

Проверка:

```bash
sudo systemctl status nftables
```

Теперь все таблицы `nat`, `filter`, `forward` и политики восстановятся при загрузке.

---

## Полезные команды

| Команда | Что делает |
| --- | --- |
| `sudo nft list tables` | список таблиц |
| `sudo nft list chains` | список цепочек |
| `sudo nft list rules` | список правил |
| `sudo nft delete rule <table> <chain> handle <id>` | удалить конкретное правило |
| `sudo nft monitor` | в реальном времени смотреть, что происходит |
| `sudo nft flush table <table>` | очистить таблицу |

---

## TL;DR

| Что делаешь | iptables | nftables |
| --- | --- | --- |
| Посмотреть правила | `iptables -t nat -L -v` | `nft list ruleset` |
| NAT наружу | `-A POSTROUTING -j MASQUERADE` | `ip saddr ... masquerade` |
| Проброс портов | `-A PREROUTING -j DNAT` | `dnat to <ip>` |
| Разрешить forward | `-P FORWARD ACCEPT` | `policy accept` |
| Сохранить | `netfilter-persistent save` | `nft list ruleset > /etc/nftables.conf` |