# Пакет доказательств урока 76

Сохраняй доказательства в локальной папке, которая игнорируется Git, например:

```text
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/evidence/l76-capstone-YYYYmmdd_HHMMSS/
```

Не коммить сырые доказательства без осознанной редактуры. `tfplan.json`, `backend.hcl`, `terraform.auto.tfvars` и runtime outputs могут содержать account IDs, ARNs, внутренние DNS names, IP-адреса и другую операционную информацию.

---

## 1. Метаданные

Сохрани:

```text
git-sha.txt
git-status.txt
terraform-version.txt
operator.txt
reviewer.txt
release-id.txt
target-env.txt
```

Должно быть видно:

- commit SHA;
- target environment;
- release ID;
- чистый или явно объяснённый Git status.

---

## 2. Локальные проверки

Сохрани:

```text
local-checks.txt
```

Команда:

```bash
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/scripts/run-local-checks.sh \
  > local-checks.txt 2>&1
```

Должно быть видно, что script/policy checks прошли.

---

## 3. Доказательства Terraform plan

Сохрани:

```text
backend.hcl
terraform.auto.tfvars
tfplan
tfplan.txt
tfplan.json
tfplan.sha256
```

Должно быть видно:

- plan создан из root нужного окружения;
- backend key соответствует target environment;
- текстовый plan доступен ревьюеру;
- JSON plan доступен policy gates.

---

## 4. Доказательства policy

Сохрани:

```text
policy-decision.txt
policy-deny.json
policy-warn.json
cost-decision.txt
cost-deny.json
cost-warn.json
```

Должно быть видно:

- решение security policy;
- решение cost/blast-radius policy;
- deny/warn details, если они есть.

---

## 5. Доказательства risk review

Сохрани:

```text
risk-decision.json
risk-decision.md
reviewer-note.md
```

Должно быть видно:

- risk level;
- `apply_allowed`;
- approval level;
- reason codes;
- решение ревьюера.

---

## 6. Доказательства продвижения (promotion)

Для `stage`/`prod` сохрани:

```text
promotion-evidence.json
promotion-manifest.json
source-workflow-run-verification.json
source-workflow-run-url.txt
```

Должно быть видно:

- release ID;
- source environment;
- commit SHA;
- source workflow run URL;
- source result passed;
- GitHub API verification подтверждает successful source run на том же commit SHA;
- `promotion-manifest.json` подтверждает тот же `release_id`, source environment, successful apply и clean post-apply drift check.
- для реального production-flow source workflow URL должен ссылаться на предыдущий successful run с apply artifact, а не на синтетический локальный файл.

---

## 7. Доказательства apply

Сохрани:

```text
apply.txt
applied-tfplan-sha256.txt
```

Должно быть видно:

- применялся exact saved plan;
- apply завершился успешно;
- hash reviewer-approved plan, если доступен.

---

## 8. Доказательства post-apply verification

Сохрани:

```text
post_apply_plan.txt
post_apply_exitcode.txt
runtime-health-summary.txt
target-health.json
asg.json
cloudwatch-alarms.json
drift-plan.txt
drift-exitcode.txt
```

Должно быть видно:

- `post_apply_exitcode.txt` равен `0` для clean state;
- runtime health здоровый или отдельно объяснён;
- нет неожиданных alarms;
- scheduled drift workflow либо clean с exit code `0`, либо failed с сохранёнными drift evidence при exit code `2`.

---

## 9. Доказательства incident/recovery

Если использовался incident mode или recovery, сохрани:

```text
incident-record.md
state-snapshot-summary.txt
post-incident-summary.txt
runbook-used.txt
```

Должно быть видно:

- incident ID;
- approval;
- выбранный recovery path;
- verification после recovery.

---

## 10. Доказательства от collection helpers

Сохрани output от:

```bash
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/scripts/collect-capstone-proof.sh <env>
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/scripts/summarize-capstone.sh <evidence-dir>
```

Должно быть видно:

- одна timestamped evidence directory;
- `evidence-manifest.txt`;
- `copied-files.txt`;
- сгенерированный `capstone-review-summary.md`;
- непроверенные raw sensitive data не добавлены в Git.

Важно: `collect-capstone-proof.sh` собирает только заранее известные файлы из папок урока, env и evidence. Он не ищет outputs в `/tmp`. Если policy/cost/risk outputs были созданы в `/tmp/l76-*`, скопируй их в папку доказательств перед `summarize-capstone.sh`.

---
## 11. Итоговая заметка ревью

Создай:

```text
capstone-review-summary.md
```

Шаблон:

```markdown
# Capstone Review Summary

- Commit SHA:
- Target environment:
- Release ID:
- Plan result:
- Security policy:
- Cost policy:
- Risk level:
- Approval level:
- Reviewer:
- Apply result:
- Post-apply drift result:
- Runtime health result:
- Runbooks used:
- Final decision:
```
