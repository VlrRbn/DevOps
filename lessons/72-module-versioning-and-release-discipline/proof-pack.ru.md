# Пакет доказательств урока 72

Этот файл — чеклист доказательств для релиза модуля. Raw artifacts сохранять в игнорируемой папке, например:

```text
lessons/72-module-versioning-and-release-discipline/evidence/l72-network-v1.1.0/
```

Не коммитить raw plans, account-specific ARNs или internal DNS names, если они специально не отредактированы.

---

## 1. Идентичность релиза

Сохранить:

```bash
git rev-parse HEAD > evidence/l72-network-v1.1.0/release-commit.txt
git show network/v1.0.0 --stat > evidence/l72-network-v1.1.0/tag-network-v1.0.0.txt
git show network/v1.1.0 --stat > evidence/l72-network-v1.1.0/tag-network-v1.1.0.txt
```

Заполнить:

| Поле | Значение |
| --- | --- |
| Module | `network` |
| Previous version | `network/v1.0.0` |
| New version | `network/v1.1.0` |
| Release type | patch / minor / major |
| Breaking change | yes / no |
| Rollback target | `network/v1.0.0` |

---

## 2. Матрица версий

До promotion:

| Environment | Module ref | Status |
| --- | --- | --- |
| dev | `network/v1.0.0` | stable |
| stage | `network/v1.0.0` | stable |
| prod | `network/v1.0.0` | stable |

После promotion:

| Environment | Module ref | Evidence |
| --- | --- | --- |
| dev | `network/v1.1.0` | link/file |
| stage | `network/v1.1.0` | link/file |
| prod | `network/v1.1.0` | link/file |

Сохранить как:

```text
evidence/l72-network-v1.1.0/version-matrix.md
```

---

## 3. Локальные quality gates

Сохранить вывод:

```bash
terraform fmt -check -recursive lessons/72-module-versioning-and-release-discipline/lab_72/terraform \
  > evidence/l72-network-v1.1.0/terraform-fmt.txt 2>&1

packer fmt -check -recursive lessons/72-module-versioning-and-release-discipline/lab_72/packer \
  > evidence/l72-network-v1.1.0/packer-fmt.txt 2>&1

TF_DATA_DIR=/tmp/l72-module-test-data \
terraform -chdir=lessons/72-module-versioning-and-release-discipline/lab_72/terraform/modules/network \
  test -no-color \
  > evidence/l72-network-v1.1.0/terraform-test.txt 2>&1

lessons/72-module-versioning-and-release-discipline/policies/test-policy.sh \
  > evidence/l72-network-v1.1.0/policy-test.txt 2>&1

lessons/72-module-versioning-and-release-discipline/policies/test-opa.sh \
  > evidence/l72-network-v1.1.0/opa-test.txt 2>&1
```

---

## 4. Release note и changelog

Сгенерировать release note:

```bash
lessons/72-module-versioning-and-release-discipline/scripts/module-release-note.sh \
  network \
  v1.1.0 \
  network/v1.0.0 \
  network/v1.1.0 \
  > evidence/l72-network-v1.1.0/release-note-network-v1.1.0.md
```

Сохранить соответствующую запись changelog:

```text
evidence/l72-network-v1.1.0/changelog-entry-network-v1.1.0.md
```

Release note должен отвечать:

- patch, minor или major;
- breaking change: yes/no;
- нужно ли действие от вызывающего кода;
- rollback target.

---

## 5. Проверка env refs

После того как env roots закреплены на Git refs:

```bash
for env in dev stage prod; do
  lessons/72-module-versioning-and-release-discipline/scripts/check-module-version.sh \
    "lessons/72-module-versioning-and-release-discipline/lab_72/terraform/envs/${env}" \
    "network/v1.1.0" \
    > "evidence/l72-network-v1.1.0/ref-check-${env}.txt" 2>&1
done
```

Если окружение специально остаётся на старой версии, зафиксировать это в матрице версий.

---

## 6. Доказательства promotion

Для каждого окружения сохранить один или несколько artifacts:

- GitHub Actions artifact из promotion workflow;
- локальный вывод `terraform plan`;
- локальный результат policy;
- итоговое решение.

Рекомендуемые файлы:

```text
dev-upgrade-plan.txt
stage-upgrade-plan.txt
prod-upgrade-plan.txt
dev-policy-result.txt
stage-policy-result.txt
prod-policy-result.txt
```

Порядок promotion должен быть виден:

```text
dev -> stage -> prod
```

---

## 7. Доказательства rollback

Сохранить:

```text
rollback-target.txt
rollback-plan.txt
rollback-decision.md
```

`rollback-target.txt` — это ручной evidence-файл о том, куда можно откатиться. В него нужно записать окружение, текущую версию, rollback target и commit SHA обоих tags.

Пример содержимого:

```text
Environment: prod
Current module ref: network/v1.1.0
Rollback module ref: network/v1.0.0
Current tag commit: 86763ca
Rollback tag commit: 6eab4fd
Reason: previous known-good module snapshot
Checked at: 2026-06-17T12:00:00+01:00
```

Можно сгенерировать так:

```bash
mkdir -p evidence/l72-network-v1.1.0
{
  echo "Environment: prod"
  echo "Current module ref: network/v1.1.0"
  echo "Rollback module ref: network/v1.0.0"
  echo "Current tag commit: $(git rev-parse network/v1.1.0^{})"
  echo "Rollback tag commit: $(git rev-parse network/v1.0.0^{})"
  echo "Reason: previous known-good module snapshot"
  echo "Checked at: $(date -Iseconds)"
} > evidence/l72-network-v1.1.0/rollback-target.txt
```

`rollback-plan.txt` — это сохранённый вывод `terraform plan` после временной смены module ref на rollback target.

`rollback-decision.md` — это ручное решение после review плана.

Минимальная rollback note:

```markdown
# Решение по rollback

- Environment:
- Current version:
- Rollback version:
- Reason:
- Plan reviewed: yes/no
- Policy passed: yes/no
- Approved by:
```

---

## 8. Финальное решение

Создать:

```text
evidence/l72-network-v1.1.0/decision.md
```

Шаблон:

```markdown
# Решение по релизу модуля

- Module: network
- Previous version: network/v1.0.0
- New version: network/v1.1.0
- Version type: patch/minor/major
- Breaking change: yes/no
- Contract tests passed: yes/no
- Policy tests passed: yes/no
- Dev promoted: yes/no
- Stage promoted: yes/no
- Prod promoted: yes/no
- Rollback target: network/v1.0.0
- Decision: GO / HOLD / ROLLBACK
- Notes:
```
