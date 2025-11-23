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
