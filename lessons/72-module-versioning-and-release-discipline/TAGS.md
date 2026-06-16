# Module Tag Commands

This file is a practical command guide for lesson 72 module tags.

Use it when you need to answer:

- what tag to create;
- when to create it;
- why it exists;
- how to check it;
- what not to do after it is published.

## 1. Tag Naming

Use module-scoped tags:

```text
network/v1.0.0
network/v1.1.0
network/v2.0.0
```

Do not use only:

```text
v1.0.0
```

Why:

- this repository is a monorepo;
- `v1.0.0` does not say which module was released;
- `network/v1.0.0` clearly means version `v1.0.0` of the `network` module;
- future modules can use their own version streams, for example `observability/v1.0.0`.

## 2. Before Creating Any Tag

Tags point to Git commits. They do not include untracked files, unstaged changes, or staged-but-not-committed changes.

Always check:

```bash
git status --short
git log --oneline --decorate -5
```

If the module change is not committed yet, do not tag yet.

Run checks before tagging:

```bash
terraform fmt -check -recursive lessons/72-module-versioning-and-release-discipline/lab_72/terraform
packer fmt -check -recursive lessons/72-module-versioning-and-release-discipline/lab_72/packer

TF_DATA_DIR=/tmp/l72-module-test-data \
terraform -chdir=lessons/72-module-versioning-and-release-discipline/lab_72/terraform/modules/network \
  init -backend=false -input=false -no-color

TF_DATA_DIR=/tmp/l72-module-test-data \
terraform -chdir=lessons/72-module-versioning-and-release-discipline/lab_72/terraform/modules/network \
  test -no-color
```

## 3. Create Baseline Tag `network/v1.0.0`

Create this only after the first clean lesson 72 baseline is committed.

Why:

- it marks the initial stable module version;
- env roots can pin to it;
- later releases have a known previous version to compare against;
- rollback has a real target.

Commands:

```bash
git tag -a network/v1.0.0 -m "network module v1.0.0"
git push origin network/v1.0.0
```

Check:

```bash
git show network/v1.0.0 --stat
git rev-parse network/v1.0.0
git ls-remote --tags origin "network/v1.0.0"
```

Expected result:

- local tag exists;
- remote tag exists after push;
- tag points to the baseline commit.

## 4. Pin Env Roots To The Baseline Tag

After `network/v1.0.0` exists, env roots can stop using a local module path:

```hcl
source = "../../modules/network"
```

and use a pinned Git source:

```hcl
source = "git::https://github.com/VlrRbn/DevOps.git//lessons/72-module-versioning-and-release-discipline/lab_72/terraform/modules/network?ref=network/v1.0.0"
```

Check refs:

```bash
for env in dev stage prod; do
  lessons/72-module-versioning-and-release-discipline/scripts/check-module-version.sh \
    "lessons/72-module-versioning-and-release-discipline/lab_72/terraform/envs/${env}" \
    "network/v1.0.0"
done
```

After changing a module source ref, run:

```bash
terraform init -upgrade
```

inside the env root you are checking.

## 5. Create Release Tag `network/v1.1.0`

Create this only after:

- the module change is committed;
- tests pass;
- `CHANGELOG.md` is updated;
- release note shows the expected diff;
- the change is classified as patch, minor, or major.

Example minor change:

```hcl
output "alb_zone_id" {
  value       = aws_lb.app.zone_id
  description = "ALB hosted zone ID for DNS automation."
}
```

Generate release note:

```bash
lessons/72-module-versioning-and-release-discipline/scripts/module-release-note.sh \
  network \
  v1.1.0 \
  network/v1.0.0 \
  HEAD \
  > /tmp/release-note-network-v1.1.0.md
```

Read it before tagging:

```bash
sed -n '1,220p' /tmp/release-note-network-v1.1.0.md
```

Create and push the tag:

```bash
git tag -a network/v1.1.0 -m "network module v1.1.0"
git push origin network/v1.1.0
```

Check:

```bash
git show network/v1.1.0 --stat
git rev-parse network/v1.1.0
git ls-remote --tags origin "network/v1.1.0"
```

Expected result:

- tag points to the release commit;
- release note diff matches the intended module change;
- `network/v1.0.0` remains unchanged.

## 6. Compare Two Module Versions

Show changed files inside the module:

```bash
git diff --name-status network/v1.0.0 network/v1.1.0 -- \
  lessons/72-module-versioning-and-release-discipline/lab_72/terraform/modules/network
```

Show full diff:

```bash
git diff network/v1.0.0 network/v1.1.0 -- \
  lessons/72-module-versioning-and-release-discipline/lab_72/terraform/modules/network
```

Show only output/interface-related changes:

```bash
git diff network/v1.0.0 network/v1.1.0 -- \
  lessons/72-module-versioning-and-release-discipline/lab_72/terraform/modules/network/variables.tf \
  lessons/72-module-versioning-and-release-discipline/lab_72/terraform/modules/network/outputs.tf \
  lessons/72-module-versioning-and-release-discipline/lab_72/terraform/modules/network/versions.tf
```

## 7. Promotion Order

Do not move every environment at once.

Use this order:

```text
dev -> stage -> prod
```

Typical version matrix during promotion:

| Environment | Module version | Status |
| --- | --- | --- |
| dev | `network/v1.1.0` | testing |
| stage | `network/v1.0.0` | stable |
| prod | `network/v1.0.0` | stable |

After dev evidence is clean:

```text
stage -> network/v1.1.0
```

After stage evidence is clean:

```text
prod -> network/v1.1.0
```

## 8. Rollback Check

Rollback target must be a real tag:

```bash
git show network/v1.0.0 --no-patch
git ls-remote --tags origin "network/v1.0.0"
```

Rollback means changing the env root ref back:

```hcl
?ref=network/v1.0.0
```

Then run:

```bash
terraform init -upgrade
terraform plan
```

Do not rollback blindly. Review the rollback plan first.

## 9. Do Not Move Published Tags

Bad idea:

```bash
git tag -f network/v1.1.0
git push --force origin network/v1.1.0
```

Why this is dangerous:

- another environment may already use the old tag value;
- Terraform module cache may contain the previous version;
- CI evidence becomes misleading;
- rollback and audit trails become unreliable.

Correct fix if a published tag is wrong:

```text
Create a new version:

network/v1.1.1 for a patch fix
network/v1.2.0 for a new backward-compatible release
network/v2.0.0 for a breaking release
```

## 10. Safe Local Cleanup

If you created a tag locally by mistake and did not push it:

```bash
git tag -d network/v1.1.0
```

If the tag was already pushed, do not delete or move it during a production-style release. Create a corrected new version instead.

## 11. Quick Checklist

Before `network/v1.0.0`:

- baseline committed;
- tests pass;
- tag does not already exist;
- tag points to the baseline commit.

Before `network/v1.1.0`:

- module change committed;
- release note generated from `network/v1.0.0` to `HEAD`;
- release note diff is expected;
- changelog updated;
- tests pass;
- version type is clear;
- rollback target `network/v1.0.0` exists.
