# Changelog

This changelog tracks Terraform module releases for lesson 72.

## network/v1.0.0 - 2026-06-10

### Added

- Initial `network` module release baseline.
- VPC, subnets, ALB, target group, ASG, SSM proxy, monitoring alarms, and GitHub OIDC roles.
- Native Terraform contract tests for inputs, outputs, and IAM role behavior.

### Changed

- None.

### Fixed

- None.

### Breaking

- None.

### Upgrade Notes

- First release. Pin environment roots to `network/v1.0.0` after the tag exists.

## network/v1.1.0 - 2026-06-10

### Added

- Added `alb_zone_id` output for DNS automation against the internal ALB.

### Changed

- No behavior change expected for existing callers.

### Fixed

- N/A.

### Breaking

- None.

### Upgrade Notes

- Run `terraform init -upgrade` after changing an env root module `ref`.
- Promote through `dev -> stage -> prod`.
- Capture the proof pack before promoting to the next environment.
- Existing callers do not need to change inputs.
- Do not move `network/v1.1.0` after publishing. If the release content is wrong, create a corrected `network/v1.1.1` or `network/v1.2.0`.
