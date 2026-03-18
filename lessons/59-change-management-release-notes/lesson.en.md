# lesson_59

---

# Change Management & Release Notes (Evidence -> Decision -> Record)

**Date:** 2026-03-18

**Focus:** convert lesson 58 artifacts into a standard release note that explains what changed, what was observed, and why the decision was made.

**Mindset:** no release note from memory; only from evidence.

---

## Why This Lesson Exists

Lesson 58 already gives you a stable decision flow (`GO` / `HOLD` / `ROLLBACK`) and artifact folders.

Lesson 59 adds the missing operational layer:

- consistent release record format
- reproducible note generation
- clear handoff for teammate/reviewer/on-call

Without this, decisions remain personal. With this, decisions become auditable.

---

## Outcomes

- one `release-note.md` generated from lesson 58 evidence
- one `release-note.json` for machine-readable handoff
- explicit decision rationale linked to artifact files
- same structure for every release attempt (GO/HOLD/ROLLBACK)

---

## Prerequisites

- lesson 58 completed
- at least one canary artifact folder exists (for example `l58-canary-...`)
- optional baseline artifact folder exists (`l58-baseline-...`)
- `jq` installed locally (JSON parsing)

Quick check:

```bash
command -v jq
```

---

## Repo Layout

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

## Input Contract (from Lesson 58)

`release-note-gen.sh` expects an artifact folder containing:

- `decision.txt`
- `summary.json`
- `load.summary.txt`
- `alarms.json`
- `target-health.json`
- `instance-refreshes.json`
- `build-sampler.txt`

Recommended source path in this repo:

- `lessons/58-release-automation-runbook-standardization/evidence/l58-canary-...`

---

## Release Note Contract

Every note must contain:

1. Metadata: timestamp, environment, release id, ASG/ALB/TG context
2. Change: candidate build, previous build (if known), why changed
3. Risk: key failure modes and rollback method
4. Evidence summary:
   - baseline and canary load numbers
   - alarm states
   - target health
   - instance refresh state
5. Decision: `GO` / `HOLD` / `ROLLBACK` with rationale
6. Actions: exact next steps for that decision
7. References: artifact directories used for generation

---

## Script: Generate Release Note

Script path:

- `lessons/59-change-management-release-notes/scripts/release-note-gen.sh`

### Usage

```bash
chmod +x lessons/59-change-management-release-notes/scripts/release-note-gen.sh

# example using lesson 58 evidence folders
lessons/59-change-management-release-notes/scripts/release-note-gen.sh \
  --artifact-dir lessons/58-release-automation-runbook-standardization/evidence/l58-canary-20260303_195546 \
  --baseline-dir lessons/58-release-automation-runbook-standardization/evidence/l58-baseline-20260303_194433 \
  --out-dir lessons/59-change-management-release-notes/evidence/l59-20260318_01 \
  --why "Promote candidate after checkpoint canary" \
  --env lab57
```

Public-share variant (redaction enabled):

```bash
lessons/59-change-management-release-notes/scripts/release-note-gen.sh \
  --artifact-dir lessons/58-release-automation-runbook-standardization/evidence/l58-canary-20260303_195546 \
  --baseline-dir lessons/58-release-automation-runbook-standardization/evidence/l58-baseline-20260303_194433 \
  --out-dir /tmp/l59-public-note \
  --redact
```

---

## Output Contract

Generator writes:

- `release-note.md`
- `release-note.json`

in `--out-dir` (defaults to `--artifact-dir` when omitted).

---

## Runbook: What To Do With The Note

### If `decision=GO`

- continue refresh to 100%
- monitor alarms and target health for 10 minutes
- attach note to PR/release record

### If `decision=HOLD`

- keep rollout paused at checkpoint
- investigate latency/errors using artifact references
- document what must be true to resume

### If `decision=ROLLBACK`

- revert AMI input to last known good
- apply and confirm alarm recovery
- generate updated note that includes rollback completion timestamp

---

## Final Acceptance

- [ ] note generated from artifacts only
- [ ] baseline/canary numbers are present
- [ ] alarm states and refresh status are present
- [ ] decision rationale is evidence-based
- [ ] actions are explicit for GO/HOLD/ROLLBACK

---

## Pitfalls

- mixing baseline from one run with canary from another unrelated run
- writing rationale without file references
- publishing note without redacting internal IDs when needed
- changing note manually without regenerating from updated evidence

---

## Security Checklist

- no credentials/tokens in note
- redact account/instance/internal identifiers before public sharing
- keep raw evidence local when repository visibility is broad

---

## Lesson Summary

Lesson 59 makes release decisions reviewable.

Flow now is:

**Signals (57) -> Automation (58) -> Change Record (59)**

This is the minimum operational standard for repeatable change management.
