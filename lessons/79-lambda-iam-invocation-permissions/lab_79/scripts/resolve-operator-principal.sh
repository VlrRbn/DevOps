#!/usr/bin/env bash
set -Eeuo pipefail

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'missing required command: %s\n' "$1" >&2
    exit 1
  }
}

require_command aws

caller_arn="$(aws sts get-caller-identity --query Arn --output text)"

case "$caller_arn" in
  arn:aws:iam::*:role/* | arn:aws:iam::*:user/*)
    printf '%s\n' "$caller_arn"
    ;;
  arn:aws:sts::*:assumed-role/*)
    # STS returns a session ARN, but an IAM trust policy should name the
    # underlying IAM role ARN. get-role also restores an AWS SSO role path.
    role_and_session="${caller_arn#*:assumed-role/}"
    role_name="${role_and_session%%/*}"
    aws iam get-role --role-name "$role_name" --query Role.Arn --output text
    ;;
  *)
    printf 'unsupported caller ARN: %s\n' "$caller_arn" >&2
    exit 1
    ;;
esac
