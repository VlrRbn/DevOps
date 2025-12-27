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
- Test HTTPS with `curl -v https://lab37.local` and browser.
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
- Create the Secret locally using `kubectl create secret tls` or `kubectl apply -f`.
- The certificate CN/SAN must match the Ingress host (e.g., `lab37.local`).

---

## Pitfalls

- Wrong host name in the certificate → the browser/`curl` will complain about a hostname mismatch.
- The Secret must be of type `kubernetes.io/tls` and contain `tls.crt` and `tls.key`.
- In the Ingress, `tls.secretName` and `tls.hosts` must match the host name in the certificate.
- Your `/etc/hosts` must include `127.0.0.1 lab37.local` (or the host machine’s IP).

---

## Layout

```
labs/lesson_37/k8s/
├─ tls-notes.md
└─ ingress/ingress-tls.yaml           # Ingress with TLS section for lab37.local

```

> Real cert/key live outside git (e.g. ~/secrets/`lab37`/).
> 

---

## 1) Check /etc/hosts and Ingress

1. Ensure `/etc/hosts` has:

```
127.0.0.1   lab37.local

```

(or the IP your ingress-nginx NodePort/hostPort is bound to .)

1. Check Ingress:

```bash
kubectl get ingress -n lab37
kubectl describe ingress lab37-ingress -n lab37
kubectl get svc -n ingress-nginx

```

As expected, it’s HTTP there right now — there’s no `tls:` section yet.

---

## 2) Generate certificate (option A: openssl self-signed)

If you don’t want to install `mkcert`, you can do it with plain `openssl`.

Create a directory outside your git repo:

```bash
mkdir -p ~/secrets/lab37
cd ~/secrets/lab37

```

**Self-signed cert for `lab37.local`:**

```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout lab37.local.key \
  -out lab37.local.crt \
  -subj "/CN=lab37.local" \
  -addext "subjectAltName=DNS:lab37.local"

```

This will create:

- `lab37.local.key` — the private key
- `lab37.local.crt` — a self-signed certificate

Verify:

```bash
openssl x509 -in lab37.local.crt -text -noout | head -n 20

```

---

## 3) Generate certificate with mkcert (trusted)

Install `mkcert`:

```bash
mkcert -install
mkcert -cert-file lab37.local.crt -key-file lab37.local.key lab37.local

```

A local root CA will be added to system trust store, so the browser will stop showing warnings.

After that, the Secret steps are the same — only the filenames differ.

---

## 4) Create TLS Secret in lab37

Use the self-signed option with `lab37.local.crt` / `lab37.local.key`.

(If you’re using mkcert, just adjust the filenames accordingly.)

```bash
cd ~/secrets/lab37

kubectl create secret tls lab37-tls \
  -n lab37 \
  --cert=lab37.local.crt \
  --key=lab37.local.key

```

Check:

```bash
kubectl get secret lab37-tls -n lab37 -o yaml
# or
kubectl describe secret lab37-tls -n lab37

```

Type should be:

```yaml
type: kubernetes.io/tls

```

---

## 5) Update Ingress for HTTPS

Copy current Ingress YAML from `labs/lesson_30/k8s/ingress.yaml` (or wherever) into `lesson_37`:

Edit `labs/lesson_37/k8s/ingress-tls.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: lab37-ingress
  namespace: lab37
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
spec:
  ingressClassName: nginx
  tls:
    - hosts: 
        - lab37.local
      secretName: lab37-tls
  rules:
    - host: lab37.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: lab37-web
                port:
                  number: 8080

```

Key points:

- `tls.secretName: lab37-tls` — must match the Secret name.
- `tls.hosts: [lab37.local]` — the host must match the certificate CN/SAN.
- `rules.host: lab37.local` — the same host again.
- `ssl-redirect/force-ssl-redirect`: if someone open `http://lab37.local`, he goes on HTTPS.

Apply it:

```bash
kubectl apply -f labs/lesson_37/k8s/ingress-tls.yaml
kubectl describe ingress lab37-ingress -n lab37

```

---

## 6) Test HTTPS with curl and browser

### 6.1 curl

```bash
curl -v https://lab37.local/
curl -vk https://lab37.local/ --resolve lab37.local:443:127.0.0.1
curl -I http://lab37.local --resolve lab37.local:80:127.0.0.1
```

Look for:

- In the `curl` output: certificate details (CN, validity, etc.).
- The HTTP response from your `lab37-web`.

With a self-signed cert you’ll get a warning, but `-k` skips certificate chain verification.

View just the certificate:

```bash
echo | openssl s_client -connect lab37.local:443 -servername lab37.local 2>/dev/null \
 | openssl x509 -noout -subject -issuer -dates -ext subjectAltName

```

### 6.2 Browser

- Open `https://lab37.local` in your browser.
- Self-signed: you’ll get a red warning → add an exception.
- mkcert: it should be “green” / trusted (for local).

---

## 7) TLS notes / mini runbook

Create `labs/lesson_37/k8s/tls-notes.md`:

```markdown
# lab37 Ingress TLS Notes

## 1. Where is TLS terminated?

- TLS ends at ingress-nginx.
- Upstream to lab37-web Service is plain HTTP on port 8080.

## 2. How to regenerate certificate (local)

### Self-signed:

mkdir -p ~/secrets/lab37
cd ~/secrets/lab37

openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout lab37.local.key \
  -out lab37.local.crt \
  -subj "/CN=lab37.local" \
  -addext "subjectAltName=DNS:lab37.local"

kubectl create secret tls lab37-tls -n lab37 \
  --cert=lab37.local.crt \
  --key=lab37.local.key

kubectl describe secret lab37-tls -n lab37
  
### mkcert:

mkcert -install
mkcert -cert-file lab37.local.crt -key-file lab37.local.key lab37.local

kubectl create secret tls lab37-tls -n lab37 \
  --cert=lab37.local.crt \
  --key=lab37.local.key

kubectl describe secret lab37-tls -n lab37
```

## 3. Checkpoints

1. `/etc/hosts` has `lab37.local` → 127.0.0.1
2. Secret `lab37-tls` exists in namespace `lab37`
3. Ingress `lab37-ingress` has:
    - `tls.secretName: lab37-tls`
    - `tls.hosts: [lab37.local]`
    - `rules.host: lab37.local`
4. `curl -vk https://lab37.local` works

---

## Core

- [ ]  Generated a self-signed or mkcert certificate for `lab37.local`.
- [ ]  Created the TLS Secret `lab37-tls` in the `lab37` namespace.
- [ ]  The `lab37-web` Ingress was updated with a `tls:` block and applied.
- [ ]  `curl -vk https://lab37.local` works and returns the `lab37-web` response.
- [ ]  Tried the mkcert option so the browser trusts the certificate.
- [ ]  Documented the full local cert generation/rotation process in `tls-notes.md`.
- [ ]  Verified that plain HTTP (the old Ingress without TLS) is no longer being used.
- [ ]  Practiced deleting/recreating the Secret and Ingress to confirm you know the correct order of operations.

---

## Acceptance Criteria

- [ ]  Understand where TLS terminates (at the Ingress) and how the traffic continues over HTTP afterward.
- [ ]  Create a TLS Secret from a `crt`/`key` pair and reference it from an Ingress.
- [ ]  Explain why using mkcert / a local CA is better than a plain self-signed certificate.
- [ ]  Have a written checklist for quickly enabling HTTPS for a new host in Kubernetes.

---

## Summary

- Migrated `lab30` Ingress from plain HTTP to **HTTPS**.
- Worked hands-on with the chain: cert → Secret → Ingress → ingress-nginx.
- Can quickly wrap any local k8s service with HTTPS — and next can do it “properly” with cert-manager and (later) Let’s Encrypt.

---

## Artifacts

- `labs/lesson_37/k8s/ingress-tls.yaml`
- `labs/lesson_37/k8s/tls-notes.md`