# Prep evening

---

# Ansible Roles Testing: Molecule + Testinfra + ansible-lint

**Date:** 2025-11-27

**Topic:** Turn an Ansible role into a **tested, repeatable unit** using Molecule (Docker driver), Testinfra/pytest, and ansible-lint.

---

## Goals

- Create a **generic Ansible role** `lab_common` for host baseline (packages, user, motd).
- Use **Molecule** with Docker driver to spin up a test host and apply the role.
- Verify results with **Testinfra** (pytest-style tests).
- Run **`molecule test`** end-to-end: create → converge → verify → destroy.
- Add **ansible-lint** for basic quality checks.

---

## Pocket Cheat

| Command / File | What it does | Why |
| --- | --- | --- |
| `ansible-galaxy init lab_common --init-path roles` | Create role skeleton | Clean structure |
| `molecule init scenario default -r lab_common -d docker` | Add Molecule scenario | Testing scaffold |
| `molecule test` | Full cycle (create→converge→verify→destroy) | One button QA |
| `molecule converge` | Apply role to test instance | Debug play |
| `molecule login` | Shell into test container | Manual checks |
| `tests/test_default.py` | Testinfra tests | Assert state |
| `ansible-lint` | Lint Ansible content | Catch bad patterns |

---

## Notes

- A **separate, clean role** that can be applied both to lab hosts and to future servers.
- Molecule spins up a **Docker container** as a “virtual host”, applies the Ansible role to it, and Testinfra verifies the result.
- The idea is that any role (including future ones like `lab25_stack` and `docker_host`) can be wrapped in a Molecule scenario with tests in the same way.

---

## Security Checklist

- Do not put passwords or private keys into the role; at most, only public SSH keys.
- Avoid granting overly broad sudo privileges unless they are truly necessary.
- Do not run unnecessary services in the test container — we only need a minimal base host.

---

## Pitfalls

- Molecule requires Docker and the Python tooling (`molecule`, `pytest`, `testinfra`).
- Images like `geerlingguy/docker-ubuntu2204-ansible` already have Ansible preinstalled — convenient, but you still need to read the logs.
- If you forget `become: true`, some tasks (packages, files) will fail inside the container.
- `molecule test` **destroys** the container at the end; for interactive debugging it’s better to use `create + converge + login`.

---

## Layout

```
labs/prep_evening/
└─ ansible/
   └─ roles/
      └─ lab_common/
         ├─ tasks/
         │  └─ main.yml
         ├─ templates/
         │  └─ motd.j2
         ├─ defaults/
         │  └─ main.yml
         ├─ meta/
         │  └─ main.yml
         ├─ ansible.cfg
         └─ molecule/
            └─ default/
               ├─ molecule.yml
               ├─ converge.yml
               ├─ verify.yml
               └─ tests/
                  └─ test_default.py
```

---

## 1) Prepare role skeleton

From repo root:

```bash
mkdir -p labs/prep_evening/ansible
cd labs/prep_evening/ansible

ansible-galaxy init lab_common --init-path roles
```

Create `roles/lab_common` skeleton.

---

## 2) Define role behavior: `lab_common`

### 2.1 Defaults (config knobs)

`labs/prep_evening/ansible/roles/lab_common/defaults/main.yml`:

```yaml
---
lab_common_packages:
  - curl
  - vim
  - htop

lab_common_user: "labops_user"
lab_common_group: "labops_group"
lab_common_create_user: true

lab_common_motd_enabled: true
lab_common_motd_message: "Welcome to lab host (managed by lab_common)"
```

### 2.2 MOTD template

`labs/prep_evening/ansible/roles/lab_common/templates/motd.j2`:

```
{{ lab_common_motd_message }}
Managed by role: lab_common
User: {{ lab_common_user }}
```

### 2.3 Tasks

`labs/prep_evening/ansible/roles/lab_common/tasks/main.yml`:

```yaml
---
- name: Update apt cache
  ansible.builtin.apt:
    update_cache: true
    cache_valid_time: 3600
    
- name: Ensure common packages are installed
  ansible.builtin.package:
    name: "{{ lab_common_packages }}"
    state: present

- name: Ensure lab_common group exists
  ansible.builtin.group:
    name: "{{ lab_common_group }}"
    state: present
  when: lab_common_create_user

- name: Ensure lab_common user exists
  ansible.builtin.user:
    name: "{{ lab_common_user }}"
    group: "{{ lab_common_group }}"
    shell: /bin/bash
    create_home: true
    state: present
  when: lab_common_create_user

- name: Deploy /etc/motd if enabled
  ansible.builtin.template:
    src: motd.j2
    dest: /etc/motd
    owner: root
    group: root
    mode: "0644"
  when: lab_common_motd_enabled
```

> The role does three straightforward things: manages packages, creates the user/group, and configures the MOTD. All of this is easy to test in a container.
> 

---

## 3) Add Molecule scenario

Install the dependencies:

```bash
# 1. Создать venv
python3 -m venv .venv
# 2. Активировать
source .venv/bin/activate
# 3. Обновить pip внутри venv (по желанию)
python -m pip install --upgrade pip
# 4. Поставить тестовые зависимости
python -m pip install molecule molecule-plugins[docker] ansible ansible-lint pytest testinfra
```

Initializing the script:

```bash
cd labs/prep_evening/ansible/roles/lab_common
molecule init scenario default
```

---

## 4) Configure Molecule: `molecule.yml`

`labs/prep_evening/ansible/roles/lab_common/molecule/default/molecule.yml`:

```yaml
---
dependency:
  name: galaxy
  options:
    ignore-certs: false
    ignore-errors: false

driver:
  name: docker

platforms:
  - name: lab_evening-ubuntu
    image: geerlingguy/docker-ubuntu2204-ansible:latest
    pre_build_image: true
    privileged: true
    command: /lib/systemd/systemd
    volumes:
      - /sys/fs/cgroup:/sys/fs/cgroup:ro

provisioner:
  name: ansible
  playbooks:
    create: create.yml
    converge: converge.yml
    verify: verify.yml
    destroy: destroy.yml
  config_options:
    defaults:
      host_key_checking: false
      stdout_callback: ansible.builtin.default
    callback_default:
      result_format: yaml
  env:
    ANSIBLE_FORCE_COLOR: "1"
    ANSIBLE_LOAD_CALLBACK_PLUGINS: "1"
    ANSIBLE_ROLES_PATH: "${MOLECULE_PROJECT_DIRECTORY}/.."
    ANSIBLE_REMOTE_TMP: /tmp

scenario:
  name: default
  test_sequence:
    - destroy
    - create
    - converge
    - verify

verifier:
  name: testinfra
  options:
    v: true
  directory: ./tests
```

> Use an image with Ansible already installed. `privileged` + `systemd` are enabled because that’s how the image is designed — it’s the standard pattern geerlingguy uses for Ansible testing.
> 

---

## 5) Converge playbook

`labs/prep_evening/ansible/roles/lab_common/molecule/default/converge.yml`:

```yaml
---
- name: Converge lab_common
  hosts: all
  become: true
  roles:
    - role: lab_common
      vars:
        lab_common_motd_message: "Welcome to Molecule lab host"
```

---

## 6) Verify playbook + Testinfra

For Molecule v4, Testinfra is enough. You can keep `verify.yml` very simple:

`labs/prep_evening/ansible/roles/lab_common/molecule/default/verify.yml`:

```yaml
---
- name: Verify using Testinfra
  hosts: all
  gather_facts: false # Quicker, if do not need facts
  tasks: []
```

### Testinfra tests

Create dir:

```bash
mkdir -p molecule/default/tests
```

`labs/prep_evening/ansible/roles/lab_common/molecule/default/tests/test_default.py`:

```python
import pytest

def test_packages_installed(host):
    pkgs = ["curl", "vim", "htop"]
    for name in pkgs:
        pkg = host.package(name)
        assert pkg.is_installed, f"Package {name} should be installed"

def test_lab_user_exists(host):
    user = host.user("labops_user")
    assert user.exists
    assert user.group == "labops_group"
    assert "/home/labops_user" in user.home

def test_motd_content(host):
    motd = host.file("/etc/motd")
    assert motd.exists
    assert motd.user == "root"
    assert motd.group == "root"
    assert motd.mode & 0o644 == 0o644

    content = motd.content_string
    assert "Welcome to Molecule lab host" in content
    assert "lab_common" in content
    assert "labops_user" in content
```

> There are three simple tests here: packages, user, and MOTD. It makes it very clear what the role does.
> 

---

## 7) Run Molecule

From the role directory:

```bash
cd labs/prep_evening/ansible/roles/lab_common

# full cicle:
molecule test
```

Step by step:

```bash
molecule create      # поднять контейнер
molecule converge    # применить роль
molecule verify      # прогнать Testinfra
molecule login       # зайти внутрь контейнера (для ручного осмотра)
molecule destroy     # убрать контейнер
```

Inside `molecule login` can check it manually:

```bash
# inside container
id labops_user
grep lab_common /etc/motd || echo "no motd line"
dpkg -l curl vim htop | head
exit
```

---

## 8) ansible-lint

Run from the repo or from the role directory:

```bash
ansible-lint labs/prep_evening/ansible/roles/lab_common
# or
ansible-lint .
```

---

## Core

- [ ]  The `lab_common` role is created and **locally coherent** (packages, user, MOTD).
- [ ]  `molecule test` in `roles/lab_common` runs without errors.
- [ ]  Testinfra confirms that the packages/user/MOTD are present.
- [ ]  Add more options to the role (for example: extra packages, managing `/etc/sudoers.d/labops_group`).
- [ ]  Add more tests (sudo rules, existence of the home directory, etc.).
- [ ]  Integrate `ansible-lint` into regular workflow (for example via `pre-commit`).
- [ ]  Try adding a second Molecule scenario (for example a `minimal` scenario with MOTD disabled or with a different user).

---

## Acceptance Criteria

- [ ]  There is a **full-fledged Ansible role** `lab_common` with clear behavior.
- [ ]  The role is covered by **Molecule + Testinfra** tests — `molecule test` is green.
- [ ]  Understand how to use Docker platforms in Molecule for Ansible roles.
- [ ]  `ansible-lint` doesn’t complain about basic things (or any warnings are clear and fixable).

---

## Summary

- **Wrote a role that has tests.**
- Learned the basic Molecule cycle: create → converge → verify → destroy.
- Integrated Testinfra/pytest to verify host state at the level of files/packages/users.

---

## Artifacts

- `prep_evening.md`
- `labs/prep_evening/ansible/roles/lab_common/` with all files:
    - `defaults/main.yml`
    - `tasks/main.yml`
    - `templates/motd.j2`
    - `molecule/default/{molecule.yml,converge.yml,verify.yml,tests/test_default.py}`