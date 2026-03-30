# Proof Pack Для Lesson 62

## Что Это

Proof pack для lesson 62 — это набор артефактов, который доказывает, что quality gates реально ловят плохие изменения до apply.

Он должен показывать:

- baseline clean run
- failing run после deliberate bad change
- clean run после фикса
- короткое explanation, какой инструмент что поймал

## Когда Собирать

Собирай один proof folder на каждый drill или один общий folder с отдельными файлами по drill-ам.

Минимальные drills:

1. public ingress footgun
2. IMDSv2 removed
3. backend bucket protection broken

## Стандартная Структура

```text
/tmp/l62-proof-YYYYmmdd_HHMMSS/
  baseline-fmt.txt
  baseline-validate.txt
  baseline-tflint.txt
  baseline-checkov.txt
  fail-public-sg.txt
  fail-imdsv2.txt
  fail-backend-bucket.txt
  fix-public-sg.txt
  fix-imdsv2.txt
  fix-backend-bucket.txt
  decision.txt
```

## Стандартный Сбор (готовые команды)

Запускай из:

`lessons/62-testing-and-policy/lab_62/terraform`

```bash
STAMP="$(date +%Y%m%d_%H%M%S)"
OUT="/tmp/l62-proof-$STAMP"
mkdir -p "$OUT"

terraform fmt -check -recursive > "$OUT/baseline-fmt.txt" 2>&1
terraform -chdir=envs init -backend=false > /dev/null 2>&1
terraform -chdir=envs validate -no-color > "$OUT/baseline-validate.txt" 2>&1

tflint --chdir=envs --init > /dev/null 2>&1
tflint --chdir=envs -f compact > "$OUT/baseline-tflint.txt" 2>&1

checkov -d . --framework terraform --config-file ../../checkov.yaml > "$OUT/baseline-checkov.txt" 2>&1
```

После каждого deliberate bad change:

```bash
checkov -d . --framework terraform --config-file ../../checkov.yaml > "$OUT/fail-example.txt" 2>&1
```

После возврата good state:

```bash
checkov -d . --framework terraform --config-file ../../checkov.yaml > "$OUT/fix-example.txt" 2>&1
```

Decision file:

```bash
cat > "$OUT/decision.txt" <<EOF2
decision=QUALITY_GATES_OK
timestamp=$(date -Is)
operator=$(whoami)
env=prod
workspace=default

Drill:
Bad change:
Expected catcher:
Why it matters:
State flow: baseline -> fail -> fix -> clean
EOF2
```

## Как Выглядит Хороший Proof

- baseline run clean
- failing run реально падает на deliberate bad change
- fixed run снова clean
- понятно, какой инструмент поймал проблему

## Упаковка Для Хранения/Передачи (Архивация)

```bash
tar -C /tmp -czf "/tmp/$(basename "$OUT").tar.gz" "$(basename "$OUT")"
```

Raw proof folders обычно лучше держать локально.
Если хочешь положить их в Git, сначала цензурируй sensitive values и коммить только public-safe subset.
