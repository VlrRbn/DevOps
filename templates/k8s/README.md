# Kubernetes YAML Templates

Copy a template, replace placeholders, then apply.

Files in this folder are intentionally minimal and safe for labs.

## Notes
- `deployment.yaml` references `APP_NAME-config` and `APP_NAME-secret` via `envFrom`.
  If you don't need them, remove those blocks or create the resources.
- `pv.yaml` uses `hostPath` (works on single-node/local clusters only).
- `pvc.yaml` uses `storageClassName: standard` (change to match your cluster).
- `networkpolicy-allow-namespace.yaml` allows ingress from the **same** namespace.
