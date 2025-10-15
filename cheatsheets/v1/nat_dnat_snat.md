# nat/dnat/snat

---

# NAT, SNAT, DNAT — в чём суть?

| Термин | Что делает | Куда применяется |
| --- | --- | --- |
| **NAT** | Network Address Translation — подмена IP-адресов | общий термин |
| **SNAT** | Source NAT — подменяет **исходный IP** | для выхода в интернет |
| **DNAT** | Destination NAT — подменяет **целевой IP** | для проброса портов внутрь |
| **MASQUERADE** | Спец-тип SNAT, который автоматически берёт внешний IP | удобно для динамических адресов (например, у сервера в облаке) |

---

## Простой SNAT (исходящий NAT)

Чтобы внутренняя сеть (например, `10.0.0.0/24`) выходила в интернет через интерфейс `eth0` сервера.

```bash
sudo sysctl -w net.ipv4.ip_forward=1
sudo iptables -t nat -A POSTROUTING -s 10.0.0.0/24 -o eth0 -j MASQUERADE
```

Теперь все пакеты от 10.0.0.x будут выглядеть так, будто идут **с IP сервера**.

---

## DNAT (проброс портов внутрь)

Хочешь, чтобы запросы снаружи на порт 8080 шли во внутренний сервер `10.0.0.2:80`?

```bash
sudo iptables -t nat -A PREROUTING -i eth0 -p tcp --dport 8080 -j DNAT --to-destination 10.0.0.2:80
```

И не забудь разрешить форвардинг пакетов:

```bash
sudo iptables -A FORWARD -p tcp -d 10.0.0.2 --dport 80 -j ACCEPT
```

Теперь запрос на `http://<твой_сервер>:8080` уходит во внутренний хост. Это и есть “port forwarding”, но на уровне ядра.

---

## SNAT (фиксированный IP-заменитель)

Если сервер имеет **постоянный IP**, лучше использовать SNAT вместо MASQUERADE:

```bash
sudo iptables -t nat -A POSTROUTING -s 10.0.0.0/24 -o eth0 -j SNAT --to-source 203.0.113.5
```

Чуть быстрее, потому что не пересчитывает адрес при каждом пакете.

---

## Проверка NAT-таблиц

```bash
sudo iptables -t nat -L -n -v
```

Покажет таблицу NAT с подсчётом пакетов.

---

## Удаление и чистка NAT-правил

```bash
sudo iptables -t nat -F                        # очистить все NAT-цепочки
sudo iptables -t nat -D PREROUTING <номер>     # удалить конкретное правило
sudo iptables-save | grep -A5 NAT              # просмотреть активные
```

---

## Частые паттерны

| Сценарий | Решение |
| --- | --- |
| Разрешить внутренней сети интернет | `MASQUERADE` |
| Пробросить порт внутрь LAN | `DNAT` + `FORWARD ACCEPT` |
| Использовать фиксированный внешний IP | `SNAT --to-source` |
| Лаборатория в `netns` | NAT + `ip netns exec` |
| Сочетание с UFW | включи `DEFAULT_FORWARD_POLICY="ACCEPT"` в `/etc/default/ufw` |