#!/usr/bin/env bash
set -euo pipefail

# Check if docker command is available
if ! command -v docker &> /dev/null; then
    echo "ERROR: docker command not found. Please install Docker first." >&2
    exit 1
fi

TAG="${TAG:-v3.5.6}"
IMG="traefik:${TAG}"

CANDIDATES=(
    "public.ecr.aws/docker/library/traefik:${TAG}"
    "docker.io/library/traefik:${TAG}"
)

MAX_RETRIES=3
RETRY_DELAY=5

echo "==> Attempting to pull ${IMG}..."
echo ""

for ref in "${CANDIDATES[@]}"; do
    for attempt in $(seq 1 $MAX_RETRIES); do
        echo "==> Trying ${ref} (attempt ${attempt}/${MAX_RETRIES})..."

        if docker pull --quiet "$ref"; then
            echo "==> Successfully pulled from ${ref}"
            docker tag "$ref" "$IMG"
            echo "==> Tagged as ${IMG}"
            exit 0
        fi

        if [ "$attempt" -lt $MAX_RETRIES ]; then
            echo "==> Pull failed, retrying in ${RETRY_DELAY}s..." >&2
            sleep $RETRY_DELAY
        fi
    done

    echo "==> Failed to pull from ${ref} after ${MAX_RETRIES} attempts" >&2
    echo "" >&2
done

echo "ERROR: Failed to pull ${IMG} from any registry" >&2
exit 1
