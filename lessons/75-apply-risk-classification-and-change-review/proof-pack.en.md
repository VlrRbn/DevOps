# Lesson 75 Proof Pack

Store evidence in an ignored local folder, for example:

```text
lessons/75-apply-risk-classification-and-change-review/evidence/l75-risk-review/
```

Do not commit raw state files, account IDs, internal DNS names, credentials, tokens, emails, or incident screenshots with sensitive values.

---

## 1. Risk Classifier Test Evidence

Save output from:

```bash
lessons/75-apply-risk-classification-and-change-review/policies/test-risk-classifier.sh
```

Expected result:

```text
risk classifier tests passed
```

---

## 2. Low-Risk Dev Evidence

Save:

```text
low-risk-dev-risk-decision.json
low-risk-dev-risk-decision.md
```

Must show:

- target env `dev`;
- risk `LOW`;
- approval required `true`;
- approval level `standard`;
- apply allowed `true`.

---

## 3. No-Change Evidence

Save:

```text
no-change-risk-decision.json
no-change-risk-decision.md
```

Must show:

- risk `NO_CHANGE`;
- approval required `false`;
- approval level `none`;
- reason code `no_managed_resource_changes`.

---

## 4. Medium-Risk Stage Evidence

Save:

```text
medium-risk-stage-risk-decision.json
medium-risk-stage-risk-decision.md
promotion-evidence-stage.json
```

Must show:

- target env `stage`;
- promotion evidence present;
- promotion valid `true`;
- warning signal present;
- risk `MEDIUM`.

---

## 5. High-Risk Prod Evidence

Save:

```text
high-risk-prod-risk-decision.json
high-risk-prod-risk-decision.md
promotion-evidence-prod.json
```

Must show:

- target env `prod`;
- promotion evidence present;
- promotion valid `true`;
- risk `HIGH`;
- approval required `true`;
- stronger approval required.

---

## 6. Blocked Change Evidence

Save:

```text
blocked-public-ingress-risk-decision.json
blocked-public-ingress-risk-decision.md
```

Must show:

- risk `BLOCKED`;
- apply allowed `false`;
- reason code includes policy/cost deny.

---

## 7. Fail-Closed Evidence

Save:

```text
fail-closed-missing-outputs-risk-decision.json
fail-closed-missing-outputs-risk-decision.md
```

Must show:

- risk `BLOCKED`;
- apply allowed `false`;
- reason codes include `policy_deny_missing`, `policy_warn_missing`, `cost_deny_missing`, `cost_warn_missing`.

---

## 8. Emergency Evidence

Save:

```text
emergency-risk-decision.json
emergency-risk-decision.md
incident-record.md
```

Must show:

- `INCIDENT_MODE=true`;
- `INCIDENT_RECORD_FILE` was provided;
- risk `EMERGENCY`;
- approval level `incident_commander_and_break_glass`;
- incident/break-glass record attached.

---

## 9. Missing Incident Record Evidence

Save:

```text
missing-incident-record-risk-decision.json
missing-incident-record-risk-decision.md
```

Must show:

- `INCIDENT_MODE=true`;
- incident record required `true`;
- incident record present `false`;
- risk `BLOCKED`.

---

## 10. Missing Promotion Evidence

Save:

```text
missing-promotion-evidence-risk-decision.json
missing-promotion-evidence-risk-decision.md
```

Must show:

- target env `stage` or `prod`;
- promotion required `true`;
- promotion present `false`;
- risk `BLOCKED`.

---

## 11. Invalid Promotion Evidence

Save:

```text
invalid-promotion-evidence-risk-decision.json
invalid-promotion-evidence-risk-decision.md
```

Must show:

- promotion required `true`;
- promotion present `true`;
- promotion valid `false`;
- risk `BLOCKED`;
- reason codes identify the specific issue: `release_id`/`source_env` mismatch, status not `passed`, or invalid `commit_sha`.

---

## 12. Reviewer Note

Create:

```text
reviewer-note.md
```

Template:

```markdown
# Change Review

- Commit SHA:
- Target environment:
- Release ID:
- Source environment:
- Risk level:
- Approval required:
- Approval level:
- Reason codes:
- Main reasons:
- Security policy result:
- Cost policy result:
- Promotion evidence:
- Incident mode:
- Approval decision:
- Reviewer:
```

---

## 13. Real Plan Workflow Evidence

If you ran `.github/workflows/lesson75-real-plan-risk-review.yml`, save the artifact:

```text
lesson75-<env>-real-plan-risk-review
```

It should contain:

```text
tfplan
tfplan.sha256
tfplan.txt
tfplan.json
plan.txt
policy-results/
cost-policy-results/
risk-results/
```

Verify:

- `tfplan.json` was created from a real `terraform show -json tfplan`, not from a fixture;
- `policy-results/policy-decision.txt` exists;
- `cost-policy-results/cost-decision.txt` exists;
- `risk-results/risk-decision.json` exists;
- `risk-results/risk-decision.md` is readable for a human reviewer;
- GitHub summary shows `target_env`, backend key, policy decision, cost decision, and risk.

Do not commit raw artifacts without redaction: `tfplan.json` and `tfplan.txt` can expose operational metadata.
