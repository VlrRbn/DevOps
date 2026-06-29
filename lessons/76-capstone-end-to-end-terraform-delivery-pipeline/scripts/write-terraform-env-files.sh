#!/usr/bin/env bash
set -Eeuo pipefail

# Why this exists:
# - backend.hcl and terraform.tfvars are intentionally ignored by git;
# - GitHub Actions runners start from a clean checkout and cannot rely on local files;
# - CI should build temporary config from GitHub Variables/Secrets and upload only
#   reviewed operational artifacts.
#
# The script writes:
# - backend.hcl: S3 backend config for the selected environment;
# - terraform.auto.tfvars: non-secret Terraform inputs used by plan/apply.
#
# Required environment variables:
# - TF_STATE_BUCKET
# - TF_WEB_AMI_ID
# - TF_SSM_PROXY_AMI_ID
# - TF_GITHUB_OIDC_PROVIDER_ARN
#
# Optional environment variables:
# - AWS_REGION, default eu-west-1
# - TF_GITHUB_OWNER, default parsed from GITHUB_REPOSITORY
# - TF_GITHUB_REPO, default parsed from GITHUB_REPOSITORY
# - TF_ENV_DIR, default lab_76/terraform/envs/<target_env>

usage() {
  cat >&2 <<'USAGE'
Usage:
  write-terraform-env-files.sh <dev|stage|prod>

Example:
  AWS_REGION=eu-west-1 \
  TF_STATE_BUCKET=my-tfstate-bucket \
  TF_WEB_AMI_ID=ami-0123456789abcdef0 \
  TF_SSM_PROXY_AMI_ID=ami-0123456789abcdef0 \
  TF_GITHUB_OWNER=VlrRbn \
  TF_GITHUB_REPO=DevOps \
  TF_GITHUB_OIDC_PROVIDER_ARN=arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com \
  write-terraform-env-files.sh dev
USAGE
}

TARGET_ENV="${1:-}"
case "$TARGET_ENV" in
  dev|stage|prod) ;;
  -h|--help) usage; exit 0 ;;
  *) usage; exit 64 ;;
esac

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LESSON_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
ENV_DIR="${TF_ENV_DIR:-${LESSON_DIR}/lab_76/terraform/envs/${TARGET_ENV}}"

AWS_REGION="${AWS_REGION:-eu-west-1}"
TF_STATE_BUCKET="${TF_STATE_BUCKET:-}"
TF_WEB_AMI_ID="${TF_WEB_AMI_ID:-}"
TF_SSM_PROXY_AMI_ID="${TF_SSM_PROXY_AMI_ID:-}"
TF_GITHUB_OIDC_PROVIDER_ARN="${TF_GITHUB_OIDC_PROVIDER_ARN:-}"

if [[ -z "$TF_STATE_BUCKET" ]]; then
  echo "TF_STATE_BUCKET is required" >&2
  exit 64
fi
if [[ -z "$TF_WEB_AMI_ID" ]]; then
  echo "TF_WEB_AMI_ID is required" >&2
  exit 64
fi
if [[ -z "$TF_SSM_PROXY_AMI_ID" ]]; then
  echo "TF_SSM_PROXY_AMI_ID is required" >&2
  exit 64
fi
if [[ -z "$TF_GITHUB_OIDC_PROVIDER_ARN" ]]; then
  echo "TF_GITHUB_OIDC_PROVIDER_ARN is required" >&2
  exit 64
fi

# GitHub Actions exposes owner/repo as GITHUB_REPOSITORY=owner/repo. Keep explicit variables available so
# local drills and forks can override the values cleanly.
github_repository="${GITHUB_REPOSITORY:-}"
if [[ -z "${TF_GITHUB_OWNER:-}" ]]; then
  TF_GITHUB_OWNER="${github_repository%%/*}"
fi
if [[ -z "${TF_GITHUB_REPO:-}" ]]; then
  TF_GITHUB_REPO="${github_repository#*/}"
fi
if [[ -z "$TF_GITHUB_OWNER" || -z "$TF_GITHUB_REPO" || "$TF_GITHUB_OWNER" == "$github_repository" || "$TF_GITHUB_REPO" == "$github_repository" ]]; then
  echo "TF_GITHUB_OWNER and TF_GITHUB_REPO are required when GITHUB_REPOSITORY is not set to owner/repo" >&2
  exit 64
fi

case "$TARGET_ENV" in
  dev)
    project_name="lab76-dev"
    vpc_cidr="10.76.0.0/16"
    public_subnets='["10.76.1.0/24", "10.76.2.0/24"]'
    private_subnets='["10.76.11.0/24", "10.76.12.0/24"]'
    enable_web_ssm="true"
    web_min_size=1
    web_desired_capacity=1
    web_max_size=2
    asg_min_healthy_percentage=50
    asg_instance_warmup_seconds=120
    asg_checkpoint_delay_seconds=180
    tg_slow_start_seconds=60
    health_check_healthy_threshold=2
    criticality="low"
    ;;
  stage)
    project_name="lab76-stage"
    vpc_cidr="10.77.0.0/16"
    public_subnets='["10.77.1.0/24", "10.77.2.0/24"]'
    private_subnets='["10.77.11.0/24", "10.77.12.0/24"]'
    enable_web_ssm="true"
    web_min_size=2
    web_desired_capacity=2
    web_max_size=3
    asg_min_healthy_percentage=50
    asg_instance_warmup_seconds=120
    asg_checkpoint_delay_seconds=360
    tg_slow_start_seconds=60
    health_check_healthy_threshold=2
    criticality="medium"
    ;;
  prod)
    project_name="lab76-prod"
    vpc_cidr="10.78.0.0/16"
    public_subnets='["10.78.1.0/24", "10.78.2.0/24"]'
    private_subnets='["10.78.11.0/24", "10.78.12.0/24"]'
    enable_web_ssm="false"
    web_min_size=2
    web_desired_capacity=2
    web_max_size=4
    asg_min_healthy_percentage=100
    asg_instance_warmup_seconds=180
    asg_checkpoint_delay_seconds=600
    tg_slow_start_seconds=120
    health_check_healthy_threshold=3
    criticality="high"
    ;;
esac

mkdir -p "$ENV_DIR"

cat > "${ENV_DIR}/backend.hcl" <<BACKEND
bucket       = "${TF_STATE_BUCKET}"
key          = "lab76/${TARGET_ENV}/full/terraform.tfstate"
region       = "${AWS_REGION}"
encrypt      = true
use_lockfile = true
BACKEND

cat > "${ENV_DIR}/terraform.auto.tfvars" <<TFVARS
aws_region   = "${AWS_REGION}"
project_name = "${project_name}"
environment  = "${TARGET_ENV}"

vpc_cidr             = "${vpc_cidr}"
public_subnet_cidrs  = ${public_subnets}
private_subnet_cidrs = ${private_subnets}

enable_ssm_vpc_endpoints = true
enable_web_ssm           = ${enable_web_ssm}

web_ami_id       = "${TF_WEB_AMI_ID}"
ssm_proxy_ami_id = "${TF_SSM_PROXY_AMI_ID}"

web_min_size         = ${web_min_size}
web_desired_capacity = ${web_desired_capacity}
web_max_size         = ${web_max_size}

asg_min_healthy_percentage     = ${asg_min_healthy_percentage}
asg_instance_warmup_seconds    = ${asg_instance_warmup_seconds}
asg_checkpoint_delay_seconds   = ${asg_checkpoint_delay_seconds}
tg_slow_start_seconds          = ${tg_slow_start_seconds}
health_check_healthy_threshold = ${health_check_healthy_threshold}
instance_type_web              = "t3.micro"

github_owner             = "${TF_GITHUB_OWNER}"
github_repo              = "${TF_GITHUB_REPO}"
github_branch            = "main"
github_apply_environment = "terraform-${TARGET_ENV}"
github_oidc_provider_arn = "${TF_GITHUB_OIDC_PROVIDER_ARN}"

tf_state_bucket_name = "${TF_STATE_BUCKET}"
tf_state_key         = "lab76/${TARGET_ENV}/full/terraform.tfstate"

demo_api_token_parameter_name = "/devops/lab76/${TARGET_ENV}/demo/api-token"
demo_app_secret_name          = "/devops/lab76/${TARGET_ENV}/demo/app-secret"

common_tags = {
  Owner       = "DevOpsTrack"
  Criticality = "${criticality}"
}
TFVARS

echo "Wrote ${ENV_DIR}/backend.hcl"
echo "Wrote ${ENV_DIR}/terraform.auto.tfvars"
