#!/usr/bin/env bash
# Description: Start an SSM port-forwarding session to a web instance by tag.
# Usage: ssm-forward.sh [local_port] [remote_port]
# Notes: Requires AWS CLI, SSM Session Manager, and Role=web instance tag.
set -e

# Configuration
REGION="eu-west-1"
LOCAL_PORT="${1:-8080}"
REMOTE_PORT="${2:-80}"

# Find the instance ID of the web server ([0] ensures we get only one ID, but we and have only one ;)
WEB_INSTANCE_ID="$(aws ec2 describe-instances \
  --region "$REGION" \
  --filters "Name=tag:Role,Values=web" "Name=instance-state-name,Values=running" \
  --query "Reservations[].Instances[].InstanceId | [0]" \
  --output text)"

echo "Forward localhost:${LOCAL_PORT} -> ${WEB_INSTANCE_ID}:${REMOTE_PORT} (region ${REGION})"

# Start the port forwarding session
aws ssm start-session \
  --region "$REGION" \
  --target "$WEB_INSTANCE_ID" \
  --document-name AWS-StartPortForwardingSession \
  --parameters "portNumber=${REMOTE_PORT},localPortNumber=${LOCAL_PORT}"
