# Lesson 73 Proof Pack

Store evidence in an ignored local folder, for example:

```text
lessons/73-cost-and-blast-radius-controls/evidence/l73-cost-guard/
```

Do not commit raw billing data, account IDs, emails, or internal DNS names unless intentionally redacted.

---

## 1. Plan Policy Evidence

Save:

```text
security-policy-decision.txt
security-policy-deny.json
security-policy-warn.json
```

The baseline policy should still prove:

- destructive changes are blocked unless explicitly approved;
- public ingress is blocked;
- required tags are enforced.

---

## 2. Cost Policy Evidence

Save outputs from:

```bash
lessons/73-cost-and-blast-radius-controls/policies/test-cost-policy.sh
```

Practical option:

```bash
mkdir -p lessons/73-cost-and-blast-radius-controls/evidence/l73-cost-guard

lessons/73-cost-and-blast-radius-controls/policies/test-cost-policy.sh \
  > lessons/73-cost-and-blast-radius-controls/evidence/l73-cost-guard/cost-policy-tests.txt 2>&1
```

Minimum files:

```text
cost-policy-safe.txt
cost-policy-nat-dev-deny.txt
cost-policy-nat-stage-warn.txt
cost-policy-asg-deny.txt
cost-policy-large-instance-deny.txt
cost-policy-public-lb-warn.txt
```

---

## 3. Infracost Evidence

If Infracost is available, you can scan the real `tfplan.json`, but remember: this sends plan metadata to the external Infracost service. Use it only for lab/non-sensitive plans. Save the scan result in the proof pack, not the raw `tfplan.json`:

```text
infracost.json
infracost-summary.txt
infracost-top.txt
infracost-failing.txt
```

---

## 4. AWS Budget Evidence

Save a redacted proof file:

```text
aws-budget-proof-redacted.txt
```

Include:

- budget name;
- monthly limit;
- threshold type: actual/forecasted;
- notification target redacted;
- date checked.

---

## 5. Quota Evidence

Save at least one relevant quota check:

```text
service-quota-ec2.txt
service-quota-elb.txt
```

The note must say whether the lab design is inside the quota.

Example read-only command:

```bash
aws service-quotas list-service-quotas \
  --service-code elasticloadbalancing \
  --region eu-west-1 \
  --output table \
  > lessons/73-cost-and-blast-radius-controls/evidence/l73-cost-guard/service-quota-elb.txt
```

---

## 6. Cost Decision

Create:

```text
cost-decision.md
```

`Commit SHA` is for the audit trail. It does not require `git commit` or `git push`; use the current local `HEAD`:

```bash
git rev-parse HEAD
git status --short
```

If the working tree is not clean, fill `Working tree status`.

Template:

```markdown
# Cost & Blast-Radius Decision

- Date checked: 2026-06-12
- Commit SHA: REPLACE_WITH_GIT_REV_PARSE_HEAD
- Working tree status: dirty, lesson 73 files modified locally
- Target environment: dev
- Terraform plan source: lab_73/terraform/envs/dev/tfplan.json
- Release/module version: local lesson 73 module source

## Security/change policy

- Security policy decision: baseline policy tests passed
- Security policy denies: none in accepted proof
- Security policy warnings: see generated policy evidence if present

## Cost policy

- Cost policy decision: ALLOW
- Cost policy denies: []
- Cost policy warnings: see real-dev-cost-policy/cost-warn.json

## Infracost

- Infracost attached: yes
- Infracost diagnostics: none
- Estimated monthly cost: $150
- Resources: 48 total, 17 costed, 31 free
- Top cost driver: 5 Interface VPC Endpoints across 2 AZs, about $120/month
- Notable findings:
  - ALB HTTP listener does not redirect HTTP to HTTPS.
  - EC2 ssm_proxy could potentially use Graviton, but this requires ARM-compatible AMI.
  - Infracost sample tagging policy expects Service tag and Environment values Dev/Stage/Prod.

## AWS Budget

- AWS Budget checked: yes
- Budget proof file: aws-budget-proof-redacted.txt
- Budget is an alerting safety net, not an instant apply blocker.

## Quotas

- Quota reviewed: yes
- Quota proof file: service-quota-elb.txt
- ELB quota decision: lab design is inside reviewed quotas.

## Decision

- Apply allowed for lab: yes
- Reason: deterministic cost policy allows the dev plan; Infracost estimate is accepted for lab; expensive VPC endpoints are understood as the main cost driver; Budget and quota evidence are present.
- Reviewer: ---
```