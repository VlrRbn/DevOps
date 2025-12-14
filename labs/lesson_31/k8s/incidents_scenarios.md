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
