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

---

## Layout

```
labs/lesson_32/
└─ k8s/
   ├─ namespace.yaml
   ├─ memhog-bad-limit.yaml      # OOMKilled scenario
   ├─ memhog-fixed.yaml          # fixed memory limits
   ├─ cpuhog-tight-limit.yaml    # CPU throttle scenario
   ├─ cpuhog-relaxed.yaml        # more reasonable CPU
   └─ resources_runbook.md       # your notes/runbook

```

---

## 1) Namespace for experiments

`labs/lesson_32/k8s/namespace.yaml`:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: lab32-resources
  labels:
    env: lab
    topic: resources

```

Apply:

```bash
kubectl apply -f namespace.yaml
kubectl get ns

```

---

## 2) Scenario 1 — Memory OOMKilled (memhog)

We’ll use a container with `stress` and an intentionally low memory limit.

### 2.1 Bad memory limit — expect OOMKilled

`labs/lesson_32/k8s/memhog-bad-limit.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: lab32-memhog
  namespace: lab32-resources
  labels:
    app: lab32-memhog
spec:
  replicas: 1
  selector:
    matchLabels:
      app: lab32-memhog
  template:
    metadata:
      labels:
        app: lab32-memhog
    spec:
      containers:
        - name: memhog
          image: polinux/stress
          command: ["stress"]
          args:
            - "--vm"
            - "1"
            - "--vm-bytes"
            - "256M"
            - "--vm-hang"
            - "1"
          resources:
            requests:
              memory: "64Mi"
              cpu: "50m"
            limits:
              memory: "124Mi"
              cpu: "200m"

```

Apply:

```bash
kubectl apply -f memhog-bad-limit.yaml
kubectl get pods -n lab32-resources -w

```

Expected:

- The Pod starts, begins consuming memory, exceeds 128Mi → `OOMKilled`.
- Pod status: `CrashLoopBackOff` with reason `OOMKilled`.

### 2.2 Debugging OOMKilled

Take Pod’s name:

```bash
POD=$(kubectl get pod -n lab32-resources -l app=lab32-memhog -o jsonpath='{.items[0].metadata.name}')
kubectl describe pod "$POD" -n lab32-resources

kubectl describe pod lab32-memhog -n lab32-resources

```

Check:

- In `Containers:` → `Last State: Terminated`
    - `Reason: OOMKilled`
    - `Exit Code: 137`.
- In Events: `OOMKilled` / `Container killed due to ...`.

---

## 3) Fix memory limits

Now set reasonable limits: if the app needs 256Mi, don’t restrict it down to 128Mi.

`labs/lesson_32/k8s/memhog-good-limit.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: lab32-memhog
  namespace: lab32-resources
  labels:
    app: lab32-memhog
spec:
  replicas: 1
  selector:
    matchLabels:
      app: lab32-memhog
  template:
    metadata:
      labels:
        app: lab32-memhog
    spec:
      containers:
        - name: memhog
          image: polinux/stress
          command: ["stress"]
          args:
            - "--vm"
            - "1"
            - "--vm-bytes"
            - "256M"
            - "--vm-hang"
            - "1"
          resources:
            requests:
              memory: "256Mi"
              cpu: "50m"
            limits:
              memory: "512Mi"
              cpu: "200m"

```

Apply:

```bash
kubectl apply -f memhog-good-limit.yaml
kubectl rollout status deploy/lab32-memhog -n lab32-resources

kubectl get pods -n lab32-resources
kubectl describe pod -n lab32-resources -l app=lab32-memhog

```

Check:

- Pod is `Running`.
- In `describe` — haven’t new OOMKilled in Last State/Events.
- QoS = **Burstable**

---

## 4) Scenario 2 — CPU saturation / throttle (cpuhog)

CPU limit does **not kill** the container, it just throttles its speed.

### 4.1 Tight CPU limit

We’ll create a Pod that just runs `yes > /dev/null` and gets throttled by the CPU limit.

`labs/lesson_32/k8s/cpuhog-low-limit.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: lab32-cpuhog
  namespace: lab32-resources
  labels:
    app: lab32-cpuhog
spec:
  replicas: 1
  selector:
    matchLabels:
      app: lab32-cpuhog
  template:
    metadata:
      labels:
        app: lab32-cpuhog
    spec:
      containers:
        - name: cpuhog
          image: alpine:3.20
          command: ["/bin/sh", "-c"]
          args:
          # simple hog: infinite yes piped to /dev/null
            - "yes > /dev/null"
          resources:
            requests:
              memory: "32Mi"
              cpu: "50m"
            limits:
              memory: "128Mi"
              cpu: "100m"

```

Apply:

```bash
kubectl apply -f cpuhog-low-limit.yaml
kubectl get pods -n lab32-resources -w

```

The Pod will be `Running`, but the container constantly hits its CPU limit.

```bash
kubectl exec -n lab32-resources deploy/lab32-cpuhog -it -- sh
cat /sys/fs/cgroup/cpu.stat

```

Expected:

- CPU usage ~ `100m` (limit), even if the node is free — this is throttling.
- If it’s higher — the limit hasn’t been reached yet.

### 4.2 Relaxed CPU limits

Now increase the limits and observe the difference.

`labs/lesson_32/k8s/cpuhog-high-limit.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: lab32-cpuhog
  namespace: lab32-resources
  labels:
    app: lab32-cpuhog
spec:
  replicas: 1
  selector:
    matchLabels:
      app: lab32-cpuhog
  template:
    metadata:
      labels:
        app: lab32-cpuhog
    spec:
      containers:
        - name: cpuhog
          image: alpine:3.20
          command: ["/bin/sh", "-c"]
          args:
            - "yes > /dev/null"
          resources:
            requests:
              cpu: "200m"    # 0.2 core
              memory: "32Mi"
            limits:
              cpu: "1"
              memory: "256Mi"

```

Apply:

```bash
kubectl apply -f cpuhog-high-limit.yaml
kubectl rollout status deploy/lab32-cpuhog -n lab32-resources

kubectl get pods -n lab32-resources

kubectl exec -n lab32-resources deploy/lab32-cpuhog -it -- sh
cat /sys/fs/cgroup/cpu.stat

```

Now the Pod can use up to a full CPU core (1 = 1 core), if the node allows.

---

## 5) QoS classes — see it on real Pods

Now let’s look at the QoS classes that Kubernetes assigns.

1. **memhog**:

```bash
POD_MEM=$(kubectl get pod -n lab32-resources -l app=lab32-memhog -o jsonpath='{.items[0].metadata.name}')
kubectl describe pod "$POD_MEM" -n lab32-resources | grep -i "QoS" -n

kubectl describe pod -n <ns> | grep QoS
```

Expected:

- If `requests` and `limits` are set for all resources and equal → QoS class is `Guaranteed`.
- In our case `requests != limits` → QoS class is **Burstable**.
1. **cpuhog** — same as above.
2. Create a BestEffort Pod:

```bash
kubectl run besteffort-test -n lab32-resources \
  --image=alpine:3.20 --restart=Never -- /bin/sh -c "sleep 3600"
kubectl describe pod besteffort-test -n lab32-resources | grep -i "QoS"

```

Its QoS Class: BestEffort (no requests or limits set - 1st on die).

---

## 6) Runbook notes

Create `labs/lesson_32/k8s/resources_runbook.md`:

```markdown
# lab32 Resource Incidents Runbook

## 1. OOMKilled (memory)

Symptoms:
- Pod in CrashLoopBackOff
- Last State: Terminated (Reason: OOMKilled, ExitCode: 137)
- Events mention OOMKilled

Checklist:
1. kubectl get pods -n <ns>
2. kubectl describe pod <name> -n <ns>
3. Check resources.limits.memory in Deployment
4. Increase limit and request to realistic value
5. kubectl apply -f ...
6. kubectl rollout status deploy/<name> -n <ns>
7. Confirm: no new OOMKilled in describe/events

## 2. CPU throttle / saturation

Symptoms:
- Pod is Running, but app is slow
- High CPU usage for Pod (kubectl top pods) near limit
- Node still has free CPU

Checklist:
1. Check current usage: kubectl exec -n <ns> deploy/<name> -it -- sh
	 cat /sys/fs/cgroup/cpu.stat
2. Check resources.requests/limits.cpu
3. If limit too low for workload:
   - Increase limits.cpu and requests.cpu
4. Re-apply Deployment
5. Watch behavior and CPU again

## 3. QoS classes

- BestEffort: no requests/limits → first to be evicted
- Burstable: some requests set → normal workloads
- Guaranteed: requests == limits for all containers → most protected

Rule of thumb:
- Critical control-plane / infra → aim for Guaranteed
- Normal apps → Burstable with realistic requests/limits
- BestEffort — only for debugging

```

---

## Core

- [ ]  Ran `memhog-bad-limit` and saw actual `OOMKilled` in `kubectl describe`.
- [ ]  Fixed the limits in `memhog-fixed`, Pod stopped crashing.
- [ ]  Ran `cpuhog-tight-limit` and observed the Pod hitting the CPU limit (use `kubectl top` if metrics-server is available).
- [ ]  Checked QoS classes on several Pods: BestEffort vs Burstable.
- [ ]  Practiced resource breaking safely on **lab30-web**:
    - set too low memory limit → caught OOMKilled,
    - increased the limit and did a rollout.
- [ ]  Recorded typical CPU/Memory values for lab30-web and Redis on machine.
- [ ]  Explain why **BestEffort** Pods are evicted first when memory is scarce.

---

## Acceptance Criteria

- [ ]  Understand how `OOMKilled` differs from `CrashLoopBackOff` caused by application code.
- [ ]  Know where to look for memory/CPU issues: `kubectl describe`, `logs`, `resources.*`.
- [ ]  Know what QoS classes are and how they are derived from requests/limits.
- [ ]  Have a minimal runbook for resource-related incidents.

---

## Summary

- Saw real OOMKilled and CPU scenarios in k8s.
- Got hands-on with requests/limits and QoS, understanding how they relate to stability.
- If a Pod dies from memory or slows down due to CPU, follow the checklist to troubleshoot.

---

## Artifacts

- `labs/lesson_32/k8s/cpuhog-high-limit.yaml`
- `labs/lesson_32/k8s/cpuhog-low-limit.yaml`
- `labs/lesson_32/k8s/memhog-bad-limit.yaml`
- `labs/lesson_32/k8s/memhog-good-limit.yaml`
- `labs/lesson_32/k8s/resources_runbook.md`
