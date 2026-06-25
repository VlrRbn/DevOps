# Runbook: Stuck Terraform Lock

## Симптомы

- Terraform сообщает, что state locked.
- Предыдущий CI/local Terraform run упал или был cancelled.
- Lock object остался, но Terraform process больше не должен им владеть.

## Немедленные действия

1. Проверить GitHub Actions на active runs.
2. Проверить local terminals и teammates.
3. Подтвердить, что сейчас никакой apply/plan не использует lock.
4. Записать lock ID и lock metadata.
5. Использовать `terraform force-unlock` только если lock действительно stale.

## Команда

Это настоящая recovery command, а не drill command. Не запускай её, пока проверки выше не завершены и approval не записан.

```bash
terraform force-unlock <LOCK_ID>
```

## Правила безопасности

- Никогда не делай force-unlock, пока другая Terraform command может работать.
- Никогда не делай force-unlock просто из-за нетерпения.
- Запиши, кто approved unlock.
- Запусти plan после unlock.

## Доказательства

- lock error text;
- active run check;
- approval note;
- post-unlock plan output.
