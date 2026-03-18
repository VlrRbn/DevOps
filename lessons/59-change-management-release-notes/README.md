# Lesson 59: Change Management & Release Notes

## Purpose

This lesson extends lesson 58 from decision automation to release documentation.

You already have:

- gate decision (`GO` / `HOLD` / `ROLLBACK`)
- evidence folders with alarms/load/refresh snapshots

Now you add:

- a reproducible release note generator
- a standard note contract for team handoff and auditability

## Prerequisites

- Lesson 58 completed
- at least one canary artifact folder exists
- optional baseline artifact folder exists
- `jq` installed (`command -v jq`)

## Layout

- `lesson.en.md`
  - full lesson flow (EN)
- `lesson.ru.md`
  - full lesson flow (RU)
- `templates/release-note.template.md`
  - standard release note structure
- `scripts/release-note-gen.sh`
  - generator for `release-note.md` + `release-note.json`

## Quick Start

```bash
chmod +x lessons/59-change-management-release-notes/scripts/release-note-gen.sh

lessons/59-change-management-release-notes/scripts/release-note-gen.sh \
  --artifact-dir lessons/58-release-automation-runbook-standardization/evidence/l58-canary-20260303_195546 \
  --baseline-dir lessons/58-release-automation-runbook-standardization/evidence/l58-baseline-20260303_194433 \
  --out-dir lessons/59-change-management-release-notes/evidence/l59-20260318_01 \
  --why "Promote candidate after checkpoint canary" \
  --env lab57
```

## Output Contract

Generator writes to `--out-dir` (or `--artifact-dir` if omitted):

- `release-note.md`
- `release-note.json`

## Redaction Mode

If notes are shared outside your private environment, use:

```bash
--redact
```

This masks common internal identifiers (account ids, instance ids, some internal host markers) in generated outputs.

## Troubleshooting

- `ERROR: missing command: jq`
  - install `jq` and rerun
- `ERROR: required file missing`
  - verify artifact dir really comes from lesson 58 run output
- empty build list
  - check whether `build-sampler.txt` still includes `BUILD_ID:` lines

## Notes

- Prefer generating notes from evidence, not manual edits.
- If evidence changes (new canary run), regenerate note.
- Keep raw evidence local if repository visibility is broad.
