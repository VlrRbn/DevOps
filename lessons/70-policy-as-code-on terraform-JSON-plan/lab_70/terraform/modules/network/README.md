# Network Module Contract

This module owns the lesson lab_70 network and application runtime surface.

## Input Contract

| Input | Contract |
| --- | --- |
| `aws_region` | AWS region-shaped string, for example `eu-west-1` |
| `project_name` | lowercase kebab-style, starts with a letter, 3-31 characters |
| `environment` | lowercase environment name, starts with a letter, 2-21 characters |
| `vpc_cidr` | valid IPv4 CIDR |
| `public_subnet_cidrs` | 2-6 unique valid IPv4 CIDRs |
| `private_subnet_cidrs` | 2-6 unique valid IPv4 CIDRs |
| `instance_type_web` | EC2 instance type for web instances; default is `t3.micro` |
| `enable_ssm_vpc_endpoints` | boolean; creates private interface endpoints for Session Manager and runtime secret reads |
| `enable_web_ssm` | boolean; allows web instances to reach private interface endpoints when debugging is required |
| `web_ami_id` | AMI-shaped ID, for example `ami-0123456789abcdef0` |
| `ssm_proxy_ami_id` | AMI-shaped ID, explicit and separate from `web_ami_id` |
| `tg_slow_start_seconds` | target group slow start, 30-900 seconds |
| `health_check_healthy_threshold` | target group healthy threshold, 2-10 successful checks |
| `web_min_size` | ASG minimum capacity, at least 1 |
| `web_max_size` | ASG maximum capacity, at least 1 |
| `web_desired_capacity` | must be between `web_min_size` and `web_max_size` |
| `asg_min_healthy_percentage` | ASG refresh minimum healthy percentage, 0-100 |
| `asg_instance_warmup_seconds` | ASG instance warmup, at least 30 seconds |
| `asg_checkpoint_delay_seconds` | ASG checkpoint delay, at least 30 seconds |
| `common_tags` | optional non-empty tags; reserved governance keys cannot be supplied by callers |
| `github_owner` | GitHub owner name used in the OIDC trust policy |
| `github_repo` | GitHub repository name used in the OIDC trust policy |
| `github_branch` | non-empty branch name allowed to assume the plan role |
| `github_apply_environment` | non-empty GitHub Environment name allowed to assume the apply role |
| `tf_state_bucket_name` | S3 bucket-shaped name used by the plan role policy |
| `tf_state_key` | non-empty relative state object key |
| `demo_api_token_parameter_name` | absolute SSM parameter path; plaintext value is not read by Terraform |
| `demo_app_secret_name` | absolute Secrets Manager path; plaintext value is not read by Terraform |

## Output Contract

| Output | Consumer | Stability |
| --- | --- | --- |
| `vpc_id` | diagnostics, AWS CLI lookups | stable string |
| `public_subnet_ids` | diagnostics and proof packs | stable ordered list |
| `private_subnet_ids` | diagnostics and proof packs | stable ordered list |
| `security_groups` | diagnostics, access checks, and proof packs | stable object with named SG IDs |
| `azs` | diagnostics and subnet placement proof | stable ordered list |
| `web_asg_name` | release and drift workflows | stable string |
| `web_asg_arn` | diagnostics and AWS CLI lookups | stable ARN string |
| `ssm_proxy_instance_id` | Session Manager commands and proof packs | stable instance ID string |
| `ssm_proxy_private_ip` | diagnostics and private connectivity checks | stable private IP string |
| `alb_dns_name` | SSM proxy and runtime checks | stable non-empty string |
| `alb_arn` | diagnostics and AWS CLI lookups | stable ARN string |
| `web_tg_arn` | health, release, and drift checks | stable ARN-shaped string |
| `ssm_vpc_endpoint_ids` | private runtime proof | stable map keyed by service |
| `tf_plan_role_arn` | GitHub Actions OIDC plan workflow setup | stable role ARN string |
| `tf_apply_role_arn` | GitHub Actions OIDC apply workflow setup | stable role ARN string |
| `demo_api_token_parameter_name` | runtime secret-read proof | metadata only, no plaintext secret value |
| `demo_app_secret_name` | runtime secret-read proof | metadata only, no plaintext secret value |

## GitHub OIDC Contract

This module exposes two separate GitHub Actions roles:

- `tf_plan_role_arn` is branch-scoped and intended for PR/plan workflows.
- `tf_apply_role_arn` is environment-scoped and intended only for approved apply workflows.

The apply role trust policy expects this OIDC subject shape:

```text
repo:<github_owner>/<github_repo>:environment:<github_apply_environment>
```

For this lab, the apply role uses a scoped inline policy instead of `AdministratorAccess`.
The policy is intentionally still pragmatic: some AWS APIs require `Resource = "*"` for Terraform refresh or mutation workflows, so the lesson narrows the action list, role trust, state key, and `iam:PassRole` boundary.

## Breaking Changes

Breaking changes require a note in the lesson or PR:

- renaming or removing an output
- changing an output type or shape
- changing a required input type
- changing a default that changes infrastructure behavior
- removing support for a previously valid mode
- changing resource addresses without a `moved` block

## Non-Breaking Changes

- adding an optional input with a safe default
- adding a new output
- tightening documentation without changing behavior
- adding validation that rejects values the module never safely supported

## Native Contract Tests

Native tests live in `tests/` and can be run from this module directory:

```bash
terraform init -backend=false
terraform test -test-directory=tests -no-color
```

The tests use `mock_provider "aws"` so they validate the module contract without creating real AWS resources.

Current coverage:

- valid contract inputs reach plan
- invalid `project_name` fails
- invalid `web_ami_id` fails
- single private subnet fails
- too many private subnets fail
- duplicate private subnet CIDRs fail
- malformed private subnet CIDR fails
- invalid `ssm_proxy_ami_id` fails
- empty tag value fails
- reserved governance tag override fails
- invalid health check threshold fails
- absolute `tf_state_key` fails
- stable output contract remains available
- `ssm_vpc_endpoint_ids` remains a map keyed by service
- `tf_apply_role_arn` remains available for the controlled apply workflow
