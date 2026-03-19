# lesson_12

# Storage и Filesystems: `mount`, `fstab`, `fsck`, `swap`, `LVM`

**Date:** 2026-02-19
**Topic:** безопасная работа с файловыми системами, монтированием и LVM на loop-лабе.  
**Daily goal:** Научиться поднимать и обслуживать storage-стек без риска для реальных дисков, с проверяемым workflow и чистым откатом.

---

## 0. Prerequisites

Проверь базовые зависимости:

```bash
command -v lsblk blkid findmnt mount umount losetup mkfs.ext4 fsck.ext4 swapon swapoff mkswap
```

Для advanced LVM-части:

```bash
command -v pvcreate vgcreate lvcreate pvs vgs lvs || echo "install lvm2 for advanced part"
```

Критичное правило урока:

- работаем только через loop-файлы в `/tmp/lesson12-*`;
- не форматируем реальные `/dev/sdX`/`/dev/nvme...` устройства;
- изменения в `/etc/fstab` делаем только после backup и только с tagged-строками.

---

## 1. Базовые Концепции

### 1.1 Блочное устройство -> ФС -> mount point

Цепочка всегда одна:

- есть block device (`/dev/loopX`, `/dev/sdb1`, `/dev/mapper/vg-lv`);
- на нем файловая система (`ext4`, `xfs`);
- эта ФС монтируется в директорию (`/mnt/data`).

Без `mount` файловая система существует, но в дерево директорий не подключена.

### 1.2 Почему UUID важнее `/dev/sdX`

Имена устройств могут меняться после reboot или изменения железа. UUID стабилен.

Поэтому в `/etc/fstab` для постоянного mount почти всегда используем `UUID=...`, а не `/dev/sdb1`.

### 1.3 Что делает `/etc/fstab`

`fstab` = декларация постоянных mount/swap.

Поля строки:

1. `device` (`UUID=...`, `LABEL=...`, `/path/to/swapfile`)
2. `mountpoint` (или `none` для swap)
3. `fstype` (`ext4`, `xfs`, `swap`)
4. `options` (`defaults`, `nofail`, `noatime`, ...)
5. `dump` (обычно `0`)
6. `pass` (`1` root fs, `2` остальные fs, `0` не проверять fsck)

### 1.4 Что такое `fsck` и когда его запускать

`fsck` проверяет и ремонтирует ФС.

Ключевое правило:

- не запускаем repair на смонтированной RW-ФС;
- для онлайн-проверки используем безопасный preview (`-n`) или работаем после `umount`.

### 1.5 Swap: зачем он нужен

Swap не равен "медленной RAM", но:

- помогает пережить пики памяти;
- стабилизирует систему под нагрузкой;
- может спасать от раннего OOM.

Для lab мы используем swapfile, а не отдельный раздел.

### 1.6 LVM модель

LVM слой:

- `PV` (physical volume) — базовые блочные устройства;
- `VG` (volume group) — пул емкости;
- `LV` (logical volume) — логические тома для ФС.

Практическая польза: гибко увеличивать тома без ручной возни с разделами.

### 1.6.1 Как это выглядит в реальном потоке

Минимальный жизненный цикл:

```bash
sudo pvcreate /dev/loopA /dev/loopB
sudo vgcreate vglesson12 /dev/loopA /dev/loopB
sudo lvcreate -L 256M -n lvdata vglesson12
sudo mkfs.ext4 /dev/vglesson12/lvdata
sudo mount /dev/vglesson12/lvdata /mnt/lesson12-lvm

pv1.img (файл) → /dev/loopX → PV
pv2.img (файл) → /dev/loopY → PV
PV + PV → VG (vglesson12)
VG → LV (lvdata) = /dev/vglesson12/lvdata
LV → ext4
ext4 → mount /mnt/lesson12-lvm
```

Что здесь важно:

- `PV` — превращает device в участника LVM;
- `VG` — объединяет несколько PV в один общий пул;
- `LV` — выдает логический том из пула, уже как “виртуальный диск” под ФС.

### 1.6.2 Что именно расширяют в проде

Обычно расширяют не “раздел руками”, а LVM-слой:

1. добавить емкость в VG (новый PV или расширение существующего);
2. увеличить LV (`lvextend`);
3. расширить ФС (часто сразу через `lvextend -r`).

То есть масштабирование идет сверху вниз через LVM-абстракцию.

### 1.6.3 Как быстро читать `pvs` / `vgs` / `lvs`

- `pvs` — на каких устройствах построен LVM и сколько там свободно;
- `vgs` — сколько общего free space в пуле;
- `lvs` — размеры логических томов и к каким устройствам они привязаны.

Быстрое правило:

- если в `vgs` нет `VFree`, `lvextend` не вырастет;
- если LV вырос, но `df` не вырос — значит ФС не расширили.

### 1.6.4 Где чаще всего путаются

- форматируют не LV, а исходный loop/PV;
- пытаются задать LV почти в размер всего VG и упираются в метаданные/выравнивание;
- забывают проверить `findmnt`, и думают что “данные пишутся в новый том”, а пишутся в обычную папку.

### 1.7 Безопасный Ops-workflow

Для storage почти всегда:

1. `read` состояние (`lsblk`, `findmnt`, `blkid`);
2. `change` (формат/mount/swap/fstab);
3. `verify` (`findmnt`, `swapon --show`, `mount -a`, counters/logs);
4. `cleanup`/rollback.

---

## 2. Приоритет Команд (Что Учить Сначала)

### Core (обязательно сейчас)

- `lsblk -f`
- `blkid`
- `mount` / `umount`
- `findmnt`
- `cat /etc/fstab`
- `mount -a` (проверка корректности `fstab`)
- `mkswap`, `swapon`, `swapoff`, `swapon --show`
- `fsck.ext4 -n`

### Optional (после core)

- `df -hT`, `du -sh`
- `findmnt -o SOURCE,TARGET,FSTYPE,OPTIONS`
- `tune2fs -l`
- `pvs`, `vgs`, `lvs`

### Advanced (уровень эксплуатации)

- rollback-safe редактирование `/etc/fstab`
- LVM lifecycle: create -> extend -> verify
- диагностика "не монтируется после reboot"
- runbook: симптом -> проверка -> действие

---

## 3. Core Команды: Что / Зачем / Когда

### `lsblk -f`

- **Что:** дерево block devices и ФС.
- **Зачем:** понять карту storage за секунды.
- **Когда:** первая команда перед любыми изменениями.

```bash
lsblk -f
```

### `blkid`

- **Что:** UUID/LABEL/FSTYPE.
- **Зачем:** брать стабильные идентификаторы для `fstab`.
- **Когда:** перед добавлением постоянного mount.

```bash
sudo blkid
```

### `mount` + `findmnt`

- **Что:** подключить ФС и сразу проверить факт mount.
- **Зачем:** убедиться, что ФС действительно в нужной точке.
- **Когда:** после `mkfs`.

```bash
sudo mount /dev/loopX /mnt/lesson12-data
findmnt /mnt/lesson12-data
```

### `umount`

- **Что:** корректно отключить ФС.
- **Зачем:** безопасный cleanup и prerequisite для fsck/ремонта.
- **Когда:** перед detach loop или fsck-repair.

```bash
sudo umount /mnt/lesson12-data
```

### Проверка `/etc/fstab` через `mount -a`

- **Что:** применить `fstab` записи (кроме already-mounted) и сразу показать ошибки.
- **Зачем:** ловить синтаксис до reboot.
- **Когда:** после правки `fstab`.

```bash
sudo mount -a
```

### `mkswap` + `swapon` + `swapoff`

- **Что:** lifecycle swapfile.
- **Зачем:** контролируемая работа с swap без отдельного раздела.
- **Когда:** при добавлении/тестировании swap.

```bash
sudo dd if=/dev/zero of=/tmp/lesson12-storage/swapfile bs=1M count=128 status=none
sudo chown root:root /tmp/lesson12-storage/swapfile
sudo chmod 600 /tmp/lesson12-storage/swapfile
sudo mkswap /tmp/lesson12-storage/swapfile
sudo swapon /tmp/lesson12-storage/swapfile
swapon --show
sudo swapoff /tmp/lesson12-storage/swapfile
```

### `fsck.ext4 -n`

- **Что:** dry-run проверка ФС без записи изменений.
- **Зачем:** безопасно понять, есть ли ошибки.
- **Когда:** при triage или перед window на ремонт.

```bash
sudo fsck.ext4 -n "$LOOP_DEV"
```

---

## 4. Optional Команды (После Core)

Optional блок здесь про удобство и глубину проверки.

### 4.1 `df -hT` + `du -sh`

- **Что:** capacity с двух сторон: ФС и каталоги.
- **Зачем:** видеть, заполнен диск или "съела" конкретная папка.
- **Когда:** алерт по диску, ручной triage.

```bash
df -hT
sudo du -sh /var/log /var/lib 2>/dev/null
```

### 4.2 `findmnt -o SOURCE,TARGET,FSTYPE,OPTIONS`

- **Что:** точный источник, тип и опции mount.
- **Зачем:** верифицировать, что применилась нужная политика (`noatime`, `rw`, и т.д.).
- **Когда:** после `mount` и после `mount -a`.

```bash
findmnt -o SOURCE,TARGET,FSTYPE,OPTIONS /mnt/lesson12-data
```

### 4.3 `tune2fs -l`

- **Что:** метаданные ext4 (reserved blocks, mount count, state).
- **Зачем:** глубже понимать поведение ФС.
- **Когда:** advanced диагностика и baseline.

```bash
sudo tune2fs -l /dev/loopX | sed -n '1,40p'
```

### 4.4 `pvs`, `vgs`, `lvs`

- **Что:** состояние LVM слоев.
- **Зачем:** быстро понять "где закончилась емкость".
- **Когда:** после setup/extend LVM.

```bash
sudo pvs
sudo vgs
sudo lvs -a -o +devices
```

### Что делать в Optional на практике

1. Снять `df -hT` и `du -sh` для baseline.
2. Проверить active mounts через `findmnt`.
3. Для ext4 снять `tune2fs -l` верхние поля.
4. Если используешь LVM — зафиксировать `pvs/vgs/lvs` до и после изменений.

---

## 5. Advanced Темы (Ops-Grade)

### 5.1 Безопасная правка `/etc/fstab`

Надежный паттерн:

1. backup текущего файла;
2. добавить только tagged-строки;
3. проверить `mount -a`;
4. если ошибка — удалить только tagged-строки и повторить проверку.

```bash
sudo cp -a /etc/fstab /etc/fstab.bak.$(date +%F_%H%M%S)
# edit / append lines
sudo mount -a
```

### 5.2 LVM lifecycle: расширение тома

Если VG имеет free space, можно расширить LV и ФС за один шаг (`-r`):

```bash
sudo lvextend -L +64M -r /dev/vglesson12/lvdata
```

Это типичный паттерн "добавить место без пересоздания тома".

### 5.3 Почему ФС "не поднялась" после reboot

Частые причины:

- неверный UUID в `fstab`;
- опечатка в `fstype/options`;
- устройство недоступно (USB/ephemeral), а `nofail` не указан;
- конфликтующие duplicate-строки.

Быстрый алгоритм:

1. `lsblk -f` и `blkid` — фактические UUID;
2. сверить с `grep` в `/etc/fstab`;
3. `mount -a` и читать ошибку;
4. откат tagged-строк.

### 5.4 `fsck`: preview vs repair

- `-n` = только чтение/проверка (без записи);
- `-y` = авто-исправление (использовать только в controlled window);
- repair делаем на unmounted ФС.

### 5.5 Симптомы и действия

| Симптом | Проверка | Типичная причина | Действие |
|---|---|---|---|
| mount не работает | `findmnt`, `dmesg`, `blkid` | неверный тип/UUID | исправить `fstab` или mount command |
| swap не активируется | `swapon --show`, `ls -lh`, права/owner | sparse swapfile (после `truncate`) или owner не `root` | пересоздать через `dd`, `chown root:root`, `chmod 600`, `mkswap`, `swapon` |
| после изменений пропал том | `pvs/vgs/lvs` | ошибка в LVM sequence | проверить VG/LV, восстановить порядок create/mount |
| `mount -a` падает | stderr `mount -a` | синтаксис `fstab` | rollback tagged строк |

### 5.6 Почему cleanup-on-error обязателен даже в лабе

В storage-лабе ошибка в середине сценария часто оставляет хвосты:

- смонтированная ФС (`/mnt/...`);
- активный loop-device;
- активный swapfile.

Поэтому setup-скрипт должен иметь rollback (`trap ... EXIT`): если шаг упал, скрипт делает `swapoff -> umount -> losetup -d` и чистит свои временные изменения.
Это делает повторный запуск предсказуемым.

---

## 6. Скрипты в Этом Уроке

### 6.1 Ручной Core-проход (1 раз сделать без скрипта)

```bash
# 1) подготовка loop-образа
sudo mkdir -p /tmp/lesson12-storage /mnt/lesson12-data
truncate -s 256M /tmp/lesson12-storage/disk.img
LOOP_DEV="$(sudo losetup --find --show /tmp/lesson12-storage/disk.img)"

# 2) ext4 + mount
sudo mkfs.ext4 -F "$LOOP_DEV"
sudo mount "$LOOP_DEV" /mnt/lesson12-data
findmnt /mnt/lesson12-data

# check loop
losetup -a | grep /tmp/lesson12-storage/disk.img
lsblk -f "$LOOP_DEV"

# 3) swapfile (не через truncate, чтобы не было holes)
sudo dd if=/dev/zero of=/tmp/lesson12-storage/swapfile bs=1M count=128 status=none
sudo chown root:root /tmp/lesson12-storage/swapfile
sudo chmod 600 /tmp/lesson12-storage/swapfile
sudo mkswap /tmp/lesson12-storage/swapfile
sudo swapon /tmp/lesson12-storage/swapfile
swapon --show

# 4) fstab пример (сначала в файл)
sudo blkid "$LOOP_DEV"
cat > /tmp/lesson12-storage/fstab.example <<'EOT'
UUID=<PUT_UUID_HERE> /mnt/lesson12-data ext4 defaults,nofail,noatime 0 2
/tmp/lesson12-storage/swapfile none swap sw 0 0
EOT

# read/write test
sudo sh -c 'echo "ok $(date)" > /mnt/lesson12-data/healthcheck.txt'
sudo cat /mnt/lesson12-data/healthcheck.txt
sync

# 5) cleanup
sudo swapoff /tmp/lesson12-storage/swapfile
sudo umount /mnt/lesson12-data
sudo losetup -d "$LOOP_DEV"
```

### 6.2 Скрипты (automation)

```bash
chmod +x lessons/12-storage-filesystems-fstab-lvm/scripts/*.sh

# core
lessons/12-storage-filesystems-fstab-lvm/scripts/setup-storage-lab.sh
lessons/12-storage-filesystems-fstab-lvm/scripts/check-storage-lab.sh
lessons/12-storage-filesystems-fstab-lvm/scripts/cleanup-storage-lab.sh

# advanced lvm
lessons/12-storage-filesystems-fstab-lvm/scripts/setup-lvm-loop.sh
lessons/12-storage-filesystems-fstab-lvm/scripts/cleanup-lvm-loop.sh
```

### 6.3 Чем отличаются `setup-storage-lab.sh` и `setup-lvm-loop.sh`

| Скрипт | Схема | Что дает | Когда использовать |
|---|---|---|---|
| `setup-storage-lab.sh` | `loop -> ext4` + `swapfile` | минимум слоев, быстрый и понятный базовый flow | для core-практики `mount/fstab/swap` |
| `setup-lvm-loop.sh` | `loop -> PV -> VG -> LV -> ext4` | пул емкости и управляемое расширение тома (`lvextend`) | для advanced-практики и LVM сценариев |

Ключевая идея:

- в первом скрипте ФС живет прямо на loop-device;
- во втором ФС живет на `LV`, который выделяется из `VG`, собранной из нескольких `PV`.

Что автоматизируют скрипты:

- reproducible storage lab без реальных дисков;
- state file в `/tmp/lesson12_*_state.env`;
- tagged-cleanup для `fstab` и network-neutral teardown.

---

## 7. Мини-Лаба (Core Path)

Цель: поднять ext4+swap lab, проверить состояние, корректно убрать.

```bash
# setup
lessons/12-storage-filesystems-fstab-lvm/scripts/setup-storage-lab.sh

# checks
lessons/12-storage-filesystems-fstab-lvm/scripts/check-storage-lab.sh --strict

# quick manual verify
findmnt /mnt/lesson12-data
swapon --show

# cleanup
lessons/12-storage-filesystems-fstab-lvm/scripts/cleanup-storage-lab.sh
```

Критерии успеха:

- mountpoint активен в setup-фазе;
- swapfile виден в `swapon --show`;
- после cleanup нет mount/swap/loop для lab.

---

## 8. Расширенная Лаба (Optional + Advanced)

### 8.1 Проверка `fstab` с tagged workflow

```bash
lessons/12-storage-filesystems-fstab-lvm/scripts/setup-storage-lab.sh --write-fstab
sudo grep -n "lesson12-storage-lab" /etc/fstab
sudo mount -a
lessons/12-storage-filesystems-fstab-lvm/scripts/check-storage-lab.sh
```

### 8.2 LVM на loop устройствах

```bash
lessons/12-storage-filesystems-fstab-lvm/scripts/setup-lvm-loop.sh
sudo pvs
sudo vgs
sudo lvs -a -o +devices
findmnt /mnt/lesson12-lvm
```

### 8.3 Расширение LV (если есть свободное место в VG)

```bash
sudo lvextend -L +64M -r /dev/vglesson12/lvdata
sudo lvs -a -o +devices
df -h /mnt/lesson12-lvm
```

### 8.4 Полная очистка

```bash
lessons/12-storage-filesystems-fstab-lvm/scripts/cleanup-lvm-loop.sh
lessons/12-storage-filesystems-fstab-lvm/scripts/cleanup-storage-lab.sh
```

---

## 9. Очистка

Если работал вручную и что-то осталось:

```bash
sudo swapoff /tmp/lesson12-storage/swapfile 2>/dev/null || true
sudo umount /mnt/lesson12-data 2>/dev/null || true
LOOP_DEV="$(sudo losetup --list --noheadings --output NAME --associated /tmp/lesson12-storage/disk.img | head -n1)"
[[ -n "$LOOP_DEV" ]] && sudo losetup -d "$LOOP_DEV" || true
sudo sed -i '/lesson12-storage-lab/d' /etc/fstab
```

---

## 10. Итоги Урока

- **Что изучил:** lifecycle storage-объектов (device -> filesystem -> mount), роль `fstab`, preview-проверки `fsck`, и базовый LVM слой.
- **Что практиковал:** loop-based ext4 lab, swapfile workflow, проверка mount/swap состояния, безопасный cleanup.
- **Что теперь смогу сделать вручную:** собрать и проверить storage lab без риска для реального диска, диагностировать типовые mount/fstab ошибки.
- **Артефакты в репозитории:** `lessons/12-storage-filesystems-fstab-lvm/scripts/`, `lessons/12-storage-filesystems-fstab-lvm/scripts/README.md`.
