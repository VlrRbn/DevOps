# tools/lab24-compose-check.sh
#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR%/tools}"
COMPOSE_DIR="${PROJECT_ROOT}/compose"

if [[ ! -d "$COMPOSE_DIR" ]]; then
  echo "Compose dir not found: $COMPOSE_DIR" >&2
  exit 1
fi

cd "$COMPOSE_DIR"

echo "==> Bringing up lab24 stack..."
docker compose up -d

MAX_WAIT=60
SLEEP=3
elapsed=0

get_health_status() {
  local name="$1"
  docker inspect -f '{{.State.Health.Status}}' "$name" 2>/dev/null || echo "unknown"
}

cleanup() {
  echo "Stopping..."
  docker compose -f "${COMPOSE_DIR}/docker-compose.yml" down || true
}

echo "==> Waiting for containers to become healthy..."
while true; do
  web_status="$(get_health_status lab24-web)"
  redis_status="$(get_health_status lab24-redis)"
  nginx_status="$(get_health_status lab24-nginx || true)"

  printf '  WEB: %s | REDIS: %s | NGINX: %s\n' \
    "$web_status" "$redis_status" "${nginx_status:-n/a}"

  if [[ "$web_status" == "healthy" && "$redis_status" == "healthy" ]]; then
    break
  fi

  if (( elapsed >= MAX_WAIT )); then
    echo "ERROR: Timeout waiting for healthy containers" >&2
    exit 1
  fi

  sleep "$SLEEP"
  elapsed=$((elapsed + SLEEP))
done

WEB_PORT_DEFAULT=8080
WEB_PORT="$WEB_PORT_DEFAULT"

if [[ -f .env ]]; then
  export $(grep -E '^[A-Za-z_][A-Za-z0-9_]*=' .env | xargs -d $'\n') || true
fi

WEB_PORT="${WEB_PORT:-$WEB_PORT_DEFAULT}"

HEALTH_URL="http://127.0.0.1:${WEB_PORT}/health"
echo "==> Checking health endpoint: $HEALTH_URL"

if ! health_json="$(curl -fsS "$HEALTH_URL")"; then
  echo "ERROR: request to /health failed" >&2
  exit 1
fi

redis_ok="$(grep -o '"redis_ok":[^,}]*' <<<"$health_json" | head -n1 | cut -d: -f2 | tr -d '[:space:]')"
env_val="$(grep -o '"env":[^,}]*' <<<"$health_json" | head -n1 | cut -d: -f2- | tr -d '"' )"

echo "==> Summary:"
echo "  web container:    $web_status"
echo "  redis container:  $redis_status"
[[ -n "${nginx_status:-}" ]] && echo "  nginx container:   $nginx_status"
echo "  /health env:      ${env_val:-unknown}"
echo "  /health redis_ok: ${redis_ok:-unknown}"

trap cleanup EXIT INT TERM

exit 0
