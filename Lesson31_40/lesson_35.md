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
