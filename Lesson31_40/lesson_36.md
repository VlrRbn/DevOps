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
- Apply a small NetworkPolicy to `lab27` to limit access to Redis.
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
- For `lab27`, start with a policy that restricts Redis without breaking everything else.
- Rollback plan: `kubectl delete networkpolicy ...`.

---

## Pitfalls

- NetworkPolicy is **namespaced**: it only applies to Pods within its own namespace.
- If define ingress rules but forget about egress, egress remains allow-all by default (until add `egress` rules).
- Don’t forget DNS: when blocking egress, must explicitly allow traffic to kube-dns.

---