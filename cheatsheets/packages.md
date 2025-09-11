# packages

---

## Базовые команды APT

| Command | Что делает | Зачем/Пример |
| --- | --- | --- |
| `sudo apt update` | Обновляет списки пакетов | Перед установками/апдейтом всегда: `sudo apt update` |
| `sudo apt install <pkg>` | Устанавливает пакет + зависимости | Стандартная установка: `sudo apt install nginx` |
| `sudo apt reinstall <pkg>` | Переустанавливает пакет | Поломанные файлы/конфиги: `sudo apt reinstall coreutils` |
| `sudo apt upgrade` | Обновляет установленные пакеты без удаления | Безопасный апдейт; не удаляет пакеты |
| `sudo apt full-upgrade` | Обновляет с возможным **удалением** пакетов (разрешение зависимостей) | ⚠️ Может удалить: использовать осознанно на серверах |
| `sudo apt remove <pkg>` | Удаляет пакет, оставляя конфиги | Потом можно `purge` для чистки конфигов |
| `sudo apt purge <pkg>` | Полное удаление пакета+конфигов | ⚠️ Удаляет конфиги; полезно для «чистой» переустановки |
| `sudo apt autoremove` | Удаляет неиспользуемые зависимости | После удаления метапакетов может снести нужное |
| `sudo apt clean` | Чистит **весь** кэш `.deb` | Освободить место (радикально) |
| `sudo apt autoclean` | Удаляет только устаревшие `.deb` | Мягкая чистка кэша |

---

## Поиск и Инфо о пакетах

| Command | Что делает | Зачем/Пример |
| --- | --- | --- |
| `apt search <term>` | Поиск по именам/описаниям | Быстро найти пакет: `apt search redis` |
| `apt show <pkg>` | Подробная инфа о пакете | Версии, зависимости, описание: `apt show nginx` |
| `apt policy <pkg>` | Откуда и какую версию возьмёт APT | Для пиннинга и сравнения реп: `apt policy openssl` |
| `apt-cache depends <pkg>` | Прямые зависимости | Понять, что подтянется |
| `apt-cache rdepends <pkg>` | Обратные зависимости | Кто зависит от `<pkg>` |
| `apt-cache madison <pkg>` | Матрица версий/репо |  |
| `apt list --installed` | Список установленных (шумно) | Для глаз; для скриптов — лучше `dpkg -l` |
| `apt list --upgradable` | Какие можно обновить | Контроль версий |
| `dpkg -l | grep '^ii'` | Лаконичный список установленных пакетов | Удобно в скриптах или для снимков |
| `apt-file search <path>` | Найти пакет по файлу (в репах) | Неустановленные пакеты: `apt-file search /usr/bin/abc` |
| `dpkg -S <file>` | Найти владелца файла среди **установленных** пакетов | «Чей файл?» по локальной системе |

## Скриптам — `apt-get`, людям — `apt`

- `apt` = удобные сообщения/прогресс, для ручной работы.
- `apt-get`/`apt-cache` = стабильный интерфейс для скриптов/CI.

---

## Управление dpkg (низкий уровень)

| Command | Что делает | Зачем/Пример |
| --- | --- | --- |
| `dpkg -L <pkg>` | Какие файлы установил пакет | Проверка содержимого: `dpkg -L nginx` |
| `dpkg -s <pkg>` | Статус/метаданные установленного пакета | Быстрый статус: версия, арх, «ок» |
| `dpkg -r <pkg>` | Remove — удаление, **оставляет конфиги** | Останутся «residual configs» (статус `rc`) |
| `dpkg -P <pkg>` | Purge — удаление с конфигами | Полный снос: чистая переустановка |
| `dpkg -V <pkg>` | Проверка целостности файлов пакета | Выявить изменённые файлы (MD5) |
| `sudo debsums -s` | Проверка контрольных сумм по всей системе | Найти повреждения/изменения (пакет `debsums`) |

---

## Логи и Аудит APT

| Command | Что делает | Зачем/Пример |
| --- | --- | --- |
| `sudo less /var/log/apt/history.log` | История установок/обновлений | Кто/что/когда ставилось |
| `sudo less /var/log/apt/term.log` | Подробный вывод сессий apt | Диагностика проблем/скриптов `postinst` |
| `zgrep -h " install " /var/log/apt/history.log*` | Вытащить установки из всех логов | Быстрый аудит |
| `zgrep -h " upgrade " /var/log/apt/history.log*` | Вытащить апгрейды | Ретроспектива изменений |

---

## Восстановление после ошибок

| Command | Что делает | Зачем/Пример |
| --- | --- | --- |
| `sudo dpkg --configure -a` | Донастроить «зависшие» пакеты | После прерванной установки/апгрейда |
| `sudo apt --fix-broken install` | Починить зависимости | Когда «сломались зависимости» |
| `sudo apt -o Dpkg::Options::="--force-confnew" -y install <pkg>` | Принять новые конфиги | В спорных конфликтах конфигов |
| Резервные копии `/etc/apt/sources.list{,.d}`, `/etc/apt/preferences.d` | Вернуть репозитории/пины | Снимайте бэкапы перед экспериментами |

---

## Загрузка, исходники и зависимости для сборки

| Command | Что делает | Зачем/Пример |
| --- | --- | --- |
| `apt download <pkg>` | Скачать `.deb` без установки | Принести пакет на офлайн-машину |
| `apt source <pkg>` | Скачать исходники | Разбор/патч/сборка |
| `sudo apt-get build-dep <pkg>` | Поставить зависимые для сборки | Готовим окружение для `dpkg-buildpackage` |

---

## Hold / Pinning / Версии

| Command | Что делает | Зачем/Пример |
| --- | --- | --- |
| `apt-mark hold <pkg>` | Заморозить версию | Зафиксировать критичный пакет |
| `apt-mark unhold <pkg>` | Снять фикс | Вернуть обновления |
| `apt-mark showhold` | Показать все hold | Аудит фиксов |
| `sudo apt install <pkg>=<ver>` | Установить конкретную версию | Точный даун/апгрейд |
| `/etc/apt/preferences.d/*.pref` | Пиннинг источников/версий | Управление приоритетами |

**Таблица приоритетов Pin-Priority (кратко):**

| Pin-Priority | Поведение |
| --- | --- |
| `>1000` | Форсировать установку даже при даунгрейде |
| `990..1000` | Предпочитать из данного релиза (если активен) |
| `500` | Значение по умолчанию для репозиториев |
| `<100` | Не устанавливать автоматически (нужно указать версию явно) |

---

## Репозитории и Ключи (DEB822 + KEYRINGS)

| Command / Файл | Что делает | Зачем/Пример |
| --- | --- | --- |
| `/etc/apt/sources.list.d/nginx.sources` | Deb822-формат репозитория | Современнее и чище, чем `sources.list` |
| `/etc/apt/keyrings/<vendor>.gpg` | Отдельный keyring для репозитория | **Не** использовать `apt-key` (устарело/опасно) |
| `sudo apt update` | Обновить индексы после добавления | Проверить подписи/доступность |

**Шаблон Deb822 (`*.sources`):**

```
Types: deb
URIs: https://repo.example.com/ubuntu
Suites: noble
Components: main
Signed-By: /etc/apt/keyrings/example.gpg
```

⚠️ На проде избегать случайных PPA. Для популярных сервисов (например, Nginx) использовать только официальный репозиторий + keyring.

---

## Поведение APT (Рекомендации/Предложения)

| Command / Файл | Что делает | Зачем/Пример |
| --- | --- | --- |
| `/etc/apt/apt.conf.d/99norecommends` | Отключить «рекомендованные» зависимости | Тонкая серверная установка |
|  | `APT::Install-Recommends "0";` |  |
|  | `APT::Install-Suggests "0";` |  |

---

## CI/Автоматизация/Мульти-АРХ

| Command | Что делает | Зачем/Пример |
| --- | --- | --- |
| `DEBIAN_FRONTEND=noninteractive apt-get -yq install <pkg>` | Без диалогов | Для CI и автоскриптов |
| `sudo dpkg --add-architecture i386 && sudo apt update` | Включить multi-arch | Когда нужны библиотеки i386 |

---

## UNATTENDED-UPGRADES (Авто-обновления)

| Command | Что делает | Зачем/Пример |
| --- | --- | --- |
| `sudo apt install -y unattended-upgrades` | Установка | Базовая защита |
| `sudo dpkg-reconfigure --priority=low unattended-upgrades` | Включить автообновления | Через диалог (Enable: Yes) |
| `systemctl list-timers --all | grep apt` | Проверить таймеры | Контроль расписания |
| `sudo unattended-upgrade --dry-run --debug | sed -n '1,80p’` | Пробный прогон | Проверка, что именно обновится |
| `journalctl -u apt-daily-upgrade.service -n 50 --no-pager` | Логи автообновлений | Аудит |

---

## Снимки/Экспорт состояния

| Command | Что делает | Зачем/Пример |
| --- | --- | --- |
| `dpkg-query -W -f='${binary:Package}\t${Version}\n' > pkglist.txt` | Снимок «что установлено» | Миграции/аудит |
| `apt-mark showmanual > manual.txt` | Ручные пакеты | Чтобы потом восстановить «ручной набор» |
| Архив: `/etc/apt/{sources.list,sources.list.d,preferences.d,apt.conf.d}` | Конфиги APT | Обязательно в бэкап |

---

## Подводные камни

- **`apt full-upgrade`** может удалить пакеты для разрешения зависимостей. На проде — только после просмотра плана.
- **`apt purge`** удаляет конфиги. Удобно для «чистой» переустановки, но можно потерять ручные правки.
- **`apt autoremove`** может снести якобы «неиспользуемые» зависимости. Помечать важные пакеты `apt-mark manual <pkg>`.
- **PPA на серверах**: повышают риск конфликтов. Предпочтительнее официальные репозитории с keyring’ами.
- **`apt-key` устарел**: использовать `Signed-By: /etc/apt/keyrings/*.gpg`.

---

## ПРАКТИКУМ

1. **Аудит**: посмотреть последние установки/обновления через `history.log`, зафиксировать вывод в `practice/apt_audit.txt`.

```bash
leprecha@Ubuntu-DevOps:~$ mkdir -p practice
leprecha@Ubuntu-DevOps:~$ zgrep -h "Start-Date\|Commandline:\|Install:\|Upgrade:\|Remove:\|End-Date" /var/log/apt/history.log* | tail -n 10 > practice/apt_audit.txt
```

2. **Hold**: поставить `apt-mark hold` на один критичный пакет (например, `nginx`), проверить `apt-mark showhold`, потом снять.

```bash
leprecha@Ubuntu-DevOps:~$ sudo apt-mark hold nginx
nginx set on hold.
leprecha@Ubuntu-DevOps:~$ apt-mark showhold
nginx
leprecha@Ubuntu-DevOps:~$ sudo apt-mark unhold nginx
Canceled hold on nginx.
```

3. **Integrity**: установить `debsums`, проверить систему `debsums -s`, отработать `dpkg -V` для 1-2 пакетов.

```bash
sudo apt update
sudo apt install debsums -y
leprecha@Ubuntu-DevOps:~$ sudo debsums -s
debsums: changed file /usr/lib/systemd/system/cloud-init.service (from cloud-init package)
leprecha@Ubuntu-DevOps:~$ sudo dpkg -V bash
leprecha@Ubuntu-DevOps:~$ sudo dpkg -V cloud-init
??5??????   /usr/lib/systemd/system/cloud-init.service
leprecha@Ubuntu-DevOps:~$ sudo apt install --reinstall cloud-init     # Вернуть оригинал
```

4. **Recovery**: симулировать прерванную установку (Ctrl+C), восстановить `dpkg --configure -a`, зафиксировать шаги.

```bash
sudo apt install sl          # Во время загрузки нажать Ctrl+C
sudo apt update              # Будет ругаться
sudo dpkg --configure -a     # Восстановить
sudo apt install -f          # Устранит зависимости, если что-то не докачалось
```

---

## Security Checklist

- Репозитории оформлены в **Deb822** (`.sources`) + отдельные **keyrings** (`/etc/apt/keyrings/*.gpg`), `apt-key` не используется.
- На серверах нет случайных PPA; сторонние репы — только при необходимости и с pinning’ом.
- Включён `unattended-upgrades` и проверены таймеры/логи.
- Отключены `Recommends/Suggests` там, где важна минимальность системы.
- Регулярный аудит: `history.log`, `term.log`, снимки пакетов/конфигов в бэкапе.
- Критичные пакеты — под `apt-mark hold` с осознанной политикой обновления.
- Автоматизация использует `noninteractive` и фиксированные версии там, где это критично.

---

## Быстрые блоки

```bash
# Найти поломанные зависимости и починить
sudo dpkg --configure -a && sudo apt --fix-broken install

# Показать hold’ы и снять/поставить
apt-mark showhold
sudo apt-mark hold <pkg>       # зафиксировать
sudo apt-mark unhold <pkg>     # снять фикс

# Аудит: что ставили/обновляли
zgrep -hE " install | upgrade " /var/log/apt/history.log* | tail -50

# Скачать .deb и исходники
apt download <pkg>
apt source <pkg>

# Зависимости для сборки
sudo apt-get build-dep <pkg>

# Остаточные конфиги (rc) — удалить подчистую
dpkg -l | awk '/^rc/ {print $2}' | xargs -r sudo apt purge -y

# Проверить целостность системы
sudo apt install -y debsums && sudo debsums -s
dpkg -V <pkg>     # точечно для пакета
```