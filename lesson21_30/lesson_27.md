# lesson_27

---

# Kubernetes Intro: Run lab Web + Redis on a Local k8s Cluster

**Date:** 2025-11-30

**Topic:** Run a minimal Kubernetes cluster locally (kind), deploy web+Redis app (lab25-style) with Deployments and Services, configure basic probes, and learn core `kubectl` workflows.

> Use localhost, 127.0.0.1, or internal k8s names like *.cluster.local.
> 

---

## Goals

- Understand **core k8s objects**: Namespace, Pod, Deployment, Service.
- Create a local k8s cluster with **kind** (Kubernetes in Docker).
- Containerize app using **existing lab25 image** (from registry or local).
- Deploy **Redis** + **web** as Deployments, expose via Service.
- Use `kubectl` to inspect Pods, logs, and basic connectivity (port-forward).

---

## Pocket Cheat

| Command / File | What it does | Why |
| --- | --- | --- |
| `kind create cluster --name lab27 --config kind-config.yaml` | Create local k8s cluster | Sandbox |
| `kubectl get pods -n lab27` | List Pods | See what’s running |
| `kubectl describe pod …` | Detailed Pod info | Debug issues |
| `kubectl logs deploy/lab27-web -n lab27` | App logs | Check web behavior |
| `kubectl apply -f labs/lesson_27/k8s/` | Apply YAMLs | Deploy/update |
| `kubectl delete -f …` | Remove resources | Cleanup |
| `kubectl port-forward svc/lab27-web -n lab27 8080:8080` | Expose service to localhost | Test from host |
| `deployment.yaml` | Desired state for Pods | Self-healing |

---

## Notes

- k8s is a **“desired state machine”**: you declare what you want, and controllers continuously try to make the actual state match that desired state.
- A `Deployment` manages Pods (replicas, rollouts, restarts).
- A `Service` provides a stable DNS name / virtual IP for accessing Pods.
- We use `kind` — a lightweight local Kubernetes cluster that runs inside Docker.

---

## Security Checklist

- The cluster is only accessible locally (kind does not listen on the public internet by default).
- **Do NOT expose NodePorts directly to the outside world** — use the safer option `kubectl port-forward`.
- Do not put secrets into manifests; only use non-sensitive env vars (like `LAB_ENV`, etc.).

---

## Pitfalls

- Local Docker images are not visible inside kind until you run `kind load docker-image`.
- Wrong `image:` value (typo, wrong tag) → Pod gets stuck in `ImagePullBackOff`.
- Missing readiness/liveness probes → k8s can’t detect that the container is dead or not ready.
- Running `kubectl apply` without `n` → resources are created in the `default` namespace while you’re looking for them in `lab27` (or the other way around).

---

## Layout

```
labs/lesson_27/k8s/
├─ kind-config.yaml
├─ namespace.yaml
├─ redis-deployment.yaml
├─ redis-service.yaml
├─ web-deployment.yaml
└─ web-service.yaml
```

Reuse **lab25 web** behavior (Flask + Redis), but run it on k8s.

---

## 1) Install & sanity: kind + kubectl

*(If already have them, just verify versions and skip install.)*

### 1.1 kubectl version (sanity)

```bash
kubectl version --client
```

If not installed (Ubuntu):

```bash
# Installation (check official docs if needed):

# Create key dir
sudo install -m 0755 -d /etc/apt/keyrings

# Repo key v1.30
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key \
  | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

sudo chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# Repo
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /' \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list > /dev/null

sudo chmod 644 /etc/apt/sources.list.d/kubernetes.list

# Update and install
sudo apt-get update
sudo apt-get install -y kubectl
```

### 1.2 Install kind

```bash
# Download kind (Linux AMD64 example)
curl -Lo ./kind "https://kind.sigs.k8s.io/dl/latest/kind-linux-amd64"
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind

kind version
```

---

## 2) kind cluster for lab27

Create `labs/lesson_27/k8s/kind-config.yaml`:

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: lab27
nodes:
  - role: control-plane
    extraPortMappings:
      # Optional: map NodePort range
      # - containerPort: 30080
      #   hostPort: 30080
      #   protocol: TCP
```

Create cluster:

```bash
cd labs/lesson_27/k8s
kind create cluster --config kind-config.yaml
```

Check nodes:

```bash
kubectl get nodes
```

---

## 3) Namespace for this lab

`labs/lesson_27/k8s/namespace.yaml`:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: lab27
  labels:
    env: lab
```

Apply:

```bash
kubectl apply -f labs/lesson_27/k8s/namespace.yaml
kubectl get ns
```

---

## 4) Redis Deployment + Service

### 4.1 Redis Deployment

`labs/lesson_27/k8s/redis-deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: lab27-redis
  namespace: lab27
  labels:
    app: lab27-redis
    tier: backend
spec:
  replicas: 1
  selector:
    matchLabels:
      app: lab27-redis
  template:
    metadata:
      labels:
        app: lab27-redis
        tier: backend
    spec:
      containers:
        - name: redis
          image: redis:7-alpine
          args: ["redis-server", "--save", "60", "1", "--loglevel", "warning"]
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

### 4.2 Redis Service (ClusterIP)

`labs/lesson_27/k8s/redis-service.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: lab27-redis
  namespace: lab27
  labels:
    app: lab27-redis
spec:
  type: ClusterIP
  selector:
    app: lab27-redis
  ports:
    - name: redis
      port: 6379
      targetPort: 6379
```

Apply:

```bash
kubectl apply -f labs/lesson_27/k8s/redis-deployment.yaml
kubectl apply -f labs/lesson_27/k8s/redis-service.yaml

kubectl get deploy,svc -n lab27
kubectl get pods -n lab27
```

---

## 5) Web Deployment (lab25 image) + Service

Two options for the image:

- **Registry image**: e.g. `ghcr.io/vlrrbn/lab25-web-workflows:latest`.
- **Local image**: build `lab25-web-workflows:dev` and load into kind.

### 5.0 If using local image

From repo root:

```bash
# Build image reusing lesson_25 Dockerfile
cd labs/lesson_25/app
docker build -t lab25-web-workflows:dev .

# Load into kind so the cluster can see it
# kind get clusters
kind load docker-image lab25-web-workflows:dev --name lab27
```

Then set `image: lab25-web-workflows:dev` in web Deployment.

If already push to GHCR/Docker Hub, just use full registry name.

### 5.1 Web Deployment

`labs/lesson_27/k8s/web-deployment.yaml`:

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
          # Use either local or registry image:
          # image: lab25-web:dev
          image: ghcr.io/vlrrbn/lab25-web:latest
          imagePullPolicy: IfNotPresent
          env:
            - name: LAB_ENV
              value: "lab"
            - name: PORT
              value: "8080"
            - name: REDIS_HOST
              value: "lab27-redis"
            - name: REDIS_PORT
              value: "6379"
            - name: REDIS_DB
              value: "0"
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

### 5.2 Web Service (ClusterIP)

`labs/lesson_27/k8s/web-service.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: lab27-web
  namespace: lab27
  labels:
    app: lab27-web
spec:
  type: ClusterIP
  selector:
    app: lab27-web
  ports:
    - name: http
      port: 8080
      targetPort: 8080

```

Apply:

```bash
kubectl apply -f labs/lesson_27/k8s/web-deployment.yaml
kubectl apply -f labs/lesson_27/k8s/web-service.yaml

kubectl get deploy,svc -n lab27
kubectl get pods -n lab27
```

---

## 6) Test from host via port-forward

We keep Services as `ClusterIP` and use `port-forward`:

```bash
# Terminal 1
kubectl port-forward svc/lab27-web -n lab27 8080:8080

# sudo lsof -i :8080
# kubectl port-forward svc/lab27-web -n lab27 18080:8080
```

Then from host (Terminal 2):

```bash
curl -s http://localhost:8080/ | jq
curl -s http://localhost:8080/health | jq

# kubectl get pods -n lab27 -o wide
# kubectl logs deploy/lab27-web -n lab27
```

Expected:

- JSON with `message`, `env="lab"`, and `hit_count` increasing.
- `/health` should show `redis_ok: true` once Redis is ready.

---

## 7) Basic kubectl diagnostics

Useful commands while pods are starting:

```bash
# List everything in lab27 namespace
kubectl get all -n lab27

# Detailed info about pod
kubectl describe pod -l app=lab27-web -n lab27

# Logs
kubectl logs deploy/lab27-web -n lab27
kubectl logs deploy/lab27-redis -n lab27

# Watch pods
kubectl get pods -n lab27 -w
kubectl get pods -n lab27 -l app=lab27-redis
```

Common statuses:

- `ContainerCreating` → pulling images and preparing the container.
- `CrashLoopBackOff` → the application keeps crashing on start (check the logs).
- `ImagePullBackOff` → k8s cannot pull the image (wrong image/tag or missing auth).

---

## 8) Cleanup

When done:

```bash
# Delete only lab27 namespace (and all inside)
kubectl delete namespace lab27

# Or selectively:
kubectl delete -f labs/lesson_27/k8s/

# Delete kind cluster
kind delete cluster --name lab27
```

---

## Core

- [ ]  Installed/verified `kubectl` and `kind`.
- [ ]  Created kind cluster and `lab27` namespace.
- [ ]  Deployed Redis + web via Deployments and Services.
- [ ]  Confirmed `/` and `/health` via `kubectl port-forward`.
- [ ]  Switched between **local image** (`kind load docker-image`) and **registry image**.
- [ ]  Broke something on purpose (wrong image tag, bad env) and debugged with `kubectl describe` + `kubectl logs`.
- [ ]  Tweaked `replicas` in `web` Deployment (e.g. 2–3) and saw multiple Pods and stable Service.
- [ ]  Added labels `env`/`service` in your manifests consistently (preparing for future monitoring in k8s).

---

## Acceptance Criteria

- [ ]  **Create & destroy** a local k8s cluster with kind.
- [ ]  Deploy a simple app stack (web + Redis) using Deployment + Service.
- [ ]  Reach the app via `kubectl port-forward` and see Redis-backed `hit_count`.
- [ ]  Inspect Pods, logs, Services, and understand basic states (`Running`, `CrashLoopBackOff`, etc.).

---

## Summary

- Went from Docker/Compose to **basic Kubernetes**: Pods, Deployments, Services, Namespaces.
- Deployed your own app (not some hello-nginx) onto a local cluster with kind.
- Learned how to access it via `kubectl port-forward` and debug it with `kubectl` commands.
- This is the foundation for next steps: ConfigMaps/Secrets, Ingress, k8s-native observability, and eventually Helm/Operators.

---

## Artifacts

- `lesson_27.md`
- `labs/lesson_27/k8s/{kind-config.yaml,namespace.yaml,redis-deployment.yaml,redis-service.yaml,web-deployment.yaml,web-service.yaml}`