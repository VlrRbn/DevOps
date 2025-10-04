# lesson_14

---

# Day 14 — Ansible Fundamentals: Inventory, Playbooks, Roles, Idempotence

**Date:** **2025-10-02**

**Topic:** Ansible on localhost + optional SSH to netns host, ad-hoc vs playbooks, idempotence, handlers, templates, variables, tags, check-mode, diff, ansible-lint

---

## Goals

- Idempotency confirmed: the second run of `ansible-playbook site.yml` results in `changed=0`.
- Health OK: `curl -s http://127.0.0.1/health` → OK, HTTP 200 on `/`.
- Handlers are triggered correctly: template change calls **Validate nginx → Restart nginx** (visible in `--check --diff`).
- Linter is green: `ansible-lint` — 0 fatal/warn.
- Dry run is clean: `--check --diff` executes without “sudo: password…” (cfg with `[privilege_escalation]` configured).

---

## Pocket Cheat

| Command / File | What it does | Why |
| --- | --- | --- |
| `sudo apt-get install -y ansible ansible-lint` | Install Ansible + linter | Tooling |
| `ansible all -i inventory -m ping` | Ad-hoc ping | Connectivity |
| `ansible-playbook -i inventory site.yml --check --diff` | Dry-run with diff | Safe preview |
| `ansible-config dump --only-changed` | Show custom config | Debug |
| `ansible-galaxy init roles/nginx_reverse_proxy` | Role skeleton | Reuse |
| `notify: restart nginx` + handler | Restart only on change | Idempotence |
| `vars:` / `group_vars/all.yml` | Variables | DRY |
| `tags:` + `--tags nginx` | Run subset | Speed |
| `ansible-lint` | Static checks | Quality |

---

## Project Layout

```bash
ansible/
├─ inventory
├─ ansible.cfg
├─ site.yml
├─ group_vars/
│  └─ all.yml
└─ roles/
   └─ nginx_reverse_proxy/
      ├─ defaults/main.yml
      ├─ handlers/main.yml
      ├─ tasks/main.yml
      ├─ templates/lab-nginx.conf.j2
      └─ files/ (optional)
```

---

## Files

### `ansible/ansible.cfg`

```yaml
[defaults]
inventory = ./inventory
deprecation_warnings = False
retry_files_enabled = False
forks = 10
stdout_callback = default
host_key_checking = False
interpreter_python = auto_silent

[privilege_escalation]
become = True
become_method = sudo
become_ask_pass = True
```

### `ansible/inventory`

```yaml
[local]
localhost ansible_connection=local
```

> Optional SSH target:
> 
> 
> `web1 ansible_host=YOUR_HOST ansible_user=YOUR_USER ansible_ssh_common_args='-o StrictHostKeyChecking=no'`
> 

### `ansible/group_vars/all.yml`

```yaml
nginx_site_name: lab14
nginx_backend_host: 10.10.0.2
nginx_backend_port: 8080
nginx_listen_http: 80
use_https: false           # Day 12 covered TLS;
access_log_json: /var/log/nginx/access.json
```

### Role skeleton

```bash
cd ansible
ansible-galaxy init roles/nginx_reverse_proxy
```

### `ansible/roles/nginx_reverse_proxy/defaults/main.yml`

```yaml
nginx_reverse_proxy_packages:
  - nginx
nginx_reverse_proxy_health_path: /health
nginx_reverse_proxy_rate_limit_enabled: false
```

### `ansible/roles/nginx_reverse_proxy/handlers/main.yml`

```yaml
---
- name: Validate nginx
  ansible.builtin.command: nginx -t
  become: true
  changed_when: false
  when: not ansible_check_mode

- name: Restart nginx
  ansible.builtin.service:
    name: nginx
    state: restarted
  become: true
  listen: "restart nginx"
  when: not ansible_check_mode
```

### `ansible/roles/nginx_reverse_proxy/templates/lab-nginx.conf.j2`

```bash
# Managed by Ansible (role: nginx_reverse_proxy)
upstream lab_backend {
    server {{ nginx_backend_host }}:{{ nginx_backend_port }};
    keepalive 16;
}

server {
    listen {{ nginx_listen_http }} default_server;
    listen [::]:{{ nginx_listen_http }} default_server;
    server_name localhost 127.0.0.1;

    access_log {{ access_log_json }} json;
    server_tokens off;

    location = {{ nginx_reverse_proxy_health_path }} {
	return 200 "OK\n";
	add_header Content-Type text/plain;
    }

    location / {
	proxy_set_header Host			             $host;
	proxy_set_header X-Real-IP		         $remote_addr;
	proxy_set_header X-Forwarded-For	     $proxy_add_x_forwarded_for;
	proxy_set_header X-Forwarded-Proto     $scheme;
	proxy_http_version 1.1;
	proxy_set_header Connection "";
	proxy_pass http://lab_backend;
    }
}
```

### `ansible/roles/nginx_reverse_proxy/tasks/main.yml`

```yaml
---
- name: Install nginx packages
  ansible.builtin.apt:
    name: "{{ nginx_reverse_proxy_packages }}"
    state: present
    update_cache: true
  become: true

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

### `ansible/site.yml`

```yaml
---
- name: Lab14 — Reverse proxy via Ansible
  hosts: local
  gather_facts: true
  become: true     # Security WARNING (only in lab14)
  vars_files:
    - group_vars/all.yml
  roles:
    - role: nginx_reverse_proxy
```

---

# What we’re building

1. **An Ansible project** with a clear structure (inventory, `ansible.cfg`, playbook, role).
2. A **`nginx_reverse_proxy` role** that:
    - installs Nginx,
    - drops a config from a Jinja2 template,
    - enables the site and disables the `default`,
    - validates with `nginx -t`,
    - restarts Nginx **only when something actually changed**.
3. **Patterns**: check mode (`-check`), diff (`-diff`), handlers, variables (`group_vars`), tags, linting.

Result: you run `ansible-playbook site.yml` — and you get a ready-to-go reverse proxy with `/health` and JSON logs. A second run yields **0 changes** (idempotency).

---

## Practice

1. **Install tooling**

```bash
sudo apt-get update
sudo apt-get install -y ansible ansible-lint jq
```

2. **Bootstrap project**

```bash
mkdir -p ansible && cd ansible
printf "[local]\nlocalhost ansible_connection=local\n" > inventory     # fill ansible.cfg, group_vars/all.yml, site.yml
ansible-galaxy init roles/nginx_reverse_proxy                          # fill role files from snippets above
```

3. **Dry run first**

```bash
ansible all -m ping
ansible-playbook site.yml --check --diff
```

4. **Apply**

```bash
ansible-playbook site.yml
curl -sI http://127.0.0.1/ | head
curl -s http://127.0.0.1/health
tail -n 20 /var/log/nginx/access.json || sudo tail -n 20 /var/log/nginx/access.json
```

---

**Change & idempotence test**
- Change `nginx_backend_port` in `group_vars/all.yml` to a wrong port (e.g., `8081`), run `-check --diff`, see upcoming change.
- Revert to `8080`, run again: play should be **idempotent** (0 changes).

**Tags & partial runs**

```bash
# add `tags: [nginx]` to tasks in role if you want; then:
ansible-playbook site.yml --tags nginx --check
ansible-lint
```

---

## Optional: target a netns host via SSH

```yaml
[netns]
ns1 ansible_host=127.0.0.1 ansible_port=2222 ansible_user=lab ansible_ssh_common_args='-o StrictHostKeyChecking=no'
```

And make a separate play:

```yaml
- name: Configure nginx on netns host
  hosts: netns
  become: true
  roles:
    - role: nginx_reverse_proxy
```

---

## Security Checklist

- Don’t embed secrets in plain YAML; prefer environment variables or Ansible Vault.
- Use `become: true` only where needed; avoid `become: true` on the entire play unless justified.
- Validate generated configs before restarting services (e.g., `nginx -t`).
- Never run `shell:` unless a module exists for the task; if you must, set `creates:`/`removes:` or `changed_when:`.

---

## Pitfalls

- “It always changes” → missing `creates:`/`removes:` or using `shell:` instead of native modules.
- Handlers firing too often → template lacks stable formatting or timestamp-like content.
- Check-mode shows “changed” for service tasks by default; use `check_mode: no` where appropriate.
- Inventory groups don’t match your play’s `hosts:` → play runs on nothing.

---

## Notes

- Always run a **check-mode** (`-check`) first; add `-diff` to see template changes.
- Handlers must be **idempotent**: restart only when config changes.
- Keep secrets out of git.

---

## Summary

- Built a minimal yet solid **Ansible** project: inventory, role, templates, handlers.
- Practiced **check-mode**, **diff**, **idempotence**, and **linting**.
- Prepared ground for next steps: multi-host inventory, group_vars, vault, and CI.

---

## Artifacts

- `ansible/` project with role `nginx_reverse_proxy`

---

## To repeat

- Duplicate the role for another service (e.g., Node exporter) to reinforce patterns.
- Add a `reload` handler path and conditionally use it when only logs/headers change.
- Try `-limit` to run on a subset of hosts and compare timings.

---

## Acceptance Criteria

- [ ]  `ansible-playbook site.yml` runs cleanly; second run **idempotent**.
- [ ]  `curl -sI http://127.0.0.1/` returns `200`; `/health` returns `OK`.
- [ ]  Any template change triggers **handler**; `nginx -t` passes before restart.
- [ ]  `ansible-lint` has no blocking issues.