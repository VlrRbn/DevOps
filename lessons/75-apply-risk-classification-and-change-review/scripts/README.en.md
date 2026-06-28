# Lesson 75 Scripts

This folder contains helper scripts for local checks, promotion evidence, and reviewer notes.

These scripts do not run `terraform apply`, `terraform destroy`, AWS API calls, or Terraform state operations.

## Scripts

| Script | Purpose | Changes infrastructure/state? |
|---|---|---|
| `run-local-checks.sh` | Runs safe local checks. | No |
| `promotion-evidence-template.sh` | Generates valid promotion evidence JSON. | No |
| `reviewer-note-template.sh` | Generates a Markdown reviewer note from `risk-decision.json`. | No |

## `run-local-checks.sh`

Run from repo root:

```bash
lessons/75-apply-risk-classification-and-change-review/scripts/run-local-checks.sh
```

Optional checks:

```bash
RUN_OPA=true lessons/75-apply-risk-classification-and-change-review/scripts/run-local-checks.sh
RUN_TERRAFORM=true lessons/75-apply-risk-classification-and-change-review/scripts/run-local-checks.sh
```

`RUN_TERRAFORM=true` may need Terraform provider/plugin access depending on local cache state.

## `promotion-evidence-template.sh`

Generate valid promotion evidence:

```bash
lessons/75-apply-risk-classification-and-change-review/scripts/promotion-evidence-template.sh \
  l75-demo \
  dev \
  "$(git rev-parse HEAD)" \
  > /tmp/promotion-evidence-stage.json
```

## `reviewer-note-template.sh`

Generate a reviewer note from a risk decision:

```bash
lessons/75-apply-risk-classification-and-change-review/scripts/reviewer-note-template.sh \
  lessons/75-apply-risk-classification-and-change-review/evidence/risk-results/risk-decision.json \
  > lessons/75-apply-risk-classification-and-change-review/evidence/reviewer-note.md
```

## Safety Notes

- Generated evidence can contain resource names, ARNs, account IDs, internal DNS names, and operational metadata.
- Do not commit raw evidence unless it is intentionally redacted.
- `evidence/` is ignored by this lesson's `.gitignore`.
