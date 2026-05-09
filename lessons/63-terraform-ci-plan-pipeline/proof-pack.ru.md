# Proof Pack Для Lesson 63

## Что Это

Proof pack для lesson 63 — это набор артефактов, который доказывает, что Terraform PR plan pipeline работает и в success path, и в failure path.

Он должен показывать:

- успешный plan run
- хотя бы один ранний failure до `plan`
- evidence загрузки plan artifact
- evidence concurrency cancellation
- короткий operator decision note

## Минимальный Набор Артефактов

Сохрани минимум:

1. `success-plan-run.txt`
2. `fail-validate.txt`
3. `fail-policy.txt`
4. `artifact-list.txt`
5. `concurrency-cancel.txt`
6. `decision.txt`

## Стандартная Структура

```text
/tmp/l63-proof-YYYYmmdd_HHMMSS/
  success-plan-run.txt
  fail-validate.txt
  fail-policy.txt
  artifact-list.txt
  concurrency-cancel.txt
  decision.txt
```

## Что Именно Сохранять

### 1. Успешный plan run

Сохрани:

- фрагмент workflow logs
- job summary
- подтверждение upload artifact

### 2. Failed validate run

Сломай HCL или reference так, чтобы pipeline остановился до `plan`.

Сохрани:

- фрагмент failed workflow log
- точный failing stage

### 3. Failed policy run

Верни один footgun из lesson 62.

Сохрани:

- failed `checkov` или `tflint` output
- stage name, где всё упало

### 4. Concurrency proof

Быстро запушь два коммита в один PR.

Сохрани:

- evidence canceled run
- evidence latest surviving run

## Шаблон Decision File

```text
decision=PR_PLAN_PIPELINE_OK
timestamp=<ISO8601>
operator=<your_name>
repo=<owner/repo>
pr=<number-or-link>

Success case:
Failure case:
Policy case:
Concurrency proof:
Why this matters before merge:
```

## Как Выглядит Хороший Proof

- pipeline доходит до `plan` на healthy PR
- плохой код падает до `plan`
- plan artifacts загружаются и читаются
- concurrency cancellation видно
- оператор может объяснить infrastructure impact
