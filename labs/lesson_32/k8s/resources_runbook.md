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
