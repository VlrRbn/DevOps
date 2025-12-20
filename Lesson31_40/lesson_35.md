# lesson_35

---

# K8s RBAC Basics: ServiceAccounts, Roles & RoleBindings

**Date:** 2025-12-18

**Topic:** Learn **RBAC** in Kubernetes: create **ServiceAccounts**, **Role/ClusterRole**, **RoleBinding/ClusterRoleBinding**, and practice `kubectl auth can-i` to see who can do what.

> Use a dedicated namespace lab35-rbac and also re-use lab27 to show safe app ServiceAccounts.
> 

---

## Goals

- Understand the difference between **User**, **Group**, **ServiceAccount**.
- Create **Role** (namespaced) and **ClusterRole** (cluster-wide).
- Bind them with **RoleBinding/ClusterRoleBinding**.
- Practice checking permissions with `kubectl auth can-i` and test with real Pods.
- Prepare a small RBAC runbook for future apps (Prometheus, CI, etc.).

---

## Pocket Cheat

| Command / Thing | What it does | Why |
| --- | --- | --- |
| `ServiceAccount` | Identity for Pods | “User” inside cluster |
| `Role` | Permissions in one namespace | Fine-grained access |
| `ClusterRole` | Permissions cluster-wide | Nodes, namespaces, multi-ns |
| `RoleBinding` | Bind Role → User/SA in namespace | Namespaced access |
| `ClusterRoleBinding` | Bind ClusterRole → User/SA | Cluster/global access |
| `kubectl auth can-i ... --as=...` | Simulate another user | Test RBAC rules |
| `kubectl describe role/rolebinding` | Inspect rules & subjects | Debug access issues |

---

## Notes

- Kubernetes does not store users/passwords itself — RBAC simply says: **if** a request comes from subject X, **then** it is allowed or denied to do Y.
- In the real world:
    - humans → **User/Group** (OIDC, certificates),
    - applications → **ServiceAccount**.
- Kind cluster already has RBAC enabled — just adding rules.

---

## Security Checklist

- Do not grant `cluster-admin` unnecessarily; use only **read-only / limited** roles for training.
- New ServiceAccounts are used only in lab Pods.
- Anything powerful (ClusterRole) is defined carefully and clearly labeled in YAML.

---

## Pitfalls

- A `Role` only works within a single namespace. For cluster-wide resources, we need a **ClusterRole**.
- A `RoleBinding` to a ClusterRole is still **namespaced**: the ClusterRole’s permissions apply only within that namespace.
- `kubectl auth can-i` checks *whether* an action would be allowed, but doesn’t execute real commands — great for dry-run permission checks.

---

## Layout

```
labs/lesson_35/k8s/
├─ clusterrolebinding-read-all-ns.yaml
├─ clusterrole-read-all-ns.yaml
├─ rolebinding-configmap-editor.yaml
├─ rolebinding-viewer.yaml
├─ role-configmap-editor.yaml
├─ role-viewer.yaml
└─ serviceaccounts.yaml

```

---

## 1) Namespace for RBAC lab

`labs/lesson_35/k8s/lab35-namespace.yaml`:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: lab35-rbac
  labels:
    env: lab
    topic: rbac

```

Apply:

```bash
kubectl apply -f lab35-namespace.yaml
kubectl get ns

```

---

## 2) ServiceAccounts for this lab

Create a couple of ServiceAccounts in `lab35-rbac`:

`labs/lesson_35/k8s/serviceaccounts.yaml`:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: lab35-viewer
  namespace: lab35-rbac

---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: lab35-config-editor
  namespace: lab35-rbac

```

Apply:

```bash
kubectl apply -f serviceaccounts.yaml
kubectl get sa -n lab35-rbac

```

---

## 3) Role + RoleBinding: read-only viewer in lab35-rbac

### 3.1 Role: view Pods/Services/Deployments

`labs/lesson_35/k8s/role-viewer.yaml`:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: lab35-viewer-role
  namespace: lab35-rbac
rules:
  - apiGroups: [""]
    resources: ["pods", "services"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["pods/log"]
    verbs: ["get"]
  - apiGroups: ["apps"]
    resources: ["deployments", "replicasets"]
    verbs: ["get", "list", "watch"]

```

### 3.2 RoleBinding: bind Role → ServiceAccount

`labs/lesson_35/k8s/rolebinding-viewer.yaml`:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: lab35-viewer-binding
  namespace: lab35-rbac
subjects:
  - kind: ServiceAccount
    name: lab35-viewer
    namespace: lab35-rbac
roleRef:
  kind: Role
  name: lab35-viewer-role
  apiGroup: rbac.authorization.k8s.io

```

Apply:

```bash
kubectl apply -f role-viewer.yaml
kubectl apply -f rolebinding-viewer.yaml

kubectl get role,rolebinding -n lab35-rbac

```

---

## 4) Role: edit ConfigMaps only

We want to grant the second ServiceAccount permission to modify only ConfigMaps (and nothing else).

### 4.1 Role: configmap editor

`labs/lesson_35/k8s/role-configmap-editor.yaml`:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: lab35-configmap-editor-role
  namespace: lab35-rbac
rules:
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["get", "list", "watch", "create", "delete", "update", "patch"]

```

### 4.2 RoleBinding: bind to ServiceAccount

`labs/lesson_35/k8s/rolebinding-configmap-editor.yaml`:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: lab35-configmap-editor-binding
  namespace: lab35-rbac
subjects:
  - kind: ServiceAccount
    name: lab35-config-editor
    namespace: lab35-rbac
roleRef:
  kind: Role
  name: lab35-configmap-editor-role
  apiGroup: rbac.authorization.k8s.io

```

Apply:

```bash
kubectl apply -f role-configmap-editor.yaml
kubectl apply -f rolebinding-configmap-editor.yaml

kubectl get role,rolebinding -n lab35-rbac

```

---

## 5) Test RBAC with kubectl auth can-i

This is a demonstration of RBAC, not the creation of a real user.

Use impersonation (`--as`) to verify what this subject would be allowed to do.

### 5.1 lab35-viewer (should be readonly on pods/services/deployments)

```bash
# Can list pods in lab35-rbac?
kubectl auth can-i list pods -n lab35-rbac --as=system:serviceaccount:lab35-rbac:lab35-viewer

# Can get services?
kubectl auth can-i get services -n lab35-rbac --as=system:serviceaccount:lab35-rbac:lab35-viewer

# Can delete pods? (should be no)
kubectl auth can-i delete pods -n lab35-rbac --as=system:serviceaccount:lab35-rbac:lab35-viewer

# Can list configmaps? (no, not in role)
kubectl auth can-i list configmaps -n lab35-rbac --as=system:serviceaccount:lab35-rbac:lab35-viewer

```

Expecting:

- `list/get` pods/services/deployments → `yes`.
- `delete pods` / `list configmaps` → `no`.

### 5.2 lab35-config-editor (should manage ConfigMaps only)

```bash
# Can list configmaps?
kubectl auth can-i list configmaps -n lab35-rbac --as=system:serviceaccount:lab35-rbac:lab35-config-editor

# Can create configmaps?
kubectl auth can-i create configmaps -n lab35-rbac --as=system:serviceaccount:lab35-rbac:lab35-config-editor

# Can delete pods? (no)
kubectl auth can-i delete pods -n lab35-rbac --as=system:serviceaccount:lab35-rbac:lab35-config-editor

```

---

## 6) See it from inside a Pod (ServiceAccount in action)

Create a Pod that uses `lab35-config-editor` and try to create a ConfigMap.

```bash
kubectl run cm-editor-shell -n lab35-rbac \
  --image=registry.k8s.io/kubectl:v1.34.3 \
  --restart=Never \
  --overrides='{"spec":{"serviceAccountName":"lab35-config-editor"}}' \
  --command -- kubectl get cm -n lab35-rbac -w
```

Check Pod:

```bash
kubectl get pod cm-editor-shell -n lab35-rbac

# Check log
kubectl auth can-i get pods --subresource=log -n lab35-rbac \
  --as=system:serviceaccount:lab35-rbac:lab35-viewer
kubectl logs cm-editor-shell -n lab35-rbac \
  --as=system:serviceaccount:lab35-rbac:lab35-viewer

```

From outside, run commands inside the Pod:

```bash
# List configmaps (should be allowed)
kubectl exec -it cm-editor-shell -n lab35-rbac -- \
  kubectl get configmaps

# Create a test ConfigMap
kubectl exec -it cm-editor-shell -n lab35-rbac -- \
  kubectl create configmap lab35-test-cm --from-literal=foo=bar

# Patch a test ConfigMap
kubectl exec -it cm-editor-shell -n lab35-rbac -- \
  kubectl patch configmap lab35-test-cm --type merge -p '{"data":{"foo":"baz"}}'

# Try to list pods (should be forbidden)
kubectl exec -it cm-editor-shell -n lab35-rbac -- \
  kubectl get pods

# Check what role give rights
kubectl get rolebinding,clusterrolebinding -n lab35-rbac \
  -o wide | grep lab35-config-editor
  
# kubectl delete pod cm-editor-shell -n lab35-rbac
```

Inside the Pod, `kubectl` uses the ServiceAccount token, so RBAC is actually enforced.

---

## 7) ClusterRole: read-only across all namespaces

Create a ClusterRole that can read basic resources across the entire cluster, and bind it to a dummy user`lab35-readonly`.

`labs/lesson_35/k8s/clusterrole-read-all-ns.yaml`:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: lab35-read-all
rules:
  - apiGroups: [""]
    resources: ["pods", "services", "namespaces"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["apps"]
    resources: ["deployments", "statefulsets", "daemonsets"]
    verbs: ["get", "list", "watch"]

```

`labs/lesson_35/k8s/clusterrolebinding-read-all-ns.yaml`:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: lab35-read-all-binding
subjects:
  - kind: User
    name: lab35-readonly
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: lab35-read-all
  apiGroup: rbac.authorization.k8s.io

```

Apply:

```bash
kubectl apply -f clusterrole-read-all-ns.yaml
kubectl apply -f clusterrolebinding-read-all-ns.yaml

kubectl get clusterrole lab35-read-all
kubectl get clusterrolebinding lab35-read-all-binding

```

Проверка:

```bash
# Can list pods in any namespace (e.g., lab27)?
kubectl auth can-i list pods -n lab27 --as=lab35-readonly

# Can list namespaces?
kubectl auth can-i list namespaces --as=lab35-readonly

# Can delete pods? (should be no)
kubectl auth can-i delete pods -n lab27 --as=lab35-readonly

```

---

## 8) RBAC runbook

`labs/lesson_35/k8s/rbac_runbook.md`:

```markdown
# lab35 RBAC Runbook

## 1. Questions to ask

1. WHO is this? (ServiceAccount / User / Group)
2. WHERE do they work? (namespace(s))
3. WHAT exactly do they need? (resources + verbs)
4. HOW broad? (Role vs ClusterRole)

## 2. Common patterns

### Read-only viewer in namespace

- Subject: ServiceAccount or User
- Role:
  - apiGroups: "", resources: pods,services,verbs: get,list,watch
  - apiGroups: apps, resources: deployments,replicasets,verbs: get,list,watch
- Binding: RoleBinding in that namespace only

### Config-only editor

- Role with CRUD on configmaps/secrets only
- No permissions to touch pods/services/deployments

### Cluster-wide readonly

- ClusterRole with get/list/watch on namespaces,pods,services,deployments
- ClusterRoleBinding to User/Group for ops/support team

## 3. Debugging RBAC

1. kubectl auth can-i <verb> <resource> -n <ns> --as=<subject>
2. kubectl describe role/clusterrole <name>
3. kubectl describe rolebinding/clusterrolebinding <name>
4. Remember:
   - Role is namespaced
   - RoleBinding is namespaced
   - ClusterRoleBinding is cluster-wide

```

---

## Core

- [ ]  The `lab35-rbac` namespace and two ServiceAccounts are created.
- [ ]  `lab35-viewer-role` + RoleBinding provide read-only access to pods/services/deployments in `lab35-rbac`.
- [ ]  `lab35-configmap-editor-role` grants full access to ConfigMaps only.
- [ ]  Using `kubectl auth can-i`, can see the permission differences between subjects.
- [ ]  Via a Pod using the `lab35-config-editor` ServiceAccount, can create a ConfigMap and get `Forbidden` when running `kubectl get pods`.
- [ ]  A ClusterRole + ClusterRoleBinding give the `lab35-readonly` user read-only permissions across all namespaces.
- [ ]  Added 3 typical roles to runbook for future services (Prometheus, CI, etc.).
- [ ]  Can explain why **shouldn’t** run everything under the `default` ServiceAccount and `cluster-admin`.

---

## Acceptance Criteria

- [ ]  Understand the difference between ServiceAccount, Role, ClusterRole, RoleBinding, and ClusterRoleBinding.
- [ ]  Know how to check permissions using `kubectl auth can-i`.
- [ ]  Can create read-only and config-only roles and bind them to ServiceAccounts.
- [ ]  Can sketch RBAC for a new service.

---

## Summary

- Gained a practical, hands-on understanding of **Kubernetes RBAC**.
- Have examples of minimal, sane roles (viewer, config editor, cluster read-only).
- When adding a new service (Prometheus, CI, app), can **grant proper permissions from the start**, instead of handing out `cluster-admin`.

---

## Artifacts

- `labs/lesson_35/k8s/clusterrolebinding-read-all-ns.yaml`
- `labs/lesson_35/k8s/clusterrole-read-all-ns.yaml`
- `labs/lesson_35/k8s/rolebinding-configmap-editor.yaml`
- `labs/lesson_35/k8s/rolebinding-viewer.yaml`
- `labs/lesson_35/k8s/role-configmap-editor.yaml`
- `labs/lesson_35/k8s/role-viewer.yaml`
- `labs/lesson_35/k8s/serviceaccounts.yaml`
- `labs/lesson_35/k8s/rbac_runbook.md`