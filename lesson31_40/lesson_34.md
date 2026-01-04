# lesson_34

---

# K8s Jobs & CronJobs: One-off Tasks & Redis Backups

**Date:** 2025-12-16

**Topic:** Use **Jobs** for one-off tasks and **CronJobs** for scheduled work (e.g. Redis backups). Learn how retries, backoff, and history limits work, and how to inspect completed/failed Jobs.

---

## Goals

- Understand when to use **Job** vs **Deployment**.
- Create simple Jobs (success & failure) and observe **retries/backoffLimit**.
- Create a **CronJob** that periodically backs up Redis from `lab33`.
- Inspect Job history, logs, and manage CronJob (suspend/resume, manual run).

---

## Pocket Cheat

| Command / File | What it does | Why |
| --- | --- | --- |
| `kubectl create job ...` | Create one-off Job | Run task once |
| `kubectl get jobs -n ...` | List Jobs | See completions/status |
| `kubectl get pods -n ... --show-labels` | See Job Pods | Map Pods ↔ Job |
| `kubectl logs job/<name> -n ...` | Logs from Job Pods | Debug |
| `kubectl describe job ...` | Events, conditions, backoff | Why it failed/succeeded |
| `kubectl get cronjobs -n ...` | List CronJobs | Schedules |
| `kubectl get jobs --watch` | Watch Jobs running | Observe retries |
| `backoffLimit` | Max failed Pods before Job marked failed | Protect cluster |
| `suspend: true` (CronJob) | Pause running schedule | Maintenance window |

---

## Notes

- **Deployment** → “keep N replicas running forever”.
- **Job** → “run this task until it completes successfully (or fails too many times)”.
- **CronJob** → “run this Job on a schedule (every X minutes/hours/days)”.
- Backup DB/Redis/files in k8s usually done through CronJob.

---

## Security Checklist

- Redis backup: no real secrets, just lab Redis in `lab33`.
- PVC for backups limited to small size (1Gi).
- CronJob schedule — for labs (`/5 * * * *`).

---

## Pitfalls

- A Job does not restart a Pod indefinitely; use `backoffLimit` and `activeDeadlineSeconds`.
- A CronJob can create **multiple Jobs** if the previous one is still running and the schedule catches up.
- On errors, check **logs** and **Events** for the Job, not just the status.
- PVCs used for backups are not automatically deleted when a CronJob is removed → watch for leftover volumes.

---

## Layout

```
labs/lesson_34/k8s/
├─ backup-pvc.yaml                 # PVC for Redis backups (namespace lab33-storage)
├─ backup-pvc-testpod.yaml
├─ cronjob-redis-backup.yaml       # CronJob in lab33-storage namespace
├─ failing-job.yaml                # Job that fails and hits backoffLimit
├─ job-success.yaml                # single-run success Job
├─ redis-headless-service.yaml
└─ redis-statefulset.yaml

```

---

## 1) Simple success Job

This Job just sleeps a bit and prints a message.

`labs/lesson_34/k8s/job-success.yaml`:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: lab34-success
  namespace: lab34-jobs
  labels:
    job: lab34-success
    tier: backend
spec:
  backoffLimit: 0
  template:
    metadata:
      labels:
        job: lab34-success
        tier: backend
    spec:
      restartPolicy: Never
      containers:
        - name: success
          image: alpine:3.20
          command: ["/bin/sh", "-c"]
          args:
            - |
              echo "Lab34 starting Job...";
              sleep 5;
              echo "Success! k8s Job completed...";

```

Apply & observe:

```bash
kubectl apply -f job-success.yaml

kubectl get jobs -n lab34-jobs -w
kubectl get pods -n lab34-jobs --show-labels

```

Check status:

```bash
kubectl describe job lab34-success -n lab34-jobs
kubectl logs job/lab34-success -n lab34-jobs

```

Expected - `Succeeded`:

- Logs show 2 lines: “starting Job” and “Job completed…”.

---

## 2) Failing Job with retries (backoffLimit)

Create a Job that deliberately fails.

`labs/lesson_34/k8s/failing-job.yaml`:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: lab34-fail
  namespace: lab34-jobs
  labels:
    job: lab34-fail
    tier: backend
spec:
  backoffLimit: 3
  template:
    metadata:
      labels:
        job: lab34-fail
        tier: backend
    spec:
      restartPolicy: Never
      containers:
        - name: fail
          image: alpine:3.20
          command: ["/bin/sh", "-c"]
          args:
            - |
              echo "Lab34 will failed...";
              exit 1;

```

Apply:

```bash
kubectl apply -f failing-job.yaml

kubectl get jobs -n lab34-jobs -w

```

Observe how the status changes:

- `0/1` → `0/1` with `Failed` Pods,
- Eventually, Job status: `Failed`, `backoffLimit` reached.

Check with:

```bash
kubectl describe job lab34-fail -n lab34-jobs

kubectl get pods -n lab34-jobs -l job=lab34-fail
kubectl logs $(kubectl get pod -n lab34-jobs -l job=lab34-fail -o jsonpath='{.items[0].metadata.name}') -n lab34-jobs

```

**Important to understand:**

- `backoffLimit: 3` → maximum of 3 *Pod attempts* (or restarts) before the Job is marked `Failed`.
- Pods may remain in the cluster if you don’t clean up history.

---

## 3) PVC and testing Pod

`labs/lesson_34/k8s/backup-pvc.yaml`:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: lab34-redis-backup-pvc
  namespace: lab33-storage
  labels:
    app: lab34-redis-backup-pvc
    tier: backend
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi

```

`labs/lesson_34/k8s/backup-pvc-testpod.yaml`:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: redis-backup-job
  namespace: lab33-storage
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: backup
          image: busybox
          command: ["sh", "-c", "date > /backup/backup.txt"]
          volumeMounts:
        - name: backup-pvc
          mountPath: /backup
      volumes:
        - name: backup-pvc
          persistentVolumeClaim:
            claimName: lab34-redis-backup-pvc

```

Apply:

```bash
kubectl apply -f backup-pvc.yaml
kubectl apply -f backup-pvc-testpod.yaml

kubectl get pvc -n lab33-storage

```

Expected: PVC `lab34-redis-backup-pvc` is in `Bound` status.

---

## 4) CronJob: Redis backup in lab33

Idea:

- CronJob in namespace `lab33-storage`.
- Pod inside the CronJob uses `redis:7-alpine`.
- Command: `redis-cli` connects to `lab33-redis`, performs `rdb` backup into `/backup/` with a timestamp.
- Volume = our PVC `lab34-redis-backup-pvc`.

Example (for Redis in **lab33-storage** namespace, Service `lab33-redis-headless`):

`labs/lesson_34/k8s/cronjob-redis-backup.yaml`:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: lab34-redis-backup
  namespace: lab33-storage
  labels:
    app: lab34-redis-backup
spec:
  schedule: "*/5 * * * *"
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  concurrencyPolicy: Forbid
  jobTemplate:
    spec:
      backoffLimit: 2
      template:
        metadata:
          labels:
            app: lab34-redis-backup
        spec:
          restartPolicy: Never
          activeDeadlineSeconds: 300
          containers:
            - name: backup
              image: redis:7-alpine
              command: ["/bin/sh", "-c"]
              args:
                - |
                  set -eux
                  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Starting Redis backup...";
                  mkdir -p /backup;
                  BACKUP_FILE="/backup/redis-lab33-$(date -u +%Y%m%dT%H%M%SZ).rdb";
                  # connect to lab33-redis in lab33-storage namespace
                  redis-cli -h lab33-redis --rdb "${BACKUP_FILE}";
                  echo "Backup finished: ${BACKUP_FILE}";
                  # keep only last 7 days
                  busybox find /backup -type f -name "*.rdb" -mtime +7 -delete
                  echo "Current backups:"
                  ls -lh /backup;
              volumeMounts:
                - name: backup-pvc
                  mountPath: /backup
          volumes:
            - name: backup-pvc
              persistentVolumeClaim:
                claimName: lab34-redis-backup-pvc

```

Apply:

```bash
kubectl apply -f cronjob-redis-backup.yaml

kubectl get cronjobs -n lab33-storage
kubectl get job -A

```

---

## 5) Trigger backup manually & inspect

No need to wait 10 minutes — create a Job manually from the CronJob:

```bash
kubectl create job --from=cronjob/lab34-redis-backup \
  lab34-redis-backup-manual-1 \
  -n lab33-storage

kubectl get jobs -n lab33-storage
kubectl get pods -n lab33-storage -l app=lab34-redis-backup

```

Logs:

```bash
kubectl logs job/lab34-redis-backup-manual-1 -n lab33-storage

```

Expected:

- Logs with “Starting Redis backup…” and “Backup finished…”.
- File list in `/backup` showing `redis-lab33-<timestamp>.rdb`.

To check PVC contents, attach a new Pod using the same PVC:

```bash
kubectl run backup-shell -n lab33-storage \
  --restart=Never \
  --image=alpine:3.20 \
  --overrides='
{
  "spec": {
	  "restartPolicy": "Never",
    "containers": [{
      "name": "backup-shell",
      "image": "alpine:3.20",
      "command": ["/bin/sh", "-c", "ls -lh /backup; sleep 3600"],
      "volumeMounts": [{
        "name": "backup",
        "mountPath": "/backup"
      }]
    }],
    "volumes": [{
      "name": "backup",
      "persistentVolumeClaim": {
        "claimName": "lab34-redis-backup-pvc"
      }
    }]
  }
}'

kubectl logs -n lab33-storage backup-shell
kubectl exec -it backup-shell -n lab33-storage -- ls -lh /backup
# kubectl exec -it backup-shell -n lab33-storage -- cat /backup/backup.txt

```

You should see `.rdb` files there.

After checking, you can delete the `backup-shell` Pod:

```bash
kubectl delete pod backup-shell -n lab33-storage

```

---

## 6) Manage CronJob (suspend/resume & history)

### 6.1 Suspend CronJob

To temporarily suspend the schedule:

```bash
kubectl patch cronjob lab34-redis-backup -n lab33-storage \
  -p '{"spec": {"suspend": true}}'

kubectl get cronjob lab34-redis-backup -n lab33-storage -o yaml | grep -i suspend -n

```

To resume the schedule:

```bash
kubectl patch cronjob lab34-redis-backup -n lab33-storage \
  -p '{"spec": {"suspend": false}}'

```

### 6.2 Cleanup Jobs

Jobs and their Pods are not deleted automatically if `successfulJobsHistoryLimit`/`failedJobsHistoryLimit` keep history.

For manual cleanup:

```bash
kubectl delete job -n lab33-storage lab34-redis-backup-manual-1
kubectl get jobs -n lab33-storage
kubectl get pods -n lab33-storage -l app=lab34-redis-backup

```

---

## Core

- [ ]  Created `lab34-hello` Job, saw `Completed` status and checked logs.
- [ ]  Created `lab34-fail` Job, observed it reach `backoffLimit` and marked as `Failed`.
- [ ]  Created PVC `lab34-redis-backup-pvc` and CronJob `lab34-redis-backup`.
- [ ]  Triggered backup manually via `kubectl create job --from=cronjob`, saw `.rdb` files in the PVC.
- [ ]  Experimented with `backoffLimit`, `activeDeadlineSeconds`, and `concurrencyPolicy` for CronJobs.
- [ ]  Added another CronJob.
- [ ]  Added a mini-section in runbook: “**Incident -  CronJob Not Running / Silent Failures**”.
- [ ]  Simulated an error (e.g., wrong Redis host) and observed CronJob behavior in logs/Events.

---

## Acceptance Criteria

- [ ]  Understand the difference between Deployment and Job, and when to use a CronJob.
- [ ]  Can check Job status: `succeeded`, `failed`, and whether `backoffLimit` was reached.
- [ ]  Can configure a CronJob that performs real work (Redis backup to PVC) and verify the result.
- [ ]  Know how to **suspend** a CronJob and how to clean up old Jobs/Pods.

---

## Summary

- Learned Jobs/CronJobs for one-off and recurring tasks in k8s.
- Configured a **real CronJob for Redis backup** saving `.rdb` files to a PersistentVolume.
- Now in k8s cluster has not only applications and monitoring, but also a basic **backup history**.

---

## Artifacts

- `labs/lesson_34/k8s/job-success.yaml`
- `labs/lesson_34/k8s/failing-job.yaml`
- `labs/lesson_34/k8s/backup-pvc.yaml`
- `labs/lesson_34/k8s/backup-pvc-testpod.yaml`
- `labs/lesson_34/k8s/cronjob-redis-backup.yaml`
