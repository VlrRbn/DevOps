# testinfra

---

# Что это и зачем

**Testinfra** — плагин к `pytest` для проверки фактического состояния хостов: пакеты, сервисы, файлы, сокеты, sysctl и т.д. Пишешь тесты на Python, гонять локально, или по SSH, Docker/Podman или через Ansible-инвентори. ([testinfra.readthedocs.io](https://testinfra.readthedocs.io/))

---

# Установка и запуск

```bash
# базовый минимум
pip install pytest-testinfra

# бэкенды как extras (подтянет зависимости), например:
pip install "pytest-testinfra[ansible,docker]"
```

Запуск:

```bash
# Стендэлон
pytest -q tests/

# Параллельно (быстро!)
pytest -q -n auto tests/     # через pytest-xdist
```

Testinfra официально рекомендует xdist для распараллеливания. ([testinfra.readthedocs.io](https://testinfra.readthedocs.io/en/latest/invocation.html))

С Molecule:

```
molecule/SCENARIO/tests/test_*.py     # Сюда ложить тесты
molecule verify                       # Запустит pytest/testinfra
```

(Подход «testinfra как verifier» — классика для Molecule.) ([Medium](https://medium.com/contino-engineering/testing-ansible-automation-with-molecule-pt-1-66ab3ea7a58a))

---

# Как Testinfra подключается к хостам (бекенды)

- **local** — локальный хост
- **ssh** / **paramiko** — удалёнка
- **docker** / **podman** — контейнеры
- **ansible** — использовать инвентори Ansible (очень удобно в CI)

Выбираешь бекенд флагами `--hosts`, `--connection` или через переменные в тесте. Примеры ниже. Полный список и нюансы — в доке. ([testinfra.readthedocs.io](https://testinfra.readthedocs.io/en/latest/backends.html))

---

# Быстрый старт

```python
# tests/test_web.py
def test_nginx_installed(host):
    pkg = host.package("nginx")
    assert pkg.is_installed

def test_nginx_running_and_enabled(host):
    svc = host.service("nginx")
    assert svc.is_running
    assert svc.is_enabled

def test_listen_port_80(host):
    sock = host.socket("tcp://0.0.0.0:80")
    assert sock.is_listening

def test_config_exists_and_has_line(host):
    f = host.file("/etc/nginx/nginx.conf")
    assert f.exists and f.user == "root" and f.group == "root"
    assert f.contains("worker_processes")
```

Модули `package/service/socket/file`. Полный каталог модулей: `User`, `Group`, `Interface`, `Sysctl`, `MountPoint`, `Process`, `Command`, `SystemInfo`, и т.д. — см. список и API. ([testinfra.readthedocs.io](https://testinfra.readthedocs.io/en/latest/modules.html))

---

# Выбор хостов (3 рабочих стратегии)

### 1) Через CLI

```bash
pytest -q --hosts='ssh://root@host1,ssh://root@host2' tests/
pytest -q --connection=ansible --hosts='web'           # группа из инвентори
```

Док: invocation + бэкенды. ([testinfra.readthedocs.io](https://testinfra.readthedocs.io/en/latest/invocation.html))

### 2) Через переменную `testinfra_hosts` в файле

```python
# tests/test_hosts.py
testinfra_hosts = ["ssh://root@host1", "ssh://root@host2"]
```

(Параметризует фикстуру `host` под каждый таргет.) ([testinfra.readthedocs.io](https://testinfra.readthedocs.io/en/latest/invocation.html))

### 3) Через `pytest_generate_tests` (динамика/хитрые кейсы)

```python
# conftest.py
import pytest

def pytest_generate_tests(metafunc):
    if "host" in metafunc.fixturenames:
        hosts = ["ssh://root@host1", "ssh://root@host2"]
        metafunc.parametrize("host", hosts, indirect=True)
```

Удобно, если список хостов собирается на лету (по API/файлу/инвентори). Подход из методичек pytest. ([docs.pytest.org](https://docs.pytest.org/en/stable/how-to/parametrize.html))

---

# Умные ассершены и команды

```python
def test_command_ok(host):
    # быстрый stdout
    out = host.check_output("nginx -v 2>&1")
    assert "nginx/" in out

def test_command_result(host):
    r = host.run("id -u nginx")
    assert r.rc == 0
    assert r.stdout.strip().isdigit()

def test_sysctl(host):
    assert host.sysctl("net.ipv4.ip_forward") in (0, 1)

def test_process(host):
    assert any(p.user == "nginx" for p in host.process.filter(comm="nginx"))
```

`check_output()`, `run()`, `CommandResult` — документированы в API. ([testinfra.readthedocs.io](https://testinfra.readthedocs.io/en/latest/genindex.html))

---

# Детект ОС/дистрибутива и скип

```python
import pytest

def test_service_name_by_os(host):
    osfam = host.system_info.distribution  # ubuntu, centos, etc.
    svc = "nginx" if osfam in ("ubuntu","debian") else "nginx"
    assert host.service(svc).is_running

@pytest.mark.skipif(lambda host: host.system_info.type != "linux",
                    reason="only on Linux")
def test_only_linux(host):
    ...
```

`SystemInfo` даёт `type`, `distribution`, `release`, `codename`. ([testinfra.readthedocs.io](https://testinfra.readthedocs.io/en/latest/modules.html))

---

# Работа через Ansible

```bash
pytest -q --connection=ansible --hosts='web:!drain'
```

Или прямо из теста вызвать модуль Ansible:

```python
def test_ansible_module(host):
    res = host.ansible("setup", "filter=ansible_os_family")
    assert res["ansible_facts"]["ansible_os_family"] in ("Debian","RedHat")
```

---

# Параллельные запуски

```bash
pip install pytest-xdist
pytest -n auto -q --connection=ansible --hosts='web,db,cache' tests/
```

xdist гонит тесты в нескольких воркерах, скейлится по хостам/группам. Док с примерами команд. ([testinfra.readthedocs.io](https://testinfra.readthedocs.io/en/latest/invocation.html))

---

# Практики

- **Идемпотентные проверки**: тест не должен менять систему. Никаких `echo > /etc/...`.
- **Анти-флейк**: сеть/сервисы → `wait_for`, ретраи c backoff (обернуть в цикл), минимальные таймауты.
- **Логи и подробности**: печатать диагностический контент (stdout/stderr), легче в CI.
- **Маркеры и выборка**: `-k 'nginx and not slow'`, `-m slow` + `@pytest.mark.slow`.
- **Быстрый фидбек**: распараллеливать по хостам и по тестам — xdist. ([testinfra.readthedocs.io](https://testinfra.readthedocs.io/en/latest/invocation.html))

---

# Частые рецепты

## 1) Конфиг-файл должен содержать строку

```python
def test_conf_line(host):
    f = host.file("/etc/myapp/myapp.conf")
    assert f.exists
    assert f.contains(r"^enabled\s*=\s*true$")
```

Модуль `File.contains()` регэкспы понимает. ([testinfra.readthedocs.io](https://testinfra.readthedocs.io/en/latest/genindex.html))

## 2) Порт слушает только localhost

```python
def test_local_listen(host):
    sock = host.socket("tcp://127.0.0.1:5432")
    assert sock.is_listening
    # никакого 0.0.0.0
    assert not host.socket("tcp://0.0.0.0:5432").is_listening
```

API `Socket` — в модулях. ([testinfra.readthedocs.io](https://testinfra.readthedocs.io/en/latest/modules.html))

## 3) Правильные права/владельцы

```python
def test_perms(host):
    f = host.file("/var/lib/myapp/secret")
    assert f.user == "myapp" and f.group == "myapp"
    assert f.mode == 0o600
```

`File.mode/user/group` — стандарт. ([testinfra.readthedocs.io](https://testinfra.readthedocs.io/en/latest/modules.html))

## 4) Валидация пакетов и версий

```python
def test_pkg_version(host):
    pkg = host.package("openssl")
    assert pkg.is_installed
    assert pkg.version.startswith(("3.", "1.1.1"))
```

Модуль `Package` поддерживает версии. ([testinfra.readthedocs.io](https://testinfra.readthedocs.io/en/latest/modules.html))

## 5) Дымовые HTTP-проверки (через curl/Command)

```python
def test_http_200(host):
    r = host.run("curl -sS -o /dev/null -w '%%{http_code}' http://127.0.0.1/")
    assert r.stdout.strip() == "200"
```

`Host.run()` даёт rc/stdout/stderr. ([testinfra.readthedocs.io](https://testinfra.readthedocs.io/en/latest/genindex.html))

---

# Паттерны параметризации

## Параметризуем тесты данными ([docs.pytest.org](https://docs.pytest.org/en/stable/how-to/parametrize.html))

```python
import pytest

@pytest.mark.parametrize("pkg", ["nginx","curl","tar"])
def test_pkgs(host, pkg):
    assert host.package(pkg).is_installed
```

## Параметризуем хосты из инвентори/списка

```python
testinfra_hosts = ["ansible://web", "ansible://db"]
```

(Каждый тест выполнится на каждом хосте.) ([testinfra.readthedocs.io](https://testinfra.readthedocs.io/en/latest/invocation.html))

---

# Частые флаги CLI

```bash
# выбрать подключение и хостов
pytest --connection=ansible --hosts='web,db'

# накатить sudo/пользователя
pytest --sudo                    # все команды под sudo
pytest --sudo-user appuser

# подробный вывод
pytest -vv

# выбрать часть тестов
pytest -k "nginx and not slow" -m "not flaky"
```

Команды/опции описаны в разделе invocation/backends. ([testinfra.readthedocs.io](https://testinfra.readthedocs.io/en/latest/invocation.html))

---

# Полезные модули

- `host.file(path)` — права/владельцы/содержимое/regex.
- `host.service(name)` — `is_running`, `is_enabled`.
- `host.package(name)` — `is_installed`, `version`.
- `host.socket(proto://addr:port)` — `is_listening`.
- `host.process.filter(...)` — поиск процессов.
- `host.sysctl(key)` — значение sysctl.
- `host.user(name)` / `group(name)` — проверка пользователей/групп.
- `host.check_output(cmd)` / `host.run(cmd)` — команды/результаты.
    
    Полная справка по модулям — в оф. документации. ([testinfra.readthedocs.io](https://testinfra.readthedocs.io/en/latest/modules.html))
    

---

# Интеграция с Molecule

```
role/
└── molecule/
    └── default/
        ├── converge.yml
        ├── ...
        └── tests/
            ├── conftest.py
            ├── test_pkg.py
            └── test_service.py
```

`molecule verify` дернёт `pytest` в этом каталоге. ([Medium](https://medium.com/contino-engineering/testing-ansible-automation-with-molecule-pt-1-66ab3ea7a58a))

---

# Диагностика и ускорение в CI

- **Параллельный прогон**: `pytest -n auto` (xdist).
- **Шардим по группам**: `-hosts='web'` и `-hosts='db'` в разных джобах.
- **Полезные плагины**: `pytest-xdist` (параллель), отчёты. ([pytest-xdist.readthedocs.io](https://pytest-xdist.readthedocs.io/))

---

# Версионные нюансы

- Новый ansible-бекенд у Testinfra 3.x+ работает поверх ‘’родных’’ бекендов (`local/ssh/docker`) — читать changelog, если что-то внезапно отвалилось при апдейте. ([testinfra.readthedocs.io](https://testinfra.readthedocs.io/en/latest/changelog.html))

---

# Мини-шаблон под ‘’любой сервис’’

```python
import pytest

PKGS = ["nginx"]
FILES = [("/etc/nginx/nginx.conf", "root", "root", 0o644)]
PORTS = ["tcp://0.0.0.0:80"]

@pytest.mark.parametrize("p", PKGS)
def test_pkgs(host, p):
    assert host.package(p).is_installed

@pytest.mark.parametrize("path,owner,group,mode", FILES)
def test_files(host, path, owner, group, mode):
    f = host.file(path)
    assert f.exists and f.user == owner and f.group == group and f.mode == mode

@pytest.mark.parametrize("port", PORTS)
def test_ports(host, port):
    assert host.socket(port).is_listening

def test_service(host):
    svc = host.service("nginx")
    assert svc.is_running and svc.is_enabled
```