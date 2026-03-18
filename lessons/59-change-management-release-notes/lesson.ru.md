# lesson_59

---

# Change Management & Release Notes (Evidence -> Decision -> Record)

**Date:** 2026-03-18

**Фокус:** превратить артефакты из lesson 58 в стандартный release-note: что поменяли, что наблюдали, почему приняли именно это решение.

**Mindset:** release-note пишется из evidence, а не из памяти.

---

## Зачем Этот Урок

В lesson 58 уже есть стабильный decision flow (`GO` / `HOLD` / `ROLLBACK`) и artifact folders.

В lesson 59 добавляем операционный слой:

- единый формат release-record
- воспроизводимая генерация note
- понятный handoff для ревьюера/тиммейта/on-call

Без этого решения остаются в голове. С этим решения становятся аудируемыми.

---

## Что Должно Получиться

- один `release-note.md`, собранный из evidence lesson 58
- один `release-note.json` для machine-readable handoff
- явная rationale с ссылками на файлы
- одинаковая структура для GO/HOLD/ROLLBACK

---

## Prerequisites

- lesson 58 завершён
- есть хотя бы одна canary-папка артефактов (`l58-canary-...`)
- опционально есть baseline-папка (`l58-baseline-...`)
- локально установлен `jq` (нормальный JSON parsing)

Быстрая проверка:

```bash
command -v jq
```

---

## Структура Урока

```text
lessons/59-change-management-release-notes/
├── lesson.en.md
├── lesson.ru.md
├── README.md
├── templates/
│   └── release-note.template.md
└── scripts/
    └── release-note-gen.sh
```

---

## Input Contract (из Lesson 58)

`release-note-gen.sh` ожидает в artifact-dir файлы:

- `decision.txt`
- `summary.json`
- `load.summary.txt`
- `alarms.json`
- `target-health.json`
- `instance-refreshes.json`
- `build-sampler.txt`

Рекомендуемый источник в репозитории:

- `lessons/58-release-automation-runbook-standardization/evidence/l58-canary-...`

---

## Release Note Contract

В каждом note обязательно:

1. Metadata: timestamp, env, release id, ASG/ALB/TG контекст
2. Change: candidate build, previous build (если есть), зачем меняли
3. Risk: ключевые риски и rollback method
4. Evidence summary:
   - baseline и canary load numbers
   - alarm states
   - target health
   - instance refresh state
5. Decision: `GO` / `HOLD` / `ROLLBACK` + rationale
6. Actions: что делать дальше при этом решении
7. References: какие artifact directories использовались

---

## Скрипт Генерации Release Note

Путь:

- `lessons/59-change-management-release-notes/scripts/release-note-gen.sh`

### Использование

```bash
chmod +x lessons/59-change-management-release-notes/scripts/release-note-gen.sh

# пример на артефактах lesson 58
lessons/59-change-management-release-notes/scripts/release-note-gen.sh \
  --artifact-dir lessons/58-release-automation-runbook-standardization/evidence/l58-canary-20260303_195546 \
  --baseline-dir lessons/58-release-automation-runbook-standardization/evidence/l58-baseline-20260303_194433 \
  --out-dir lessons/59-change-management-release-notes/evidence/l59-20260318_01 \
  --why "Promote candidate after checkpoint canary" \
  --env lab57
```

Вариант для публикации (с редактированием чувствительных данных):

```bash
lessons/59-change-management-release-notes/scripts/release-note-gen.sh \
  --artifact-dir lessons/58-release-automation-runbook-standardization/evidence/l58-canary-20260303_195546 \
  --baseline-dir lessons/58-release-automation-runbook-standardization/evidence/l58-baseline-20260303_194433 \
  --out-dir /tmp/l59-public-note \
  --redact
```

---

## Output Contract

Генератор пишет:

- `release-note.md`
- `release-note.json`

в `--out-dir` (если не задан, пишет в `--artifact-dir`).

---

## Runbook: Что Делать С Note

### Если `decision=GO`

- продолжаем refresh до 100%
- 10 минут мониторим alarms и target health
- прикладываем note в PR/release record

### Если `decision=HOLD`

- держим rollout на checkpoint
- разбираем latency/errors по ссылкам из note
- фиксируем, что именно должно стать нормой для продолжения

### Если `decision=ROLLBACK`

- возвращаем last known good AMI
- делаем apply и проверяем восстановление
- генерируем обновлённый note с меткой rollback completed

---

## Final Acceptance

- [ ] note собран только из artifact files
- [ ] baseline/canary numbers присутствуют
- [ ] alarm states и refresh status присутствуют
- [ ] rationale подтверждается evidence
- [ ] actions явно расписаны для GO/HOLD/ROLLBACK

---

## Pitfalls

- смешивать baseline и canary из разных несвязанных запусков
- писать rationale без ссылок на файлы
- публиковать note без редактирования внутренних ID/ARN
- править note вручную и не регенерировать после новых данных

---

## Security Checklist

- в note нет секретов/токенов
- перед публичным шарингом маскируются account/instance/internal identifiers
- сырые evidence лучше держать локально

---

## Lesson Summary

Lesson 59 делает release-решения проверяемыми.

Теперь цепочка такая:

**Signals (57) -> Automation (58) -> Change Record (59)**

Это базовый операционный стандарт для repeatable change management.
