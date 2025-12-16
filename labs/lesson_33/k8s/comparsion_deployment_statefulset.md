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
