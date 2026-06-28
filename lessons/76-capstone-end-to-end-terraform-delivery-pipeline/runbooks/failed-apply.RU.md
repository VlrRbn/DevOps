# Runbook: Failed Terraform Apply

## Симптомы

- `terraform apply` завершился с non-zero exit code.
- Часть ресурсов уже могла измениться.
- Следующий plan может показать partial work, replacement или drift.

## Немедленные действия

1. Не запускай apply повторно вслепую.
2. Сохрани apply logs.
3. Запусти `scripts/state-snapshot.sh <env>`.
4. Запусти `terraform plan -detailed-exitcode` из затронутого root.
5. Проверь AWS reality для изменённых ресурсов.
6. Выбери fix-forward, rollback, state reconciliation или no-op.

Если следующий plan непонятен, остановись и эскалируй. Второй apply может ухудшить partial failure.

## Вопросы для диагностики

- Terraform упал до изменения ресурсов?
- Он упал после начала create/update/delete?
- State успешно обновился?
- Следующий plan хочет завершить то же изменение?
- Следующий plan содержит неожиданные destructive changes?
- Затронут ли user traffic?

## Варианты recovery

| Вариант | Использовать когда | Избегать когда |
| --- | --- | --- |
| Rerun apply | ошибка была transient и следующий plan ожидаемый | plan непонятный или destructive |
| Fix-forward | маленькое исправление config безопаснее | state повреждён |
| Rollback | предыдущий config/module version known-good | rollback вызывает более широкую замену |
| State surgery | reality правильная, но state mapping неверный | нет snapshot/approval |

## Проверка

- `terraform plan -detailed-exitcode` возвращает `0`, или оставшийся diff явно approved.
- Drift workflow/check clean.
- Runtime health checks проходят.
- Incident decision сохранён.

## Доказательства

- apply log;
- snapshot folder;
- current plan;
- decision note;
- verification output.
