# lesson_06

# Управление Пакетами: APT и DPKG

**Date:** 2025-08-26  
**Topic:** Практика APT/dpkg: поиск, policy, версии, владельцы файлов, hold, snapshot/restore и unattended upgrades  
**Daily goal:** Научиться безопасно проверять состояние пакетов, симулировать изменения и готовить восстановление.
**Bridge:** [05-07 Operations Bridge](../00-foundations-bridge/05-07-operations-bridge.ru.md) — компенсация недостающих практических тем после уроков 5-7.

---

## 1. Базовые Концепции

### 1.1 APT vs DPKG vs APT-CACHE

- `dpkg` работает с уже установленными пакетами и локальными `.deb`.
- `apt` / `apt-get` работают с репозиториями и зависимостями.
- `apt-cache` - инструмент чтения метаданных (стабильный вывод, удобно для скриптов).

Практическое правило:

- **интерактивно:** `apt`
- **в автоматизации:** `apt-get` + `apt-cache`

### 1.2 Модель состояния пакетов

Пакет может быть:

- установлен
- доступен к обновлению
- на hold
- установлен автоматически как зависимость
- установлен вручную

Полезные проверки:

- installed vs candidate version
- manual vs auto
- список hold-пакетов

### 1.3 Зачем нужна симуляция

Перед реальными изменениями делаем симуляцию:

- `apt-get -s upgrade`
- `apt-get -s full-upgrade`
- `apt-get -s dselect-upgrade`

Это снижает риск неожиданных удалений/конфликтов.

### 1.4 Где лежат данные по пакетам

- Репозитории: `/etc/apt/sources.list`, `/etc/apt/sources.list.d/*.list`
- База статуса пакетов: `/var/lib/dpkg/status`
- APT cache: `/var/cache/apt/archives/`
- Конфиг unattended-upgrades (частота): `/etc/apt/apt.conf.d/20auto-upgrades`
- Конфиг unattended-upgrades (правила): `/etc/apt/apt.conf.d/50unattended-upgrades`

### 1.5 Как APT выбирает версию (Candidate)

APT выбирает версию в 2 шага:

1. Смотрит приоритет источника (Pin-Priority).
2. При равном приоритете выбирает более новую версию.

`Candidate` - это версия, которую APT поставит прямо сейчас, если выполнить `apt install <pkg>` или `apt upgrade`.

Если `Installed` и `Candidate` отличаются, значит обновление доступно (или выбран другой источник/приоритет).

### 1.6 Мини-глоссарий терминов урока

- `Installed` - версия, уже установленная на хосте.
- `Candidate` - версия, которую APT выберет для установки/апдейта сейчас.
- `Version table` - список доступных версий из источников с приоритетами.
- `Pin-Priority` - числовое правило выбора версии (например, `500`, `990`).
- `hold` - запрет обновлять пакет автоматически.
- `full-upgrade` - апгрейд, который может добавить/удалить пакеты для разрешения зависимостей.
- `autoremove` - удаление автозависимостей, которые больше никому не нужны.
- `phased update` - постепенная раскатка обновления на часть машин.

### 1.7 Операционный workflow: `read -> simulate -> apply`

Безопасный порядок работы с пакетами:

1. `read`: собрать контекст (`apt show`, `apt-cache policy`, `apt list --upgradable`).
2. `simulate`: посмотреть impact без изменений (`apt-get -s upgrade` / `-s full-upgrade`).
3. `apply`: только после проверки выполнить реальную команду.
4. `verify`: проверить результат (`apt list --upgradable`, сервисы, логи).

Практическое правило:

- если нет этапа simulate, это уже рискованный change.

---

## 2. Приоритет Команд (Что Учить Сначала)

### Core (обязательно сейчас)

- `apt update`
- `apt list --upgradable`
- `apt show <pkg>`
- `apt-cache policy <pkg>`
- `dpkg -L <pkg>`
- `dpkg -S <file>`
- `apt-mark hold|unhold|showhold`
- `apt-get -s upgrade`

### Optional (после core)

- `apt search <pkg>`
- `apt list -a <pkg>`
- `apt-cache madison <pkg>`
- `apt-cache depends <pkg>` / `apt-cache rdepends <pkg>`
- `apt-mark showmanual` / `apt-mark showauto`
- `apt-file search <path>`

### Advanced (для безопасной эксплуатации)

- snapshot/restore через `dpkg --get-selections` и `dpkg --set-selections`
- `apt-get -s dselect-upgrade` перед реальным restore
- phased updates и override-флаг
- dry-run проверка unattended-upgrades + анализ логов
- гигиена cache (`apt-get autoclean`, аккуратно с `autoremove`)

---

## 3. Core Команды: Что / Зачем / Когда

### `apt update`

- **Что:** обновляет индексы пакетов из репозиториев.
- **Зачем:** без свежего индекса вывод может быть устаревшим.
- **Когда:** перед любой проверкой или изменением пакетов.

```bash
sudo apt update
```

### `apt list --upgradable`

- **Что:** список установленных пакетов, у которых есть новые версии.
- **Зачем:** быстро увидеть backlog по обновлениям.
- **Когда:** перед maintenance-окном.

```bash
apt list --upgradable 2>/dev/null | head -n 20
```

### `apt show <pkg>`

- **Что:** метаданные пакета (depends, maintainer, description).
- **Зачем:** понять, что именно ставим/обновляем.
- **Когда:** до установки и принятия решения.

```bash
apt show htop | sed -n '1,25p'
```

### `apt-cache policy <pkg>`

- **Что:** installed, candidate, источники и приоритеты.
- **Зачем:** понять, почему выбирается конкретная версия.
- **Когда:** при проблемах с версиями.

```bash
apt-cache policy htop
```

Как читать вывод:

```text
htop:
  Installed: 3.3.0-4build1
  Candidate: 3.3.0-4build1
  Version table:
 *** 3.3.0-4build1 500
        500 http://archive.ubuntu.com/ubuntu noble/main amd64 Packages
        100 /var/lib/dpkg/status
```

- `Installed` - версия, которая уже стоит в системе.
- `Candidate` - версия, которую APT выберет для установки/обновления сейчас.
- `Version table` - все доступные версии + их приоритеты.
- `***` - текущая установленная версия.

Что означает число `500`:

- Это Pin-Priority для конкретного источника (репозитория).
- `500` обычно означает обычный включенный репозиторий.
- Это не “проценты” и не “оценка качества”, а правило выбора версии.

Быстрый ориентир по приоритетам:

- `100` - обычно текущая установленная версия (`/var/lib/dpkg/status`).
- `500` - стандартный внешний репозиторий без специальных правил.
- `990` - приоритет целевого release (если задан `APT::Default-Release`).
- `1001` и выше - принудительное предпочтение версии (часто через pinning).
- `<0` - версия запрещена к установке.

Где настраивается pinning:

- `/etc/apt/preferences`
- `/etc/apt/preferences.d/*.pref`

### `dpkg -L <pkg>`

- **Что:** какие файлы установил пакет.
- **Зачем:** найти бинарь/конфиги/доки.
- **Когда:** вопрос "куда установилось?".

```bash
dpkg -L htop | head -n 20
```

### `dpkg -S <file>`

- **Что:** какой установленный пакет владеет файлом.
- **Зачем:** связать путь на диске с именем пакета.
- **Когда:** troubleshooting по конкретному файлу.

```bash
dpkg -S /usr/bin/journalctl
```

### `apt-mark hold|unhold|showhold`

- **Что:** заморозка/разморозка обновления пакета.
- **Зачем:** временно удержать стабильную версию.
- **Когда:** рискованный апдейт, инцидент, окно стабилизации.

```bash
sudo apt-mark hold htop
apt-mark showhold | grep -E '^htop$' || true
sudo apt-mark unhold htop
```

Важно про `hold`:

- `hold` защищает от обычных `upgrade/full-upgrade`, но не заменяет change-процесс.
- `hold` легко забыть: пакет может "застрять" на старой версии и не получать важные фиксы.
- всегда периодически проверяй `apt-mark showhold` и фиксируй причину hold.

### `apt-get -s upgrade`

- **Что:** симуляция апгрейда без реальных изменений.
- **Зачем:** заранее видеть набор изменений.
- **Когда:** перед любым `upgrade`.

```bash
sudo apt-get -s upgrade | sed -n '1,40p'
```

---

## 4. Optional Команды (После Core)

### `apt search <pkg>` / `apt list -a <pkg>` / `apt-cache madison <pkg>`

- **Что:** `apt search` ищет пакет по имени/описанию; `apt list -a` показывает все доступные версии; `apt-cache madison` показывает компактную матрицу “версия -> источник”.
- **Зачем:** быстро понять, какие версии вообще существуют и откуда они приходят.
- **Когда:** выбор версии, сверка репозиториев, подготовка pinning.

```bash
apt search htop | sed -n '1,20p'
apt list -a nginx 2>/dev/null | head -n 10
apt-cache madison nginx
```

### `apt-cache depends <pkg>` / `apt-cache rdepends <pkg>`

- **Что:** `depends` показывает, что пакету нужно для работы; `rdepends` показывает, кому нужен этот пакет.
- **Зачем:** оценить blast radius перед удалением или фиксом.
- **Когда:** перед `remove/purge`, перед экспериментами с критичными пакетами.

```bash
apt-cache depends htop | sed -n '1,30p'
apt-cache rdepends htop | sed -n '1,30p'
```

### `apt-mark showmanual` / `apt-mark showauto`

- **Что:** показывает, что было установлено вручную, а что как зависимости.
- **Зачем:** понять, что потенциально попадет под `autoremove`.
- **Когда:** cleanup системы, минимизация образа, подготовка к миграции.

```bash
apt-mark showmanual | head -n 20
apt-mark showauto | head -n 20
```

Практическое правило:

- Перед `autoremove` сначала смотри `showauto`, чтобы не удалить нужное по ошибке.

### `apt-file search <path>`

- **Что:** находит пакет по файлу даже если пакет не установлен.
- **Зачем:** закрывает кейс, где `dpkg -S` не помогает (файл из неустановленного пакета).
- **Когда:** расследование “в каком пакете есть этот бинарь/lib?”.

```bash
sudo apt install -y apt-file
sudo apt-file update
apt-file search bin/journalctl | head -n 10
```

---

## 5. Advanced Темы (Snapshots, Restore, Unattended)

Advanced в этом уроке - это команды, которые влияют на целостность системы в масштабе:

- массовые изменения набора пакетов;
- автоматические апдейты без ручного подтверждения;
- изменение поведения rollout (phasing).

### 5.1 Снимок текущего package state

- **Что:** фиксируем состояние пакетов в файл.
- **Зачем:** иметь точку восстановления перед рискованными изменениями.
- **Когда:** до major-upgrade, миграции, hardening-экспериментов.

```bash
lessons/06-apt-dpkg-package-management/scripts/pkg-snapshot.sh ./pkg-state
```

Результат:

- `packages.list` (машиночитаемый список)
- `packages_table.txt` (читаемая таблица)

### 5.2 Безопасный restore (сначала симуляция)

- **Что:** восстановление package state из `packages.list`.
- **Зачем:** вернуть known-good состояние.
- **Когда:** после неудачного обновления, переезда, drift-конфигурации.

Симуляция (по умолчанию):

```bash
lessons/06-apt-dpkg-package-management/scripts/pkg-restore.sh ./pkg-state/packages.list
```

Реальное применение:

```bash
lessons/06-apt-dpkg-package-management/scripts/pkg-restore.sh --apply ./pkg-state/packages.list
```

### 5.3 Проверка `.deb` без установки

- **Что:** inspect пакета до установки.
- **Зачем:** заранее увидеть зависимости и список файлов.
- **Когда:** security review, offline audit, сомнительный внешний репозиторий.

```bash
apt-get download htop
dpkg -I htop_*.deb | sed -n '1,20p'
dpkg -c htop_*.deb | sed -n '1,20p'
rm -f htop_*.deb
```

### 5.4 Phased updates

- **Что:** постепенная раскатка обновления по проценту машин.
- **Зачем:** снизить массовый риск от проблемного обновления.
- **Когда:** почти всегда оставляем как есть; override только осознанно.

Проверка metadata:

```bash
apt-cache show <pkg> | grep -i Phased-Update-Percentage || true
```

Принудительно включить phased updates (рискованно):

```bash
sudo apt-get -o APT::Get::Always-Include-Phased-Updates=true upgrade -y
```

### 5.5 Проверка unattended-upgrades

`unattended-upgrades` нужен для автоматической установки обновлений (обычно security) без ручного запуска `apt upgrade`.

Зачем это нам:

- закрывать уязвимости быстрее;
- не пропускать регулярные security patching окна;
- держать серверы в более предсказуемом состоянии между ручными релизами.

Когда использовать:

- VPS/серверы, где важны security fixes даже без ежедневного ручного администрирования.

Когда быть осторожным:

- критичные прод-системы с жестким change window;
- окружения, где любое обновление проходит только через staging и approval.

Dry-run скриптом:

```bash
lessons/06-apt-dpkg-package-management/scripts/unattended-dry-run.sh
```

Скрипт проверяет:

- timers (`apt-daily*`)
- dry-run debug вывод
- последние логи unit
- наличие `/var/log/unattended-upgrades/`

### 5.6 Гигиена cache

- **Что:** `autoclean` чистит только устаревшие `.deb` в кеше.
- **Зачем:** экономия места без агрессивного удаления.
- **Когда:** регулярный maintenance, cleanup после апдейтов.

```bash
sudo apt-get autoclean
```

### 5.7 Быстрый запуск скриптов урока

Скрипты находятся в:

- `lessons/06-apt-dpkg-package-management/scripts/`

Проверка справки:

```bash
./lessons/06-apt-dpkg-package-management/scripts/apt-dry-upgrade.sh --help
./lessons/06-apt-dpkg-package-management/scripts/pkg-snapshot.sh --help
./lessons/06-apt-dpkg-package-management/scripts/pkg-restore.sh --help
./lessons/06-apt-dpkg-package-management/scripts/unattended-dry-run.sh --help
```

Быстрый типовой прогон:

```bash
./lessons/06-apt-dpkg-package-management/scripts/pkg-snapshot.sh ./pkg-state
./lessons/06-apt-dpkg-package-management/scripts/apt-dry-upgrade.sh --full
./lessons/06-apt-dpkg-package-management/scripts/pkg-restore.sh ./pkg-state/packages.list
```

---

## 6. Мини-Лаба (Core Path)

### Цель

Проверить состояние пакетов и безопасно просимулировать обновление.

### Шаги

1. Обновить package index.
2. Посмотреть список upgradable.
3. Проверить metadata и policy.
4. Проверить файлы пакета и владельца файла.
5. Выполнить simulation upgrade.

```bash
sudo apt update
apt list --upgradable 2>/dev/null | head -n 20

apt show htop | sed -n '1,20p'
apt-cache policy htop

dpkg -L htop | head -n 20
dpkg -S /usr/bin/journalctl

sudo apt-get -s upgrade | sed -n '1,40p'
```

Checklist:

- умею объяснить installed vs candidate
- умею найти, какие файлы ставит пакет и кто владелец файла
- умею проверять impact до реального апгрейда

---

## 7. Расширенная Лаба (Optional + Advanced)

### 7.1 Snapshot и dry restore

```bash
lessons/06-apt-dpkg-package-management/scripts/pkg-snapshot.sh ./pkg-state
lessons/06-apt-dpkg-package-management/scripts/pkg-restore.sh ./pkg-state/packages.list
```

### 7.2 Сравнение инструментов версий

```bash
apt list -a nginx 2>/dev/null | head -n 10
apt-cache madison nginx
apt-cache policy nginx
```

Цель: понимать, какой вывод использовать в каком кейсе.

### 7.3 Карта зависимостей

```bash
apt-cache depends htop | sed -n '1,30p'
apt-cache rdepends htop | sed -n '1,30p'
```

### 7.4 Dry-run unattended-upgrades

```bash
lessons/06-apt-dpkg-package-management/scripts/unattended-dry-run.sh
```

### 7.5 Практика hold/unhold

```bash
sudo apt-mark hold htop
apt-mark showhold | grep -E '^htop$' || true
sudo apt-mark unhold htop
```

---

## 8. Очистка

```bash
rm -f htop_*.deb
```

Если snapshot делался только для лабораторки:

```bash
rm -rf ./pkg-state
```

---

## 9. Итоги Урока

- **Что изучил:** модель состояния пакетов, выбор версии и безопасный workflow через симуляцию.
- **Что практиковал:** связку `apt/apt-cache/dpkg`, hold/unhold, поиск владельца файла.
- **Продвинутые навыки:** snapshot/restore пакетов, понимание phased updates, dry-run проверка unattended-upgrades.
- **Фокус по безопасности:** сначала simulate, потом apply.
- **Артефакты в репозитории:** скрипты в `lessons/06-apt-dpkg-package-management/scripts/`.
