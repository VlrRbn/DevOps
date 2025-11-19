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