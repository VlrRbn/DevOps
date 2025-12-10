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
      service="lab30-web" \
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