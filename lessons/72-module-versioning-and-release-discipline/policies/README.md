# Lesson 72 Policies

This folder reuses the JSON plan policy gate from the previous Terraform delivery lessons.

In lesson 72 the policy is not the main topic. Its role is to keep module release drills honest:

- destructive plans are denied unless there is an explicit exception file;
- public ingress and broad egress are caught;
- required tags are enforced;
- policy tests prove the gate still behaves before a module release is promoted.

Run from repo root:

```bash
lessons/72-module-versioning-and-release-discipline/policies/test-policy.sh
lessons/72-module-versioning-and-release-discipline/policies/test-opa.sh
```
