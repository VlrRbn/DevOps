# lesson_16

---

# Ansible Role Testing: Molecule + Testinfra + CI

**Date:** **2025-10-06**

**Topic:** Molecule scenarios for your `nginx_reverse_proxy` role, idempotence tests, Testinfra checks, ansible-lint, and GitHub Actions CI (matrix)

---

## Goals

- Add **Molecule** tests to the `nginx_reverse_proxy` role.
- Verify **converge → idempotence → verify → destroy** locally.
- Write **Testinfra** (pytest) checks: port open, health endpoint, config present.
- Run **ansible-lint** automatically.
- Wire up **GitHub Actions** CI to run tests on multiple Ubuntu versions.

---

## Pocket Cheat

| Command | What it does |
| --- | --- |
| `python3 -m venv .venv && source .venv/bin/activate` | Isolated env |
| `pip install ansible molecule-plugins[docker] molecule ansible-lint pytest testinfra` | Tooling |
| `molecule init scenario -r roles/nginx_reverse_proxy -s default -d docker` | Create scenario |
| `molecule converge` | Apply role in container |
| `molecule idempotence` | Ensure second run changes=0 |
| `molecule verify` | Run Testinfra |
| `molecule destroy` | Clean up |
| `ansible-lint` | Lint role |

---

## Project Layout

```
ansible_molecule/
├─ ansible.cfg
├─ inventory
├─ requirements
├─ site.yml
└─ roles/
   └─ nginx_reverse_proxy/
      ├─ default/
         └─main.yml
      ├─ handlers/
         └─main.yml
      ├─ meta/
         └─main.yml
      ├─ tasks/
         └─main.yml
      ├─ templates
         └─site.conf.j2
      └─ molecule/
         └─ default/
            ├─ collections.yml
            ├─ converge.yml
            ├─ create.yml
            ├─ destroy.yml
            ├─ molecule.yml
            ├─ prepare.yml
            ├─ verify.yml
            └─ tests/test_default.py
.github/
└─ workflows/
   └─ ansible-role-ci.yml
```

---

## Setup and create

```bash
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"
newgrp docker

mkdir -p ~/ansible_molecule
cd ~/ansible_molecule

python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip

#  Ansible + Molecule v6 + plugins + tests
pip install ansible molecule molecule-plugins[docker] ansible-lint pytest testinfra

mkdir -p ansible/{inventories/dev,roles/nginx_reverse_proxy/{tasks,handlers,defaults,templates,meta}}

cd ~/ansible_molecule/roles/nginx_reverse_proxy
molecule init scenario default
```

### `ansible_molecule/ansible.cfg`

```bash
---
[defaults]
inventory = ./inventory
retry_files_enabled = False
deprecation_warnings = False
forks = 20
stdout_callback = yaml
host_key_checking = False
interpreter_python = auto_silent
roles_path = ./roles
ansible_managed = Managed by Ansible

[privilege_escalation]
become = True
become_method = sudo
become_ask_pass = False
```

### `ansible_molecule/inventory`

```bash
---
[web]
web1 ansible_host=localhost ansible_user=leprecha
```

### `ansible_molecule/site.yml`

```yaml
---
- name: Lab16 - apply nginx reverse proxy
  hosts: web
  gather_facts: true
  roles:
    - role: nginx_reverse_proxy
```

### `ansible_molecule/requirements.txt`

```yaml
---
ansible>=9
molecule>=6
molecule-plugins[docker]>=23.5.0
ansible-lint>=24
pytest>=8
testinfra>=6
```

### `ansible_molecule/roles/nginx_reverse_proxy/defaults/main.yml`

```yaml
---
nginx_reverse_proxy_site_name: lab16
nginx_reverse_proxy_backend_host: backend
nginx_reverse_proxy_backend_port: 8081
nginx_reverse_proxy_http_port: 80
nginx_reverse_proxy_health_path: /health
nginx_reverse_proxy_access_log_json: /var/log/nginx/access.log
nginx_reverse_proxy_use_become: false
```

### `ansible_molecule/roles/nginx_reverse_proxy/handlers/main.yml`

```yaml
---
- name: Validate nginx config
  listen: "restart nginx"
  become: "{{ nginx_reverse_proxy_use_become | default(false) }}"
  ansible.builtin.command: nginx -t
  changed_when: false

- name: Systemd restart nginx
  listen: "restart nginx"
  become: "{{ nginx_reverse_proxy_use_become | default(false) }}"
  ansible.builtin.systemd:
    name: nginx
    state: restarted
    enabled: true
    daemon_reload: true

- name: Systemd reload nginx
  listen: "reload nginx"
  become: "{{ nginx_reverse_proxy_use_become | default(false) }}"
  ansible.builtin.systemd:
    name: nginx
    state: reloaded
```

### `ansible_molecule/roles/nginx_reverse_proxy/meta/main.yml`

```yaml
---
galaxy_info:
  author: leprecha
  description: Simple Nginx reverse proxy with /health
  license: MIT
  min_ansible_version: "2.14"
dependencies: []
```

### `ansible_molecule/roles/nginx_reverse_proxy/tasks/main.yml`

```yaml
- name: Install nginx and tools
  ansible.builtin.apt:
    name:
      - nginx
      - curl
      - iproute2
    state: present
    update_cache: true
  become: "{{ nginx_reverse_proxy_use_become }}"

- name: Deploy site config
  ansible.builtin.template:
    src: site.conf.j2
    dest: "/etc/nginx/sites-available/{{ nginx_reverse_proxy_site_name }}.conf"
    mode: "0644"
  notify: restart nginx

- name: Enable site
  ansible.builtin.file:
    src: "/etc/nginx/sites-available/{{ nginx_reverse_proxy_site_name }}.conf"
    dest: "/etc/nginx/sites-enabled/{{ nginx_reverse_proxy_site_name }}.conf"
    state: link
  notify: restart nginx

- name: Disable default site if present
  ansible.builtin.file:
    path: /etc/nginx/sites-enabled/default
    state: absent
  notify: restart nginx

- name: Nginx syntax check
  ansible.builtin.command: nginx -t
  changed_when: false

- name: Ensure nginx service
  ansible.builtin.service:
    name: nginx
    state: started
    enabled: true
  become: "{{ nginx_reverse_proxy_use_become }}"
```

### `ansible_molecule/roles/nginx_reverse_proxy/templates/site.conf.j2`

```bash
server {
  listen {{ nginx_reverse_proxy_http_port }};
  server_name _;

  location {{ nginx_reverse_proxy_health_path }} {
    default_type text/plain;
    return 200 "OK\n";
  }

  location / {
    proxy_pass http://{{ nginx_reverse_proxy_backend_host }}:{{ nginx_reverse_proxy_backend_port }};
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
  }

  access_log {{ nginx_reverse_proxy_access_log_json }};
  error_log  /var/log/nginx/error.log;
}
```

### `ansible_molecule/roles/nginx_reverse_proxy/molecule/default/converge.yml`

```yaml
---
- name: Converge
  hosts: all
  gather_facts: true

  vars:
    role_dir: "{{ (playbook_dir ~ '/..' ~ '/..') | realpath }}"

    nginx_reverse_proxy_site_name: lab16
    nginx_reverse_proxy_use_become: false
    nginx_reverse_proxy_backend_host: backend
    nginx_reverse_proxy_backend_port: 8081
    nginx_reverse_proxy_access_log_json: /var/log/nginx/access.log
    nginx_reverse_proxy_http_port: 80
    nginx_reverse_proxy_health_path: /health

  roles:
    - role: "{{ role_dir }}"

  tasks:
    - name: Sanity — path resolved
      ansible.builtin.debug:
        msg: "Applying role from {{ role_dir }}"
```

### `ansible_molecule/roles/nginx_reverse_proxy/molecule/default/create.yml`

```yaml
---
- name: Create
  hosts: localhost
  gather_facts: false
  vars:
    net_name: molecule_net
    proxy_name: instance
    backend_name: backend
    proxy_image: "jrei/systemd-ubuntu:24.04"
    backend_image: "python:3.12-slim"
  tasks:
    - name: Ensure network exists
      community.docker.docker_network:
        name: "{{ net_name }}"
        state: present

    - name: Ensure backend image present
      community.docker.docker_image:
        name: "{{ backend_image }}"
        source: pull

    - name: Run backend container (8081)
      community.docker.docker_container:
        name: "{{ backend_name }}"
        image: "{{ backend_image }}"
        state: started
        restart_policy: unless-stopped
        command: python -m http.server 8081 --bind 0.0.0.0
        networks:
          - name: "{{ net_name }}"

    - name: Ensure proxy image present
      community.docker.docker_image:
        name: "{{ proxy_image }}"
        source: pull

    - name: Run systemd-enabled proxy
      community.docker.docker_container:
        name: "{{ proxy_name }}"
        image: "{{ proxy_image }}"
        state: started
        restart_policy: unless-stopped
        privileged: true
        command: "/lib/systemd/systemd"
        cgroupns_mode: host
        tmpfs:
          - /run
          - /run/lock
        volumes:
          - /sys/fs/cgroup:/sys/fs/cgroup:rw
        env:
          container: docker
        networks:
          - name: "{{ net_name }}"
```

### `ansible_molecule/roles/nginx_reverse_proxy/molecule/default/destroy.yml`

```yaml
---
- name: Destroy
  hosts: localhost
  gather_facts: false
  vars:
    net_name: molecule_net
    proxy_name: instance
    backend_name: backend
  tasks:
    - name: Remove proxy
      community.docker.docker_container:
        name: "{{ proxy_name }}"
        state: absent
        force_kill: true
    - name: Remove backend
      community.docker.docker_container:
        name: "{{ backend_name }}"
        state: absent
        force_kill: true
    - name: Remove network
      community.docker.docker_network:
        name: "{{ net_name }}"
        state: absent
      failed_when: false
```

### `ansible_molecule/roles/nginx_reverse_proxy/molecule/default/molecule.yml`

```yaml
---
dependency:
  name: galaxy
  enabled: false

driver:
  name: docker

platforms:
  - name: instance
    image: "jrei/systemd-ubuntu:24.04"
    command: "/lib/systemd/systemd"
    privileged: true
    pre_build_image: true
    volumes:
      - /sys/fs/cgroup:/sys/fs/cgroup:rw
    env:
      container: docker
    published_ports:
      - "8080:80"

provisioner:
  name: ansible
  playbooks:
    create: create.yml
    destroy: destroy.yml
    prepare: prepare.yml
    converge: converge.yml
  inventory:
    hosts:
      all:
        hosts:
          instance:
            ansible_connection: docker
            ansible_python_interpreter: /usr/bin/python3
  config_options:
    defaults:
      roles_path: "${MOLECULE_PROJECT_DIRECTORY}/roles"
      remote_tmp: /tmp
      deprecation_warnings: false
  env:
    ANSIBLE_ROLES_PATH: "${MOLECULE_PROJECT_DIRECTORY}/roles"
    ANSIBLE_VERBOSITY: "2"

verifier:
  name: testinfra

lint: |
  set -e
  ansible-lint -v
```

### `ansible_molecule/roles/nginx_reverse_proxy/molecule/default/prepare.yml`

```yaml
---
- name: Prepare target for Ansible
  hosts: instance
  gather_facts: false
  tasks:
    - name: Ensure python3 and curl present
      ansible.builtin.raw: |
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -y
        apt-get install -y python3 python3-apt curl
      changed_when: false
```

### `ansible_molecule/roles/nginx_reverse_proxy/molecule/default/verify.yml`

```yaml
---
- name: Check health
  hosts: all
  gather_facts: false
  tasks:
    - name: Health endpoint returns 200
      ansible.builtin.uri:
        url: "http://127.0.0.1/health"
        method: HEAD
        status_code: 200
        return_content: false
```

### `ansible_molecule/roles/nginx_reverse_proxy/molecule/default/tests/test_default.py`

```python
def test_nginx_pkg(host):
    pkg = host.package("nginx")
    assert pkg.is_installed

def test_nginx_service(host):
    s = host.service("nginx")
    assert s.is_running
    assert s.is_enabled

def test_port_80_listening(host):
    sock = host.socket("tcp://0.0.0.0:80")
    assert sock.is_listening

def test_health_endpoint(host):
    cmd = host.run("curl -sI http://127.0.0.1/health")
    assert cmd.rc == 0
    assert "200" in cmd.stdout

def test_nginx_syntax_ok(host):
    cmd = host.run("nginx -t")
    assert cmd.rc == 0
```

---

## Run locally

```bash
cd ansible_molecule/roles/nginx_reverse_proxy
molecule destroy
molecule create
docker ps -a | grep -E 'instance|backend'     # all 2 UP
molecule prepare
molecule converge
molecule idempotence
molecule verify

# molecule test -s default

ansible-lint
```

---

## CI: GitHub Actions

### `.github/workflows/ansible-role-ci.yml`

```yaml
name: Ansible Role CI

on:
  push:
  pull_request:

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

jobs:
  lint_and_test:
    runs-on: ${{ matrix.os }}
    strategy:
      fail-fast: false
      matrix:
        os: [ubuntu-22.04, ubuntu-24.04]
        py: ["3.11", "3.12"]

    env:
      XDG_CACHE_HOME: ${{ github.workspace }}/.cache
      ANSIBLE_COLLECTIONS_PATH: ${{ github.workspace }}/.lint-collections

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: ${{ matrix.py }}
          cache: pip

      - name: Install dependencies
        working-directory: ansible_molecule
        run: |
          python -m pip install --upgrade pip
          if [ -f requirements.txt ]; then
            pip install -r requirements.txt
          else
            pip install \
              "ansible>=9" \
              "molecule>=6" \
              "molecule-plugins[docker]>=23.5.0" \
              "ansible-lint>=24" \
              "pytest>=8" \
              "testinfra>=6,<7"
          fi

      - name: Prep caches and limits
        run: |
          mkdir -p "$XDG_CACHE_HOME" "$ANSIBLE_COLLECTIONS_PATH" || true
          ulimit -n 4096 || true
          docker --version
          ansible --version
          molecule --version

      - name: Install minimal collections for lint
        run: |
          ansible-galaxy collection install community.general community.docker -p "$ANSIBLE_COLLECTIONS_PATH"

      - name: Ansible Lint (role only)
        working-directory: ansible_molecule
        run: |
          ansible-lint roles/nginx_reverse_proxy

      - name: Molecule test (default scenario)
        working-directory: ansible_molecule/roles/nginx_reverse_proxy
        env:
          ANSIBLE_ROLES_PATH: ${{ github.workspace }}/ansible_molecule/roles
          MOLECULE_NO_LOG: "false"
        run: |
          molecule test -s default

      - name: Upload logs on failure
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: molecule-logs-${{ matrix.os }}-py${{ matrix.py }}
          path: |
            /home/runner/.ansible/tmp/**/*
            ansible_molecule/roles/nginx_reverse_proxy/molecule/**/.molecule/**/*
          if-no-files-found: ignore
```

---

## Pitfalls

- Systemd in containers: use images that run `/lib/systemd/systemd` and `privileged: true`.
- Don’t overuse `shell:` in roles; it breaks idempotence and lint.
- Keep tests **fast**.

---

## Summary

- Wrapped your role in **repeatable tests** (Molecule + Testinfra).
- Proved **idempotence** and basic functionality automatically.
- Wired **CI** to catch regressions on push/PR.
- Foundation set for expanding tests (TLS scenario, limits, cache).

---

## Artifacts

- `ansible_molecule/roles/nginx_reverse_proxy/molecule/default/…` (scenario)
- `.github/workflows/ansible-role-ci.yml`

---

## To repeat

- Add a `https` scenario with self-signed cert; verify 443 and `/health` over HTTPS.
- Test rate-limits: return 429 under load (short curl loop) and assert in Testinfra.
- Publish role on Galaxy after stabilizing CI.

---

## Acceptance Criteria

- [ ]  `molecule idempotence` shows **success** (no changes on 2nd run).
- [ ]  `molecule verify` green; Testinfra asserts pass.
- [ ]  `ansible-lint` passes (no blockers).
- [ ]  GitHub Actions workflow green on at least one Ubuntu image.