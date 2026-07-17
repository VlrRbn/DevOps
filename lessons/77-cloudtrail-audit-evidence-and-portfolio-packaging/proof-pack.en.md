# Lesson 77 Proof Pack

Store evidence in an ignored local folder, for example:

```bash
mkdir -p lessons/77-cloudtrail-audit-evidence-and-portfolio-packaging/evidence/l77-$(date -u +%Y%m%d_%H%M%S)
```

Do not commit raw evidence unless it is intentionally redacted. `tfplan.json`, `backend.hcl`, `terraform.auto.tfvars`, and runtime outputs can contain account IDs, ARNs, internal DNS names, IPs, and other operational information.

---

## 1. CloudTrail Snapshot

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
s3-management-events.json
denied-events.json
```

Must show:

- capture time;
- region;
- caller identity used for audit collection;
- OIDC role assumption evidence if a workflow ran;
- recent service events relevant to Terraform delivery.
- a summary explaining any missing events or deferred checks.

---

## 2. GitHub To AWS Correlation

Save a table with:

```text
GitHub run URL
Commit SHA
Target environment
Release ID
Plan/apply role ARN or redacted ARN
CloudTrail event time
CloudTrail event name
Apply result
Post-apply result
```

Expected conclusion:

```text
GitHub workflow evidence and CloudTrail evidence describe the same change.
```

---

## 3. OIDC Role Assumption Evidence

Save:

```text
assume-role-with-web-identity-events.json
assume-role-review.md
```

Review fields:

```text
eventName
requestParameters.roleArn
requestParameters.roleSessionName
responseElements.assumedRoleUser.arn
errorCode
errorMessage
```

---

## 4. AccessDenied Evidence

Save one of:

```text
access-denied-decision.md
cloudtrail-after-deny.json
```

If no denied event was produced during the lab, document that explicitly.

Decision must say:

- expected guardrail or missing permission;
- role involved;
- event name/source;
- action taken.

---

## 5. State Backend Audit Decision

Save:

```text
state-backend-audit-decision.md
audit-trail-plan.txt
audit-trail-apply.txt
audit-trail-outputs.txt
```

Must include:

- state bucket;
- state prefix;
- whether S3 data events are enabled;
- where they are queried: CloudTrail Lake, Athena over trail logs, or another audit system;
- cost/noise decision;
- production recommendation.

Important: `aws cloudtrail lookup-events` is useful for recent management events, but it is not a complete query interface for object-level S3 data events.

If optional `lab_77/audit-trail/` was not applied, document it as `deferred`. If it was applied, save `terraform output`, `cloudtrail-event-selectors.json`, and the trail name passed to the snapshot script.

---

## 6. Redaction Checklist

Before sharing anything publicly, verify that you removed or masked:

- AWS account IDs;
- full ARNs;
- internal DNS names;
- private IPs;
- raw `tfplan.json`;
- Terraform state files;
- secret values;
- notification emails/endpoints;
- unreviewed CloudTrail raw events.

---

## 7. Final Review Note

Create:

```text
lesson77-final-review.md
```

Template:

```markdown
# Lesson 77 Final Review

- CloudTrail snapshot collected: yes/no
- OIDC role assumption found: yes/no
- AccessDenied investigated: yes/no/deferred
- State backend audit decision completed: yes/no
- Portfolio redacted: yes/no
- Public-safe files selected: yes/no
- Remaining sensitive evidence location:
- Final decision:
```
