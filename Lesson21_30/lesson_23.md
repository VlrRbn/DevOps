# lesson_23

---

# Docker Images & Dockerfiles: Build, Tag, Run, Inspect

**Date:** 2025-11-19

**Topic:** Build own Docker images with Dockerfiles, use `.dockerignore`, non-root users, healthchecks, tagging strategy, and integrate with Docker Compose.

---

## Goals

- Understand **Dockerfile** basics: `FROM`, `RUN`, `COPY`, `WORKDIR`, `CMD`, `EXPOSE`.
- Build a **small web service image** (Python) with proper `.dockerignore`.
- Run container with Docker & Docker Compose, wire ports and healthchecks.
- Use **non-root user** in container.
- Practice **tagging**, inspecting layers, and cleaning images.

---

## Pocket Cheat

| Command / File | What it does | Why |
| --- | --- | --- |
| `docker build -t lab23-web:dev .` | Build image from Dockerfile | Create image |
| `docker run --rm -p 8080:8080 lab23-web:dev` | Run container | Quick test |
| `docker compose up -d` | Run stack | One-liner |
| `.dockerignore` | Skip junk in build context | Smaller images |
| `docker image ls` | List images | Check tags/size |
| `docker history lab23-web:dev` | Layer history | Understand layers |
| `docker inspect lab23-web:dev` | Inspect metadata | Env, user, health |
| `USER appuser` | Drop root in container | Security |
| `HEALTHCHECK` | Built-in health | Status in `docker ps` |

---

## Notes

- Docker builds a layered filesystem from Dockerfile instructions. **Order matters** for cache and image size.
- Best practice:
    - Start from **slim** base image.
    - Install deps in as few `RUN` layers as reasonable.
    - Use `.dockerignore` aggressively.
    - Run as **non-root**.
- It’s important not only to run containers but also to build images properly.

---

## Security Checklist

- Don’t leave secrets in the Dockerfile or the image (e.g. `ENV PASSWORD=...` is not acceptable).
- Don’t run as root: create a dedicated user and switch to it.
- Avoid using huge base images (like `ubuntu:latest`) for simple services if a `slim` variant is available.
- Don’t expose unnecessary ports; in the Dockerfile, only declare the port the application actually listens on.

---

## Pitfalls

- A missing `.dockerignore` file → half of the repository ends up in the image.
- Instruction order matters: putting frequently changed files (like application code) too early in the Dockerfile invalidates the build cache on every run.
- `CMD` vs `ENTRYPOINT`: the wrong combination breaks how `docker run ...` passes arguments.
- Running as root out of habit → more security issues and painful volume permission problems.

---

## Layout

```
labs/lesson_23/
└─ app/
   ├─ app.py
   ├─ requirements.txt
   ├─ Dockerfile
   └─ .dockerignore
└─ compose/
   └─ docker-compose.yml
```

---

## 1) Minimal web app (Python)

Create `labs/lesson_23/app/app.py`:

```python
from flask import Flask, jsonify, request
import os
import socket
import time

app = Flask(__name__)
start_time = time.time()

@app.get("/health")
def health():
    return jsonify(
        status="ok",
        uptime_seconds=int(time.time() - start_time),
        hostname=socket.gethostname(),
    )

@app.get("/")
def index():
    return jsonify(
        message="Hello from lab23",
        path=request.path,
        host=request.host,
        env=os.getenv("LAB_ENV", "dev"),
    )

if __name__ == "__main__":
    port = int(os.getenv("PORT", "8080"))
    app.run(host="0.0.0.0", port=port)
```

`labs/lesson_23/app/requirements.txt`:

```
flask==3.0.3
```

---

## 2) `.dockerignore` — keep image clean

`labs/lesson_23/app/.dockerignore`:

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

---

## 3) Dockerfile (slim + non-root + healthcheck)

`labs/lesson_23/app/Dockerfile`:

```
# Base image: slim Python
FROM python:3.12-slim AS runtime

# Metadata
LABEL maintainer="you@yourdomain.net" \
      service="lab23-web" \
      env="lab"

# System deps + cleanup
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN useradd --create-home --shell /usr/sbin/nologin appuser

# Working dir
WORKDIR /app

# Install Python deps (copy requirements first for cache)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy app code
COPY app.py .

# Environment (runtime)
ENV PORT=8080 \
    LAB_ENV=lab

# Expose port
EXPOSE 8080

# Healthcheck (simple HTTP)
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD curl -fsS http://127.0.0.1:${PORT}/health || exit 1

# Drop privileges
USER appuser

# Default command
CMD ["python", "app.py"]

```

> Key points:
> 
> - `COPY requirements.txt` in a separate step → layers stay cached until dependencies change.
> - `USER appuser` → the application doesn’t run as root.
> - `HEALTHCHECK` → exposes container health status in `docker ps`.

---

## 4) Build & run (plain Docker)

From `labs/lesson_23/app`:

```bash
cd labs/day23/app

# Build image
docker build -t lab23-web:dev .

# List images
docker image ls | grep lab23

# Run image
docker run --rm -p 8080:8080 lab23-web:dev

# If not Docker, but someone on 8080 (nginx)
# sudo ss -tulpn | grep :8080
# sudo systemctl stop nginx
# Or just change port with docker run --rm -p 8081:8080 lab23-web:dev
```

Test in another terminal:

```bash
curl -s http://127.0.0.1:8080/ | jq
curl -s http://127.0.0.1:8080/health | jq
docker ps   # health status should be "healthy" after a bit
```

Stop container (Ctrl+C in the first terminal or `docker ps` + `docker stop`).

---

## 5) Docker Compose integration

`labs/lesson_23/compose/docker-compose.yml`:

```yaml
services:
  lab23-web:
    build:
      context: ../app
      dockerfile: Dockerfile
    image: lab23-web:dev
    container_name: lab23-web
    environment:
      LAB_ENV: "lab"
      PORT: "8080"
    ports:
      - "127.0.0.1:8080:8080"
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS http://127.0.0.1:8080/health || exit 1"]
      interval: 30s
      timeout: 3s
      retries: 3
      start_period: 10s
    restart: unless-stopped
```

Run:

```bash
cd labs/lesson_23/compose
docker compose up -d
docker compose ps
curl -s http://127.0.0.1:8080/ | jq
curl -s http://127.0.0.1:8080/health | jq
```

---

## 6) Tagging & inspection

Play with tags:

```bash
cd labs/lesson_23/app

# Tag as v1
docker tag lab23-web:dev lab23-web:v1

# List images <all tag>
docker image ls lab23-web

# Inspect image metadata
docker inspect lab23-web:dev | jq '.[0].Config.User, .[0].Config.Labels'

# Layer history
docker history lab23-web:dev
```

> Dockerfile instructions are reflected in `docker history` (compressed into layers).
> 

---

## 7) Cleanup

```bash
cd labs/lesson_23/compose
docker compose down

# Сlean tag
docker image rm lab23-web:dev lab23-web:v1 2>/dev/null || true
```

---

## Сore

- [ ]  The `lab23-web` image builds successfully.
- [ ]  The container runs via `docker run` and responds on `/` and `/health`.
- [ ]  A `.dockerignore` file is present and excludes unnecessary files.
- [ ]  `USER appuser` is set in the Dockerfile, and this is visible in `docker inspect`.

Extended tasks:

1. Add **build args** and environment variables (for example, `BUILD_VERSION`).
2. Create an additional tag `lab23-web:prod` (simulating a production build).
3. Write a small script in `tools/` that:
    - builds the image,
    - runs a couple of `curl` checks,
    - prints the image size and layer history.
4. Intentionally **break** the application (an error in `app.py` or in the dependencies) and see how it shows up in the container logs and in the `docker build` output.

---

## Acceptance Criteria

- [ ]  The Dockerfile in `labs/lesson_23/app` produces a working image that runs on port 8080.
- [ ]  The application runs under a non-root user (`appuser`).
- [ ]  A `.dockerignore` file is present and correctly configured.
- [ ]  `docker compose up -d` from `labs/lesson_23/compose` brings the service up and the healthcheck is **healthy**.
- [ ]  Can inspect the image’s layer history and basic metadata.

---

## Summary

- Learned how to write a **Dockerfile** for a simple web service (Python).
- Added a `.dockerignore`, a non-root user, and a healthcheck.
- Learned how to tag, run, inspect, and clean up images.
- Laid the groundwork for the next steps: multi-stage builds, image size optimization, and registry/CI.

---

## Artifacts

- `lesson_23.md`
- `labs/lesson_23/app/{app.py,requirements.txt,Dockerfile,.dockerignore}`
- `labs/lesson_23/compose/docker-compose.yml`