#!/usr/bin/env bash

set -Eeuo pipefail

DEPLOY_SHA="${1:-}"
CANDIDATE_COMPOSE="${2:-/tmp/taskforge-compose.yaml}"

DEPLOY_DIR="/opt/taskforge"
ENV_FILE="${DEPLOY_DIR}/.env"
COMPOSE_FILE="${DEPLOY_DIR}/compose.yaml"

PROJECT_NAME="taskforge"
IMAGE="ghcr.io/eguerichnel2025/taskforge:${DEPLOY_SHA}"

log() {
    printf '[TaskForge Deploy] %s\n' "$1"
}

fail() {
    printf '[TaskForge Deploy] ERROR: %s\n' "$1" >&2
    exit 1
}

if [[ "$(id -u)" -ne 0 ]]; then
    fail "This script must run as root through AWS SSM."
fi

if [[ ! "$DEPLOY_SHA" =~ ^[0-9a-f]{40}$ ]]; then
    fail "A valid 40-character Git commit SHA is required."
fi

if [[ ! -s "$CANDIDATE_COMPOSE" ]]; then
    fail "The candidate Docker Compose file is missing or empty."
fi

if [[ ! -f "$ENV_FILE" ]]; then
    fail "Production environment file not found."
fi

ENV_MODE="$(stat -c '%a' "$ENV_FILE")"
ENV_OWNER="$(stat -c '%U:%G' "$ENV_FILE")"

if [[ "$ENV_MODE" != "600" || "$ENV_OWNER" != "root:root" ]]; then
    fail "Production environment file permissions are incorrect."
fi

if ! docker volume inspect taskforge_postgres_data >/dev/null 2>&1; then
    fail "Existing PostgreSQL volume was not found. Refusing deployment."
fi

export TASKFORGE_IMAGE="$IMAGE"

compose() {
    docker compose \
        --project-name "$PROJECT_NAME" \
        --env-file "$ENV_FILE" \
        --file "$COMPOSE_FILE" \
        "$@"
}

log "Validating deployment configuration."

docker compose \
    --project-name "$PROJECT_NAME" \
    --env-file "$ENV_FILE" \
    --file "$CANDIDATE_COMPOSE" \
    config --quiet

log "Pulling application image: $IMAGE"

docker compose \
    --project-name "$PROJECT_NAME" \
    --env-file "$ENV_FILE" \
    --file "$CANDIDATE_COMPOSE" \
    pull api

log "Installing validated Compose configuration."

install -o root -g root -m 0644 \
    "$CANDIDATE_COMPOSE" \
    "${COMPOSE_FILE}.new"

mv -f "${COMPOSE_FILE}.new" "$COMPOSE_FILE"

wait_for_health() {
    local service="$1"
    local attempt
    local container_id
    local state
    local health

    for attempt in $(seq 1 36); do
        container_id="$(compose ps -q "$service" 2>/dev/null || true)"

        if [[ -n "$container_id" ]]; then
            state="$(docker inspect \
                --format '{{.State.Status}}' "$container_id")"

            health="$(docker inspect \
                --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' \
                "$container_id")"

            if [[ "$state" == "running" && "$health" == "healthy" ]]; then
                log "$service is healthy."
                return 0
            fi

            if [[ "$state" == "exited" || "$health" == "unhealthy" ]]; then
                compose logs --tail=60 "$service" >&2 || true
                return 1
            fi
        fi

        sleep 5
    done

    compose logs --tail=60 "$service" >&2 || true
    return 1
}

log "Ensuring PostgreSQL is running."

compose up -d db

if ! wait_for_health db; then
    fail "PostgreSQL did not become healthy."
fi

log "Starting the TaskForge API."

compose up -d --no-deps api

if ! wait_for_health api; then
    fail "TaskForge API did not become healthy."
fi

log "Running final HTTP health checks."

curl --fail --silent --show-error \
    http://127.0.0.1:8000/health

printf '\n'

curl --fail --silent --show-error \
    http://127.0.0.1:8000/health/ready

printf '\n'

log "Deployment completed successfully."
log "Image: $IMAGE"

compose ps
