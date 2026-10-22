#!/usr/bin/env bash
#
# While the image has both the ubuntu and the centos user, the watcher runs as
# centos and the config file may be written to either home directory. This
# copies a newer config file from ubuntu to centos, and a newer status file
# back from centos to ubuntu. Run as root by scylla-monitoring-sync.path.

set -euo pipefail

UBUNTU=/home/ubuntu/scylla-monitoring
CENTOS=/home/centos/scylla-monitoring
CONFIG=scylla-monitoring.yaml
STATUS=scylla-monitoring.status.json

# copy <src> <dst> <user>: copy if newer, keeping the timestamp, by a rename.
# Each side is owned by another user, so a symlink in either path is skipped:
# root would follow it to any file.
copy() {
	local src=$1 dst=$2 user=$3
	[ ! -L "$src" ] && [ ! -L "$(dirname "$src")" ] && [ ! -L "$(dirname "$dst")" ] || return 0
	[ -f "$src" ] && [ "$src" -nt "$dst" ] || return 0
	install -p -o "$user" -g "$user" -m 600 "$src" "$dst.new"
	mv "$dst.new" "$dst"
}

if [ -f "$UBUNTU/$CONFIG" ] && [ ! -L "$CENTOS" ]; then
	install -d -o centos -g centos -m 700 "$CENTOS"
	copy "$UBUNTU/$CONFIG" "$CENTOS/$CONFIG" centos
fi
if [ -d "$UBUNTU" ]; then
	copy "$CENTOS/$STATUS" "$UBUNTU/$STATUS" ubuntu
fi
