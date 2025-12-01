# lesson_28

---

# Kubernetes Config: ConfigMap, Secret & Ingress for lab27 Web

**Date:** 2025-12-01

**Topic:** Take **lab27 web+redis app** on k8s and add proper configuration with **ConfigMap + Secret**, plus expose it via **Ingress** (ingress-nginx on kind) instead of `kubectl port-forward`.

> Reuses: kind cluster lab27 + namespace lab27 + lab27-redis from lesson_27.
> 
> 
> Use `lab27.local`.
> 

---

## Goals

- Separate app configuration into **ConfigMap** (non-secret) and **Secret** (sensitive-ish).
- Wire environment variables in `lab27-web` Deployment via `envFrom`.
- Install **ingress-nginx** in kind cluster.
- Create **Ingress** object for host `lab27.local` and route `/` → `lab27-web`.
- Test access via normal `http://lab27.local/` (no port-forward).

---

## Pocket Cheat

| Command / File | What it does | Why |
| --- | --- | --- |
| `web-config.yaml` | ConfigMap + Secret | Externalized config |
| `web-deployment.yaml` | Updated Deployment using envFrom | No hardcoded env |
| `web-ingress.yaml` | Ingress for lab27-web | HTTP entrypoint |
| `kubectl apply -f labs/lesson_28/k8s/` | Apply all changes | Update app |
| `kubectl get ingress -n lab27` | Check Ingress | DNS/paths |
| `curl http://lab27.local/` | Test through Ingress | Realistic access |
| `kubectl logs deploy/lab27-web -n lab27` | Check app logs | Debug config issues |

---

## Notes

- **ConfigMap** – non-secret configuration (strings/keys, flags, hosts, etc.).
- **Secret** – base64-encoded values (not real encryption, but at least not in plain YAML).
- Ingress is a kind of “reverse proxy” inside k8s. Together with an ingress controller it receives external HTTP traffic and routes it to a Service.
- We do **not** modify the Redis Deployment/Service from lesson_27 — we only **add** config and Ingress for the web app.

---

## Security Checklist

- **Do NOT put real passwords** in the repo, even inside a Secret. Use a dummy/training token/key.
- Config that is truly sensitive (SMTP creds, API tokens, etc.) in production must come from the **outside** (Vault, CI, sealed secrets, etc.), not hardcoded in manifests.
- The Ingress only listens on `lab27.local`, which is mapped in `/etc/hosts` → access is still local to your machine.

---

## Pitfalls

- Missing or wrong `namespace` in the ConfigMap/Secret/Ingress manifest → they get created in `default`, and the Deployment can’t see them.
- Name mismatch (`name: lab27-web-config` vs `configMapRef.name: ...`) → the container starts without the required env vars.
- Ingress will not work until an **ingress controller** (like ingress-nginx) is installed.
- `lab27.local` not added to `/etc/hosts` → curl/browser has no idea where to send the request.

---

## Layout

```
labs/lesson_28/k8s/
├─ web-config.yaml      # ConfigMap + Secret
├─ web-deployment.yaml  # Updated web Deployment (v2)
└─ web-ingress.yaml     # Ingress for lab27-web
```

> Namespace lab27, Redis Deployment/Service — stay from lesson_27.
> 

---

## 0) kind-config from lab27

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: lab27
nodes:
  - role: control-plane
    extraPortMappings:
      - containerPort: 80
        hostPort: 80
        protocol: TCP
      - containerPort: 443
        hostPort: 443
        protocol: TCP
```

> Apply: `kind create cluster --config kind-lab27.yaml`
> 

---

## 1) ConfigMap + Secret for lab27-web

Create new manifests; they will live separately from `lesson_27` but use the same namespace.

### 1.1 ConfigMap + Secret

`labs/lesson_28/k8s/web-config.yaml`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: lab27-web-config
  namespace: lab27
data:
  LAB_ENV: "lab"
  PORT: "8080"
  REDIS_HOST: "lab27-redis"
  REDIS_PORT: "6379"
  REDIS_DB: "0"
  FEATURE_FLAG_SHOW_HITS: "true"

---
apiVersion: v1
kind: Secret
metadata:
  name: lab27-web-secret
  namespace: lab27
type: Opaque
stringData:
  APP_SECRET_KEY: "dev-secret-key-lab27"
  FAKE_API_TOKEN: "lab27-demo-token"

```

> Use `stringData` → k8s will automatically encode it to base64 and store it in `.data`.
> 
> 
> The app doesn’t use this yet, but later you can add a log/endpoint to show that the env vars are available (or just check them with `kubectl exec -- env`).
> 

Apply & check:

```bash
kubectl apply -f web-config.yaml

kubectl get configmap,secret -n lab27
kubectl describe configmap lab27-web-config -n lab27
kubectl describe secret lab27-web-secret -n lab27

# kubectl get configmap lab27-web-config -n lab27 -o yaml
```

---

## 2) Update web Deployment to use envFrom

Don’t patch the old file in-place — create a v2 Deployment for lesson_28 instead; it will overwrite the existing `lab27-web` Deployment.

`labs/lesson_28/k8s/web-deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: lab27-web
  namespace: lab27
  labels:
    app: lab27-web
    tier: frontend
spec:
  replicas: 1
  selector:
    matchLabels:
      app: lab27-web
  template:
    metadata:
      labels:
        app: lab27-web
        tier: frontend
        service: labweb
        env: lab
    spec:
      containers:
        - name: web
          image: ghcr.io/VlrRbn/lab25-web:latest
          imagePullPolicy: IfNotPresent
          envFrom:
            - configMapRef:
                name: lab27-web-config
            - secretRef:
                name: lab27-web-secret
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

> Differences from lesson_27:
> 
> - No manual `env:` list → use `envFrom` (ConfigMap + Secret).
> - The update is **idempotent**: any `kubectl apply` brings the Deployment to the same state.

Apply:

```bash
kubectl apply -f web-deployment.yaml

kubectl get deploy -n lab27
kubectl get pods -n lab27
```

Check that the env vars made it into the container:

```bash
POD=$(kubectl get pod -n lab27 -l app=lab27-web -o jsonpath='{.items[0].metadata.name}')
kubectl exec -it "$POD" -n lab27 -- env | grep -E 'LAB_ENV|REDIS_|APP_SECRET_KEY|FAKE_API_TOKEN'
```

---

## 3) Install ingress-nginx (kind)

> This is done once per cluster. If an ingress controller is already installed, just check the Pods.
> 

Command (official manifest for the kind provider, can be pulled from the internet):

```bash
kubectl apply -f \
  https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
```

Wait until everything is up and running:

```bash
kubectl get pods -n ingress-nginx -w
```

Wait for the `ingress-nginx-controller` Pod to reach `Running` state (this can take 30–60 seconds).

> This manifest configures ingress-nginx with hostPort/NodePort so that it listens on port 80 on the host (inside kind). There’s no need to change the kind config.
> 

---

## 4) Ingress for lab27-web

`labs/lesson_28/k8s/web-ingress.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: lab27-web
  namespace: lab27
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
    - host: lab27.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: lab27-web
                port:
                  number: 8080
```

> Use the host lab27.local and the IngressClass nginx (that’s the default name for ingress-nginx).
> 
> 
> Requests to `http://lab27.local/...` will be routed to the `lab27-web:8080` Service.
> 

Apply:

```bash
kubectl apply -f web-ingress.yaml

kubectl get ingress -n lab27
kubectl describe ingress lab27-web -n lab27
```

---

## 5) /etc/hosts — make `lab27.local` resolve

On the host machine (Ubuntu), add the following line to `/etc/hosts`:

```bash
sudo sh -c 'echo "127.0.0.1 lab27.local" >> /etc/hosts'
```

Проверка:

```bash
ping -c1 lab27.local
# resolve in 127.0.0.1
```

---

## 6) Test via Ingress

Now — no more port-forward. Just run:

```bash
curl -s http://lab27.local/ | jq
curl -s http://lab27.local/health | jq
```

Expected:

- The `/` endpoint should return the same JSON as in lesson_27 with port-forward (message, env, hit_count, redis_ok).
- The `/health` endpoint should return `status=ok`, `redis_ok=true`.

If something is off, check:

```bash
kubectl get pods -A
kubectl get svc -A
kubectl get ingress -A
kubectl describe ingress lab27-web -n lab27
kubectl logs -n ingress-nginx deploy/ingress-nginx-controller | tail -n 50
kubectl logs -n lab27 deploy/lab27-web | tail -n 50
```

---

## Core

- [ ]  Created a `ConfigMap` + `Secret` and wired them into the Deployment via `envFrom`.
- [ ]  `kubectl exec -- env` shows `LAB_ENV`, `REDIS_*` and `APP_SECRET_KEY` inside the container.
- [ ]  Installed ingress-nginx and confirmed the controller is `Running`.
- [ ]  Created the `lab27-web` Ingress and accessed the app via `http://lab27.local/`.
- [ ]  Added extra settings to the ConfigMap (for example, log level, feature flags) and verified their usage in the app (via logs or an endpoint).
- [ ]  Simulated a failure (incorrect `REDIS_HOST` in the ConfigMap) and debugged the issue using `kubectl describe` + logs.
- [ ]  Added a second path to the Ingress (for example, `/healthz` → same backend) and verified the routing.
- [ ]  Prepared a short cheat table for yourself: “ConfigMap vs Secret vs env vs args” with examples.

---

## Acceptance Criteria

- [ ]  The web Pod in k8s no longer keeps config hardcoded — it gets it via ConfigMap/Secret.
- [ ]  You understand how to change values in a ConfigMap/Secret and in which order to run `kubectl apply` / `kubectl rollout restart`.
- [ ]  The Ingress controller is installed and you know how to check its status.
- [ ]  You can open the app at `http://lab27.local/` and know how to debug Ingress-related issues.

---

## Summary

- Moved the web app configuration into **k8s ConfigMap + Secret**, instead of stuffing the Deployment with a pile of env vars.
- Brought up **ingress-nginx** and configured an **Ingress** for the service instead of relying on port-forward.
- **Actual traffic path**: `Client → Ingress → Service → Pod (web) → Service (redis) → Pod (redis)`.

---

## Artifacts

- `lesson_28.md`
- `labs/lesson_28/k8s/web-config.yaml`
- `labs/lesson_28/k8s/web-deployment.yaml`
- `labs/lesson_28/k8s/web-ingress.yaml`