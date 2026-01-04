# lesson_15

---

# Ansible Advanced: Multi-Host, Vault, Rolling Updates, Health Checks

**Date:** **2025-10-04**

**Topic:** Multi-host inventory & group vars, Ansible Vault (secrets), rolling updates (`serial`), health checks (`wait_for`, `uri`), conditionals, loops, blocks (`rescue/always`), delegation

---

## Goals

- Manage **multiple hosts** with inventory groups and `group_vars/host_vars`.
- Store secrets in **Ansible Vault** and load them safely.
- Perform **rolling updates** with `serial`, `max_fail_percentage`, `strategy`.
- Add **health checks** and **conditional rollback** using `uri`, `wait_for`, `block/rescue/always`.
- Use **conditionals/loops** and **delegation** (`delegate_to`) where it makes sense.

---

## Pocket Cheat

| Command / Snippet | What it does | Why |
| --- | --- | --- |
| `ansible-vault create group_vars/all.vault.yml` | Create encrypted vars | Store secrets safely |
| `ansible-playbook site.yml --ask-vault-pass` | Use vault | Decrypt on the fly |
| `serial: 1` | Rolling (one host at a time) | Zero-downtime-ish |
| `max_fail_percentage: 20` | Tolerate partial failure | Safer rollouts |
| `strategy: linear` | Parallel tasks per host | Faster play |
| `wait_for: port=80 state=started` | Port health | Service up |
| `uri: url=http://127.0.0.1/health status_code=200` | HTTP health | App up |
| `block / rescue / always` | Error handling | Rollback + cleanup |
| `when: ansible_os_family == "Debian"` | Conditional | Per-OS logic |
| `loop:` | Iterate items | DRY tasks |
| `delegate_to: localhost` | Run here, affect remote | E.g., DNS/notify |

---

## Project Layout (extended)

```bash
ansible_adv/
├─ ansible.cfg
├─ inventory
├─ site.yml
├─ group_vars/
│  ├─ all.vault.yml            # encrypted
│  ├─ all.yml
│  ├─ web.yml                  # group vars: web
│  └─ web1.yml
├─ host_vars/
│  └─ web2.yml                 # host-specific vars
└─ roles/
   └─ nginx_reverse_proxy/     # from lesson_14
      ├─ defaults/
      ├─ files/
      ├─ handlers/
      ├─ meta/
      ├─ tasks/
      ├─ templates/
      ├─ tests/
      └─ vars/
```

---

## Files

### `ansible/ansible.cfg` (extend lesson_14)

```bash
[defaults]
inventory = ./inventory
retry_files_enabled = False
deprecation_warnings = False
forks = 20
stdout_callback = yaml
host_key_checking = False
interpreter_python = auto_silent
vault_password_file = .vault_pass.txt

[privilege_escalation]
become = True
become_method = sudo
become_ask_pass = True
```

### `ansible/inventory` (multi-host example)

```bash
[web]
web1 ansible_connection=local
web2 ansible_connection=local
# web2 ansible_host=YOUR_HOST ansible_user=YOUR_USER     # ansible-inventory --list -y | sed -n '1,200p'

[db]
# db1 ansible_host=YOUR_DB_HOST ansible_user=YOUR_USER
```

### `ansible/group_vars/all.yml`

```yaml
# Global non-secret defaults
health_path: /health
http_port: 80
rolling_serial: 1
max_fail_pct: 20
use_https: false
```

### `ansible/group_vars/all.vault.yml` (encrypted)

```yaml
# Encrypted with ansible-vault
basic_auth_user: "admin"
basic_auth_pass: "S3cureP@ss!"
```

Create & edit:

```bash
cd ansible_adv
ansible-vault create group_vars/all.vault.yml  
# add the two keys above; this file will be encrypted
# ansible-vault view group_vars/all.vault.yml | sed -n '1,20p'
```

### `ansible/group_vars/web.yml`

```yaml
nginx_site_name: lab15
nginx_backend_host: 10.10.0.2
nginx_backend_port: 8080
access_log_json: /var/log/nginx/access.json
rate_limit_enabled: true
```

### `ansible/host_vars/web1.yml`

```yaml
# Host-specific overrides
nginx_backend_port: 8080
```

### Role adjustments (lesson_14 role reuse)

`roles/nginx_reverse_proxy/templates/lab-nginx.conf.j2`:

```bash
# Managed by Ansible (role: nginx_reverse_proxy)
upstream lab_backend {
    server {{ nginx_backend_host }}:{{ nginx_backend_port }};
    keepalive 16;
}

map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}

server {
    listen {{ http_port }} default_server;
    listen [::]:{{ http_port }} default_server;
    server_name localhost 127.0.0.1;

    access_log {{ access_log_json }} json;
    server_tokens off;

    location = {{ health_path }} {
	return 200 "OK\n";
	add_header Content-Type text/plain;
    }
    
    {% if basic_auth_user is defined and basic_auth_pass is defined %}
    auth_basic            "Restricted";
    auth_basic_user_file /etc/nginx/.htpasswd;
    {% endif %}

    location / {
	proxy_set_header Host			$host;
	proxy_set_header X-Real-IP		$remote_addr;
	proxy_set_header X-Forwarded-For	$proxy_add_x_forwarded_for;
	proxy_set_header X-Forwarded-Proto	$scheme;
	proxy_http_version 1.1;
	proxy_set_header Connection $connection_upgrade;
	proxy_set_header Upgrade    $http_upgrade;
	proxy_pass http://lab_backend;
    }
}
```

Add tasks to **create htpasswd** only when secrets exist: `roles/nginx_reverse_proxy/tasks/main.yml`:

```yaml
---
- name: Install nginx packages
  ansible.builtin.apt:
    name: "{{ nginx_reverse_proxy_packages }}"
    state: present
    update_cache: true
  become: true
  
- name: Ensure apache2-utils (htpasswd) present (Debian/Ubuntu)
  ansible.builtin.apt:
    name: apache2-utils
    state: present
    update_cache: true
  become: true
  when: basic_auth_user is defined and basic_auth_pass is defined and ansible_os_family == "Debian"

- name: Create htpasswd file when auth is enabled
  ansible.builtin.command: >
    htpasswd -b -c /etc/nginx/.htpasswd "{{ basic_auth_user }}" "{{ basic_auth_pass }}"
  args:
    creates: /etc/nginx/.htpasswd
  become: true
  when: basic_auth_user is defined and basic_auth_pass is defined
  notify:
    - validate nginx
    - restart nginx

- name: Ensure log dir exists
  ansible.builtin.file:
    path: "{{ access_log_json | dirname }}"
    state: directory
    owner: www-data
    group: www-data
    mode: "0755"
  become: true

- name: Deploy site config
  ansible.builtin.template:
    src: lab-nginx.conf.j2
    dest: /etc/nginx/sites-available/{{ nginx_site_name }}.conf
    owner: root
    group: root
    mode: "0644"
  notify:
    - validate nginx
    - restart nginx
  become: true

- name: Enable site
  ansible.builtin.file:
    src: /etc/nginx/sites-available/{{ nginx_site_name }}.conf
    dest: /etc/nginx/sites-enabled/{{ nginx_site_name }}.conf
    state: link
  become: true

- name: Disable default site
  ansible.builtin.file:
    path: /etc/nginx/sites-enabled/default
    state: absent
  notify:
    - validate nginx
    - restart nginx
  become: true

- name: Ensure nginx running
  ansible.builtin.service:
    name: nginx
    state: started
    enabled: true
  become: true
  when: not ansible_check_mode
```

*(Rest of the role **stays** the same from lesson_14.)*

---

## `ansible/site.yml` — Rolling updates + Health checks + Blocks

```yaml
---
- name: Lab15 — Rolling reverse proxy rollout with health checks
  hosts: web
  gather_facts: true
  serial: "{{ rolling_serial | int }}"
  max_fail_percentage: "{{ max_fail_pct }}"
  strategy: linear

  vars_files:
    - group_vars/all.yml
    - group_vars/all.vault.yml

  pre_tasks:
    - name: Announce start (controller)
      ansible.builtin.debug:
        msg: "Starting rolling update on {{ inventory_hostname }}"
      delegate_to: localhost
      run_once: true

  roles:
    - role: nginx_reverse_proxy

  tasks:
    - name: Wait for port to be reachable
      ansible.builtin.wait_for:
        port: "{{ http_port }}"
        host: "127.0.0.1"
        state: started
        timeout: 30
      when: not ansible_check_mode

    - name: HTTP health probe
      ansible.builtin.uri:
        url: "http://127.0.0.1{{ health_path }}"
        status_code: 200
        return_content: false
        validate_certs: false
      register: health
      retries: 5
      delay: 3
      until: health.status == 200
      when: not ansible_check_mode

    - name: Show health result
      ansible.builtin.debug:
        var: health
      when: (not ansible_check_mode) and (health is defined)

  post_tasks:
  - block:
      - name: Post-verify homepage responds 200 (auth-aware)
        ansible.builtin.uri:
          url: "http://127.0.0.1/"
          status_code: 200
          return_content: false
          validate_certs: false
          url_username: "{{ basic_auth_user | default(omit) }}"
          url_password: "{{ basic_auth_pass | default(omit) }}"
          force_basic_auth: "{{ (basic_auth_user is defined) and (basic_auth_pass is defined) }}"
    rescue:
      - name: Attempt rollback (disable site symlink)
        ansible.builtin.file:
          path: "/etc/nginx/sites-enabled/{{ nginx_site_name }}.conf"
          state: absent
        become: true
        notify:
          - validate nginx
          - restart nginx
      - name: Fail play after rollback attempt
        ansible.builtin.fail:
          msg: "Health failed on {{ inventory_hostname }}, rollback attempted."
    always:
      - name: Mark host finished
        ansible.builtin.debug:
          msg: "Finished {{ inventory_hostname }}"
    when: not ansible_check_mode

  handlers:
    - name: validate nginx
      ansible.builtin.command: nginx -t
      become: true
      changed_when: false

    - name: restart nginx
      ansible.builtin.service:
        name: nginx
        state: restarted
      become: true
```

---

## Practice

1. **Create vault secrets**:

```bash
cd ansible_adv
printf '%s\n' 'pass-here' > .vault_pass.txt
chmod 600 .vault_pass.txt                       # ansible-config dump --only-changed | sed -n '1,120p'

ansible-vault create group_vars/all.vault.yml
# add:
# basic_auth_user: "admin"
# basic_auth_pass: "S3cureP@ss!"
```

2. **Run a dry-run**:

```bash
ansible-playbook site.yml --check --diff
```

3. **Apply with rolling**:

```bash
ansible-playbook site.yml
```

4. **Verify**:

```bash
curl -sI http://127.0.0.1/ | head
curl -sI http://127.0.0.1/health | head
# If basic auth enabled:
curl -sI -u admin:S3cureP@ss! http://127.0.0.1/ | head
```

1. **Idempotence**: run again → `changed=0`.
2. **Failure simulation**: set `nginx_backend_port: 9999` in `host_vars/web1.yml`, run play → watch `rescue` path and rollback.
3. **Delegation note**: the `debug` in `pre_tasks` runs once on controller via `delegate_to: localhost`.

---

## Pitfalls

- Forgetting `--ask-vault-pass` (or `vault_password_file`) → vault errors.
- Health checks that hit dynamic paths → flaky results; keep `/health` trivial.
- Rolling without handlers/validation → deploy succeeds but service broken.
- Mixing secrets in plain `all.yml` → bad practice; keep them in vault.

---

## Summary

- Upgraded to **multi-host** management with proper var scoping.
- Secured secrets via **Ansible Vault**.
- Implemented **rolling updates** with health probes and safe rollback mechanics.
- Used **conditionals/loops**, **blocks**, and **delegation** to make plays robust.

---

## Artifacts

- Updated `ansible_adv/` project: inventory, group_vars/host_vars, `all.vault.yml`, updated role template/tasks, `site.yml` with rolling/health

---

## To repeat

- Add more hosts and run with `--limit web` or a single host to compare behavior.
- Extend role to support HTTPS toggle via vars; validate with `nginx -t`.
- Split health probes into a separate role and reuse across services.

---

## Acceptance Criteria

- [ ]  `ansible-playbook site.yml` runs successfully with **vault** and **serial**.
- [ ]  Health checks pass (`/health` returns `200`).
- [ ]  Idempotence confirmed (no changes on second run).
- [ ]  Failure path triggers `rescue` and handler rollback as expected.
- [ ]  Basic auth works, and is not stored in plain text files.