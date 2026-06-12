#!/usr/bin/env bash
#
# Collects performance metrics from your Prometheus instance and packages them
# into a single metrics export file you can share with ScyllaDB Support.
#
# Licensed under the Apache License, Version 2.0. The full license text and
# the licenses of the bundled dependencies are available inside the container
# image at:
#   /app/LICENSE      — this project's license
#   /app/NOTICE       — attribution notices
#   /app/licenses/    — license texts for third-party dependencies
#
# The tool runs a lightweight container that queries your Prometheus server,
# collects the relevant ScyllaDB metrics, and writes them to a local file on
# your machine. No data is uploaded anywhere — the file stays on your host
# and you decide when and how to share it.
#
# Usage:
#   ./package_metrics_for_support.sh [-v|--verbose] [--image-tag <tag>] [-h|--help]
#
# Prerequisites: Docker or Podman

set -euo pipefail

# Versioning. Each release of this script is paired with a specific container
# image tag: by default the script pulls that exact tag, so a given copy of
# the script always produces results from a known, reproducible build.
# Override at run-time with --image-tag <tag> (e.g. --image-tag latest, or a
# pinned version like --image-tag v1.1) when support asks you to.
SCRIPT_VERSION="v1.0"
DEFAULT_IMAGE_TAG="$SCRIPT_VERSION"
SCRAPER_IMAGE_REPO="public.ecr.aws/scylladb-sre/scylladb-metrics-packager"

VERBOSE=false
IMAGE_TAG="$DEFAULT_IMAGE_TAG"

usage() {
    cat <<EOF
ScyllaDB Metrics Packager ${SCRIPT_VERSION}

Usage: $(basename "$0") [options]

Options:
  -v, --verbose          Show detailed execution information.
  --image-tag <tag>      Container image tag to pull (default: ${DEFAULT_IMAGE_TAG}).
                         Use this only when ScyllaDB Support asks you to run a
                         specific build (e.g. --image-tag v1.1 or --image-tag latest).
  -h, --help             Show this help and exit.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        --image-tag)
            if [ $# -lt 2 ] || [ -z "$2" ]; then
                echo "Error: --image-tag requires a non-empty argument."
                exit 1
            fi
            IMAGE_TAG="$2"
            shift 2
            ;;
        --image-tag=*)
            IMAGE_TAG="${1#--image-tag=}"
            if [ -z "$IMAGE_TAG" ]; then
                echo "Error: --image-tag requires a non-empty argument."
                exit 1
            fi
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Error: Unknown argument: $1"
            usage >&2
            exit 1
            ;;
    esac
done

SCRAPER_IMAGE="${SCRAPER_IMAGE_REPO}:${IMAGE_TAG}"
CONTAINER_CMD=""

detect_container_runtime() {
    if command -v docker &>/dev/null; then
        CONTAINER_CMD="docker"
    elif command -v podman &>/dev/null; then
        CONTAINER_CMD="podman"
    else
        echo "Error: Neither Docker nor Podman is installed."
        exit 1
    fi
    if [ "$VERBOSE" = true ]; then
        echo "Using ${CONTAINER_CMD} as container runtime."
    fi
}

prompt() {
    local var_name="$1" prompt_text="$2" default="$3"
    local input
    if [ -n "$default" ]; then
        read -rp "${prompt_text} [${default}]: " input
        printf -v "$var_name" '%s' "${input:-$default}"
    else
        read -rp "${prompt_text}: " input
        printf -v "$var_name" '%s' "$input"
    fi
}

prompt_secret() {
    local var_name="$1" prompt_text="$2"
    local input
    read -rsp "${prompt_text}: " input
    echo
    printf -v "$var_name" '%s' "$input"
}

gather_inputs() {
    echo ""
    echo "=== ScyllaDB Metrics Packager ${SCRIPT_VERSION} ==="
    echo ""
    echo "This tool collects ScyllaDB performance metrics from your Prometheus"
    echo "instance and saves them to a local metrics export file. The file can"
    echo "then be shared with ScyllaDB Support to help diagnose issues."
    echo ""
    echo "  • All data stays on your machine — nothing is uploaded."
    echo "  • Only ScyllaDB-related metrics are collected."
    echo "  • The process typically takes a few minutes."
    echo ""

    prompt PROMETHEUS_URL "Prometheus endpoint URL" "http://localhost:9090"
    prompt USERNAME       "Username (leave empty to skip auth)" ""
    if [ -n "$USERNAME" ]; then
        prompt_secret PASSWORD "Password"
    else
        PASSWORD=""
    fi

    local default_output_dir base_tmp
    base_tmp="${TMPDIR:-/tmp}"
    base_tmp="$(cd "$base_tmp" 2>/dev/null && pwd)" || base_tmp="/tmp"
    default_output_dir="${base_tmp%/}/scylladb-metrics-packager"
    prompt OUTPUT_DIR "Output directory" "$default_output_dir"
    # `read` does not perform tilde expansion; do it manually so paths like
    # "~/scylla-metrics" don't end up creating a literal "~" directory.
    OUTPUT_DIR="${OUTPUT_DIR/#\~/$HOME}"

    local date_part rand_part default_output_file
    date_part="$(date +%Y-%m-%d)"
    if command -v openssl &>/dev/null; then
        rand_part="$(openssl rand -hex 4)"
    else
        rand_part="$(printf '%08x' "$((RANDOM * 32768 + RANDOM))")"
    fi
    # `.smi` (ScyllaDB Metrics) is a gzipped tarball under the hood — the
    # CLI defaults to --format=tar.gz. Support engineers can extract it with
    # `tar xzf <file>.smi`.
    default_output_file="scylladb_metrics_${date_part}_${rand_part}.smi"
    prompt OUTPUT_FILE "Output file name" "$default_output_file"
}

validate_and_confirm() {
    if [ -d "$OUTPUT_DIR" ]; then
        OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"
    elif [ -e "$OUTPUT_DIR" ]; then
        echo "Error: Output path exists but is not a directory: ${OUTPUT_DIR}"
        exit 1
    else
        local mkdir_err
        if ! mkdir_err=$(mkdir -p "$OUTPUT_DIR" 2>&1); then
            echo "Error: Cannot create output directory: ${OUTPUT_DIR}"
            [ -n "$mkdir_err" ] && echo "$mkdir_err"
            exit 1
        fi
        OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"
    fi

    local full_path="${OUTPUT_DIR}/${OUTPUT_FILE}"
    if [ -f "$full_path" ]; then
        echo ""
        echo "WARNING: ${full_path} already exists."
        read -rp "Overwrite? [y/N]: " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "Aborted."
            exit 0
        fi
    fi

    if [ "$VERBOSE" = true ]; then
        echo ""
        echo "Configuration:"
        echo "  Script:      ${SCRIPT_VERSION}"
        echo "  Image:       ${SCRAPER_IMAGE}"
        echo "  Prometheus:  ${PROMETHEUS_URL}"
        if [ -n "$USERNAME" ]; then
            echo "  Auth:        enabled (user: ${USERNAME})"
        else
            echo "  Auth:        disabled"
        fi
        echo "  Output:      ${full_path}"
    fi
    echo ""
}

run_container() {
    echo "Preparing environment..."
    if [ "$VERBOSE" = true ]; then
        if ! ${CONTAINER_CMD} pull "$SCRAPER_IMAGE"; then
            echo ""
            echo "Error: Failed to pull the container image."
            echo "Please check your network connection and verify you have access to the image registry."
            exit 1
        fi
    else
        if ! ${CONTAINER_CMD} pull "$SCRAPER_IMAGE" > /dev/null 2>&1; then
            echo ""
            echo "Error: Failed to pull the container image."
            echo "Please check your network connection and verify you have access to the image registry."
            echo "Run with --verbose for more details."
            exit 1
        fi
    fi

    echo "Collecting metrics..."
    echo ""
    # Build the extra-flags array. The ${arr[@]+"${arr[@]}"} idiom is required
    # because macOS ships bash 3.2, which treats an empty array as "unset" under
    # `set -u` and aborts with "unbound variable" on a plain "${arr[@]}".
    local extra_flags=()
    if [ "$VERBOSE" = true ]; then
        extra_flags+=("--verbose")
    fi
    # Run as the current user's UID:GID so the output file is owned by the
    # caller on Linux (where bind-mount ownership is not remapped by default).
    local user_flag
    user_flag="$(id -u):$(id -g)"

    if [ -n "$USERNAME" ] && [ -n "$PASSWORD" ]; then
        # Stream both username and password into the container's stdin behind
        # --auth-stdin so neither value lands in argv, env (visible to
        # `docker inspect`), or shell history. The bytes only live in the
        # kernel pipe and the container process memory.
        printf '%s\n%s\n' "$USERNAME" "$PASSWORD" | ${CONTAINER_CMD} run --rm -i \
            --user "$user_flag" \
            --network host \
            -v "${OUTPUT_DIR}:/output" \
            "$SCRAPER_IMAGE" \
            --url "$PROMETHEUS_URL" \
            --output "/output/${OUTPUT_FILE}" \
            --auth-stdin \
            ${extra_flags[@]+"${extra_flags[@]}"}
    else
        ${CONTAINER_CMD} run --rm \
            --user "$user_flag" \
            --network host \
            -v "${OUTPUT_DIR}:/output" \
            "$SCRAPER_IMAGE" \
            --url "$PROMETHEUS_URL" \
            --output "/output/${OUTPUT_FILE}" \
            ${extra_flags[@]+"${extra_flags[@]}"}
    fi

    echo ""
    echo "Done! Results saved to:"
    echo "  ${OUTPUT_DIR}/${OUTPUT_FILE}"
    echo ""
    echo "You can share this file with your ScyllaDB Support."
}

main() {
    detect_container_runtime
    gather_inputs
    validate_and_confirm
    run_container
}

main
