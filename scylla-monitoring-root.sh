#!/usr/bin/env bash
#
# The root-only tasks of scylla_monitoring_config.py, which runs it with
# sudo -n. Installed root-owned, with a sudoers rule that lets the watcher's
# user run this script only.
#
#   scylla-monitoring-root.sh dropin <unit> <file>     install <file> as the unit's drop-in, restart the unit
#   scylla-monitoring-root.sh dropin <unit> --remove   remove the drop-in, restart the unit
#   scylla-monitoring-root.sh certs <dir> <cert dir>   install server.crt, server.key and rootCA.crt
#   scylla-monitoring-root.sh docker-proxy <file>      install <file> as docker's proxy environment
#   scylla-monitoring-root.sh docker-proxy --remove    remove docker's proxy
#
# The drop-in is /etc/systemd/system/<unit>.d/50-scylla-monitoring.conf; other
# drop-ins and the unit itself are left alone. docker-proxy installs the proxy
# as docker.service.d/50-scylla-monitoring.env, root-only since the URLs can
# hold credentials, and a drop-in that reads it with EnvironmentFile=, so
# systemctl does not show the values. It restarts docker only when they
# change, or when a restart it started did not happen; docker's restart
# restarts the watcher too (PartOf=docker.service).

set -euo pipefail

die() { echo "$@" >&2; exit 1; }

SYSTEMD_DIR=/etc/systemd/system
DROPIN=50-scylla-monitoring.conf
# docker's invocation before a proxy restart; in /run, since a reboot starts
# docker with the new proxy
PENDING=/run/scylla-monitoring-docker-proxy

# The watcher's own unit and docker would take the watcher down with them;
# docker's proxy has its own command.
REFUSED_UNITS="docker.service scylla-monitoring-config.service"

dropin() {
	local unit=$1 src=$2
	[[ "$unit" =~ ^[A-Za-z0-9@._-]+\.(service|socket|timer)$ ]] || die "error: not a unit name: $unit"
	for refused in $REFUSED_UNITS; do
		[ "$unit" != "$refused" ] || die "error: $unit cannot be changed"
	done
	local dir=$SYSTEMD_DIR/$unit.d
	local dst=$dir/$DROPIN
	if [ "$src" = "--remove" ]; then
		[ -e "$dst" ] || return 0
		rm -f "$dst"
		rmdir "$dir" 2>/dev/null || true
	else
		[ -f "$src" ] || die "error: no such file: $src"
		install -d -m 755 "$dir"
		install -m 644 "$src" "$dst.new"
		mv "$dst.new" "$dst"
	fi
	systemctl daemon-reload
	systemctl restart "$unit"
}

# docker still runs the invocation recorded before the restart: the restart
# failed to run, or the helper was stopped before it. A docker that started
# since, or failed to start, reads the new proxy when it starts.
restart_pending() {
	[ -e "$PENDING" ] && systemctl is-active -q docker.service &&
		[ "$(cat "$PENDING")" = "$(systemctl show -p InvocationID --value docker.service)" ]
}

docker_proxy() {
	local src=$1
	local dir=$SYSTEMD_DIR/docker.service.d
	local conf=$dir/$DROPIN env=$dir/${DROPIN%.conf}.env
	local unit="[Service]
EnvironmentFile=$env"
	if [ "$src" = "--remove" ]; then
		if [ -e "$conf" ] || [ -e "$env" ]; then
			systemctl show -p InvocationID --value docker.service > "$PENDING"
			rm -f "$conf" "$env"
			rmdir "$dir" 2>/dev/null || true
		elif ! restart_pending; then
			rm -f "$PENDING"
			return 0
		fi
	else
		[ -f "$src" ] || die "error: no such file: $src"
		# a private copy: the watcher's user can change $src after the check
		tmp=$(mktemp)
		trap 'rm -f "$tmp"' EXIT
		cat "$src" > "$tmp"
		# only the proxy variables: any other would change how dockerd runs, as root
		if grep -qvxE 'HTTPS?_PROXY="[^"\\[:space:][:cntrl:]]+"' "$tmp"; then
			die "error: $src may set HTTP_PROXY and HTTPS_PROXY only"
		fi
		if ! cmp -s "$tmp" "$env" || [ "$(cat "$conf" 2>/dev/null)" != "$unit" ]; then
			# recorded first, so a helper stopped from here on restarts docker next time
			systemctl show -p InvocationID --value docker.service > "$PENDING"
		elif ! restart_pending; then
			rm -f "$PENDING"
			return 0
		fi
		# the environment first, so the drop-in never names a missing file
		install -d -m 755 "$dir"
		install -m 600 "$tmp" "$env.new"
		mv "$env.new" "$env"
		printf '%s\n' "$unit" > "$conf.new"
		chmod 644 "$conf.new"
		mv "$conf.new" "$conf"
	fi
	systemctl daemon-reload
	systemctl restart docker.service
	rm -f "$PENDING"
}

certs() {
	local src=$1 dst=$2
	[[ "$dst" == /* ]] || die "error: the cert dir must be an absolute path"
	install -d -m 755 "$dst"
	local f mode
	for f in rootCA.crt server.crt server.key; do
		[ -f "$src/$f" ] || die "error: $src/$f is missing"
	done
	# each file is renamed into place, so a reader never sees half a file
	for f in rootCA.crt server.crt server.key; do
		mode=644
		[ "$f" != server.key ] || mode=600
		install -m $mode -o root -g root "$src/$f" "$dst/.$f.new"
		mv "$dst/.$f.new" "$dst/$f"
	done
}

case "${1:-}" in
dropin)
	[ $# -eq 3 ] || die "usage: $0 dropin <unit> <file>|--remove"
	dropin "$2" "$3"
	;;
certs)
	[ $# -eq 3 ] || die "usage: $0 certs <dir> <cert dir>"
	certs "$2" "$3"
	;;
docker-proxy)
	[ $# -eq 2 ] || die "usage: $0 docker-proxy <file>|--remove"
	docker_proxy "$2"
	;;
*)
	die "usage: $0 dropin <unit> <file>|--remove | certs <dir> <cert dir> | docker-proxy <file>|--remove"
	;;
esac
