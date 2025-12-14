# lesson_32

---

# K8s Incidents II: OOMKilled, CPU Throttle & QoS

**Date:** 2025-12-14

**Topic:** Trigger **memory OOM** and **CPU saturation** incidents in Kubernetes, understand **requests/limits** and **QoS classes**, and learn how to debug and tune resource settings.

---

## Goals

- Understand how **requests** and **limits** affect scheduling and runtime behavior.
- See **OOMKilled** in action (memory limit too low).
- Simulate **CPU saturation/throttle** with tight CPU limits.
- Learn how **QoS classes** (Guaranteed / Burstable / BestEffort) affect eviction priority.
- Start a small **resource-incident runbook**.

---

## Pocket Cheat

| Command / Thing | What it does | Why |
| --- | --- | --- |
| `kubectl create ns lab32-resources` | Namespace for experiments | Don’t break lab30 |
| `resources.requests` | Guaranteed minimum | Scheduling + QoS |
| `resources.limits` | Hard cap | OOMKill / CPU throttle |
| `kubectl describe pod …` | See Last State & Reason | OOMKilled, ExitCode, etc. |
| `kubectl top pods -n lab32-resources` | Show CPU/Memory usage (if metrics-server) | Observe saturation |
| QoS Guaranteed | requests == limits for **all** containers | Last to be evicted |
| QoS Burstable | some requests set, limits > requests | Normal workloads |
| QoS BestEffort | no requests/limits | First to die under pressure |

---

## Notes

- **Memory limit** is **strict**: if the container exceeds it, the kernel kills it → `OOMKilled`.
- **CPU limit** does **not kill** the container, it throttles: the container gets no more than the set CPU, causing it to slow down.
- QoS = how Kubernetes decides which Pods to evict first when the node is under pressure.

---

## Security Checklist

- All experiments are done in the `lab32-resources` namespace.
- Use public images like `polinux/stress` / `alpine` for load Pods.
- No real secrets/passwords are needed here.

---

## Pitfalls

- Without the `metrics-server`, `kubectl top` won’t work; for OOM, `kubectl describe` is enough.
- CPU throttling is not always obvious: Pod is `Running` but the app is slow → check both metrics and limits.
- If requests are set **too low**, a Pod may be scheduled on a weak node (in a real cluster).
