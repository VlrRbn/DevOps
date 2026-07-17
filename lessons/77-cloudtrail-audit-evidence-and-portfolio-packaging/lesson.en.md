# Lesson 77. CloudTrail Audit Evidence

**Goal:** close the Terraform delivery track by proving what AWS recorded and packaging the capstone.

**Focus:** CloudTrail audit evidence, OIDC role assumption proof, state backend audit notes, AccessDenied investigation, and safe public sharing.

---

## 1. Why This Lesson Exists

Lesson 76 proved the delivery pipeline:

```text
PR checks
-> fresh plan from protected branch
-> policy gates
-> cost gates
-> risk classification
-> approval
-> exact saved-plan apply
-> post-apply drift check
-> runtime health evidence
```

That evidence proves what the pipeline did. The last operational question is different:

```text
Can I prove what AWS saw?
```

CloudTrail answers that question. It records AWS API activity as events: who called an API, when, from which role/session, whether it succeeded, and which service/resource was involved.

Terraform operator should be able to correlate both sides:

```text
GitHub workflow evidence <-> CloudTrail AWS-side evidence
```

---

## 2. Outcomes

After this lesson you should be able to:

- explain CloudTrail in one sentence;
- distinguish management events from data events;
- find `AssumeRoleWithWebIdentity` events from GitHub Actions OIDC;
- identify the plan/apply role used by Terraform;
- investigate `AccessDenied` with CloudTrail instead of guessing;
- explain why Terraform S3 backend object access needs S3 data events;
- collect CloudTrail audit evidence for the capstone;
- package the project for interview review without leaking sensitive details.

---

## 3. Connection To Previous Lessons

| Lesson | What it added | What lesson 77 does with it |
| --- | --- | --- |
| 60 | remote state and locking | explains how to audit state object access |
| 63 | PR plan pipeline | ties CI plan evidence to AWS role assumption |
| 64 | drift detection | uses CloudTrail to investigate unexpected AWS-side changes |
| 65 | secrets and safe inputs | reinforces redaction before sharing evidence |
| 69 | plan/apply role split | proves which role was actually used |
| 70 | JSON plan policy | includes policy result in the story |
| 71 | multi-env promotion | connects dev/stage/prod promotion to AWS audit trails |
| 76 | end-to-end delivery capstone | becomes the source project for audit packaging |

Lesson 77 closes the loop around the architecture what already built.

Lesson 77 does not need a dedicated CI workflow. Script checks can run locally, and live CloudTrail checks stay as manual practice because they depend on the account, region, run time, and data events that must have been enabled in advance.

---

## 4. CloudTrail Mental Model

CloudTrail records AWS account activity as events.

- CloudTrail does not record whether “the server is working or not.”
- It records “who called which AWS API.”

CloudTrail answers these questions:

```text
Who?
When?
Through which role/session?
Which AWS service?
Which API action?
Successful or failed?
Which request parameters?
Which errorCode/errorMessage?
```

Imagine delivery-chain:

```text
GitHub Actions job
-> OIDC token
-> STS AssumeRoleWithWebIdentity
-> temporary AWS credentials
-> Terraform calls AWS API
-> CloudTrail records API events
```

For Terraform delivery, the most useful event families are:

| Area | Event examples | Why it matters |
| --- | --- | --- |
| STS / OIDC | `AssumeRoleWithWebIdentity` | proves GitHub Actions received AWS credentials |
| IAM | `CreateRole`, `PutRolePolicy`, `PassRole` | proves role/policy activity |
| EC2 / ELB / ASG | `RunInstances`, `CreateLoadBalancer`, `UpdateAutoScalingGroup` | proves infrastructure changes |
| S3 backend | `GetObject`, `PutObject`, `DeleteObject` | proves state object access when data events are enabled |
| CloudTrail itself | `LookupEvents`, trail changes | proves audit access or audit configuration changes |

`AssumeRoleWithWebIdentity` is usually the first event we look for after a GitHub Actions workflow:

```text
GitHub OIDC token -> AWS STS -> temporary credentials for IAM role
```

Key rule:

```text
CloudTrail does not replace pipeline evidence. It verifies and complements it.
```

---

## 5. Management Events vs Data Events

| Event type | Examples | Default behavior | Terraform relevance |
| --- | --- | --- | --- |
| Management events | IAM, STS, EC2, ALB, ASG control-plane calls | visible in Event History for recent events | enough for role assumption and infra API calls |
| Data events | S3 object `GetObject`, `PutObject`, `DeleteObject` | must be explicitly enabled | required for object-level state audit |

Delivery management events are usually enough to understand:

- which role was used
- which AWS APIs Terraform called
- where `AccessDenied` happened
- which control-plane changes occurred

Terraform state backend audit needs object-level S3 visibility.

Bucket-level events answer questions like:

```text
Was bucket versioning configured?
Was bucket policy changed?
```

Object-level data events answer questions like:

```text
Who read terraform.tfstate?
Who wrote terraform.tfstate?
Who removed terraform.tfstate.tflock?
```

Data events can add noise and cost, and they make it harder to find what you need. In production, use narrow selectors for the Terraform state bucket and prefix instead of enabling broad S3 data events for every bucket.

Important limitation: `aws cloudtrail lookup-events` is convenient for recent management events. For object-level S3 data events, you usually need a data source that was configured in advance: CloudTrail Lake, Athena over trail logs in S3, or another destination where CloudTrail delivers events.

---

## 6. GitHub Actions OIDC Audit Trail

The role assumption chain is:

```text
GitHub Actions job
-> OIDC token from token.actions.githubusercontent.com
-> AWS STS AssumeRoleWithWebIdentity
-> temporary AWS credentials
-> Terraform AWS API calls
```

Main Event:

```text
eventName = AssumeRoleWithWebIdentity
```

Useful fields:

```text
eventTime
eventSource
eventName
awsRegion
sourceIPAddress
userIdentity
requestParameters.roleArn
requestParameters.roleSessionName
responseElements.assumedRoleUser.arn
errorCode
errorMessage
```

This event proves that the workflow assumed an AWS role. It does not prove the whole deployment succeeded. For that, correlate it with plan/apply artifacts and post-apply evidence.

**What exactly we check**

1. `eventName`

It must be:

```text
AssumeRoleWithWebIdentity
```

2. `requestParameters.roleArn`

Shows which IAM role GitHub tried to assume.

For example:

```text
arn:aws:iam::<account-id>:role/lab76-dev-github-actions-plan-role
```

3. `requestParameters.roleSessionName`

Usually shows the session name configured in the workflow.

For example:

```text
gha-lesson76-promote-dev
```

4. `responseElements.assumedRoleUser.arn`

Shows the final assumed-role identity.

5. `errorCode` and `errorMessage`

If everything is fine, there is no error. If the OIDC trust policy is wrong, it may show `AccessDenied`.

**What this proves**

This proves:

```text
GitHub Actions really received temporary AWS credentials for the correct role.
```

**What this does NOT prove**

This does not prove:

```text
Terraform apply was successful
the infrastructure works
the risk decision was correct
post-apply drift is clean
```

For that, you need other evidence:

- `plan.txt`
- `tfplan.json`
- `risk-decision.md`
- `apply.txt`
- `post_apply_plan.txt`
- runtime health evidence
- GitHub run URL
- commit SHA

**How to connect GitHub and AWS**

Minimal linkage:

```text
GitHub run URL
Commit SHA
Target environment
Role ARN
Role session name
CloudTrail eventTime
Apply result
Post-apply result
```

---

## 7. Basic CloudTrail CLI Commands

Find recent OIDC role assumptions:

```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity \
  --region eu-west-1 \
  --max-results 10 \
  --query 'Events[].{Time:EventTime,Name:EventName,User:Username,EventId:EventId}' \
  --output table
```

Do not print the full `lookup-events` response as a table without `--query`: a CloudTrail event contains large nested JSON, and the terminal becomes almost unreadable.

Inspect one event as JSON:

```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity \
  --region eu-west-1 \
  --max-results 1 \
  --query 'Events[0].CloudTrailEvent' \
  --output text | jq .
```

Find IAM-related events:

```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventSource,AttributeValue=iam.amazonaws.com \
  --region eu-west-1 \
  --max-results 20 \
  --query 'Events[].{Time:EventTime,Name:EventName,User:Username,EventId:EventId}' \
  --output table
```

Capture recent events for later review:

```bash
aws cloudtrail lookup-events \
  --region eu-west-1 \
  --max-results 50 \
  --output json > cloudtrail-recent-events.json
```

---

## 8. S3 State Backend Audit

For Terraform remote state, relevant object names usually look like:

```text
lab76/dev/full/terraform.tfstate
lab76/dev/full/terraform.tfstate.tflock
lab76/stage/full/terraform.tfstate
lab76/prod/full/terraform.tfstate
```

Important object actions:

```text
GetObject
PutObject
DeleteObject
CopyObject
ListObjectVersions
```

`lookup-events` can show recent management events, but it should not be treated as a full search interface for object-level S3 access. Reads and writes of `terraform.tfstate` require S3 data event logging that was enabled before the event happened. If data events were not enabled in advance, CloudTrail cannot retroactively produce object-level events for that action.

State backend audit decision template:

```markdown
# State Backend Audit Decision

- State bucket:
- State prefix:
- Data events enabled: yes/no/deferred
- Reason:
- Cost risk:
- Production recommendation:
```

Expected production recommendation:

```text
Enable S3 data events for the Terraform state bucket/prefix, not for every bucket in the account.
Decide in advance where those data events will be queried: CloudTrail Lake, Athena over trail logs, or another centralized audit system.
```

### Optional production path: create a CloudTrail trail

Event History is enough for the basic lab, but production-style audit needs a dedicated trail. This lesson includes an optional Terraform root:

```text
lab_77/audit-trail/
```

It creates:

- a dedicated S3 bucket for CloudTrail logs;
- public access block;
- S3 bucket versioning;
- SSE-S3 encryption;
- lifecycle retention;
- CloudTrail trail for management events;
- focused S3 data events only for the Terraform state bucket/prefixes.

This is not another application stack. It is an audit layer around the capstone you already built.

Use it when you want to prove not only recent management events from Event History, but also configured audit trail selectors.

```bash
cd lessons/77-cloudtrail-audit-evidence-and-portfolio-packaging/lab_77/audit-trail
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

After apply:

```bash
terraform output -raw trail_name
```

Pass the trail name to the snapshot script:

```bash
../../scripts/cloudtrail-audit-snapshot.sh \
  --region eu-west-1 \
  --state-bucket YOUR_TFSTATE_BUCKET \
  --state-prefix lab76/dev/full/ \
  --trail-name YOUR_TRAIL_NAME
```

Important: S3 data events can add cost and noise. Do not enable them for every bucket in the account. For both lab and production, keep the scope narrow: only the Terraform state bucket/prefixes.

For stricter production/compliance setups, harden the audit log bucket with S3 Object Lock and SSE-KMS. They are not enabled by default in the lab: Object Lock makes cleanup harder, and SSE-KMS requires a dedicated KMS key policy and adds another troubleshooting layer.

#### Cleanup audit trail

By default, `force_destroy_log_bucket = false`. That means:

```text
terraform destroy removes the CloudTrail trail and bucket configuration,
but the S3 log bucket can remain if it still contains log object versions.
```

This is normal behavior for an audit bucket. Logs should not disappear accidentally.

Options:

1. Keep the bucket as audit evidence.

This is the safest option if the logs might be useful later.

2. For a disposable lab, allow Terraform to delete bucket contents:

```hcl
force_destroy_log_bucket = true
```

Then run:

```bash
terraform apply -auto-approve
terraform destroy
```

3. Delete object versions/delete markers manually if the bucket already remained after destroy.

Inspect first:

```bash
aws s3api list-object-versions \
  --bucket YOUR_CLOUDTRAIL_LOG_BUCKET \
  --region eu-west-1
```

After emptying the bucket, rerun:

```bash
terraform destroy
```

Do not delete audit logs if they are needed for the proof-pack or an investigation.


Example:

```bash
bucket: vlrrbn-tfstate-123456789012-eu-west-1
prefix: lab76/prod/full/
```

---

## 9. AccessDenied Investigation

When Terraform fails with `AccessDenied`, do not guess.

Correct approach:

```text
First understand which API action was denied,
which role called it,
and whether this deny should actually be treated as an error.
```

Because `AccessDenied` can be of two types.

### 1. Expected guardrail

This is when the deny is expected and correct.

Example:

- the plan role tries to call `CreateRole`
- but the plan role should only read and build a plan, not mutate AWS

In this case, `AccessDenied` is not a bug. It proves that:

* least privilege works

### 2. Missing permission

This is when the action is legitimate, but the role is too narrow.

Example:

* the apply role needs to update an ASG tag
* but it does not have `autoscaling:CreateOrUpdateTags`

In this case, it is not a guardrail. It is a missing permission.

We do not give `Admin`. We add the specific action on the specific scope.

Use this flow:

```text
1. Save the Terraform error.
2. Identify the approximate failure time.
3. Search CloudTrail around that time.
4. Find eventName, eventSource, errorCode, and errorMessage.
5. Identify the assumed role.
6. Decide whether the denial is expected guardrail behavior or a missing permission.
7. Change IAM only if the action is legitimate.
8. Save before/after evidence.
```

Important fields:

```text
eventTime
eventName
eventSource
awsRegion
userIdentity.type
userIdentity.sessionContext.sessionIssuer.arn
requestParameters
errorCode
errorMessage
```

Important mindset:

```text
AccessDenied is not automatically a bug. Sometimes it proves the guardrail worked.
```

---

## 10. Audit Snapshot Script

This lesson includes:

```text
scripts/cloudtrail-audit-snapshot.sh
```

It collects:

- AWS caller identity;
- recent `AssumeRoleWithWebIdentity` events;
- recent IAM events;
- recent EC2, ELBv2, and Auto Scaling events;
- recent denied-looking events;
- optional S3 backend event notes;
- a Markdown summary for review.

Example:

```bash
lessons/77-cloudtrail-audit-evidence-and-portfolio-packaging/scripts/cloudtrail-audit-snapshot.sh \
  --region eu-west-1 \
  --state-bucket YOUR_STATE_BUCKET \
  --state-prefix lab76/ \
  --start-time 2026-07-01T10:00:00Z \
  --end-time 2026-07-01T11:00:00Z \
  --release-id l76-demo \
  --workflow-url https://github.com/OWNER/REPO/actions/runs/123456789 \
  --trail-name YOUR_TRAIL_NAME
```

The script does not modify AWS resources. It only reads CloudTrail and STS data.

---

## 11. Practical Drills

### Drill 1. Find GitHub OIDC Role Assumption

Run a GitHub Actions workflow from lesson 76. Then run:

```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity \
  --region eu-west-1 \
  --max-results 10 \
  --output json > assume-role-events.json
```

Expected evidence:

- event name is `AssumeRoleWithWebIdentity`;
- role ARN matches plan/apply role;
- event time is close to the GitHub workflow run;
- no unexpected `errorCode`.

### Drill 2. Investigate One Denied Action

Use a safe denied case from your previous lessons, for example a plan role trying to mutate infrastructure.

Capture:

```bash
aws cloudtrail lookup-events \
  --region eu-west-1 \
  --max-results 50 \
  --output json > cloudtrail-after-deny.json
```

Write a short decision:

```markdown
# AccessDenied Decision

- Failure time:
- Event name:
- Event source:
- Role:
- Error:
- Expected denial: yes/no
- Action taken:
```

### Drill 3. State Backend Audit Decision

Write the state backend data-event decision note. Do not enable broad S3 data events blindly.

Expected answer:

```text
For a production backend, enable S3 data events only for the Terraform state bucket/prefix. For a short lab, document whether it was deferred to avoid cost/noise.
```

### Drill 4. Match GitHub and AWS Evidence

Pick one workflow run and build this table:

```markdown
| Evidence | Value |
| --- | --- |
| GitHub run URL |  |
| Commit SHA |  |
| Target environment |  |
| AWS role assumed |  |
| CloudTrail event time |  |
| Risk decision |  |
| Apply result |  |
| Post-apply exit code |  |
```

Expected result:

```text
CloudTrail and workflow artifacts describe the same change.
```

---

## 12. Troubleshooting

| Symptom | Likely cause | What to check |
| --- | --- | --- |
| No CloudTrail events found | wrong region or event too old | CloudTrail region, time window, Event History retention |
| No S3 object access events | data events not enabled or checked through the wrong interface | trail/event selector configuration, CloudTrail Lake, Athena, or log destination |
| OIDC event missing | workflow did not assume AWS role | GitHub job logs, OIDC provider, role trust policy |
| AccessDenied event not obvious | CloudTrail delay or wrong lookup field | search by time, source, event name, and role ARN |
| Event shows wrong role | workflow variable/secret points to wrong ARN | GitHub variables and environment secrets |
| Evidence contains account IDs | raw files copied into folder | run redaction checklist before commit |
| Portfolio too detailed | raw implementation leaked | summarize controls, do not publish internal artifacts |

---

## 13. Proof Pack

Create an ignored evidence folder, for example:

```bash
mkdir -p lessons/77-cloudtrail-audit-evidence-and-portfolio-packaging/evidence/l77-$(date -u +%Y%m%d_%H%M%S)
```

Save:

```text
cloudtrail-summary.md
aws-caller-identity.json
aws-cli-version.txt
assume-role-with-web-identity-events.json
iam-events.json
ec2-events.json
elbv2-events.json
autoscaling-events.json
cloudtrail-trails.json
cloudtrail-event-selectors.json
cloudtrail-events.json
recent-events.json
denied-events.json
s3-management-events.json
state-backend-audit-decision.md
access-denied-decision.md
```

Raw evidence can contain sensitive operational metadata. Keep raw evidence local or redact it before committing.

If a file is empty or an event is missing, keep the file and explain why in `cloudtrail-summary.md`. Missing evidence is still useful when it is documented clearly.

---

## 14. Final Acceptance

Lesson is complete when:

- [ ] you can explain CloudTrail in one sentence;
- [ ] you can find `AssumeRoleWithWebIdentity`;
- [ ] you can explain management vs data events;
- [ ] you can explain why S3 state backend audit needs data events;
- [ ] you investigated one denied event or documented why no denied event was available;
- [ ] you created a CloudTrail audit snapshot;
- [ ] you completed the state backend audit decision note;
- [ ] you ran a redaction checklist before sharing anything;
- [ ] your proof-pack explains both pipeline evidence and AWS-side audit evidence.

---

## 15. Lesson Summary

- **What you learned:** CloudTrail gives AWS-side audit evidence for Terraform delivery.
- **What you practiced:** finding OIDC role assumption, checking Terraform-related events, documenting state backend audit needs, and packaging the capstone.
- **Operational focus:** prove not only what the pipeline said, but also what AWS recorded.
