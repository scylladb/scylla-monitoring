#!/usr/bin/env bash
#
# Pre-install the Vector and vmagent binaries, so Scylla Cloud does not have
# to upload them to a machine started from this image. It skips the upload
# only when the binary is at the expected path, at the exact expected version,
# and the binary and every directory above it are owned by root and not group
# or world writable. It installs everything else itself (users, config,
# /etc/vector, systemd units), so this installs the binaries and nothing more:
# a file in /etc/vector makes its install fail.
#
# Any failure (download, checksum, a check at the end) exits non-zero, which
# fails the image build.

set -euo pipefail

VECTOR_VERSION=0.58.0
VMAGENT_VERSION=v1.151.0

VECTOR_DIR=/opt/vector
VECTOR_BIN=$VECTOR_DIR/bin/vector
VMUTILS_DIR=/opt/vmutils
VMAGENT_BIN=$VMUTILS_DIR/vmagent-prod

print_usage() {
	echo "obs_agents_install.sh [--arch amd64/arm64]"
	exit 1
}

fail() {
	echo "obs_agents_install.sh: $*" >&2
	exit 1
}

ARCH="amd64"
while [ $# -gt 0 ]; do
	case "$1" in
	"--arch")
		[ $# -ge 2 ] || print_usage
		ARCH="$2"
		shift 2
		;;
	*)
		print_usage
		;;
	esac
done

case "$ARCH" in
"amd64")
	VECTOR_TARGET=x86_64-unknown-linux-gnu
	VECTOR_SHA256=a4634bea859a7ad7064ff3dd6f6ad7eb0e8dd4493cc41657d84da8dd66f09d09
	VMUTILS_SHA256=1813b8c8f5c609b56ee01243e1c1213b302be9bbd1243e51fd67a06cb83e53d6
	;;
"arm64")
	VECTOR_TARGET=aarch64-unknown-linux-gnu
	VECTOR_SHA256=06d9f9768feb0cb5c7cdfc12e0b737b22f1220967f5455f391a395361b5799e5
	VMUTILS_SHA256=5fdfe95bbd09cc4f0884feda725fda25f39aede9deef8cddb11070ecea494206
	;;
*)
	print_usage
	;;
esac
VECTOR_URL=https://packages.timber.io/vector/$VECTOR_VERSION/vector-$VECTOR_VERSION-$VECTOR_TARGET.tar.gz
VMUTILS_URL=https://github.com/VictoriaMetrics/VictoriaMetrics/releases/download/$VMAGENT_VERSION/vmutils-linux-$ARCH-$VMAGENT_VERSION.tar.gz

[ "$(id -u)" = 0 ] || fail "Requires root permission."

TMP=$(mktemp -d /var/tmp/obs-agents-XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# download <url> <sha256> <dest>
download() {
	# --speed-*: give up on a transfer that stalls after connecting
	curl -fsSL --retry 5 --retry-connrefused --connect-timeout 30 --speed-limit 1024 --speed-time 60 -o "$3" "$1"
	echo "$2  $3" | sha256sum -c - || fail "sha256 mismatch for $1: expected $2"
}

download "$VECTOR_URL" "$VECTOR_SHA256" "$TMP/vector.tar.gz"
download "$VMUTILS_URL" "$VMUTILS_SHA256" "$TMP/vmutils.tar.gz"

# The archive holds ./vector-<target>/bin/vector: strip two components to get
# /opt/vector/bin/vector. tar run as root would keep the owner stored in the
# archive (vmutils stores a non-root one); --no-same-owner, chown and chmod
# make both trees root owned and not group or world writable whatever the
# archive or the umask hold.
rm -rf "$VECTOR_DIR"
install -d -o root -g root -m 755 "$VECTOR_DIR"
tar -xzf "$TMP/vector.tar.gz" -C "$VECTOR_DIR" --strip-components=2 --no-same-owner
chown -R root:root "$VECTOR_DIR"
chmod -R go-w "$VECTOR_DIR"

# Only vmagent is needed from vmutils
tar -xzf "$TMP/vmutils.tar.gz" -C "$TMP" --no-same-owner vmagent-prod
rm -rf "$VMUTILS_DIR"
install -d -o root -g root -m 755 "$VMUTILS_DIR"
install -o root -g root -m 755 "$TMP/vmagent-prod" "$VMAGENT_BIN"

# The check Scylla Cloud runs on the machine, as root
trusted() { p=$(readlink -f "$1") && while [ "$p" != / ]; do [ "$(stat -c %u "$p")" = 0 ] && [ $((0$(stat -c %a "$p") & 022)) = 0 ] || return 1; p=$(dirname "$p"); done; }

out=$("$VECTOR_BIN" --version 2>&1) || fail "$VECTOR_BIN --version failed: $out"
[[ $out == "vector $VECTOR_VERSION "* ]] || fail "$VECTOR_BIN --version: expected vector $VECTOR_VERSION, got $out"
echo "$out"
out=$("$VMAGENT_BIN" -version 2>&1) || fail "$VMAGENT_BIN -version failed: $out"
[[ $out == *"$VMAGENT_VERSION"* ]] || fail "$VMAGENT_BIN -version: expected $VMAGENT_VERSION, got $out"
echo "$out"
for path in "$VECTOR_BIN" "$VMAGENT_BIN"; do
	trusted "$path" || fail "$path or a directory above it is not owned by root or is group/world writable"
done
if [ -e /etc/vector ] || [ -L /etc/vector ]; then
	fail "/etc/vector exists; Scylla Cloud creates it and fails when it holds other files"
fi

echo "Vector $VECTOR_VERSION and vmagent $VMAGENT_VERSION successfully installed"
