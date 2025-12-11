# lesson_31

---

# K8s Incidents I: CrashLoopBackOff & ImagePullBackOff

**Date:** 2025-12-11

**Topic:** Break your `lab30` app on purpose (bad image / bad config), then **debug & fix**: `CrashLoopBackOff`, `ImagePullBackOff`, rollbacks, and safe rollout patterns.

> Use your existing lab30 namespace (web + redis + Ingress + monitoring).
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