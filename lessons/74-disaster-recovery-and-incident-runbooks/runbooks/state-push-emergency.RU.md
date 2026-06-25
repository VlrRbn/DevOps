# Runbook: Emergency State Pull/Push

## Предупреждение

`terraform state push` - это last-resort операция. Если проблему решают S3 object version restore, `import`, `moved` или `state mv`, используй их вместо `state push`.

## Использовать только если

- Remote state нужно исправить вручную.
- S3 version restore недостаточен.
- Candidate state file был проверен.
- Все workflows заморожены.
- Есть approval.

## Процедура

1. Заморозить Terraform workflows.
2. Снять snapshot текущего state:
   ```bash
   terraform state pull > before.json
   ```
3. Подготовить `candidate.json`.
4. Проверить JSON format.
5. Сравнить `before.json` и `candidate.json`.
6. Провести peer review.
7. Делать push только если он approved. Эта команда перезаписывает remote Terraform state:
   ```bash
   terraform state push candidate.json
   ```
8. Запустить `terraform plan -detailed-exitcode`.
9. Задокументировать всё.

Не используй `terraform state push` для обычного rollback, ошибок configuration или удобной cleanup-операции.

## Доказательства

- location файла `before.json`;
- location candidate state;
- diff/comparison summary;
- approval;
- post-push plan.
