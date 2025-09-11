# disks_and_filesystems

---

## Диагностика и инвентаризация

| Command | Что делает | Зачем/Пример |
| --- | --- | --- |
| `lsblk -o NAME,SIZE,FSTYPE,UUID,MOUNTPOINTS` | Дерево устройств/разделов | Быстро понять, что и где смонтировано |
| `blkid` | UUID/тип ФС | Подставить в fstab |
| `parted -l` | Сводка GPT/MBR, выравнивание | Проверка таблиц разделов |
| `fdisk -l` | Низкоуровневый список разделов | Альтернатива `parted -l` |
| `findmnt` | Дерево маунтов | Кто и куда смонтирован |
| `df -hT` | Использование ФС (с типом) | «Где кончилось место?» |
| `du -xh --max-depth=1 . | sort -h` | Топ папок по размеру | Понять, кто съел диск |
| `smartctl -a /dev/sda` | SMART S/ATA | Ранняя диагностика диска (пакет: smartmontools) |
| `nvme list` | NVMe устройства | Перечень NVMe (пакет: nvme-cli) |
| `nvme smart-log /dev/nvme0` | SMART NVMe | Температура/ошибки/ресурс NVMe |

---

## Работа с разделами (MBR/GPT)

Кратко: fdisk — базовый интерактив для MBR/GPT; gdisk — GPT-ориентированный; parted — для продвинутых сценариев/resize; sgdisk — скриптуемый.

| Command | Что делает | Зачем/Пример |
| --- | --- | --- |
| `fdisk /dev/sdX` | Интерактивная правка таблицы | Быстрые изменения (MBR/GPT) |
| `gdisk /dev/sdX` | GPT-утилита | Если диск точно GPT |
| `parted /dev/sdX` | Создание/resize разделов | Для >2 ТБ и гибких операций |
| `sgdisk --backup=tbl.bin /dev/sdX` | Бэкап/скриптинг GPT | Сохранить/восстановить таблицу |

**Заметки:**

- Для новых дисков — GPT по умолчанию (особенно >2 ТБ).
- После изменения разделов обновить ядру таблицу: `partprobe` или `echo 1 > /sys/class/block/sdXN/device/rescan`.

---

## Создание файловых систем

| Command | Что делает | Зачем/Пример |
| --- | --- | --- |
| `mkfs.ext4 -L DATA /dev/sdX1` | Форматирование ext4 | Универсальный выбор, можно **сжимать оффлайн** |
| `tune2fs -l /dev/sdX1` | Инфо/тюнинг ext | Проверка журнала/флагов |
| `mkfs.xfs -L DATA /dev/sdX1` | Форматирование XFS | Высокая производительность, grow only (`xfs_growfs`). Часто на серверах. |
| `xfs_info /mnt` | Инфо XFS | Параметры ФС |
| `mkfs.btrfs -L DATA /dev/sdX1` | Форматирование Btrfs | Снапшоты/сжатие/RAID уровни. Поддерживает online grow/shrink. |
| `btrfs filesystem df /mnt` | Квоты/занятость Btrfs | Реальная раскладка по чанкам |

**Полезное для Btrfs:** включать `compress=zstd`, для ноутов/SSD обычно `ssd`.

---

## Монтирование/размонтирование

| Command | Что делает | Зачем/Пример |
| --- | --- | --- |
| `mkdir -p /data && mount /dev/sdX1 /data` | Разовый маунт | Проверить ФС до fstab |
| `findmnt /data` | Проверить маунт | Убедиться, что смонтировано |
| `umount /data` | Размонтировать | Перед проверками/ремонтом |
| `mount -o remount,rw /` | Пересмонтировать RW/RO | Режим обслуживания |

---

## /etc/fstab — типовые строки

Правило: сначала протестировать mount -a (`mount -a -f -v`), только потом ребут.

| ФС | Строка fstab | Комментарий |
| --- | --- | --- |
| ext4 | `UUID=<uuid>  /data  ext4   defaults,relatime   0  2` | `relatime` обычно лучше, чем жесткий `noatime` |
| XFS | `UUID=<uuid>  /data  xfs    defaults,relatime   0  0` | XFS не fsck-ается при буте |
| Btrfs | `UUID=<uuid>  /data  btrfs  defaults,compress=zstd,ssd,relatime  0  0` | Можно добавить `autodefrag` для ноутов |
| Автомаунт | `UUID=<uuid>  /cold  ext4  x-systemd.automount,x-systemd.idle-timeout=600,defaults,relatime  0  2` | Ленивое подключение «холодных» точек |

---

## LVM — минимальный набор

| Command | Что делает | Зачем/Пример |
| --- | --- | --- |
| `pvcreate /dev/sdb` | Инициализация физ. тома | Подготовить диск для LVM |
| `vgcreate vgdata /dev/sdb` | Создать Volume Group | Пул хранения |
| `lvcreate -n data01 -L 50G vgdata` | Логический том | Выделить место под ФС |
| `mkfs.xfs /dev/vgdata/data01` | Файловая система | Часто XFS для данных |
| `mount /dev/vgdata/data01 /data` | Монтирование | Проверка перед fstab |
| `lvextend -L +10G /dev/vgdata/data01` | Увеличить LV | Расширение |
| `xfs_growfs /data` | Растянуть XFS | Делается по **точке монтирования** |
| `resize2fs /dev/vgdata/data01` | Растянуть ext4 | Если ФС — ext4 |

### Что происходит по шагам

1. `pvcreate /dev/sdb` — **клеймо LVM** на диске/разделе (тип *LVM2_member*). Теперь LVM видит этот носитель как **Physical Volume (PV)**.
2. `vgcreate vgdata /dev/sdb` — собираем **Volume Group (VG)** `vgdata`: это общий **пул места** (как ведро), из которого будем резать тома.
3. `lvcreate -n data01 -L 50G vgdata` — из пула режемь **Logical Volume (LV)** `data01` на 50 ГБ. Это «виртуальный раздел», который можно потом растягивать.
4. `mkfs.xfs /dev/vgdata/data01` — кладём **файловую систему** на **LV**.
5. `mount /dev/vgdata/data01 /data` — монтируем и пользуемся. (Постоянно — через `/etc/fstab`, лучше по UUID).
6. `lvextend -L +10G /dev/vgdata/data01` — **увеличиваем LV** на +10 ГБ из свободного места **VG**. Физически карта блоков **LV** расширяется.
7. `xfs_growfs /data` — **растягиваем файловую систему** поверх выросшего **LV**. Для XFS — по **точке монтирования**; для ext4 — `resize2fs /dev/vgdata/data01`.
    
    (Обе умеют расти **онлайн**.)
    

---

## RAID (mdadm) — база

| Command | Что делает | Зачем/Пример |
| --- | --- | --- |
| `mdadm --create /dev/md0 --level=1 --raid-devices=2 /dev/sdb /dev/sdc` | Создать RAID1 | Зеркало |
| `watch -n1 cat /proc/mdstat` | Мониторинг синка | Прогресс сборки |
| `mkfs.xfs /dev/md0` | ФС поверх RAID | XFS/ext4 |
| `mdadm --detail --scan >> /etc/mdadm/mdadm.conf` | Записать конфиг | Чтобы массив собирался при загрузке |

---

## Шифрование (LUKS)

| Command | Что делает | Зачем/Пример |
| --- | --- | --- |
| `cryptsetup luksFormat /dev/sdX1` | Инициализация LUKS | Зашифровать раздел |
| `cryptsetup open /dev/sdX1 secure_data` | Открыть (map) | Появится `/dev/mapper/secure_data` |
| `mkfs.xfs /dev/mapper/secure_data` | ФС поверх LUKS | Создать файловую систему |
| `echo 'secure_data UUID=<uuid> none luks' >> /etc/crypttab` | Запись в crypttab | Авто-открытие при загрузке |
| `/etc/fstab: /dev/mapper/secure_data /data xfs defaults,relatime 0 0` | Маунт в fstab | Последовательность: crypttab → fstab |

---

## TRIM/Discard (SSD/NVMe)

| Command | Что делает | Зачем/Пример |
| --- | --- | --- |
| `fstrim -av` | Ручной TRIM всех ФС | Освободить неиспользуемые блоки |
| `systemctl enable --now fstrim.timer` | Периодический TRIM | Лучше, чем `discard` в fstab |

---

## Swap и память

| Command | Что делает | Зачем/Пример |
| --- | --- | --- |
| `fallocate -l 1G /swapfile && chmod 600 /swapfile` | Создать swap-файл | Быстро увеличить swap |
| `mkswap /swapfile && swapon /swapfile` | Инициализировать/включить | Проверка: `swapon --show` |
| `echo '/swapfile none swap sw 0 0' >> /etc/fstab` | Постоянный swap | Автомонт при загрузке |
| `sysctl vm.swappiness=10` | Временный тюнинг | Меньше свопить под нагрузкой |
| `/etc/sysctl.d/99-swap.conf: vm.swappiness=10` | Постоянный тюнинг | Сохраняем настройку |
| `apt install -y zram-tools` | Лёгкий swap в RAM | Для ноутов/легких систем |

---

## Проверка и ремонт ФС

Всегда размонтировывай ФС перед оффлайн-проверкой. Для root — с live/rescue.

| ФС | Инструмент | Как/когда |
| --- | --- | --- |
| ext4 | `fsck.ext4 -f /dev/sdX1` | Оффлайн, при проблемах/грязном журнале |
| XFS | `xfs_repair -n /dev/sdX1` | Сначала `-n` (dry-run). Ремонт — с rescue/live |
| Btrfs | `btrfs scrub start -Bd /mnt` | Регулярная проверка данных на живой ФС |
| Btrfs (крайний случай) | `btrfs check [--repair] /dev/sdX1` | **Только оффлайн и понимая риски** |

---

## Автомонтирование (systemd.automount / autofs)

| Command | Что делает | Зачем/Пример |
| --- | --- | --- |
| `x-systemd.automount,x-systemd.idle-timeout=600` | Опции в fstab | Лениво монтировать «холодные» точки |
| `apt install -y autofs` | Демон autofs | Альтернатива через `/etc/auto.master` |

---

## NVMe/SMART

| Command | Что делает | Зачем/Пример |
| --- | --- | --- |
| `apt install -y smartmontools nvme-cli` | Пакеты мониторинга | Всё нужное разом |
| `smartctl -x /dev/nvme0` | Расширенный отчёт | Температура, сбои, ресурс |
| `nvme smart-log /dev/nvme0` | NVMe SMART | Ключевые метрики контроллера |

---

## Расширение ФС — памятка

| Сценарий | Шаги (кратко) |
| --- | --- |
| LVM + XFS | `lvextend -L +10G /dev/vg/data` → `xfs_growfs /mnt/data` |
| LVM + ext4 | `lvextend -L +10G /dev/vg/data` → `resize2fs /dev/vg/data` |
| Раздел + ext4 | Увеличить раздел (`parted`), ребут/перечитать → `resize2fs /dev/sdX1` |
| XFS shrink | **Нельзя** |

---

## Подводные камни

- **fstab/UUID**: неверный UUID → emergency mode. Всегда тестировать `mount -a`.
- **XFS repair/shrink**: `xfs_repair` только оффлайн; сжатия нет, уменьшать нельзя.
- **Btrfs check**: использовать только оффлайн; в повседневке — `scrub`.
- **Device busy**: `lsof +f -- /mnt` или `fuser -vm /mnt`.
- **noatime**: не ставить без нужды; `relatime` — хороший баланс.
- **TRIM**: предпочтительнее `fstrim.timer`, а не постоянный `discard`.

---

## Практикум

### 1. «Добавить диск и расширить /data (LVM+XFS)»

1. `pvcreate /dev/sdb` → `vgextend vgdata /dev/sdb`
2. `lvextend -l +100%FREE /dev/vgdata/data01` → `xfs_growfs /data`

### 2. «Разобраться с переполнением»

1. `df -hT` → 2) `du -xh --max-depth=1 /var \| sort -h` → 3) Перенос тяжёлых директорий на отдельный том/точку

### 3. «Btrfs c субволюмами и снапшотами»

```bash
mkfs.btrfs -L ROOT /dev/sdX1
mount /dev/sdX1 /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
umount /mnt
# fstab: subvol=@ и subvol=@home (compress=zstd,ssd)
```

Снимок/отправка:

```bash
btrfs subvolume snapshot -r /mnt/@ /mnt/@snap-$(date +%F)
# Передача на бэкап-диск:
btrfs send /mnt/@snap-2025-09-11 | btrfs receive /backup
```

---

## Security Checklist

- Отдельные точки для `/home`, `/var`, `/tmp` где уместно.
- `nosuid,nodev,noexec` для `/tmp` и «неисполняемых» разделов.
- LUKS для ноутбуков и чувствительных данных (с надёжной фразой).
- Резервная копия `/etc/fstab`, `/etc/crypttab`, `/etc/mdadm/mdadm.conf`.
- SMART/NVMe мониторинг по расписанию (cron/systemd.timer), алерты.
- Перед ремонтом — **бэкап** важных данных/метаданных (по возможности).
- Использовать UUID вместо `/dev/sdX` в fstab (имена могут меняться).
- Swap-файл должен быть с правами `600`.

---

## Быстрые блоки

### Новый диск → LVM → XFS → /data (+fstab)

```bash
# 1) Подготовка
pvcreate /dev/sdb
vgcreate vgdata /dev/sdb
lvcreate -n data01 -L 100G vgdata

# 2) Файловая система и маунт
mkfs.xfs /dev/vgdata/data01
mkdir -p /data
mount /dev/vgdata/data01 /data

# 3) fstab
blkid /dev/vgdata/data01     # можно использовать /dev/mapper/vgdata-data01
cat >> /etc/fstab <<'EOF'
/dev/mapper/vgdata-data01  /data  xfs  defaults,relatime  0  0
EOF
mount -a && findmnt /data
```

### Включить периодический TRIM

```bash
systemctl enable --now fstrim.timer
systemctl status fstrim.timer
```

### Зашифрованный раздел (LUKS) + XFS

```bash
cryptsetup luksFormat /dev/sdc1                   # Инициализирует LUKS-контейнер на разделе
cryptsetup open /dev/sdc1 secure_data
mkfs.xfs /dev/mapper/secure_data                  # Создать файловую систему внутри шифрованного маппинга

mkdir -p /secure
mount /dev/mapper/secure_data /secure

# persist:
echo 'secure_data UUID=$(blkid -s UUID -o value /dev/sdc1) none luks' >> /etc/crypttab       # Как открыть контейнер на старте
echo '/dev/mapper/secure_data /secure xfs defaults,relatime 0 0' >> /etc/fstab
```

### RAID1 из двух дисков

```bash
apt install -y mdadm
mdadm --create /dev/md0 --level=1 --raid-devices=2 /dev/sdb /dev/sdc     # Создание массива
watch -n1 cat /proc/mdstat                                               # Мониторинг синхронизации
mkfs.ext4 /dev/md0                                                       # Файловая система поверх массива
mkdir -p /raid1
mount /dev/md0 /raid1
mdadm --detail --scan >> /etc/mdadm/mdadm.conf                           # Автосборка при загрузке
```