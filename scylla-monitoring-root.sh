#!/usr/bin/env bash
#
# The root-only tasks of scylla_monitoring_config.py, which runs it with
# sudo -n. Installed root-owned, with a sudoers rule that lets the watcher's
# user run this script only.
#
#   scylla-monitoring-root.sh dropin <unit> <file>     install <file> as the unit's drop-in, restart the unit
#   scylla-monitoring-root.sh dropin <unit> --remove   remove the drop-in, restart the unit
#   scylla-monitoring-root.sh certs <dir> <cert dir>   install server.crt, server.key and rootCA.crt
#
# The drop-in is /etc/systemd/system/<unit>.d/50-scylla-monitoring.conf; other
# drop-ins and the unit itself are left alone.

set -euo pipefail

die() { echo "$@" >&2; exit 1; }

# The watcher's own unit and docker would take the watcher down with them.
REFUSED_UNITS="docker.service scylla-monitoring-config.service"

dropin() {
	local unit=$1 src=$2
	[[ "$unit" =~ ^[A-Za-z0-9@._-]+\.(service|socket|timer)$ ]] || die "error: not a unit name: $unit"
	for refused in $REFUSED_UNITS; do
		[ "$unit" != "$refused" ] || die "error: $unit cannot be changed"
	done
	local dir=/etc/systemd/system/$unit.d
	local dst=$dir/50-scylla-monitoring.conf
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
*)
	die "usage: $0 dropin <unit> <file>|--remove | certs <dir> <cert dir>"
	;;
esac
