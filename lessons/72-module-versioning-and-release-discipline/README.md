# Lesson 72: Module Versioning & Release Discipline

This lesson continues lesson 71. Lesson 71 promoted infrastructure changes across `dev -> stage -> prod`; lesson 72 adds release identity for the shared Terraform module itself.

The core idea: do not promote an unnamed module checkout. Promote a known module release with a tag, changelog entry, compatibility decision, tests, and rollback target.

## What Is Included

- `lesson.en.md` and `lesson.ru.md` - full lesson text
- `TAGS.md` - practical Git tag command guide
- `proof-pack.en.md` and `proof-pack.ru.md` - evidence checklist for module releases
- `CHANGELOG.md` - module changelog example
- `scripts/check-module-version.sh` - checks whether an env root is pinned to an expected Git ref
- `scripts/module-release-note.sh` - generates a review note from Git diff
- `ci/lesson72-module-release.yml` - GitHub Actions template for module release checks
- `policies/` - reused JSON plan policy gate from previous lessons
- `lab_72/terraform/envs/dev` - dev root module
- `lab_72/terraform/envs/stage` - stage root module
- `lab_72/terraform/envs/prod` - prod root module
- `lab_72/terraform/modules/network` - shared module to version and promote

## Relationship To Lesson 71

Lesson 71 answered: where does a change go?

```text
dev -> stage -> prod
```

Lesson 72 answers: what exact module release is moving?

```text
network/v1.0.0 -> network/v1.1.0
```

Production promotion needs both. Environment approval without module versioning still leaves ambiguity about what code was applied.

## Lab Model

The lab starts with local module sources so Terraform validation and native tests can run without depending on a remote Git tag:

```hcl
source = "../../modules/network"
```

During the versioning drill, replace that with a pinned Git source after creating the module tag:

```hcl
source = "git::https://github.com/VlrRbn/DevOps.git//lessons/72-module-versioning-and-release-discipline/lab_72/terraform/modules/network?ref=network/v1.0.0"
```

That edit is intentional. It is the point of the lesson: turn a local development module into a reproducible release dependency.

## Recommended Tag Format

Use module-scoped tags because this is a monorepo:

```text
network/v1.0.0
network/v1.1.0
network/v2.0.0
```

Do not use only `v1.0.0`; it does not say which module was released.

## Practical Flow

Important: Git tags and `module-release-note.sh` only compare committed Git objects. If `lab_72` is untracked or the module change is not committed, the release note can be empty even though files exist on disk. Check `git status` before tagging or generating release notes.

Use this order when running the lesson:

1. Run local checks while env roots still use `source = "../../modules/network"`.
2. Commit the clean baseline.
3. Create and push `network/v1.0.0`.
4. Replace env root module sources with Git URLs pinned to `network/v1.0.0`.
5. Make one backward-compatible module change.
6. Commit the module change, then run release checks and generate the release note.
7. Update `CHANGELOG.md`, then create and push `network/v1.1.0`.
8. Move `dev` to `network/v1.1.0`, review the plan, and capture evidence.
9. Move the same tag to `stage`, then to `prod`.
10. Document rollback target `network/v1.0.0`.

The CI input `release_version` is only the SemVer part, for example `v1.1.0`. The full module tag is `module_name/release_version`, for example `network/v1.1.0`.

For tag commands and checks, use `TAGS.md`.

## Quick Local Checks

From repo root:

```bash
terraform fmt -check -recursive lessons/72-module-versioning-and-release-discipline/lab_72/terraform
packer fmt -check -recursive lessons/72-module-versioning-and-release-discipline/lab_72/packer
lessons/72-module-versioning-and-release-discipline/policies/test-policy.sh
lessons/72-module-versioning-and-release-discipline/policies/test-opa.sh
```

Run module tests:

```bash
TF_DATA_DIR=/tmp/l72-module-test-data \
terraform -chdir=lessons/72-module-versioning-and-release-discipline/lab_72/terraform/modules/network \
  init -backend=false -input=false -no-color

TF_DATA_DIR=/tmp/l72-module-test-data \
terraform -chdir=lessons/72-module-versioning-and-release-discipline/lab_72/terraform/modules/network \
  test -no-color
```

Validate env roots without touching remote state:

```bash
for env in dev stage prod; do
  TF_DATA_DIR="/tmp/l72-${env}-data" \
  terraform -chdir="lessons/72-module-versioning-and-release-discipline/lab_72/terraform/envs/${env}" \
    init -backend=false -input=false -no-color

  TF_DATA_DIR="/tmp/l72-${env}-data" \
  terraform -chdir="lessons/72-module-versioning-and-release-discipline/lab_72/terraform/envs/${env}" \
    validate -no-color
done
```

## CI Template

`ci/lesson72-module-release.yml` is a template. Copy it to `.github/workflows/lesson72-module-release.yml` when you want GitHub Actions checks.

The workflow deliberately avoids AWS credentials. It checks module release quality before any environment apply:

1. Terraform format
2. Packer format
3. module native tests
4. policy unit tests
5. optional env root module-ref checks
6. release note artifact generation
7. GitHub Step Summary

## Proof Pack

Save release evidence under an ignored local folder, for example:

```text
lessons/72-module-versioning-and-release-discipline/evidence/l72-network-v1.1.0/
```

Do not commit raw plan JSON or environment-specific evidence unless it is intentionally redacted.

## Safety Rules

- Do not move a published tag.
- Do not let prod float on `main`.
- Do not release breaking changes as minor versions.
- Do not skip `dev -> stage -> prod` just because a module tag exists.
- Do not apply rollback without reviewing the rollback plan.
