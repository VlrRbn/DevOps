# ALB Failure Modes — Cheat Card

## 0) Golden rule
- Always look at **AWS/ApplicationELB** metrics.
- For HealthyHostCount use **Statistic: Minimum**.
- Use correct dimensions: **TargetGroup + LoadBalancer**.

---

## 1) Wrong Path / Wrong Matcher (health check misconfig)
### Signals
- Targets go unhealthy but service may still run.
- describe-target-health shows HTTP code mismatch / failed health checks.
- ASG may replace instances, but replacements don’t help.

### Diagnosis
- Health check configuration is wrong (path/matcher/port).

### Action
- Fix TG health check path/matcher.
- Confirm: HealthyHostCount(min) returns, UnHealthyHostCount drops.

---

## 2) Slow Backend / Timeout (alive but too slow)
### Signals
- TargetResponseTime rises first.
- Health checks may start timing out (Target.Timeout).
- ALB can be “green” while users complain (latency).

### Diagnosis
- Performance degradation or timeout too strict.

### Action
- Increase HealthCheckTimeoutSeconds (carefully) OR fix latency root cause.
- Add/validate scaling policy, watch p95/p99 latency.

---

## 3) Boot Race / Grace Too Low (flapping + churn)
### Signals
- Targets oscillate initial/unhealthy.
- ScalingActivities shows repeated launch/terminate (churn).
- HealthyHostCount(min) dips during refresh/scale events.

### Diagnosis
- Instance needs more warmup than allowed by grace/warmup/thresholds.

### Action
- Increase ASG HealthCheckGracePeriod / InstanceWarmup.
- Tune TG thresholds; consider Slow Start for heavy apps.
- Validate with controlled refresh.

---

## 4) Deregistration Delay Too Low (errors during scale-in/refresh)
### Signals
- Short spikes of 502/503 around terminations/refresh.
- Targets enter draining then disappear quickly.
- Errors correlate with scale-in / refresh windows.

### Diagnosis
- In-flight requests cut off during draining.

### Action
- Increase deregistration_delay.timeout_seconds.
- Confirm: fewer ELB 5XX spikes during termination windows.

---

## 5) Slow Start Missing (new target causes latency spike)
### Signals
- After new targets become healthy, latency spikes briefly.
- No UnHealthy targets; “green” but slower.
- Happens on scale-out or refresh.

### Diagnosis
- New instances need warm traffic ramp (cold cache, JVM, init).

### Action
- Enable slow_start.duration_seconds (e.g., 60–120).
- Confirm: smoother TargetResponseTime after scale-out/refresh.

---

## 6) “ALB green, users complain” (triage in 5 minutes)
### Look at
- HealthyHostCount(min), UnHealthyHostCount(max)
- TargetResponseTime
- HTTPCode_ELB_5XX vs HTTPCode_Target_5XX
- RequestCount

### Quick conclusions
- ELB 5XX + Healthy(min)=0 => no healthy targets/routing/TG mismatch
- ELB 5XX + Healthy(min)>0 => capacity/timeouts/resets/app instability
- 5XX=0 + latency high => perf issue (DB/network/CPU), health still green
