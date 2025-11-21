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
