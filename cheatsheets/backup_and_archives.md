# backup_and_archives

---

## Архивация и сжатие (tar, gzip, xz, zstd, zip)

| Формат | Команда создания | Распаковка |
| --- | --- | --- |
| tar.gz | `tar -czf backup.tar.gz DIR` | `tar -xzf backup.tar.gz` |
| tar.bz2 | `tar -cjf backup.tar.bz2 DIR` | `tar -xjf backup.tar.bz2` |
| tar.xz | `tar -cJf backup.tar.xz DIR` | `tar -xJf backup.tar.xz` |
| tar.zst (zstd) | `tar -I zstd -cf backup.tar.zst DIR` | `tar -I zstd -xf backup.tar.zst` |
| zip | `zip -r backup.zip DIR` | `unzip backup.zip` |
- `gzip` — **баланс** скорость/сжатие.
- `xz` — **максимальная экономия**, но медленно.
- `zstd` — **очень быстро**, сжатие между gzip и xz (можно многопоточно: `tar -I "zstd -T0" -cf …`).

- Опции tar: `c`=create, `x`=extract, `t`=table, `v`=verbose, `f`=file.
- Компрессия: `z`=gzip, `j`=bzip2, `J`=xz, `-I prog`=любой компрессор (`zstd`, `pigz`, `pzstd`).

Проверка архива без распаковки:

```bash
tar -tzf backup.tar.gz       # список
# или детальнее
tar -tvf backup.tar.gz       # список с правами/датами/владельцами
```

Путь/исключения/границы ФС:

```bash
# «зайти» в каталог перед операцией
tar -czf app.tgz -C /srv app/

# исключения
tar -czf app.tgz app --exclude='app/cache/*' --exclude-vcs
# --exclude-from=FILE — паттерны из файла
# --exclude-vcs — игнорировать .git/.svn и т.п.

# не переходить на другие файловые системы (актуально при бэкапе /)
tar -czf root.tgz --one-file-system /
```

Многопоточное сжатие как drop‑in:

```bash
# вместо gzip
tar --use-compress-program=pigz -cf backup.tar.gz DIR
# zstd во все ядра
tar -I "zstd -6 -T0" -cf backup.tar.zst DIR
```

---

## rsync (синхронизация и бэкапы)

| Задача | Команда |
| --- | --- |
| Копия каталога (локально) | `rsync -aP /src/ /dst/` |
| С удалённым сервером | `rsync -aP /src/ user@host:/dst/` |
| Исключить файлы | `rsync -a --exclude '*.log' /src/ /dst/` |
| Инкрементальный бэкап (hardlink) | `rsync -a --link-dest=/backup/prev/ /src/ /backup/cur/` |

Полезные флаги:

- `-n` / `--dry-run` — **сухой прогон** (особенно перед `--delete`).
- `-a` — архив (права/даты/симлинки/владельцы).
- `-P` — прогресс + докачка (`-partial --progress`).
- `--info=progress2` — нормальный общий прогресс.
- `-i` / `--itemize-changes` — покажет, *что именно* изменится.
- `-A -X` — ACL и xattrs (для «правильных» бэкапов Linux).
- `--numeric-ids` — не маппить имена пользователей/групп.
- `--checksum` — честная проверка изменений по хешу (медленнее).
- `--delete`, `--delete-after` — зеркалирование. Безопаснее — `--delete-delay` + обязательно `--dry-run` сначала.
- `-x` / `--one-file-system` — **не переходить** на другие ФС (аналогично tar).
- `--rsync-path='sudo rsync'` — если на удалённой стороне нужны root‑права.

---

## «Слэш в конце» (важно)

- `/src/ → /dst/` — копирует **содержимое** `src` в `dst`.
- `/src → /dst/` — создаст **`/dst/src/`**.

---

## Копирование по сети

| Инструмент | Когда брать | Команда |
| --- | --- | --- |
| scp | Разово кинуть файл | `scp -P 22 -pC file user@host:/path/` |
| scp (каталог) | Простая папка | `scp -P 22 -pCr dir user@host:/path/` |
| sftp | Интерактивно / через прокси | `sftp -P 22 user@host` → `put file` / `get file` |
| rsync | Синхронизация с правами/датами, возобновление, исключения | `rsync -aP --info=progress2 /src/ user@host:/dst/` |

В `scp`: **-P** (порт, заглавная), **-p** (preserve, строчная), `-C` (компрессия), `-i ~/.ssh/key` (ключ).

Стриминг архива через SSH (экономит место на источнике):

```bash
tar -C /srv -czf - app | ssh user@host 'cat > /backup/app.tgz'
```

---

## Инкрементальные бэкапы tar

Список изменений хранится в state‑файле (`backup.snar`):

```bash
# полный бэкап
tar --listed-incremental=backup.snar -czf backup.0.tar.gz /home
# следующий инкремент
tar --listed-incremental=backup.snar -czf backup.1.tar.gz /home
```

Восстановление (сначала полный, затем инкременты по порядку):

```bash
mkdir -p /restore
# на полном лучше игнорировать список (иначе метаданные .snar могут мешать)
tar --listed-incremental=/dev/null -xpf backup.0.tar.gz -C /restore \
    --same-owner --acls --xattrs --numeric-owner
# затем по одному каждый инкремент
tar -xpf backup.1.tar.gz -C /restore --same-owner --acls --xattrs --numeric-owner
```

---

## Проверка целостности

| Команда | Что делает |
| --- | --- |
| `md5sum file` | Хэш MD5 (быстро, но устарел для безопасности) |
| `sha256sum file` | Надёжный контроль целостности |
| `sha512sum file` | Ещё надёжнее, медленнее |
| `b2sum file` | Быстро и криптостойко |
| `tar -tvf archive.tar` | Просмотр содержимого архива |
| `tar -df archive.tar` | Сравнить архив с файловой системой |
| `gzip -t FILE.gz` | Проверка слоя сжатия gzip |
| `xz -t FILE.xz` / `zstd -t FILE.zst` | Проверка слоя xz/zstd |

---

## Практикум

1. **Архивировать `/etc`**

```bash
sudo tar -czf etc-$(date +%F)-$(hostname).tar.gz /etc
sudo tar -C / -czpf - etc > etc-$(date +%F)-$(hostname).tar.gz    # Архив принадлежит пользователю (а не root)
```

2. **Скопировать на другой сервер** (любой способ)

```bash
# вариант 1: rsync (рекомендуется)
rsync -aP etc-*.tar.gz user@host:/backup/

# вариант 2: scp
scp -P 22 -pC etc-*.tar.gz user@host:/backup/
```

3. **Проверить целостность**

```bash
sha256sum etc-*.tar.gz > etc-*.tar.gz.sha256
sha256sum -c etc-*.tar.gz.sha256
```

3. **Тестовое восстановление** в `/restore` + сравнение

```bash
sudo mkdir -p /restore/etc
sudo tar -xpf etc-*.tar.gz -C /restore --same-owner --acls --xattrs --numeric-owner
# точечная проверка (пример)
diff -r /etc /restore/etc | head -100 || true
```

Напоминание: бэкап считается существующим только после **успешного restore**.

---

## Security Checklist

- Хранить бэкапы **не на том же диске/сервере**, что рабочие данные (off‑host/off‑site копии).
- Перед любым `--delete` в rsync — **всегда** `--dry-run` (и можно `--delete-delay`).
- Использовать `rsync --link-dest` для экономии места при ежедневных снапшотах.
- Контролировать целостность: `sha256sum`/`b2sum` и периодический `tar -tvf/-df`.
- Шифрование при передаче: scp/rsync по SSH.
- Права и владельцы: бэкап/restore от root; при восстановлении добавлять `--same-owner --acls --xattrs --numeric-owner`.
- Регулярный **test‑restore**: раз в N недель распаковать в `/restore` и проверить: `diff -r`, выборочные файлы, запуск сервисов.
- Ротация: держать последние N полных/инкрементальных копий, периодически тестировать старые.

---

## Быстрые блоки

```bash
# Полный архив /home (дата + хост)
tar -czf home-$(date +%F)-$(hostname).tar.gz -C /home .

# Распаковка в /restore (с максимальным сохранением метаданных)
mkdir -p /restore
sudo tar -xpf home-$(date +%F)-$(hostname).tar.gz -C /restore --same-owner --acls --xattrs --numeric-owner

# Синхронизация через rsync (сухой прогон, потом реально)
rsync -aP --info=progress2 -n /src/ /dst/
rsync -aP --info=progress2 /src/ /dst/

# Инкрементальный tar-бэкап /home
rm -f backup.snar
tar --listed-incremental=backup.snar -czf backup.0.tar.gz -C /home .
tar --listed-incremental=backup.snar -czf backup.1.tar.gz -C /home .

# Стриминг архива по SSH (без временных файлов на источнике)
tar -C /srv -czf - app | ssh user@host 'cat > /backup/app.tgz'

# Многопоточное сжатие как замена gzip
.tar --use-compress-program=pigz -cf backup.tar.gz DIR
```