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
