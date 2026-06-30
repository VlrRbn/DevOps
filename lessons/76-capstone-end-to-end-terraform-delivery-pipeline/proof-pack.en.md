# Lesson 76 Proof Pack

Store evidence in an ignored local folder, for example:

```text
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/evidence/l76-capstone-YYYYmmdd_HHMMSS/
```

Do not commit raw evidence unless it is intentionally redacted. `tfplan.json`, `backend.hcl`, `terraform.auto.tfvars`, and runtime outputs can contain account IDs, ARNs, internal DNS names, IPs, and other operational information.

---

## 1. Metadata

Save:

```text
git-sha.txt
git-status.txt
terraform-version.txt
operator.txt
reviewer.txt
release-id.txt
target-env.txt
```

Must show:

- commit SHA;
- target environment;
- release ID;
- clean or intentionally documented Git status.

---

## 2. Local Checks

Save:

```text
local-checks.txt
```

Command:

```bash
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/scripts/run-local-checks.sh \
  > local-checks.txt 2>&1
```

Must show script/policy checks passed.

---

## 3. Terraform Plan Evidence

Save:

```text
backend.hcl
terraform.auto.tfvars
tfplan
tfplan.txt
tfplan.json
tfplan.sha256
```

Must show:

- plan generated from the target environment root;
- backend key matches the target environment;
- text plan available for reviewer;
- JSON plan available for policy gates.

---

## 4. Policy Evidence

Save:

```text
policy-decision.txt
policy-deny.json
policy-warn.json
cost-decision.txt
cost-deny.json
cost-warn.json
```

Must show:

- security policy decision;
- cost/blast-radius decision;
- deny/warn details if present.

---

## 5. Risk Review Evidence

Save:

```text
risk-decision.json
risk-decision.md
reviewer-note.md
```

Must show:

- risk level;
- `apply_allowed`;
- approval level;
- reason codes;
- reviewer decision.

---

## 6. Promotion Evidence

For `stage`/`prod`, save:

```text
promotion-evidence.json
promotion-manifest.json
source-workflow-run-verification.json
source-workflow-run-url.txt
```

Must show:

- release ID;
- source environment;
- commit SHA;
- source workflow run URL;
- source result passed;
- GitHub API verification confirms a successful source run on the same commit SHA;
- `promotion-manifest.json` confirms matching `release_id`, source environment, successful apply, and clean post-apply drift check.
- for a real production flow, source workflow URL should point to the previous successful run with an apply artifact, not to a synthetic local file.

---

## 7. Apply Evidence

Save:

```text
apply.txt
applied-tfplan-sha256.txt
```

Must show:

- exact saved plan was applied;
- apply completed successfully;
- reviewer-approved plan hash if available.

---

## 8. Post-Apply Verification

Save:

```text
post_apply_plan.txt
post_apply_exitcode.txt
runtime-health-summary.txt
target-health.json
asg.json
cloudwatch-alarms.json
drift-plan.txt
drift-exitcode.txt
```

Must show:

- `post_apply_exitcode.txt` is `0` for clean state;
- runtime health is healthy or documented;
- no unexpected alarms.
- scheduled drift workflow is either clean with exit code `0` or failed with saved drift evidence on exit code `2`.

---

## 9. Incident/Recovery Evidence

If incident mode or recovery was used, save:

```text
incident-record.md
state-snapshot-summary.txt
post-incident-summary.txt
runbook-used.txt
```

Must show:

- incident ID;
- approval;
- chosen recovery path;
- verification after recovery.

---

## 10. Evidence Collection Helpers

Save output from:

```bash
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/scripts/collect-capstone-proof.sh <env>
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/scripts/summarize-capstone.sh <evidence-dir>
```

Must show:

- one timestamped evidence directory;
- `evidence-manifest.txt`;
- `copied-files.txt`;
- generated `capstone-review-summary.md`;
- no raw unreviewed sensitive data committed.

Important: `collect-capstone-proof.sh` collects known files only from lesson/env/evidence locations. It does not search outputs in `/tmp`. If policy/cost/risk outputs were created under `/tmp/l76-*`, copy them into the evidence directory before running `summarize-capstone.sh`.

---
## 11. Final Review Note

Create:

```text
capstone-review-summary.md
```

Template:

```markdown
# Capstone Review Summary

- Commit SHA:
- Target environment:
- Release ID:
- Plan result:
- Security policy:
- Cost policy:
- Risk level:
- Approval level:
- Reviewer:
- Apply result:
- Post-apply drift result:
- Runtime health result:
- Runbooks used:
- Final decision:
```
