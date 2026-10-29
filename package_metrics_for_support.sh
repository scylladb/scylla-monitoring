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

# Versioning. By default the script pulls the image tag matching its version.
# Override at run-time with --image-tag <tag> (e.g. --image-tag latest, or a
# pinned version like --image-tag v1.1) when support asks you to.
SCRIPT_VERSION="v1.1"
DEFAULT_IMAGE_TAG="$SCRIPT_VERSION"
SCRAPER_IMAGE_REPO="public.ecr.aws/scylladb-sre/scylladb-metrics-packager"

VERBOSE_COUNT=0
IMAGE_TAG="$DEFAULT_IMAGE_TAG"
DAYS=""
FORCE_DAILY=false
DIAGNOSTICS=false

usage() {
    cat <<EOF
ScyllaDB Metrics Packager ${SCRIPT_VERSION}

Usage: $(basename "$0") [options]

Options:
  -v, --verbose          Show detailed execution information. Give it twice
                         (-v -v or -vv) to also turn on debug logging.
  --image-tag <tag>      Container image tag to pull (default: ${DEFAULT_IMAGE_TAG}).
                         Use this only when ScyllaDB Support asks you to run a
                         specific build (e.g. --image-tag v1.1 or --image-tag latest).
  --days <n>             Collect the last <n> days instead of the default (90).
  --force-daily          Query one day at a time from the start. Use this when
                         ScyllaDB Support tells you that multi-day queries time
                         out on your Prometheus server.
  --diagnostics          Print the collection diagnostics table at the end of
                         the run. ScyllaDB Support may ask for it.
                         --days, --force-daily and --diagnostics need image
                         v1.1 or later.
  -h, --help             Show this help and exit.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        -v|--verbose)
            VERBOSE_COUNT=$((VERBOSE_COUNT + 1))
            shift
            ;;
        -vv)
            VERBOSE_COUNT=$((VERBOSE_COUNT + 2))
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
        --days)
            if [ $# -lt 2 ] || [ -z "$2" ]; then
                echo "Error: --days requires a number of days."
                exit 1
            fi
            DAYS="$2"
            shift 2
            ;;
        --days=*)
            DAYS="${1#--days=}"
            if [ -z "$DAYS" ]; then
                echo "Error: --days requires a number of days."
                exit 1
            fi
            shift
            ;;
        --force-daily)
            FORCE_DAILY=true
            shift
            ;;
        --diagnostics)
            DIAGNOSTICS=true
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

# Fail before the image pull on a non-number; the CLI owns the range check.
if [ -n "$DAYS" ] && ! [[ "$DAYS" =~ ^[0-9]+$ ]]; then
    echo "Error: --days must be a whole number (got: ${DAYS})."
    exit 1
fi

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
    if [ "$VERBOSE_COUNT" -gt 0 ]; then
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

    if [ "$VERBOSE_COUNT" -gt 0 ]; then
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
        echo "  Days:        ${DAYS:-default (90)}"
        if [ "$FORCE_DAILY" = true ]; then
            echo "  Query mode:  one day at a time (forced)"
        else
            echo "  Query mode:  full range, one day at a time on failure"
        fi
    fi
    echo ""
}

run_container() {
    echo "Preparing environment..."
    if [ "$VERBOSE_COUNT" -gt 0 ]; then
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
    # Pass the long form once per level: images before v1.1 reject -v and
    # treat --verbose as a plain flag, so a repeated --verbose is still valid.
    if [ "$VERBOSE_COUNT" -ge 1 ]; then
        extra_flags+=("--verbose")
    fi
    if [ "$VERBOSE_COUNT" -ge 2 ]; then
        extra_flags+=("--verbose")
    fi
    if [ -n "$DAYS" ]; then
        extra_flags+=("--days" "$DAYS")
    fi
    if [ "$FORCE_DAILY" = true ]; then
        extra_flags+=("--force-daily")
    fi
    if [ "$DIAGNOSTICS" = true ]; then
        extra_flags+=("--diagnostics")
    fi
    # Pick the right --user flag based on the container runtime's mode so the
    # bind-mounted output file ends up owned by the host user invoking this
    # script.
    #
    # Rootful Docker / rootful Podman:
    #   The container UID equals the host UID, so we pass $(id -u):$(id -g).
    # Rootless Docker / rootless Podman:
    #   The daemon runs inside a user namespace where container UID 0 maps to
    #   the host user, while any other container UID is remapped via
    #   /etc/subuid (e.g. host UID 1006 used as --user inside the container
    #   becomes some unrelated subuid like 101005 on the host, which has no
    #   write permission to the host-owned output directory and triggers
    #   "Permission denied" when the scraper tries to create the result file).
    #   Run the container as UID 0 so it writes as the host user.
    local is_rootless=false
    case "$CONTAINER_CMD" in
        docker)
            if docker info --format '{{json .SecurityOptions}}' 2>/dev/null \
                    | grep -q '"name=rootless"'; then
                is_rootless=true
            fi
            ;;
        podman)
            if [ "$(podman info --format '{{.Host.Security.Rootless}}' 2>/dev/null)" = "true" ]; then
                is_rootless=true
            fi
            ;;
    esac

    local user_flag
    if [ "$is_rootless" = true ]; then
        user_flag="0:0"
        if [ "$VERBOSE_COUNT" -gt 0 ]; then
            echo "Detected rootless ${CONTAINER_CMD}; running container as UID 0 so the output file is owned by $(id -un) on the host."
        fi
    else
        user_flag="$(id -u):$(id -g)"
    fi

    # Capture the container's exit code instead of letting `set -e` abort
    # on a non-zero exit. The CLI returns 1 when individual queries failed
    # but it has still written a useful (partial) output file via the bind
    # mount; we want to keep showing the user where that file is.
    local container_exit=0
    local out_path="${OUTPUT_DIR}/${OUTPUT_FILE}"

    if [ -n "$USERNAME" ] && [ -n "$PASSWORD" ]; then
        # Stream both username and password into the container's stdin behind
        # --auth-stdin so neither value lands in argv, env (visible to
        # `docker inspect`), or shell history. The bytes only live in the
        # kernel pipe and the container process memory.
        # SCRIPT_VERSION is not a secret; the CLI records it in the output's
        # diagnostics so support can tell which script produced a file.
        printf '%s\n%s\n' "$USERNAME" "$PASSWORD" | ${CONTAINER_CMD} run --rm -i \
            --user "$user_flag" \
            --network host \
            -e "SCRIPT_VERSION=${SCRIPT_VERSION}" \
            -v "${OUTPUT_DIR}:/output" \
            "$SCRAPER_IMAGE" \
            --url "$PROMETHEUS_URL" \
            --output "/output/${OUTPUT_FILE}" \
            --auth-stdin \
            ${extra_flags[@]+"${extra_flags[@]}"} \
            || container_exit=${PIPESTATUS[1]}
    else
        ${CONTAINER_CMD} run --rm \
            --user "$user_flag" \
            --network host \
            -e "SCRIPT_VERSION=${SCRIPT_VERSION}" \
            -v "${OUTPUT_DIR}:/output" \
            "$SCRAPER_IMAGE" \
            --url "$PROMETHEUS_URL" \
            --output "/output/${OUTPUT_FILE}" \
            ${extra_flags[@]+"${extra_flags[@]}"} \
            || container_exit=$?
    fi

    echo ""
    if [ -f "$out_path" ]; then
        if [ "$container_exit" -eq 0 ]; then
            echo "Done! Results saved to:"
        else
            echo "Completed with errors. Partial results saved to:"
        fi
        echo "  $out_path"
        echo ""
        echo "You can share this file with your ScyllaDB Support."
    else
        echo "Error: ${CONTAINER_CMD} exited with code ${container_exit} and no output file was produced."
        if [ "$container_exit" -eq 0 ]; then
            container_exit=1
        fi
    fi

    exit "$container_exit"
}

main() {
    detect_container_runtime
    gather_inputs
    validate_and_confirm
    run_container
}

main
