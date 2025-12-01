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

for ref in "${CANDIDATES[@]}"; do
	echo "Trying to pull ${ref}"
    for attempt in $(seq 1 $MAX_RETRIES); do
        if docker pull --quiet "$ref"; then
            echo "Successfully pulled from ${ref}"
            docker tag "$ref" "$IMG"
            echo "Tagged as ${IMG}"
            exit 0
        fi

        if [ "$attempt" -lt $MAX_RETRIES ]; then
        	printf '.'
            sleep $RETRY_DELAY
        fi
    done

    echo "Failed to pull from ${ref} after ${MAX_RETRIES} attempts" >&2
done

exit 1
