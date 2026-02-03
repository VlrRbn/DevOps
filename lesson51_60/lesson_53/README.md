# Lesson 53: ALB Deep Dive

## Purpose
Understand how ALB decides traffic flow through health checks, target states, and traffic control features (deregistration delay, slow start). Build the ability to predict ALB behavior before testing.

## Prerequisites
- AWS account and credentials configured (`aws configure` or env vars).
- `aws` CLI installed.
- Access to an existing ALB + ASG stack (from lesson_50/51/52).

## Layout
- `lesson51_60/lesson_53/lesson_53.md`: main lesson content and exercises.
- `lesson51_60/lesson_53/alb_failure_modes.md`: cheat card for common ALB failure modes.
- `runbook/alb_incident_in_5min.md`: 5‑minute incident triage runbook (no SSH).

## What you will do
- Learn all target states and how ALB transitions between them.
- Break health checks intentionally and observe metrics.
- Trigger boot race and correlate ALB vs ASG behavior.
- Tune deregistration delay and observe draining.
- Understand when slow start is required.

## Required variables
You will need these for CLI commands:

```bash
export TG_ARN="arn:aws:elasticloadbalancing:...:targetgroup/..."
export ASG_NAME="lab50-web-asg"
export ALB_DNS="internal-...elb.amazonaws.com"
```

## Key metrics (AWS/ApplicationELB)
- `HealthyHostCount` (Minimum)
- `UnHealthyHostCount` (Maximum)
- `TargetResponseTime`
- `HTTPCode_ELB_5XX_Count`
- `HTTPCode_Target_5XX_Count`
- `RequestCount`

## Validation / Quick checks
- Target health state:
```bash
aws elbv2 describe-target-health --target-group-arn "$TG_ARN" \
  --query 'TargetHealthDescriptions[].{id:Target.Id,state:TargetHealth.State,reason:TargetHealth.Reason,desc:TargetHealth.Description}' \
  --output table
```

- ASG activity (churn/refresh):
```bash
aws autoscaling describe-scaling-activities --auto-scaling-group-name "$ASG_NAME" \
  --query 'Activities[].{Time:StartTime,Status:StatusCode,Desc:Description,Cause:Cause}' \
  --output table
```

## Expected outcome
You can explain:
- why ALB routes or stops routing traffic,
- how health checks drive target states,
- when failures are caused by checks vs real app issues,
- how traffic control features affect user experience.

## Notes
- ALB is the source of truth for user impact.
- Avoid SSH for incident triage; use ALB/TG metrics + ASG activity.
