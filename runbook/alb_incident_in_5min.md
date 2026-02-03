# Runbook: ALB Incident in 5 Minutes (No SSH)

## 1) Confirm target health
aws elbv2 describe-target-health --target-group-arn "$TG_ARN" \
  --query 'TargetHealthDescriptions[].{id:Target.Id,state:TargetHealth.State,reason:TargetHealth.Reason,desc:TargetHealth.Description}' \
  --output table

## 2) Correlate with ASG activity
aws autoscaling describe-scaling-activities --auto-scaling-group-name "$ASG_NAME" \
  --query 'Activities[].{Time:StartTime,Status:StatusCode,Desc:Description,Cause:Cause}' \
  --output table

## 3) Decide based on metrics (AWS/ApplicationELB)
- HealthyHostCount (Minimum)
- UnHealthyHostCount (Maximum)
- TargetResponseTime
- HTTPCode_ELB_5XX_Count
- HTTPCode_Target_5XX_Count
- RequestCount

## 4) Actions
- Wrong path/matcher => fix TG health check
- Timeouts/latency => tune timeout or fix perf root cause
- Boot race/churn => increase warmup/grace + validate refresh
- 5xx during scale-in => increase deregistration_delay
- Cold instance pain => enable slow_start
