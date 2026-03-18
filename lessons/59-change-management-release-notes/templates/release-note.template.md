# Release Note — {{release_id}}

## Metadata

- Timestamp (UTC): {{timestamp_utc}}
- Environment: {{env}}
- Decision: **{{decision}}**
- ASG: {{asg_name}}
- ALB URL: {{alb_url}}
- Target Group: {{tg_arn}}

## Change

- Candidate build(s): {{candidate_builds}}
- Baseline/previous build(s): {{previous_builds}}
- Why changed: {{why}}

## Risk Assessment

- Primary risks: 5xx regression, unhealthy targets, latency increase, rollout instability
- Rollback method: revert AMI variable + apply + validate alarms/health

## Evidence Summary
### Baseline

- total={{baseline_total}} ok={{baseline_ok}} bad={{baseline_bad}} avg={{baseline_avg}}s

### Canary

- total={{canary_total}} ok={{canary_ok}} bad={{canary_bad}} avg={{canary_avg}}s

### Alarm States

{{alarms_table}}

### Target Health

{{target_health_table}}

### Instance Refresh

{{instance_refresh_summary}}

## Decision Rationale

{{decision_rationale}}

## Actions

{{actions}}

## References

- Canary artifacts: {{artifact_dir}}
- Baseline artifacts: {{baseline_dir}}
