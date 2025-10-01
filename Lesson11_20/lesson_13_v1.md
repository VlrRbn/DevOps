# lesson_13

---

# Nginx Advanced: Upstreams, Zero-Downtime, Rate-Limits, Security, Caching, JSON Logs

**Date:** **2025-10-01**

**Topic:** Nginx reverse proxy (advanced) — upstream pools, graceful reload/drain, rate limiting, security headers, gzip/brotli, proxy cache, JSON access logs, fail2ban

---

## Goals

- Reverse proxy to `10.10.0.2:8080` (HTTP/1.1); frontend serves HTTPS/HTTP/2.
- `/health` on ports 80 and 443 returns `200` in under 5 ms and is not logged.
- Mini-cache enabled; repeated requests for static assets show `HIT` (or `MISS`) with lower response time.
- Zero-downtime reload under script `nginx -t && reload` work stable.

---

## Pocket Cheat

| Command | What it does | Why |
| --- | --- | --- |
| `sudo nginx -t && sudo systemctl reload nginx` | Validate & reload | Zero-downtime config apply |
| `upstream app { least_conn; server 10.10.0.2:8080 max_fails=3 fail_timeout=10s; keepalive 32; }` | Upstream pool | LB + health-ish params |
| `proxy_next_upstream error timeout http_502 http_504;` | Retry on errors | Resilience |
| `limit_req_zone $binary_remote_addr zone=req:10m rate=10r/s;` | Req rate-limit (zone) | Throttle abuse |
| `limit_conn_zone $binary_remote_addr zone=conn:10m;` | Conn limit (zone) | Stop floods |
| `add_header Content-Security-Policy "default-src 'self'";` | Security headers | Basic hardening |
| `gzip on; gzip_types text/* application/json;` | Gzip | Smaller responses |
| `proxy_cache_path /var/cache/nginx levels=1:2 keys_zone=pcache:10m max_size=200m inactive=10m;` | Proxy cache | Speed + offload |
| `log_format json …; access_log /var/log/nginx/access.json json;` | JSON logs | Easier parsing |
| `journalctl -u nginx -n 100 --no-pager` | Service logs | Quick triage |
| `sudo tail -f /var/log/nginx/access.json` | Access logs | Live view |

---

## Practice

> Assumes lesson_12 site is working (lab12.conf, backend at 10.10.0.2:8080).
> 

### 0. Prepare dirs & modules

```bash
sudo mkdir -p /var/cache/nginx/lab13
sudo chown -R www-data: /var/cache/nginx/lab13

# Make sure the workers are actually from www-data
grep -E '^\s*user\s+' /etc/nginx/nginx.conf || true
```

### 1. Global http-level tuning (create `/etc/nginx/conf.d/lab13-global.conf`)

```bash
# /etc/nginx/conf.d/lab13-global.conf

# Limits
limit_req_zone  $binary_remote_addr zone=req_zone:10m rate=10r/s;
limit_conn_zone $binary_remote_addr zone=conn_zone:10m;

# Proxy Cache
proxy_cache_path /var/cache/nginx/lab13 levels=1:2 keys_zone=LAB:10m max_size=200m inactive=10m use_temp_path=off;

# JSON Log Format
log_format json escape=json
  '{'
    '"time":"$time_iso8601",'
    '"remote_addr":"$remote_addr",'
    '"request":"$request",'
    '"status":$status,'
    '"bytes_sent":$bytes_sent,'
    '"request_time":$request_time,'
    '"upstream_addr":"$upstream_addr",'
    '"upstream_status":"$upstream_status",'
    '"upstream_response_time":"$upstream_response_time",'
    '"host":"$host",'
    '"ua":"$http_user_agent"'
  '}';

# Default types & gzip (basic)
gzip_comp_level 5;
gzip_min_length 512;
gzip_types
text/plain
text/css
text/javascript
application/javascript
application/json
application/xml;

# Keepalive to upstreams
proxy_http_version 1.1;
proxy_set_header Connection "";
```

### 2. Advanced site config (`/etc/nginx/sites-available/lab13.conf`)

```bash
# /etc/nginx/sites-available/lab13.conf
# Advanced reverse proxy for netns backend (10.10.0.2:8080)

upstream lab_backend {
    least_conn;
    server 10.10.0.2:8080 max_fails=3 fail_timeout=10s;
    keepalive 32;
}

map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}

# Common proxy params
proxy_cache_key "$scheme$request_method$host$request_uri";
proxy_cache_valid 200 301 302 10m;
proxy_cache_bypass $http_cache_control $cookie_nocache;
proxy_no_cache    $http_pragma $http_authorization $cookie_nocache;
proxy_next_upstream error timeout http_502 http_504;
proxy_buffers 16 32k;
proxy_buffer_size 8k;
proxy_read_timeout 60s;

server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name localhost 127.0.0.1;

    location = /health {
        access_log off;                                    # Silent health
        default_type text/plain;
        return 200 "OK\n";
    }
    
    location / {
        return 301 https://$host$request_uri;
    }
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name localhost 127.0.0.1;

    ssl_certificate     /etc/nginx/ssl/lab12.crt;         # Self-signed
    ssl_certificate_key /etc/nginx/ssl/lab12.key;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;
    ssl_session_cache   shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;

    # Security headers
    server_tokens off;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header Content-Security-Policy "default-src 'self'" always;

    # Give the request-id to the client
    add_header X-Request-ID $request_id always;           # Request id

    location = /health {
        access_log off;                                   # Silent health
        default_type text/plain;
        return 200 "OK\n";
    }

    location / {
        # Proxy-headers
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Port  $server_port;

        # HTTP/1.1 + upgrades
        proxy_http_version 1.1;
        proxy_set_header Connection $connection_upgrade;
        proxy_set_header Upgrade    $http_upgrade;

        # Timeouts
        proxy_connect_timeout 5s;                          # timeouts
        proxy_send_timeout    30s;
        proxy_read_timeout    30s;

        # Buffers (defolts)
        proxy_buffering       on;
        proxy_buffers         8 16k;
        proxy_buffer_size     8k;

        proxy_cache           LAB;                         # cache from nginx.conf
        proxy_cache_key       "$scheme$request_method$host$request_uri";
        proxy_cache_valid     200 301 302 10m;
        proxy_cache_bypass    $http_cache_control $cookie_nocache;
        proxy_no_cache        $http_pragma $http_authorization $cookie_nocache;

        proxy_cache_lock            on;                    # Lock
        proxy_cache_lock_timeout    10s;
        proxy_cache_use_stale       updating error timeout http_500 http_502 http_503 http_504;

        # Retry on /502/504
        proxy_next_upstream error timeout http_502 http_504;
        
        add_header X-Cache-Status $upstream_cache_status always;

        proxy_pass http://lab_backend;
    }
}

```

Enable advanced site:

```bash
sudo ln -sfn /etc/nginx/sites-available/lab13.conf /etc/nginx/sites-enabled/lab13.conf
sudo rm -f /etc/nginx/sites-enabled/lab13.conf
sudo nginx -t && sudo systemctl reload nginx
```

### 3. Verify quickly

```bash
curl -sI http://127.0.0.1/ | head
curl -s http://127.0.0.1/health
curl -skI https://127.0.0.1/some/path | grep -i x-cache-status
sudo ss -tulpn | grep -E ':(80|443)\s'
tail -n 20 /var/log/nginx/access.json
```

### 4. Zero-downtime deploy (blue-green via symlink swap)

```bash
# Prepare new site file as lab13_v2.conf
sudo cp /etc/nginx/sites-available/lab13.conf /etc/nginx/sites-available/lab13_v2.conf

# Make changes in _v2.conf
sudo nginx -t || { echo "Config invalid"; exit 1; }

# Atomically switch the symlink and reload:
sudo ln -sfn /etc/nginx/sites-available/lab13_v2.conf /etc/nginx/sites-enabled/lab13.conf
sudo nginx -t && sudo systemctl reload nginx && echo "Deployed v2"
```

### 5. Fail2ban (basic for Nginx)

```bash
sudo apt-get install -y fail2ban
sudo tee /etc/fail2ban/jail.d/nginx-lab13.local >/dev/null <<'JAIL'
[nginx-4xx-abuse]
enabled = true
port    = http,https
filter  = nginx-4xx-abuse
logpath = /var/log/nginx/access.json
maxretry = 20
findtime = 300
bantime  = 1800
JAIL

# Simple filter counting many 4xx from same IP (JSON logs)
sudo tee /etc/fail2ban/filter.d/nginx-4xx-abuse.conf >/dev/null <<'FILTER'
[Definition]
failregex = ^\{.*"remote_addr":"<ADDR>",.*"status":4\d\d,.*\}$
ignoreregex = ^\{.*"request":".*GET /health.*".*\}$
FILTER

sudo systemctl restart fail2ban
sudo fail2ban-client status nginx-4xx-abuse
```

> Note: The filter template is simple.
> 

### 6. Cleanup

```bash
# Remove old site
sudo ip netns exec lab12 bash -lc 'kill "$(cat /tmp/http.pid 2>/dev/null)" 2>/dev/null || true'
sudo ip netns del lab12 2>/dev/null || true
sudo ip link del veth0 2>/dev/null || true
sudo rm -f /etc/nginx/sites-available/lab13.conf
sudo rm -f /etc/nginx/sites-available/lab13_v2.conf
sudo rm -f /etc/nginx/sites-enabled/lab13.conf
sudo rm -f /etc/nginx/conf.d/lab13-global.conf
sudo rm -f /etc/nginx/ssl/lab12.crt
sudo rm -f /etc/nginx/ssl/lab12.key
```

---

## Security Checklist

- `server_tokens off;`
- Security headers: `Content-Security-Policy`, `X-Content-Type-Options nosniff`, `Referrer-Policy`, `X-Frame-Options DENY`.
- Reasonable **rate/conn limits** on public endpoints.
- Prefer TLSv1.2+/1.3.
- Don’t expose default site; validate every reload with `nginx -t`.

---

## Pitfalls

- Defined `limit_*_zone` but **didn’t apply** `limit_req`/`limit_conn` in `server/location` → no effect.
- `proxy_cache` on dynamic endpoints without correct cache-bypass → stale bugs.
- Overlapping site files / duplicate `server_name` → unexpected match.
- Large files proxied without tuning `proxy_read_timeout`/`client_max_body_size`.
- JSON log format typo → Nginx won’t start; always check `nginx -t`.

---

## Tools

### `tools/nginx-bluegreen-deploy.sh`

```bash
#!/usr/bin/env bash
set -Eeuo pipefail

site="${1:?site name, e.g., lab13}"
src="/etc/nginx/sites-available/${site}_v2.conf"
dst="/etc/nginx/sites-enabled/${site}.conf"

sudo nginx -t || true
[[ -f "$src" ]] || { echo "No $src"; exit 1; }
sudo ln -sfn "$src" "$dst"
sudo nginx -t && sudo systemctl reload nginx && echo "Deployed ${site}_v2" || { echo "Invalid config"; exit 1; }
```

---

## Notes

- We reuse the lesson_12 reverse proxy and make it production-friendlier: LB parameters, retries, limits, headers, compression, cache.
- **Zero-downtime** reload works if config is valid and worker shutdown is graceful.
- **Rate limits** and **conn limits** require both a `_zone` (http scope) and directives at `server`/`location`.
- **JSON logs** are easier for `jq`, fail2ban filters, and future shipping to a log stack.

---

## Summary

- Hardened Nginx reverse proxy: upstream LB with retries, limits, security headers.
- Added gzip, proxy cache, JSON access logs, and a minimal fail2ban jail.
- Implemented blue-green style zero-downtime config switch.
- Verified with curl/logs and prepared for future log shipping.

---

## Artifacts

- `tools/nginx-bluegreen-deploy.sh`
- updated `/etc/nginx/conf.d/lab13-global.conf` and `/etc/nginx/sites-available/lab13.conf` snippets in docs

---

## To repeat

- Try blue-green swap with a harmless config tweak (e.g., header).
- Extend fail2ban filters for specific patterns.

---

## Acceptance Criteria

- [ ]  `curl -sI http://127.0.0.1/` → `301` (proxied to `10.10.0.2:8080`).
- [ ]  `access.json` exists, valid JSON per line; tail shows new requests.
- [ ]  `limit_req` triggers under load (e.g., `ab`/`hey` can show 429 after threshold).
- [ ]  `proxy_cache` stores files in `/var/cache/nginx/lab13` .
- [ ]  `nginx-bluegreen-deploy.sh` swaps config and reloads without downtime.
- [ ]  `fail2ban-client status nginx-4xx-abuse` → jail active (bans appear on abuse).