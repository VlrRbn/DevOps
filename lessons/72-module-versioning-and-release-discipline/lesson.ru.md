# Урок 72. Версионирование модулей и дисциплина релизов

**Дата:** 2026-06-10

**Фокус:** превратить общий Terraform module в версионированный релизный артефакт: Git tags, changelog, release notes, решение о совместимости, закрепление версий по окружениям и доказанный rollback target.

**Подход:** урок 71 контролирует, куда идёт изменение. Урок 72 контролирует, какая именно версия модуля туда идёт.

---

## 1. Зачем нужен этот урок

В уроке 71 появился promotion path:

```text
dev -> stage -> prod
```

Но одного пути недостаточно. Если все окружения используют локальный source:

```hcl
source = "../../modules/network"
```

то окружение берёт тот код модуля, который оказался в текущем checkout. Для лаборатории это удобно, но не для production: у релиза нет стабильной идентичности.

Production-подход должен отвечать на вопросы:

- какая версия модуля продвигается;
- какой Git commit создал эту версию;
- это patch, minor или major;
- какие проверки доказали, что contract модуля не сломан;
- какие окружения уже приняли эту версию;
- куда откатываться при проблеме.

В этом уроке `network` module становится релизным артефактом:

```text
network/v1.0.0
network/v1.1.0
network/v2.0.0
```

Production-модель:

```text
local module source
        ↓
known-good commit
        ↓
network/v1.0.0 tag
        ↓
env roots pinned to network/v1.0.0
        ↓
module change
        ↓
tests + changelog + release note
        ↓
network/v1.1.0 tag
        ↓
dev -> stage -> prod
        ↓
rollback target network/v1.0.0
```

---

## 2. Что должно получиться

После урока должен уметь:

- объяснить, почему локального module path недостаточно для production-дисциплины релизов;
- определить публичный API Terraform module;
- классифицировать изменения как patch, minor или major;
- создавать module-scoped Git tags в monorepo;
- писать полезную запись в changelog и release note для модуля;
- закреплять версии модуля отдельно в каждом env root;
- продвигать одну и ту же версию через `dev -> stage -> prod`;
- доказывать, что rollback target существует;
- избегать опасных практик: двигать опубликованный tag, оставлять prod на плавающем `main`, выпускать breaking change как minor version.

---

## 3. Связь с предыдущими уроками

| Урок | Что уже есть | Что добавляет урок 72 |
| --- | --- | --- |
| 66 | module contracts и interface guarantees | contract становится границей release |
| 67 | Terraform native tests | проверки становятся gate перед tag |
| 68 | controlled apply pipeline | apply всё ещё использует exact reviewed plan |
| 69 | разные IAM roles для plan/apply | release checks не требуют apply permissions |
| 70 | policy as code по JSON plan | policy остаётся частью доказательств promotion |
| 71 | multi-environment promotion | promotion теперь двигает именованные версии модуля |

Главное различие:

```text
Promotion контролирует путь.
Versioning контролирует artifact.
```

---

## 4. Структура Репозитория

```text
lessons/72-module-versioning-and-release-discipline/
├── README.md
├── TAGS.md
├── CHANGELOG.md
├── lesson.en.md
├── lesson.ru.md
├── proof-pack.en.md
├── proof-pack.ru.md
├── ci/
│   └── lesson72-module-release.yml
├── scripts/
│   ├── check-module-version.sh
│   └── module-release-note.sh
├── policies/
└── lab_72/
    ├── packer/
    └── terraform/
        ├── envs/
        │   ├── dev/
        │   ├── stage/
        │   └── prod/
        └── modules/
            └── network/
```

`lab_72` специально стартует с multi-environment модели из урока 71. Архитектура остаётся знакомой, чтобы новой темой была именно дисциплина релизов модуля, а не новый дизайн инфраструктуры.

---

## 5. Публичный API Terraform module

У Terraform module публичный API шире, чем просто variables и outputs.

| Часть API | Примеры |
| --- | --- |
| Inputs | имена variables, types, defaults, validation rules |
| Outputs | имена outputs, types и смысл значений |
| Поведение | какие resources создаются, naming, tags, scaling model |
| Безопасность state | resource addresses, moved blocks, upgrade behavior |
| Операционный контракт | IAM permissions, secrets access pattern, rollback expectations |

Inputs
Это всё, что вызывающий код передаёт в module:

```hcl
module "network" {
  source = "..."

  project_name = "lab72-dev"
  environment  = "dev"
  web_ami_id   = "ami-..."
}
```

API здесь:

- имена variables
- types
- defaults
- validation rules
- required/optional статус

Если удалить input или сделать optional input обязательным, можно сломать вызывающий код.

Outputs
Это то, что module отдаёт наружу:

```hcl
output "web_asg_name" {
  value = aws_autoscaling_group.web.name
}
```

Если внешний код использует:

```hcl
module.network.web_asg_name
```

то переименование output сломает его код.

Поведение
Даже если variables и outputs не поменялись, module может начать вести себя иначе:

- было desired_capacity = 2
- стало desired_capacity = 1

- был public ALB
- стал internal ALB

- была одна схему именования
- стала другая

Это тоже часть контракта, потому что вызывающий код ожидает определённого поведения.

Безопасность state
Terraform привязан к resource addresses:

```text
aws_lb.app
aws_autoscaling_group.web
aws_security_group.web
```

Если ты переименовал resource без moved block, Terraform может решить:

- старый resource удалить
- новый resource создать

Для вызывающего кода это может быть breaking change, даже если variables/outputs не изменились.

Операционный контракт
Module также обещает операционное поведение:

- какие IAM permissions нужны
- как читаются secrets
- какой rollback path
- какие теги обязательны
- какие policy gates должны проходить

Например, если новая версия module внезапно требует iam:CreateRole, а раньше не требовала, это важное изменение.

Версия модуля — это обещание вызывающему коду. Если вызывающий код может обновиться без изменения inputs, но получить неожиданный plan, такое изменение нужно считать breaking.

---

## 6. Классификация версий

Используй эту таблицу.

| Тип версии | Значение для Terraform module | Примеры |
| --- | --- | --- |
| Patch `v1.0.1` | безопасное исправление ошибки, не должно требовать изменения кода у вызывающего кода. | исправить validation message, опечатку в docs, добавить missing tag на resource, исправить typo в README, поправить комментарий |
| Minor `v1.1.0` | обратно совместимая возможность | добавить optional variable с безопасным default, добавить output, добавить test без поломки старых вызывающих кодов |
| Major `v2.0.0` | breaking change | переименовать output, изменить output type, сделать optional variable required, поменять default capacity, удалить input, переименовать resource без moved block |

Практичное правило:

```text
Если существующий caller должен менять код или получит реальное изменение поведения инфраструктуры, это major.
```

Примеры:

| Изменение | Версия |
| --- | --- |
| Добавить `alb_zone_id` output | minor |
| Переименовать `web_asg_name` output | major |
| Добавить optional `enable_alb_access_logs = false` | minor |
| Сделать `web_ami_id` optional с небезопасным default | major или плохой дизайн |
| Исправить typo в README | patch |
| Поменять `web_desired_capacity` default с `2` на `1` | major |

Почему изменение default capacity может быть major?
Потому что caller ничего не менял, но после upgrade у него меняется runtime behavior.

---

## 7. Схема тегов

Используй module-scoped tags:

```text
network/v1.0.0
network/v1.1.0
network/v2.0.0
```

Не используй только это в monorepo:

```text
v1.0.0
```

Почему:

- `v1.0.0` не говорит, какой module выпущен;
- `network/v1.0.0` понятен в release notes и доказательствах promotion;
- будущие modules смогут иметь свои версии, например `observability/v1.0.0`.

На этом этапе tag ещё не создаём. Здесь важно только понять схему именования. Реальная команда создания tag будет ниже, в разделе `Процесс релиза`, после проверок и commit.

Проверить уже существующий tag:

```bash
git show network/v1.0.0 --stat
git rev-parse network/v1.0.0
```

Жёсткое правило:

```text
Не двигай опубликованный module tag. Создавай новую версию.
```

---

## 8. Закрепление версий модуля в env roots

Лаба стартует с local sources, чтобы validate и проверки работали без remote tag:

```hcl
source = "../../modules/network"
```

Для дисциплины релизов после создания tag замени local source на pinned Git source:

```hcl
module "network" {
  source = "git::https://github.com/VlrRbn/DevOps.git//lessons/72-module-versioning-and-release-discipline/lab_72/terraform/modules/network?ref=network/v1.0.0"

  project_name = "lab72-dev"
  environment  = "dev"
}
```

Важные детали:

- `?ref=network/v1.0.0` закрепляет module на tag;
- после смены ref нужен `terraform init -upgrade` или чистый init;
- prod не должен использовать `main` как module ref;
- во время promotion разные окружения временно могут быть на разных версиях.

Пример version matrix:

| Environment | Module version | Status |
| --- | --- | --- |
| dev | `network/v1.1.0` | testing |
| stage | `network/v1.0.0` | stable |
| prod | `network/v1.0.0` | stable |

---

## 9. Процесс релиза

### Step 1. Baseline `network/v1.0.0`

> Важно: Git tags и `module-release-note.sh` работают только с тем, что уже находится в Git commit.
> Untracked файлы, unstaged изменения и staged-but-not-committed изменения не попадут в `git diff network/v1.0.0 HEAD`.
> Если release note пустой, сначала проверь `git status`: возможно, baseline или изменение module ещё не закоммичены.

Запусти проверки. Первый tag создаётся только после того, как baseline code уже закоммичен и проверки зелёные:

```bash
terraform fmt -check -recursive lessons/72-module-versioning-and-release-discipline/lab_72/terraform
packer fmt -check -recursive lessons/72-module-versioning-and-release-discipline/lab_72/packer

TF_DATA_DIR=/tmp/l72-module-test-data \
terraform -chdir=lessons/72-module-versioning-and-release-discipline/lab_72/terraform/modules/network \
  init -backend=false -input=false -no-color

TF_DATA_DIR=/tmp/l72-module-test-data \
terraform -chdir=lessons/72-module-versioning-and-release-discipline/lab_72/terraform/modules/network \
  test -no-color
```

После успешных проверок и clean commit создай tag:

```bash
git tag -a network/v1.0.0 -m "network module v1.0.0"
git push origin network/v1.0.0
```

Теперь есть первая стабильная версия.

### Step 2. Закрепить env roots на `network/v1.0.0`

Обнови module source в `dev`, `stage`, `prod`, чтобы они ссылались на tag.

Проверка refs:

```bash
for env in dev stage prod; do
  lessons/72-module-versioning-and-release-discipline/scripts/check-module-version.sh \
    "lessons/72-module-versioning-and-release-discipline/lab_72/terraform/envs/${env}" \
    "network/v1.0.0"
done
```

### Step 3. Сделать non-breaking изменение

Пример minor change:

```hcl
output "alb_zone_id" {
  value       = aws_lb.app.zone_id
  description = "ALB hosted zone ID for DNS automation."
}
```

Это minor, потому что существующий вызывающий код не должен менять код.

### Step 4. Сгенерировать release note

До создания tag `network/v1.1.0` нового release ref ещё нет. Поэтому для предварительного review можно сравнить прошлый release с текущим commit-кандидатом `HEAD`:

```bash
lessons/72-module-versioning-and-release-discipline/scripts/module-release-note.sh \
  network \
  v1.1.0 \
  network/v1.0.0 \
  HEAD \
  > /tmp/release-note-network-v1.1.0.md
```

Смысл аргументов:

```text
network         модуль, который проверяем
v1.1.0          новая SemVer-версия без module prefix
network/v1.0.0  предыдущий release snapshot
HEAD            текущий commit-кандидат до создания tag
```

После создания tag финальное доказательство лучше генерировать tag-to-tag:

```bash
lessons/72-module-versioning-and-release-discipline/scripts/module-release-note.sh \
  network \
  v1.1.0 \
  network/v1.0.0 \
  network/v1.1.0 \
  > /tmp/release-note-network-v1.1.0.md
```

Короткое правило:

```text
HEAD = release candidate до tag
network/v1.1.0 = опубликованный release snapshot после tag
```

### Step 5. Обновить changelog и tag `network/v1.1.0`

Обнови `CHANGELOG.md`, затем создай tag:

```bash
git tag -a network/v1.1.0 -m "network module v1.1.0"
git push origin network/v1.1.0
```

### Step 6. Сначала обновить dev

Поменяй только `dev` на:

```text
dev: ref=network/v1.1.0
stage: ref=network/v1.0.0
prod: ref=network/v1.0.0
```

Команда:

```text
sed -i 's/ref=network\/v1.0.0/ref=network\/v1.1.0/' \
  lessons/72-module-versioning-and-release-discipline/lab_72/terraform/envs/dev/main.tf
```

Проверка:

```text
rg -n 'ref=network/v1.[01].0' \
  lessons/72-module-versioning-and-release-discipline/lab_72/terraform/envs
```

Затем в dev:

```bash
terraform init -upgrade -backend-config=backend.hcl
terraform plan
```

Ожидаемо:

- нет неожиданных replacements только из-за смены module ref;
- новый output появился, если добавил;
- policy checks проходят;
- доказательства сохранены до stage.

### Step 7. Продвинуть ту же версию в stage и prod

После чистых доказательств из dev двигай тот же tag в stage. После чистых доказательств из stage двигай тот же tag в prod.

Не продвигай другой commit под той же меткой версии. Смысл `network/v1.1.0` в том, что это один конкретный Git object.

---


## 9.1 Практический порядок прохождения

Иди в таком порядке:

1. Запусти локальные проверки, пока env roots используют `source = "../../modules/network"`.
2. Сделай commit чистого baseline.
3. Создай и отправь tag `network/v1.0.0`.
4. Замени module source в env roots на Git URL с `ref=network/v1.0.0`.
5. Сделай одно обратно совместимое изменение в module.
6. Закоммить изменение module, затем запусти release checks и сгенерируй release note.
7. Обнови `CHANGELOG.md`, затем создай и отправь tag `network/v1.1.0`.
8. Переведи `dev` на `network/v1.1.0`, проверь plan и сохрани evidence.
9. Тем же tag продвинь `stage`, затем `prod`.
10. Зафиксируй rollback target `network/v1.0.0`.

В CI input `release_version` — это только SemVer-часть, например `v1.1.0`. Полный module tag получается из `module_name/release_version`, например `network/v1.1.0`.

---

## 10. Модель CI - ci/lesson72-module-release.yml

Workflow не получает AWS roles. Это сделано специально:

- module release checks должны проходить до apply;
- Terraform native tests используют provider mocks;
- для classification module release не нужны apply permissions.

Workflow проверяет:

1. явный confirmation input;
2. checkout exact workflow commit;
3. Terraform format;
4. Packer format;
5. module native tests;
6. shell и OPA policy tests;
7. optional-проверку env root refs;
8. release note artifact;
9. GitHub Step Summary.

Пока lab использует local sources, ставь `enforce_env_refs=false`. Когда env roots будут pinned на Git tags, включай `enforce_env_refs=true`.

---

## 11. Процесс для breaking changes

Пример breaking change:

```text
rename output web_asg_name -> web_autoscaling_group_name
```

Это требует major release:

```text
network/v2.0.0
```

Перед major tag:

- обнови `CHANGELOG.md` с секцией `Breaking`;
- обнови module tests;
- обнови все root callers или явно опиши required caller actions;
- сгенерируй release note;
- докажи rollback target;
- начинай promotion с dev.

Не прячь breaking changes в `network/v1.1.0`.

---

## 12. Модель rollback

Rollback значит вернуть environment на предыдущий known-good tag:

```text
network/v1.1.0 -> network/v1.0.0
```

В этом уроке rollback — это не откат всего Git repository. Это точечное изменение module ref в конкретном environment.

Например, если проблема появилась только в `prod`, не нужно откатывать весь repo и не нужно трогать `dev` или `stage`. Нужно изменить только `prod` root module:

```hcl
source = "git::https://github.com/VlrRbn/DevOps.git//lessons/72-module-versioning-and-release-discipline/lab_72/terraform/modules/network?ref=network/v1.0.0"
```

Практический rollback для `prod`:

```bash
sed -i 's/ref=network\/v1.1.0/ref=network\/v1.0.0/' \
  lessons/72-module-versioning-and-release-discipline/lab_72/terraform/envs/prod/main.tf

cd lessons/72-module-versioning-and-release-discipline/lab_72/terraform/envs/prod
terraform init -reconfigure -upgrade -backend-config=backend.hcl
terraform plan
```

Если plan ожидаемый, rollback фиксируется обычным commit:

```bash
cd /home/leprecha/DevOps
git add lessons/72-module-versioning-and-release-discipline/lab_72/terraform/envs/prod/main.tf
git commit -m "revert(l72): roll prod back to network v1.0.0"
git push origin main
```

Почему не просто Git revert:

- Git revert отменяет commit в кодовой базе, а module rollback меняет версию зависимости окружения;
- один Git commit может содержать docs, CI, changelog и изменения для нескольких environments;
- проблема может быть только в `prod`, а `dev` и `stage` можно оставить на новой версии для расследования;
- tag `network/v1.0.0` указывает на конкретный известный module code, а не на “примерно старое состояние”;
- Terraform всё равно должен показать rollback plan до apply;
- через месяц видно, что `prod` осознанно вернули с `network/v1.1.0` на `network/v1.0.0`.

Rollback всё равно требует review:

```bash
terraform init -upgrade
terraform plan
```

Почему rollback нужно проверять:

- старый module code может убрать новые outputs;
- defaults могут отличаться;
- resources могут вернуться к старому поведению;
- rollback тоже может дать изменения в plan.

Rollback — это controlled promotion decision в обратную сторону.

---

## 13. Упражнения

### Упражнение 1. Baseline local lab

Запусти локальные проверки, пока env roots используют local module paths.

Ожидаемо:

- fmt проходит;
- Packer fmt проходит;
- module tests проходят;
- policy tests проходят.

### Упражнение 2. Создать `network/v1.0.0`

Создай первый module tag из clean commit.

Ожидаемо:

- tag существует;
- tag SHA сохранён;
- changelog содержит baseline entry.

### Упражнение 3. Закрепить все env roots на `network/v1.0.0`

Замени local module sources на Git sources с tag.

Ожидаемо:

- `check-module-version.sh` проходит для dev/stage/prod;
- после source change выполнен `terraform init -upgrade`.

### Упражнение 4. Выпустить `network/v1.1.0`

Сделай одно backward-compatible изменение, обнови changelog, сгенерируй release note и создай tag.

Ожидаемо:

- проверки проходят;
- release note существует;
- изменение классифицировано как minor.

### Упражнение 5. Продвинуть `v1.1.0`

Продвинь `network/v1.1.0` через:

```text
dev -> stage -> prod
```

Ожидаемо:

- доказательства dev есть до stage;
- доказательства stage есть до prod;
- prod не получает другой commit под тем же tag.

### Упражнение 6. Классификация breaking change

Симулируй output rename.

Ожидаемо:

- изменение классифицировано как major;
- проверки или callers падают, пока их не обновить;
- это не выпускается как `network/v1.1.0`.

### Упражнение 7. Rollback ref

Верни dev с `network/v1.1.0` на `network/v1.0.0`.

Ожидаемо:

- rollback plan reviewed;
- rollback target documented;
- post-rollback check captured.

---

## 14. Разбор проблем

| Симптом | Вероятная причина | Что делать |
| --- | --- | --- |
| `check-module-version.sh` говорит, что source local | env root всё ещё использует `../../modules/network` | после создания tag замени source на Git URL с `?ref=...` |
| Terraform всё ещё берёт старый module code | module cache не обновился | выполни `terraform init -upgrade` или удали `.terraform/modules` |
| `git push origin network/v1.1.0` падает | remote tag уже существует | не двигай tag; создай исправленную новую версию |
| prod plan неожиданно меняет ресурсы | minor release содержит behavior change | останови promotion, переклассифицируй как major или исправь module |
| rollback plan не пустой | rollback тоже меняет поведение | review как обычный plan |
| CI ref check падает | expected ref input не совпадает с env root | исправь env root или workflow input |
| release note diff пустой | неверные previous/new refs или tag не скачан | используй `fetch-depth: 0` в CI и проверь refs локально |

---

## 15. Пакет доказательств

Сохраняй evidence в ignored local folder:

```text
lessons/72-module-versioning-and-release-discipline/evidence/l72-network-v1.1.0/
```

Минимальный набор:

- version matrix before/after promotion;
- `git show network/v1.0.0 --stat`;
- `git show network/v1.1.0 --stat`;
- release note для `network/v1.1.0`;
- запись в changelog;
- Terraform native test output;
- policy test output;
- dev/stage/prod upgrade plans или CI artifacts;
- rollback target и rollback plan;
- final decision note.

Полный чеклист есть в `proof-pack.ru.md`.

---

## 16. Критерии успеха

Урок 72 завершён, если:

- `network/v1.0.0` существует как baseline tag;
- backward-compatible `network/v1.1.0` documented;
- env roots могут быть pinned на Git refs;
- module tests проходят до tag;
- release notes и changelog существуют;
- продвижение версии идёт через `dev -> stage -> prod`;
- breaking change example classified as major;
- rollback target documented;
- proof pack сохранён.

---

## 17. Итоги урока

- **Что изучил:** Terraform modules должны иметь release identity, а не быть просто reusable code.
- **Что практиковал:** module-scoped Git tags, SemVer classification, дисциплину changelog, генерацию release note, закрепление env refs и rollback targeting.
- **Операционный навык:** продвигать known module versions.
- **Почему это важно:** multi-environment promotion надёжен только тогда, когда module artifact версионирован, проверен и воспроизводим.
