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
