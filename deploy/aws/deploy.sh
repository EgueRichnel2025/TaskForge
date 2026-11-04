#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TF_DIR="${REPO_ROOT}/infra/terraform/aws"

REMOTE_SCRIPT="${SCRIPT_DIR}/remote-deploy.sh"
COMPOSE_FILE="${SCRIPT_DIR}/compose.yaml"
ENV_TEMPLATE="${SCRIPT_DIR}/.env.example"

AWS_PROFILE="${AWS_PROFILE:-taskforge-terraform}"
export AWS_PROFILE

MODE="${1:-dry-run}"
DEPLOY_REF="${2:-HEAD}"

log() {
    printf '[TaskForge] %s\n' "$1"
}

fail() {
    printf '[TaskForge] ERROR: %s\n' "$1" >&2
    exit 1
}

case "$MODE" in
    dry-run|deploy)
        ;;
    *)
        fail "Usage: $0 [dry-run|deploy] [commit-sha]"
        ;;
esac

for command in git terraform aws docker python; do
    command -v "$command" >/dev/null 2>&1 \
        || fail "Required command not found: $command"
done

if [[ ! -f "$REMOTE_SCRIPT" || ! -f "$COMPOSE_FILE" ]]; then
    fail "Deployment files are missing."
fi

if [[ ! -f "$ENV_TEMPLATE" ]]; then
    fail "AWS environment template is missing."
fi

DEPLOY_SHA="$(git -C "$REPO_ROOT" rev-parse --verify "${DEPLOY_REF}^{commit}")" \
    || fail "Unable to resolve deployment commit."

if [[ ! "$DEPLOY_SHA" =~ ^[0-9a-f]{40}$ ]]; then
    fail "Invalid Git commit SHA."
fi

CURRENT_BRANCH="$(git -C "$REPO_ROOT" branch --show-current)"

if [[ "$CURRENT_BRANCH" != "main" ]]; then
    fail "Deployments must be initiated from the main branch."
fi

if [[ -n "$(git -C "$REPO_ROOT" status --porcelain)" ]]; then
    fail "Git working tree must be clean before deployment."
fi

IMAGE="ghcr.io/eguerichnel2025/taskforge:${DEPLOY_SHA}"

log "Deployment commit: $DEPLOY_SHA"
log "Docker image: $IMAGE"

log "Checking Terraform outputs."

INSTANCE_ID="$(terraform -chdir="$TF_DIR" output -raw ec2_instance_id)"
AWS_REGION="$(terraform -chdir="$TF_DIR" output -raw aws_region)"

if [[ ! "$INSTANCE_ID" =~ ^i-[0-9a-f]+$ ]]; then
    fail "Terraform returned an invalid EC2 instance ID."
fi

log "EC2 instance: $INSTANCE_ID"
log "AWS region: $AWS_REGION"

log "Checking AWS authentication."

aws sts get-caller-identity \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --no-cli-pager >/dev/null

log "Checking EC2 Systems Manager availability."

PING_STATUS="$(aws ssm describe-instance-information \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
    --query 'InstanceInformationList[0].PingStatus' \
    --output text)"

if [[ "$PING_STATUS" != "Online" ]]; then
    fail "EC2 is not online in Systems Manager: $PING_STATUS"
fi

log "Checking GHCR image availability."

docker manifest inspect "$IMAGE" >/dev/null \
    || fail "Docker image is not available on GHCR."

log "Validating AWS Docker Compose configuration."

docker compose \
    --env-file "$ENV_TEMPLATE" \
    --file "$COMPOSE_FILE" \
    config --quiet

if [[ "$MODE" == "dry-run" ]]; then
    log "Pre-deployment checks passed."
    log "Dry run completed. No AWS resources or containers were modified."
    exit 0
fi

printf '\n'
printf 'Target: %s (%s)\n' "$INSTANCE_ID" "$AWS_REGION"
printf 'Image:  %s\n' "$IMAGE"
printf 'Deploy this version? [y/N] '

read -r CONFIRMATION

if [[ ! "$CONFIRMATION" =~ ^[Yy]$ ]]; then
    log "Deployment cancelled."
    exit 0
fi

log "Preparing SSM deployment payload."

PARAMETERS_JSON="$(
    python - "$REMOTE_SCRIPT" "$COMPOSE_FILE" "$DEPLOY_SHA" <<'PY'
import base64
import json
import pathlib
import sys

script = pathlib.Path(sys.argv[1]).read_bytes()
compose = pathlib.Path(sys.argv[2]).read_bytes()
commit_sha = sys.argv[3]

script_b64 = base64.b64encode(script).decode("ascii")
compose_b64 = base64.b64encode(compose).decode("ascii")

remote_dir = "/tmp/taskforge-deploy"

commands = [
    "set -Eeuo pipefail",
    f"install -d -o root -g root -m 0700 {remote_dir}",
    f"printf '%s' '{script_b64}' | base64 --decode > {remote_dir}/remote-deploy.sh",
    f"printf '%s' '{compose_b64}' | base64 --decode > {remote_dir}/compose.yaml",
    f"chmod 700 {remote_dir}/remote-deploy.sh",
    f"bash {remote_dir}/remote-deploy.sh {commit_sha} {remote_dir}/compose.yaml",
]

print(json.dumps({"commands": commands}, separators=(",", ":")))
PY
)"

log "Sending deployment command to EC2."

COMMAND_ID="$(aws ssm send-command \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --instance-ids "$INSTANCE_ID" \
    --document-name "AWS-RunShellScript" \
    --comment "TaskForge deployment ${DEPLOY_SHA:0:12}" \
    --timeout-seconds 600 \
    --max-concurrency "1" \
    --max-errors "0" \
    --parameters "$PARAMETERS_JSON" \
    --query 'Command.CommandId' \
    --output text)"

if [[ ! "$COMMAND_ID" =~ ^[0-9a-f-]{36}$ ]]; then
    fail "AWS returned an invalid SSM command ID."
fi

log "SSM command ID: $COMMAND_ID"
log "Waiting for deployment result."

RESULT_JSON=""
STATUS=""

for attempt in $(seq 1 180); do
    if RESULT_JSON="$(aws ssm get-command-invocation \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" \
        --command-id "$COMMAND_ID" \
        --instance-id "$INSTANCE_ID" \
        --output json 2>/dev/null)"; then

        STATUS="$(printf '%s' "$RESULT_JSON" | \
            python -c 'import json,sys; print(json.load(sys.stdin).get("Status", ""))')"

        case "$STATUS" in
            Success|Failed|Cancelled|TimedOut|DeliveryTimedOut|ExecutionTimedOut|Undeliverable|Terminated|InvalidPlatform|AccessDenied)
                break
                ;;
        esac
    fi

    sleep 5
done

if [[ -z "$RESULT_JSON" || -z "$STATUS" ]]; then
    fail "Could not retrieve the SSM result. Command ID: $COMMAND_ID"
fi

log "Deployment status: $STATUS"

printf '\n===== REMOTE STANDARD OUTPUT =====\n'

printf '%s' "$RESULT_JSON" | python -c '
import json,sys
sys.stdout.write(json.load(sys.stdin).get("StandardOutputContent", ""))
'

printf '\n===== REMOTE STANDARD ERROR =====\n'

printf '%s' "$RESULT_JSON" | python -c '
import json,sys
sys.stdout.write(json.load(sys.stdin).get("StandardErrorContent", ""))
'

if [[ "$STATUS" != "Success" ]]; then
    fail "Deployment failed. SSM command: $COMMAND_ID"
fi

log "TaskForge deployment completed successfully."
