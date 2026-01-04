# lesson_36

---

# K8s NetworkPolicies: Default Deny & Allow Rules

**Date:** 2025-12-20

**Topic:** Use **NetworkPolicy** to control which Pods can talk to which, starting with a **default deny** and then allowing only specific traffic (frontend → backend, DNS, monitoring).

---

## Goals

- Understand what **NetworkPolicy** does (and does not) control.
- Create a **default-deny** ingress policy for a namespace.
- Allow only **frontend → backend** HTTP traffic, and allow **DNS** lookups.
- Learn how to systematically **test** network policies from inside Pods.

---

## Pocket Cheat

| Thing / Command | What it does | Why |
| --- | --- | --- |
| `NetworkPolicy` | L4 rules for Pod traffic | Who can talk to whom |
| `podSelector` | Which Pods this policy applies to | Targets |
| `ingress` / `egress` | Allowed directions | Control in/out |
| `from` / `to` | Allowed peers (Pods/NS/IPs) | Whitelist only |
| `namespaceSelector` | Select by namespace labels | Cross-namespace rules |
| `kubectl exec ... -- nc` / `curl` | Connectivity tests | Verify policies |
| Default deny policy | Block all ingress (or egress) | Secure baseline |

---

## Notes

- NetworkPolicy works at **L3/L4** (IP/port/protocol); it does not understand HTTP methods, URLs, etc.
- By default, if there are **no** policies, everything is allowed (allow-all).
- As soon as **any policy** applies to a Pod, anything not explicitly allowed is denied (within the defined ingress/egress rules).

> A CNI plugin that supports NetworkPolicy is required.
> 

---

## Security Checklist

- Apply aggressive policies only in a separate namespace `lab36-netpol` first.
- Always have a rollback plan: `kubectl delete networkpolicy ...`.

---

## Pitfalls

- NetworkPolicy is **namespaced**: it only applies to Pods within its own namespace.
- If define ingress rules but forget about egress, egress remains allow-all by default (until add `egress` rules).
- Don’t forget DNS: when blocking egress, must explicitly allow traffic to kube-dns.

---

## Layout

```
labs/lesson_36/k8s/
├─ backend-configmap.yaml
├─ backend-deployment.yaml
├─ backend-service.yaml
├─ frontend-deployment.yaml
├─ netpol-allow-dns-egress.yaml
├─ netpol-allow-frontend-egress-to-backend.yaml
├─ netpol-allow-frontend-to-backend.yaml
├─ netpol-default-deny-ingress.yaml
└─ netpol-redis-lab27.yaml

```

---

## 0) Install Calico

```
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.31.2/manifests/operator-crds.yaml
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.31.2/manifests/tigera-operator.yaml

curl -O https://raw.githubusercontent.com/projectcalico/calico/v3.31.2/manifests/custom-resources.yaml
kubectl create -f custom-resources.yaml

kubectl get nodes
kubectl get pods -n tigera-operator
kubectl get pods -n calico-system

kubectl get crd | grep -i tigera
kubectl api-resources | grep -i tigera
```

## 1) Namespace & demo deployments

### 1.1 Namespace for netpol lab

`labs/lesson_36/k8s/lab36-namespace.yaml`:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: lab36-netpol
  labels:
    env: lab
    topic: netpol

```

Apply:

```bash
kubectl apply -f lab36-namespace.yaml
kubectl get ns

```

### 1.2 Backend: simple HTTP server

`labs/lesson_36/k8s/backend-configmap.yaml`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: lab36-backend-nginx-conf
  namespace: lab36-netpol
data:
  default.conf: |
    server {
      listen 80;
      server_name _;

      location = /health {
        access_log off;
        default_type text/plain;
        return 200 "ok\n";
      }

      location / {
        access_log off;
        default_type text/html;
        return 200 "Welcome to lab36-backend\n";
      }
    }

```

`labs/lesson_36/k8s/backend-deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: lab36-backend
  namespace: lab36-netpol
  labels:
    app: lab36-backend
    tier: backend
spec:
  replicas: 1
  selector:
    matchLabels:
      app: lab36-backend
  template:
    metadata:
      labels:
        app: lab36-backend
        tier: backend
    spec:
      containers:
        - name: backend
          image: nginx:1.27-alpine
          ports:
            - containerPort: 80
              name: http
          volumeMounts:
            - name: nginx-conf
              mountPath: /etc/nginx/conf.d/default.conf
              subPath: default.conf
              readOnly: true
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 200m
              memory: 128Mi
          readinessProbe:
            httpGet:
              path: /health
              port: 80
            initialDelaySeconds: 5
            periodSeconds: 5
          livenessProbe:
            httpGet:
              path: /health
              port: 80
            initialDelaySeconds: 15
            periodSeconds: 10
      volumes:
        - name: nginx-conf
          configMap:
            name: lab36-backend-nginx-conf

```

`labs/lesson_36/k8s/backend-service.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: lab36-backend
  namespace: lab36-netpol
  labels:
    app: lab36-backend
spec:
  type: ClusterIP
  selector:
    app: lab36-backend
  ports:
    - name: http
      port: 80
      targetPort: 80
      protocol: TCP

```

### 1.3 Frontend: curl client

`labs/lesson_36/k8s/frontend-deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: lab36-frontend
  namespace: lab36-netpol
  labels:
    app: lab36-frontend
    tier: frontend
spec:
  replicas: 1
  selector:
    matchLabels:
      app: lab36-frontend
  template:
    metadata:
      labels:
        app: lab36-frontend
        tier: frontend
    spec:
      containers:
        - name: client
          image: curlimages/curl:8.11.1
          command: ["/bin/sh", "-c"]
          args:
            - |
              echo "Lab36 frontend started, sleeping...";
              sleep 3600;
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 200m
              memory: 128Mi

```

Apply all:

```bash
kubectl apply -f backend-configmap.yaml
kubectl apply -f backend-deployment.yaml
kubectl apply -f backend-service.yaml
kubectl apply -f frontend-deployment.yaml

# kubectl get pods -n lab36-netpol -o wide
# kubectl get svc -n lab36-netpol

```

---

## 2) Baseline connectivity (before NetworkPolicies)

Verify that without any policies, everything is reachable.

```bash
FRONT=$(kubectl get pod -n lab36-netpol -l app=lab36-frontend -o jsonpath='{.items[0].metadata.name}')

kubectl exec -it "$FRONT" -n lab36-netpol -- curl -sS -i http://lab36-backend

```

Expected: HTML response from nginx.

---

## 3) Default deny ingress in lab36-netpol

Create a policy that denies all ingress to Pods in the namespace by default.

`labs/lesson_36/k8s/netpol-default-deny-ingress.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: lab36-default-deny-ingress
  namespace: lab36-netpol
spec:
  podSelector: {}     # select ALL pods in this namespace
  policyTypes:
    - Ingress

```

> Important: podSelector: {} + policyTypes: [Ingress] with no ingress rules → no incoming traffic is allowed.
> 

Apply:

```bash
kubectl apply -f netpol-default-deny-ingress.yaml
kubectl get networkpolicy -n lab36-netpol

```

Now try `curl` again:

```bash
kubectl exec -it "$FRONT" -n lab36-netpol -- \
  curl -sS --max-time 5 http://lab36-backend || echo "curl failed"

```

Expected: timeout / connection refused → ingress is blocked.

---

## 4) Allow frontend → backend (same namespace)

Next, allow traffic only from frontend Pods to backend Pods on TCP/80.

`labs/lesson_36/k8s/netpol-allow-frontend-to-backend.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: lab36-allow-frontend-to-backend
  namespace: lab36-netpol
spec:
  podSelector:
    matchLabels:
      tier: backend
      app: lab36-backend
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              tier: frontend
              app: lab36-frontend
      ports:
        - protocol: TCP
          port: 80

```

Explanation:

- Target: all Pods with `app=lab36-backend`.
- Rule: allow traffic from Pods with `app=lab36-frontend` to port 80/TCP.
- Everything else (other Pods, other ports) is blocked.

Apply:

```bash
kubectl apply -f netpol-allow-frontend-to-backend.yaml
kubectl get networkpolicy -n lab36-netpol

```

Test:

```bash
kubectl exec -it "$FRONT" -n lab36-netpol -- curl -sS -i http://lab36-backend

```

Everything should work.

---

## 5) Egress & DNS: allow DNS lookups

Restrict outbound traffic.

Сreate a policy that:

- selects all Pods,
- sets `policyTypes: [Egress]`,
- allows **only DNS** egress (TCP/UDP 53) to kube-dns in the `kube-system` namespace.

Assume kube-dns is labeled `k8s-app=coredns` in `kube-system`.

`labs/lesson_36/k8s/netpol-allow-dns-egress.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: lab36-allow-dns-egress
  namespace: lab36-netpol
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53

```

`labs/lesson_36/k8s/netpol-allow-frontend-egress-to-backend.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: lab36-allow-frontend-egress-to-backend
  namespace: lab36-netpol
spec:
  podSelector:
    matchLabels:
      tier: frontend
      app: lab36-frontend
  policyTypes:
    - Egress
  egress:
    - to:
        - podSelector:
            matchLabels:
              tier: backend
              app: lab36-backend
      ports:
        - protocol: TCP
          port: 80

```

Apply policy:

```bash
kubectl apply -f netpol-allow-dns-egress.yaml
kubectl apply -f netpol-allow-frontend-egress-to-backend.yaml
kubectl get networkpolicy -n lab36-netpol

kubectl get ns kube-system --show-labels | tr ',' '\n' | grep 'kubernetes.io/metadata.name'
```

Now all Pods in `lab36-netpol`:

- can only make outbound DNS queries,
- all other egress traffic will be blocked (unless allowed by other egress NetworkPolicies).

Try it out:

```bash
kubectl exec -it "$FRONT" -n lab36-netpol -- \
  nslookup kubernetes.io || echo "nslookup failed"

# Ping or curl to outside IPs to see they're blocked
kubectl exec -it "$FRONT" -n lab36-netpol -- \
  wget -qO- http://google.com || echo "wget failed"

kubectl exec -it "$FRONT" -n lab36-netpol -- sh -c \
'wget -T 5 -t 1 -qO- http://google.com >/dev/null || echo "wget failed"'
```

---

## 6) Mini netpol runbook

```markdown
# lab36 NetworkPolicy Runbook

## 1. Questions to ask

1. Which pods are we **protecting**? (podSelector)
2. Which traffic directions? (ingress / egress / both)
3. Who exactly should be allowed? (from/to – podSelector, namespaceSelector, ipBlock)
4. What ports/protocols should be allowed?

## 2. Default-deny pattern

- For a namespace:
  - Ingress default-deny: NetworkPolicy with `podSelector: {}` and no ingress rules.
  - Egress default-deny: `policyTypes: [Egress]` and no egress rules.

Then add specific allow policies.

## 3. Debugging

1. Check policies:
   - `kubectl get networkpolicy -n <ns>`
   - `kubectl describe networkpolicy <name> -n <ns>`
2. From inside a Pod:
   - `kubectl exec -it <pod> -n <ns> -- curl / nc`
3. If in doubt, temporarily delete the policy:
   - `kubectl delete networkpolicy <name> -n <ns>`

```

---

## 7) Example for lab27: restrict Redis access

Apply a NetworkPolicy for **Redis in `lab27`**:

allow ingress only from:

- `lab27-web` Pods.

`labs/lesson_36/k8s/netpol-redis-lab27.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: lab27-redis-ingress
  namespace: lab27
spec:
  podSelector:
    matchLabels:
      app: lab27-redis
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: lab27-web
     #  - podSelector:
     #      matchLabels:
     #        app: lab34-redis-backup
      ports:
        - protocol: TCP
          port: 6379

```

Apply:

```bash
kubectl apply -f netpol-redis-lab27.yaml
kubectl get networkpolicy -n lab27

```

Verification:

1. From a `lab27-web` Pod, Redis should be reachable.
2. From any “unrelated” Pod in `lab27` without the allowed labels, the connection to Redis should be blocked (timeout / connection refused).

Example check (assuming have a `redis-cli` Pod, or launch one temporarily):

```bash
kubectl run test-redis-denied -n lab27 \
  --image=redis:7-alpine \
  --restart=Never \
  --command -- sh -c 'timeout 5 redis-cli -h lab27-redis ping; echo "exit_code=$?"'

kubectl logs test-redis-denied -n lab27
# Ожидаемо: не сможет подключиться, если pod не имеет нужных labels

# kubectl get pod -n lab27 -o wide | grep test-redis-denied || true
# kubectl describe pod -n lab27 test-redis-denied

```

```bash
kubectl run test-redis-allowed -n lab27 \
  --image=redis:7-alpine --restart=Never \
  --labels=app=lab27-web \
  --command -- sh -c 'timeout 5 redis-cli -h lab27-redis ping; echo "exit_code=$?"'

kubectl logs test-redis-allowed -n lab27
# Ожидаемо: cможет подключиться, pod имеет нужные labels

```

If you broke something:

```bash
kubectl delete pod test-redis-denied -n lab27
kubectl delete pod test-redis-allowed -n lab27
kubectl delete networkpolicy lab27-redis-ingress -n lab27

```

---

## Core

- [ ]  `lab36-netpol` namespace and the frontend/backend Deployments are deployed.
- [ ]  The default-deny ingress policy in `lab36-netpol` actually breaks frontend → backend traffic.
- [ ]  The `lab36-allow-frontend-to-backend` policy restores only that specific traffic.
- [ ]  Understand that egress is allowed by default and how to restrict it (e.g., to DNS only).
- [ ]  Added the `lab36-allow-dns-egress` policy and saw external HTTP get blocked while DNS still works.
- [ ]  Wrote 1–2 reusable templates for yourself: namespace default-deny, allow app-to-db, allow monitoring-to-app.

---

## Acceptance Criteria

- [ ]  Understand that NetworkPolicy only operates at L3/L4 and within the namespace scope.
- [ ]  Can implement a default-deny policy and then explicitly allow the required flows on top of it.
- [ ]  Have a short checklist for testing NetworkPolicies using `kubectl exec` and tools like `curl` / `nc`.

---

## Summary

- Taught the cluster to **stop trusting everyone by default** and to explicitly define who is allowed to talk to whom.
- Built a learning playground (`lab36-netpol`).
- Clear model: **RBAC → who can make API requests**, **NetworkPolicy → who can talk over the network**.

---

## Artifacts

- `labs/lesson_36/k8s/backend-configmap.yaml`
- `labs/lesson_36/k8s/backend-deployment.yaml`
- `labs/lesson_36/k8s/backend-service.yaml`
- `labs/lesson_36/k8s/frontend-deployment.yaml`
- `labs/lesson_36/k8s/netpol-allow-dns-egress.yaml`
- `labs/lesson_36/k8s/netpol-allow-frontend-egress-to-backend.yaml`
- `labs/lesson_36/k8s/netpol-allow-frontend-to-backend.yaml`
- `labs/lesson_36/k8s/netpol-default-deny-ingress.yaml`
- `labs/lesson_36/k8s/netpol-redis-lab27.yaml`
