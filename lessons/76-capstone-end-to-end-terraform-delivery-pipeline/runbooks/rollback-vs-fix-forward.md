# Runbook: Rollback vs Fix-Forward

## Rollback

Use when:

- previous known-good version exists;
- rollback plan is safe;
- state/resource addresses still match;
- reverting reduces risk.

## Fix-Forward

Use when:

- rollback would replace or destroy more;
- bad change is already partially applied;
- a small patch is safer;
- dependency graph has moved on.

## State Restore

Use when:

- Terraform state itself is wrong;
- remote state was corrupted or overwritten;
- normal rollback does not address state ownership.

## Break-Glass

Use when:

- user impact is active;
- normal automation is blocked;
- delay is worse than controlled manual action.

## Decision Table

| Question | Rollback | Fix-forward | State restore | Break-glass |
| --- | --- | --- | --- | --- |
| Is state corrupt? | no | no | yes | maybe |
| Is previous version known-good? | yes | maybe | maybe | no |
| Is prod actively degraded? | maybe | yes | maybe | yes |
| Is automation working? | yes | yes | maybe | no |
| Is manual AWS action needed now? | no | maybe | maybe | yes |

## Rule

Rollback is not automatically safer. It must be planned, reviewed, and verified.
