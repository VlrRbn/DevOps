# molecule

---

# 1. Команды

```bash
# Инициализация
molecule init role myrole
molecule init scenario -r myrole -s dev

# Жизненный цикл
molecule create
molecule converge
molecule verify
molecule idempotence
molecule destroy
molecule test                      # полный цикл
molecule check                     # сухой прогон, если настроен
molecule list                      # список инстансов (или инфо по сценариям)
molecule login                     # зайти внутрь для отладки
molecule matrix                    # показать последовательность шагов
molecule reset                     # почистить времянку Molecule

# Частые флаги
molecule <cmd> -s default          # выбрать сценарий
molecule test --all                # все сценарии
molecule test --destroy=never      # не сносить окружение (для отладки)
molecule <cmd> --parallel          # параллельно, где поддерживается
molecule <cmd> --debug -- -vvv     # подробный вывод ansible-playbook
```

### Официальная справка по CLI, доступные действия и флаги. ([ansible.readthedocs.io](https://ansible.readthedocs.io/projects/molecule/usage/))

### Референс по workflow и последовательностям (какие шаги выполняются в `test`). ([ansible.readthedocs.io](https://ansible.readthedocs.io/projects/molecule/workflow/))

---

# 2. Современная модель: **ansible-native** (Molecule v6+)

Molecule — исполняет плейбуки `create.yml`, `prepare.yml`, `converge.yml`, `verify.yml`, `destroy.yml`. 

Ключевые моменты:

- Molecule генерит **доп. инвентарь** (переменные `MOLECULE_*`) и дергает плейбуки по шагам. ([ansible.readthedocs.io](https://ansible.readthedocs.io/projects/molecule/ansible-native/))
- Последовательности настраиваются в секции `scenario:` в `molecule.yml` (можно добавлять несколько `verify`/`side_effect`, дублировать `converge` и проверять идемпотентность несколько раз). ([ansible.readthedocs.io](https://ansible.readthedocs.io/projects/molecule/configuration/))

### Минимальный скелет сценария

```
molecule/
└── default/
    ├── molecule.yml
    ├── create.yml
    ├── prepare.yml
    ├── converge.yml
    ├── verify.yml
    └── destroy.yml
```

### Настройка последовательностей (пример)

```yaml
# molecule/default/molecule.yml
scenario:
  test_sequence:
    - dependency
    - cleanup
    - destroy
    - syntax
    - create
    - prepare
    - converge
    - idempotence
    - side_effect reboot.yml
    - verify verify_after_reboot/
    - cleanup
    - destroy
```

Можно передавать аргументы в `side_effect`/`verify`, и вызывать `converge`/`idempotence` многократно. ([ansible.readthedocs.io](https://ansible.readthedocs.io/projects/molecule/configuration/))

---

# 3. Примеры плейбуков под контейнеры (Docker/Podman)

## Вариант: **Podman** (через коллекцию `containers.podman`)

**create.yml**

```yaml
- hosts: localhost
  gather_facts: false
  tasks:
    - name: Create network
      containers.podman.podman_network:
        name: mol_net
        state: present

    - name: Run test container
      containers.podman.podman_container:
        name: web1
        image: "docker.io/library/ubuntu:24.04"
        state: started
        command: sleep infinity
        networks: [mol_net]

    - name: Add to inventory
      add_host:
        name: web1
        ansible_host: 127.0.0.1
        ansible_connection: podman
      changed_when: false
```

**converge.yml**

```yaml
- hosts: web1
  gather_facts: true
  roles:
    - role: myrole
```

**verify.yml**

```yaml
- hosts: web1
  tasks:
    - name: nginx слушает 80
      ansible.builtin.wait_for:
        port: 80
        timeout: 3
```

**destroy.yml**

```yaml
- hosts: localhost
  gather_facts: false
  tasks:
    - containers.podman.podman_container:
        name: web1
        state: absent
    - containers.podman.podman_network:
        name: mol_net
        state: absent
```

## Вариант: **Docker**

Аналогично, только модули `community.docker.*` в плейбуках `create`/`destroy`. Базовые принципы те же.

---

# 4. Проверки (verifier)

- **Ansible — дефолт** (v3+). Писать проверки в `verify.yml` с `assert/uri/stat/command`. ([ansible.readthedocs.io](https://ansible.readthedocs.io/projects/molecule/configuration/))
- **Testinfra**: больше не дефолт, многие проекты всё ещё пользуют; ставится отдельно и настраивается в `verifier:`. ([ansible.readthedocs.io](https://ansible.readthedocs.io/projects/molecule/configuration/))

---

# 5. Полезнейшие трюки CLI

- Передавать extra-аргументы в Ansible:
    
    ```bash
    molecule converge -- -vvv --tags "nginx,firewall"
    ```
    
    (всё после `--` уходит в `ansible-playbook`). ([ansible.readthedocs.io](https://ansible.readthedocs.io/projects/molecule/usage/))
    
- Оставить окружение после фейла:
    
    ```bash
    molecule test --destroy=never
    molecule login
    ```
    
- Параллельные сценарии:
    
    ```bash
    molecule test --all --parallel
    ```
    
    (поддержка зависит от контекста; см. CLI/usage). ([ansible.readthedocs.io](https://ansible.readthedocs.io/projects/molecule/usage/))
    
- Посмотреть, что именно выполнит `test`:
    
    ```bash
    molecule matrix
    ```
    
    Покажет последовательности. ([ansible.readthedocs.io](https://ansible.readthedocs.io/projects/molecule/usage/))
    

---

# 6. Глобальные и базовые конфиги

- Можно иметь **базовый конфиг**, который deep-merge’ится в сценарии:
    
    ```bash
    molecule test -c .config/molecule/config.yml
    ```
    
    (или пользовательский `~/.config/molecule/config.yml`). ([GitHub](https://github.com/marketplace/actions/ansible-molecule))
    

---

# 7. Теги Molecule в задачах роли

- Пропустить задачи **всегда** в тестах: `tags: [molecule-notest]` или `notest`.
- Пропустить **только** в идемпотентности: `tags: [molecule-idempotence-notest]`. ([ansible.readthedocs.io](https://ansible.readthedocs.io/projects/molecule/configuration/))

---

# 8. Часто используемые куски `molecule.yml`

### Кастомные последовательности

```yaml
scenario:
  converge_sequence: [dependency, create, prepare, converge]
  destroy_sequence: [dependency, cleanup, destroy]
  test_sequence:
    - dependency
    - syntax
    - create
    - prepare
    - converge
    - idempotence
    - verify
    - destroy
```

([ansible.readthedocs.io](https://ansible.readthedocs.io/projects/molecule/configuration/))

### Настройка ansible.cfg прямо из Molecule

```yaml
provisioner:
  name: ansible
  config_options:
    defaults:
      fact_caching: jsonfile
    ssh_connection:
      scp_if_ssh: true
```

([ansible.readthedocs.io](https://ansible.readthedocs.io/projects/molecule/configuration/))

### Передать env в шаги

```yaml
provisioner:
  name: ansible
  env:
    HTTP_PROXY: http://proxy.local:3128
```

([ansible.readthedocs.io](https://ansible.readthedocs.io/projects/molecule/configuration/))

---

# 9. Типовые verify

```yaml
- hosts: all
  gather_facts: false
  tasks:
    - name: Сервис поднят
      ansible.builtin.service_facts:

    - name: nginx слушает 80
      ansible.builtin.wait_for:
        port: 80
        timeout: 2

    - name: Конфиг на месте
      ansible.builtin.stat:
        path: /etc/nginx/nginx.conf
      register: st
    - ansible.builtin.assert:
        that:
          - st.stat.exists
```

Полная философия последовательностей и примеры — в Workflow. ([ansible.readthedocs.io](https://ansible.readthedocs.io/projects/molecule/workflow/))

---

# 10. CI: базовый GitHub Actions

```yaml
# .github/workflows/molecule.yml
name: Molecule
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-24.04
    strategy:
      matrix:
        python-version: ["3.10", "3.11"]
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: ${{ matrix.python-version }} }
      - name: Install deps
        run: |
          python -m pip install --upgrade pip
          pip install "molecule" "ansible" "ansible-lint" "community.docker" "containers.podman"
      - name: Run Molecule
        run: molecule test --all
```

См. оф. раздел про CI (есть готовые шаблоны). ([ansible.readthedocs.io](https://ansible.readthedocs.io/projects/molecule/ci/))

---

# 11. Отладка

- Оставить окружение: `molecule test --destroy=never` → `molecule login`. ([robertdebock.nl](https://robertdebock.nl/2024/03/26/molecule-debugging.html))
- Шум побольше: `ANSIBLE_DEBUG=True`, `ANSIBLE_VERBOSITY=5`, `DIFF_ALWAYS=True`.
- Повторно гоняй только нужные шаги: `molecule converge` → `molecule verify`. (Шаги и их смысл — в usage). ([ansible.readthedocs.io](https://ansible.readthedocs.io/projects/molecule/usage/))

---

# 12. Когда использовать несколько `verify`/`side_effect`

Для stateful-софта (БД, кластера):

`converge → idempotence → side_effect (reboot/failover) → verify-after → converge → verify-final`. Это **стандартная, поддерживаемая** схема. ([ansible.readthedocs.io](https://ansible.readthedocs.io/projects/molecule/configuration/))

---

# 13. На что обратить внимание по версиям

- В Molecule v3+ **Ansible — дефолтный verifier**, `testinfra` не обязателен. ([ansible.readthedocs.io](https://ansible.readthedocs.io/projects/molecule/configuration/))
- Molecule v6+ продвигает **ansible-native** подход (плейбуки управляют ресурсами). Легаси `driver/platforms` помечены как *pre ansible-native*. ([ansible.readthedocs.io](https://ansible.readthedocs.io/projects/molecule/configuration/))

---

# 14. Быстрый чеклист перед пушем в CI

1. `molecule test` зелёный локально.
2. Если контейнеры — образы доступны агенту CI.
3. Локальные зависимости роли в `requirements.yml` + `dependency: galaxy` при необходимости.
4. Линтеры (`ansible-lint`, `yamllint`) и `syntax`шаг в последовательности.
5. Для отладки PR — временно `-destroy=never`. (Не забывать убрать). ([ansible.readthedocs.io](https://ansible.readthedocs.io/projects/molecule/usage/))