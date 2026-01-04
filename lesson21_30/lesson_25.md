# lesson_25

---

# Docker Multi-Stage Builds & Registry (GitHub Actions CI)

**Date:** 2025-11-24

**Topic:** Build optimized images with multi-stage Dockerfiles, tag and push to a container registry (e.g. GitHub Container Registry), and set up GitHub Actions CI to build & push on every commit.

---

## Goals

- Understand **multi-stage Dockerfile**: builder → slim runtime.
- Build a **smaller image** for web app (lab24-style Flask + Redis client).
- Tag & push image to a **container registry** (Docker Hub or GitHub Container Registry).
- Use Docker Compose to run the image **from registry** (no local build).
- Configure **GitHub Actions** CI pipeline that builds & pushes images automatically.

---

## Pocket Cheat

| Command / File | What it does | Why |
| --- | --- | --- |
| `docker build -t lab25-web:dev .` | Build multi-stage image | Create optimized image |
| `docker image ls lab25-web` | Check size/tags | Compare with lesson_24 |
| `docker tag lab25-web:dev ghcr.io/YOUR_NAME/lab25-web:dev` | New tag for registry | Prepare push |
| `docker push ghcr.io/YOUR_NAME/lab25-web:dev` | Push image | Share/use in CI |
| `.github/workflows/docker-image-lab25.yml` | CI pipeline | Auto-build & push |
| `docker compose up -d` | Run stack from registry image | One-liner |
| `docker build --target builder ...` | Build only builder stage | Debug builds |
| `docker history lab25-web:dev` | Inspect layers | Confirm multi-stage benefits |

---

## Notes

- Multi-stage builds let you **compile/install dependencies in one stage**, then **copy only the results** into a smaller runtime image.
- Good pattern for Python: `pip install --prefix=/install ...` in builder, then copy `/install` into runtime’s `/usr/local`.
- Registry:
    - Docker Hub: `yourname/lab25-web:tag`.
    - GitHub Container Registry (GHCR): `ghcr.io/YOUR_GITHUB_NAME/lab25-web:tag`.
- CI: GitHub Actions can log in to GHCR using `GITHUB_TOKEN` and push images automatically.

---

## Security Checklist

- **No secrets** in Dockerfile or image (`ENV PASSWORD=...` is bad).
- Registry credentials must be stored as **secrets** (e.g. GitHub `GITHUB_TOKEN` or PAT) — not in repo.
- Do not push debug-only tags with sensitive tools baked in (like `ssh` keys, etc.).
- Keep base images up to date and pin to reasonably specific tags (`python:3.12-slim` instead of `latest`).

---

## Pitfalls

- Forgetting `.dockerignore` → huge build context and bloated image.
- Using same image for build + runtime → unnecessary build tools in final image.
- Wrong registry tag (typo in username or registry host) → `denied: requested access to the resource is denied`.
- GitHub Actions: missing login step to GHCR → push fails with 401.

---

## Layout

```
labs/lesson_25/
├─ app/
│  ├─ app.py
│  ├─ requirements.txt
│  ├─ Dockerfile
│  └─ .dockerignore
└─ compose/
   ├─ docker-compose.registry.yml
   └─ docker-compose.yml

.github/workflows/
└─ docker-image-lab25.yml
```

Re-use the **lab24 app idea** (Flask + optional Redis) but as a **separate lab25 app**.

---

## 1) Lab25 app (same idea, new folder)

`labs/lesson_25/app/app.py` (same behavior as lesson_24):

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
            hit_count = client.incr("lab25_hits")
        except Exception as exc:
            redis_error = str(exc)

    return jsonify(
        message="Hello from lab25",
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

---

## 2) Multi-stage Dockerfile

`labs/lesson_25/app/Dockerfile`:

```
# ---- global ----
ARG BUILD_VERSION=dev
ARG BUILD_DATE=unknown

# ---- builder stage ----
FROM python:3.12-slim AS builder

ARG BUILD_VERSION
ARG BUILD_DATE

LABEL stage="builder"

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

COPY requirements.txt .

RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

COPY app.py .

# ---- runtime stage ----
FROM python:3.12-slim AS runtime

ARG BUILD_VERSION
ARG BUILD_DATE

LABEL maintainer="you@yourdomain.net" \
      service="lab25-web" \
      env="lab"

COPY --from=builder /install /usr/local

RUN useradd --create-home --shell /usr/sbin/nologin appuser

WORKDIR /app

COPY app.py .

ENV PORT=8080 \
    LAB_ENV=lab \
    BUILD_VERSION=${BUILD_VERSION} \
    BUILD_DATE=${BUILD_DATE}

EXPOSE 8080

RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD curl -fsS http://127.0.0.1:${PORT}/health || exit 1

USER appuser

CMD ["python", "app.py"]
```

Key points:

- Builder stage installs dependencies into `/install`.
- Runtime stage copies only `/install` + `app.py`.
- Build args `BUILD_VERSION` and `BUILD_DATE` are **propagated into runtime** to track image build.

Build locally:

```bash
cd labs/lesson_25/app

docker build \
  --build-arg BUILD_VERSION=0.1.0 \
  --build-arg BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  -t lab25-web:dev .
  
docker build \
  --build-arg BUILD_VERSION=0.1.1 \
  --build-arg BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ) \
  -t lab25-web:dev .
```

Check image:

```bash
docker image ls lab25-web
docker inspect lab25-web:dev | jq '.[0].Config.User, .[0].Config.Labels, .[0].Config.Env'
docker history lab25-web:dev
```

---

## 3) Local docker-compose (for quick test)

`labs/lesson_25/compose/docker-compose.yml`:

```yaml
services:
  web:
    image: lab25-web:dev
    container_name: lab25-web
    environment:
      LAB_ENV: "lab"
      PORT: "8080"
      REDIS_HOST: "redis"
      REDIS_PORT: "6379"
      REDIS_DB: "0"
    ports:
      - "127.0.0.1:8080:8080"
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
      - backend
      
  redis:
    image: redis:7-alpine
    container_name: lab25-redis
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
    backend:
      driver: bridge
      
volumes:
    redis_data:
```

Run:

```bash
cd labs/lesson_25/compose
docker compose up -d
docker compose ps
curl -s http://127.0.0.1:8080/ | jq
curl -s http://127.0.0.1:8080/health | jq
```

---

## 4) Tagging & pushing to registry (GHCR example)

Assume GitHub username: `**username**` and repo `**reponame**`. For GitHub Container Registry:

- Image name convention: `ghcr.io/<OWNER>/<IMAGE_NAME>:<TAG>`
    
    Example: `ghcr.io/**username**/lab25-web:dev`
    

Tag and push:

```bash
# Tag existing local image
docker tag lab25-web:dev ghcr.io/<username>/lab25-web:dev

# Log in to ghcr.io (if not already logged in)
# Using a Personal Access Token or GITHUB_TOKEN exported locally:
# echo "$GITHUB_TOKEN" | docker login ghcr.io -u <username> --password-stdin

# Push
docker push ghcr.io/<username>/lab25-web:dev

# docker images | grep lab25-web
```

---

## 5) Compose that runs image from registry only

Once the image is in GHCR, create a **registry-only** compose file (no build):

`labs/lesson_25/compose/docker-compose.registry.yml`:

```yaml
services:
  web:
    image: ghcr.io/vlrrbn/lab25-web:dev
    container_name: lab25-web
    environment:
      LAB_ENV: "lab"
      PORT: "8080"
      REDIS_HOST: "redis"
      REDIS_PORT: "6379"
      REDIS_DB: "0"
    ports:
      - "127.0.0.1:8080:8080"
    depends_on:
      redis:
        condition: service_healthy
    restart: unless-stopped
    networks:
      - backend

  redis:
    image: redis:7-alpine
    container_name: lab25-redis
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
  backend:
    driver: bridge

volumes:
  redis_data:
```

Run:

```bash
cd labs/lesson_25/compose
docker compose -f docker-compose.registry.yml up -d
```

This simulates deploying to another host that **only** has Docker & access to GHCR.

---

## 6) GitHub Actions CI: build & push on push

Create `./.github/workflows/docker-image-lab25.yml`:

```yaml
name: lab25-docker-image

on:
  push:
    branches: [ "main" ]
    paths:
      - "labs/lesson_25/app/**"
      - ".github/workflows/docker-image-lab25.yml"
  workflow_dispatch: {}

jobs:
  build-and-push:
    runs-on: ubuntu-latest

    permissions:
      contents: read
      packages: write

    env:
      REGISTRY: ghcr.io
      IMAGE_NAME: lab25-web-workflows

    steps:
      - name: Checkout repo
        uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Log in to GitHub Container Registry
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Extract metadata (tags, labels)
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: |
            ${{ env.REGISTRY }}/${{ github.repository_owner }}/${{ env.IMAGE_NAME }}
          tags: |
            type=ref,event=branch
            type=sha
            type=raw,value=latest,enable={{is_default_branch}}

      - name: Build and push Docker image
        uses: docker/build-push-action@v6
        with:
          context: ./labs/lesson_25/app
          file: ./labs/lesson_25/app/Dockerfile
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          build-args: |
            BUILD_VERSION=${{ github.sha }}
            BUILD_DATE=${{ github.run_id }}
```

What this does:

- On push to `main`, if changed lab25 app or the workflow, it runs.
- Logs in to **GHCR** using the repo’s `GITHUB_TOKEN`.
- Builds image from `labs/lesson_25/app/Dockerfile`.
- Tags with branch name, commit SHA, and `latest` on default branch.
- Pushes to `ghcr.io/<OWNER>/lab25-web:<tags>`.

After the first successful run:

- Check `https://ghcr.io/<OWNER>?tab=packages` in browser (or via GitHub UI → Packages) to see the image.
- Use those tags in `docker-compose.registry.yml`.

---

## Core

- [ ]  Multi-stage Dockerfile builds `lab25-web:dev` successfully.
- [ ]  Image size is smaller or at least cleaner than a single-stage “fat” image (compare with `lesson_24`).
- [ ]  `docker compose up -d` (local) starts `web + redis`, both healthy, `/` and `/health` respond.
- [ ]  Image is pushed to a registry (GHCR or Docker Hub) with at least one tag (`dev` or `latest`).
- [ ]  Registry-only Compose file (`docker-compose.registry.yml`) works on a **fresh machine** (no local build).
- [ ]  GitHub Actions workflow built & pushed image automatically after push to `main`.
- [ ]  Different tags exist (branch-name, SHA, `latest`), and you can run with each.
- [ ]  Inspected `docker history` and understand which layers come from builder vs runtime.

---

## Acceptance Criteria

- [ ]  Multi-stage Dockerfile is in place and builds without errors.
- [ ]  Final runtime image does **not** contain build tools (just Python + deps + app).
- [ ]  The image is available in registry (GHCR/Docker Hub) and can be pulled by name.
- [ ]  GitHub Actions pipeline runs green and publishes new image versions on push.
- [ ]  Compose can run using only the registry image (no local `docker build`).

---

## Summary

- Upgraded from simple Docker builds to **multi-stage builds**, keeping final images lean and clean.
- Learned how to **tag & push** images to a registry (GHCR/Docker Hub).
- Wired up a **GitHub Actions** pipeline to automatically build & push images on every push.

---

## Artifacts

- `lesson_25.md`
- `labs/lesson_25/app/{app.py,requirements.txt,Dockerfile,.dockerignore}`
- `labs/lesson_25/compose/{docker-compose.yml,docker-compose.registry.yml}`
- `.github/workflows/docker-image-lab25.yml`