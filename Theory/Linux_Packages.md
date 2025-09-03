# Linux_Packages

---

## Базовые команды APT

| Команда | Что делает | Зачем |
| --- | --- | --- |
| `sudo apt update` | Обновить список пакетов | Нужно перед установкой |
| `sudo apt upgrade` | Обновить установленные пакеты | Поддержка актуальности |
| `sudo apt-get -s upgrade` | Симуляция | «Сухой прогон» перед апдейтом |
| `sudo apt full-upgrade` | Обновление с удалением старых пакетов | Когда меняется зависимость |
| `sudo apt install nginx` | Установить пакет |  |
| `sudo apt install --reinstall nginx` | Переустановка | Лечит поломанные файлы |
| `sudo apt install ./pkg.deb` | Установка локального .deb | Автоматически подтянет зависимости |
| `sudo apt remove nginx` | Удалить без конфигов | «чистое» удаление |
| `sudo apt purge nginx` | Удалить с конфигами | Полностью убрать |
| `sudo apt autoremove` | Удалить неиспользуемые зависимости | Чистка системы |
| `apt list --installed` | Список установленных | Инвентаризация |
| `apt list --upgradable` | Какие можно обновить | Контроль версий |
| `sudo apt-mark hold nginx` / `unhold` | Заморозить/разморозить версию | Чтобы апгрейды не сносили нужное |
| `sudo apt clean` / `autoclean` | Чистка кеша | Освободить место |

---

## dpkg — низкоуровневый слой

| Команда | Что делает | Зачем |
| --- | --- | --- |
| `dpkg -i file.deb` | Установить локальный `.deb` | Без apt |
| `dpkg -r pkg` | Удалить пакет без конфигов |  |
| `dpkg -P pkg` | Удалить с конфигами | Полное удаление |
| `dpkg -L pkg` | Файлы в пакете | Где лежит бинарь |
| `dpkg -S /path/file` | Какой пакет владеет файлом | Поиск владельца |
| `dpkg -s pkg` | Инфо о пакете | Версия, статус |
| `dpkg -l 'nginx*’` | Cписок установленных, по маске |  |
| `dpkg -I file.deb` | Показать контрольные поля  | metadata |
| `dpkg -c file.deb` | Список файлов внутри `.deb` |  |

---

## Поиск пакетов

| Команда | Что делает |
| --- | --- |
| `apt search nginx` | Найти пакет по имени/описанию |
| `apt show nginx` | Подробная инфа (описание, зависимости) |
| `apt-cache depends nginx` | Зависимости |
| `apt-cache rdepends nginx` | Обратные зависимости (кто зависит) |
| `apt policy nginx` | Версия + репозитории |
| `apt list -a nginx` | Все доступные версии |
| `apt-file search bin/foo` | Найти пакет, содержащий файл |
| `apt-cache madison nginx` | Матрица версий/репо |
| `sudo apt-mark hold nginx` / `unhold` | Заморозить/разморозить версию |

## Скриптам — `apt-get`, людям — `apt`

- `apt` = удобные сообщения/прогресс, для ручной работы.
- `apt-get`/`apt-cache` = стабильный интерфейс для скриптов/CI.

`apt-file` требует установки:

```bash
sudo apt install apt-file && sudo apt-file update
```

---

## Работа с репозиториями

- Файлы списков: `/etc/apt/sources.list` и `/etc/apt/sources.list.d/*.list` ; `/etc/apt/sources.list.d/*.sources`
- Ключи: `/etc/apt/keyrings/*.gpg`

Добавление репозитория:

```bash
sudo add-apt-repository -y ppa:nginx/stable
sudo apt update

# Удалить PPA и откатиться на репозиторий Ubuntu:
sudo apt install -y ppa-purge
sudo ppa-purge ppa:nginx/stable
```

---

## Hold / Pinning

Запретить обновление:

```bash
sudo apt-mark hold nginx
sudo apt-mark unhold nginx
```

Приоритеты (`/etc/apt/preferences.d/*.pref`):

```bash
sudo tee /etc/apt/preferences.d/nginx-1.24.pref >/dev/null <<'PIN'
Package: nginx
Pin: version 1.24.*
Pin-Priority: 1001
PIN

sudo apt update
apt-cache policy nginx
```

---

## Unattended upgrades

Установить:

```bash
sudo apt install unattended-upgrades
sudo dpkg-reconfigure --priority=low unattended-upgrades
```

Настройки: `/etc/apt/apt.conf.d/50unattended-upgrades`

Проверить таймер:

```bash
systemctl status apt-daily.timer apt-daily-upgrade.timer
systemctl list-timers | grep -E 'apt-daily|apt-daily-upgrade'
```

Файл `/etc/apt/apt.conf.d/20auto-upgrades` — периодика (включено ли автоприменение):

```bash
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
```

Сухой прогон:

```bash
sudo unattended-upgrade --dry-run --debug
```

---

## Практикум

1. Найти пакет, содержащий `ls`:

```bash
dpkg -S $(which ls)
```

1. Найти пакет по файлу:

```bash
apt-file search bin/htop
```

1. Заблокировать пакет от обновлений:

```bash
sudo apt-mark hold nginx
```

1. Проверить обновления:

```bash
apt list --upgradable
```

1. Снять снапшот установленных пакетов:

```bash
dpkg --get-selections > pkg.list
```

1. Восстановить список пакетов:

```bash
sudo dpkg --set-selections < pkg.list
sudo apt-get dselect-upgrade
```

---

## 🛡️ Security Checklist

- Всегда делать `apt update` перед `apt install`.
- Чистить `apt autoremove` после обновлений.
- Для серверов включить `unattended-upgrades`.
- Проверять `apt policy` перед апгрейдом «важных» пакетов.
- Держать отдельные `.list` файлы в `/etc/apt/sources.list.d/`.

---

## Быстрые блоки

```bash
# Установить и сразу обновить список
sudo apt update && sudo apt install pkg

# Все зависимости пакета
apt-cache depends pkg

# Все, что зависит от пакета
apt-cache rdepends pkg

# Где лежит бинарь
dpkg -L pkg | grep bin/

# Какой пакет владеет файлом
dpkg -S /usr/bin/python3
```