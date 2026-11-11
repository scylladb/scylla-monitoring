#!/usr/bin/env bash
#
# A new machine's disk loads from the image's snapshot on first read, which is
# slow. This reads Grafana's files once on boot, while the machine waits to be
# configured, so Grafana's first start finds them on the disk.
#
# usage: scylla-monitoring-preread.sh [list file]
#        scylla-monitoring-preread.sh --list [docker directory...]
#
# Without --list: reads every file under the paths in the list file, in order,
# and logs one summary line. A relative path is relative to the monitoring
# directory, the working directory; a missing path is skipped. env.sh settings:
#   GRAFANA_PREREAD=0         turns it off
#   GRAFANA_PREREAD_TIMEOUT   stops it after this many seconds (default 300)
#   GRAFANA_PREREAD_PARALLEL  files read at the same time (default 4)
#
# --list, run when the image is built: prints the list. First Grafana's image
# layers, found by path so that any Docker storage driver works: the binary,
# conf, and the bundled plugins that env.sh's GF_PLUGINS_DISABLE_PLUGINS does
# not disable. Then the directories of the monitoring stack Grafana mounts.
# It fails when it finds no Grafana binary.
#
# Runs as root to read Docker's directories. env.sh belongs to the monitoring
# user, which is in the docker group and so already has root's permissions.

set -o pipefail
[ -f env.sh ] && . ./env.sh

if [ "${1:-}" = "--list" ]; then
	shift
	[ $# -gt 0 ] || set -- /var/lib/docker /var/lib/containerd
	disabled=",${GF_PLUGINS_DISABLE_PLUGINS// /},"
	# */merged/* is a running container's view of the same layers
	mapfile -t layers < <(find "$@" -type d -path '*/usr/share/grafana' -not -path '*/merged/*' -prune 2>/dev/null | sort)
	found=1
	for layer in "${layers[@]}"; do
		[ -f "$layer/bin/grafana" ] && echo "$layer/bin" && found=0
	done
	for layer in "${layers[@]}"; do
		[ -d "$layer/conf" ] && echo "$layer/conf"
	done
	for layer in "${layers[@]}"; do
		for plugin in "$layer"/data/plugins-bundled/*/; do
			plugin=${plugin%/}
			[ -d "$plugin" ] || continue
			# a bundled plugin's directory is named by its plugin id
			[[ $disabled == *",${plugin##*/},"* ]] || echo "$plugin"
		done
	done
	printf '%s\n' grafana/plugins grafana/provisioning grafana/build
	[ $found -eq 0 ] || echo "No Grafana binary under $*" >&2
	exit $found
fi

if [ "${GRAFANA_PREREAD:-1}" = 0 ]; then
	echo "Grafana pre-read: off, GRAFANA_PREREAD=0"
	exit 0
fi

limit=${GRAFANA_PREREAD_TIMEOUT:-300}
paths=()
while IFS= read -r path; do
	[ -e "$path" ] && paths+=("$path")
done < "${1:-/etc/scylla-monitoring-preread.list}"

bytes=0
status=0
if [ ${#paths[@]} -gt 0 ]; then
	# -n 16: with xargs' default of thousands of files per cat, -P has nothing to run in parallel
	bytes=$(find "${paths[@]}" -type f -print0 2>/dev/null |
		timeout "$limit" xargs -0 -r -n 16 -P "${GRAFANA_PREREAD_PARALLEL:-4}" cat 2>/dev/null | wc -c)
	status=$?
fi
case $status in
0) result=finished ;;
124) result="stopped by the ${limit}s limit" ;;
*) result="ended with read errors (status $status)" ;;
esac
echo "Grafana pre-read: $result, $((bytes / 1048576)) MB in ${SECONDS}s"
