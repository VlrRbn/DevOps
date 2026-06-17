# Lesson 72 Proof Pack

Use this file as the evidence checklist for a module release. Store raw artifacts in an ignored folder such as:

```text
lessons/72-module-versioning-and-release-discipline/evidence/l72-network-v1.1.0/
```

Do not commit raw plans, account-specific ARNs, or internal DNS names unless they are intentionally redacted.

---

## 1. Release Identity

Save:

```bash
git rev-parse HEAD > evidence/l72-network-v1.1.0/release-commit.txt
git show network/v1.0.0 --stat > evidence/l72-network-v1.1.0/tag-network-v1.0.0.txt
git show network/v1.1.0 --stat > evidence/l72-network-v1.1.0/tag-network-v1.1.0.txt
```

Record:

| Field | Value |
| --- | --- |
| Module | `network` |
| Previous version | `network/v1.0.0` |
| New version | `network/v1.1.0` |
| Release type | patch / minor / major |
| Breaking change | yes / no |
| Rollback target | `network/v1.0.0` |

---

## 2. Version Matrix

Before promotion:

| Environment | Module ref | Status |
| --- | --- | --- |
| dev | `network/v1.0.0` | stable |
| stage | `network/v1.0.0` | stable |
| prod | `network/v1.0.0` | stable |

After promotion:

| Environment | Module ref | Evidence |
| --- | --- | --- |
| dev | `network/v1.1.0` | link/file |
| stage | `network/v1.1.0` | link/file |
| prod | `network/v1.1.0` | link/file |

Save as:

```text
evidence/l72-network-v1.1.0/version-matrix.md
```

---

## 3. Local Quality Gates

Capture:

```bash
terraform fmt -check -recursive lessons/72-module-versioning-and-release-discipline/lab_72/terraform \
  > evidence/l72-network-v1.1.0/terraform-fmt.txt 2>&1

packer fmt -check -recursive lessons/72-module-versioning-and-release-discipline/lab_72/packer \
  > evidence/l72-network-v1.1.0/packer-fmt.txt 2>&1

TF_DATA_DIR=/tmp/l72-module-test-data \
terraform -chdir=lessons/72-module-versioning-and-release-discipline/lab_72/terraform/modules/network \
  test -no-color \
  > evidence/l72-network-v1.1.0/terraform-test.txt 2>&1

lessons/72-module-versioning-and-release-discipline/policies/test-policy.sh \
  > evidence/l72-network-v1.1.0/policy-test.txt 2>&1

lessons/72-module-versioning-and-release-discipline/policies/test-opa.sh \
  > evidence/l72-network-v1.1.0/opa-test.txt 2>&1
```

---

## 4. Release Note And Changelog

Generate release note:

```bash
lessons/72-module-versioning-and-release-discipline/scripts/module-release-note.sh \
  network \
  v1.1.0 \
  network/v1.0.0 \
  network/v1.1.0 \
  > evidence/l72-network-v1.1.0/release-note-network-v1.1.0.md
```

Save the matching changelog entry:

```text
evidence/l72-network-v1.1.0/changelog-entry-network-v1.1.0.md
```

The release note must answer:

- patch, minor, or major?
- breaking change: yes/no?
- caller action required?
- rollback target?

---

## 5. Environment Ref Checks

After env roots are pinned to Git refs:

```bash
for env in dev stage prod; do
  lessons/72-module-versioning-and-release-discipline/scripts/check-module-version.sh \
    "lessons/72-module-versioning-and-release-discipline/lab_72/terraform/envs/${env}" \
    "network/v1.1.0" \
    > "evidence/l72-network-v1.1.0/ref-check-${env}.txt" 2>&1
done
```

If an environment intentionally remains on the old version, record that in the version matrix.

---

## 6. Promotion Evidence

For each environment, save one of the following:

- GitHub Actions artifact from the promotion workflow;
- local `terraform plan` output;
- local policy result;
- final decision note.

Suggested files:

```text
dev-upgrade-plan.txt
stage-upgrade-plan.txt
prod-upgrade-plan.txt
dev-policy-result.txt
stage-policy-result.txt
prod-policy-result.txt
```

Promotion order must be visible:

```text
dev -> stage -> prod
```

---

## 7. Rollback Evidence

Save:

```text
rollback-target.txt
rollback-plan.txt
rollback-decision.md
```

`rollback-target.txt` is a manual evidence file that records where the environment can roll back. Include the environment, current version, rollback target, and commit SHA for both tags.

Example content:

```text
Environment: prod
Current module ref: network/v1.1.0
Rollback module ref: network/v1.0.0
Current tag commit: 86763ca
Rollback tag commit: 6eab4fd
Reason: previous known-good module snapshot
Checked at: 2026-06-17T12:00:00+01:00
```

You can generate it like this:

```bash
mkdir -p evidence/l72-network-v1.1.0
{
  echo "Environment: prod"
  echo "Current module ref: network/v1.1.0"
  echo "Rollback module ref: network/v1.0.0"
  echo "Current tag commit: $(git rev-parse network/v1.1.0^{})"
  echo "Rollback tag commit: $(git rev-parse network/v1.0.0^{})"
  echo "Reason: previous known-good module snapshot"
  echo "Checked at: $(date -Iseconds)"
} > evidence/l72-network-v1.1.0/rollback-target.txt
```

`rollback-plan.txt` is the saved `terraform plan` output after temporarily changing the module ref to the rollback target.

`rollback-decision.md` is the manual decision after reviewing the plan.

Minimum rollback note:

```markdown
# Rollback Decision

- Environment:
- Current version:
- Rollback version:
- Reason:
- Plan reviewed: yes/no
- Policy passed: yes/no
- Approved by:
```

---

## 8. Final Decision

Create:

```text
evidence/l72-network-v1.1.0/decision.md
```

Template:

```markdown
# Module Release Decision

- Module: network
- Previous version: network/v1.0.0
- New version: network/v1.1.0
- Version type: patch/minor/major
- Breaking change: yes/no
- Contract tests passed: yes/no
- Policy tests passed: yes/no
- Dev promoted: yes/no
- Stage promoted: yes/no
- Prod promoted: yes/no
- Rollback target: network/v1.0.0
- Decision: GO / HOLD / ROLLBACK
- Notes:
```
