# Урок 74. Disaster Recovery и Terraform Incident Runbooks

**Дата:** 2026-06-15

**Фокус:** подготовить runbooks восстановления для failed apply, stuck lock, восстановления state, аварийных ручных изменений и решений rollback/fix-forward.

**Подход:** безопасная Terraform-платформа не закончена, пока ты не знаешь, как восстанавливаться после сбоя.

---

## 1. Зачем нужен этот урок

К уроку 73 цепочка доставки уже содержит contracts, tests, promotion, policy gates, controlled apply, least-privilege IAM и cost controls.

Это предотвращает много инцидентов, но не заменяет процесс реагирования на инциденты.

Реальные Terraform-инциденты всё равно случаются:

- `terraform apply` падает на середине;
- state lock остаётся после упавшего job;
- S3 state object перезаписан или восстановлен неправильно;
- аварийное изменение через AWS Console создаёт drift;
- rollback опаснее, чем fix-forward;
- CI не может сделать apply из-за IAM, OIDC или доступа к backend;
- оператор может запаниковать и ухудшить state.

Главное правило:

```text
Во время восстановления не импровизировать со state.
- Остановись.
- Сделай snapshot.
- Диагностируй.
- Выбери действие.
- Выполни одно контролируемое действие.
- Проверь.
- Задокументируй.
```

Самая большая ошибка в восстановлении Terraform:

- панически запускать `apply` / `force-unlock` / `state push` / `restore`

Потому что Terraform держится на двух реальностях:

- `AWS reality`
- `Terraform state`

Если они расходятся, Terraform может начать трогать не то, что ты ожидаешь.

---

## 2. Результаты урока

После урока должен уметь:

- классифицировать Terraform-инциденты по severity;
- делать snapshot state до восстановительных работ;
- проверять версии S3 backend object;
- понимать stuck locks и `force-unlock`;
- отличать failed apply, drift и state corruption;
- использовать `terraform state pull` и `terraform state push` только под строгим контролем;
- выбирать rollback, fix-forward, state restore, import или break-glass;
- возвращать emergency changes под Terraform control;
- готовить доказательства восстановления и decision record.

---

## 3. Связь с предыдущими уроками

| Урок | Что уже есть | Что добавляет урок 74 |
| --- | --- | --- |
| 60 | S3 remote state и lockfile | state recovery и дисциплина версий |
| 61 | `moved`, `state mv`, `state rm`, `import` | модель emergency state surgery |
| 64 | drift detection | post-incident reality check |
| 68 | controlled apply | recovery после failed apply |
| 70 | JSON plan policy | снижение известных risky plans до инцидента |
| 73 | cost/blast-radius controls | financial и operational containment |

Главная модель:

```text
Prevention не равно recovery.
Policy снижает количество инцидентов.
Runbooks помогают пройти инциденты, которые всё равно случились.
```

---

## 4. Структура репозитория

```text
lessons/74-disaster-recovery-and-incident-runbooks/
├── README.md
├── lesson.en.md
├── lesson.ru.md
├── proof-pack.en.md
├── proof-pack.ru.md
├── runbooks/
│   ├── universal-incident-procedure.md
│   ├── failed-apply.md
│   ├── stuck-lock.md
│   ├── state-restore.md
│   ├── state-push-emergency.md
│   ├── drift-after-emergency.md
│   ├── break-glass.md
│   └── rollback-vs-fix-forward.md
├── scripts/
│   ├── README.en.md
│   ├── README.ru.md
│   ├── state-snapshot.sh
│   ├── list-state-versions.sh
│   ├── post-incident-check.sh
│   ├── runtime-health-check.sh
│   └── incident-decision-template.sh
├── policies/
└── lab_74/
```

`lab_74` сохраняет структуру delivery из уроков 71-73. Новая тема — операционное восстановление.

Русские версии runbooks лежат рядом с английскими файлами и имеют суффикс `.RU.md`. Файл `aws-reality-check-cheatsheet.RU.md` — русская шпаргалка с AWS CLI командами для проверки того, что реально существует в AWS во время инцидента.

---

## 5. Модель severity для инцидентов

| Severity | Значение | Пример | Первое действие |
| --- | --- | --- | --- |
| SEV-3 | низкое влияние | failed local plan | исправить обычным путём |
| SEV-2 | окружение деградировало, но восстанавливаемо | failed apply в dev/stage | snapshot, diagnose, fix-forward |
| SEV-1 | влияние на production | prod rollout сломал traffic | freeze applies, controlled recovery |
| SEV-0 | state/control-plane danger | wrong state, corrupted state, unsafe lock | stop all applies, recover carefully |

State/control-plane incidents опасны, потому что Terraform может неправильно понимать ownership. Сломанный EC2 instance обычно можно заменить; сломанный state может заставить Terraform трогать не те ресурсы.

---

## 6. Универсальная процедура инцидента

Каждый Terraform-инцидент начинается одинаково:

```text
1. Остановить автоматические applies.
2. Определить затронутое окружение.
3. Зафиксировать commit SHA и контекст оператора.
4. Сделать snapshot текущего state.
5. Сохранить текущий вывод plan.
6. Проверить реальное состояние AWS.
7. Выбрать rollback / fix-forward / state surgery / break-glass.
8. Выполнить одно контролируемое действие.
9. Проверить результат через post-incident plan или drift check.
10. Записать incident record.
```

Не пропускай snapshot state. Сначала snapshot, потом diagnosis.

Граница безопасности для урока:

```text
Не тренируй force-unlock, S3 state restore или terraform state push на shared/prod state.
Делай упражнения только в формате документации, если ты не в изолированной лаборатории восстановления.
```

### Safety stop list

Во время восстановления Terraform не запускай эти команды без отдельного approval и доказательств:

- повторный `terraform apply` без анализа нового plan;
- `terraform destroy`;
- `terraform force-unlock` без доказательства, что lock stale;
- `terraform state push` без snapshot, сравнения, approval и post-check;
- ручное удаление или перезапись S3 state objects;
- `terraform state rm` без задокументированного решения по ownership;
- `-target` как постоянный recovery method;
- исправление production state с локальной машины без peer review.

Правило:

```text
Если команда меняет remote state или real infrastructure,
ей нужны доказательства, approval и post-check.
```

### Recovery decision matrix

| Симптом | Вероятный тип проблемы | Первый безопасный шаг | Обычно правильный путь восстановления | Не делать первым шагом |
| --- | --- | --- | --- | --- |
| Apply упал на середине | partial apply | state snapshot + new plan | fix-forward или no-op | повторный apply вслепую |
| Lock не снимается | active или stale lock | проверить активные CI/local runs | wait или force-unlock with approval | force-unlock без доказательств |
| Plan показывает unexpected replace | drift/config/state mismatch | сравнить AWS reality и state | investigate, import, moved block или config fix | apply immediately |
| State object повреждён | state corruption | freeze + snapshot + list versions | S3 version restore | state push первым делом |
| Manual console change | drift after emergency | plan + AWS check | revert manual change или codify it | игнорировать drift |
| Prod traffic сломан | service incident | freeze applies + restore service | fix-forward или rollback по влиянию | state surgery без причины |

### Approval model для SEV-0

SEV-0 означает опасность для Terraform control plane. Solo recovery недопустим.

Минимум:

- один оператор;
- один reviewer/approver;
- snapshot текущего state;
- written recovery decision;
- post-recovery verification;
- incident record.

SEV-0 закрывается только когда Terraform снова корректно понимает ownership и следующий action понятен.

---

## 7. State snapshot

Используй:

```bash
lessons/74-disaster-recovery-and-incident-runbooks/scripts/state-snapshot.sh dev
```

Скрипт сохраняет:

- версия Terraform;
- Git SHA;
- статус Git working tree;
- вывод `terraform state pull`;
- текущий `terraform plan -detailed-exitcode`;
- короткий summary-файл.

Он не меняет инфраструктуру или state.

Теперь ключевое различие:

```text
state snapshot != S3 previous version
```

`state snapshot`:

- это текущий `terraform state pull`;
- делается перед `recovery`;
- показывает, что Terraform считает правдой прямо сейчас;
- нужен как доказательство и точка сравнения.

`S3 previous version`:

- это старая версия remote `state object`;
- хранится в S3, если включён `versioning`;
- может использоваться для `restore`;
- опасна, если выбрать не ту версию.

Важно: snapshot state может содержать secrets, ARNs, IP, DNS names и всю структуру инфраструктуры. Скрипт создаёт доказательства с приватными правами доступа к файлам, но raw snapshot всё равно нельзя коммитить или публиковать без redaction.

---

## 8. Модель восстановления S3 backend

State keys в lab выглядят так:

```text
lab74/dev/full/terraform.tfstate
lab74/stage/full/terraform.tfstate
lab74/prod/full/terraform.tfstate
```

Если S3 versioning включён, старые state objects остаются как previous object versions. Это даёт путь восстановления, если текущий state object случайно перезаписан.

Важное правило:

```text
S3 versioning — это recovery-инструмент, а не кнопка отменить.
```

Почему не кнопка отменить:

- он не откатывает AWS-ресурсы;
- он не проверяет, совпадает ли старый `state` с текущей инфраструктурой;
- он не знает, какой `commit` кода был актуален на тот момент;
- он может вернуть Terraform старую `карту ownership`, которая уже не совпадает с реальностью.

Перед restore любой версии:

- останови applies;
- сделай snapshot текущего state;
- выведи список versions;
- скачай и сравни candidate state;
- получи approval;
- проверь результат через plan после restore.

### Backend protection checklist

Перед тем как считать backend production-ready, проверь controls ниже.

| Control | Зачем |
| --- | --- |
| S3 versioning enabled | нужно, чтобы старые версии state вообще существовали |
| S3 public access block | state не должен стать публичным |
| SSE-S3 или SSE-KMS | state зашифрован в S3 |
| IAM least privilege | CI roles не читают/пишут unrelated state |
| CloudTrail для S3 object events | state reads/writes audit-ready |
| retention/lifecycle policy | старые версии не удаляются слишком рано |
| separate state keys per env | dev/stage/prod не перетирают друг друга |
| restricted break-glass role | emergency access отделён от normal CI |

CloudTrail здесь нужен как audit trail для backend: кто и когда читал, писал, удалял или восстанавливал S3 object versions со state. В этом уроке не нужно глубоко настраивать CloudTrail. Достаточно понимать, что в production recovery это источник доказательств, когда нужно разобрать действия с backend.

Этот урок не реализует все production backend controls. Он учит, что нужно проверить перед тем, как полагаться на backend recovery.

---

## 9. Просмотр версий state

Используй:

```bash
lessons/74-disaster-recovery-and-incident-runbooks/scripts/list-state-versions.sh \
  "$TF_STATE_BUCKET" \
  "lab74/dev/full/terraform.tfstate"
```

Что делает скрипт:

- вызывает `aws s3api list-object-versions`;
- показывает версии `объекта state`;
- не делает `restore`;
- не копирует `state`;
- не удаляет `state`.

Критерии:

- определить `latest version`;
- найти previous candidate versions;
- понимать, что list versions безопасен, а `restore`— нет.

---

## 10. Runbooks

Runbooks находятся в `runbooks/`. Русские версии лежат рядом с суффиксом `.RU.md`.

| Runbook | Назначение |
| --- | --- |
| `universal-incident-procedure.md` | общий порядок действий перед выбором конкретного пути восстановления |
| `failed-apply.md` | recovery после failed или partial `terraform apply` |
| `stuck-lock.md` | решение active vs stale lock |
| `state-restore.md` | процедура S3 version restore |
| `state-push-emergency.md` | last-resort `terraform state push` |
| `drift-after-emergency.md` | кто-то поменял AWS руками во время аварии |
| `break-glass.md` | пришлось обойти обычный CI/IAM-процесс |
| `rollback-vs-fix-forward.md` | выбор наименее рискованного пути восстановления |

Runbook — это не скрипт. Это decision path перед опасными командами.

Без `runbook` человек в инциденте часто делает самое опасное:

```text
Давай быстро перезапустим apply
Давай force-unlock
Давай вернём старый state
Давай руками поправим в AWS
```

Иногда это помогает. Но часто делает хуже.

`Runbook` заставляет сначала собрать доказательства и выбрать путь восстановления.

---

## 11. Recovery после failed apply

Используй `runbooks/failed-apply.md`.

Поведение по умолчанию:

```text
Не запускай apply повторно вслепую.
```

Failed `apply` может означать:

1. ничего не изменилось;

  Terraform начал `apply`, но ошибка случилась до изменений.

  Пример:
    - не получил credentials;
    - не смог взять `lock`;
    - не прошёл `precondition`;
    - не смог прочитать provider.

  Тогда следующий `plan` может быть таким же, как до `apply`.

2. часть ресурсов изменилась и `state` обновился;

  Terraform создал/изменил ресурс и успел записать это в `state`, но потом упал на другом ресурсе.

  Пример:
  - создал Security Group;
  - записал SG в `state`;
  - упал на ALB.

  Тогда следующий plan может просто продолжить с места остановки.

3. часть ресурсов изменилась, но `state` не сошёлся полностью;

  Самый неприятный вариант.

  Пример:
  - AWS resource реально создался;
  - Terraform не успел записать его в `state`;
  - `apply` упал.

  Тогда следующий `plan` может попытаться создать дубликат или упасть из-за AlreadyExists.

4. следующий `plan` хочет завершить тот же change;

  Мог быть timeout или `eventual consistency`.

  Terraform думает одно, AWS уже в другом состоянии или ресурс ещё стабилизируется.

5. следующий `plan` хочет неожиданно undo или replace.

  Это самый важный сигнал: нельзя просто применять.

  Если после failed `apply` следующий `plan` хочет удалить/заменить важные ресурсы, сначала diagnosis.

Восстановление основывается на следующем `plan` и реальном состоянии AWS, а не на панике.

Правильный порядок восстановления:

После failed `apply`:

1. Freeze applies.
2. Сохрани failed apply log.
3. Запусти state snapshot.
4. Запусти новый `terraform plan`.
5. Проверь реальные ресурсы в AWS.
6. Сравни: config, state, real AWS.
7. Выбери путь восстановления:
   - rerun apply;
   - fix-forward;
   - rollback;
   - import;
   - state rm/mv/moved block;
   - no-op.
8. Получи approval, если действие рискованное.
9. После восстановления запусти post-incident check.

### Когда rerun `apply` нормален?

Повторный `apply` может быть нормальным, если:

- ошибка была transient;
- следующий `plan` понятный;
- нет неожиданного destroy/create;
- `state` выглядит согласованным;
- AWS reality совпадает с ожиданием;
- ресурс не критичный или изменение безопасное.

Примеры transient-проблем:

- AWS API throttling;
- temporary timeout;
- dependency ещё не стабилизировалась;
- provider retry не дождался.

### Когда rerun `apply` плохая идея?

Не надо просто повторять `apply`, если:

- следующий `plan` непонятный;
- есть destroy/create важных ресурсов;
- есть `AlreadyExists`;
- есть missing resource в `state`;
- resource создан в AWS, но не в `state`;
- `apply` упал на IAM/PassRole/security;
- `lock`/`state` выглядит подозрительно.

---

## 12. Recovery после stuck lock

Terraform `lock` нужен, чтобы только один процесс Terraform писал в `state`.

Если два процесса одновременно пишут в один `state`, можно получить повреждённый `state` или несогласованную инфраструктуру.

Используй `runbooks/stuck-lock.md`.

И доказываешь:

- нет активного `GitHub Actions run`;
- нет локального `Terraform процесса`;
- `lock` действительно `stale`;
- есть approval на `force-unlock`.

`terraform force-unlock` снимает lock, но не доказывает, что lock stale. Операционный риск — снять lock, пока другой процесс Terraform реально работает.

### Что такое `lock`?

Когда Terraform работает с `remote state`, он ставит `lock`.

Смысл:

```text
“Я сейчас читаю/пишу state. Другие процессы Terraform должны ждать.”
```

Пока `lock` активен, второй процесс Terraform не должен писать в этот `state`.

Что такое `stuck lock`?

`stuck lock` - это ситуация, когда Terraform уже не работает, но `lock` остался.

Например:

- runner упал;
- локальный терминал оборвался;
- процесс Terraform умер;
- network timeout;
- job была отменена в плохой момент.

Но важно: не каждый `lock` - stuck.

`Lock` может быть **active**:

- GitHub Actions `apply` всё ещё работает;
- кто-то локально запускает `terraform apply`;
- Terraform долго ждёт AWS resource stabilization;
- процесс жив, но кажется зависшим.

### Почему `force-unlock` опасен?

Команда:

```bash
terraform force-unlock <LOCK_ID>
```

говорит Terraform: `сними lock принудительно`.

Она не проверяет, работает ли другой процесс Terraform. Она просто снимает `lock`.

Опасность:

```text
процесс A всё ещё пишет state
ты сделал force-unlock
процесс B начал apply
оба пишут/читают state
```

Результат:

- `state` может стать повреждённым;
- ресурс может создаться, но не попасть в `state`;
- ресурс может удалиться неожиданно;
- следующий `plan` станет странным;
- recovery станет сложнее.

Перед `force-unlock` нужно доказать, что `lock` stale.

Проверки:

1. GitHub Actions:

   - нет активного `apply workflow`;
   - нет queued/running job для этого env.

2. Локально:

   - нет запущенного `terraform` процесса;
   - другой терминал не делает `apply`/`plan`.

3. Backend:

   - `lock` висит дольше ожидаемого;
   - `lock owner`/`session` неактивен.

4. Команда/approval:

   - кто-то подтвердил, что процесс не живой;
   - решение записано в incident decision.

Только после этого:

```bash
terraform force-unlock <LOCK_ID>
```

### Что делать после `force-unlock`?

Сразу после `force-unlock` не надо делать `apply` на автомате.

Сначала:

```bash
terraform plan -detailed-exitcode
```

И смотри:

- нет ли странного `destroy`;
- не появился ли `drift`;
- не осталось ли partially-created ресурсов;
- совпадает ли `state` с `AWS reality`.

Потом post-incident check и запись в доказательства.

---

## 13. State restore и state push

Используй:

- `runbooks/state-restore.md` для S3 object version restore;
- `runbooks/state-push-emergency.md` для last-resort local state push.

Обычный config fix обычно безопаснее, потому что Terraform сначала строит plan, и ты видишь, какие ресурсы будут изменены.

State restore и `terraform state push` опаснее, потому что они меняют не AWS-ресурсы напрямую, а память Terraform о том, какими ресурсами он владеет.

Если подставить неправильный state, Terraform может:

- потерять уже существующий ресурс;
- создать дубликат;
- удалить или заменить не тот ресурс;
- начать управлять ресурсом под неправильным address;
- усилить drift вместо recovery.

Поэтому state restore и особенно `terraform state push` используются только после snapshot, сравнения, approval и post-check.

`terraform state push` специально считается аварийным путём. Он может перезаписать remote state локальным файлом, поэтому нужны snapshot, сравнение, approval и post-restore plan.

Это самый опасный `recovery` блок в уроке.

Здесь речь не про обычный rollback кода, а про восстановление или перезапись `Terraform state`.

### Что такое — S3 state restore?

Это когда ты берёшь старую версию объекта:

```text
lab74/dev/full/terraform.tfstate
```

из S3 versioning и делаешь её current version.

То есть Terraform начинает читать старый `state`.

### Что такое — Terraform state push?

Это когда у тебя есть локальный state-файл, и ты руками заливаешь его в remote backend:

```bash
terraform state push some-state.json
```

Это ещё опаснее, потому что ты напрямую перезаписываешь remote `state` локальным файлом.

### Почему это опасно?

`Terraform state` - это не просто “кэш”.

State хранит ownership:

```text
Terraform address -> real AWS resource ID
```

Пример:

```text
module.network.aws_lb.app -> arn:aws:elasticloadbalancing:...
module.network.aws_instance.proxy -> i-1234567890
module.network.aws_security_group.web -> sg-1234567890
```

Если `state` неправильный, Terraform может думать:

- ресурса нет, хотя он есть;
- ресурс есть, хотя его нет;
- ресурс принадлежит другому address;
- ресурс нужно удалить и создать заново;
- ресурс надо импортировать;
- ресурс надо перестать отслеживать.

### Почему config fix обычно лучше

Обычный путь:

```text
исправил Terraform config
terraform plan
review
terraform apply
```

Преимущество: Terraform заранее показывает, что изменится.

`State restore`/`state push` меняют основу, на которой Terraform строит план. Если выбрать неправильный `state`, следующий `plan` может быть опасным.

### Правильный порядок риска

```text
normal config fix
-> moved/import/state mv
-> S3 version restore
-> terraform state push as last resort
```

### Почему так?

`normal config fix`
- самый прозрачный;
- виден в Git;
- проходит CI;
- можно review.

`moved/import/state mv`
- чинит ownership;
- часто лучше, чем откатывать весь `state`.

`S3 version restore`
- меняет весь `state object` на старую версию;
- может быть нужно, если current `state` повреждён или случайно перезаписан.

`terraform state push`
- ручная перезапись remote state локальным файлом;
- использовать только как аварийный путь.

### Когда S3 state restore может быть уместен?

Например:

- current `state object` случайно перезаписан;
- `state` повреждён;
- `state` потерял большую часть resources;
- ошибка именно в backend `state`, а не в Terraform config;
- есть понятная предыдущая версия `state`;
- ты сравнил candidate `state` с текущим AWS;
- есть approval.

### Когда S3 state restore плохая идея?

Если проблема в коде:

- неправильный input;
- плохой module release;
- не тот AMI;
- ошибка в IAM policy;
- неверный lifecycle;
- неудачный refactor без `moved`.

Тогда restore старого `state` не чинит причину. Лучше исправлять config/module.

### Когда `terraform state push` может быть уместен?

Очень редко.

Например:

- remote `state` повреждён;
- S3 version restore невозможен;
- есть проверенный локальный `state snapshot`;
- команда понимает последствия;
- есть approval;
- после push будет обязательный `plan`.

Если есть нормальный S3 version restore, обычно он лучше, чем `state push`.

### Что делать обязательно?

Перед `state restore`/`state push`:

1. Freeze applies.
2. Сделать current `state snapshot`.
3. Сохранить список S3 state versions.
4. Скачать candidate `state`.
5. Сравнить:
   - current state;
   - candidate state;
   - Terraform config;
   - real AWS resources.
6. Записать decision.
7. Получить approval.
8. Выполнить restore/push.
9. Сразу сделать `terraform plan`.
10. Сохранить доказательства после инцидента.

---

## 14. Drift после emergency change

Используй `runbooks/drift-after-emergency.md`.

Emergency change допустим только когда incident требует этого. После этого окружение нужно вернуть под Terraform control.

Сценарий: случилась авария, и кто-то поменял AWS руками.

Например:

- открыл Security Group;
- увеличил ASG desired capacity;
- поменял listener rule;
- заменил target group;
- отключил alarm;
- поменял IAM policy;
- вручную перезапустил instance.

Это называется **emergency change** или **break-glass change**, если изменение сделано в обход обычного Terraform/CI процесса.

После такого `Terraform state` и Terraform config могут больше не совпадать с реальным AWS.

Это и есть `drift`.

### Почему drift после emergency change опасен?

Потому что Terraform потом может “исправить” AWS обратно.

Пример:

В аварии вручную увеличили ASG:

```text
desired_capacity: 2 -> 4
```

Terraform config всё ещё говорит:

```hcl
desired_capacity = 2
```

Следующий `terraform apply` может вернуть ASG обратно на `2`.

Если ручное изменение было нужно для стабилизации сервиса, Terraform может случайно убрать его.

Другой пример:

Вручную открыли временный доступ в Security Group.

Если это забыть:

- security risk останется;
- или Terraform потом закроет доступ неожиданно;
- или команда не будет понимать, почему поведение отличается от кода.

### Правильный recovery flow

После emergency AWS change:

1. Зафиксировать, что поменяли:
   - кто;
   - когда;
   - зачем;
   - какой ресурс;
   - какое старое/новое значение.
2. Freeze applies, если есть риск.
3. Запустить `terraform plan -detailed-exitcode`.
4. Посмотреть, что Terraform хочет вернуть.
5. Выбрать путь:
   - принять изменение в код;
   - откатить ручное изменение;
   - импортировать ресурс;
   - убрать ресурс из state;
   - сделать controlled fix-forward.
6. Проверить результат.
7. Добавить follow-up, чтобы это не повторилось.

### Возможные решения — Принять изменение в Terraform config

Если ручное изменение стало новым желаемым состоянием.

Пример:

- ASG временно подняли до 4;
- решили, что теперь нужно 4;
- меняем Terraform variable/config;
- делаем plan/apply через нормальный pipeline.

### Возможные решения — Откатить ручное изменение

Если изменение было временным.

Пример:

- открыли SG для диагностики;
- диагностика закончилась;
- возвращаем SG к Terraform config;
- plan должен стать clean.

### Import

Если в аварии создали новый ресурс руками, и теперь Terraform должен им управлять.

```bash
terraform import <address> <real-resource-id>
```

После import обязательно `plan`.

`terraform import` только привязывает реальный AWS-ресурс к Terraform address в `state`.

Он не доказывает, что config полностью совпадает с этим ресурсом.

### State rm

Если Terraform больше не должен управлять ресурсом.

```bash
terraform state rm <address>
```

Осторожно: ресурс останется в AWS, но Terraform перестанет его видеть.

### Fix-forward

Если откат опаснее, чем закрепить правильное состояние новым изменением.

Например:

- manual change стабилизировал сервис;
- rollback приведёт к downtime;
- лучше внести корректный Terraform config и пройти pipeline.

### Главное правило

```text
Внесение изменений вручную в экстренных случаях должно либо стать частью кода Terraform, либо быть удалено.
```

Иначе будет вечный `drift`.

---

## 15. Break-glass

Используй `runbooks/break-glass.md`.

Break-glass — аварийный путь вне обычного процесса. Он допустим только когда обычный путь недоступен или слишком медленный при активном влиянии на сервис.

В Terraform/AWS это значит:

```text
Мы временно обходим обычный CI/IAM-процесс, потому что ждать нормальный путь опаснее.
```

Примеры:
- вручную закрыть публичный доступ;
- срочно увеличить capacity;
- временно отключить опасный listener/rule;
- отозвать скомпрометированный credential;
- вручную восстановить доступ к backend;
- использовать emergency role.

### Когда break-glass нужен?

Если:

- CI сломан;
- GitHub недоступен;
- OIDC role не работает;
- apply pipeline завис;
- есть security incident;
- сервис лежит;

то иногда нужно действовать руками.

Но `break-glass` опасен тем, что создаёт `drift` и обходит `guardrails`.

### Правильная модель break-glass

`Break-glass` должен быть:

1. rare
2. approved
3. logged
4. time-bound
5. reviewed
6. согласован с Terraform

Разберём:

`rare`
- Не обычный способ деплоя.
- Если `break-glass` нужен каждую неделю, значит процесс плохой.

`approved`
- Кто-то должен подтвердить действие, даже если быстро.

`logged`
- Нужно записать кто, что, когда и зачем сделал.

`time-bound`
- Доступ или исключение должны быть временными.

`reviewed`
- После инцидента нужно разобрать, что произошло.

`согласован с Terraform`
- Ручное изменение должно быть либо внесено в код, либо убрано.

    Это может быть один из вариантов:
    - ручное изменение откатили, и `terraform plan` снова чистый;
    - ручное изменение добавили в Terraform-код, и теперь Terraform им управляет;
    - ресурс импортировали в `state`;
    - `state` поправили `import`/`moved`/`state rm`, и Terraform снова правильно понимает ownership;
    - после фикса `terraform plan -detailed-exitcode` показывает ожидаемый результат, а не неожиданный `drift`.

### Что нельзя делать?

Плохой `break-glass`:

```text
“Я просто зашёл админом и что-то поправил.”
```

Почему плохо:

- никто не знает, что изменилось;
- Terraform может перетереть изменение;
- audit trail неполный;
- security risk может остаться;
- невозможно повторить recovery.

### Пример хорошей записи `break-glass-record.md`

```markdown
# Break-Glass Record

- Incident ID: INC-001
- Environment: prod
- Severity: SEV-1
- Operator: Valerii
- Approver: On-call lead
- Start UTC: 2026-06-24T12:10:00Z
- End UTC: 2026-06-24T12:25:00Z

## Why normal path was not enough

GitHub Actions apply was blocked by OIDC failure, and production ALB listener rule exposed an unsafe route.

## Action Taken

Temporarily disabled the unsafe listener rule in AWS Console.

## Verification

ALB route no longer reachable. Terraform plan shows drift on listener rule.

## Reconciliation

Terraform config updated and applied through normal pipeline after CI recovery.

## Follow-up

Add policy test for unsafe listener rule.
```

## Главное правило

```text
Break-glass допустим только если бездействие опаснее обхода обычного процесса.
```

---

## 16. Rollback vs fix-forward

Используй `runbooks/rollback-vs-fix-forward.md`.

Rollback не становится безопасным автоматически.

Когда что-то сломалось, есть два базовых пути:

```text
rollback = откатиться назад
fix-forward = исправить вперёд
```

### Rollback

`Rollback` - это когда ты возвращаешься к предыдущему известному хорошему состоянию.

В Terraform это может быть:

- вернуть предыдущую версию `module`;
- вернуть предыдущий `commit`;
- вернуть старые input values;
- откатить AMI;
- вернуть прошлую IAM policy;
- вернуть старый ASG desired capacity;
- вернуть старую listener rule.

Пример:

```bash
git revert <bad_commit>
terraform plan
terraform apply
```

Или в module versioning:

```hcl
source = "git::https://github.com/VlrRbn/DevOps.git//.../modules/network?ref=network/v1.1.0"
```

откатить на:

```hcl
source = "git::https://github.com/VlrRbn/DevOps.git//.../modules/network?ref=network/v1.0.0"
```

### Fix-forward

`Fix-forward` - это когда ты не возвращаешь старое состояние, а делаешь новое исправление.

Например:
- сломалась IAM policy - добавляешь недостающее разрешение;
- ALB health check неверный - исправляешь health check;
- ASG capacity мала - увеличиваешь capacity;
- AMI плохой - выпускаешь новую AMI;
- security rule слишком широкая - добавляешь точное правило.

### Почему rollback не всегда безопаснее

`Rollback` может быть опасен, если:

- текущая инфраструктура уже изменилась;
- `state` ушёл вперёд;
- database migration уже применена;
- ресурс был заменён;
- ручной emergency change стабилизировал сервис;
- откат удалит новые зависимости;
- старая версия имела security issue;
- старый AMI больше не доступен.

Пример:

Ты выкатил новую версию, потом вручную увеличил ASG, чтобы сервис выжил.

Если сделать rollback на старый config, Terraform может вернуть capacity вниз и снова положить сервис.

### Когда rollback хорош

`Rollback` обычно хорош, если:

- изменение маленькое;
- предыдущее состояние известно и безопасно;
- нет irreversible changes;
- `state` и `AWS reality` понятны;
- `plan` показывает ожидаемый откат;
- downtime допустим или отсутствует.

### Когда fix-forward лучше

Fix-forward часто лучше, если:

- rollback затронет больше ресурсов;
- старая версия небезопасна;
- данные/миграции уже ушли вперёд;
- emergency change уже стабилизировал сервис;
- проблема понятна и исправляется точечно;
- rollback создаёт больший `blast radius`.

### Как принять решение

Сравни два плана:

```text
rollback plan
fix-forward plan
```

И оцени:

- что будет deleted;
- что будет replaced;
- что будет changed;
- какой downtime;
- есть ли data loss;
- какое влияние на безопасность;
- какой blast radius;
- какое время восстановления;
- какой путь понятнее команде.

### Главное правило

```text
Choose the path with the smallest understood risk, not the path that sounds safer.
```

То есть не “rollback всегда лучше” и не “fix-forward всегда лучше”.

Нужно выбрать путь, где риск понятен, ограничен и проверяем.

Выбирай `rollback`, когда есть previous known-good config и rollback plan безопасен.

Выбирай `fix-forward`, когда маленькое исправление безопаснее, чем откат частично применённого изменения.

`State restore` выбирается только когда проблема именно в `state`.

---

## 17. Post-incident check

Это проверка после восстановления.

То есть если сделал что-то из этого:

- rerun apply;
- fix-forward;
- rollback;
- import;
- state restore;
- force-unlock;
- ручное AWS change;
- break-glass action.

Теперь нужно доказать, что система вернулась в понятное состояние.

### Зачем нужен post-incident check

После восстановления нужно проверить:

- Terraform снова понимает `state`;
- backend доступен;
- следующий `plan` понятен;
- нет неожиданного `drift`;
- сервис жив;
- ручные изменения либо внесены в код, либо убраны;
- follow-up записан.

### Скрипт

Используй:

```bash
lessons/74-disaster-recovery-and-incident-runbooks/scripts/post-incident-check.sh dev
```

Скрипт делает безопасную проверку, сохраняет post-incident plan и печатает один из статусов:

- `POST_INCIDENT_STATUS=CLEAN`;
- `POST_INCIDENT_STATUS=DRIFT_OR_DIFF`;
- `POST_INCIDENT_STATUS=ERROR`.

Значение plan exit code:

```text
| Exit code | Значение |
| ---: | --- |
| 0 | no diff |
| 1 | error |
| 2 | diff/drift present |
```

Если вернул `CLEAN`

Terraform plan вернул exit code `0`.

Значит:

```text
Plan: 0 to add, 0 to change, 0 to destroy
```

Это хороший сигнал: Terraform config, state и AWS reality совпадают.

Но это ещё не значит, что приложение точно работает. Для этого нужны runtime checks.

Если вернул `DRIFT_OR_DIFF`

Terraform plan вернул exit code `2`.

Это значит: Terraform видит изменения.

Это не всегда плохо. Например:

- ты сделал rollback plan, и он ожидаемо показывает изменения;
- ты ещё не применил fix-forward;
- есть ручное изменение, которое нужно принять в код;
- обычное создание новой инфраструктуры;
- есть drift.

Но это требует решения. Нужно читать сам plan. Нельзя просто закрыть инцидент.

Если вернул `ERROR`

Terraform plan завершился ошибкой.

Это значит, что восстановление не завершено. Нужно разбирать:

- backend access;
- provider auth;
- broken config;
- state issue;
- lock;
- AWS API error.

### Что сохраняет скрипт

```text
terraform-version.txt
git-sha.txt
git-status.txt
post-incident-plan.txt
post-incident-plan-exitcode.txt
post-incident-summary.txt
```

Особенно важны:

```text
post-incident-plan-exitcode.txt
post-incident-summary.txt
```

### Что делать после статуса

Если `CLEAN`

- сохранить доказательства;
- проверить runtime health;
- закрыть incident decision;
- создать follow-up.

Если `DRIFT_OR_DIFF`

- прочитать `post-incident-plan.txt`;
- решить: apply/fix-forward/rollback/import/state repair/no-op;
- не закрывать инцидент без объяснения.

Если `ERROR`

- не закрывать восстановление;
- открыть troubleshooting;
- проверить backend, credentials, config, state, lock.

### Главное правило

```text
Восстановление не завершено, пока не понятны и Terraform-состояние, и runtime health.
```

Terraform может быть clean, но сервис всё равно не работает.  
И наоборот: сервис может работать, но Terraform видит drift.

Нужно понимать оба слоя.

### Runtime health check

После Terraform-level проверки запусти read-only runtime check:

```bash
lessons/74-disaster-recovery-and-incident-runbooks/scripts/runtime-health-check.sh dev
```

Скрипт проверяет:

- ALB Target Group health через `elbv2 describe-target-health`;
- ASG instances через `autoscaling describe-auto-scaling-groups`;
- CloudWatch alarm states для release/safety alarms.

Он не делает `curl` к внутреннему ALB, потому что ALB private и с локальной машины может быть недоступен без SSM port forwarding или VPN. Вместо этого он собирает health-доказательства со стороны AWS.

Статусы:

- `RUNTIME_HEALTH_STATUS=HEALTHY` - targets healthy, критичные alarms не в `ALARM`;
- `RUNTIME_HEALTH_STATUS=WARN` - есть предупреждения, например `INSUFFICIENT_DATA`;
- `RUNTIME_HEALTH_STATUS=UNHEALTHY` - нет healthy targets или есть критичный alarm;
- `RUNTIME_HEALTH_STATUS=ERROR` - не удалось собрать доказательства.

Скрипт сохраняет:

```text
runtime-health-summary.txt
target-health.json
target-health-states.txt
asg.json
asg-instances.txt
cloudwatch-alarms.json
cloudwatch-alarm-states.txt
aws-caller-identity.json
```

---

## 18. Шаблон incident decision

После всех действий восстановления нужен один финальный документ:

```text
incident-decision.md
```

Это запись решения:

- что произошло;
- какое было влияние;
- какие доказательства собрали;
- какие варианты рассматривали;
- что выбрали;
- почему отклонили другие варианты;
- кто approved;
- как проверили результат;
- какие последующие действия создали.

### Генерация шаблона

Используй:

```bash
lessons/74-disaster-recovery-and-incident-runbooks/scripts/incident-decision-template.sh INC-001 dev \
  > /tmp/incident-decision.md
```

Где:

```text
INC-001 = incident ID
dev = environment
```

Скрипт просто печатает Markdown-template. Он ничего не меняет в AWS или Terraform.

### Что внутри шаблона

### Metadata

```text
Incident ID
Environment
Date UTC
Commit SHA
Terraform version
Operator
Reviewer
Severity
Status
```

Это нужно, чтобы через месяц было понятно:
- когда было;
- кто делал;
- против какой версии кода;
- в каком env;
- насколько серьёзно.

### Symptom

Что заметили.

Пример:

```text
Terraform apply failed while updating ASG tags.
```

Или:

```text
Production ALB target group has unhealthy targets after rollout.
```

### Immediate Actions

Что сделали сразу:

```text
Applies frozen
Current state snapshotted
Current plan captured
AWS reality checked
```

### Diagnosis

Что выяснили:

```text
Incident type
Root cause
Affected resources
User impact
```

Здесь важно отделить symptom от root cause.

Пример:
- symptom: apply failed;
- root cause: apply role не имела `autoscaling:CreateOrUpdateTags`.

### Decision

Самая важная часть:

```text
Recovery path
Why this path
Alternatives rejected
Approval
```

Здесь видно, почему выбрали `fix-forward`, `rollback`, `state restore`, `import`, `no-op` и т.д.

### Execution

Точные команды или действия.

Например:

```text
Added missing IAM action to apply role policy.
Ran controlled apply from GitHub Actions.
```

Или:

```text
No force-unlock executed. Lock was active, waited for workflow completion.
```

### Verification

Как доказали, что `recovery` завершён:

```text
Post-incident plan exit code
Drift status
Runtime checks
Rollback needed
```

Теперь у нас есть два слоя:
- `post-incident-check.sh` - Terraform-level доказательства;
- `runtime-health-check.sh` - runtime health доказательства.

### Follow-up

Что сделать, чтобы не повторилось:

```text
Add CI policy check
Update IAM policy test
Improve runbook
Add alert
Add missing validation
```

## Хороший incident decision отвечает на 4 вопроса

```text
What happened?
What did we decide?
Why was that the safest option?
How did we verify recovery?
```

---

## 19. Упражнения

Делай упражнения в `dev`, если не указано другое.

### Упражнение 1. State snapshot

Запусти `scripts/state-snapshot.sh dev` и проверь, что папка snapshot содержит state, plan, Git SHA и summary.

### Упражнение 2. Решение по stuck lock

Сломай real state, но только в **изолированной dev/lab среде**. Напиши decision note: как ты докажешь, что lock stale до `force-unlock`.

Для stuck lock безопаснее симулировать не “поломку”, а **оставшийся lockfile**.

```text
lab74/dev/full/terraform.tfstate.tflock
```

#### Важно

Не делай это, если:

- сейчас работает `GitHub Actions apply`;
- открыт другой `terraform apply/plan`;
- ты не уверен, что это именно `lab74/dev`;
- есть риск перепутать bucket/key.

#### Безопасная симуляция stale lock

#### A. Задай переменные

Из env `dev`:

```bash
BUCKET="$(awk -F\" '/bucket/ {print $2}' backend.hcl)"
STATE_KEY="$(awk -F\" '/key/ {print $2}' backend.hcl)"
LOCK_KEY="${STATE_KEY}.tflock"

echo "$BUCKET"
echo "$STATE_KEY"
echo "$LOCK_KEY"
```

#### B. Убедись, что lock сейчас не существует

```bash
aws s3api head-object \
  --bucket "$BUCKET" \
  --key "$LOCK_KEY"
```

Если получишь `404 Not Found` - lock нет, можно продолжать.

Если объект существует - **стоп**, сначала разбираться.

#### C. Создай fake stale lock

```bash
cat > /tmp/fake-tflock.json <<EOF
{
  "ID": "fake-stale-lock-l74-drill",
  "Operation": "OperationTypeApply",
  "Info": "lesson 74 stale lock drill",
  "Who": "manual-drill",
  "Version": "1.14.4",
  "Created": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "Path": "$STATE_KEY"
}
EOF

aws s3api put-object \
  --bucket "$BUCKET" \
  --key "$LOCK_KEY" \
  --body /tmp/fake-tflock.json \
  --content-type application/json
```

#### D. Проверь, что Terraform видит lock

```bash
terraform plan -input=false -no-color
```

Ожидаемо: Terraform должен упасть с ошибкой про lock.

#### E. Сохрани доказательства

```bash
terraform plan -input=false -no-color > ../../../../evidence/stuck-lock-plan-error.txt 2>&1 || true
cat ../../../../evidence/stuck-lock-plan-error.txt
```

#### F. Удалить fake lock через Terraform force-unlock или S3 delete?

Правильная Terraform recovery-команда:

```bash
terraform force-unlock fake-stale-lock-l74-drill
```

Если Terraform не сможет снять synthetic lock из-за формата, тогда cleanup вручную:

```bash
aws s3api delete-object \
  --bucket "$BUCKET" \
  --key "$LOCK_KEY"
```

#### G. Проверка после cleanup

```bash
terraform plan -detailed-exitcode -input=false -no-color
echo $?
```

### Упражнение 3. Runbook для failed apply

Используй controlled failure или simulated failed apply log. Пройди `runbooks/failed-apply.md` и напиши rollback/fix-forward/no-op decision.

Тут не обязательно реально ломать apply. Лучше сделать **simulated failed apply log** и пройти decision process.

Создай файл доказательства:

```bash
cat > lessons/74-disaster-recovery-and-incident-runbooks/evidence/failed-apply-log.txt <<'EOF'
Terraform apply failed while updating Auto Scaling Group tags.

Error:
AccessDenied: User is not authorized to perform autoscaling:CreateOrUpdateTags
Resource:
module.network.aws_autoscaling_group.web

Observed:
Some resources may already be changed.
State may or may not have been updated.
EOF
```

Цель: научиться не жать повторно `apply`, а пройти recovery flow.

### Упражнение 4. Drift после emergency change

Сделай настоящий безопасный `drift`: поменяй **tag** вручную в AWS, потом посмотри, как Terraform хочет вернуть его обратно.

Цель:
- понять, что manual AWS change создаёт `drift`;
- увидеть это в `terraform plan`;
- решить: откатить ручное изменение или принять его в код.

#### A. ASG в переменную

Сохрани имя ASG в переменную:

```bash
ASG_NAME="$(terraform output -raw web_asg_name)"
echo "$ASG_NAME"
```

#### B. Сделай ручной low-risk drift через tag

Добавим tag только на ASG:

```bash
aws autoscaling create-or-update-tags \
  --tags "ResourceId=${ASG_NAME},ResourceType=auto-scaling-group,Key=ManualDrift,Value=lesson74,PropagateAtLaunch=false"
```

Это безопаснее, чем менять capacity/security/IAM.

#### C. Проверь, что tag появился

```bash
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$ASG_NAME" \
  --query 'AutoScalingGroups[0].Tags[?Key==`ManualDrift`]' \
  --output table
```

#### D. Запусти plan

```bash
EVIDENCE_DIR=../../../../evidence
mkdir -p "$EVIDENCE_DIR"

terraform plan -detailed-exitcode -input=false -no-color > "$EVIDENCE_DIR/drift-after-emergency-plan.txt"
echo $? > "$EVIDENCE_DIR/drift-after-emergency-plan-exitcode.txt"
cat "$EVIDENCE_DIR/drift-after-emergency-plan-exitcode.txt"
```

Ожидаемо:
- exit code `2`;
- plan покажет, что Terraform хочет убрать или изменить tag.

#### E. Создай decision file

```bash
cat > "$EVIDENCE_DIR/drift-after-emergency.md" <<EOF
# Drift After Emergency Change

- Environment: dev
- Resource: ${ASG_NAME}
- Manual change: Added ASG tag ManualDrift=lesson74
- Reason: lesson 74 drift drill
- Plan file: evidence/drift-after-emergency-plan.txt
- Plan exit code: $(cat "$EVIDENCE_DIR/drift-after-emergency-plan-exitcode.txt")

## Diagnosis

Terraform detected manual drift on ASG tags.

## Decision

Selected path: revert manual change in AWS.

Reason:
The manual tag was only a drill. It is not desired Terraform configuration.

Rejected:
- Codify in Terraform, because this tag is not needed.
- Ignore drift, because hidden manual changes should not remain.
- State restore, because state is not corrupted.

## Verification

After deleting the manual tag, run terraform plan again and confirm the drift is gone or only expected changes remain.
EOF
```

#### F. Убери ручной drift

```bash
aws autoscaling delete-tags \
  --tags "ResourceId=${ASG_NAME},ResourceType=auto-scaling-group,Key=ManualDrift"
```

#### G. Проверка после cleanup

```bash
terraform plan -detailed-exitcode -input=false -no-color > "$EVIDENCE_DIR/drift-after-emergency-post-cleanup-plan.txt"
echo $? > "$EVIDENCE_DIR/drift-after-emergency-post-cleanup-exitcode.txt"
cat "$EVIDENCE_DIR/drift-after-emergency-post-cleanup-exitcode.txt"
```

Если `0` — clean.  
Если `2` — есть ещё diff, читаем plan.  
Если `1` — ошибка.

### Упражнение 5. S3 state versions

Выведи версии для `lab74/dev/full/terraform.tfstate`. Cделай restore, если специально тренируешь recovery в изолированной lab.

Минимальная команда `restore` выглядит так:

```bash
aws s3api copy-object \
  --bucket "$BUCKET" \
  --copy-source "${BUCKET}/${STATE_KEY}?versionId=${VERSION_ID}" \
  --key "$STATE_KEY"
```

Но правильная дисциплина всё равно такая:

1. Перед restore сохранить current latest `VersionId`.
2. Сохранить state `snapshot`.
3. Скачать candidate `state`.
4. Сделать restore candidate.
5. Сразу `terraform plan -detailed-exitcode`.
6. Если plan странный - restore обратно исходный latest `VersionId`.
7. Сохранить оба `VersionId` в доказательства.

### Упражнение 6. Rollback vs fix-forward

Возьми bad `module release` и напиши, почему `rollback` или `fix-forward` безопаснее.

Используй сценарий:

```text
Scenario:
A module release changed the ALB target group health check threshold too aggressively.
Targets became unhealthy during rollout.

Bad change:
health_check_healthy_threshold was changed in a way that caused unstable rollout behavior.

User impact:
dev only / no production impact.

Rollback option:
Return to previous module version or previous health check values.

Fix-forward option:
Patch health check settings to safer values and apply controlled change.

Decision:
fix-forward or rollback, depending on which plan is smaller and safer.
```

Как выбрать:

`Rollback` лучше, если
- предыдущая версия точно known-good;
- rollback plan маленький;
- не будет destroy/replace важных ресурсов;
- `state` и `AWS reality` понятны.

`Fix-forward` лучше, если
- проблема понятна и чинится одной настройкой;
- rollback тронет больше ресурсов;
- старая версия небезопасна;
- уже есть emergency/manual change, который стабилизировал сервис.

### Упражнение 7. Break-glass evidence

Симулируй только документацию: кто, что, когда, почему normal path был недостаточен, как Terraform control будет восстановлен.

### Упражнение 8. Recovery game day

В изолированной `dev` lab симулируй один безопасный сценарий:

- failed apply;
- manual tag drift;
- unexpected plan diff;
- stale lock scenario.

Для сценария собери:

- snapshot;
- diagnosis;
- decision;
- путь восстановления;
- post-check;
- incident record.

---

## 20. Разбор проблем

| Симптом | Вероятная причина | Что делать |
| --- | --- | --- |
| `terraform state pull` падает | backend не инициализирован или нет credentials | сначала сделай init и проверь AWS auth |
| plan exits `2` после incident | drift или remaining diff | классифицируй как expected или unexpected |
| plan exits `1` | provider/backend/config error | сначала исправь tooling, потом recovery action |
| S3 versions не видны | versioning disabled или wrong key | проверь bucket/key и bootstrap settings |
| lock error повторяется | active run still exists или stale lock не очищен | проверь active runs до force-unlock |
| state restore выглядит заманчиво | rollback config путают с восстановлением state | делай restore state только когда проблема именно в state |
| break-glass action не задокументирован | при incident response пропустили доказательства | запиши record до закрытия incident |

---

## 21. Критерии успеха

Урок 74 завершён, если:

- scripts существуют и проходят syntax checks;
- runbooks существуют и совпадают с flow урока;
- module tests проходят;
- inherited policy tests проходят;
- завершены минимум четыре упражнения;
- proof-pack собран;
- можешь объяснить, когда не использовать `force-unlock`, `state push` и S3 state restore.

---

## 22. Итоги урока

- **Что изучил:** Terraform disaster recovery — это контролируемый операционный процесс.
- **Что практиковал:** state snapshots, lock reasoning, S3 version recovery model, failed apply triage, break-glass evidence.
- **Операционный фокус:** freeze, snapshot, diagnose, decide, execute, verify, document.
- **Почему это важно:** рано или поздно что-то сломается.
