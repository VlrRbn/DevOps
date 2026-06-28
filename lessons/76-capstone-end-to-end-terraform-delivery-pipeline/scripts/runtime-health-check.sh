#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

usage() {
  cat >&2 <<'USAGE'
Usage:
  runtime-health-check.sh <dev|stage|prod>

Collects read-only runtime health evidence after recovery.
It checks ALB target health, ASG instance health, and CloudWatch alarm states.
It does not modify infrastructure or Terraform state.

Exit codes:
  0 = runtime health looks healthy or only warnings were found
  1 = evidence collection failed
  2 = runtime health is unhealthy
USAGE
}

ENV_NAME="${1:-}"
case "$ENV_NAME" in
  dev|stage|prod) ;;
  *) usage; exit 64 ;;
esac

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LESSON_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
ROOT="${LESSON_DIR}/lab_74/terraform/envs/${ENV_NAME}"
STAMP="$(date -u +%Y%m%d_%H%M%S)"
OUT_DIR="${OUT_DIR:-${LESSON_DIR}/evidence/runtime-health-${ENV_NAME}-${STAMP}}"

if [[ ! -d "$ROOT" ]]; then
  echo "Terraform root not found: $ROOT" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
cd "$ROOT"

if ! command -v jq >/dev/null 2>&1; then
  echo "Missing required command: jq" >&2
  exit 1
fi

terraform version > "${OUT_DIR}/terraform-version.txt" 2>&1
git rev-parse HEAD > "${OUT_DIR}/git-sha.txt" 2>&1 || true
git status --short > "${OUT_DIR}/git-status.txt" 2>&1 || true

read_output() {
  local name="$1"
  terraform output -raw "$name" 2> "${OUT_DIR}/terraform-output-${name}-stderr.txt"
}

project_name="$(read_output project_name)" || {
  echo "Failed to read Terraform output: project_name" >&2
  exit 1
}
web_tg_arn="$(read_output web_tg_arn)" || {
  echo "Failed to read Terraform output: web_tg_arn" >&2
  exit 1
}
web_asg_name="$(read_output web_asg_name)" || {
  echo "Failed to read Terraform output: web_asg_name" >&2
  exit 1
}
alb_dns_name="$(read_output alb_dns_name)" || {
  echo "Failed to read Terraform output: alb_dns_name" >&2
  exit 1
}

cat > "${OUT_DIR}/runtime-inputs.txt" <<INPUTS
environment=${ENV_NAME}
timestamp_utc=${STAMP}
terraform_root=${ROOT}
project_name=${project_name}
web_tg_arn=${web_tg_arn}
web_asg_name=${web_asg_name}
alb_dns_name=${alb_dns_name}
INPUTS

region_args=()
if [[ -n "${AWS_REGION:-}" ]]; then
  region_args=(--region "$AWS_REGION")
elif [[ -n "${AWS_DEFAULT_REGION:-}" ]]; then
  region_args=(--region "$AWS_DEFAULT_REGION")
fi

aws "${region_args[@]}" sts get-caller-identity --output json > "${OUT_DIR}/aws-caller-identity.json"

set +e
aws "${region_args[@]}" elbv2 describe-target-health \
  --target-group-arn "$web_tg_arn" \
  --output json > "${OUT_DIR}/target-health.json" 2> "${OUT_DIR}/target-health-stderr.txt"
target_health_ec=$?
set -e
echo "$target_health_ec" > "${OUT_DIR}/target-health-exitcode.txt"

target_status="ERROR"
target_count="0"
unhealthy_targets="UNKNOWN"
if [[ "$target_health_ec" -eq 0 ]]; then
  jq -r '.TargetHealthDescriptions[].TargetHealth.State' \
    "${OUT_DIR}/target-health.json" > "${OUT_DIR}/target-health-states.txt"
  target_count="$(jq -r '.TargetHealthDescriptions | length' "${OUT_DIR}/target-health.json")"
  unhealthy_targets="$(jq -r '[.TargetHealthDescriptions[].TargetHealth.State | select(. != "healthy")] | length' "${OUT_DIR}/target-health.json")"

  if [[ "$target_count" -eq 0 ]]; then
    target_status="NO_TARGETS"
    unhealthy_targets="0"
  elif [[ "$unhealthy_targets" -eq 0 ]]; then
    target_status="HEALTHY"
  else
    target_status="UNHEALTHY"
  fi
fi

set +e
aws "${region_args[@]}" autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$web_asg_name" \
  --output json > "${OUT_DIR}/asg.json" 2> "${OUT_DIR}/asg-stderr.txt"
asg_ec=$?
set -e
echo "$asg_ec" > "${OUT_DIR}/asg-exitcode.txt"

asg_status="ERROR"
asg_instance_count="0"
asg_bad_instances="UNKNOWN"
if [[ "$asg_ec" -eq 0 ]]; then
  jq -r '.AutoScalingGroups[0].Instances[]? | "\(.InstanceId):\(.LifecycleState):\(.HealthStatus)"' \
    "${OUT_DIR}/asg.json" > "${OUT_DIR}/asg-instances.txt"
  asg_instance_count="$(jq -r '(.AutoScalingGroups[0].Instances // []) | length' "${OUT_DIR}/asg.json")"
  asg_bad_instances="$(jq -r '[.AutoScalingGroups[0].Instances[]? | select(.LifecycleState != "InService" or .HealthStatus != "Healthy")] | length' "${OUT_DIR}/asg.json")"

  if [[ "$asg_instance_count" -eq 0 ]]; then
    asg_status="NO_INSTANCES"
    asg_bad_instances="0"
  elif [[ "$asg_bad_instances" -eq 0 ]]; then
    asg_status="HEALTHY"
  else
    asg_status="WARN"
  fi
fi

alarm_names=(
  "${project_name}-alb-unhealthy-hosts"
  "${project_name}-alb-5xx-critical"
  "${project_name}-target-5xx-critical"
  "${project_name}-release-target-5xx"
  "${project_name}-release-latency"
)

set +e
aws "${region_args[@]}" cloudwatch describe-alarms \
  --alarm-names "${alarm_names[@]}" \
  --output json > "${OUT_DIR}/cloudwatch-alarms.json" 2> "${OUT_DIR}/cloudwatch-alarms-stderr.txt"
alarms_ec=$?
set -e
echo "$alarms_ec" > "${OUT_DIR}/cloudwatch-alarms-exitcode.txt"

alarm_status="ERROR"
alarm_count="0"
alarm_alarm_count="UNKNOWN"
alarm_insufficient_count="UNKNOWN"
if [[ "$alarms_ec" -eq 0 ]]; then
  jq -r '.MetricAlarms[]? | "\(.AlarmName):\(.StateValue)"' \
    "${OUT_DIR}/cloudwatch-alarms.json" > "${OUT_DIR}/cloudwatch-alarm-states.txt"
  alarm_count="$(jq -r '(.MetricAlarms // []) | length' "${OUT_DIR}/cloudwatch-alarms.json")"
  alarm_alarm_count="$(jq -r '[.MetricAlarms[]? | select(.StateValue == "ALARM")] | length' "${OUT_DIR}/cloudwatch-alarms.json")"
  alarm_insufficient_count="$(jq -r '[.MetricAlarms[]? | select(.StateValue == "INSUFFICIENT_DATA")] | length' "${OUT_DIR}/cloudwatch-alarms.json")"

  if [[ "$alarm_count" -eq 0 ]]; then
    alarm_status="NO_ALARMS_FOUND"
    alarm_alarm_count="0"
    alarm_insufficient_count="0"
  elif [[ "$alarm_alarm_count" -gt 0 ]]; then
    alarm_status="ALARM"
  elif [[ "$alarm_insufficient_count" -gt 0 ]]; then
    alarm_status="WARN"
  else
    alarm_status="OK"
  fi
fi

overall_status="HEALTHY"
exit_code=0

if [[ "$target_status" == "ERROR" || "$asg_status" == "ERROR" || "$alarm_status" == "ERROR" ]]; then
  overall_status="ERROR"
  exit_code=1
elif [[ "$target_status" != "HEALTHY" || "$alarm_status" == "ALARM" ]]; then
  overall_status="UNHEALTHY"
  exit_code=2
elif [[ "$asg_status" == "WARN" || "$alarm_status" == "WARN" ]]; then
  overall_status="WARN"
  exit_code=0
fi

cat > "${OUT_DIR}/runtime-health-summary.txt" <<SUMMARY
environment=${ENV_NAME}
timestamp_utc=${STAMP}
terraform_root=${ROOT}
project_name=${project_name}
alb_dns_name=${alb_dns_name}
web_tg_arn=${web_tg_arn}
web_asg_name=${web_asg_name}
target_status=${target_status}
target_count=${target_count}
unhealthy_targets=${unhealthy_targets}
asg_status=${asg_status}
asg_instance_count=${asg_instance_count}
asg_bad_instances=${asg_bad_instances}
alarm_status=${alarm_status}
alarm_count=${alarm_count}
alarm_alarm_count=${alarm_alarm_count}
alarm_insufficient_count=${alarm_insufficient_count}
runtime_health_status=${overall_status}
SUMMARY

echo "RUNTIME_HEALTH_STATUS=${overall_status}"
echo "$OUT_DIR"
exit "$exit_code"
