# lesson_12

---

# Nginx Reverse Proxy + TLS (self-signed)

**Date:** **2025-09-23**

**Topic:** Nginx reverse proxy to netns backend (`10.10.0.2:8080`), TLS (self-signed for lab; Let’s Encrypt notes), UFW, healthchecks, logs, zero-downtime reload

---

## Goals

- Reverse proxy to netns backend.
- HTTPS on 443.
- Zero-downtime reload.
- Quick verifications.

---

## Pocket Cheat

| Command | What it does | Why / Example |
| --- | --- | --- |
| `sudo nginx -t` | Validate config | Catch typos fast |
| `sudo systemctl reload nginx` | Zero-downtime reload | Apply changes |
| `sudo mkdir -p /etc/nginx/ssl` | Create TLS dir | Store keys locally |
| `sudo openssl req -x509 -nodes -newkey rsa:2048 -keyout /etc/nginx/ssl/lab12.key -out /etc/nginx/ssl/lab12.crt -days 365 -subj "/CN=localhost" -addext "subjectAltName=DNS:localhost` | Self-signed cert | Lab HTTPS |
| `sudo ufw allow 'Nginx Full'` | Open 80/443 | Firewall allow |
| `curl -sI http://127.0.0.1/` | Check HTTP | Quick probe |
| `curl -skI https://127.0.0.1/` | Check HTTPS (skip verify) | Self-signed test |
| `journalctl -u nginx -n 100 --no-pager` | Nginx logs (service) | Debug reload |
| `sudo tail -f /var/log/nginx/access.log` | Access log | See traffic |

---

## Practice

### 0. Prep

```bash
sudo ufw allow 'Nginx Full'        # opens 80/tcp and 443/tcp
sudo ufw status verbose
```

### 1. Self-signed TLS for lab (base)

```bash
sudo mkdir -p /etc/nginx/ssl                          # Directory for Nginx keys/certs
sudo openssl req \
  -x509 \
  -nodes \
  -newkey rsa:2048 \
  -keyout /etc/nginx/ssl/lab12.key \
  -out    /etc/nginx/ssl/lab12.crt \
  -days 365 \
  -subj "/CN=localhost" \
  -addext "subjectAltName=DNS:localhost"

sudo chmod 600 /etc/nginx/ssl/lab12.key

# Checksums must match
# sudo openssl rsa  -noout -modulus -in /etc/nginx/ssl/lab12.key | md5sum
# openssl x509 -noout -modulus -in /etc/nginx/ssl/lab12.crt    | md5sum
```

- `x509` — produce an X.509 certificate directly (no CSR step).
- `nodes` — create the private key without a passphrase (so Nginx can start unattended).
- `newkey rsa:2048` — generate a new 2048-bit RSA key.
- `keyout …` / `out …` — paths for the key and the self-signed cert.
- `days 365` — validity period: 1 year.
- `subj "/CN=localhost"` — sets Subject, Common Name = `localhost`.
- `addext "subjectAltName=DNS:localhost"` — adds SAN; modern clients require SAN, CN alone is ignored.

### 2. Backend (reuse lesson_10 or 11)

Make sure `lab10` netns and Python server are up:

```bash
# If needed, re-create minimal backend:
sudo ip netns del lab12 2>/dev/null || true
sudo ip netns add lab12
sudo ip link add veth0 type veth peer name veth1
sudo ip link set veth1 netns lab12
sudo ip addr add 10.10.0.1/24 dev veth0
sudo ip link set veth0 up
sudo ip -n lab12 addr add 10.10.0.2/24 dev veth1
sudo ip -n lab12 link set veth1 up
sudo ip -n lab12 link set lo up
sudo ip -n lab12 route add default via 10.10.0.1
sudo ip netns exec lab12 bash -lc 'echo nameserver 1.1.1.1 >/etc/resolv.conf'
sudo ip netns exec lab12 python3 -m http.server 8080 --bind 10.10.0.2 >/dev/null 2>&1 & echo $! | sudo tee /tmp/http.pid

# Check namespaces and interfaces:
# ip netns list
# ip addr show veth0
# sudo ip netns exec lab12 ip addr
```

### 3. Nginx site config

Create `/etc/nginx/sites-available/lab12.conf`:

```bash
# /etc/nginx/sites-available/lab12.conf
# Minimal reverse proxy for lab backend in netns (10.10.0.2:8080)

# This ensures WebSocket/HTTP2 upgrade scenarios are proxied correctly via proxy_set_header
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}

upstream lab_backend {
    server 10.10.0.2:8080;  # netns backend
    keepalive 16;
}

server {
    listen 80 default_server;
    listen [::]:80 default_server;

    server_name localhost 127.0.0.1;

    # Simple healthcheck (fast path)
    location = /health {
        return 200 "OK\n";     # Returns 200 with body OK\n, no proxying
        add_header Content-Type text/plain;
    }

    location / {
        return 301 https://$host$request_uri;
    }
}

server {
    listen 443 ssl http2;                                         # Listens on 443 (IPv4/IPv6), enables TLS and HTTP/2
    listen [::]:443 ssl http2;
    server_name localhost 127.0.0.1;

    ssl_certificate     /etc/nginx/ssl/lab12.crt;
    ssl_certificate_key /etc/nginx/ssl/lab12.key;

    # TLS hygiene
    ssl_protocols TLSv1.2 TLSv1.3;                                # Only TLS 1.2/1.3 are allowed
    ssl_prefer_server_ciphers on;                                 # Prefer server cipher order

    server_tokens off;                                            # Hide Nginx version in errors/headers

    location = /health {        
        return 200 "OK\n";
        add_header Content-Type text/plain;
    }

    location / {
        proxy_set_header Host $host;                                     # Original host from the client request
        proxy_set_header X-Real-IP $remote_addr;                         # Client IP as seen by Nginx
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;     # Proxy chain
        proxy_set_header X-Forwarded-Proto $scheme;                      # Client-side scheme (http/https)

        proxy_http_version 1.1;
        proxy_set_header Connection $connection_upgrade;
        proxy_set_header Upgrade $http_upgrade;                          # Enables upgrades (WebSocket, etc.)

        proxy_pass http://lab_backend;                                   # Proxy everything else to lab_backend
    }
}
```

Enable site + disable default:

```bash
sudo ln -sfn /etc/nginx/sites-available/lab12.conf /etc/nginx/sites-enabled/lab12.conf
sudo rm -f /etc/nginx/sites-enabled/default     # Removes the default site so it won’t grab traffic
sudo nginx -t                                   # Checks config syntax and validity
sudo systemctl reload nginx

ls -l /etc/nginx/sites-enabled/
```

Drops (or replaces) a symlink to our site in `sites-enabled`.

- `s` — create a symlink
- `f` — overwrite if the file/link already exists
- `n` — don’t dereference if the target is a directory (safer for symlinks)

Result: the virtual host is enabled.

### 4. Verify

```bash
curl -sI http://127.0.0.1/ | head
curl -skI https://127.0.0.1/ | head     # -k: accept self-signed
sudo ss -tulpn | grep -E ':(80|443)\s'
tail -n 20 /var/log/nginx/access.log
journalctl -u nginx -n 50 --no-pager
```

### 5. Let’s Encrypt (real domain only)

```bash
# For a public domain pointing to this host:
sudo apt-get install -y certbot python3-certbot-nginx
# Basic flow:
#   sudo certbot --nginx -d yourdomain.tld -d www.yourdomain.tld
# Certbot will edit nginx conf and install a timer for auto-renew.
```

### 6. Cleanup

```bash
sudo ip netns exec lab12 bash -lc 'kill "$(cat /tmp/http.pid 2>/dev/null)" 2>/dev/null || true'
sudo ip netns del lab12 2>/dev/null || true
sudo ip link del veth0 2>/dev/null || true
```

---

## Security Checklist

- `server_tokens off;` (hide version)
- TLS: disable TLSv1.0/1.1; prefer TLSv1.2+/TLSv1.3
- UFW: allow only what you need (`Nginx Full` opens 80/443)
- Remove/disable **default** server block to avoid leaks
- Healthcheck path that does **not** hit heavy app code (simple `200 OK`)
- Logs: rotate via `logrotate` (Ubuntu has defaults for Nginx)

---

## Pitfalls

- Forgetting `nginx -t` → reload fails silently.
- UFW not opened → site “down” from outside.
- Backend not reachable from host (netns down) → 502 Bad Gateway.
- Self-signed cert → browsers warn (normal for lab).
- Mixing multiple site files with overlapping `server_name` → unexpected match.

---

## Tools

### `tools/nginx-reload-safe.sh`

```bash
#!/usr/bin/env bash
set -Eeuo pipefail
sudo nginx -t && sudo systemctl reload nginx && echo "Reload OK" || { echo "Config invalid"; exit 1; }
```

---

## Notes

- Backend from lesson_10/11 runs in netns on `10.10.0.2:8080`. Proxy it via Nginx on the host.
- For **lab TLS**, use a local self-signed cert (browsers warn, `curl -k` OK).
- For **real TLS**, use Let’s Encrypt (`certbot`) for a public DNS name and 80/443 reachable.
- Keep config **idempotent**: one site file, enabled via symlink; always validate with `nginx -t` before reload.

---

## Summary

- Installed and configured Nginx as a reverse proxy to the netns backend.
- Added lab-grade TLS with self-signed cert, kept Let’s Encrypt path documented.
- Opened UFW ports and validated with curl/logs; created a healthcheck endpoint.
- Zero-downtime reload and a small helper script included.

---

## Artifacts

- `tools/nginx-reload-safe.sh`

---

## To repeat

- Reboot: ensure Nginx auto-starts (`systemctl is-enabled nginx`).
- Rotate cert (generate new self-signed) and reload Nginx.
- Replace backend with another service on `10.10.0.2:PORT` and adjust `upstream`.
- When you get a real domain, run `certbot --nginx` to switch to valid TLS.

---

## Acceptance Criteria

- [ ]  `curl -sI http://127.0.0.1/` returns `301` (via proxy to `10.10.0.2:8080`).
- [ ]  `curl -skI https://127.0.0.1/` returns `200` with self-signed TLS.
- [ ]  `sudo nginx -t` passes; `systemctl reload nginx` succeeds.
- [ ]  Access log shows requests; UFW shows `Nginx Full` allowed.
- [ ]  Removing/bringing down netns backend leads to 502 in access log.