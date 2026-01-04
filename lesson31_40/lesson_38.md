# lesson_38

---

# K8s cert-manager: Automatic TLS Certificates

**Date:** 2026-01-01

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
- A typical production setup is: `ClusterIssuer (ACME/Let’s Encrypt)` → Certificates for Ingresses.
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

## Layout

```
labs/lesson_38/k8s/
├─ certificate-lab38-local.yaml      # cert for lab38.local (TLS Secret managed by cert-manager)
├─ cluster-certificate-ca.yaml
├─ clusterissuer-labca.yaml          # CA issuer based on root
├─ clusterissuer-selfsigned-root.yaml
└─ tls-notes-cert-manager.md         # notes / mini-runbook

```

> Important: cert-manager installation itself (Helm or kubectl apply) is not committed to repo.
> 

---

## 1) Install cert-manager (cluster-level, not in repo)

Namespace & CRDs + controller — the general flow (manifest-based install; Helm is fine too).

> This is cluster admin action, run once per cluster.
> 

### 1.1 Namespace

`labs/lesson_38/k8s/cert-manager-namespace.yaml`:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: cert-manager
  labels:
    app: cert-manager

```

Apply namespace:

```bash
kubectl apply -f cert-manager-namespace.yaml
kubectl get ns

```

### 1.2 Install cert-manager (pick one way)

**Option A (Helm) – highly recommended**

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update

helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true

```

**Option B (kubectl apply) – quick lab**

A typical pattern:

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.15.0/cert-manager.crds.yaml

kubectl apply -n cert-manager \
  -f https://github.com/cert-manager/cert-manager/releases/download/v1.15.0/cert-manager.yaml

```

Check:

```bash
kubectl get pods -n cert-manager
kubectl get crd | grep cert-manager
kubectl -n cert-manager logs deploy/cert-manager

```

Waiting: 3 Pod:

- `cert-manager`
- `cert-manager-cainjector`
- `cert-manager-webhook`

All in `Running`.

---

## 2) Self-signed root ClusterIssuer

We’ll create a root CA using a selfSigned `ClusterIssuer` and a dedicated `Certificate` that generates the root CA Secret.

### 2.1 Self-signed root ClusterIssuer

`labs/lesson_38/k8s/clusterissuer-selfsigned-root.yaml`:

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: labca-selfsigned-root
spec:
  selfSigned: {}

```

Apply:

```bash
kubectl apply -f clusterissuer-selfsigned-root.yaml
kubectl get clusterissuer
kubectl describe clusterissuer labca-selfsigned-root

```

---

## 3) Root CA Certificate + CA-based ClusterIssuer

Now we’ll create a `Certificate` that generates a CA (key + certificate) and stores it in a Secret, and then a `ClusterIssuer` that uses that Secret as a CA.

### 3.1 Root CA certificate

`labs/lesson_38/k8s/cluster-certificate-ca.yaml`:

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: labca-root
  namespace: cert-manager
spec:
  isCA: true
  commonName: "lab38.local Root CA"
  secretName: labca-root-tls
  duration: 8760h
  renewBefore: 720h
  issuerRef:
    name: labca-selfsigned-root
    kind: ClusterIssuer

```

Apply:

```bash
kubectl apply -f cluster-certificate-ca.yaml

kubectl get certificate -n cert-manager
kubectl describe certificate labca-root -n cert-manager
kubectl get secret labca-root-tls -n cert-manager

```

The `labca-root-tls` Secret now contains the CA root (key + cert).

### 3.2 CA-based ClusterIssuer

Now create a `ClusterIssuer` that will issue **leaf** certificates signed by this CA:

`labs/lesson_38/k8s/clusterissuer-labca.yaml`:

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: labca
spec:
  ca:
    secretName: labca-root-tls

```

Apply:

```bash
kubectl apply -f clusterissuer-labca.yaml

kubectl get clusterissuer
kubectl describe clusterissuer labca

```

---

## 4) Certificate for `lab38.local` (lab37 namespace)

Let `lab38.local` be an additional host we use to access `lab37-web`, but this time with a cert-manager-managed Secret.

### Certificate resource

`labs/lesson_38/k8s/certificate-lab38-local.yaml`:

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: lab38-local-tls
  namespace: lab37
spec:
  secretName: lab38-local-tls
  duration: 2160h
  renewBefore: 720h
  issuerRef:
    name: labca
    kind: ClusterIssuer
  dnsNames:
    - lab38.local

```

Apply:

```bash
kubectl apply -f certificate-lab38-local.yaml

kubectl get certificate -n lab37
kubectl describe certificate lab38-local-tls -n lab37
kubectl describe secret lab38-local-tls -n lab37
kubectl get secret lab38-local-tls -n lab37

```

As expected:

- The `Certificate` reaches `Ready` status (after a few seconds).
- The `lab38-local-tls` Secret is created and contains the TLS cert + key.

---

## 5) Ingress for lab38.local using cert-manager-managed TLS

Now create a separate Ingress for `lab38.local` that uses the cert-manager-generated Secret.

`labs/lesson_38/k8s/ingress-lab38-tls.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: lab38-ingress
  namespace: lab37
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - lab38.local
      secretName: lab38-local-tls
  rules:
    - host: lab38.local
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

Apply:

```bash
kubectl apply -f ingress-lab38-tls.yaml

kubectl get ingress -n lab37
kubectl describe ingress lab38-ingress -n lab37

```

Add CA to trusted list (Ubuntu)

```bash
# Get the root CA certificate from the secret:
kubectl get secret -n cert-manager labca-root-tls -o jsonpath='{.data.tls\.crt}' \
  | base64 -d > labca-root.crt

# Copy in /usr...
sudo cp labca-root.crt /usr/local/share/ca-certificates/labca-root.crt
sudo update-ca-certificates

# Test
curl -v https://lab38.local/

```

Look for:

- The TLS handshake → the certificate is issued by the `labca` CA.
- The HTTP response from `lab37-web`.

Verify the certificate chain:

```bash
echo | openssl s_client -connect lab38.local:443 -servername lab38.local 2>/dev/null \
 | openssl x509 -noout -subject -issuer -dates -ext subjectAltName

```

---

## 6) Let cert-manager create Certificate from Ingress annotation

Alternative to writing a `Certificate` YAML: can avoid creating the `Certificate` resource manually and instead use an annotation in `labs/lesson_38/k8s/ingress-lab38-tls.yaml`:

```yaml
metadata:
  annotations:
    cert-manager.io/cluster-issuer: labca

```

And in `spec.tls`:

```yaml
tls:
  - hosts:
      - lab38.local
    secretName: lab38-local-auto

```

cert-manager will detect the annotation and create the `Certificate` automatically.

This is a solid pattern when have lots of Ingresses: only set `tls.secretName` plus the annotation, and cert-manager handles the `Certificate`/`Secret` lifecycle.

---

## 7) TLS + cert-manager runbook

`labs/lesson_38/k8s/tls-notes-cert-manager.md`:

```markdown
# lab38 cert-manager TLS Notes

## 1. Objects we use

- ClusterIssuer `labca-selfsigned-root`: selfSigned, used only to create root CA.
- Certificate `labca-root` in namespace `cert-manager`: creates `labca-root-tls` with CA key+cert.
- ClusterIssuer `labca`: CA-based issuer using `labca-root-tls`.
- Certificate `lab38-local-tls` in namespace `lab37`: issues TLS cert for `lab38.local`, Secret `lab38-local-tls`.
- Ingress `lab38-ingress`: uses `lab38-local-tls` for HTTPS.

## 2. How to add a new HTTPS host with labca

Steps:
1. Add host to /etc/hosts pointing to ingress IP.
2. Create Certificate:

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: <hostname>-tls
  namespace: <app-namespace>
spec:
  secretName: <hostname>-tls
  dnsNames:
    - <hostname>
  issuerRef:
    name: labca
    kind: ClusterIssuer

```

1. Apply Certificate and wait for `Ready`.
2. Update Ingress:

```yaml
spec:
  tls:
    - hosts:
        - <hostname>
      secretName: <hostname>-tls

```

1. Test with `curl -v https://<hostname>/`.

## 3. Debugging cert-manager

1. Check Certificate:

```bash
kubectl get certificate -A
kubectl get certificaterequest -A
kubectl describe certificate <name> -n <ns>   # Check if not ready

# kubectl get secret -n <ns> | grep <word>

```

2. Check Issuer/ClusterIssuer:

```bash
kubectl get clusterissuer
kubectl describe clusterissuer <name>
kubectl describe issuer <name> -n <ns>

```

3. Look at cert-manager logs:

```bash
kubectl logs -n cert-manager deploy/cert-manager

```

4. Common issues:
- Wrong `issuerRef.name/kind`
- Missing ClusterIssuer (typo in name)
- Certificate not in `Ready` state (`conditions` show errors)
- DNS/hosts `kubectl get ingress -n lab37`

---

## Core

- [ ]  cert-manager is installed; Pods in the `cert-manager` namespace are `Running`.
- [ ]  The `labca-selfsigned-root` `ClusterIssuer` is created, and the root CA `Certificate` `labca-root` is issued in `cert-manager`.
- [ ]  The `labca` (CA) `ClusterIssuer` uses `labca-root-tls`.
- [ ]  The `lab38-local-tls` `Certificate` in `lab37` is created and `Ready`; the `lab38-local-tls` Secret exists.
- [ ]  The `lab38-ingress` Ingress serves HTTPS for `https://lab38.local` using a cert-manager-managed Secret.
- [ ]  Tried the annotation-based approach: `cert-manager.io/cluster-issuer: labca` on the Ingress and automatic `Certificate` creation.
- [ ]  Inspected `kubectl describe certificate` during a failure (by intentionally breaking `issuerRef.name`).
- [ ]  You compared the chains: `lab37.local` (lesson_37) vs `lab38.local` (lesson_38) and understand the difference between a “manual Secret” and a “cert-manager-managed Secret”.

---

## Acceptance Criteria

- [ ]  YUnderstand the difference between a selfSigned Issuer, a CA Issuer, and an ACME Issuer .
- [ ]  Can describe the flow: `ClusterIssuer → Certificate → Secret → Ingress`.
- [ ]  Can check a `Certificate` status and understand why it isn’t ready.
- [ ]  Can add a new HTTPS host to a local cluster via cert-manager in 5–10 minutes.

---

## Summary

- Learned to use **cert-manager** the normal way instead of manually stuffing keys into Secrets.
- Connected the dots: `ClusterIssuer (CA) → Certificate → TLS Secret → Ingress`.
- Now moving toward production Let’s Encrypt / ACME is mostly “switch the Issuer and solver”, not “rewrite half the cluster.”

---

## Artifacts

- `labs/lesson_38/k8s/namespaces/cert-manager-namespace.yaml`
- `labs/lesson_38/k8s/ingress/ingress-lab38-tls.yaml`
- `labs/lesson_38/k8s/certificate-lab38-local.yaml`
- `labs/lesson_38/k8s/cluster-certificate-ca.yaml`
- `labs/lesson_38/k8s/clusterissuer-labca.yaml`
- `labs/lesson_38/k8s/clusterissuer-selfsigned-root.yaml`
- `labs/lesson_38/k8s/tls-notes-cert-manager.md`