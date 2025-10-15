# netns

---

## Что такое `ip netns`

`netns` (network namespace) — это **отдельное сетевое пространство**:

каждое имеет свои интерфейсы, маршруты, таблицы маршрутизации, iptables, UFW и т.п.

Можно создать "мини-интернет" внутри своей системы — каждый `netns` живёт как отдельный контейнер с собственными сетевыми настройками.

---

## Основные команды

| Команда | Что делает |
| --- | --- |
| `ip netns list` | Показать все неймспейсы |
| `ip netns add <имя>` | Создать неймспейс |
| `ip netns delete <имя>` | Удалить неймспейс |
| `ip netns exec <имя> <команда>` | Выполнить команду внутри неймспейса |
| `ip netns identify <pid>` | Узнать, в каком неймспейсе процесс |
| `ip netns set <имя> <pid>` | Привязать процесс к неймспейсу |

---

## Пример: создаём два изолированных неймспейса и соединяем их

```bash
# создаём два пространства
sudo ip netns add ns1
sudo ip netns add ns2

# создаём виртуальный кабель (veth-пару)
sudo ip link add veth1 type veth peer name veth2

# подключаем интерфейсы к неймспейсам
sudo ip link set veth1 netns ns1
sudo ip link set veth2 netns ns2

# задаём IP-адреса
sudo ip netns exec ns1 ip addr add 10.0.0.1/24 dev veth1
sudo ip netns exec ns2 ip addr add 10.0.0.2/24 dev veth2

# включаем интерфейсы
sudo ip netns exec ns1 ip link set veth1 up
sudo ip netns exec ns2 ip link set veth2 up
```

Проверим связь:

```bash
sudo ip netns exec ns1 ping 10.0.0.2
```

---

## Добавим выход в интернет

Чтобы `ns1` видел интернет через основной интерфейс `eth0`

Вот как:

```bash
sudo ip link add veth-ns type veth peer name veth-host
sudo ip link set veth-ns netns ns1

sudo ip addr add 10.200.1.1/24 dev veth-host
sudo ip link set veth-host up

sudo ip netns exec ns1 ip addr add 10.200.1.2/24 dev veth-ns
sudo ip netns exec ns1 ip link set veth-ns up
sudo ip netns exec ns1 ip route add default via 10.200.1.1
```

Теперь NATим трафик наружу:

```bash
sudo sysctl -w net.ipv4.ip_forward=1
sudo iptables -t nat -A POSTROUTING -s 10.200.1.0/24 -o eth0 -j MASQUERADE
```

И `ns1` теперь может пинговать 8.8.8.8 

---

## Работа с именами и DNS внутри netns

Создать `/etc/netns/ns1/resolv.conf`:

```
nameserver 8.8.8.8
```

Теперь внутри `ns1` будет свой DNS.

---

## Пример сценария: эмуляция двух серверов

```bash
sudo ip netns add client
sudo ip netns add server
sudo ip link add veth-client type veth peer name veth-server
sudo ip link set veth-client netns client
sudo ip link set veth-server netns server

sudo ip netns exec client ip addr add 192.168.1.10/24 dev veth-client
sudo ip netns exec server ip addr add 192.168.1.20/24 dev veth-server
sudo ip netns exec client ip link set veth-client up
sudo ip netns exec server ip link set veth-server up

# Поднимаем "сервер" внутри неймспейса:
sudo ip netns exec server python3 -m http.server 8080 &
# И проверяем с клиента:
sudo ip netns exec client curl http://192.168.1.20:8080
```

---

## Полезные трюки

| Команда | Что делает |
| --- | --- |
| `sudo ip netns exec <имя> bash` | Зайти внутрь как в контейнер |
| `sudo ip netns exec <имя> ip link` | Посмотреть интерфейсы |
| `sudo ip netns exec <имя> ip route` | Посмотреть маршруты |
| `sudo ip netns exec <имя> ufw status` | Проверить правила внутри namespace (если UFW установлен) |
| `sudo ip netns exec <имя> tcpdump -i any` | Сниффить трафик внутри пространства |

---

## Когда использовать `netns`

- Отладка сетей Kubernetes, Calico, Cilium, Istio
- Тестирование iptables, UFW, NAT без риска
- Эмуляция нескольких машин на одном сервере
- Изоляция сетей в CI/CD-пайплайнах (например, тест VPN или API)