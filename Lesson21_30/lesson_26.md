# lesson_26

---

# Ansible + Docker: Deploying a Docker Compose Stack to a Host

**Date:** 2025-11-25

**Topic:** Use Ansible to install Docker Engine on a host, deploy a Docker Compose stack (lab25-style app), and manage lifecycle (up/ps/logs/update) idempotently.

---

## Goals

- Use **Ansible** to provision a **Docker host** (install Docker Engine + compose plugin).
- Copy **lab25** Compose files to the host in a clean structure.
- Run `docker compose up -d` via Ansible **idempotently**.
- Add a small **“update”** flow: pull new image and restart stack.
- Use **inventory** and **group_vars** to separate host config from playbook logic.

---

## Pocket Cheat

| Command / File | What it does | Why |
| --- | --- | --- |
| `labs/lesson_26/ansible/inventory.ini` | Hosts definition | Where to deploy |
| `lab26_docker.yml` | Main playbook | Provision & deploy |
| `roles/docker_host/` | Install Docker on host | Reusable role |
| `roles/lab25_stack/` | Deploy lab25-compose stack | Reusable app role |
| `ansible-playbook -i inventory.ini lab26_docker.yml` | Run whole thing | One command |
| `docker ps`, `docker compose ps` | Check stack | Sanity |
| `ansible-playbook ... --tags update` | Only update stack | Quick rollout |

---

## Notes

- Don’t depend on a specific container registry: the `lab25` image can be local, or pulled from GHCR / Docker Hub.
- Ansible will:
    1. Install Docker (if it’s not already installed).
    2. Create the `/opt/lab25/` directory on the target host.
    3. Copy `docker-compose.yml` into that directory.
    4. Run `docker compose up -d`.
- You can run this both over SSH to a remote host and on `localhost`.
- The roles (`docker_host`, `lab25_stack`) are designed to be reusable, so we can plug them into other projects later.

---

## Security Checklist

- Don’t store passwords/tokens directly in playbooks. Use `group_vars` and Ansible Vault for any secrets.
- If you deploy to a real remote host, check UFW/firewall rules so that only the required ports are open.
- Don’t mess with Docker daemon / rootless settings “just because”. On production this needs a separate, careful design.
- SSH access to the host (in a real environment) should be key-based, not password-based.

---

## Pitfalls

- Wrong `hosts:` value → the playbook runs “successfully” but doesn’t actually do anything.
- Missing `become: true` → Ansible can’t install packages or create directories.
- Incorrect path to `docker-compose.yml` → `docker compose` fails.
- Mixing manual stack runs with Ansible runs → becomes unclear what state the stack is in and who changed what.

---

## Layout

```
labs/lesson_26/
└─ ansible/
   ├─ inventory.ini
   ├─ lab26_docker.yml
   ├─ group_vars/
   │  └─ all.yml
   └─ roles/
      ├─ docker_host/
      │  ├─ defaults/main.yml
      │  └─ tasks/main.yml
      └─ lab25_stack/
         ├─ handlers/main.yml
         ├─ tasks/main.yml
         └─ templates/docker-compose.yml.j2
```

> `lab25` already exists (the image is built and pushed to a registry, see `lesson_25`).
> 
> 
> Use the image **from the registry**, not a local build, to make it closer to a real-world scenario.
> 

---

## 1) Inventory: where to deploy

`labs/lesson_26/ansible/inventory.ini`:

```
[lab_docker_hosts]
# For local testing:
localhost ansible_connection=local

# For remote host example:
# lab-docker-1 ansible_host=192.0.2.10 ansible_user=youruser
```

> To deploy directly to a remote machine, uncomment/update the host entry and configure SSH access.
> 

---

## 2) group_vars: registry image & stack settings

`labs/lesson_26/ansible/group_vars/all.yml`:

```yaml
# Docker package settings
docker_package_state: present

# Lab25 image settings
lab25_image: "ghcr.io/vlrrbn/lab25-web-workflows:latest"

lab25_stack_dir: "/opt/lab25"
lab25_compose_filename: "docker-compose.yml"

lab25_web_port: 8080
lab25_lab_env: "lab"
lab25_redis_image: "redis:7-alpine"

```

> Change `lab25_image` once, and Ansible will deploy the desired image tag on the host.
> 

---

## 3) Role `docker_host`: install Docker engine + compose plugin

`labs/lesson_26/ansible/roles/docker_host/defaults/main.yml`:

```yaml
docker_package_state: present
```

`labs/lesson_26/ansible/roles/docker_host/tasks/main.yml` (simplified variant for Ubuntu/Debian):

```yaml
- name: Ensure apt packages for Docker are installed
  become: true
  apt:
    name:
      - ca-certificates
      - curl
      - gnupg
      - lsb-release
    state: present
    update_cache: true

- name: Remove distro-provided Docker packages
  become: true
  apt:
    name:
      - docker.io
      - docker-compose
      - docker-compose-v2
      - docker-doc
      - podman-docker
      - containerd
      - runc
    state: absent
    purge: true

- name: Ensure /etc/apt/keyrings directory exists
  become: true
  ansible.builtin.file:
    path: /etc/apt/keyrings
    state: directory
    mode: "0755"

- name: Add Docker GPG key
  become: true
  ansible.builtin.shell: |
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
      gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  args:
    creates: /etc/apt/keyrings/docker.gpg

- name: Add Docker apt repository
  become: true
  ansible.builtin.copy:
    dest: /etc/apt/sources.list.d/docker.list
    content: |
      deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu {{ ansible_distribution_release }} stable
    mode: "0644"

- name: Install Docker Engine and compose plugin
  become: true
  apt:
    name:
      - docker-ce
      - docker-ce-cli
      - containerd.io
      - docker-buildx-plugin
      - docker-compose-plugin
    state: "{{ docker_package_state }}"
    update_cache: true

- name: Ensure docker service enabled and started
  become: true
  service:
    name: docker
    enabled: true
    state: started
```

> This is good enough for lab environments. For production you’ll need additional tuning (storage driver, logging, etc.).
> 

---

## 4) Role `lab25_stack`: deploy compose stack

### 4.1 Template for docker-compose

`labs/lesson_26/ansible/roles/lab25_stack/templates/docker-compose.yml.j2`:

```yaml
services:
  web:
    image: {{ lab25_image | quote }}
    container_name: lab25-web-workflows
    environment:
      LAB_ENV: {{ lab25_lab_env | quote }}
      PORT: "8080"
      REDIS_HOST: "redis"
      REDIS_PORT: "6379"
      REDIS_DB: "0"
    ports:
      - "127.0.0.1:{{ lab25_web_port }}:8080"
    depends_on:
      redis:
        condition: service_healthy
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS http://127.0.0.1:8080/health || exit 1"]
      interval: 30s
      timeout: 3s
      retries: 3
      start_period: 15s
    networks:
      - backend

  redis:
    image: {{ lab25_redis_image | quote }}
    container_name: lab25-redis
    command: ["redis-server", "--save", "60", "1", "--loglevel", "warning"]
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 3s
      retries: 5
      start_period: 5s
    restart: unless-stopped
    networks:
      - backend

networks:
  backend:
    driver: bridge

volumes:
  redis_data:
```

### 4.2 Tasks for stack role

`labs/lesson_26/ansible/roles/lab25_stack/tasks/main.yml`:

```yaml
---
- name: Ensure lab25 stack directory exists
  become: true
  file:
    path: "{{ lab25_stack_dir }}"
    state: directory
    owner: root
    group: root
    mode: "0755"

- name: Deploy lab25 docker-compose.yml
  become: true
  template:
    src: docker-compose.yml.j2
    dest: "{{ lab25_stack_dir }}/{{ lab25_compose_filename }}"
    owner: root
    group: root
    mode: "0644"
  notify:
    - redeploy lab25 stack

- name: Ensure lab25 stack is up (docker compose up -d)
  become: true
  args:
    chdir: "{{ lab25_stack_dir }}"
  ansible.builtin.command: >
    docker compose -f {{ lab25_compose_filename }} up -d
  register: compose_up
  changed_when: "'Creating' in compose_up.stdout or 'Recreating' in compose_up.stdout or 'Pulling' in compose_up.stdout"
```

> Use the `command` module instead of the `docker_compose` module, we don’t have to pull in extra collections.
> 

### 4.2 Tasks for stack role

`labs/lesson_26/ansible/roles/lab25_stack/handlers/main.yml`:

```yaml
- name: stop lab25 stack
  become: true
  args:
    chdir: "{{ lab25_stack_dir }}"
  ansible.builtin.command: >
    docker compose -f {{ lab25_compose_filename }} down
  listen: "redeploy lab25 stack"

- name: start lab25 stack
  become: true
  args:
    chdir: "{{ lab25_stack_dir }}"
  ansible.builtin.command: >
    docker compose -f {{ lab25_compose_filename }} up -d
  listen: "redeploy lab25 stack"
```

---

## 5) Main playbook

`labs/lesson_26/ansible/lab26_docker.yml`:

```yaml
---
# Host & Deploy
- name: Provision Docker host and deploy lab25 stack
  hosts: lab_docker_hosts
  become: true

  vars:
    docker_package_state: present

  roles:
    - docker_host
    - lab25_stack

# Update only
- name: Update lab25 stack only
  hosts: lab_docker_hosts
  become: true
  tags: update

  roles:
    - lab25_stack
```

Run:

```bash
cd labs/lesson_26/ansible
ansible-playbook -i inventory.ini lab26_docker.yml
```

---

## 6) Verify on host

If deployed it on `localhost`:

```bash
docker ps
docker compose -f /opt/lab25/docker-compose.yml ps
curl -s http://127.0.0.1:8080/ | jq
curl -s http://127.0.0.1:8080/health | jq
```

If deployed to a remote host, it’s the same, just over SSH:

```bash
ssh youruser@REMOTE_HOST 'docker ps'
ssh youruser@REMOTE_HOST 'docker compose -f /opt/lab25/docker-compose.yml ps'
ssh youruser@REMOTE_HOST 'curl -s http://127.0.0.1:8080/health'
```

---

## 7) Update flow (new image → rollout)

When CI (from `lesson_25`) publishes a new image tag, update `lab25_image` in `group_vars/all.yml`, for example:

```yaml
lab25_image: "ghcr.io/vlrrbn/lab25-web:main"
# or "ghcr.io/vlrrbn/lab25-web:sha-1234567"
```

Then:

```bash
cd labs/lesson_26/ansible
ansible-playbook -i inventory.ini lab26_docker.yml
```

Ansible will:

- Replace the compose file (if any fields have changed).
- Run `docker compose up -d` (pull and recreate the required containers).

If you need a separate **update** tag, you can create one like:

```yaml
# lab26_docker.yml
- name: Update lab25 stack only
  hosts: lab_docker_hosts
  become: true
  tags: update
  roles:
    - lab25_stack
```

Then:

```bash
ansible-playbook -i inventory.ini lab26_docker.yml --tags update
```

---

## Core

- [ ]  The `docker_host` role installs Docker and starts the daemon.
- [ ]  The `lab25_stack` role creates `/opt/lab25/docker-compose.yml` and brings the stack up.
- [ ]  `ansible-playbook -i inventory.ini lab26_docker.yml` successfully deploys to either `localhost` or a remote host.
- [ ]  `/` and `/health` on port 8080 respond, and Redis is working (the counter increases).
- [ ]  Deployment to a **separate host** over SSH (not `localhost`).
- [ ]  Changing `lab25_image` (new tag) + running the playbook results in an updated container (`docker ps` shows the new image ID).
- [ ]  A separate play with `tags update` is added, which doesn’t touch Docker installation, only the stack itself.
- [ ]  Common settings (port, directory, etc.) are moved to `group_vars`; the playbook stays clean and short.

---

## Acceptance Criteria

- [ ]  Can provision a Docker host and the `lab25` stack **from scratch** with a single `ansible-playbook …` command.
- [ ]  No longer need to SSH into the host and run `docker compose up -d` manually.
- [ ]  Basic changes (image tag, port, env vars) are controlled via vars, not by editing the compose file directly on the host.
- [ ]  Scripts/commands are safe to rerun: the playbook is idempotent (a second run makes almost no changes).

---

## Summary

- Wired **Ansible** together with **Docker/Compose**, also **roll out stacks to hosts** declaratively.
- Split the logic into two roles:
    - `docker_host` — installs and prepares the host.
    - `lab25_stack` — deploys and updates the specific Compose stack.
- Set up a basic update flow: change the image tag → run the playbook → clean, controlled rollout.

---

## Artifacts

- `lesson_26.md`
- `labs/lesson_26/ansible/inventory.ini`
- `labs/lesson_26/ansible/lab26_docker.yml`
- `labs/lesson_26/ansible/group_vars/all.yml`
- `labs/lesson_26/ansible/roles/docker_host/{defaults/main.yml,tasks/main.yml}`
- `labs/lesson_26/ansible/roles/lab25_stack/{handlers/main.yml,tasks/main.yml,templates/docker-compose.yml.j2}`