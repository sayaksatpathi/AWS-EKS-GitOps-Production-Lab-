import os
import time
import socket
import logging
import json
from datetime import datetime
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
from flask import Flask, jsonify, Response, request

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s %(levelname)s %(name)s %(message)s'
)
logger = logging.getLogger(__name__)

app = Flask(__name__)

REQUEST_COUNT = Counter(
    'cloudlaunch_http_requests_total',
    'Total HTTP requests',
    ['method', 'endpoint', 'status']
)
REQUEST_LATENCY = Histogram(
    'cloudlaunch_http_request_duration_seconds',
    'HTTP request latency',
    ['method', 'endpoint']
)
ERROR_COUNT = Counter(
    'cloudlaunch_errors_total',
    'Total errors',
    ['type']
)

APP_NAME = os.getenv('APP_NAME', 'cloudlaunch-api')
APP_VERSION = os.getenv('APP_VERSION', '1.0.0')
POD_NAME = os.getenv('POD_NAME', socket.gethostname())
NAMESPACE = os.getenv('NAMESPACE', 'default')
FAIL_READY = os.getenv('FAIL_READY', 'false').lower() == 'true'
FAIL_STARTUP = os.getenv('FAIL_STARTUP', 'false').lower() == 'true'
START_TIME = time.time()

if FAIL_STARTUP:
    logger.error("FAIL_STARTUP=true — simulating startup failure")
    raise RuntimeError("Simulated startup failure for rollback demo")


@app.before_request
def start_timer():
    request.start_time = time.time()


@app.after_request
def record_metrics(response):
    latency = time.time() - getattr(request, 'start_time', time.time())
    endpoint = request.path
    REQUEST_COUNT.labels(
        method=request.method,
        endpoint=endpoint,
        status=response.status_code
    ).inc()
    REQUEST_LATENCY.labels(
        method=request.method,
        endpoint=endpoint
    ).observe(latency)
    logger.info(
        json.dumps({
            "event": "http_request",
            "method": request.method,
            "path": endpoint,
            "status": response.status_code,
            "latency_ms": round(latency * 1000, 2),
            "pod": POD_NAME,
            "version": APP_VERSION,
        })
    )
    return response


@app.route('/')
def index():
    return jsonify({
        "service": APP_NAME,
        "version": APP_VERSION,
        "pod": POD_NAME,
        "namespace": NAMESPACE,
        "uptime_seconds": round(time.time() - START_TIME, 2),
        "timestamp": datetime.utcnow().isoformat() + 'Z',
    })


@app.route('/health')
def health():
    return jsonify({"status": "healthy", "pod": POD_NAME, "version": APP_VERSION})


@app.route('/ready')
def ready():
    if FAIL_READY:
        ERROR_COUNT.labels(type='readiness_failure').inc()
        logger.warning(json.dumps({
            "event": "readiness_failure",
            "pod": POD_NAME,
            "version": APP_VERSION,
            "reason": "FAIL_READY=true"
        }))
        return jsonify({"status": "not_ready", "reason": "FAIL_READY=true", "version": APP_VERSION}), 503
    return jsonify({"status": "ready", "pod": POD_NAME, "version": APP_VERSION})


@app.route('/metrics')
def metrics():
    return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)


@app.route('/api/v1/items')
def list_items():
    return jsonify({
        "items": [
            {"id": 1, "name": "Widget Alpha", "category": "tools"},
            {"id": 2, "name": "Widget Beta", "category": "tools"},
            {"id": 3, "name": "Gadget Gamma", "category": "gadgets"},
        ],
        "pod": POD_NAME,
        "version": APP_VERSION,
    })


if __name__ == '__main__':
    port = int(os.getenv('PORT', '8080'))
    logger.info(json.dumps({
        "event": "startup",
        "service": APP_NAME,
        "version": APP_VERSION,
        "pod": POD_NAME,
        "port": port,
    }))
    app.run(host='0.0.0.0', port=port)
