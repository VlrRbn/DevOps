# Runbook: Rollback vs Fix-Forward

## Rollback

Используй когда:

- есть предыдущая known-good версия;
- rollback plan безопасен;
- state/resource addresses всё ещё совпадают;
- откат снижает риск.

## Fix-Forward

Используй когда:

- rollback заменит или удалит больше ресурсов;
- плохое изменение уже частично применилось;
- маленький patch безопаснее;
- dependency graph уже ушёл вперёд.

## State Restore

Используй когда:

- сам Terraform state неверный;
- remote state был повреждён или перезаписан;
- обычный rollback не решает проблему ownership в state.

## Break-Glass

Используй когда:

- есть активный user impact;
- normal automation заблокирована;
- задержка опаснее контролируемого ручного действия.

## Decision Table

| Вопрос | Rollback | Fix-forward | State restore | Break-glass |
| --- | --- | --- | --- | --- |
| State corrupt? | no | no | yes | maybe |
| Previous version known-good? | yes | maybe | maybe | no |
| Prod actively degraded? | maybe | yes | maybe | yes |
| Automation working? | yes | yes | maybe | no |
| Manual AWS action needed now? | no | maybe | maybe | yes |

## Правило

Rollback не является автоматически более безопасным. Его нужно спланировать, проверить на review и подтвердить проверками.
