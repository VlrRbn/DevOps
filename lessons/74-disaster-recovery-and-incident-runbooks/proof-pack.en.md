# Lesson 74 Proof Pack

Store evidence in an ignored local folder, for example:

```text
lessons/74-disaster-recovery-and-incident-runbooks/evidence/l74-recovery/
```

Do not commit raw state files, account IDs, internal DNS names, credentials, tokens, emails, or incident screenshots with sensitive values.

---

## 1. State Snapshot Evidence

Save output from:

```bash
lessons/74-disaster-recovery-and-incident-runbooks/scripts/state-snapshot.sh dev
```

Minimum files:

```text
terraform-version.txt
git-sha.txt
git-status.txt
terraform-state-pull.json
terraform-state-pull-stderr.txt
terraform-state-pull-exitcode.txt
current-plan.txt
current-plan-exitcode.txt
snapshot-summary.txt
```

Redact or do not commit `terraform-state-pull.json`. Treat the whole snapshot folder as sensitive operational evidence.

---

## 2. State Version Evidence

Save:

```text
state-versions-dev.txt
```

The note must identify:

- bucket name redacted if needed;
- state key;
- latest version;
- candidate previous versions;
- whether restore was performed: yes/no.

Normal lesson evidence should show `restore performed: no` unless you are working in an isolated recovery lab.

---

## 3. Failed Apply Decision

Save:

```text
failed-apply-decision.md
```

Include:

- failed command/log location;
- snapshot folder;
- next plan summary;
- chosen path: rerun / fix-forward / rollback / state surgery / no-op;
- reviewer.

---

## 4. Stuck Lock Decision

Save:

```text
stuck-lock-decision.md
```

Include:

- lock ID if available;
- active run checks;
- why lock is active or stale;
- whether `force-unlock` was used;
- approval.

---

## 5. Drift After Emergency Change

Save:

```text
drift-after-emergency.md
```

Include:

- manual change record;
- drift plan exit code;
- recovery path;
- verification result.

---

## 6. Rollback vs Fix-Forward Decision

Save:

```text
rollback-vs-fix-forward.md
```

Include:

- scenario;
- rollback plan risk;
- fix-forward plan risk;
- final decision;
- why alternatives were rejected.

---

## 7. Break-Glass Record

Save:

```text
break-glass-record.md
```

Include:

- what happened;
- who acted;
- when;
- why normal path was not enough;
- exact action taken;
- how Terraform control was restored;
- follow-up.

---

## 8. Post-Incident Verification

Save output from:

```bash
lessons/74-disaster-recovery-and-incident-runbooks/scripts/post-incident-check.sh dev
```

Minimum files:

```text
post-incident-plan.txt
post-incident-plan-exitcode.txt
post-incident-summary.txt
```

---

## 9. Runtime Health Verification

Save output from:

```bash
lessons/74-disaster-recovery-and-incident-runbooks/scripts/runtime-health-check.sh dev
```

Minimum files:

```text
runtime-health-summary.txt
target-health.json
target-health-states.txt
asg.json
asg-instances.txt
cloudwatch-alarms.json
cloudwatch-alarm-states.txt
```

If the status is `WARN`, `UNHEALTHY`, or `ERROR`, add a short explanation:

- what is not healthy;
- whether this is expected or a new incident symptom;
- what follow-up is needed.

---

## 10. Final Incident Decision

Save:

```text
incident-decision.md
```

You can generate the template with:

```bash
lessons/74-disaster-recovery-and-incident-runbooks/scripts/incident-decision-template.sh INC-001 dev \
  > incident-decision.md
```

The final decision must include recovery exit criteria:

- backend reachable;
- state pull works;
- post-incident plan understood;
- service health verified;
- manual changes reconciled;
- follow-up action created.

---

## 11. Game Day Evidence

If you run the optional game day drill, save:

```text
game-day-scenario.md
game-day-snapshot-path.txt
game-day-post-check.txt
```

The scenario can be simulated or documentation-only if you are not in an isolated recovery lab.
