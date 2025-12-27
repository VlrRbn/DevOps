# lesson_38

---

# K8s cert-manager: Automatic TLS Certificates

**Date:** 2025-12-27

**Topic:** Install **cert-manager** in cluster, create a **(selfSigned → CA) ClusterIssuer**, and let cert-manager **auto-manage TLS Secrets** for an Ingress (`lab38.local`).

> Reuse:
> 
> - kind cluster `lab37`
> - namespace `lab37` (same app)
> - ingress-nginx
> 
> New:
> 
> - namespace `cert-manager`
> - namespace `lab38-cert`
> - host `lab38.local` for cert-manager-managed certificate

---

## Goals

- Install **cert-manager** in the cluster (CRDs + controllers).
- Understand key CRDs: **Issuer / ClusterIssuer / Certificate**.
- Create a **self-signed root** (ClusterIssuer) and a **CA Issuer** based on that root.
- Issue a TLS **Certificate** for `lab38.local` and let cert-manager maintain the Secret.
- Attach this Secret to an Ingress and verify HTTPS with `curl`.

---

## Pocket Cheat

| Thing / Resource | What it does | Why |
| --- | --- | --- |
| `Issuer` | Namespaced certificate issuer | Per-namespace CA/ACME |
| `ClusterIssuer` | Cluster-wide issuer | Reuse across namespaces |
| `Certificate` | Desired X.509 cert | cert-manager manages Secret |
| `cert-manager` controller | Reconciles Issuer/Certificate | Auto-renew/replace |
| `status.conditions` | Progress & errors | Debug issuance |
| `status.secretName` | Name of TLS Secret | Plug into Ingress |
| `kubectl describe certificate` | View events/conditions | Understand why it failed |

---

## Notes

- cert-manager is a TLS “operator”: declare **what you want**, and it handles CSRs, creates/updates Secrets, and watches certificate expiry.
- A typical production setup is: `ClusterIssuer (ACME/Let’s Encrypt)` → Certificates for your Ingresses.
- In the local lab build this chain:
    
    **selfSigned ClusterIssuer → CA Secret → CA Issuer → app Certificates**.
    

---

## Security Checklist

- Don’t commit private keys (`tls.key`, `ca.key`) to git.
- In this lesson, cert-manager stores keys inside Kubernetes Secrets — they stay **inside the cluster**.
- For a real cloud setup handle DNS/HTTP challenges and DNS API access separately — here a local self-signed CA only.

---

## Pitfalls

- Don’t mix up `Issuer` vs `ClusterIssuer`: an `Issuer` is namespaced (`metadata.namespace`), while a `ClusterIssuer` is cluster-scoped (no namespace).
- A `Certificate` creates the Secret **by name** via `spec.secretName`; don’t create it manually.
- Errors are usually visible in `kubectl describe certificate` → Events (e.g., “Issuer not found”).
- For ACME in the real world you need a publicly resolvable domain — here only doing a **self-signed CA**.

---
