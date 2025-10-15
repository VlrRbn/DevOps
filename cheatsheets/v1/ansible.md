# ansible

---

## Что это вообще такое

> Ansible — инструмент для автоматизации конфигурации серверов. Без агентов, по SSH, с YAML-плейбуками.
> 

Пишешь, **что должно быть** на сервере, а Ansible делает **как угодно**, чтобы этого достичь.

---

## Установка

```bash
sudo apt update
sudo apt install ansible -y
# ansible --version

cd ~/ansible

python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install ansible
mkdir -p {playbooks,group_vars}
```

## Структура проекта

```
ansible/
├── inventory.ini
├── ansible.cfg
└── playbooks/
    └── deploy.yml
```

---

Файл `/etc/ansible/hosts` (или `inventory.ini` в проекте):

```
[local]
localhost ansible_connection=local     # если локально

# [dev]
# ubuntu-devops ansible_host=192.168.1.10 ansible_user=ubuntu
```

### `ansible.cfg`

```yaml
[defaults]
inventory = ./inventory.ini
interpreter_python = auto_silent
become_ask_pass = True
```

## Playbook `deploy.yml`:

```yaml
---
- name: Full DevOps environment setup                # Заголовок плейбука
  hosts: localhost
  connection: local
  become: true
  gather_facts: false

  vars:                                              # Переменные
    netns_name: ns1
    netns_subnet: 10.200.0.0/24
    netns_ip: 10.200.0.2
    host_ip: 10.200.0.1/24
    host_iface: wlo1
    host_veth: veth-host
    ns_veth: veth-ns

    nginx_server_name: devops.local
    nginx_proxy_target: "http://{{ netns_ip }}:8080"

  tasks:
    - name: Ensure iproute2 is present              # Сеть (netns + veth)
      become: true
      package:
        name: iproute2
        state: present

    - name: Create network namespace (if missing)
      become: true
      command: ip netns add {{ netns_name }}
      args:
        creates: "/var/run/netns/{{ netns_name }}"

    - name: Check host veth existence
      command: ip link show {{ host_veth }}
      register: host_veth_check
      failed_when: false
      changed_when: false

    - name: Check ns veth existence (inside netns)
      command: ip netns exec {{ netns_name }} ip link show {{ ns_veth }}
      register: ns_veth_check
      failed_when: false
      changed_when: false

    - name: Create veth pair only if both ends absent
      become: true
      command: ip link add {{ ns_veth }} type veth peer name {{ host_veth }}
      when: host_veth_check.rc != 0 and ns_veth_check.rc != 0

    - name: Move ns end into namespace if not there
      command: ip link set {{ ns_veth }} netns {{ netns_name }}
      when: ns_veth_check.rc != 0

    - name: Bring up host end with address
      shell: |
        set -Eeuo pipefail
        ip addr show {{ host_veth }} | grep -q '{{ host_ip }}' || ip addr add {{ host_ip }} dev {{ host_veth }}
        ip link set {{ host_veth }} up
      args:
        executable: /bin/bash
      changed_when: false

    - name: Bring up ns loopback and ns end with address
      shell: |
        set -Eeuo pipefail
        ip netns exec {{ netns_name }} sh -c '
          ip link set lo up
          ip addr show {{ ns_veth }} | grep -q "{{ netns_ip }}/24" || ip addr add {{ netns_ip }}/24 dev {{ ns_veth }}
          ip link set {{ ns_veth }} up
        '
      args:
        executable: /bin/bash
      changed_when: false

    - name: Ensure default route inside netns via host end
      command: ip netns exec {{ netns_name }} ip route replace default via 10.200.0.1

    - name: Ensure nftables is installed
      apt:
        name: nftables
        state: present
        update_cache: true

    - name: Enable and start nftables service
      systemd:
        name: nftables
        enabled: true
        state: started

    - name: Deploy nftables.conf (valid syntax)            # nftables (NAT/forward)
      become: true
      copy:
        dest: /etc/nftables.conf
        mode: '0644'
        content: |
          flush ruleset

          table ip nat {
            chain postrouting {
              type nat hook postrouting priority 100;
              ip saddr {{ netns_subnet }} oifname "{{ host_iface }}" masquerade
            }
          }

          table inet filter {
            chain forward {
              type filter hook forward priority 0;
              policy drop;
              ct state established,related accept
              iifname "{{ host_veth }}" oifname "{{ host_iface }}" accept
              iifname "{{ host_iface }}" oifname "{{ host_veth }}" accept
            }
          }

      notify: Reload nftables

    - name: Install NGINX                                # NGINX
      become: true
      apt:
        name: nginx
        state: present
        update_cache: true

    - name: Configure reverse proxy
      become: true
      copy:
        dest: /etc/nginx/sites-available/devops.conf
        mode: '0644'
        content: |
          server {
              listen 80;
              server_name {{ nginx_server_name }};

              location / {
                  proxy_pass {{ nginx_proxy_target }};
                  proxy_http_version 1.1;
                  proxy_set_header Connection "";
                  proxy_set_header Host $host;
                  proxy_set_header X-Real-IP $remote_addr;
                  proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              }
          }
      notify: Reload nginx

    - name: Enable site
      file:
        src: /etc/nginx/sites-available/devops.conf
        dest: /etc/nginx/sites-enabled/devops.conf
        state: link
        force: true
      notify: Reload nginx

    - name: Ensure /etc/hosts entry for devops.local
      lineinfile:
        path: /etc/hosts
        line: "127.0.0.1 {{ nginx_server_name }}"
        state: present

    - name: Ensure Python & pip
      apt:
        name:
          - python3
          - python3-venv
          - python3-pip
        state: present
        update_cache: true

    - name: Create app directory
      become: true
      file:
        path: /opt/nsapp
        state: directory
        mode: '0755'

    - name: Create venv
      become: true
      command: python3 -m venv /opt/nsapp/venv
      args:
        creates: /opt/nsapp/venv/bin/activate

    - name: Install Flask in venv                     # Flask + systemd
      become: true
      command: /opt/nsapp/venv/bin/pip install --upgrade pip flask

    - name: Create Flask app
      become: true
      copy:
        dest: /opt/nsapp/app.py
        mode: '0644'
        content: |
          from flask import Flask
          app = Flask(__name__)
          @app.get("/")
          def index():
              return "Hello from ns1 via NGINX reverse proxy!"
          if __name__ == "__main__":
              app.run(host="0.0.0.0", port=8080)

    - name: Create systemd service (run in netns)
      become: true
      copy:
        dest: /etc/systemd/system/nsapp.service
        mode: '0644'
        content: |
          [Unit]
          Description=Flask app inside netns
          After=network-online.target
          Wants=network-online.target

          [Service]
          Type=simple
          ExecStartPre=/usr/sbin/ip netns exec {{ netns_name }} true
          ExecStart=/usr/sbin/ip netns exec {{ netns_name }} /opt/nsapp/venv/bin/python /opt/nsapp/app.py
          Restart=always
          RestartSec=2

          [Install]
          WantedBy=multi-user.target
      notify: Reload systemd

    - name: Enable & start app
      systemd:
        name: nsapp
        enabled: true
        state: started
        
    - name: Validate nftables.conf
      command: nft -c -f /etc/nftables.conf
      changed_when: false

  handlers:                                        # Хендлеры
    - name: Reload nftables
      command: nft -f /etc/nftables.conf

    - name: Reload nginx
      shell: nginx -t && systemctl reload nginx

    - name: Reload systemd
      command: systemctl daemon-reload

```

Запуск:

```bash
ansible-playbook -i playbooks/deploy.yml --ask-become-pass
```

Проверим подключение и использование файлов:

```bash
ansible all -m ping     # "ping": "pong”
ansible-config dump --only-changed | sed -n '1,120p'
```

---

# Что вообще происходит?

1. Поднимает лабораторную сеть: `netns` + veth-пара (`veth-host` ↔ `veth-ns`) и адреса 10.200.0.1/24 ↔ 10.200.0.2/24.
2. (Для интернета из ns) Готовит `nftables` с NAT/forward.
3. Ставит NGINX и настраивает реверс-прокси на Flask внутри `ns1`.
4. Деплоит Flask-приложение и systemd-юнит, который запускает его **внутри** `ns1`.

---

## Полезные модули

| Модуль | Что делает |
| --- | --- |
| `apt`, `yum` | установка пакетов |
| `copy` | копирование файлов |
| `template` | шаблоны с переменными Jinja2 |
| `service` / `systemd` | управление службами |
| `ufw` / `firewalld` | настройка фаервола |
| `user` | пользователи и SSH-ключи |
| `lineinfile` / `blockinfile` | правка конфигов |
| `command` / `shell` | выполнение команд |
| `nftables` (через `ansible.posix.nftables`) | правила NAT/фильтра |
| `git` | клонирование репозиториев |
| `cron` | задания по расписанию |

---

---

## Идемпотентность

> Один и тот же playbook можно запускать 100 раз — изменения будут только если реально нужно.
> 

---

## Проверка и отладка

| Команда | Описание |
| --- | --- |
| `ansible -m ping all` | проверка соединения |
| `ansible-playbook -C playbooks/deploy.yml` | dry-run (без реальных изменений) |
| `ansible-playbook -vvv playbooks/deploy.yml` | подробный вывод |
| `ansible-lint playbooks/deploy.yml` | проверка стиля и ошибок |
| `ansible-doc <module>` | помощь по модулю |