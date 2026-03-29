# lesson_61

---

# State Hygiene & Safe Refactors (`moved`, `state mv`, `state rm`, `import`)

**Date:** 2026-03-22

**Focus:** научиться менять Terraform-структуру без случайного destroy, скрытого drift и путаницы в state.

**Mindset:** lesson 60 сделал state общим и долговечным; lesson 61 учит не ломать его.

---

## Зачем Этот Урок

Когда state становится remote и долгоживущим, Terraform refactor перестаёт быть просто правкой кода.

Ты меняешь уже не только имена файлов и labels, а связь между:

- адресами ресурсов в коде;
- реальными object IDs в AWS;
- Terraform state как source of truth.

Поэтому даже refactor-изменения опасны:

- rename выглядит как destroy + create;
- split into modules выглядит как destroy + create;
- поздний import может скрыть drift;
- `state rm` может отдать ownership наружу.

Этот урок про controlled state surgery.

В этом уроке Terraform state надо воспринимать как карту соответствия между:

- адресом ресурса в Terraform-коде
- реальным AWS-объектом
- записью в state

Пример идеи:

- в коде есть `module.network.aws_cloudwatch_metric_alarm.release_target_5xx`
- в AWS реально существует alarm
- в state Terraform хранит: “вот этот address соответствует вот этому объекту”

---

## Что Должно Получиться

- понимать, когда использовать `moved`, а когда `terraform state mv`
- переименовывать или переносить resource address без пересоздания реального AWS объекта
- осознанно прекращать управление ресурсом через `terraform state rm`
- импортировать существующий AWS объект в Terraform state и разбирать drift
- выстроить повторяемый surgery-workflow: snapshot, lock discipline, proof artifacts

---

## Quick Path

1. Начать с чистого remote-backed env (`terraform plan` -> `No changes`).
2. Снять snapshot текущего state через `terraform state pull`.
3. Сделать один declarative rename через `moved`.
4. Сделать один imperative move через `terraform state mv`.
5. Сделать один detach-сценарий через `terraform state rm`.
6. Импортировать один существующий CloudWatch alarm или security group.
7. Сохранить before/after state list + plan proof.

---

## Prerequisites

- lesson 60 завершён
- remote backend + locking уже активны
- есть один реальный Terraform env, например:
  - `lessons/61-state-hygiene-and-refactors/lab_61/terraform/envs`
- AWS CLI + Terraform настроены
- принимаешь одно правило: никакой state surgery поверх уже грязного плана

---

## Структура Урока

Рекомендуемая рабочая зона:

```text
lessons/61-state-hygiene-and-refactors/
├── lesson.en.md
├── lesson.ru.md
├── proof-pack.en.md
├── proof-pack.ru.md
├── README.md
└── lab_61/
    ├── packer/
    └── terraform/
        ├── backend-bootstrap/
        ├── envs/
        └── modules/network/
```

Используй `lab_61/terraform/envs` как основной env root.

В модуле уже есть стабильные ресурсы, подходящие для упражнений, например:

- `module.network.aws_cloudwatch_metric_alarm.release_target_5xx`
- `module.network.aws_cloudwatch_metric_alarm.release_latency`
- `module.network.aws_cloudwatch_metric_alarm.alb_unhealthy`
- `module.network.aws_security_group.web`
- `module.network.aws_lb_target_group.web`

---

## Иерархия Refactor-Инструментов

Предпочтительный порядок такой:

1. `moved`
   - лучший вариант для обычных refactor-изменений внутри одного state
   - фиксируется в Git
   - воспроизводим для teammates и CI
2. `terraform state mv`
   - подходит для one-off address move и repair-сценариев после изменения кода
   - imperative и сам по себе плохо документирует историю
3. `removed` или `terraform state rm`
   - нужен, когда Terraform должен перестать владеть объектом
4. `terraform import`
   - нужен, когда реальность уже существует, а state должен догнать её

Практическое правило:

- если refactor можно выразить декларативно, выбирай `moved`
- если ты ремонтируешь state руками в моменте, используй `terraform state mv`

---

## Safety Rails (Без Этого Нельзя)

Перед любой surgery-операцией:

1. `terraform plan` должен быть чистым.
2. Locking должен оставаться включённым.
3. Нужно снять snapshot state.
4. Менять нужно по одному адресу за раз.
5. Proof нужно сохранять до и после.

Базовые команды:

```bash
cd lessons/61-state-hygiene-and-refactors/lab_61/terraform/envs

terraform plan
terraform state list | sort > /tmp/l61-state-before.txt
terraform state pull > /tmp/l61-state-before.json
```

Не используй:

```bash
-lock=false
```

Не начинай import/move/rm, если в плане уже висят посторонние diffs.

---

## Surgery Mode Runbook

Используй одну и ту же последовательность каждый раз:

1. Убедись, что план чистый.
2. Сними snapshot state и список текущих address.
3. Сделай минимально возможное изменение в коде.
4. Запусти `terraform plan` и прочитай, что Terraform думает о ситуации.
5. Если план показывает нежелательный destroy/create, исправь mapping через `moved` или `state mv`.
6. Перезапускай plan, пока результат не станет либо:
   - `No changes`, либо
   - одним осознанным и желаемым diff.
7. Сохрани proof artifacts.
8. И только потом делай apply, если нужно.

Этот runbook важнее, чем сами названия команд.

---

## Exercise 1: Declarative Rename Через `moved`

### Цель

Научить Terraform, что address изменился, а реальный объект нет.

Переименуй:

- `module.network.aws_cloudwatch_metric_alarm.release_target_5xx`

в:

- `module.network.aws_cloudwatch_metric_alarm.release_5xx_gate`

### Почему это хороший первый сценарий

- тот же модуль
- тот же state
- тот же resource type
- легко рассуждать
- не должно быть реального infrastructure replacement

### Workflow

1. Переименуй resource block в `modules/network/monitoring.tf`.
2. Добавь `moved`, например в `modules/network/refactors.tf`:

```hcl
moved {
  from = aws_cloudwatch_metric_alarm.release_target_5xx
  to   = aws_cloudwatch_metric_alarm.release_5xx_gate
}
```

3. Запусти:

```bash
terraform plan
```

### Ожидаемый результат

- не destroy/create
- в идеале `0 to add, 0 to change, 0 to destroy`
- address в state меняется, AWS alarm остаётся тем же самым

### Acceptance

- [ ] план чистый после rename
- [ ] имя alarm в AWS не изменилось, если ты не менял это специально в коде
- [ ] можешь объяснить, почему `moved` здесь лучше, чем `state mv`

---

## Exercise 2: Imperative Surgery Через `terraform state mv`

### Цель

Сделать one-off state move там, где нужен прямой ручной контроль.

Переименуй ещё один alarm, но уже через CLI:

- из `module.network.aws_cloudwatch_metric_alarm.release_latency`
- в `module.network.aws_cloudwatch_metric_alarm.latency_gate`

### Workflow

1. Сначала измени resource label в коде.
2. Запусти `terraform plan`.

Terraform предложит create + destroy. Это и есть сигнал, что mapping адресов сломался.

3. Исправь state явно:

```bash
terraform state mv \
  'module.network.aws_cloudwatch_metric_alarm.release_latency' \
  'module.network.aws_cloudwatch_metric_alarm.latency_gate'
```

4. Снова запусти `terraform plan`.

### Ожидаемый результат

- первый план показывает нежелательный create/destroy
- после `state mv` план снова становится чистым

Сейчас **`apply` не нужен**.

Почему:

- `terraform state mv` уже меняет state сразу
- `plan` после этого нужен как проверка, что операция была корректной
- если план чистый, значит repair прошёл успешно

### Когда это правильный инструмент

- ты уже поменял код и хочешь быстро починить state
- нужен one-time move, который не хочется фиксировать навсегда в коде
- ты делаешь controlled operator-led surgery

### Acceptance

- [ ] первый план показал неправильную интерпретацию create/destroy
- [ ] `state mv` исправил mapping адресов
- [ ] второй план чистый

---

## Exercise 3: Detach Ownership Через `terraform state rm`

### Цель

Перестать управлять ресурсом через Terraform без удаления самого AWS объекта.

### Важное отличие

`state rm` **не удаляет** ресурс.
Он только убирает объект из Terraform state.
“Cуществует в облаке” и “управляется Terraform” — это не одно и то же.

### Безопасный паттерн для урока

Используй временный ресурс, например отдельный CloudWatch alarm.

Не используй backend-ресурсы или core networking components.

### Workflow

1. Выбери disposable lesson resource.
2. Удали его только из state:

```bash
terraform state rm module.network.aws_cloudwatch_metric_alarm.latency_gate
```

3. Проверь в AWS, что реальный объект всё ещё существует.
4. Запусти `terraform plan`.

### Ожидаемый результат

Если block всё ещё существует в коде, Terraform теперь захочет создать этот ресурс заново.

Это правильно.

Так видно разницу между:

- реальным AWS объектом
- ownership в Terraform state
- desired configuration в коде

### Acceptance

- [ ] AWS object всё ещё существует после `state rm`
- [ ] Terraform больше не отслеживает его
- [ ] можешь объяснить, почему код тоже нужно убрать или загейтить, если recreation не нужен

---

## Exercise 4: Import Reality В State

### Цель

Подтянуть существующий AWS объект под управление Terraform.

### Хорошие кандидаты для import

- CloudWatch alarm
- security group
- target group

Для этого урока CloudWatch alarm проще всего, потому что address и drift читаются легче.

### Workflow

1. Создай или оставь один существующий объект вне Terraform.
2. Добавь matching resource block в код.
3. Импортируй его:

```bash
terraform import \
  'module.network.aws_cloudwatch_metric_alarm.latency_gate' \
  'lab61-release-latency'
```

Используй правильный import ID format для выбранного AWS resource type.

По Terraform CLI синтаксис такой: `terraform import ADDRESS ID`, и импорт делается по одному ресурсу за раз. Для `aws_cloudwatch_metric_alarm import ID` — это alarm_name.

4. Запусти `terraform plan`.

### Ожидаемый результат

Допустимы два исхода:

- план чистый, значит config совпал с реальностью
- план показывает drift, и ты дальше приводишь config к понятному состоянию

### Acceptance

- [ ] import успешен
- [ ] post-import план чистый или полностью объяснён
- [ ] drift resolution задокументирован в proof artifacts

---

## Drill Pack (Обязательный)

### Drill 1: rename через `moved`

- переименуй один реальный alarm address через `moved`
- докажи, что recreation не произошло

### Drill 2: repair через `state mv`

- переименуй ещё один address
- специально сначала посмотри на неправильный destroy/create plan
- исправь это через `terraform state mv`
- докажи, что план стал чистым

### Drill 3: detach через `state rm`

- detach-ь один disposable object
- докажи, что он всё ещё жив в AWS
- докажи, что Terraform попытается создать его заново, если block останется в коде

### Drill 4: import

- импортируй один существующий объект
- докажи, что post-import план понятен

### Drill 5: full surgery note

Напиши короткую runbook note по одному drill:

- что изменилось
- почему это было безопасно
- что могло пойти не так
- какие evidence доказывают успех

---

## Proof Pack (Обязательные Артефакты)

Минимальный набор для каждой surgery-операции:

- `terraform state list` до
- `terraform state pull` snapshot до
- первый план с неправильной интерпретацией, если он был
- использованная команда (`moved`, `state mv`, `state rm` или `import`)
- второй план с желаемым результатом
- короткое объяснение риска и результата

Храни артефакты по drill-ам, например так:

```text
/tmp/l61-proof-YYYYmmdd_HHMMSS/
  moved-plan-before.txt
  moved-plan-after.txt
  state-list-before.txt
  state-list-after.txt
  state-before.json
  decision.txt
```

Готовый шаблон сбора смотри в `proof-pack.ru.md`.

---

## Частые Ошибки

- делать surgery поверх посторонних pending changes
- забывать, что resource address и AWS object ID это разные вещи
- запускать `state rm`, а потом recreation в следующем плане
- импортировать в неправильный address
- считать imperative state-команды самодокументируемой историей
- пытаться тренироваться на backend-ресурсах вместо обычного стека

---

## Final Acceptance

Урок можно считать закрытым, когда всё это правда:

- [ ] можешь объяснить разницу между `moved` и `terraform state mv`
- [ ] сделал хотя бы один rename без recreation
- [ ] сделал один `state rm` detach и понимаешь риск recreation
- [ ] сделал один import и разобрал drift
- [ ] у каждого drill есть proof artifacts
- [ ] можешь описать repeatable surgery-mode workflow без гадания

---

## Итоги Урока

- **Что изучил:** state это не просто storage, а address map между Terraform-кодом и реальной инфраструктурой.
- **Что практиковал:** `moved`, `terraform state mv`, `terraform state rm`, `terraform import` и clean-plan surgery workflow.
- **Операционный фокус:** сначала snapshot, потом по одному move, после каждого шага новый plan и proof.
- **Почему это важно:** remote state из lesson 60 полезен только тогда, когда умеешь безопасно развивать код.
