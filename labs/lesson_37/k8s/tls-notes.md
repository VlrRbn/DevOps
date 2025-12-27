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
  --key=lab37.local-key

kubectl describe secret lab37-tls -n lab37
