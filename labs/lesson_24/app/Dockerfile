FROM python:3.12-slim AS runtime

LABEL maintainer="you@yourdomain.net" \
      service="lab24-web" \
      env="lab"

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl iputils-ping redis-tools \
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
