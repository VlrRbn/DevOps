#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="${ROOT_DIR}/app"
COMPOSE_DIR="${ROOT_DIR}/compose"

log() {
  printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"
}

build_images() {
  log "Building dev image..."
  docker build -f "${APP_DIR}/Dockerfile.dev" -t lab23:dev "${APP_DIR}"

  log "Building prod image..."
  docker build -f "${APP_DIR}/Dockerfile.prod" -t lab23:prod \
    --build-arg BUILD_VERSION="prod-$(date +%Y%m%d%H%M)" \
    "${APP_DIR}"
}

show_image_info() {
  log "Image list:"
  docker image ls lab23

  log "Inspect dev image user & labels:"
  docker inspect lab23:dev | jq '.[0].Config.User, .[0].Config.Labels'

  log "Inspect prod image user & labels:"
  docker inspect lab23:prod | jq '.[0].Config.User, .[0].Config.Labels'

  log "History for dev:"
  docker history lab23:dev

  log "History for prod:"
  docker history lab23:prod
}

run_tests() {
  log "Starting dev..."
  docker compose -f "${COMPOSE_DIR}/docker-compose.dev.yml" up -d
  sleep 5

  log "Checking dev endpoints..."
  curl -s http://127.0.0.1:8080/health | jq .
  curl -s http://127.0.0.1:8080/ | jq .

  log "Starting prod..."
  docker compose -f "${COMPOSE_DIR}/docker-compose.prod.yml" up -d
  sleep 10

  log "Checking prod endpoints..."
  curl -s http://127.0.0.1:18080/health | jq .
  curl -s http://127.0.0.1:18080/ | jq .
}

cleanup() {
  log "Stopping..."
  docker compose -f "${COMPOSE_DIR}/docker-compose.dev.yml" down || true
  docker compose -f "${COMPOSE_DIR}/docker-compose.prod.yml" down || true
}

case "${1:-}" in
  build)
    build_images
    ;;
  info)
    show_image_info
    ;;
  test)
    run_tests
    ;;
  cleanup)
    cleanup
    ;;
  all|"")
    build_images
    show_image_info
    run_tests
    ;;
esac
