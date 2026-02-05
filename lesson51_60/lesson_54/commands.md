# lab_54 Terraform — AWS CLI Commands (Quick View)

## Preconditions
Set these once (adjust values for your env):

```bash
export PROJECT="lab54"
export ALB_DNS="internal-...elb.amazonaws.com"
export TG_ARN="arn:aws:elasticloadbalancing:...:targetgroup/..."
export TG_BLUE_ARN="arn:aws:elasticloadbalancing:...:targetgroup/..."
export TG_GREEN_ARN="arn:aws:elasticloadbalancing:...:targetgroup/..."
export ASG_NAME="lab54-web-asg"
export SSM_PROXY_ID="i-xxxxxxxxxxxxxxxxx"
```

---

## SSM port forwarding

```bash
aws ssm start-session \
  --target "$SSM_PROXY_ID" \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["80"],"localPortNumber":["8080"]}'
```

If you need ALB DNS via proxy:

```bash
aws ssm start-session \
  --target "$SSM_PROXY_ID" \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters '{"host":["'$ALB_DNS'"],"portNumber":["80"],"localPortNumber":["8080"]}'
```

---

## EC2 discovery

```bash
aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=$PROJECT" "Name=instance-state-name,Values=running" \
  --query "Reservations[].Instances[].{Id:InstanceId,Name:Tags[?Key=='Name']|[0].Value,Role:Tags[?Key=='Role']|[0].Value,PrivIP:PrivateIpAddress,Subnet:SubnetId}" \
  --output table
```

---

## Target group health + config

```bash
aws elbv2 describe-target-groups \
  --target-group-arns "$TG_ARN" \
  --query 'TargetGroups[0].{Path:HealthCheckPath,Interval:HealthCheckIntervalSeconds,Timeout:HealthCheckTimeoutSeconds,HealthyThr:HealthyThresholdCount,UnhealthyThr:UnhealthyThresholdCount,Matcher:Matcher}' \
  --output table
```

```bash
aws elbv2 describe-target-health \
  --target-group-arn "$TG_ARN" \
  --query 'TargetHealthDescriptions[].{Id:Target.Id,State:TargetHealth.State,Reason:TargetHealth.Reason,Desc:TargetHealth.Description}' \
  --output table
```

Blue/Green health:

```bash
aws elbv2 describe-target-health \
  --target-group-arn "$TG_BLUE_ARN" \
  --query 'TargetHealthDescriptions[].{Id:Target.Id,State:TargetHealth.State,Reason:TargetHealth.Reason,Desc:TargetHealth.Description}' \
  --output table

aws elbv2 describe-target-health \
  --target-group-arn "$TG_GREEN_ARN" \
  --query 'TargetHealthDescriptions[].{Id:Target.Id,State:TargetHealth.State,Reason:TargetHealth.Reason,Desc:TargetHealth.Description}' \
  --output table
```

---

## ASG refresh and status

```bash
aws autoscaling start-instance-refresh \
  --auto-scaling-group-name "$ASG_NAME" \
  --preferences '{"MinHealthyPercentage":50,"InstanceWarmup":60}'
```

```bash
aws autoscaling describe-instance-refreshes \
  --auto-scaling-group-name "$ASG_NAME" \
  --query 'InstanceRefreshes[0].{Status:Status,Percentage:PercentageComplete,StartTime:StartTime,StatusReason:StatusReason}' \
  --output table
```

```bash
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$ASG_NAME" \
  --query 'AutoScalingGroups[0].{HealthCheckType:HealthCheckType,Grace:HealthCheckGracePeriod,Min:MinSize,Desired:DesiredCapacity,Max:MaxSize,Instances:Instances[].{Id:InstanceId,Health:HealthStatus,Lifecycle:LifecycleState}}' \
  --output table
```

```bash
aws autoscaling describe-scaling-activities \
  --auto-scaling-group-name "$ASG_NAME" \
  --query 'Activities[].{Time:StartTime,Status:StatusCode,Desc:Description,Cause:Cause}' \
  --output table
```

---

## ALB / TG attributes

```bash
aws elbv2 describe-target-group-attributes \
  --target-group-arn "$TG_ARN" \
  --query 'Attributes[].{Key:Key,Value:Value}' \
  --output table
```

```bash
aws elbv2 modify-target-group-attributes \
  --target-group-arn "$TG_ARN" \
  --attributes Key=deregistration_delay.timeout_seconds,Value=60
```

```bash
aws elbv2 modify-target-group-attributes \
  --target-group-arn "$TG_ARN" \
  --attributes Key=slow_start.duration_seconds,Value=60
```

---

## List outputs (Terraform)

```bash
cd lesson51_60/lesson_54/lab_54/terraform/envs
terraform output
```

```bash
cd lesson51_60/lesson_54/lab_54/terraform/envs
terraform output -raw alb_dns_name
```

---

## Optional: quick HTTP check via local port forward

```bash
curl -I "http://127.0.0.1:8080/" | head
```
