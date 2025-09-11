# logs_and_monitoring

---

## `journalctl` — Системные логи (базовые запросы)

| Command | Что делает | Зачем/Пример |
| --- | --- | --- |
| `journalctl -xe` | Показать свежие ошибки/варнинги с контекстом | Быстрый «что сломалось прямо сейчас» |
| `journalctl -xeu <unit>` | То же, но по конкретному сервису | `journalctl -xeu ssh` |
| `journalctl -u <unit> --since today` | Логи сервиса за сегодня | Ежедневная проверка: `-u nginx` |
| `journalctl -p err --since today` | Фильтр по уровню (err и выше) | Скан ошибок за день |
| `journalctl --grep 'PATTERN'` | Поиск по регулярке (`-g` — короткая форма) | `journalctl -u nginx -g '5..'` |
| `journalctl -o short-iso` | Компактное ISO‑время | Удобно для отчётов и diff’ов |
| `journalctl -o cat` | Печать только сообщения (без метаданных) | Когда «шумят» поля системд |
| `journalctl -b -1` | Логи предыдущей загрузки | Инцидент был «вчера до ребута» |

**Примечания:** Если `rsyslog` отсутствует, централизоватся на `journalctl` — файла `syslog` может не быть.

---

## Размер и хранение журнала (`journald`)

| Command | Что делает | Зачем/Пример |
| --- | --- | --- |
| `journalctl --disk-usage` | Показывает, сколько место занимает журнал | Контроль «жирности» |
| `sudo journalctl --vacuum-time=7d` | Чистит записи старше 7 дней | «Дедуп» по времени |
| `sudo journalctl --vacuum-size=1G` | Оставляет не более 1 ГБ журнала | Контроль по размеру |
| `sudoedit /etc/systemd/journald.conf` | Включить постоянное хранение | `Storage=persistent` |
| `sudo mkdir -p /var/log/journal && sudo systemctl restart systemd-journald` | Создать каталог и перезапустить | Активирует persistent‑журнал |

---

## Доступ к журналам без `root`

| Command | Что делает | Зачем/Пример |
| --- | --- | --- |
| `sudo usermod -aG systemd-journal "$USER"` | Добавляет в группу чтения журнала | Чтение логов без `sudo` |
| `newgrp systemd-journal` | Применяет группу без релога | Сразу проверить доступ |
| `groups` | Проверить, что группа применена | Должна быть `systemd-journal` |

---

## Классические логи в `/var/log`

| Command | Что делает | Зачем/Пример |
| --- | --- | --- |
| `ls -lh /var/log` | Быстрый обзор размеров логов | Что растёт быстрее всего |
| `tail -n 100 -F /var/log/nginx/error.log` | «Следить» за ошибками nginx | Живой стрим ошибок |
| `zgrep -i 'pattern' /var/log/<file>.gz` | Поиск по сжатым логам | История в `*.gz` |
| `zless /var/log/<file>.gz` | Просмотр gzip логов | Навигация по старым логам |
| `grep -Rni 'pattern' /var/log` | Глубокий поиск по всем логам | Когда не знаешь где искать |

**Важно:** На системах без `rsyslog` файла `/var/log/syslog` может не быть — использовать `journalctl`.

---

## Поиск, пайпы и буферизация

| Command | Что делает | Зачем/Пример |
| --- | --- | --- |
| `grep --line-buffered 'foo'` | «Построчная» буферизация (GNU grep) | Реальное время в пайпах (пример: `tail -f logfile | grep foo`) |
| `grep -E "error|fail" file.log` | Несколько паттернов |  |
| `stdbuf -oL -eL cmd` | Снимает буферизацию stdout/stderr по строкам | Чтобы логи текли без задержек |
| `awk '{print; fflush()}'` | Принудительный flush в awk | Реальный стрим через awk/pipe |
| `journalctl -fu <unit>` | «Фоллоу» по сервису | Живой стрим конкретного юнита |

---

## Сервисы (`systemd`)

| Command | Что делает | Зачем/Пример |
| --- | --- | --- |
| `systemctl --failed` | Упал и не поднялся? | Точка входа в разбор |
| `systemctl status <unit>` | Состояние + последние логи | «Что с сервисом прямо сейчас» |
| `journalctl -u <unit> -b` | Логи юнита за текущую загрузку | Отсечь старые шумы |
| `systemctl restart <unit>` | Перезапуск | Проверить восстановление |
| `systemctl list-units --type=service --state=failed` | Все фейлящиеся юниты | Полная картина |
| `systemctl list-timers --all | head -15` | Посмотреть таймеры | Плановые задачи/обновления |

---

## CPU / RAM / IO (быстрые метрики)

| Command | Что делает | Зачем/Пример |
| --- | --- | --- |
| `pidstat 1` | По‑процессный CPU/IO каждый 1s | Найти «кого бить» |
| `iostat -x 1` | иски (sysstat) |  |
| `vmstat 1` | CPU, память, IO |  |
| `top` | CPU, память, процессы |  |
| `htop` | Красиво + дерево процессов |  |
| `atop` | CPU, RAM, диски, сеть (история) |  |
| `btop` | Красивый интерактивный мониторинг | Быстрый обзор нагрузки |
| `glances` | Всё в одном |  |
| `iotop -oPa` | Топ по диску (IO) | Кто «долбит» диск |
| `free -h` | Использование памяти/свопа | Базовая sanity‑проверка |
| `vmstat 1` | Сводка CPU/mem/io | Общая динамика |
| `sar -u 1 5` / `sar -r 1 5` | CPU нагрузка (sysstat)/Память |  |

*Примечание:* `pidstat/iostat/iotop` в пакете `sysstat`/`iotop`.

---

## Сеть — экспресс‑проверки

| Command | Что делает | Зачем/Пример |
| --- | --- | --- |
| `iftop` | Трафик по соединениям |  |
| `nload` | Входящий/исходящий трафик |  |
| `ss -s` | Краткая статистика сокетов | «Давка» по TCP/UDP? |
| `ss -tulpn | grep -E ':(80|443)\b'` | Кто слушает 80/443 | Избежать ложных 8080/18080 |
| `ip -br addr` | Краткий список адресов/интерфейсов | Понять, какой iface живой |
| `ip -s link` | Счётчики ошибок/дропов | Сеть «сыпется»? |
| `ping -c 2 1.1.1.1` | Быстрый внешний коннект | Исключить локальные проблемы |

---

## HTTP/HTTPS — быстрые проверки

| Command | Что делает | Зачем/Пример |
| --- | --- | --- |
| `curl -fsSIL http://localhost` | HEAD‑проверка без шума | Код возврата говорит сам за себя |
| `curl -fsS http://localhost/health || echo 'DOWN'` | Healthcheck | Удобно в CI/скриптах: упадёт только при ошибке |
| `goaccess /var/log/nginx/access.log --log-format=COMBINED -o report.html` | Быстрый отчёт по access‑логу | «Где болит» за 5 минут |

---

## Крэши и `coredumpctl`

| Command | Что делает | Зачем/Пример |
| --- | --- | --- |
| `coredumpctl list` | Список свежих крэшей | Есть ли вообще падения |
| `coredumpctl info` | Подробности последнего дампа | Время/юнит/путь к core |
| `coredumpctl info <PID|EXE>` | Точка входа для дебага | Привязка к процессу/бинарю |
| `coredumpctl gdb <PID>` | Открыть дамп в gdb | Быстрый анализ |

---

## Ротация логов (`logrotate`)

| Command | Что делает | Зачем/Пример |
| --- | --- | --- |
| `ls /etc/logrotate.d/` | Какие правила ротации активны | Понять, кто когда «крутится» |
| `sudo logrotate -d /etc/logrotate.conf` | «Сухой прогон» без изменений | Проверить конфиг перед пушем |
| `sudo logrotate -f /etc/logrotate.conf` | Форсировать ротацию | Когда лог разросся прямо сейчас |

---

## Подводные камни

- **Таймзона.** Фиксировать `timedatectl status` в инцидент‑нотах: «вчера 23:00 UTC» ≠ «сегодня 00:00 Europe/Dublin».
- **Буферизация в пайпах.** Использовать `grep --line-buffered` и/или `stdbuf -oL`, иначе «реального времени» не будет.
- **Интерфейсы.** `ip -br link` перед `iftop`/`ss` — выбрать правильный iface (например, `wlo1` для Wi‑Fi).
- **Отсутствие `syslog`.** На системах без rsyslog не искать `/var/log/syslog` — всё в `journalctl`.

---

## Практикум — ежедневный ритуал

1. `journalctl -p err --since today` — быстрый скан ошибок.
2. `systemctl --failed` — есть ли упрямые фейлы.
3. `ss -s && ip -s link` — сеть не дропает?
4. `df -h / && journalctl --disk-usage` — место и размер журнала ок?
5. Если nginx: `grep -E ' 5[0-9]{2} ' /var/log/nginx/access.log && tail -n 50 /var/log/nginx/error.log`.

---

## Security Checklist

- Доступ к логам — только нужным группам (`systemd-journal`, `adm`).
- Следить за аутентификацией: `journalctl -u ssh -p warning --since today | grep -i 'fail\|invalid'`.
- Алёрты на рост журналов/логов веб‑сервера (дисковая «атака»/утечки).
- Проверять `/var/log/auth.log` каждый день.
- Логи должны храниться **persistently** (`/var/log/journal`).
- Для внешних health‑checks не раскрывай лишнее: `curl -fsSIL` вместо полного тела.

---

## Быстрые блоки

```bash
sudo mkdir -p /etc/systemd/journald.conf.d                   # Каталог для drop-in конфигов

# фиксируем Storage=persistent
printf '[Journal]\nStorage=persistent\n' | sudo tee /etc/systemd/journald.conf.d/99-persistent.conf >/dev/null

sudo mkdir -p /var/log/journal                               # Еаталог, куда писать persistent-журнал
sudo systemd-tmpfiles --create --prefix /var/log/journal     # Еорректные права/владельцы на каталог
sudo systemctl restart systemd-journald                      # Перезапуск демона journald
journalctl --disk-usage                                      # Проверка: видим, что журнал на диске
test -d /var/log/journal && echo "Persistent включён"        # Быстрая проверка

sudo usermod -aG systemd-journal "$USER"                     # Добавить текущего пользователя в группу
newgrp systemd-journal                                       # Применить группу в текущей сессии (или перелогиниться)

sudo journalctl --vacuum-time=7d                             # Хранить только последние 7 дней
sudo journalctl --vacuum-size=1G                             # Или ограничить общий объём 1 ГБ

journalctl -o short-iso -b | tail -n 50                      # ISO-временной формат
journalctl -o cat -u nginx | tail -n 50                      # Чистый текст без метаданных (nginx)

journalctl --grep 'PATTERN'                                  # Либо короче: -g 'PATTERN'
journalctl -u ssh -g 'Failed password' --since 'today'       # Пример: ошибки по ssh за сегодня

zgrep -i 'panic' /var/log/*.gz                               # Искать по сжатым логам без распаковки
zless /var/log/syslog.1.gz                                   # Читать .gz постранично
```