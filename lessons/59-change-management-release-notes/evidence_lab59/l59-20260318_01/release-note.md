# Release Note - l58-canary-20260303_195546

## Metadata
- Timestamp (UTC): 2026-03-03T20:00:58+00:00
- Environment: lab57
- Decision: **GO**
- ASG: lab57-web-asg
- ALB URL: http://<ip>:18080/
- Target Group: arn:aws:elasticloadbalancing:eu-west-1:<account-id>:targetgroup/<resource>/<hash>

## Change
- Candidate build(s): 57-01,57-02
- Baseline/previous build(s): 57-02
- Why changed: Promote candidate based on release gate evidence

## Risk Assessment
- Primary risks: 5xx regression, unhealthy targets, latency increase, rollout instability
- Rollback method: revert AMI/config and validate alarms + target health

## Evidence Summary
### Baseline
- total=36960 ok=36960 bad=0 avg=0.078s

### Canary
- total=54960 ok=54960 bad=0 avg=0.090s

### Alarm States
| Alarm | State |
|---|---|
| lab57-alb-unhealthy-hosts | OK |
| lab57-release-latency | OK |
| lab57-release-target-5xx | OK |
| lab57-target-5xx-critical | OK |

### Target Health
| Target | State | Reason |
|---|---|---|
| <instance-id> | healthy |  |
| <instance-id> | healthy |  |

### Instance Refresh
status=InProgress; percentage=100; reason=Waiting for terminating instances before continuing. For example: <instance-id> is terminating.

## Decision Rationale
Decision is GO because gates are healthy and canary evidence is stable. Source reason: all gates OK.

## Actions
- Continue rollout to 100%.
- Monitor alarms and target health for 10 minutes.
- Attach this note to release record/PR.

## References
- Canary artifacts: <redacted-path>
- Baseline artifacts: <redacted-path>
