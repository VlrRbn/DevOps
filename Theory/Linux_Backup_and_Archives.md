# Linux_Backup_and_Archives

---

## Архивация и сжатие (tar, gzip, bzip2, xz, zip, zstd)

| Формат | Команда создания | Распаковка |
| --- | --- | --- |
| tar.gz | `tar -czf backup.tar.gz DIR` | `tar -xzf backup.tar.gz` |
| tar.bz2 | `tar -cjf backup.tar.bz2 DIR` | `tar -xjf backup.tar.bz2` |
| tar.xz | `tar -cJf backup.tar.xz DIR` | `tar -xJf backup.tar.xz` |
| zip | `zip -r backup.zip DIR` | `unzip backup.zip` |
| zstd | `tar -I zstd -cf backup.tar.zst DIR` | `tar -I zstd -xf backup.tar.zst` |

`gzip` — **баланс** (быстро/нормально сжимает)

`xz` — **максимальная экономия**, но медленно.

`zstd` — **очень быстро**, сжатие ~между gzip и xz

Опции: `c` = create, `x` = extract, `t` = table, `v` = verbose, `f` = file.

Сжатие: `z` = gzip (`.tar.gz`, `.tgz`), **`j`** — bzip2 (`.tar.bz2`), **`J`** — xz (`.tar.xz`), **`-I prog`** — любой компрессор (zstd/lz4 и т.п.)

Проверка архива без распаковки:

```bash
tar -tzf backup.tar.gz
```

Путь/исключения/границы ФС:

```bash
tar -czf backup.tar.gz -C /srv app/
# **-C DIR** — «зайти» в каталог перед операцией

tar -czf app.tgz app --exclude='app/cache/*' --exclude-vcs
#--exclude='PATTERN' / --exclude-from=FILE / --exclude-vcs
#--one-file-system — не переходить на другие ФС (актуально для бэкапа /)
```

---

## rsync (синхронизация и бэкапы)

| Задача | Команда |
| --- | --- |
| Копия каталога | `rsync -aP /src/ /dst/` |
| С удалённым сервером | `rsync -aP /src/ user@host:/dst/` |
| Исключить файлы | `rsync -a --exclude '*.log' /src/ /dst/` |
| Инкрементальный бэкап | `rsync -a --link-dest=/prev/ /src/ /backup/` |
- `-n` / `--dry-run` — **сухой прогон** (перед любым `-delete` обязательно).
- `-a` = archive (права, даты, симлинки).
- `-P` = прогресс + докачка.
- `--link-dest` = hardlink для неизменённых файлов (экономия места).
- `-i` / `--itemize-changes` — покажет, *что именно* изменится.
- `--delete` / `--delete-after` — зеркалирование (удалять то, чего нет в источнике).
- `-z` / `--compress` — сжатие по сети (не нужно для уже сжатого: `.jpg`, `.mp4`, `.gz`).
- `--info=progress2` — нормальный общий прогресс (лучше, чем просто `P`).
- `-A -X` — ACL и xattrs (для «правильных» бэкапов Linux).
- `--numeric-ids` — не маппить имена пользователей/групп (надёжнее для бэкапа).
- `--checksum` — определять изменения по хешу (медленнее, но честно, когда mtime/size врут).
- `--rsync-path='sudo rsync'` — если на удалённой стороне нужны root-права.

## Слэш в конце

- `/src/ → /dst/` — копирует **содержимое** `src` в `dst`.
- `/src → /dst/` — создаст **`/dst/src/`**.

---

## Копирование по сети

| Инструмент | Когда брать | Команда |
| --- | --- | --- |
| scp | Разово кинуть файл | `scp -P 22 -pC file 'user@host:/path/’` |
| scp каталог | Простая папка | `scp -P 22 -pCr dir 'user@host:/path/’` |
| sftp | Интерактивно / через прокси | `sftp -P 22 user@host` → `put file` / `get file` |
| rsync | Синк с правами/датами, возобновление, исключения | `rsync -aP --info=progress2 /src/ 'user@host:/dst/’` |

В `scp` **-P** (порт, заглавная), **-p** (preserve, строчная).

- **scp**
    - `-P 22` — порт SSH
    - `-p` — сохранить время/права
    - `-C` — компрессия (полезно на медленной сети)
    - `-i ~/.ssh/key` — ключ
- **rsync**
    - `-a` — архивный режим (права/владельцы/время/логику ссылок)
    - `-P` — прогресс + докачка (`--partial --progress`)
    - `--info=progress2` — инфо про прогресс

---

## Инкрементальные бэкапы tar

Список изменений сохраняется в state-файле:

```bash
tar --listed-incremental=backup.snar -czf backup.0.tar.gz /home
tar --listed-incremental=backup.snar -czf backup.1.tar.gz /home
```

- `backup.0.tar.gz` — полный бэкап.
- `backup.1.tar.gz` — только изменения.

---

## Проверка целостности

| Команда | Что делает |
| --- | --- |
| `md5sum file` | Хэш md5 |
| `sha256sum file` | Более надёжный хэш |
| `sha512sum file` | Самый надёжный |
| `b2sum file` | Быстрее SHA-256 и криптонадёжен |
| `tar -tvf archive.tar` | Проверка содержимого архива |
| `tar -df archive.tar` | Сравнить архив с диском |
| `gzip -t / xz -t / zstd -t` | Проверка слоя сжатия |

---

## Практикум

1. Архивировать /etc:

```bash
tar -czf etc-$(date +%F).tar.gz /etc
```

1. Скопировать на другой сервер:

```bash
scp etc-2025-09-01.tar.gz user@host:/backup/
```

1. Синхронизировать каталог:

```bash
rsync -aP /var/www/ user@host:/srv/backup/www/
```

1. Проверить хэши:

```bash
sha256sum etc-2025-09-01.tar.gz
```

---

## Security Checklist

- Хранть бэкапы **не на том же диске**, что рабочие данные.
- Использовать `rsync --link-dest` для экономии места.
- Проверять бэкапы с `-dry-run` перед запуском.
- Хэши (`sha256sum`) для контроля целостности.
- Шифровать при передаче (scp/rsync поверх ssh).

---

## Быстрые блоки

```bash
# Полный архив /home
tar -czf home.tar.gz -C /home .

# Распаковка в /restore
tar -xzf home.tar.gz -C /restore

# Синхронизация через rsync
rsync -aP /src/ /dst/

# Инкрементальный tar-бэкап
tar --listed-incremental=backup.snar -czf backup.0.tar.gz -C /restore

# Проверка целостности
sha256sum backup.0.tar.gz
```