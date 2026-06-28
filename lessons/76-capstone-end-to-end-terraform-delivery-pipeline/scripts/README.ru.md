# Скрипты урока 75

Эта папка содержит вспомогательные скрипты для локальных проверок, promotion evidence и reviewer notes.

Скрипты не запускают `terraform apply`, `terraform destroy`, AWS API calls или операции с Terraform state.

## Скрипты

| Скрипт | Назначение | Меняет инфраструктуру/state? |
|---|---|---|
| `run-local-checks.sh` | Запускает безопасные локальные проверки. | Нет |
| `promotion-evidence-template.sh` | Генерирует валидный JSON promotion evidence. | Нет |
| `reviewer-note-template.sh` | Генерирует Markdown reviewer note из `risk-decision.json`. | Нет |

## `run-local-checks.sh`

Запуск из корня репозитория:

```bash
lessons/75-apply-risk-classification-and-change-review/scripts/run-local-checks.sh
```

Опциональные проверки:

```bash
RUN_OPA=true lessons/75-apply-risk-classification-and-change-review/scripts/run-local-checks.sh
RUN_TERRAFORM=true lessons/75-apply-risk-classification-and-change-review/scripts/run-local-checks.sh
```

`RUN_TERRAFORM=true` может потребовать доступ к Terraform provider/plugin registry, если локальный cache пустой.

## `promotion-evidence-template.sh`

Сгенерировать валидный promotion evidence:

```bash
lessons/75-apply-risk-classification-and-change-review/scripts/promotion-evidence-template.sh \
  l75-demo \
  dev \
  "$(git rev-parse HEAD)" \
  > /tmp/promotion-evidence-stage.json
```

## `reviewer-note-template.sh`

Сгенерировать reviewer note из risk decision:

```bash
lessons/75-apply-risk-classification-and-change-review/scripts/reviewer-note-template.sh \
  lessons/75-apply-risk-classification-and-change-review/evidence/risk-results/risk-decision.json \
  > lessons/75-apply-risk-classification-and-change-review/evidence/reviewer-note.md
```

## Безопасность

- Generated evidence может содержать имена ресурсов, ARNs, account IDs, внутренние DNS-имена и operational metadata.
- Не коммить raw evidence без redaction.
- `evidence/` уже игнорируется `.gitignore` этого урока.
