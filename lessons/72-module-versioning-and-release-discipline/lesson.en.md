# Module Versioning & Release Discipline

**Date:** 2026-06-10

**Focus:** turn the shared Terraform module into a versioned release artifact with Git tags, changelog entries, release notes, compatibility decisions, environment pinning, and rollback evidence.

**Mindset:** lesson 71 controls where a change is promoted. Lesson 72 controls what exact module release is promoted.

---

## 1. Why This Lesson Exists

In lesson 71 you built a promotion path:

```text
dev -> stage -> prod
```

That path is not enough by itself. If every environment uses a local module source like this:

```hcl
source = "../../modules/network"
```

then the environment consumes whatever module code exists in the current checkout. That is convenient for a lab, but not for production because the release has no stable identity.

A production module promotion should answer these questions:

- Which module version is being promoted?
- Which Git commit created that version?
- Is the change patch, minor, or major?
- Which tests proved the module contract still works?
- Which environments already consumed the version?
- What is the rollback target?

In this lesson the `network` module becomes a release artifact:

```text
network/v1.0.0
network/v1.1.0
network/v2.0.0
```

Production-model:

```text
local module source
        ↓
known-good commit
        ↓
network/v1.0.0 tag
        ↓
env roots pinned to network/v1.0.0
        ↓
module change
        ↓
tests + changelog + release note
        ↓
network/v1.1.0 tag
        ↓
dev -> stage -> prod
        ↓
rollback target network/v1.0.0
```

---

## 2. Outcomes

After this lesson you should be able to:

- explain why local module paths are not enough for production release discipline;
- define the public API of a Terraform module;
- classify module changes as patch, minor, or major;
- create module-scoped Git tags in a monorepo;
- write a useful module changelog entry and release note;
- pin module versions per environment root;
- promote the same module version through `dev -> stage -> prod`;
- prove that a rollback target exists;
- avoid dangerous practices such as moving published tags or letting prod float on `main`.

---

## 3. Connection To Previous Lessons

| Lesson | What it gave you | What lesson 72 adds |
| --- | --- | --- |
| 66 | module contracts and interface guarantees | the contract becomes the release boundary |
| 67 | Terraform native tests | tests become release gates before tagging |
| 68 | controlled apply pipeline | apply still uses exact reviewed plans |
| 69 | separate plan/apply IAM roles | release checks do not need apply permissions |
| 70 | policy as code over JSON plans | plan policy stays part of promotion evidence |
| 71 | multi-environment promotion | promotion now moves named module versions |

The important distinction:

```text
Promotion controls the path.
Versioning controls the artifact.
```

---

## 4. Repository Layout

```text
lessons/72-module-versioning-and-release-discipline/
├── README.md
├── TAGS.md
├── CHANGELOG.md
├── lesson.en.md
├── lesson.ru.md
├── proof-pack.en.md
├── proof-pack.ru.md
├── ci/
│   └── lesson72-module-release.yml
├── scripts/
│   ├── check-module-version.sh
│   └── module-release-note.sh
├── policies/
└── lab_72/
    ├── packer/
    └── terraform/
        ├── envs/
        │   ├── dev/
        │   ├── stage/
        │   └── prod/
        └── modules/
            └── network/
```

`lab_72` intentionally starts from the lesson 71 multi-environment model. The architecture stays familiar so the new topic is module release discipline, not a new infrastructure design.

---

## 5. Public API Of A Terraform Module

For Terraform modules, the public API is more than variables and outputs.

| API area | Examples |
| --- | --- |
| Inputs | variable names, types, defaults, validation rules |
| Outputs | output names, types, and expected meaning |
| Behavior | resources created, naming model, tagging rules, scaling model |
| State safety | resource addresses, moved blocks, upgrade behavior |
| Operational contract | required IAM permissions, secrets access pattern, rollback expectations |

Inputs
This is everything the caller passes into the module:

```hcl
module "network" {
  source = "..."

  project_name = "lab72-dev"
  environment  = "dev"
  web_ami_id   = "ami-..."
}
```

The API here includes:

- variable names;
- types;
- defaults;
- validation rules;
- required/optional status.

If you remove an input or turn an optional input into a required input, you can break the caller.

Outputs
This is what the module exposes to the outside:

```hcl
output "web_asg_name" {
  value = aws_autoscaling_group.web.name
}
```

If external code uses this:

```hcl
module.network.web_asg_name
```

then renaming the output breaks that code.

Behavior
Even if variables and outputs do not change, the module can start behaving differently:

- desired_capacity was 2;
- desired_capacity became 1.

- ALB was public;
- ALB became internal.

- one naming scheme was used;
- another naming scheme is now used.

This is also part of the contract because the caller expects certain behavior.

State safety
Terraform is tied to resource addresses:

```text
aws_lb.app
aws_autoscaling_group.web
aws_security_group.web
```

If you rename a resource without a moved block, Terraform may decide to:

- delete the old resource;
- create a new resource.

For the caller, this can be a breaking change even if variables and outputs did not change.

Operational contract
The module also promises operational behavior:

- which IAM permissions are required;
- how secrets are read;
- what rollback path exists;
- which tags are required;
- which policy gates must pass.

For example, if a new module version suddenly requires `iam:CreateRole`, while the previous version did not, that is an important change.

A module version is a promise to callers. If a caller can upgrade without changing inputs and gets a surprising plan, treat the change as breaking.

---

## 6. Version Classification

Use this table for module changes.

| Version type | Meaning for Terraform modules | Examples |
| --- | --- | --- |
| Patch `v1.0.1` | safe bug fix, no caller behavior surprise | fix validation message, docs typo, missing tag on a resource |
| Minor `v1.1.0` | backward-compatible feature | add optional variable with safe default, add output, add stricter test that does not reject valid old callers |
| Major `v2.0.0` | breaking change | rename output, change output type, make optional variable required, change default capacity, remove an input |

Useful rule:

```text
If existing callers must change code or should expect real infrastructure behavior changes, it is major.
```

Examples:

| Change | Version |
| --- | --- |
| Add `alb_zone_id` output | minor |
| Rename `web_asg_name` output | major |
| Add optional `enable_alb_access_logs = false` | minor |
| Make `web_ami_id` optional with unsafe default | major or rejected design |
| Fix a typo in README | patch |
| Change `web_desired_capacity` default from `2` to `1` | major |

---

## 7. Tag Scheme

Use module-scoped tags:

```text
network/v1.0.0
network/v1.1.0
network/v2.0.0
```

Do not use only this in a monorepo:

```text
v1.0.0
```

Why:

- `v1.0.0` does not say which module changed;
- `network/v1.0.0` is clear in release notes and promotion evidence;
- future modules can have their own streams, for example `observability/v1.0.0`.

Do not create the tag at this point. This section only defines the naming scheme. The actual tag command appears later in `Release Workflow`, after checks and commit.

Inspect an existing tag:

```bash
git show network/v1.0.0 --stat
git rev-parse network/v1.0.0
```

Hard rule:

```text
Do not move a published module tag. Create a new version instead.
```

---

## 8. Pin Module Versions In Env Roots

The lab starts with local sources so you can validate and test without a remote tag:

```hcl
source = "../../modules/network"
```

For release discipline, replace the local source with a pinned Git source after the tag exists:

```hcl
module "network" {
  source = "git::https://github.com/VlrRbn/DevOps.git//lessons/72-module-versioning-and-release-discipline/lab_72/terraform/modules/network?ref=network/v1.0.0"

  project_name = "lab72-dev"
  environment  = "dev"
}
```

Important details:

- `?ref=network/v1.0.0` pins the module to a tag;
- changing the ref requires `terraform init -upgrade` or a clean init;
- prod should not use `main` as the module ref;
- each environment can temporarily use a different module version during promotion.

Version matrix example:

| Environment | Module version | Status |
| --- | --- | --- |
| dev | `network/v1.1.0` | testing |
| stage | `network/v1.0.0` | stable |
| prod | `network/v1.0.0` | stable |

---

## 9. Release Workflow

### Step 1. Baseline `network/v1.0.0`


> Important: Git tags and `module-release-note.sh` only work with content that is already in a Git commit.
> Untracked files, unstaged changes, and staged-but-not-committed changes are not included in `git diff network/v1.0.0 HEAD`.
> If the release note is empty, check `git status` first: the baseline or module change may not be committed yet.

Run tests first. Create the first tag only after the baseline code is committed and checks are green:

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

After successful checks and a clean commit, tag:

```bash
git tag -a network/v1.0.0 -m "network module v1.0.0"
git push origin network/v1.0.0
```

### Step 2. Pin env roots to `network/v1.0.0`

Update `dev`, `stage`, and `prod` module sources to use the tag.

Check refs:

```bash
for env in dev stage prod; do
  lessons/72-module-versioning-and-release-discipline/scripts/check-module-version.sh \
    "lessons/72-module-versioning-and-release-discipline/lab_72/terraform/envs/${env}" \
    "network/v1.0.0"
done
```

### Step 3. Make a non-breaking module change

Example minor change:

```hcl
output "alb_zone_id" {
  value       = aws_lb.app.zone_id
  description = "ALB hosted zone ID for DNS automation."
}
```

This is minor because existing callers do not need to change.

### Step 4. Generate release note

Before `network/v1.1.0` exists, the new release ref does not exist yet. For pre-release review, compare the previous release with the current candidate commit, `HEAD`:

```bash
lessons/72-module-versioning-and-release-discipline/scripts/module-release-note.sh \
  network \
  v1.1.0 \
  network/v1.0.0 \
  HEAD \
  > /tmp/release-note-network-v1.1.0.md
```

Argument meaning:

```text
network         module being checked
v1.1.0          new SemVer version without module prefix
network/v1.0.0  previous release snapshot
HEAD            current candidate commit before tag creation
```

After the tag exists, generate final proof tag-to-tag:

```bash
lessons/72-module-versioning-and-release-discipline/scripts/module-release-note.sh \
  network \
  v1.1.0 \
  network/v1.0.0 \
  network/v1.1.0 \
  > /tmp/release-note-network-v1.1.0.md
```

Short rule:

```text
HEAD = release candidate before tag
network/v1.1.0 = published release snapshot after tag
```

### Step 5. Update changelog and tag `network/v1.1.0`

Update `CHANGELOG.md`, then tag:

```bash
git tag -a network/v1.1.0 -m "network module v1.1.0"
git push origin network/v1.1.0
```

### Step 6. Upgrade dev first

Change only `dev` to:

```text
dev: ref=network/v1.1.0
stage: ref=network/v1.0.0
prod: ref=network/v1.0.0
```

Command:

```text
sed -i 's/ref=network\/v1.0.0/ref=network\/v1.1.0/' \
  lessons/72-module-versioning-and-release-discipline/lab_72/terraform/envs/dev/main.tf
```

Check:

```text
rg -n 'ref=network/v1.[01].0' \
  lessons/72-module-versioning-and-release-discipline/lab_72/terraform/envs
```

Then in `dev`:

```bash
terraform init -upgrade -backend-config=backend.hcl
terraform plan
```

Expected:

- no unexpected replacement just because the module ref changed;
- new output appears if you added one;
- policy checks are clean;
- proof is captured before stage.

### Step 7. Promote the same version to stage and prod

After dev evidence is clean, move the same tag to stage. After stage evidence is clean, move the same tag to prod.

Do not promote a different commit under the same version. The whole point is that `network/v1.1.0` means one exact Git object.

---


## 9.1 Practical Flow

Use this order:

1. Run local checks while env roots still use `source = "../../modules/network"`.
2. Commit the clean baseline.
3. Create and push tag `network/v1.0.0`.
4. Replace module sources in env roots with Git URLs pinned to `network/v1.0.0`.
5. Make one backward-compatible module change.
6. Commit the module change, then run release checks and generate a release note.
7. Update `CHANGELOG.md`, then create and push tag `network/v1.1.0`.
8. Move `dev` to `network/v1.1.0`, review the plan, and capture evidence.
9. Promote the same tag to `stage`, then to `prod`.
10. Record rollback target `network/v1.0.0`.

In CI, input `release_version` is only the SemVer part, for example `v1.1.0`. The full module tag is built from `module_name/release_version`, for example `network/v1.1.0`.

---

## 10. CI Model - ci/lesson72-module-release.yml

This workflow does not assume AWS roles. That is intentional:

- module release checks should run before apply;
- Terraform native tests use provider mocks;
- no apply permission is needed to classify a module release.

The workflow checks:

1. explicit confirmation input;
2. exact workflow commit checkout;
3. Terraform format;
4. Packer format;
5. module native tests;
6. shell and OPA policy tests;
7. optional env root ref enforcement;
8. release note artifact;
9. GitHub Step Summary.

Use `enforce_env_refs=false` while the lab still uses local sources. Turn it on after env roots are pinned to Git tags.

---

## 11. Breaking Change Workflow

Example breaking change:

```text
rename output web_asg_name -> web_autoscaling_group_name
```

This requires a major release:

```text
network/v2.0.0
```

Before tagging a major release:

- update `CHANGELOG.md` with a `Breaking` section;
- update module tests;
- update all root callers or document required caller actions;
- generate a release note;
- prove rollback target;
- start promotion from dev.

Do not hide breaking changes in `network/v1.1.0`.

---

## 12. Rollback Model

Rollback means pinning an environment back to the previous known-good tag:

```text
network/v1.1.0 -> network/v1.0.0
```

In this lesson, rollback is not a revert of the whole Git repository. It is a targeted module ref change in one environment.

For example, if the issue exists only in `prod`, you do not need to revert the whole repo and you do not need to touch `dev` or `stage`. Change only the `prod` root module:

```hcl
source = "git::https://github.com/VlrRbn/DevOps.git//lessons/72-module-versioning-and-release-discipline/lab_72/terraform/modules/network?ref=network/v1.0.0"
```

Practical rollback for `prod`:

```bash
sed -i 's/ref=network\/v1.1.0/ref=network\/v1.0.0/' \
  lessons/72-module-versioning-and-release-discipline/lab_72/terraform/envs/prod/main.tf

cd lessons/72-module-versioning-and-release-discipline/lab_72/terraform/envs/prod
terraform init -reconfigure -upgrade -backend-config=backend.hcl
terraform plan
```

If the plan is expected, record the rollback as a normal commit:

```bash
cd /home/leprecha/DevOps
git add lessons/72-module-versioning-and-release-discipline/lab_72/terraform/envs/prod/main.tf
git commit -m "revert(l72): roll prod back to network v1.0.0"
git push origin main
```

Why not just use Git revert:

- Git revert cancels a codebase commit, while module rollback changes an environment dependency version;
- one Git commit may include docs, CI, changelog, and changes for multiple environments;
- the issue may exist only in `prod`, while `dev` and `stage` can stay on the newer version for investigation;
- tag `network/v1.0.0` points to exact known module code, not to an approximate old state;
- Terraform still needs to show the rollback plan before apply;
- a month later it is clear that `prod` was intentionally moved from `network/v1.1.0` back to `network/v1.0.0`.

Rollback still needs review:

```bash
terraform init -upgrade
terraform plan
```

Why review rollback?

- older module code can remove new outputs;
- defaults may differ;
- resources may move back to older behavior;
- rollback can still produce changes.

Rollback is a controlled promotion decision in the opposite direction.

---

## 13. Drills

### Drill 1. Baseline local lab

Run local checks while env roots still use local module paths.

Expected:

- fmt passes;
- Packer fmt passes;
- module tests pass;
- policy tests pass.

### Drill 2. Create `network/v1.0.0`

Create the first module tag from a clean commit.

Expected:

- tag exists;
- tag SHA is captured;
- changelog has the baseline entry.

### Drill 3. Pin all env roots to `network/v1.0.0`

Replace local module sources with Git sources pinned to the tag.

Expected:

- `check-module-version.sh` passes for dev/stage/prod;
- `terraform init -upgrade` is run after the source change.

### Drill 4. Release `network/v1.1.0`

Make one backward-compatible module change, update changelog, generate a release note, and tag.

Expected:

- tests pass;
- release note exists;
- change is classified as minor.

### Drill 5. Promote `v1.1.0`

Move `network/v1.1.0` through:

```text
dev -> stage -> prod
```

Expected:

- dev evidence exists before stage;
- stage evidence exists before prod;
- prod does not receive a different commit under the same tag.

### Drill 6. Breaking change classification

Simulate an output rename.

Expected:

- classified as major;
- tests or callers fail until updated;
- not released as `network/v1.1.0`.

### Drill 7. Rollback ref

Set dev back from `network/v1.1.0` to `network/v1.0.0`.

Expected:

- rollback plan reviewed;
- rollback target documented;
- post-rollback check captured.

---

## 14. Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `check-module-version.sh` says source is local | env root still uses `../../modules/network` | replace source with Git URL and `?ref=...` after tag exists |
| Terraform still uses old module code | module cache was not refreshed | run `terraform init -upgrade` or remove `.terraform/modules` |
| `git push origin network/v1.1.0` fails | tag already exists remotely | do not move it; create a corrected new version |
| prod plan changes unexpectedly | minor release contains behavior change | stop promotion, reclassify as major or fix module |
| rollback plan is not empty | rollback changes behavior too | review it like any other plan |
| CI ref check fails | expected ref input does not match env root | fix either the env root or workflow input |
| release note diff is empty | wrong previous/new refs or tag not fetched | use `fetch-depth: 0` in CI and verify refs locally |

---

## 15. Proof Pack

Capture evidence under an ignored local folder:

```text
lessons/72-module-versioning-and-release-discipline/evidence/l72-network-v1.1.0/
```

Minimum evidence:

- version matrix before and after promotion;
- `git show network/v1.0.0 --stat`;
- `git show network/v1.1.0 --stat`;
- release note for `network/v1.1.0`;
- changelog entry;
- Terraform native test output;
- policy test output;
- dev/stage/prod upgrade plans or CI artifacts;
- rollback target and rollback plan;
- final decision note.

Use `proof-pack.en.md` for the full checklist.

---

## 16. Acceptance Criteria

Lesson 72 is complete when:

- `network/v1.0.0` exists as a baseline tag;
- a backward-compatible `network/v1.1.0` release is documented;
- env roots can be pinned to Git refs;
- module tests pass before tagging;
- release notes and changelog exist;
- version promotion follows `dev -> stage -> prod`;
- a breaking change example is classified as major;
- rollback target is documented;
- proof pack is captured.

---

## 17. Lesson Summary

- **What you learned:** Terraform modules need release identity, not just reusable code.
- **What you practiced:** module-scoped Git tags, SemVer classification, changelog discipline, release note generation, env ref pinning, and rollback targeting.
- **Operational focus:** promote known module versions.
- **Why it matters:** multi-environment promotion is only trustworthy when the module artifact itself is versioned, tested, and reproducible.
