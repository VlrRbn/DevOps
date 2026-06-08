# Lesson 69 Proof Pack - Production IAM Least Privilege

Recommended evidence folder:

```bash
mkdir -p lessons/69-production-iam-least-privilege-plan-and-apply-roles/evidence/l69-YYYYmmdd_HHMMSS
```

Redact account IDs, bucket names, role unique IDs, AMI IDs if needed, and GitHub run URLs before committing public evidence.

## 1. Role Policy Inventory

Capture attached and inline policies:

```bash
aws iam list-attached-role-policies --role-name lab69-github-actions-apply-role --output json > apply-role-attached-policies.json
aws iam list-role-policies --role-name lab69-github-actions-apply-role --output json > apply-role-inline-policies.json
aws iam list-role-policies --role-name lab69-github-actions-role --output json > plan-role-inline-policies.json
```

Expected:

- apply role does not have `AdministratorAccess`
- plan role does not have broad infrastructure mutation permissions

## 2. Trust Policies

Capture trust policy documents:

```bash
aws iam get-role --role-name lab69-github-actions-apply-role --output json > apply-role-trust-policy.json
aws iam get-role --role-name lab69-github-actions-role --output json > plan-role-trust-policy.json
```

Expected:

- apply role `sub` is environment-bound
- plan role `sub` allows PR/main only

## 3. Positive Proof

Save evidence that plan and safe apply still work:

```text
plan-role-plan-success.txt
apply-safe-change-run.md
post-apply-exitcode.txt
```

Expected:

- plan completes
- apply completes for a safe change inside the allowed scope
- post-apply plan exit code is `0`

## 4. Negative Proof

Save denial evidence:

```text
plan-role-apply-denied.txt
passrole-denied.txt
wrong-oidc-subject-denied.txt
```

Expected:

- plan role cannot mutate
- apply role cannot pass arbitrary roles
- non-environment job cannot assume apply role

## 5. Permission Refinement Notes

Keep a short review note:

```text
access-analyzer-notes.md
least-privilege-review.md
```

Include:

- why any `Resource = "*"` remains
- actions added after proven `AccessDenied`
- actions intentionally rejected
- follow-up work for tighter production IAM
