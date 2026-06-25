# Runbook: Drift After Emergency Manual Change

## Сценарий

Кто-то изменил AWS вручную во время инцидента.

## Цель

Вернуть окружение под контроль Terraform.

## Процедура

1. Записать ручное изменение: кто, когда, зачем, точный ресурс.
2. Запустить drift detection или `terraform plan -detailed-exitcode`.
3. Классифицировать изменение: случайный drift, намеренное emergency change или state mismatch.
4. Выбрать recovery path: откатить в AWS, описать в Terraform или сделать import/reconcile.
5. Открыть PR, если config должен измениться.
6. Применить через controlled pipeline.
7. Проверить, что drift clean.

## Правило

Emergency manual change допустим только если позже он reconciled.

## Доказательства

- запись о ручном изменении;
- drift plan;
- выбранный recovery path;
- PR/apply output;
- post-incident check.
