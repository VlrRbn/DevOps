# lesson_33

---

# K8s Storage: PVC, PV & Redis StatefulSet

**Date:** 2025-12-15

**Topic:** Turn Redis from a throwaway Deployment into a **persistent StatefulSet** using **PersistentVolumeClaims (PVC)** and a **headless Service**. Verify that data survives Pod restarts.

> Keep lab30 for main app.
> 
> 
> For storage experiments use namespace `lab33-storage`.
> 

---

## Goals

- Understand the difference between **Deployment** and **StatefulSet** for stateful apps.
- Use **PersistentVolumeClaim (PVC)** with the cluster’s default **StorageClass** (kind’s local-path).
- Deploy Redis as a **StatefulSet** with its own PVC per Pod.
- Verify that **data survives Pod deletion** and restart.

---

## Pocket Cheat

| Thing / Command | What it does | Why |
| --- | --- | --- |
| `PersistentVolume (PV)` | Actual storage in the cluster | Where bits live |
| `PersistentVolumeClaim (PVC)` | Request for storage | Pod asks for storage |
| `StorageClass` | “How to provision volume” | Dynamic provisioning |
| `StatefulSet` | Stable identities + storage | For DBs, queues, etc. |
| `kubectl get pvc,pv -n …` | See claims & volumes | Verify binding |
| `kubectl delete pod …` | Kill Pod only | Check data survives |
| `kubectl delete sts …` | Kill StatefulSet controller | PVCs usually remain |

---

## Notes

- **Deployment** is a good fit for stateless workloads: web, APIs, workers.
- **StatefulSet** provides stable Pod names and persistent volumes → Redis, Postgres, Kafka.
- In kind, a default StorageClass is usually available (`standard` / `local-path`), so creating a PVC will automatically provision a PV.

---

## Security Checklist

- All experiments are done in the separate namespace `lab33-storage`.
- Redis is for learning purposes only; no real passwords or data.
- Keep PVC sizes small (1Gi) to avoid bloating the disk.

---

## Pitfalls

- If there is no default StorageClass, PVCs will stay in `Pending` state.
- StatefulSet requires a **headless Service** (no ClusterIP) for stable DNS names.
- Deleting a StatefulSet **by default** does not delete PVCs → leftover volumes are normal.

---

## Layout

```
labs/lesson_33/k8s/
├─ redis-headless-service.yaml
└─ redis-statefulset.yaml

```

---

## 1) Namespace for storage lab

`labs/lesson_33/k8s/lab33-namespace.yaml`:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: lab33-storage
  labels:
    env: lab
    topic: storage

```

Apply:

```bash
kubectl apply -f lab33-namespace.yaml
kubectl get ns

```

---

## 2) Headless Service & normal Service for Redis

### 2.1 Headless Service (for StatefulSet DNS)

`labs/lesson_33/k8s/redis-headless-service.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: lab33-redis-headless
  namespace: lab33-storage
  labels:
    app: lab33-redis
spec:
  clusterIP: None
  selector:
    app: lab33-redis
  ports:
    - name: redis
      port: 6379
      targetPort: 6379

```

> clusterIP: None → headless service.
> 
> 
> Pods will be on DNS:
> 
> `lab33-redis-0.lab33-redis-headless.lab33-storage.svc.cluster.local`.
> 

### 2.2 Normal ClusterIP service (for clients)

`labs/lesson_33/k8s/redis-service.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: lab33-redis
  namespace: lab33-storage
  labels:
    app: lab33-redis
spec:
  type: ClusterIP
  selector:
    app: lab33-redis
  ports:
    - name: redis
      port: 6379
      targetPort: 6379

```

Apply both:

```bash
kubectl apply -f redis-headless-service.yaml
kubectl apply -f redis-service.yaml

kubectl get svc -n lab33-storage

```

---

## 3) Redis StatefulSet with PVC

`labs/lesson_33/k8s/redis-statefulset.yaml`:

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: lab33-redis
  namespace: lab33-storage
  labels:
    app: lab33-redis
    tier: backend
spec:
  serviceName: lab33-redis-headless
  replicas: 1
  selector:
    matchLabels:
      app: lab33-redis
  template:
    metadata:
      labels:
        app: lab33-redis
        tier: backend
    spec:
      containers:
        - name: redis
          image: redis:7-alpine
          args: ["redis-server", "--appendonly", "yes"]
          ports:
            - containerPort: 6379
              name: redis
          volumeMounts:
            - name: redis-data
              mountPath: /data
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
  volumeClaimTemplates:
    - metadata:
        name: redis-data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 1Gi

```

Apply:

```bash
kubectl apply -f redis-statefulset.yaml

kubectl get statefulset -n lab33-storage
kubectl get pods -n lab33-storage

```

Wait until `lab33-redis-0` turn `Running`.

---

## 4) Check PVC & PV

Check what PVC is create:

```bash
kubectl get pvc -n lab33-storage

```

Expecting:

- `redis-data-lab33-redis-0`  in state `Bound`.

PV:

```bash
kubectl get pv

```

You’ll see the PV bound to this PVC. (StorageClass — local-path/standard).

---

## 5) Prove persistence: write → delete Pod → read

### 5.1 Write some data into Redis

Let’s enter in Pod:

```bash
POD=$(kubectl get pod -n lab33-storage -l app=lab33-redis -o jsonpath='{.items[0].metadata.name}')
kubectl exec -it "$POD" -n lab33-storage -- sh

```

Inside:

```bash
redis-cli set lab33:key1 "persist-me"
redis-cli set lab33:key2 "another-value"
redis-cli keys "lab33:*"
exit

```

### 5.2 Delete Pod

Delete only Pod (not a StatefulSet, not a PVC):

```bash
kubectl delete pod "$POD" -n lab33-storage
# kubectl delete pod lab33-redis-0
kubectl get pods -n lab33-storage

```

Wait until `lab33-redis-0` recreate and would be `Running`.

### 5.3 Read data again

Again:

```bash
POD=$(kubectl get pod -n lab33-storage -l app=lab33-redis -o jsonpath='{.items[0].metadata.name}')
kubectl exec -it "$POD" -n lab33-storage -- sh

```

Inside:

```bash
redis-cli keys "lab33:*"
redis-cli get lab33:key1
redis-cli get lab33:key2
exit

```

If everything is fine — the values persist → the PVC is working.

---

## 6) What happens if we delete StatefulSet?

Important to understand: **StatefulSet ≠ data.** Data lives in PV/PVC.

Let’s try:

```bash
kubectl delete statefulset lab33-redis -n lab33-storage
kubectl get statefulset -n lab33-storage
kubectl get pods -n lab33-storage
kubectl get pvc -n lab33-storage
kubectl get pv

```

Expected:

- StatefulSet and Pod are deleted.
- PVC `redis-data-lab33-redis-0` **remains**.
- PV is still `Bound` to the PVC.

**Reapply the StatefulSet**:

```bash
kubectl apply -f redis-statefulset.yaml

kubectl get pods -n lab33-storage
kubectl get pvc -n lab33-storage

```

Again:

```bash
POD=$(kubectl get pod -n lab33-storage -l app=lab33-redis -o jsonpath='{.items[0].metadata.name}')
kubectl exec -it "$POD" -n lab33-storage -- sh
redis-cli keys "lab33:*"
exit

```

The data should still be there → the PV/PVC survived the StatefulSet deletion.

---

## 7) Quick comparison: Deployment vs StatefulSet

```markdown
## Deployment vs StatefulSet (TL;DR)

Deployment:
- Pod names: random (lab30-web)
- Volume: usually ephemeral unless you manually use PVCs
- Good for: stateless apps (web, API, workers)

StatefulSet:
- Pod names: stable (lab33-redis-0, lab33-redis-1, ...)
- Each Pod gets its own PVC via volumeClaimTemplates
- Good for: DBs, queues, storage-heavy apps

Key behavior:
- Deleting Pod in StatefulSet does NOT delete PVC → data persists
- Deleting StatefulSet usually keeps PVC/PV (depends on reclaimPolicy)

```

---

## Core

- [ ]  Redis StatefulSet `lab33-redis` with PVC is up and `Running`.
- [ ]  Wrote/read keys in Redis, deleted the Pod, and the data **persisted**.
- [ ]  Observed the `redis-data-lab33-redis-0` PVC and its corresponding PV.
- [ ]  Increased replicas to 2–3 and checked which PVCs are created (`1`, `2`, ...).
- [ ]  Simulated deleting the StatefulSet and confirmed that PVC/PV survive.
- [ ]  Tested connecting `lab30-web` to `lab33-redis.lab33-storage.svc.cluster.local`.
- [ ]  Wrote a when a Deployment for Redis is acceptable, and when a StatefulSet is **required**.

---

## Acceptance Criteria

- [ ]  Can explain **why** StatefulSet and PVC are needed for Redis/databases, instead of just a Deployment.
- [ ]  Can read `kubectl get pvc,pv` and understand what `Bound`/`Pending` means.
- [ ]  Proved in practice that **data survives** Pod restarts and even StatefulSet deletion.
- [ ]  Clearly distinguish for yourself: stateless → Deployment, stateful → StatefulSet + PVC.

---

## Summary

- Migrated Redis to a **stateful service with PersistentVolume**.
- Got experience with `StatefulSet + PVC + PV + headless Service`.
- Have a basic understanding of running databases in Kubernetes, not just web Pods.

---

## Artifacts

- `labs/lesson_33/k8s/redis-headless-service.yaml`
- `labs/lesson_33/k8s/redis-statefulset.yaml`
