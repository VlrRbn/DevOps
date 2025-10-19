# git

---

# База (инициализация и статус)

```bash
git init                    # создать репозиторий в текущей папке
git clone <url>             # склонировать репозиторий
git status                  # что изменено/не добавлено/в очереди на коммит
git help <команда>          # быстро открыть справку по команде
```

---

# Индексация (staging)

```bash
git add <file>              # добавить файл в индекс
git add .                   # добавить все изменения в текущей папке
git add -p                  # по кусочкам (интерактивно)
git restore --staged <f>    # убрать файл из индекса (останется в рабочей копии)
```

---

# Коммиты

```bash
git commit -m "msg"         # обычный коммит
git commit -am "msg"        # добавить ТОЛЬКО отслеживаемые файлы + коммит
git commit --amend          # переписать последний коммит (сообщение/содержимое)
```

---

# Просмотр изменений

```bash
git diff                    # разница рабочая копия ↔ индекс
git diff --staged           # индекс ↔ последний коммит
git show <hash>             # показать коммит/тег/объект
git blame <file>            # кто и когда трогал строки
```

---

# Ветвление

```bash
git branch                  # список веток
git branch <name>           # создать ветку
git checkout <name>         # переключиться
git checkout -b <name>      # создать и переключиться
git switch <name>           # переключиться
git switch -c <name>        # создать и переключиться
```

---

# Слияние и ребейз

```bash
git merge <branch>          # слить ветку в текущую (merge-коммит)
git rebase <branch>         # переписать историю поверх <branch>
git rebase -i HEAD~N        # интерактивная правка N последних коммитов
git mergetool               # запустить инструмент для решения конфликтов
```

---

# Работа с удалённым репом

```bash
git remote -v               # посмотреть remotes
git remote add origin <url> # добавить origin
git fetch                   # подтянуть ссылки/обновления без слияния
git pull                    # fetch + merge (обычно)
git pull --rebase           # fetch + rebase (чище история)
git push                    # отправить текущую ветку
git push -u origin <branch> # пуш и установить upstream
git push --force-with-lease # аккуратный форс-пуш (проверяет чужие изменения)
```

---

# Теги (релизы)

```bash
git tag                     # список тегов
git tag v1.0.0              # lightweight тег
git tag -a v1.0.0 -m "..."  # аннотированный тег
git push origin v1.0.0      # запушить тег
git push origin --tags      # запушить все теги
```

---

# Временная заначка (stash)

```bash
git stash                   # спрятать незакоммиченные изменения
git stash -u                # вместе с неотслеживаемыми
git stash list              # список тайников
git stash show -p           # что внутри тайника
git stash apply [@{n}]      # применить (не удаляя из списка)
git stash pop               # применить и удалить
```

---

# Отмена/возврат (осторожно)

```bash
git restore <file>                  # откатить файл к HEAD из рабочей копии
git restore --source=<hash> <file>  # откатить к конкретному коммиту
git reset --soft <hash>             # откатить HEAD, оставить индекс+раб.копию
git reset --mixed <hash>            # (по умолч.) сбросить индекс, оставить файлы
git reset --hard <hash>             # всё снести до <hash> (безвозвратно*)
git revert <hash>                   # создать “отменяющий” коммит (без переписи истории)
```

---

# Спасательные круги (когда “всё пропало”)

```bash
git reflog                # история перемещений HEAD/веток (даже после reset --hard)
git fsck --lost-found     # найти осиротевшие объекты (редко нужно)
```

Рецепт: нашёл нужный коммит в `git reflog` → `git checkout <hash>` → создай ветку `git switch -c rescue` → живи дальше.

---

# Выборочные переносы

```bash
git cherry-pick <hash1> [<hash2> ...]  # перенести коммиты поверх текущей ветки
git checkout <branch> -- <path>        # вытащить файл/папку из другой ветки
```

---

# Очистка мусора

```bash
git clean -n               # сухой запуск — что будет удалено
git clean -fd              # удалить неотслеживаемые файлы и папки
```

---

# Игноры, атрибуты, архив

```bash
echo "node_modules/" >> .gitignore
git rm -r --cached . && git add .     # применить .gitignore к уже отслеживаемому
git check-ignore -v <file>            # почему файл игнорится
git archive -o release.zip HEAD       # собрать архив из репозитория
```

---

# Сабмодули и worktree

```bash
git submodule add <url> path          # добавить сабмодуль
git submodule update --init --recursive

git worktree add ../dir feature-x     # отдельная рабочая директория для ветки
git worktree list
git worktree remove ../dir
```

---

# Конфигурация и удобства

```bash
git config --global user.name "Имя"
git config --global user.email "mail@example.com"
git config --global init.defaultBranch main
git config --global pull.rebase true
git config --global alias.lg "log --oneline --graph --decorate --all"
```

---

# Диагностика и проверка

```bash
git status -sb              # короткий статус
git diff --stat             # сводка изменений по файлам
git shortlog -sn            # вклад участников (по количеству коммитов)
git describe --tags         # ближайший тег к текущему коммиту
```

---

# Полезные флаги и приёмы

- `-n` / `--dry-run` — покажи, что сделаешь, не делай. (напр. `git clean -n`)
- `--` перед путями отделяет опции от имён файлов: `git checkout main -- path/file`
- `HEAD~N` — “N коммитов назад”; `HEAD^` — родитель; `HEAD^^` — дедушка.
- Конвенции сообщений: `feat:`, `fix:`, `chore:`, `refactor:`, и т.д. — облегчит чтение и релизы.
- Перед `reset --hard` сделать `git stash` или хотя бы `git branch backup/$(date +%F)`.
- Конфликты не пугают: `git status` подскажет, `git add` фиксирует, `git rebase --continue` завершит.