# lesson_24

---

# Docker Compose: Multi-Container App, Networks, Volumes & Health

**Date:** 2025-11-21

**Topic:** Use Docker Compose to run a small multi-container app: web image + Redis, with named volumes, custom networks, healthchecks, and `depends_on` conditions.

---

## Goals

- Understand **Compose** structure: `services`, `networks`, `volumes`.
- Run a **multi-container stack**: `web` (app) + `redis` (state).
- Use **named volumes** to persist Redis data.
- Use **custom networks** and container DNS names.
- Configure **healthchecks** and `depends_on` with `service_healthy`.
- Practice `docker compose ps/logs/top` for basic diagnostics.

---

## Pocket Cheat

| Command / File | What it does | Why |
| --- | --- | --- |
| `docker compose up -d` | Start/refresh stack | One command |
| `docker compose ps` | Show services & health | Quick overview |
| `docker compose logs -f web` | Tail app logs | Debug |
| `docker compose down` | Stop & remove | Cleanup |
| `docker compose exec web sh` | Shell into container | Inspect from inside |
| `networks:` & `volumes:` | Define named networks/volumes | Clear topology |
| `depends_on: condition: service_healthy` | Order by health | No race |
| `healthcheck:` | Container health | Status & automation |

---

## Notes

- Compose creates a network per project by default, but we’ll define our own so we can see the topology explicitly.
- Containers on the same network can reach each other by **service name** (`redis`, `web`).
- Named volumes survive `docker compose down` (you can keep data between restarts).
- Healthchecks let us start `web` **only after** Redis is actually up and healthy.

---

## Security Checklist

- Under `ports:` expose only what’s needed (here — only `web` on `127.0.0.1:8080`).
- Do **not** expose Redis to the outside world, access it only via the internal network.
- Don’t put secrets into `docker-compose.yml` and especially not into `.env` (use those only for non-sensitive stuff: port, env name, etc.).
- Don’t run containers as root unless it’s really necessary (the `web` service is already non-root from lesson_23).

---

## Pitfalls

- Containers on different networks with no shared networks cannot see each other.
- No healthcheck → `depends_on` does **not** guarantee the service is actually ready.
- Using a volume without understanding what’s inside → mysterious data after restart.
- Mixing “secrets” and regular env vars: real secrets need a separate system (Vault/secret store).

---

## Layout

```
labs/lesson_24/
├─ app/
│  ├─ app.py
│  ├─ requirements.txt
│  ├─ Dockerfile
│  └─ .dockerignore
└─ compose/
   ├─ docker-compose.yml
   ├─ .gitignore
   └─ .env
```

---

## 1) Web app with optional Redis

`labs/lesson_24/app/app.py`:

```python
from flask import Flask, jsonify, request
import os
import socket
import time

try:
    import redis
except ImportError:
    redis = None

app = Flask(__name__)
start_time = time.time()

_redis_client = None

def get_redis_client():
    """Return Redis client or None if not configured/available."""
    global _redis_client
    if not redis:
        return None
    if _redis_client is not None:
        return _redis_client

    host = os.getenv("REDIS_HOST")
    if not host:
        return None

    port = int(os.getenv("REDIS_PORT", "6379"))
    db = int(os.getenv("REDIS_DB", "0"))
    try:
        _redis_client = redis.Redis(host=host, port=port, db=db)
        _redis_client.ping()
    except Exception:
        _redis_client = None
    return _redis_client

@app.get("/health")
def health():
    uptime = int(time.time() - start_time)
    client = get_redis_client()
    redis_ok = False
    if client is not None:
        try:
            client.ping()
            redis_ok = True
        except Exception:
            redis_ok = False

    return jsonify(
        status="ok",
        uptime_seconds=uptime,
        hostname=socket.gethostname(),
        env=os.getenv("LAB_ENV", "dev"),
        redis_ok=redis_ok,
    )

@app.get("/")
def index():
    client = get_redis_client()
    hit_count = None
    redis_error = None

    if client is not None:
        try:
            hit_count = client.incr("lab24_hits")
        except Exception as exc:
            redis_error = str(exc)

    return jsonify(
        message="Hello from lab24",
        path=request.path,
        host=request.host,
        env=os.getenv("LAB_ENV", "dev"),
        hit_count=hit_count,
        redis_error=redis_error,
    )

if __name__ == "__main__":
    port = int(os.getenv("PORT", "8080"))
    app.run(host="0.0.0.0", port=port)
```

`labs/lesson_24/app/requirements.txt`:

```
flask==3.0.3
redis==5.0.8
```

> If Redis is unavailable, the app still works — `hit_count` will just be `null` and `redis_ok = false`.
> 

---

## 2) `.dockerignore` & Dockerfile (reuse pattern from lesson_23)

`labs/lesson_24/app/.dockerignore`:

```
__pycache__/
*.pyc
*.pyo
*.pyd
.env
.git
.gitignore
.vscode/
.idea/
*.log
labs/
tests/
*.md
```

`labs/lesson_24/app/Dockerfile`:

```
FROM python:3.12-slim AS runtime

LABEL maintainer="you@yourdomain.net" \
      service="lab24-web" \
      env="lab"

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

RUN useradd --create-home --shell /usr/sbin/nologin appuser

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

ENV PORT=8080 \
    LAB_ENV=lab

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD curl -fsS http://127.0.0.1:${PORT}/health || exit 1

USER appuser

CMD ["python", "app.py"]
```

Build:

```bash
cd labs/lesson_24/app
docker build -t lab24-web:dev .
```

---

## 3) Docker Compose: web + redis, networks & volume

`labs/lesson_24/compose/docker-compose.yml`:

```yaml
services:
  web:
    build:
      context: ../app
      dockerfile: Dockerfile
    image: lab24-web:dev
    container_name: lab24-web
    environment:
      LAB_ENV: "${LAB_ENV:-lab}"
      PORT: "8080"
      REDIS_HOST: "redis"
      REDIS_PORT: "6379"
      REDIS_DB: "0"
    ports:
      - "127.0.0.1:${WEB_PORT:-8080}:8080"
    depends_on:
      redis:
        condition: service_healthy
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS http://127.0.0.1:8080/health || exit 1"]
      interval: 30s
      timeout: 3s
      retries: 3
      start_period: 15s
    restart: unless-stopped
    networks:
      - frontend
      - backend

  redis:
    image: redis:7-alpine
    container_name: lab24-redis
    command: ["redis-server", "--save", "60", "1", "--loglevel", "warning"]
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 3s
      retries: 5
      start_period: 5s
    restart: unless-stopped
    networks:
      - backend

networks:
  frontend:
    driver: bridge
  backend:
    driver: bridge

volumes:
  redis_data:
```

> Scheme:
> 
> - `web` is on both `frontend` and `backend`: in the future we can hang a reverse proxy on `frontend`.
> - `redis` is only on `backend`.
> - Redis is not exposed to the outside world, it’s only accessible to other containers by the `redis` service name.

---

## 4) `.env` for non-secret tweaks

 `labs/lesson_24/compose/.env`:

```
WEB_PORT=8080
LAB_ENV=lab
```

> For .env:
> 
> - Change the values and **do not commit** `.env` to git.
> - Compose will automatically pick up `.env` if it’s next to `docker-compose.yml`.

---

## 5) Run & basic checks

```bash
cd labs/lesson_24/compose
docker compose up -d
docker compose ps

# for :8080   
# sudo systemctl stop nginx
```

Check the statuses:

- `STATE` for both `redis` and `web` should be `running (healthy)` after 20–30 seconds.

Then:

```bash
curl -s http://127.0.0.1:8080/ | jq
curl -s http://127.0.0.1:8080/health | jq
```

Expected:

- In `/health`: `redis_ok: true` (a few seconds after startup).
- In `/`: the `hit_count` field increases with every request (1, 2, 3, …).

---

## 6) Networks & volumes

### Networks

```bash
docker network ls | grep compose
docker network inspect compose_backend | head
docker network inspect compose_frontend | head

# docker network rm compose_backend compose_frontend
```

From inside the `web` container:

```bash
docker compose exec web sh

# inside:
ping -c1 redis

# or:
redis-cli -h redis ping

exit
```

### Volume

```bash
docker volume ls | grep redis_data
docker volume inspect compose_redis_data | jq

# docker volume ls -qf dangling=true
# for all
# docker volume prune
```

> Make sure that `redis_data` remains after `docker compose down` (as long as you don’t pass `--volumes`).
> 

---

## 7) Diagnostics

Useful commands:

```bash
# Summary
docker compose ps

# Logs
docker compose logs -f web
docker compose logs -f redis
# cat /proc/sys/vm/overcommit_memory
# sudo sysctl vm.overcommit_memory=1

# Top-like view (resource usage)
docker compose top

# Curl from inside web to prove hostname resolution:
docker compose exec web sh -c 'curl -s http://redis:6379 || echo "ok (no HTTP, but DNS works)"'
# Whether the web can see it via DNS.
docker compose exec web python -c "import socket; print(socket.gethostbyname('redis'))"
```

---

## 8) Cleanup

```bash
cd labs/lesson_24/compose
docker compose down

# to delete volume:
# docker compose down --volumes
```

---

## Core

- [ ]  Build the `lab24-web:dev` image from the Dockerfile.
- [ ]  `docker compose up -d` brings up `web` + `redis`, both **healthy**.
- [ ]  `curl /` returns JSON with `hit_count` and `env`.
- [ ]  Redis data is preserved across container restarts (thanks to the volume).
- [ ]  Add **one more service** (for example, an `nginx` reverse proxy in front of `web`) on the `frontend` network.
- [ ]  Add a second Compose file `docker-compose.override.yml` (e.g. for dev: different port, env).
- [ ]  Create a simple script in `tools/` (`tools/lab24-compose-check.sh`) that:
    - runs `docker compose up -d`,
    - waits for the healthchecks,
    - checks `curl /health`,
    - and prints a short summary.

---

## Acceptance Criteria

- [ ]  The multi-container stack works: `web` ↔ `redis` over the network, and Redis is **not** exposed to the outside world.
- [ ]  The named volume `redis_data` keeps data between restarts.
- [ ]  Healthchecks for both `redis` and `web` are green; `depends_on` uses `service_healthy`.
- [ ]  You know how to inspect networks, volumes, and logs using `docker compose *` commands.

---

## Summary

- You’ve moved from a single container to a **full Compose stack**: web + Redis + networks + volume.
- You practiced healthchecks, `depends_on` with `condition: service_healthy`, and basic diagnostics.
- You’ve prepared the ground for the next steps: multi-stage builds, a registry, CI/CD for images, and more complex stacks.

---

## Artifacts

- `lesson_24.md`
- `labs/lesson_24/app/{app.py,requirements.txt,Dockerfile,.dockerignore}`
- `labs/lesson_24/compose/{docker-compose.yml,docker-compose.override.yml, nginx.conf}`
- `labs/lesson_24/tools/lab24-compose-check.sh`