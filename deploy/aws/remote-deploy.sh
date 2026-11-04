#!/usr/bin/env bash

set -Eeuo pipefail

DEPLOY_SHA="${1:-}"
CANDIDATE_COMPOSE="${2:-/tmp/taskforge-compose.yaml}"

DEPLOY_DIR="/opt/taskforge"
ENV_FILE="${DEPLOY_DIR}/.env"
COMPOSE_FILE="${DEPLOY_DIR}/compose.yaml"

PROJECT_NAME="taskforge"

IMAGE="ghcr.io/eguerichnel2025/taskforge:${DEPLOY_SHA}"

BACKUP_COMPOSE=""
ROLLBACK_OVERRIDE=""
PREVIOUS_IMAGE_ID=""
ROLLBACK_IMAGE_TAG=""
ROLLBACK_ARMED=0

log() {
    printf '[TaskForge Deploy] %s\n' "$1"
}

fail() {
    printf '[TaskForge Deploy] ERROR: %s\n' "$1" >&2
    exit 1
}

compose() {
    docker compose \
        --project-name "$PROJECT_NAME" \
        --env-file "$ENV_FILE" \
        --file "$COMPOSE_FILE" \
        "$@"
}

compose_rollback() {
    docker compose \
        --project-name "$PROJECT_NAME" \
        --env-file "$ENV_FILE" \
        --file "$COMPOSE_FILE" \
        --file "$ROLLBACK_OVERRIDE" \
        "$@"
}

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

rollback_on_exit() {
    local exit_code=$?

    trap - EXIT

    if [[ "$exit_code" -ne 0 && "$ROLLBACK_ARMED" -eq 1 ]]; then
        log "Deployment failed. Starting automatic rollback."

        if [[ -s "$BACKUP_COMPOSE" && -s "$ROLLBACK_OVERRIDE" && -n "$ROLLBACK_IMAGE_TAG" ]]; then
            cp -p "$BACKUP_COMPOSE" "$COMPOSE_FILE"

            log "Restoring exact previous image: $ROLLBACK_IMAGE_TAG"

            if compose_rollback up -d --pull never --no-recreate db \
                && wait_for_health db \
                && compose_rollback up -d --pull never --no-deps api \
                && wait_for_health api; then

                log "Rollback completed. Previous application restored."
            else
                log "CRITICAL: Automatic rollback failed."
                log "Manual inspection of EC2 is required."
            fi
        else
            log "CRITICAL: Previous deployment backup is incomplete."
        fi
    fi

    if [[ -n "$BACKUP_COMPOSE" ]]; then
        rm -f "$BACKUP_COMPOSE"
    fi

    if [[ -n "$ROLLBACK_OVERRIDE" ]]; then
        rm -f "$ROLLBACK_OVERRIDE"
    fi

    exit "$exit_code"
}

trap rollback_on_exit EXIT

# --------------------------------------------------
# 1. Validate deployment prerequisites
# --------------------------------------------------

if [[ "$(id -u)" -ne 0 ]]; then
    fail "This script must run as root through AWS SSM."
fi

if [[ ! "$DEPLOY_SHA" =~ ^[0-9a-f]{40}$ ]]; then
    fail "A valid 40-character Git commit SHA is required."
fi

if [[ ! -s "$CANDIDATE_COMPOSE" ]]; then
    fail "Candidate Docker Compose file is missing or empty."
fi

if [[ ! -f "$ENV_FILE" ]]; then
    fail "Production environment file not found."
fi

if [[ ! -f "$COMPOSE_FILE" ]]; then
    fail "Existing Docker Compose configuration not found."
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

log "Validating candidate Docker Compose configuration."

docker compose \
    --project-name "$PROJECT_NAME" \
    --env-file "$ENV_FILE" \
    --file "$CANDIDATE_COMPOSE" \
    config --quiet

# --------------------------------------------------
# 2. Prepare the new image
# --------------------------------------------------

log "Pulling application image: $IMAGE"

docker compose \
    --project-name "$PROJECT_NAME" \
    --env-file "$ENV_FILE" \
    --file "$CANDIDATE_COMPOSE" \
    pull api

# --------------------------------------------------
# 3. Capture the previous deployment
# --------------------------------------------------

API_CONTAINER="$(compose ps -q api)"

if [[ -z "$API_CONTAINER" ]]; then
    fail "Existing TaskForge API container was not found."
fi

PREVIOUS_IMAGE_ID="$(docker inspect \
    --format '{{.Image}}' "$API_CONTAINER")"

if [[ ! "$PREVIOUS_IMAGE_ID" =~ ^sha256:[0-9a-f]{64}$ ]]; then
    fail "Unable to identify the previous application image ID."
fi

ROLLBACK_IMAGE_TAG="taskforge-rollback:${DEPLOY_SHA:0:12}"

log "Preserving previous image locally: $PREVIOUS_IMAGE_ID"

docker image tag "$PREVIOUS_IMAGE_ID" "$ROLLBACK_IMAGE_TAG"

BACKUP_COMPOSE="$(mktemp "${DEPLOY_DIR}/compose.rollback.XXXXXX")"

cp -p "$COMPOSE_FILE" "$BACKUP_COMPOSE"

ROLLBACK_OVERRIDE="$(mktemp "${DEPLOY_DIR}/compose.rollback.override.XXXXXX")"

printf 'services:\n  api:\n    image: "%s"\n' \
    "$ROLLBACK_IMAGE_TAG" > "$ROLLBACK_OVERRIDE"

chown root:root "$ROLLBACK_OVERRIDE"
chmod 600 "$ROLLBACK_OVERRIDE"

# --------------------------------------------------
# 4. Activate the new deployment
# --------------------------------------------------

install -o root -g root -m 0644 \
    "$CANDIDATE_COMPOSE" \
    "${COMPOSE_FILE}.new"

ROLLBACK_ARMED=1

mv -f "${COMPOSE_FILE}.new" "$COMPOSE_FILE"

log "Ensuring PostgreSQL is running."

compose up -d --no-recreate db

if ! wait_for_health db; then
    fail "PostgreSQL did not become healthy."
fi

log "Starting TaskForge API."

compose up -d --no-deps api

if ! wait_for_health api; then
    fail "TaskForge API did not become healthy."
fi

# --------------------------------------------------
# 5. Final application checks
# --------------------------------------------------

log "Running HTTP health checks."

curl --fail --silent --show-error \
    http://127.0.0.1:8000/health

printf '\n'

curl --fail --silent --show-error \
    http://127.0.0.1:8000/health/ready

printf '\n'

compose ps

log "Deployment completed successfully."
log "Image: $IMAGE"

ROLLBACK_ARMED=0
