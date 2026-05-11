# Proof Pack Для Lesson 64

## Что Это

Proof pack для lesson 64 доказывает, что drift workflow умеет отличать clean state, настоящий drift и ошибку pipeline.

Он должен показать:

- baseline `NO_DRIFT`
- deliberate `DRIFT_DETECTED`
- читаемый plan evidence
- triage decision
- возврат к `NO_DRIFT`

## Рекомендуемая Структура

```text
/tmp/l64-proof-YYYYmmdd_HHMMSS/
  baseline-decision.txt
  baseline-plan.txt
  drift-decision.txt
  drift-plan.txt
  drift-tfplan.txt
  fix-decision.txt
  fix-plan.txt
  triage-note.txt
```

## Локальный Шаблон Сбора

Запускай из:

`lessons/64-drift-detection-and-change-awareness/lab_64/terraform/envs`

```bash
STAMP="$(date +%Y%m%d_%H%M%S)"
OUT="/tmp/l64-proof-$STAMP"
mkdir -p "$OUT"

terraform init -reconfigure -backend-config=backend.hcl

set +e
terraform plan -detailed-exitcode -input=false -no-color -out=tfplan > "$OUT/baseline-plan.txt" 2>&1
ec=$?
set -e

if [ "$ec" -eq 0 ]; then
  echo "NO_DRIFT" > "$OUT/baseline-decision.txt"
elif [ "$ec" -eq 2 ]; then
  echo "DRIFT_DETECTED" > "$OUT/baseline-decision.txt"
else
  echo "PIPELINE_ERROR" > "$OUT/baseline-decision.txt"
fi

terraform show -no-color tfplan > "$OUT/baseline-tfplan.txt"
```

После manual drift повтори тот же шаблон и сохрани файлы как `drift-*`.

После revert/codify повтори ещё раз и сохрани файлы как `fix-*`.

## Triage Note Template

```text
decision=DRIFT_TRIAGED
timestamp=<ISO8601>
operator=<your_name>
env=lab64

Drift introduced:
Workflow decision:
Plan evidence:
Triage choice:
Clean-state proof:
```

## Как Выглядит Хороший Proof

- baseline начинается с `NO_DRIFT`
- manual change даёт `DRIFT_DETECTED`
- plan output объясняет diff
- triage note фиксирует revert/codify/import/investigate
- финальный run возвращается в `NO_DRIFT`
