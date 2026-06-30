# Runbook: восстановление Terraform state из версии S3

## Использовать только когда

- Текущий remote state повреждён или перезаписан.
- Предыдущая версия S3 object считается рабочей.
- Текущий state уже сохранён отдельным snapshot.
- Все Terraform apply заморожены.
- Reviewer подтвердил восстановление.

## Не использовать для

- Обычного rollback приложения.
- Исправления плохой Terraform configuration.
- Избегания работы с `import`, `moved` или `state mv`.
- Догадок.

## Процедура

1. Заморозить все Terraform workflows.
2. Снять snapshot текущего state через `terraform state pull`.
3. Вывести список версий S3 object.
4. Найти предыдущую рабочую версию.
5. Скачать candidate state в локальный файл.
6. Сравнить текущий и candidate state.
7. Получить approval на restore.
8. Восстановить предыдущую версию в текущий key.
9. Запустить `terraform plan -detailed-exitcode`.
10. Задокументировать решение и проверку.

## Скачать Candidate Version

Перед копированием явно задай state key:

```bash
export TF_STATE_KEY="lab76/dev/full/terraform.tfstate"
```

```bash
aws s3api get-object \
  --bucket "$TF_STATE_BUCKET" \
  --key "$TF_STATE_KEY" \
  --version-id "$VERSION_ID" \
  previous-state.json
```

## Восстановить Candidate Version

Эта команда меняет текущий remote state object. Не запускай её во время обычного прохождения урока. Используй только в изолированной recovery lab или во время approved incident.

```bash
aws s3api copy-object \
  --bucket "$TF_STATE_BUCKET" \
  --copy-source "${TF_STATE_BUCKET}/${TF_STATE_KEY}?versionId=${VERSION_ID}" \
  --key "$TF_STATE_KEY"
```

После restore не делай apply сразу. Сначала запусти `terraform plan -detailed-exitcode` и классифицируй любой diff.

## Доказательства

- snapshot текущего state;
- candidate version ID;
- заметки сравнения;
- approval;
- post-restore plan.
