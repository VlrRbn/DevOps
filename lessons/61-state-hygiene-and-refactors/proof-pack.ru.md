# Proof Pack Для Lesson 61

## Что Это

Proof pack для lesson 61 — это минимальный набор артефактов, который доказывает, что ты сделал state surgery безопасно.

Он должен показывать:

- чистый baseline до refactor
- точную команду или declarative mapping
- before/after evidence по state
- before/after evidence по плану
- финальное operator decision

Raw proof folders обычно лучше держать локально.
Если хочешь положить их в Git, сначала цензурируй sensitive values и коммить только public-safe subset.

## Зачем Это Нужно

1. State refactor очень легко потом перепутать в памяти.
2. Address move потом неочевиден без сохранённого proof.
3. С привычкой к proof работать особенно важно, когда remote state общий и долгоживущий.

## Когда Собирать

Собирай одну proof-папку на каждый drill.

Рекомендуемые drills:

1. rename через `moved`
2. `terraform state mv`
3. `terraform state rm`
4. `terraform import`

## Стандартная Структура

```text
/tmp/l61-proof-YYYYmmdd_HHMMSS/
  state-list-before.txt
  state-list-after.txt
  state-before.json
  state-after.json
  plan-before.txt
  plan-after.txt
  command.txt
  notes.txt
  decision.txt
```

## Стандартный Сбор (готовые команды)

Запускай из:

`lessons/61-state-hygiene-and-refactors/lab_61/terraform/envs`

```bash
STAMP="$(date +%Y%m%d_%H%M%S)"
OUT="/tmp/l61-proof-$STAMP"
mkdir -p "$OUT"

terraform state list | sort > "$OUT/state-list-before.txt"
terraform state pull > "$OUT/state-before.json"
terraform plan -no-color > "$OUT/plan-before.txt"
```

После refactor-команды или import:

```bash
terraform state list | sort > "$OUT/state-list-after.txt"
terraform state pull > "$OUT/state-after.json"
terraform plan -no-color > "$OUT/plan-after.txt"
```

Зафиксируй саму команду или declarative action:

```bash
cat > "$OUT/command.txt" <<'CMD'
# Example: imperative move
terraform state mv \
  'module.network.aws_cloudwatch_metric_alarm.release_latency' \
  'module.network.aws_cloudwatch_metric_alarm.latency_gate'
CMD
```

Добавь короткие operator notes:

```bash
cat > "$OUT/notes.txt" <<'EOF2'
what=renamed release_latency to latency_gate
why=align alarm labels with gate naming
risk=Terraform could misread it as destroy/create
proof=plan-before showed create/destroy, plan-after returned clean
EOF2
```

Decision file:

```bash
cat > "$OUT/decision.txt" <<EOF3
decision=STATE_SURGERY_OK
timestamp=$(date -Is)
operator=$(whoami)
env=prod
workspace=default

Drill:
Change:
Command:
Why it was safe:
Pre-check:
Post-check:
Risks:
Rollback:
EOF3
```

## Как Выглядит Хороший Proof

### `moved`

- `plan-before.txt` уже должен быть чистым, если `moved` добавлен правильно
- `state-list-after.txt` должен показать новый address

### `terraform state mv`

- `plan-before.txt` должен показать неправильный create/destroy после rename в коде
- `plan-after.txt` должен вернуться к чистому состоянию после `state mv`

### `terraform state rm`

- `state-list-after.txt` больше не должен содержать ресурс
- `plan-after.txt` должен показывать recreation, если block всё ещё остался в коде

### `terraform import`

- `state-list-after.txt` должен содержать импортированный address
- `plan-after.txt` должен быть чистым или полностью понятным

## Упаковка Для Хранения/Передачи (Архивация)

```bash
tar -C /tmp -czf "/tmp/$(basename "$OUT").tar.gz" "$(basename "$OUT")"
echo "saved: /tmp/$(basename "$OUT").tar.gz"
```

## Быстрая Проверка

- baseline plan чистый?
- before/after state list действительно доказывает смену address?
- evidence по plan показывает, зачем вообще была нужна surgery?
- финальный план чистый или явно понятен?
- есть короткая operator note с объяснением change и риска?
