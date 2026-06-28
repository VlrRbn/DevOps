# Runbook: Restore Terraform State From S3 Version

## Использовать только когда

- Current remote state повреждён или перезаписан.
- Previous S3 object version считается known-good.
- Current state уже snapshotted.
- Все applies заморожены.
- Reviewer approved restore.

## Не использовать для

- Обычного application rollback.
- Исправления плохой Terraform configuration.
- Избегания работы с `import`, `moved` или `state mv`.
- Догадок.

## Процедура

1. Заморозить все Terraform workflows.
2. Снять snapshot current state через `terraform state pull`.
3. Вывести список S3 object versions.
4. Найти candidate previous version.
5. Скачать candidate state в local file.
6. Сравнить current vs candidate.
7. Approve restore.
8. Восстановить previous version в current key.
9. Запустить `terraform plan -detailed-exitcode`.
10. Задокументировать решение и verification.

## Скачать Candidate Version

```bash
aws s3api get-object \
  --bucket "$TF_STATE_BUCKET" \
  --key "lab74/dev/full/terraform.tfstate" \
  --version-id "$VERSION_ID" \
  previous-state.json
```

## Восстановить Candidate Version

Эта команда меняет current remote state object. Не запускай её во время обычного прохождения урока. Используй только в изолированной recovery lab или во время approved incident.

```bash
aws s3api copy-object \
  --bucket "$TF_STATE_BUCKET" \
  --copy-source "${TF_STATE_BUCKET}/lab74/dev/full/terraform.tfstate?versionId=${VERSION_ID}" \
  --key "lab74/dev/full/terraform.tfstate"
```

После restore не делай apply сразу. Сначала запусти `terraform plan -detailed-exitcode` и классифицируй любой diff.

## Доказательства

- current state snapshot;
- candidate version ID;
- comparison notes;
- approval;
- post-restore plan.
