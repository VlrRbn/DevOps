# Linux_Disks_and_Filesystems

---

## Диагностика дисков

| Команда | Что делает | Зачем |
| --- | --- | --- |
| `lsblk` | Дерево устройств, разделов, точек монтирования | Быстрый обзор |
| `lsblk -fp` | UUID/LABEL + древо |  |
| `lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,UUID,MODEL` | Кастомные колонки | Гибкость |
| `blkid` | UUID/тип ФС | Когда нужен точный идентификатор |
| `findmnt` |  | Кто/куда смонтирован |
| `df -h` | Использование места | Проверка дисков |
| `du -xh --max-depth=1 . | sort -h` | Размеры папок | Кто «жрёт» место |
| `findmnt` | Где смонтировано устройство | Удобнее чем `mount` |
| `sudo nvme list` | Показывает Cписок NVMe-устройств |  |

```bash
sudo apt install ncdu && sudo ncdu
# Просмотр в ncdu (интерактивно) "кто «жрёт» место"
```

---

## Работа с разделами

| Инструмент | Где |
| --- | --- |
| `fdisk /dev/sdX` | MBR-диски (старое, до 2TB) |
| `parted /dev/sdX` | GPT и современные диски |
| `gdisk /dev/sdX` | Удобнее GPT |
| `lsblk -fp` | После изменений — проверить |

Пример с `fdisk`:

```bash
sudo fdisk /dev/sdb
# n (новый раздел), w (сохранить)
```

---

## Создание файловых систем

| ФС | Команда | Пример |
| --- | --- | --- |
| ext4 | `sudo mkfs.ext4 -L DATA -m 0 /dev/sdb1` | `-L` метка; `-m 0` убрать зарезервированные 5% для **данных.** Ext4 можно **сжимать оффлайн** (уменьшать размер раздела). |
| xfs | `sudo mkfs.xfs -L DATA /dev/sdb1` | Быстрый, надёжен. **Нельзя сжимать (shrink)**, только расширять (`xfs_growfs`). Хорош для больших файлов. Часто на серверах. |
| btrfs | `sudo mkfs.btrfs -L DATA /dev/sdb1` | Снапшоты, сжатие. Рекомендуют монтировать с `compress=zstd`. Поддерживает online grow/shrink (*в рамках носителя/RAID*). |
| swap | `sudo mkswap -L SWAP /dev/sdb2` | Подкачка. После — `sudo swapon /dev/sdb2`. Размер и swappiness настраиваются отдельно. |

Проверка:

```bash
sudo file -s /dev/sdb1
sudo file -s /dev/nvme0n1p2
```

---

## Монтирование

| Команда | Что делает |
| --- | --- |
| `sudo blkid /dev/nvme0n1p2` | Узнать UUID |
| `mount /dev/nvme0n1p1 /mnt` | Смонтировать |
| `umount /mnt` | Отмонтировать |
| `mount -o ro /dev/nvme0n1p2 /mnt` | Только чтение |
| `mount -a` | Примонтировать всё из /etc/fstab |
| `findmnt /mnt` | Проверить точку монтирования |

---

## fstab (автомонтирование)

Файл: `/etc/fstab`

Формат:

```bash
# ext4
UUID=<UUID>  /data  ext4  defaults,noatime  0 2

# xfs
UUID=<UUID>  /data  xfs   defaults,noatime  0 0

# btrfs (сжатие и автомаунт)
UUID=<UUID>  /data  btrfs defaults,noatime,compress=zstd,autodefrag  0 0

# swap
UUID=<UUID>  none   swap  sw  0 0
```

Пример:

```bash
sudo lsblk -f
# берем UUID и прописываем в /etc/fstab
```

Проверка:

```bash
sudo mount -a
```

---

## Работа со swap

| Команда | Что делает |
| --- | --- |
| `swapon -s` | Список swap |
| `free -h` | Общий объём/использование |
| `mkswap /dev/sdb2` | Сделать swap-раздел |
| `swapon /dev/sdb2` | Включить |
| `swapoff /dev/sdb2` | Выключить |
| `fallocate -l 1G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile` | Сделать Swap-файл |

fstab запись для swap:

```bash
/swapfile none swap sw 0 0
```

---

## Проверка и ремонт

| Команда | Что делает |
| --- | --- |
| `sudo umount /dev/sdb1 || sudo mount -o remount,ro /mntpoint` | **Всегда оффлайн.** Размонтируй том перед проверкой/ремонтом |
| `fsck /dev/sdb1` | Проверка ФС (off-line) |
| `e2fsck -f /dev/sdb1` | Для ext4 |
| `e2fsck -p /dev/sdb1` | Для ext4 полуавтоматическая починка |
| `xfs_repair -n /dev/sdb1` | Для XFS сначала dry-run |
| `xfs_repair /dev/sdb1` | Для XFS реальный ремонт |
| `btrfs check /dev/sdb1` | Для Btrfs оффлайн-проверка |
| `tune2fs -l /dev/sdb1` | Инфо об ext ФС |

---

## Мониторинг и SMART

| Команда | Что делает |
| --- | --- |
| `df -h` | Свободное место |
| `iostat -x 1` | Нагрузка на диск (sysstat) |
| `iotop` | Кто жрёт I/O |
| `smartctl -a /dev/sda` | SMART-проверка |
| `badblocks -sv /dev/sdb` | Проверка секторов |

---

## Практикум

1. Создать раздел и отформатировать в ext4:

```bash
sudo fdisk /dev/sdb
sudo mkfs.ext4 /dev/sdb1
```

1. Смонтировать:

```bash
sudo mount /dev/sdb1 /mnt
```

1. Добавить в fstab:

```bash
UUID=<UUID>  /data  ext4  defaults,noatime  0 2
```

1. Создать swap-файл 2G:

```bash
fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
```

---

## Security Checklist

- Использовать UUID вместо `/dev/sdX` в fstab (имена могут меняться).
- Swap-файл должен быть с правами `600`.
- Всегда делать `umount` перед `fsck`.
- Проверять SMART (`smartctl`) для предсказания проблем.
- Следить за `df -h` и `du -sh *` чтобы не словить «no space left».

---

## Быстрые блоки

```bash
# Список дисков и ФС
lsblk -f

# Смонтировать устройство
sudo mount /dev/sdb1 /mnt

# Автомонт через fstab
UUID=<UUID>  /data  ext4  defaults,noatime  0 2

# Проверка ФС ext4
sudo e2fsck -f /dev/sdb1

# SMART статус
sudo smartctl -a /dev/sda
```