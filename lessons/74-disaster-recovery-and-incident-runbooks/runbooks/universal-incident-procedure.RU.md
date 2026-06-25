# Runbook: Universal Terraform Incident Procedure

## Назначение

Используй этот runbook перед выбором конкретного recovery path: failed apply recovery, stuck lock handling, state restore, state push, drift reconciliation, rollback, fix-forward или break-glass.

Цель - не дать panic actions ухудшить Terraform state, AWS reality или production impact.

## Главное правило

```text
Stop, snapshot, diagnose, decide, execute, verify, document.
```

Не начинай с `apply`, `force-unlock`, `state push`, `state rm`, S3 state restore или ручных AWS changes.

## Universal Flow

1. Заморозить automatic applies для затронутого environment.
2. Определить affected environment и state key.
3. Зафиксировать commit SHA, workflow run URL, operator и time.
4. Сделать state snapshot перед recovery work.
5. Сохранить свежий `terraform plan -detailed-exitcode`.
6. Проверить AWS reality для затронутых ресурсов.
7. Классифицировать incident type и severity.
8. Выбрать один recovery path.
9. Выполнить одно controlled action.
10. Запустить post-incident verification.
11. Сохранить incident decision record.
12. Создать follow-up work, чтобы предотвратить повторение.

## Примеры Severity

| Severity | Example | Recovery posture |
| --- | --- | --- |
| SEV-3 | failed local plan | normal fix path |
| SEV-2 | failed apply in dev/stage | snapshot, diagnose, fix-forward or no-op |
| SEV-1 | production traffic degraded | freeze applies, restore service first |
| SEV-0 | corrupted/wrong state, unsafe lock, bad state restore | stop all applies, require reviewer approval |

SEV-0 связан с опасностью для Terraform control-plane. Это значит, что Terraform может неправильно понимать resource ownership.

## Safety Stop List

Не запускай это без отдельного approval и evidence:

- повторный `terraform apply` без review нового plan;
- `terraform destroy`;
- `terraform force-unlock` без доказательства, что lock stale;
- `terraform state push`;
- `terraform state rm`;
- S3 state object overwrite/delete/restore;
- `-target` как постоянный recovery method;
- production state repair с local machine без peer review.

Если команда меняет remote state или real infrastructure, нужны evidence, approval и post-check.

## Decision Matrix

| Symptom | Likely issue | First safe step | Usually correct path | Avoid first |
| --- | --- | --- | --- | --- |
| Apply failed halfway | partial apply | snapshot + new plan | fix-forward or no-op | rerun apply blindly |
| Lock does not clear | active or stale lock | check active CI/local runs | wait or force-unlock with approval | force-unlock without proof |
| Plan shows unexpected replace | drift/config/state mismatch | compare AWS reality and state | investigate, import, moved block, or config fix | apply immediately |
| State object is corrupted | state corruption | freeze + snapshot + list versions | S3 version restore | state push first |
| Manual console change | drift after emergency | plan + AWS check | revert manual change or codify it | ignore drift |
| Production traffic is broken | service incident | freeze applies + restore service | fix-forward or rollback by impact | state surgery without cause |

## Evidence Checklist

Сохрани или укажи ссылки на:

- incident ID;
- affected environment;
- state key;
- Git commit SHA;
- workflow run URL, если был CI;
- operator и reviewer;
- state snapshot path;
- plan output и exit code;
- AWS reality check notes;
- selected recovery path;
- rejected alternatives;
- approval;
- post-incident plan output;
- service health verification;
- follow-up action.

## Example: Failed Apply

```text
Symptom: apply failed while updating an Auto Scaling Group.
First action: freeze applies and run state-snapshot.sh dev.
Diagnosis: new plan shows the same ASG tag update only.
Decision: fix-forward by allowing the missing IAM action, then rerun controlled apply.
Rejected: state restore, because state is not corrupted.
Verification: post-incident plan is clean or remaining diff is understood.
```

## Example: Stale Lock

```text
Symptom: Terraform reports a lock, but the previous CI job was cancelled.
First action: check GitHub Actions and local terminals for active runs.
Decision: force-unlock only if no active run exists and approval is recorded.
Rejected: immediate force-unlock, because another process may still own the lock.
Verification: plan runs after unlock and no unexpected diff appears.
```

## Example: State Corruption

```text
Symptom: state object was overwritten or restored incorrectly.
First action: freeze all applies and snapshot current state.
Diagnosis: list S3 object versions and compare candidate state files.
Decision: S3 version restore only after reviewer approval.
Rejected: terraform state push first, because it is a last-resort operation.
Verification: terraform plan is understood after restore.
```

## Exit Criteria

Инцидент не закрыт, пока:

- backend reachable;
- `terraform state pull` работает;
- post-incident plan понятен;
- unexpected diffs resolved or accepted;
- service health verified outside Terraform;
- emergency/manual changes reconciled;
- decision record saved;
- follow-up action exists.
