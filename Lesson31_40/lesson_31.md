# lesson_31

---

# K8s Incidents I: CrashLoopBackOff & ImagePullBackOff

**Date:** 2025-12-11

**Topic:** Break your `lab30` app on purpose (bad image / bad config), then **debug & fix**: `CrashLoopBackOff`, `ImagePullBackOff`, rollbacks, and safe rollout patterns.

> Use existing lab30 namespace (web + redis + Ingress + monitoring).
> 

---

## Goals

- Understand what **CrashLoopBackOff** and **ImagePullBackOff** really mean.
- Use `kubectl get/describe/logs` to debug broken Pods.
- Practice **safe rollouts**, `kubectl set image`, and **rollback** with `kubectl rollout undo`.
- Document a small **incident runbook** for lab30.

---

## Pocket Cheat

| Command | What it does | Why |
| --- | --- | --- |
| `kubectl get pods -n lab30 -w` | Watch Pods live | See restarts/status |
| `kubectl describe pod …` | Events, last state, reasons | Root cause hints |
| `kubectl logs pod/...` | Container logs | Exceptions, tracebacks |
| `kubectl logs deploy/lab30-web` | Logs for all pods of Deployment | Simpler lookup |
| `kubectl set image deploy/lab30-web …` | Change container image | Quick broken image test |
| `kubectl rollout status deploy/lab30-web` | Wait for rollout | See success/failure |
| `kubectl rollout undo deploy/lab30-web` | Rollback to previous ReplicaSet | Fix bad rollout |
| `kubectl get rs -n lab30` | ReplicaSets for Deployment | Understand history |

---

## Notes

- **CrashLoopBackOff** = the container starts → crashes → k8s keeps trying to restart it → the backoff delay keeps increasing.
- **ImagePullBackOff** = the kubelet can’t pull the image (it doesn’t exist / wrong tag / no access).
- *Something is always broken* — the important part is being able to **quickly understand what and where**.

---

## Security Checklist

- Do not push real passwords/keys into broken configs/images — use training values only.
- Do not change Ingress/certificates in this lesson — only Deployments.
- All experiments stay in the `lab30` namespace; the kind cluster is local only.

---

## Pitfalls

- Look at **Events** in `kubectl describe`, not just `kubectl get pods`.
- `CrashLoopBackOff` is often caused by **application**, not k8s (check exceptions in the logs).
- A wrong image in the Deployment + `imagePullPolicy: Always` = endless `ImagePullBackOff`.
- After a fix, don’t forget to check `kubectl rollout status` — make sure the rollout actually finished.

---

## Layout

```
labs/lesson_31/
└─ k8s/  &namespaces/ &monitoring/ from lab30
   ├─ bad-redis-arg.yaml         # scenario: CrashLoopBackOff (bad env/config/args)
   ├─ incidents_scenarios.md
   ├─ redis-deployment.yaml
   ├─ redis-service.yaml
   ├─ web-bad-image.yaml         # scenario: ImagePullBackOff
   ├─ web-config.yaml            # known-good Config
   ├─ web-deployment.yaml        # known-good Deployment
   ├─ web-ingress.yaml
   └─ web-service.yaml

```

---

## 1) Prepare a “known-good” Deployment manifest

Copy the current working web Deployment (from lesson_28/30) into `lesson_31` as a base:

```bash
mkdir -p labs/lesson_31/k8s
cp labs/lesson_30/k8s/web-deployment.yaml labs/lesson_31/k8s/web-deployment.yaml

```

If everything goes completely off the rails, just:

```bash
kubectl apply -f web-deployment.yaml
kubectl rollout status deploy/lab30-web -n lab30

```

---

## 2) Scenario 1 — ImagePullBackOff (bad image tag)

### 2.1 Broken manifest

Create `labs/lesson_31/k8s/web-bad-image.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: lab30-web
  namespace: lab30
  labels:
    app: lab30-web
    tier: frontend
spec:
  replicas: 1
  selector:
    matchLabels:
      app: lab30-web
  template:
    metadata:
      labels:
        app: lab30-web
        tier: frontend
        service: labweb
        env: lab
    spec:
      containers:
        - name: web
          # Non-existent tag → ImagePullBackOff
          image: ghcr.io/vlrrbn/lab30-web-metrics:does-not-exist
          imagePullPolicy: Always
          envFrom:
            - configMapRef:
                name: lab30-web-config
          ports:
            - containerPort: 8080
          readinessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 5
            periodSeconds: 5
          livenessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 15
            periodSeconds: 10

```

### 2.2 Apply & observe

```bash
kubectl apply -f web-bad-image.yaml
kubectl rollout status deploy/lab30-web -n lab30

```

Check Pods:

```bash
kubectl get pods -n lab30 -w

```

Expected: the Pod will go into `ImagePullBackOff` or `ErrImagePull` state.

Check the details with:

```bash
POD=$(kubectl get pod -n lab30 -l app=lab30-web -o jsonpath='{.items[0].metadata.name}')
kubectl describe pod "$POD" -n lab30

kubectl get pods -n lab30 -l app=lab30-web
kubectl describe pod <name> -n lab30

POD=$(kubectl get pods -n lab30 -l app=lab30-web | grep CrashLoop | awk '{print $1}')
kubectl describe pod "$POD" -n lab30
```

**On what looks:**

- Events down: `Failed to pull image "…does-not-exist"`.
- Reason: `ErrImagePull` → `ImagePullBackOff`.

### 2.3 Fix via kubectl set image

Don’t fix the file directly — act as if this is “prod on fire”:

```bash
kubectl set image deploy/lab30-web -n lab30 web=ghcr.io/vlrrbn/lab30-web-metrics:0.2.1

kubectl rollout status deploy/lab30-web -n lab30
kubectl get pods -n lab30

```

Verify that the Pod is back in `Running` state and the application responds:

```bash
curl -s http://lab30.local/health | jq

```

---

## 3) Scenario 2 — CrashLoopBackOff (bad env / app crash)

Make the container pull successfully but crash on startup.

### 3.1 Broken env (e.g. invalid REDIS_PORT)

Create `labs/lesson_31/k8s/web-bad-env.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: lab30-redis
  namespace: lab30
  labels:
    app: lab30-redis
    tier: backend
spec:
  replicas: 1
  selector:
    matchLabels:
      app: lab30-redis
  template:
    metadata:
      labels:
        app: lab30-redis
        tier: backend
    spec:
      containers:
        - name: redis
          image: redis:7-alpine
          # 1st args not-a-number "redis-server"
          args: ["9090", "--save", "60", "1", "--loglevel", "warning"]
          ports:
            - containerPort: 6379
          readinessProbe:
            tcpSocket:
              port: 6379
            initialDelaySeconds: 5
            periodSeconds: 5
          livenessProbe:
            tcpSocket:
              port: 6379
            initialDelaySeconds: 10
            periodSeconds: 10

```

### 3.2 Apply & observe

```bash
kubectl apply -f bad-redis-arg.yaml
kubectl rollout status deploy/lab30-redis -n lab30
kubectl get pods -n lab30 -w

```

The Pod will:

- start,
- crash,
- end up in `CrashLoopBackOff` state.

### 3.3 Debug with describe + logs

```bash
POD=$(kubectl get pod -n lab30 -l app=lab30-redis -o jsonpath='{.items[0].metadata.name}')
kubectl describe pod "$POD" -n lab30
kubectl logs "$POD" -n lab30
kubectl logs <name> -n lab30 --previous`

kubectl get pods -n lab30 -l app=lab30-redis
kubectl describe pod <name> -n lab30

POD=$(kubectl get pods -n lab30 -l app=lab30-redis | grep CrashLoop | awk '{print $1}')
kubectl describe pod "$POD" -n lab30
```

Check:

- **Last State:** Terminated (ExitCode 1, Reason Error).
- Events: `Back-off restarting failed container`.
- In the logs you’ll see either a traceback or an error message about invalid configuration.

### 3.4 Fix by rollback

Broken YAML has already been committed and applied.

First, **look at the history**:

```bash
kubectl rollout history deploy/lab30-web-redis -n lab30

```

Then rollback:

```bash
kubectl rollout undo deploy/lab30-redis -n lab30
kubectl rollout status deploy/lab30-redis -n lab30

kubectl get pods -n lab30
curl -s http://lab30.local/health | jq

```

---

## 4) Combine with Prometheus: watch impact

Prometheus + kube-state-metrics:

- At the moment when the Pod is in `CrashLoopBackOff`, check Prometheus:

```
kube_pod_container_status_restarts_total{namespace="lab30", pod=~"lab30-redis.*"}

kube_pod_container_status_waiting_reason{reason="CrashLoopBackOff", namespace="lab30"} > 0

```

- And the `Lab30PodRestarts` alert should be firing as well.

This ties together:

> “CrashLoopBackOff in k8s”↔ “A spike restarts in monitoring”.
> 

---

## 5) Mini runbook for lab30 incidents

Create `labs/lesson_31/k8s/incidents_scenarios.md`:

```markdown
# lab30 Incident Runbook (CrashLoopBackOff & ImagePullBackOff)

## 1. ImagePullBackOff

Symptoms:
- Pods in ImagePullBackOff or ErrImagePull
- kubectl describe pod - shows events about failing to pull image

Checklist:
1. kubectl get pods -n lab30 -w
2. kubectl describe pod <name> -n lab30
3. Check image: in Deployment
4. Fix image tag:
   - kubectl set image deploy/lab30-web web=<correct-image>
   - OR rollback: kubectl rollout undo deploy/lab30-web -n lab30
5. Confirm:
   - kubectl rollout status deploy/lab30-web -n lab30
   - kubectl get pods -n lab30
   - curl http://lab30.local/health

## 2. CrashLoopBackOff

Symptoms:
- Pod goes Running -> Error -> CrashLoopBackOff
- Events show back-off restarting failed container

Checklist:
1. kubectl get pods -n lab30 -w
2. kubectl describe pod <name> -n lab30
3. kubectl logs <name> -n lab30 --previous` (look for stacktrace / config error)
4. Identify root cause:
   - bad env / config / code / args
5. Fix:
   - Change env/ConfigMap/Secret + kubectl apply
   - OR rollback: kubectl rollout undo deploy/lab30-redis -n lab30
6. Confirm:
   - Pods in Running
   - No new restarts:
     increase(kube_pod_container_status_restarts_total{namespace="lab30"}[10m]) == 0
```

---

## Core

- [ ]  Deliberately triggered an `ImagePullBackOff` and inspected Events/the reason in the description.
- [ ]  Fixed the bad image via `kubectl set image` and confirmed that the rollout succeeded.
- [ ]  Deliberately triggered a `CrashLoopBackOff` (bad env/code) and found the root cause in the logs.
- [ ]  Performed a rollback: `kubectl rollout undo` brought the Deployment back to a healthy state.
- [ ]  Tied these incidents to Prometheus metrics: you saw restart counts grow and the Pod become unavailable.
- [ ]  Wrote a short runbook `incidents_scenarios.md` with step-by-step diagnostics.
- [ ]  Tried the same techniques on `lab30-redis` (broke the image/config, found the issue, and fixed it).
- [ ]  Verbally explain the difference between `ImagePullBackOff` and `CrashLoopBackOff` and walk through a standard troubleshooting checklist.

---

## Acceptance Criteria

- [ ]  Not afraid to see `CrashLoopBackOff` or `ImagePullBackOff` — and know what to do step by step.
- [ ]  Can build a clear chain: k8s Events + logs + Prometheus metrics → a coherent incident story.

---

## Summary

- Practiced **breaking the cluster on purpose** and fixing it.
- Got hands-on with key `kubectl` incident commands: `describe`, `logs`, `set image`, `rollout undo`.
- Created first mini runbook for k8s incidents for the `lab30` service.

---

## Artifacts

- `labs/lesson_31/k8s/{bad-redis-arg.yaml, incidents_scenarios.md, web-bad-image.yaml}`