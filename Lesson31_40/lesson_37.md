# lesson_37

---

# K8s TLS: Ingress HTTPS with Self-Signed / mkcert

**Date:** 2025-12-26

**Topic:** Add **HTTPS** to `lab37` Ingress using a **TLS Secret** in Kubernetes. Generate a cert (self-signed or `mkcert`), configure Ingress to use it, and test with `curl` + browser.

> Use:
> 
> - kind cluster `lab37`
> - namespace `lab37`
> - existing Ingress `lab37.local`
> - ingress-nginx as the Ingress controller

---

## Goals

- Understand how **Ingress + TLS Secret** gives you HTTPS in k8s.
- Generate a **local certificate** (self-signed or mkcert) for `lab37.local`.
- Create a **TLS Secret** in `lab37` namespace and use it in Ingress.
- Test HTTPS with `curl -vk https://lab37.local` and browser.
- Capture a small **TLS runbook** for future clusters.

---

## Pocket Cheat

| Thing / Command | What it does | Why |
| --- | --- | --- |
| `openssl req -x509 ...` | Generate self-signed cert | Quick local TLS |
| `mkcert lab37.local` | Generate trusted local cert | No scary browser warning |
| `kubectl create secret tls ...` | Create TLS Secret from crt/key | Ingress uses this |
| `tls:` block in Ingress | Attach cert to host | Enable HTTPS |
| `curl -vk https://lab37.local` | Test TLS & Ingress | See cert + HTTP |
| `kubectl get secret -n lab37` | Verify secret exists | Debug issues |
| `openssl x509 -in tls.crt -text -noout` | Inspect certificate | CN/SAN, expiry |

---

## Notes

- Ingress by itself does **not** do TLS — TLS is handled by the Ingress controller (e.g., NGINX), which reads a TLS Secret.
- The flow is:
    
    Browser → HTTPS → ingress-nginx (terminates TLS) → HTTP → `lab37-web` Service/Pods.
    
- Locally, you can either:
    - use a **self-signed** cert and ignore browser warnings, or
    - use **mkcert** so your OS/browser trusts the certificate.

---

## Security Checklist

- Do **not** commit TLS keys (`tls.key`) or certificates (`tls.crt`) to git.
- In the repo, keep only an example script (`.example.sh`) or documentation — no real keys.
- Create the Secret locally using `kubectl create secret tls` or `kubectl apply -f`.
- The certificate CN/SAN must match the Ingress host (e.g., `lab37.local`).

---

## Pitfalls

- Wrong host name in the certificate → the browser/`curl` will complain about a hostname mismatch.
- The Secret must be of type `kubernetes.io/tls` and contain `tls.crt` and `tls.key`.
- In the Ingress, `tls.secretName` and `tls.hosts` must match the host name in the certificate.
- Your `/etc/hosts` must include `127.0.0.1 lab37.local` (or the host machine’s IP).

---
