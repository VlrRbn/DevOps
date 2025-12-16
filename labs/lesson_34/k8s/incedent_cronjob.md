# lab34 Incident CronJob Not Running / Silent Failures

**Symptoms:**

* CronJob appears active (`kubectl get cronjob <name>`), but `LAST SCHEDULE` hasn’t updated for a while
* Job list is empty or missing expected runs (`kubectl get jobs --selector=job-name=<cronjob-name>`)
* No logs or outputs from CronJob

**Checklist:**

1. Check the CronJob:

```bash
kubectl get cronjob -n lab34
kubectl describe cronjob <name> -n lab34
```

2. Check Jobs created by the CronJob:

```bash
kubectl get jobs -n lab34 --selector=job-name=<name>
```

* Look for `SUCCEEDED` / `FAILED` status

3. Inspect logs of the last Job:

```bash
kubectl logs job/<job-name> -n lab34
```

4. Run a test Job manually to verify immediately:

```bash
kubectl create job --from=cronjob/<name> <name>-test -n lab34
kubectl logs job/<name>-test -n lab34
```

5. Check CronJob / Job events:

```bash
kubectl get events -n lab34 --sort-by=.metadata.creationTimestamp
```

* Look for errors like `failed to start pod` or `backoff`

**Fix:**

* Correct schedule / image / env / ConfigMap / Secret
* Delete failed Jobs if necessary:

```bash
kubectl delete job <failed-job-name> -n lab34
```

* Verify CronJob again after changes:

```bash
kubectl get cronjob <name> -n lab34
kubectl get jobs -n lab34
kubectl logs job/<job-name> -n lab34
```
