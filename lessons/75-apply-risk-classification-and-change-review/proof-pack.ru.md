# Пакет доказательств урока 75

Сохраняй доказательства в локальной папке, которая игнорируется Git, например:

```text
lessons/75-apply-risk-classification-and-change-review/evidence/l75-risk-review/
```

Не коммить raw state files, account IDs, внутренние DNS-имена, credentials, tokens, emails или incident screenshots с чувствительными значениями.

---

## 1. Доказательства тестов risk classifier

Сохрани вывод:

```bash
lessons/75-apply-risk-classification-and-change-review/policies/test-risk-classifier.sh
```

Ожидаемый результат:

```text
risk classifier tests passed
```

---

## 2. Доказательства low-risk dev

Сохрани:

```text
low-risk-dev-risk-decision.json
low-risk-dev-risk-decision.md
```

Должно быть видно:

- target env `dev`;
- risk `LOW`;
- approval required `true`;
- approval level `standard`;
- apply allowed `true`.

---

## 3. Доказательства no-change

Сохрани:

```text
no-change-risk-decision.json
no-change-risk-decision.md
```

Должно быть видно:

- risk `NO_CHANGE`;
- approval required `false`;
- approval level `none`;
- reason code `no_managed_resource_changes`.

---

## 4. Доказательства medium-risk stage

Сохрани:

```text
medium-risk-stage-risk-decision.json
medium-risk-stage-risk-decision.md
promotion-evidence-stage.json
```

Должно быть видно:

- target env `stage`;
- promotion evidence есть;
- promotion valid `true`;
- warning signal есть;
- risk `MEDIUM`.

---

## 5. Доказательства high-risk prod

Сохрани:

```text
high-risk-prod-risk-decision.json
high-risk-prod-risk-decision.md
promotion-evidence-prod.json
```

Должно быть видно:

- target env `prod`;
- promotion evidence есть;
- promotion valid `true`;
- risk `HIGH`;
- approval required `true`;
- нужен более строгий approval.

---

## 6. Доказательства blocked change

Сохрани:

```text
blocked-public-ingress-risk-decision.json
blocked-public-ingress-risk-decision.md
```

Должно быть видно:

- risk `BLOCKED`;
- apply allowed `false`;
- reason code содержит policy/cost deny.

---

## 7. Доказательства fail-closed

Сохрани:

```text
fail-closed-missing-outputs-risk-decision.json
fail-closed-missing-outputs-risk-decision.md
```

Должно быть видно:

- risk `BLOCKED`;
- apply allowed `false`;
- reason codes содержат `policy_deny_missing`, `policy_warn_missing`, `cost_deny_missing`, `cost_warn_missing`.

---

## 8. Доказательства emergency

Сохрани:

```text
emergency-risk-decision.json
emergency-risk-decision.md
incident-record.md
```

Должно быть видно:

- `INCIDENT_MODE=true`;
- `INCIDENT_RECORD_FILE` был передан;
- risk `EMERGENCY`;
- approval level `incident_commander_and_break_glass`;
- incident/break-glass record приложен.

---

## 9. Доказательства missing incident record

Сохрани:

```text
missing-incident-record-risk-decision.json
missing-incident-record-risk-decision.md
```

Должно быть видно:

- `INCIDENT_MODE=true`;
- incident record required `true`;
- incident record present `false`;
- risk `BLOCKED`.

---

## 10. Доказательства missing promotion evidence

Сохрани:

```text
missing-promotion-evidence-risk-decision.json
missing-promotion-evidence-risk-decision.md
```

Должно быть видно:

- target env `stage` или `prod`;
- promotion required `true`;
- promotion present `false`;
- risk `BLOCKED`.

---

## 11. Доказательства invalid promotion evidence

Сохрани:

```text
invalid-promotion-evidence-risk-decision.json
invalid-promotion-evidence-risk-decision.md
```

Должно быть видно:

- promotion required `true`;
- promotion present `true`;
- promotion valid `false`;
- risk `BLOCKED`;
- reason codes показывают конкретную проблему: mismatch `release_id`/`source_env`, status не `passed` или неверный `commit_sha`.

---

## 12. Reviewer note

Создай:

```text
reviewer-note.md
```

Шаблон:

```markdown
# Change Review

- Commit SHA:
- Target environment:
- Release ID:
- Source environment:
- Risk level:
- Approval required:
- Approval level:
- Reason codes:
- Main reasons:
- Security policy result:
- Cost policy result:
- Promotion evidence:
- Incident mode:
- Approval decision:
- Reviewer:
```

---

## 13. Доказательства real plan workflow

Если запускал `.github/workflows/lesson75-real-plan-risk-review.yml`, сохрани artifact:

```text
lesson75-<env>-real-plan-risk-review
```

Внутри должны быть:

```text
tfplan
tfplan.sha256
tfplan.txt
tfplan.json
plan.txt
policy-results/
cost-policy-results/
risk-results/
```

Проверь:

- `tfplan.json` создан из реального `terraform show -json tfplan`, а не из fixture;
- `policy-results/policy-decision.txt` существует;
- `cost-policy-results/cost-decision.txt` существует;
- `risk-results/risk-decision.json` существует;
- `risk-results/risk-decision.md` читается человеком;
- GitHub summary показывает `target_env`, backend key, policy decision, cost decision и risk.

Не коммить raw artifact без redaction: `tfplan.json` и `tfplan.txt` могут раскрывать operational metadata.
