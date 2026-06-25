# Lesson 74. Disaster Recovery & Terraform Incident Runbooks

**Date:** 2026-06-15

**Focus:** prepare recovery runbooks for failed applies, stuck locks, state recovery, emergency manual changes, and rollback/fix-forward decisions.

**Mindset:** a safe Terraform platform is not finished until you know how to recover when it fails.

---

## 1. Why This Lesson Exists

By lesson 73, the delivery chain already has contracts, tests, promotion, policy gates, controlled apply, least-privilege IAM, and cost controls.

That prevents many incidents, but it does not remove incident response.

Real Terraform incidents still happen:

- `terraform apply` fails halfway through;
- state lock remains stuck after a crashed job;
- S3 state object is overwritten or restored incorrectly;
- emergency AWS console change creates drift;
- rollback is riskier than fix-forward;
- CI cannot apply because IAM, OIDC, or backend access is broken;
- operator may panic and make state worse.

Core rule:

```text
During recovery, do not improvise on state.
- Stop.
- Take a snapshot.
- Diagnose.
- Choose the action.
- Execute one controlled action.
- Verify.
- Document.
```

The biggest mistake in `Terraform recovery`:

* panic-running `apply` / `force-unlock` / `state push` / `restore`

Because Terraform depends on two realities:

* `AWS reality`
* `Terraform state`

If they drift apart, Terraform may start touching something different from what you expect.

---

## 2. Outcomes

After this lesson you should be able to:

- classify Terraform incidents by severity;
- create a state snapshot before recovery work;
- inspect S3 backend object versions;
- reason about stuck locks and `force-unlock`;
- distinguish failed apply, drift, and state corruption;
- use `terraform state pull` and `terraform state push` only under strict controls;
- choose rollback, fix-forward, state restore, import, or break-glass;
- reconcile emergency manual changes back into Terraform;
- produce recovery evidence and a decision record.

---

## 3. Connection To Previous Lessons

| Lesson | What it gave you | What lesson 74 adds |
| --- | --- | --- |
| 60 | S3 remote state and lockfile | state recovery and version discipline |
| 61 | `moved`, `state mv`, `state rm`, `import` | emergency state surgery decision model |
| 64 | drift detection | post-incident reality check |
| 68 | controlled apply | failed apply recovery process |
| 70 | JSON plan policy | reduce known risky plans before incidents |
| 73 | cost/blast-radius controls | financial and operational containment |

Main model:

```text
Prevention is not recovery.
Policy reduces incidents.
Runbooks handle incidents that still happen.
```

---

## 4. Repository Layout

```text
lessons/74-disaster-recovery-and-incident-runbooks/
├── README.md
├── lesson.en.md
├── lesson.ru.md
├── proof-pack.en.md
├── proof-pack.ru.md
├── runbooks/
│   ├── universal-incident-procedure.md
│   ├── failed-apply.md
│   ├── stuck-lock.md
│   ├── state-restore.md
│   ├── state-push-emergency.md
│   ├── drift-after-emergency.md
│   ├── break-glass.md
│   └── rollback-vs-fix-forward.md
├── scripts/
│   ├── README.en.md
│   ├── README.ru.md
│   ├── state-snapshot.sh
│   ├── list-state-versions.sh
│   ├── post-incident-check.sh
│   ├── runtime-health-check.sh
│   └── incident-decision-template.sh
├── policies/
└── lab_74/
```

`lab_74` keeps the same delivery shape as lessons 71-73. The new topic is operational recovery.

Russian runbook versions are stored next to the English files with the `.RU.md` suffix. The `aws-reality-check-cheatsheet.RU.md` file is a Russian AWS CLI cheat sheet for checking what actually exists in AWS during an incident.

---

## 5. Incident Severity Model

| Severity | Meaning | Example | Immediate action |
| --- | --- | --- | --- |
| SEV-3 | low impact | failed local plan | fix normally |
| SEV-2 | env degraded but recoverable | failed apply in dev/stage | snapshot, diagnose, fix-forward |
| SEV-1 | production impact | prod rollout broke traffic | freeze applies, controlled recovery |
| SEV-0 | state/control-plane danger | wrong state, corrupted state, unsafe lock | stop all applies, recover carefully |

State/control-plane incidents are high risk because Terraform may misunderstand ownership. A broken EC2 instance can usually be replaced; broken state can make Terraform target the wrong resources.

---

## 6. Universal Incident Procedure

Every Terraform incident starts the same way:

```text
1. Stop automatic applies.
2. Identify affected environment.
3. Capture commit SHA and current operator context.
4. Snapshot current state.
5. Capture current plan output.
6. Check current AWS reality.
7. Decide rollback / fix-forward / state surgery / break-glass.
8. Execute one controlled action.
9. Verify with post-incident plan or drift check.
10. Write incident record.
```

Do not skip the state snapshot. Snapshot first, diagnosis second.

Safety boundary for this lesson:

```text
Do not practice force-unlock, S3 state restore, or terraform state push on shared/prod state.
Use documentation-only drills unless you are in an isolated recovery lab.
```

### Safety Stop List

During Terraform recovery, do not run these commands without separate approval and evidence:

- rerun `terraform apply` without reading the new plan;
- run `terraform destroy`;
- run `terraform force-unlock` without proving the lock is stale;
- run `terraform state push` without snapshot, comparison, approval, and post-check;
- manually delete or overwrite S3 state objects;
- run `terraform state rm` without a documented ownership decision;
- use `-target` as a permanent recovery method;
- repair production state from a local laptop without peer review.

Rule:

```text
If a command changes remote state or real infrastructure,
it needs evidence, approval, and a post-check.
```

### Recovery Decision Matrix

| Symptom | Likely problem type | First safe step | Usual recovery path | Do not do first |
| --- | --- | --- | --- | --- |
| Apply failed halfway | partial apply | state snapshot + new plan | fix-forward or no-op | rerun apply blindly |
| Lock does not clear | active or stale lock | check active CI/local runs | wait or force-unlock with approval | force-unlock without proof |
| Plan shows unexpected replace | drift/config/state mismatch | compare AWS reality and state | investigate, import, moved block, or config fix | apply immediately |
| State object is corrupted | state corruption | freeze + snapshot + list versions | S3 version restore | state push first |
| Manual console change | drift after emergency | plan + AWS check | revert manual change or codify it | ignore drift |
| Prod traffic is broken | service incident | freeze applies + restore service | fix-forward or rollback by impact | state surgery without cause |

### SEV-0 Approval Model

SEV-0 means Terraform control-plane danger. Solo recovery is not acceptable.

Minimum requirements:

- one operator;
- one reviewer/approver;
- current state snapshot;
- written recovery decision;
- post-recovery verification;
- incident record.

SEV-0 closes only when Terraform again has a correct ownership picture and the next action is understood.

---

## 7. State Snapshot

Use:

```bash
lessons/74-disaster-recovery-and-incident-runbooks/scripts/state-snapshot.sh dev
```

The script captures:

- Terraform version;
- Git SHA;
- Git dirty status;
- `terraform state pull` output;
- current `terraform plan -detailed-exitcode` output;
- a small summary file.

It does not modify infrastructure or state.

Now the key distinction:

```text
state snapshot != S3 previous version
```

`state snapshot`:

- this is the current `terraform state pull`
- it is taken before `recovery`
- it shows what Terraform believes to be true right now
- it is needed as `evidence` and as a comparison point

`S3 previous version`:

- this is an older version of the remote `state object`
- it is stored in S3 if `versioning` is enabled
- it can be used for `restore`
- it is dangerous if you choose the wrong version

Important: a state snapshot can contain secrets, ARNs, IP addresses, DNS names, and the full infrastructure structure. The script writes evidence with private file permissions, but raw snapshots still must not be committed or published without redaction.

---

## 8. S3 Backend Recovery Model

The lab state keys follow this pattern:

```text
lab74/dev/full/terraform.tfstate
lab74/stage/full/terraform.tfstate
lab74/prod/full/terraform.tfstate
```

With S3 versioning enabled, old state objects remain available as previous object versions. That gives you a recovery path if the current state object is accidentally overwritten.

Important rule:

```text
S3 versioning is a recovery tool, not an undo button.
```
Why it is not an undo button:

- it does not roll back AWS resources
- it does not verify whether the old `state` matches the current infrastructure
- it does not know which code `commit` was valid at that point in time
- it can give Terraform an old `ownership map` that no longer matches reality

Before restoring any version:

- freeze applies;
- snapshot current state;
- list candidate versions;
- download and compare candidate state;
- get approval;
- verify with plan after restore.

### Backend Protection Checklist

Before treating a backend as production-ready, verify the controls below.

| Control | Why it matters |
| --- | --- |
| S3 versioning enabled | previous state objects can be recovered |
| S3 public access block | state must never become public |
| SSE-S3 or SSE-KMS | state is encrypted at S3 |
| IAM least privilege | CI roles cannot read/write unrelated state |
| CloudTrail for S3 object events | state reads/writes are auditable |
| retention/lifecycle policy | old versions are not removed too early |
| separate state keys per env | dev/stage/prod cannot overwrite each other |
| restricted break-glass role | emergency access is separate from normal CI |

CloudTrail matters here as the backend audit trail: who read, wrote, deleted, or restored S3 object versions for state, and when it happened. This lesson does not go deep into CloudTrail setup. It is enough to understand that production recovery needs this evidence source when investigating backend activity.

This lesson does not implement every production backend control. It teaches what must be checked before relying on backend recovery.

---

## 9. List State Versions

Use:

```bash
lessons/74-disaster-recovery-and-incident-runbooks/scripts/list-state-versions.sh \
  "$TF_STATE_BUCKET" \
  "lab74/dev/full/terraform.tfstate"
```

What the script does:

- calls `aws s3api list-object-versions`
- shows versions of the `state object`
- does not perform `restore`
- does not copy `state`
- does not delete `state`

Criteria:

- identify the `latest version`
- find previous candidate versions
- understand that listing versions is safe, but `restore` is not

---

## 10. Runbooks

Runbooks are in `runbooks/`. Russian versions are stored next to them with the `.RU.md` suffix.

| Runbook | Purpose |
| --- | --- |
| `universal-incident-procedure.md` | common incident flow before choosing a specific recovery path |
| `failed-apply.md` | failed or partial `terraform apply` recovery |
| `stuck-lock.md` | active vs stale lock decision |
| `state-restore.md` | S3 version restore procedure |
| `state-push-emergency.md` | last-resort `terraform state push` process |
| `drift-after-emergency.md` | Someone changed AWS manually during the incident |
| `break-glass.md` | emergency actions outside normal automation |
| `rollback-vs-fix-forward.md` | choose the least risky recovery path |

A runbook is not a script. It is the decision path you follow before running dangerous commands.

Why is this important?

Without a `runbook`, a person under incident pressure often does the most dangerous thing:

```text
Let's quickly rerun apply
Let's force-unlock
Let's restore the old state
Let's fix it manually in AWS
```

Sometimes this helps. But often it makes the situation worse.

A `runbook` forces you to collect `evidence` first and choose a recovery path.

---

## 11. Failed Apply Recovery

Use `runbooks/failed-apply.md`.

Default behavior:

```text
Do not rerun apply blindly.
```

A failed `apply` can mean:

1. Nothing changed.

   Terraform started `apply`, but the error happened before any changes were made.

   Example:

   * it did not receive credentials
   * it could not acquire the `lock`
   * it failed a `precondition`
   * it could not read the provider

   In this case, the next `plan` may be the same as it was before `apply`.

2. Some resources changed and the `state` was updated.

   Terraform created or changed a resource and managed to write it to `state`, but then failed on another resource.

   Example:

   * it created a Security Group
   * it wrote the SG to `state`
   * it failed on the ALB

   In this case, the next `plan` may simply continue from where Terraform stopped.

3. Some resources changed, but the `state` did not fully converge.

   This is the most unpleasant case.

   Example:

   * the AWS resource was actually created
   * Terraform did not manage to write it to `state`
   * `apply` failed

   In this case, the next `plan` may try to create a duplicate or fail with `AlreadyExists`.

4. The next `plan` wants to finish the same change.

   This may be caused by a timeout or `eventual consistency`.

   Terraform believes one thing, while AWS is already in another state, or the resource is still stabilizing.

5. The next `plan` wants to unexpectedly undo or replace something.

   This is the most important signal: you must not just apply it.

   If, after a failed `apply`, the next `plan` wants to delete or replace important resources, diagnose first.

`Recovery` is based on the next `plan` and the real AWS state, not on panic.

Correct `recovery flow`:

After a failed `apply`:

1. Freeze applies.
2. Save the failed apply log.
3. Run a state snapshot.
4. Run a new `terraform plan`.
5. Check the real resources in AWS.
6. Compare: config, state, real AWS.
7. Choose the recovery path:
   - rerun apply
   - fix-forward
   - rollback
   - import
   - state rm / mv / moved block
   - no-op
8. Get approval if the action is risky.
9. After recovery, run a post-incident check.

When is rerunning `apply` acceptable?

Rerunning `apply` can be acceptable if:

- the error was transient
- the next `plan` is understandable
- there is no unexpected destroy/create
- the `state` looks consistent
- AWS reality matches expectations
- the resource is not critical, or the change is safe

Examples of transient problems:

- AWS API throttling
- temporary timeout
- dependency has not stabilized yet
- provider retry did not wait long enough

When is rerunning `apply` a bad idea?

Do not simply rerun `apply` if:

- the next `plan` is unclear
- there is destroy/create for important resources
- there is `AlreadyExists`
- there is a missing resource in `state`
- the resource was created in AWS but is not in `state`
- `apply` failed on IAM / PassRole / security
- the `lock` / `state` looks suspicious

---

## 12. Stuck Lock Recovery

Terraform `lock` is needed so that only one Terraform process can write to the `state`.

If two processes write to the same `state` at the same time, you can get a corrupted `state` or inconsistent infrastructure.

Use `runbooks/stuck-lock.md`.

And you prove that:

- there is no active `GitHub Actions run`
- there is no local `Terraform process`
- the `lock` is actually `stale`
- there is approval for `force-unlock`

`terraform force-unlock` removes a lock, but it does not prove the lock is stale. Operationally, the dangerous part is unlocking while another Terraform process is active.

What is a `lock`?

When Terraform works with `remote state`, it creates a `lock`.

Meaning:

```text
“I am reading/writing state right now. Other Terraform processes must wait.”
```

While the `lock` is active, a second Terraform process must not write to the same `state`.

What is a `stuck lock`?

A `stuck lock` is a situation where Terraform is no longer running, but the `lock` remains.

For example:

- the runner crashed
- the local terminal disconnected
- the Terraform process died
- there was a network timeout
- the job was cancelled at a bad moment

But important: not every `lock` is stuck.

A `lock` can be **active**:

- a GitHub Actions `apply` is still running
- someone is running `terraform apply` locally
- Terraform is waiting for AWS resource stabilization
- the process is alive, but looks stuck

Why is `force-unlock` dangerous?

The command:

```bash
terraform force-unlock <LOCK_ID>
```

tells Terraform: `remove the lock forcibly`.

It does not check whether another Terraform process is still running. It simply removes the `lock`.

Danger:

```text
process A is still writing state
you run force-unlock
process B starts apply
both processes read/write state
```

Result:

- `state` can become corrupted
- a resource can be created but not recorded in `state`
- a resource can be deleted unexpectedly
- the next `plan` can become strange
- recovery can become harder

Before `force-unlock`, you must prove that the `lock` is stale.

Checks:

1. GitHub Actions:

   - there is no active `apply workflow`
   - there is no queued/running job for this environment

2. Locally:

   - there is no running `terraform` process
   - no other terminal is running `apply`/`plan`

3. Backend:

   - the `lock` has been present longer than expected
   - the `lock owner/session` is inactive

4. Team/approval:

   - someone confirmed that the process is not alive
   - the decision was recorded in the incident decision

Only after that:

```bash
terraform force-unlock <LOCK_ID>
```

What to do after `force-unlock`?

Do not run `apply` automatically immediately after `force-unlock`.

First run:

```bash
terraform plan -detailed-exitcode
```

And check:

- whether there is any strange `destroy`
- whether `drift` appeared
- whether there are partially-created resources left
- whether `state` matches `AWS reality`

Then run the post-incident check and record the evidence.

---

## 13. State Restore and State Push

Use:

- `runbooks/state-restore.md` for S3 object version restore;
- `runbooks/state-push-emergency.md` for last-resort local state push.

A normal config fix is usually safer because Terraform first builds a plan, and you can review which resources will change.

State restore and `terraform state push` are more dangerous because they do not change AWS resources directly. They change Terraform's memory of which resources it owns.

If you provide the wrong state, Terraform can:

- lose track of an existing resource;
- create a duplicate;
- delete or replace the wrong resource;
- manage a resource under the wrong address;
- make drift worse instead of recovering.

That is why state restore, and especially `terraform state push`, require snapshot, comparison, approval, and post-check.

`terraform state push` is intentionally treated as an emergency path. It can overwrite remote state with a local file, so it needs snapshot, comparison, approval, and post-restore plan.

This is the most dangerous `recovery` block in the lesson.

This is not about a normal code rollback. This is about restoring or overwriting `Terraform state`.

### What is an S3 state restore?

This is when you take an older version of the object:

```text
lab74/dev/full/terraform.tfstate
```

from S3 versioning and make it the current version.

In other words, Terraform starts reading an older `state`.

### What is Terraform state push?

This is when you have a local state file and manually upload it to the remote backend:

```bash
terraform state push some-state.json
```

This is even more dangerous, because you directly overwrite the remote `state` with a local file.

### Why is this dangerous?

`Terraform state` is not just a “cache”.

State stores ownership:

```text
Terraform address -> real AWS resource ID
```

Example:

```text
module.network.aws_lb.app -> arn:aws:elasticloadbalancing:...
module.network.aws_instance.proxy -> i-1234567890
module.network.aws_security_group.web -> sg-1234567890
```

If the `state` is wrong, Terraform may think:

- the resource does not exist, even though it does
- the resource exists, even though it does not
- the resource belongs to a different address
- the resource must be deleted and recreated
- the resource must be imported
- the resource must stop being tracked

### Why a config fix is usually better

The normal path:

```text
fix Terraform config
terraform plan
review
terraform apply
```

Advantage: Terraform shows in advance what will change.

`State restore`/`state push` changes the foundation Terraform uses to build the plan. If you choose the wrong `state`, the next `plan` can be dangerous.

### Correct risk order

```text
normal config fix
-> moved/import/state mv
-> S3 version restore
-> terraform state push as last resort
```

### Why this order?

`normal config fix`

- most transparent
- visible in Git
- goes through CI
- can be reviewed

`moved/import/state mv`

- fixes ownership
- often better than rolling back the entire `state`

`S3 version restore`

- changes the whole `state object` to an older version
- may be needed if the current `state` is corrupted or accidentally overwritten

`terraform state push`

- manually overwrites the remote `state` with a local file
- use only as an emergency path

### When can S3 state restore be appropriate?

For example:

- the current `state object` was accidentally overwritten
- the `state` is corrupted
- the `state` lost most of its resources
- the problem is specifically in the backend `state`, not in the Terraform config
- there is a clear previous `state` version
- you compared the candidate `state` with current AWS
- there is approval

### When is S3 state restore a bad idea?

If the problem is in the code:

- wrong input
- bad module release
- wrong AMI
- IAM policy mistake
- incorrect lifecycle
- failed refactor without `moved`

Then restoring the old `state` does not fix the root cause. It is better to fix the config/module.

### When can `terraform state push` be appropriate?

Very rarely.

For example:

- remote `state` is corrupted
- S3 version restore is impossible
- there is a verified local `state snapshot`
- the team understands the consequences
- there is approval
- a mandatory `plan` will be run after the push

If a normal S3 version restore is available, it is usually better than `state push`.

### Mandatory steps

Before `state restore`/`state push`:

1. Freeze applies.
2. Take a current `state snapshot`.
3. Save the list of S3 state versions.
4. Download the candidate `state`.
5. Compare:
   - current `state`
   - candidate `state`
   - Terraform config
   - real AWS resources
6. Record the decision.
7. Get approval.
8. Perform the restore/push.
9. Immediately run `terraform plan`.
10. Save post-incident evidence.

---

## 14. Drift After Emergency Change

Use `runbooks/drift-after-emergency.md`.

Emergency manual change is allowed only when the incident requires it. Afterward, the environment must return to Terraform control.

Scenario: an incident happened, and someone changed AWS manually.

For example:

- opened a Security Group
- increased ASG desired capacity
- changed a listener rule
- replaced a target group
- disabled an alarm
- changed an IAM policy
- manually restarted an instance

This is called an **emergency change** or a **break-glass change** if the change was made outside the normal Terraform/CI process.

After this, `Terraform state` and Terraform config may no longer match real AWS.

That is `drift`.

### Why is drift after an emergency change dangerous?

Because Terraform may later “fix” AWS back to the config.

Example:

During the incident, ASG was manually increased:

```text
desired_capacity: 2 -> 4
```

Terraform config still says:

```hcl
desired_capacity = 2
```

The next `terraform apply` may return the ASG back to `2`.

If the manual change was needed to stabilize the service, Terraform may accidentally remove it.

Another example:

Temporary access was manually opened in a Security Group.

If this is forgotten:

- the security risk remains
- or Terraform later closes the access unexpectedly
- or the team will not understand why behavior differs from the code

### Correct recovery flow

After an emergency AWS change:

1. Record what changed:
   - who
   - when
   - why
   - which resource
   - what old/new value
2. Freeze applies if there is risk.
3. Run `terraform plan -detailed-exitcode`.
4. Check what Terraform wants to revert.
5. Choose the path:
   - accept the change in code
   - roll back the manual change
   - import the resource
   - remove the resource from state
   - perform a controlled fix-forward
6. Verify the result.
7. Add a follow-up so it does not happen again.

### Possible solution — Accept the change in Terraform config

Use this if the manual change became the new desired state.

Example:

- ASG was temporarily increased to 4
- the decision is that it should now stay at 4
- update the Terraform variable/config
- run plan/apply through the normal pipeline

### Possible solution — Roll back the manual change

Use this if the change was temporary.

Example:

- SG was opened for diagnostics
- diagnostics finished
- return SG to the Terraform config
- the plan should become clean

### Import

Use this if a new resource was created manually during the incident and Terraform must now manage it.

```bash
terraform import <address> <real-resource-id>
```

After import, `plan` is mandatory.

`terraform import` only attaches a real AWS resource to a Terraform address in `state`.

It does not prove that the config fully matches that resource.

### State rm

Use this if Terraform should no longer manage the resource.

```bash
terraform state rm <address>
```

Be careful: the resource stays in AWS, but Terraform stops seeing it.

### Fix-forward

Use this if rollback is more dangerous than stabilizing the correct state with a new change.

For example:

- the manual change stabilized the service
- rollback would cause downtime
- it is better to update the Terraform config correctly and go through the pipeline

### Main rule

```text
Manual emergency changes must either become part of Terraform code or be removed.
```

Otherwise, there will be permanent `drift`.

---

## 15. Break-Glass

Use `runbooks/break-glass.md`.

Break-glass is an emergency path outside normal automation. It is valid only when the normal path is unavailable or too slow for active impact.

In Terraform/AWS, this means:

```text
We temporarily bypass the normal CI/IAM/process because waiting for the normal path is riskier.
```

Examples:

- manually close public access
- urgently increase capacity
- temporarily disable a dangerous listener/rule
- revoke a compromised credential
- manually restore access to the backend
- use an emergency role

### When is break-glass needed?

If:

- CI is broken
- GitHub is unavailable
- the OIDC role does not work
- the apply pipeline is stuck
- there is a security incident
- the service is down

then sometimes you need to act manually.

But `break-glass` is dangerous because it creates `drift` and bypasses `guardrails`.

### Correct break-glass model

`Break-glass` must be:

1. rare
2. approved
3. logged
4. time-bound
5. reviewed
6. reconciled back into Terraform

Explanation:

`rare`
- Not the normal deployment method.
- If `break-glass` is needed every week, the process is broken.

`approved`
- Someone must approve the action, even if quickly.

`logged`
- You must record who did what, when, and why.

`time-bound`
- The access or exception must be temporary.

`reviewed`
- After the incident, the team must review what happened.

`reconciled back into Terraform`
- The manual change must either be added to code or removed.

      This can mean one of the following:

      - the manual change was rolled back, and `terraform plan` is clean again
      - the manual change was added to Terraform code, and Terraform now manages it
      - the resource was imported into `state`
      - `state` was corrected through `import` / `moved` / `state rm`, and Terraform correctly understands ownership again
      - after the fix, `terraform plan -detailed-exitcode` shows the expected result, not unexpected `drift`

### What must not be done?

Bad `break-glass`:

```text
“I just logged in as admin and fixed something.”
```

Why this is bad:

- nobody knows what changed
- Terraform may overwrite the change
- the audit trail is incomplete
- the security risk may remain
- the recovery cannot be repeated

### Example of a good `break-glass-record.md`

```markdown
# Break-Glass Record

- Incident ID: INC-001
- Environment: prod
- Severity: SEV-1
- Operator: Valerii
- Approver: On-call lead
- Start UTC: 2026-06-24T12:10:00Z
- End UTC: 2026-06-24T12:25:00Z

## Why normal path was not enough

GitHub Actions apply was blocked by OIDC failure, and production ALB listener rule exposed an unsafe route.

## Action Taken

Temporarily disabled the unsafe listener rule in AWS Console.

## Verification

ALB route no longer reachable. Terraform plan shows drift on listener rule.

## Reconciliation

Terraform config updated and applied through normal pipeline after CI recovery.

## Follow-up

Add policy test for unsafe listener rule.
```

## Main rule

```text
Break-glass is allowed only if doing nothing is riskier than bypassing the normal process.
```

---

## 16. Rollback vs Fix-Forward

Use `runbooks/rollback-vs-fix-forward.md`.

Rollback is not automatically safer.

When something breaks, there are two basic paths:

```text
rollback = go back
fix-forward = fix forward
```

### Rollback

`Rollback` means returning to a previous known-good state.

In Terraform, this can mean:

* restore the previous `module` version
* restore the previous `commit`
* restore old input values
* roll back the AMI
* restore the previous IAM policy
* restore the old ASG desired capacity
* restore the old listener rule

Example:

```bash
git revert <bad_commit>
terraform plan
terraform apply
```

Or with module versioning:

```hcl
source = "git::https://github.com/VlrRbn/DevOps.git//.../modules/network?ref=network/v1.1.0"
```

roll back to:

```hcl
source = "git::https://github.com/VlrRbn/DevOps.git//.../modules/network?ref=network/v1.0.0"
```

### Fix-forward

`Fix-forward` means that you do not return to the old state. Instead, you make a new corrective change.

For example:

* IAM policy is broken → add the missing permission
* ALB health check is wrong → fix the health check
* ASG capacity is too low → increase capacity
* AMI is bad → release a new AMI
* security rule is too broad → add a precise rule

### Why rollback is not always safer

`Rollback` can be dangerous if:

* the current infrastructure has already changed
* `state` has moved forward
* a database migration has already been applied
* a resource was replaced
* a manual emergency change stabilized the service
* rollback would remove new dependencies
* the old version had a security issue
* the old AMI is no longer available

Example:

You deployed a new version, then manually increased ASG capacity so the service could survive.

If you roll back to the old config, Terraform may reduce capacity again and break the service again.

### When rollback is good

`Rollback` is usually good if:

* the change is small
* the previous state is known and safe
* there are no irreversible changes
* `state` and `AWS reality` are clear
* the `plan` shows the expected rollback
* downtime is acceptable or does not exist

### When fix-forward is better

`Fix-forward` is often better if:

* rollback would affect more resources
* the old version is unsafe
* data/migrations have already moved forward
* an emergency change already stabilized the service
* the problem is understood and can be fixed precisely
* rollback creates a larger `blast radius`

### How to decide

Compare two plans:

```text
rollback plan
fix-forward plan
```

And evaluate:

* what will be deleted
* what will be replaced
* what will be changed
* expected downtime
* possible data loss
* security impact
* blast radius
* recovery time
* which path is clearer for the team

### Main rule

```text
Choose the path with the smallest understood risk, not the path that sounds safer.
```

So it is not “rollback is always better” and not “fix-forward is always better”.

You need to choose the path where the risk is understood, limited, and verifiable.

Choose `rollback` when there is a previous known-good config and the rollback plan is safe.

Choose `fix-forward` when a small corrective change is safer than rolling back a partially applied change.

Choose `state restore` only when the problem is specifically in `state`.

---

## 17. Post-Incident Check

This is a check after `recovery`.

That means if you did any of the following:

- rerun apply
- fix-forward
- rollback
- import
- state restore
- force-unlock
- manual AWS change
- break-glass action

Now you need to prove that the system has returned to an understandable state.

### Why a post-incident check is needed

After `recovery`, you need to verify that:

* Terraform understands the `state` again
* the backend is accessible
* the next `plan` is understandable
* there is no unexpected `drift`
* the service is alive
* manual changes were either added to code or removed
* the follow-up was recorded

### Script

Use:

```bash
lessons/74-disaster-recovery-and-incident-runbooks/scripts/post-incident-check.sh dev
```

The script performs a safe check, saves the post-incident plan, and prints one of these statuses:

* `POST_INCIDENT_STATUS=CLEAN`
* `POST_INCIDENT_STATUS=DRIFT_OR_DIFF`
* `POST_INCIDENT_STATUS=ERROR`

Meaning of the plan exit code:

```text
| Exit code | Meaning |
| ---: | --- |
| 0 | no diff |
| 1 | error |
| 2 | diff/drift present |
```

If it returns `CLEAN`

Terraform plan returned exit code `0`.

That means:

```text
Plan: 0 to add, 0 to change, 0 to destroy
```

This is a good signal: Terraform config, state, and AWS reality match.

But it does not prove that the application definitely works. For that, you need runtime checks.

If it returns `DRIFT_OR_DIFF`

Terraform plan returned exit code `2`.

This means Terraform sees changes.

This is not always bad. For example:

* you created a rollback plan, and it expectedly shows changes
* you have not applied the fix-forward yet
* there is a manual change that needs to be accepted into code
* there is drift

But it requires a decision. You must not simply close the incident.

If it returns `ERROR`

Terraform plan failed.

This means recovery is not complete. You need to investigate:

* backend access
* provider auth
* broken config
* state issue
* lock
* AWS API error

### What the script saves

```text
terraform-version.txt
git-sha.txt
git-status.txt
post-incident-plan.txt
post-incident-plan-exitcode.txt
post-incident-summary.txt
```

The most important files are:

```text
post-incident-plan-exitcode.txt
post-incident-summary.txt
```

### What to do after each status

If `CLEAN`:

* save the evidence
* check runtime health
* close the incident decision
* create a follow-up

If `DRIFT_OR_DIFF`:

* read `post-incident-plan.txt`
* decide: apply / fix-forward / rollback / import / state repair / no-op
* do not close the incident without an explanation

If `ERROR`:

* do not close recovery
* open troubleshooting
* check backend, credentials, config, state, and lock

### Main rule

```text
Recovery is not complete until Terraform and runtime health are both understood.
```

Terraform can be clean while the service still does not work.

And the opposite is also possible: the service can work while Terraform still sees drift.

You need to understand both layers.

### Runtime Health Check

After the Terraform-level check, run the read-only runtime check:

```bash
lessons/74-disaster-recovery-and-incident-runbooks/scripts/runtime-health-check.sh dev
```

The script checks:

* ALB Target Group health via `elbv2 describe-target-health`
* ASG instances via `autoscaling describe-auto-scaling-groups`
* CloudWatch alarm states for release/safety alarms

It does not `curl` the internal ALB because the ALB is private and may not be reachable from your local machine without SSM port forwarding or VPN. Instead, it collects AWS-side health evidence.

Statuses:

* `RUNTIME_HEALTH_STATUS=HEALTHY` - targets are healthy and critical alarms are not in `ALARM`
* `RUNTIME_HEALTH_STATUS=WARN` - warnings exist, for example `INSUFFICIENT_DATA`
* `RUNTIME_HEALTH_STATUS=UNHEALTHY` - there are no healthy targets or a critical alarm is firing
* `RUNTIME_HEALTH_STATUS=ERROR` - evidence collection failed

The script saves:

```text
runtime-health-summary.txt
target-health.json
target-health-states.txt
asg.json
asg-instances.txt
cloudwatch-alarms.json
cloudwatch-alarm-states.txt
aws-caller-identity.json
```

---

## 18. Incident Decision Template

After all `recovery` actions, you need one final document:

```text
incident-decision.md
```

This is the decision record:

- what happened
- what the impact was
- what evidence was collected
- which options were considered
- what was chosen
- why the other options were rejected
- who approved it
- how the result was verified
- which follow-up actions were created

### Generate the template

Use:

```bash
lessons/74-disaster-recovery-and-incident-runbooks/scripts/incident-decision-template.sh INC-001 dev \
  > /tmp/incident-decision.md
```

Where:

```text
INC-001 = incident ID
dev = environment
```

The script only prints a Markdown template. It does not change anything in AWS or Terraform.

### What is inside the template

### Metadata

```text
Incident ID
Environment
Date UTC
Commit SHA
Terraform version
Operator
Reviewer
Severity
Status
```

This is needed so that one month later it is still clear:

- when it happened
- who performed the action
- which code version was used
- which environment was affected
- how serious it was

### Symptom

What was observed.

Example:

```text
Terraform apply failed while updating ASG tags.
```

Or:

```text
Production ALB target group has unhealthy targets after rollout.
```

### Immediate Actions

What was done immediately:

```text
Applies frozen
Current state snapshotted
Current plan captured
AWS reality checked
```

### Diagnosis

What was found:

```text
Incident type
Root cause
Affected resources
User impact
```

Here it is important to separate the symptom from the root cause.

Example:

- symptom: apply failed
- root cause: the apply role did not have `autoscaling:CreateOrUpdateTags`

### Decision

The most important section:

```text
Recovery path
Why this path
Alternatives rejected
Approval
```

This shows why you chose `fix-forward`, `rollback`, `state restore`, `import`, `no-op`, and so on.

### Execution

The exact commands or actions.

For example:

```text
Added missing IAM action to apply role policy.
Ran controlled apply from GitHub Actions.
```

Or:

```text
No force-unlock executed. Lock was active, waited for workflow completion.
```

### Verification

How you proved that `recovery` was completed:

```text
Post-incident plan exit code
Drift status
Runtime checks
Rollback needed
```

Now we have two layers:

* `post-incident-check.sh` — Terraform-level evidence
* `runtime-health-check.sh` — runtime health evidence

### Follow-up

What must be done to prevent this from happening again:

```text
Add CI policy check
Update IAM policy test
Improve runbook
Add alert
Add missing validation
```

## A good incident decision answers 4 questions

```text
What happened?
What did we decide?
Why was that the safest option?
How did we verify recovery?
```

---

## 19. Drills

Run drills in `dev` unless explicitly stated.

### Drill 1. State snapshot

Run `scripts/state-snapshot.sh dev` and verify the snapshot folder contains state, plan, Git SHA, and summary.

### Drill 2. Decision for a stuck lock

Break the real state, but only in an **isolated dev/lab environment**. Write a decision note explaining how you would prove that the lock is stale before running `force-unlock`.

For a stuck lock, it is safer to simulate not “damage”, but a **leftover lockfile**:

```text
lab74/dev/full/terraform.tfstate.tflock
```

#### Important

Do not do this if:

* a `GitHub Actions apply` is currently running
* another `terraform apply/plan` is open
* you are not sure that this is exactly `lab74/dev`
* there is any risk of mixing up the bucket/key

#### Safe stale lock simulation

#### A. Set variables

From the `dev` env:

```bash
BUCKET="$(awk -F\" '/bucket/ {print $2}' backend.hcl)"
STATE_KEY="$(awk -F\" '/key/ {print $2}' backend.hcl)"
LOCK_KEY="${STATE_KEY}.tflock"

echo "$BUCKET"
echo "$STATE_KEY"
echo "$LOCK_KEY"
```

#### B. Make sure the lock does not currently exist

```bash
aws s3api head-object \
  --bucket "$BUCKET" \
  --key "$LOCK_KEY"
```

If you get `404 Not Found`, there is no lock and you can continue.

If the object exists, **stop** and investigate first.

#### C. Create a fake stale lock

```bash
cat > /tmp/fake-tflock.json <<EOF
{
  "ID": "fake-stale-lock-l74-drill",
  "Operation": "OperationTypeApply",
  "Info": "lesson 74 stale lock drill",
  "Who": "manual-drill",
  "Version": "1.14.4",
  "Created": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "Path": "$STATE_KEY"
}
EOF

aws s3api put-object \
  --bucket "$BUCKET" \
  --key "$LOCK_KEY" \
  --body /tmp/fake-tflock.json \
  --content-type application/json
```

#### D. Verify that Terraform sees the lock

```bash
terraform plan -input=false -no-color
```

Expected result: Terraform should fail with a lock error.

#### E. Save evidence

```bash
terraform plan -input=false -no-color > ../../../../evidence/stuck-lock-plan-error.txt 2>&1 || true
cat ../../../../evidence/stuck-lock-plan-error.txt
```

#### F. Remove the fake lock with Terraform force-unlock or S3 delete?

The correct Terraform recovery command is:

```bash
terraform force-unlock fake-stale-lock-l74-drill
```

If Terraform cannot remove the synthetic lock because of its format, then clean it up manually:

```bash
aws s3api delete-object \
  --bucket "$BUCKET" \
  --key "$LOCK_KEY"
```

#### G. Check after cleanup

```bash
terraform plan -detailed-exitcode -input=false -no-color
echo $?
```

### Drill 3. Failed apply runbook

Use a controlled failure or a simulated failed apply log. Follow `runbooks/failed-apply.md` and write rollback/fix-forward/no-op decision.

Here, you do not have to actually break `apply`.

It is better to create a **simulated failed apply log** and go through the decision process.

Create an evidence file:

```bash
cat > lessons/74-disaster-recovery-and-incident-runbooks/evidence/failed-apply-log.txt <<'EOF'
Terraform apply failed while updating Auto Scaling Group tags.

Error:
AccessDenied: User is not authorized to perform autoscaling:CreateOrUpdateTags
Resource:
module.network.aws_autoscaling_group.web

Observed:
Some resources may already be changed.
State may or may not have been updated.
EOF
```

Goal: learn not to press `apply` again immediately, but to follow the recovery flow.

### Drill 4. Drift after emergency change

Create real safe `drift`: manually change a **tag** in AWS, then check how Terraform wants to revert it.

Goal:

* understand that a manual AWS change creates `drift`
* see it in `terraform plan`
* decide whether to roll back the manual change or accept it into code

#### A. Save ASG name into a variable

Save the ASG name into a variable:

```bash
ASG_NAME="$(terraform output -raw web_asg_name)"
echo "$ASG_NAME"
```

#### B. Create low-risk manual drift through a tag

Add a tag only to the ASG:

```bash
aws autoscaling create-or-update-tags \
  --tags "ResourceId=${ASG_NAME},ResourceType=auto-scaling-group,Key=ManualDrift,Value=lesson74,PropagateAtLaunch=false"
```

This is safer than changing capacity/security/IAM.

#### C. Verify that the tag appeared

```bash
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$ASG_NAME" \
  --query 'AutoScalingGroups[0].Tags[?Key==`ManualDrift`]' \
  --output table
```

#### D. Run plan

```bash
EVIDENCE_DIR=../../../../evidence
mkdir -p "$EVIDENCE_DIR"

terraform plan -detailed-exitcode -input=false -no-color > "$EVIDENCE_DIR/drift-after-emergency-plan.txt"
echo $? > "$EVIDENCE_DIR/drift-after-emergency-plan-exitcode.txt"
cat "$EVIDENCE_DIR/drift-after-emergency-plan-exitcode.txt"
```

Expected:

* exit code `2`
* the plan shows that Terraform wants to remove or change the tag

#### E. Create a decision file

```bash
cat > "$EVIDENCE_DIR/drift-after-emergency.md" <<EOF
# Drift After Emergency Change

- Environment: dev
- Resource: ${ASG_NAME}
- Manual change: Added ASG tag ManualDrift=lesson74
- Reason: lesson 74 drift drill
- Plan file: evidence/drift-after-emergency-plan.txt
- Plan exit code: $(cat "$EVIDENCE_DIR/drift-after-emergency-plan-exitcode.txt")

## Diagnosis

Terraform detected manual drift on ASG tags.

## Decision

Selected path: revert manual change in AWS.

Reason:
The manual tag was only a drill. It is not desired Terraform configuration.

Rejected:
- Codify in Terraform, because this tag is not needed.
- Ignore drift, because hidden manual changes should not remain.
- State restore, because state is not corrupted.

## Verification

After deleting the manual tag, run terraform plan again and confirm the drift is gone or only expected changes remain.
EOF
```

#### F. Remove the manual drift

```bash
aws autoscaling delete-tags \
  --tags "ResourceId=${ASG_NAME},ResourceType=auto-scaling-group,Key=ManualDrift"
```

#### G. Check after cleanup

```bash
terraform plan -detailed-exitcode -input=false -no-color > "$EVIDENCE_DIR/drift-after-emergency-post-cleanup-plan.txt"
echo $? > "$EVIDENCE_DIR/drift-after-emergency-post-cleanup-exitcode.txt"
cat "$EVIDENCE_DIR/drift-after-emergency-post-cleanup-exitcode.txt"
```

If `0` — clean.
If `2` — there is still a diff; read the plan.
If `1` — error.

### Drill 5. S3 state versions

List the versions for `lab74/dev/full/terraform.tfstate`.

Perform a `restore` only if you are intentionally practicing recovery in an isolated lab.

The minimal restore command looks like this:

```bash
aws s3api copy-object \
  --bucket "$BUCKET" \
  --copy-source "${BUCKET}/${STATE_KEY}?versionId=${VERSION_ID}" \
  --key "$STATE_KEY"
```

But the correct discipline is still:

1. Before restore, save the current latest `VersionId`.
2. Save a `state snapshot`.
3. Download the candidate `state`.
4. Restore the candidate.
5. Immediately run `terraform plan -detailed-exitcode`.
6. If the plan looks strange, restore back to the original latest `VersionId`.
7. Save both `VersionId` values in evidence.

### Drill 6. Rollback vs fix-forward

Take a bad `module release` and write why `rollback` or `fix-forward` is safer.

Use this scenario:

```text
Scenario:
A module release changed the ALB target group health check threshold too aggressively.
Targets became unhealthy during rollout.

Bad change:
health_check_healthy_threshold was changed in a way that caused unstable rollout behavior.

User impact:
dev only / no production impact.

Rollback option:
Return to the previous module version or previous health check values.

Fix-forward option:
Patch the health check settings to safer values and apply a controlled change.

Decision:
fix-forward or rollback, depending on which plan is smaller and safer.
```

How to choose:

`Rollback` is better if:

- the previous version is definitely known-good
- the rollback plan is small
- there will be no destroy/replace of important resources
- `state` and `AWS reality` are understood

`Fix-forward` is better if:

- the problem is understood and can be fixed with one setting
- rollback would touch more resources
- the old version is unsafe
- there is already an emergency/manual change that stabilized the service

### Drill 7. Break-glass evidence

Simulate documentation only: who, what, when, why normal path was not enough, and how Terraform control is restored.

### Drill 8. Recovery game day

In an isolated `dev` lab, simulate one safe scenario:

- failed apply;
- manual tag drift;
- unexpected plan diff;
- stale lock scenario.

For the scenario, collect:

- snapshot;
- diagnosis;
- decision;
- recovery path;
- post-check;
- incident record.

---

## 20. Troubleshooting

| Symptom | Likely cause | What to do |
| --- | --- | --- |
| `terraform state pull` fails | backend not initialized or credentials missing | run init/check AWS auth before recovery |
| plan exits `2` after incident | drift or remaining diff | classify as expected or unexpected |
| plan exits `1` | provider/backend/config error | fix tooling before recovery action |
| S3 versions not visible | versioning disabled or wrong key | verify bucket/key and bootstrap settings |
| lock error repeats | active run still exists or stale lock not cleared | check active runs before force-unlock |
| state restore looks tempting | config rollback is being confused with state recovery | restore state only when state is wrong |
| break-glass action not documented | incident response skipped evidence | write record before closing incident |

---

## 21. Acceptance Criteria

Lesson 74 is complete when:

- scripts exist and pass syntax checks;
- runbooks exist and match the lesson flow;
- module tests pass;
- inherited policy tests pass;
- at least four drills are completed;
- proof pack is captured;
- can explain when not to use `force-unlock`, `state push`, and S3 state restore.

---

## 22. Lesson Summary

- **What you learned:** Terraform disaster recovery is a controlled operational process.
- **What you practiced:** state snapshots, lock reasoning, S3 version recovery model, failed apply triage, break-glass evidence.
- **Operational focus:** freeze, snapshot, diagnose, decide, execute, verify, document.
- **Why it matters:** eventually something will fail.
