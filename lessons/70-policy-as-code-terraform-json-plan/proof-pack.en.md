# Lesson 70 Proof Pack

Use this checklist when saving evidence for Policy as Code on Terraform JSON Plan.

Recommended ignored folder:

```text
lessons/70-policy-as-code-terraform-json-plan/evidence/l70-YYYYmmdd_HHMMSS/
```

## 1. Plan Artifacts

Save:

```bash
cp tfplan.txt evidence/l70-YYYYmmdd_HHMMSS/
cp tfplan.json evidence/l70-YYYYmmdd_HHMMSS/
```

Required files:

- `tfplan.txt`
- `tfplan.json`

Redact before sharing outside your environment.

## 2. Policy Decision

Save:

```bash
cp policy-results/policy-decision.txt evidence/l70-YYYYmmdd_HHMMSS/
cp policy-results/policy-output.txt evidence/l70-YYYYmmdd_HHMMSS/
cp policy-results/policy-deny.json evidence/l70-YYYYmmdd_HHMMSS/
cp policy-results/policy-warn.json evidence/l70-YYYYmmdd_HHMMSS/
```

Required files:

- `policy-decision.txt`
- `policy-output.txt`
- `policy-deny.json`
- `policy-warn.json`

## 3. Rule Evidence

Save the rule-specific outputs:

- `destructive.json`
- `destructive-unapproved.json`
- `public-ingress-rules.json`
- `public-ingress-inline-sg.json`
- `missing-tags.json`
- `warn-nat.json`
- `warn-asg-max.json`
- `warn-public-lb.json`

## 4. Exception Evidence

If destroy/replacement was allowed, save:

- exception file
- approval reference
- reason
- expiry date
- before/after policy decision
- invalid-exception proof if a wildcard or malformed exception was tested
- expired-exception proof if an expired exception was tested

Destroy exceptions without exact addresses should be rejected.
Destroy exceptions with an expired `expires` date should be rejected against the current UTC date.

## 5. False Positive Checks

If you test the policy deeper, save evidence that:

- public ingress is blocked
- public egress is not blocked by the ingress rule
- missing required tags are blocked
- empty required tag values are blocked

## 6. CI Evidence

If GitHub Actions was used, save:

- workflow run URL
- plan artifact name
- apply artifact name
- GitHub Environment approval screenshot or note
- post-apply drift check result

## 7. Final Decision

Create `decision.txt`:

```text
DECISION=ALLOW|DENY
reason=<short explanation>
reviewer=<name or handle>
timestamp=<UTC timestamp>
artifacts=<folder path>
```

## 8. Redaction Checklist

Before committing or sharing evidence, check for:

- AWS account IDs
- ARNs that identify private infrastructure
- instance IDs
- public IPs
- secret values
- backend bucket names if you consider them private
- GitHub role ARNs
