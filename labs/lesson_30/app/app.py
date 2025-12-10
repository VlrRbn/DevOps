from flask import Flask, jsonify, request, current_app
import os
import socket
import time

try:
    import redis
except ImportError:
    redis = None

from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST

app = Flask(__name__)
start_time = time.time()

_redis_client = None

# --- Prometheus

HTTP_REQUEST = Counter(
    "labweb_http_requests_total",
    "HTTP request",
    ["method", "endpoint", "status"],
)

HTTP_LATENCY = Histogram(
    "labweb_http_request_duration_seconds",
    "HTTP request latency (seconds)",
    ["endpoint"],
)

@app.before_request
def start_timer():
    request._start_time = time.time()

@app.after_request
def record_metrics(response):
    endpoint = request.endpoint or "unknown"
    elapsed = time.time() - getattr(request, "_start_time", time.time())
    status = str(response.status_code)

    try:
        HTTP_REQUEST.labels(
            method=request.method,
            endpoint=endpoint,
            status=status,
        ).inc()

        HTTP_LATENCY.labels(endpoint=endpoint).observe(elapsed)
    except Exception as e:
        current_app.logger.exception("Failed to record metrics")
        pass

    return response

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

@app.get("/metrics")
def metrics():
    """Prometheus metrics endpoint."""
    return app.response_class(
        generate_latest(),
        mimetype=CONTENT_TYPE_LATEST,
    )

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
            hit_count = client.incr("lab30_hits")
        except Exception as exc:
            redis_error = str(exc)

    return jsonify(
        message="Hello from lab30 (metrics enabled)",
        path=request.path,
        host=request.host,
        env=os.getenv("LAB_ENV", "dev"),
        hit_count=hit_count,
        redis_error=redis_error,
    )

if __name__ == "__main__":
    port = int(os.getenv("PORT", "8080"))
    app.run(host="0.0.0.0", port=port)
