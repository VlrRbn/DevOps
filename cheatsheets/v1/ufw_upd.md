# ufw_upd (uncomplicated firewall)

---

## Архитектура: как UFW работает

UFW — это **обёртка над `iptables` (или `nftables` на новых системах)**.

Он не заменяет их, а просто делает управление удобным.

- **iptables** — движок правил в ядре Linux
- **nftables** — его современная замена
- **UFW** → пишет правила в iptables/nftables

Проверить, что реально применено:

```bash
sudo ufw show raw
```

---

## Защита от брутфорса

Ограничить частоту подключений (особенно для SSH):

```bash
sudo ufw limit 22/tcp
```

Разрешает соединения, но блокирует IP, если он делает слишком много попыток (по умолчанию >6 в 30 сек).

---

## Работа с маршрутизацией (route rules)

Если сервер маршрутизирует трафик между интерфейсами (например, VPN, NAT, Kubernetes-ноды и т.п.),

тогда можно писать *route rules*:

```bash
sudo ufw route allow in on eth0 out on eth1 to any port 80 proto tcp
```

Это позволяет пропускать или блокировать трафик, проходящий *через* сервер, а не только *к нему*.

(Полезно для шлюзов, bastion-hosts, NAT и прокси.)

---

## UFW и Docker

По умолчанию Docker **обходит UFW** и сам прописывает iptables-правила напрямую.

### Проблема:

Даже если `ufw default deny incoming`, Docker всё равно открывает порты наружу.

### Решение:

1. В `/etc/docker/daemon.json` добавить:
    
    ```json
    {
      "iptables": false
    }
    ```
    
2. Перезапустить Docker:
    
    ```bash
    sudo systemctl restart docker
    ```
    
3. Теперь правила UFW снова контролируют доступ.
    
    (Но тогда нужно явно разрешать нужные порты контейнерам.)
    

---

## UFW и Ansible / Автоматизация

Можно управлять UFW из Ansible вот так:

```yaml
- name: Enable UFW and set rules
  hosts: servers
  become: yes
  tasks:
    - name: Enable UFW
      ufw:
        state: enabled
        policy: deny

    - name: Allow SSH and HTTP
      ufw:
        rule: allow
        port: "{{ item }}"
      loop:
        - 22
        - 80
        - 443
```

> Модуль: ansible.builtin.ufw. Работает из коробки без ручных скриптов.
> 

---

## Логи и аудит

Файл логов:

```
/var/log/ufw.log
```

Команды:

```bash
sudo ufw logging on         # включить логирование
sudo ufw logging medium     # средний уровень
sudo ufw logging high       # подробный
```

Для живого мониторинга:

```bash
sudo tail -f /var/log/ufw.log
```

---

## Интеграция с системами мониторинга

UFW не пишет в syslog напрямую, но можно настроить через journald:

```bash
journalctl -u ufw
```

Для Prometheus/Zabbix можно парсить `/var/log/ufw.log` или метрики из iptables:

```bash
sudo iptables -L -v -n
```

---

## Полезные трюки

| Команда | Что делает |
| --- | --- |
| `sudo ufw app update <имя>` | Обновить профиль приложения |
| `sudo ufw allow in on eth0 to any port 22` | Разрешить SSH только на конкретном интерфейсе |
| `sudo ufw status numbered` | Показать правила с номерами (для удобного удаления) |
| `sudo ufw delete 3` | Удалить 3-е правило |
| `sudo ufw show added` | Показать только добавленные пользователем правила |

---

## Рекомендованный “Preset”

**UFW стартовый шаблон для прод-сервера:**

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw limit 22/tcp
sudo ufw allow 80,443/tcp
sudo ufw allow 8080/tcp comment 'App server'
sudo ufw logging medium
sudo ufw enable
sudo ufw status verbose
```