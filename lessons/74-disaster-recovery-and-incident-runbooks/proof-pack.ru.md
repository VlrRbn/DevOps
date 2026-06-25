# Пакет доказательств урока 74

Сохраняй доказательства в локальной папке, которая игнорируется Git, например:

```text
lessons/74-disaster-recovery-and-incident-runbooks/evidence/l74-recovery/
```

Не коммить raw state files, account IDs, внутренние DNS-имена, credentials, tokens, emails или incident screenshots с чувствительными значениями.

---

## 1. Доказательства state snapshot

Сохрани вывод:

```bash
lessons/74-disaster-recovery-and-incident-runbooks/scripts/state-snapshot.sh dev
```

Минимальные файлы:

```text
terraform-version.txt
git-sha.txt
git-status.txt
terraform-state-pull.json
terraform-state-pull-stderr.txt
terraform-state-pull-exitcode.txt
current-plan.txt
current-plan-exitcode.txt
snapshot-summary.txt
```

`terraform-state-pull.json` нужно отредактировать перед публикацией или не коммитить вообще. Считай всю папку snapshot чувствительными операционными доказательствами.

---

## 2. Доказательства по версиям state

Сохрани:

```text
state-versions-dev.txt
```

В заметке должно быть:

- bucket name, с редактированием если нужно;
- state key;
- latest version;
- предыдущие версии-кандидаты;
- выполнялся ли restore: yes/no.

Для обычного прохождения урока ожидаемо `restore: no`, если ты не тренируешь восстановление в изолированной лаборатории.

---

## 3. Решение после failed apply

Сохрани:

```text
failed-apply-decision.md
```

Укажи:

- где лежит failed command/log;
- папка snapshot;
- краткое summary следующего plan;
- выбранный вариант: rerun / fix-forward / rollback / state surgery / no-op;
- reviewer.

---

## 4. Решение по stuck lock

Сохрани:

```text
stuck-lock-decision.md
```

Укажи:

- lock ID, если есть;
- проверки активных runs;
- почему lock active или stale;
- использовался ли `force-unlock`;
- approval.

---

## 5. Drift после emergency change

Сохрани:

```text
drift-after-emergency.md
```

Укажи:

- запись о ручном изменении;
- drift plan exit code;
- выбранный путь восстановления;
- результат verification.

---

## 6. Решение rollback vs fix-forward

Сохрани:

```text
rollback-vs-fix-forward.md
```

Укажи:

- сценарий;
- rollback plan risk;
- fix-forward plan risk;
- итоговое решение;
- почему отклонили alternatives.

---

## 7. Запись break-glass

Сохрани:

```text
break-glass-record.md
```

Укажи:

- что произошло;
- кто действовал;
- когда;
- почему обычного пути было недостаточно;
- точное выполненное действие;
- как Terraform control восстановлен;
- follow-up.

---

## 8. Проверка после инцидента

Сохрани вывод:

```bash
lessons/74-disaster-recovery-and-incident-runbooks/scripts/post-incident-check.sh dev
```

Минимальные файлы:

```text
post-incident-plan.txt
post-incident-plan-exitcode.txt
post-incident-summary.txt
```

---

## 9. Проверка runtime health

Сохрани вывод:

```bash
lessons/74-disaster-recovery-and-incident-runbooks/scripts/runtime-health-check.sh dev
```

Минимальные файлы:

```text
runtime-health-summary.txt
target-health.json
target-health-states.txt
asg.json
asg-instances.txt
cloudwatch-alarms.json
cloudwatch-alarm-states.txt
```

Если статус `WARN`, `UNHEALTHY` или `ERROR`, добавь короткое объяснение:

- что именно не healthy;
- это ожидаемое состояние или новый симптом инцидента;
- какой follow-up нужен.

---

## 10. Финальное incident decision

Сохрани:

```text
incident-decision.md
```

Шаблон можно сгенерировать так:

```bash
lessons/74-disaster-recovery-and-incident-runbooks/scripts/incident-decision-template.sh INC-001 dev \
  > incident-decision.md
```

Финальное решение должно включать recovery exit criteria:

- backend доступен;
- state pull работает;
- post-incident plan понятен;
- service health проверен;
- ручные изменения согласованы с Terraform;
- последующее действие создано.

---

## 11. Доказательства game day

Если выполняешь game day drill, сохрани:

```text
game-day-scenario.md
game-day-snapshot-path.txt
game-day-post-check.txt
```

Сценарий может быть симулированным или только в формате документации, если ты не в изолированной лаборатории восстановления.
