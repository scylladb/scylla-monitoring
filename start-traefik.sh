#!/usr/bin/env bash
#
# Starts the traefik mTLS reverse proxy in front of the monitoring stack.
# The version comes from TRAEFIK_VERSION in versions.sh, the same value
# fetch_traefik_image.sh bakes into the image, so the proxy that runs is the
# one the image ships.
#
# input (env): PRIVATE_IP  address traefik listens on
#              CERT_DIR    absolute path holding server.crt server.key rootCA.crt
# optional (env): TAG overrides TRAEFIK_VERSION
#                 TRAEFIK_GENERATION, written as a comment in the dynamic config
#
# --reload only rewrites the dynamic config, so the running traefik reads the
# certificates in CERT_DIR again; it needs neither PRIVATE_IP nor CERT_DIR.
# --config-only writes the static and dynamic config and exits; it needs
# PRIVATE_IP only.
# --check checks only that no proxied port is reachable outside loopback; it
# needs PRIVATE_IP only.
#
# Clients must present a certificate signed by rootCA.crt. The readiness probe
# presents server.crt, so that certificate must also allow client auth, and it
# connects to PRIVATE_IP, so the certificate needs PRIVATE_IP as an IP SAN.
#
# Traefik listens on PRIVATE_IP ports 3000 (Grafana), 9090 (Prometheus), 9093
# (Alertmanager), 9100 (node_exporter), 10911 (sidecar) and 10903 (Thanos
# query), and forwards each to 127.0.0.1 on the same port, so those services
# must listen on 127.0.0.1 only
# (start-all.sh -A 127.0.0.1, node_exporter --web.listen-address=127.0.0.1:9100).
# Its ping endpoint is on localhost:8080. Generated config goes to traefik/build:
# static/ holds traefik.yml and confs/ holds traefik-conf.yml; both are mounted
# as directories, with CERT_DIR mounted as /etc/traefik/certs.
# Any existing container named traefik is replaced.

cd "$(dirname "$0")" || exit 1
# shellcheck source=versions.sh
. ./versions.sh
set -euo pipefail

die() { echo "$@" >&2; exit 1; }

# The dynamic config. traefik's file provider reloads it, and the certificates
# with it, whenever it changes; the generation comment makes each rewrite a
# change, which is how --reload makes traefik read new certificates.
write_dynamic_conf() {
	cat > "$1" <<EOF
# generation: ${TRAEFIK_GENERATION:-}
http:
  routers:
    to-agraf:
      tls: true
      entryPoints:
        - agraf
      rule: "PathPrefix(\`/\`)"
      service: "agraf"
    to-aprom:
      tls: true
      entryPoints:
        - aprom
      rule: "PathPrefix(\`/\`)"
      service: "aprom"
    to-aalert:
      tls: true
      entryPoints:
        - aalert
      rule: "PathPrefix(\`/\`)"
      service: "aalert"
    to-node-exporter:
      tls: true
      entryPoints:
        - node-exporter
      rule: "PathPrefix(\`/\`)"
      service: "node-exporter"
    to-sidecar1:
      tls: true
      entryPoints:
        - sidecar1
      rule: "PathPrefix(\`/\`)"
      service: "sidecar1"
    to-thanos-query:
      tls: true
      entryPoints:
        - thanos-query
      rule: "PathPrefix(\`/\`)"
      service: "thanos-query"
  services:
    agraf:
      loadBalancer:
        servers:
          - url: "http://127.0.0.1:3000"
    aprom:
      loadBalancer:
        servers:
          - url: "http://127.0.0.1:9090"
    aalert:
      loadBalancer:
        servers:
          - url: "http://127.0.0.1:9093"
    node-exporter:
      loadBalancer:
        servers:
          - url: "http://127.0.0.1:9100"
    sidecar1:
      loadBalancer:
        servers:
          - url: "h2c://127.0.0.1:10911"
    thanos-query:
      loadBalancer:
        servers:
          - url: "h2c://127.0.0.1:10903"
tls:
  options:
    default:
      minVersion: VersionTLS12
      clientAuth:
        caFiles:
          - /etc/traefik/certs/rootCA.crt
        clientAuthType: RequireAndVerifyClientCert
  stores:
    default:
      defaultCertificate:
        certFile: /etc/traefik/certs/server.crt
        keyFile: /etc/traefik/certs/server.key
EOF
}

# The static config: the entry points on ADDR and the file provider.
write_static_conf() {
	cat > "$1" <<EOF
global:
  checkNewVersion: false
  sendAnonymousUsage: false
# log process events to stdout
log:
  filePath: ""
  level: INFO
# log traffic to stdout
accessLog:
  filePath: ""
entryPoints:
  agraf:
    address: "${ADDR}:3000"
  aprom:
    address: "${ADDR}:9090"
  aalert:
    address: "${ADDR}:9093"
  node-exporter:
    address: "${ADDR}:9100"
  sidecar1:
    address: "${ADDR}:10911"
  thanos-query:
    address: "${ADDR}:10903"
  ping:
    address: "localhost:8080"
providers:
  file:
    directory: "/etc/traefik/confs"

ping:
  entryPoint: "ping"
EOF
}

CONF_DIR="$PWD/traefik/build"
STATIC_DIR="$CONF_DIR/static"
CONFS_DIR="$CONF_DIR/confs"
if [ "${1:-}" = "--reload" ]; then
	# traefik skips a config that did not change, so the comment must change
	# for it to read the new certificates
	TRAEFIK_GENERATION="${TRAEFIK_GENERATION:-$(date +%s.%N)}"
	mkdir -p "$CONFS_DIR"
	write_dynamic_conf "$CONFS_DIR/traefik-conf.yml.new"
	mv "$CONFS_DIR/traefik-conf.yml.new" "$CONFS_DIR/traefik-conf.yml"
	exit 0
fi

: "${PRIVATE_IP:?is required}"
ADDR="$PRIVATE_IP"
if [[ "$ADDR" == *:* ]]; then ADDR="[$ADDR]"; fi

# Any listener on a proxied port outside loopback bypasses mTLS, or takes the
# address traefik needs. Published docker ports are checked too, because with
# userland-proxy disabled they have no socket for ss to see. Both are captured
# first so a failing ss or docker ps stops the script instead of passing it.
check_exposed() {
	local OWN listeners published restarting exposed
	local PORTS='3000|9090|9093|9100|10911|10903'
	OWN=""
	# A crash-looping traefik also reports Running while in restart backoff.
	if [[ "$(docker inspect --format '{{and .State.Running (not .State.Restarting)}}' traefik 2>/dev/null)" == true ]]; then
		OWN="$ADDR"
	fi
	listeners=$(ss -ltn)
	published=$(docker ps --format '{{.Ports}}')
	# A container in restart backoff lists no ports, yet gets them back on restart.
	restarting=$(docker ps --quiet --filter status=restarting)
	if [[ -n "$restarting" ]]; then
		# shellcheck disable=SC2086
		published+=$'\n'$(docker inspect --format '{{range $p, $b := .HostConfig.PortBindings}}{{range $b}}{{.HostIp}}:{{.HostPort}}->{{$p}},{{end}}{{end}}' $restarting)
	fi
	exposed=$(
		{
			awk 'NR > 1 {print "ss", $4}' <<<"$listeners"
			tr ',' '\n' <<<"$published" | sed -nE 's/^ *(.+)->.*/docker \1/p'
		} | awk -v own="$OWN" -v ports="$PORTS" '
			BEGIN { n = split(ports, p, "|") }
			{
				i = match($2, /:[0-9]+(-[0-9]+)?$/)
				if (!i) next
				host = substr($2, 1, i - 1)
				if (host ~ /^(127\.|\[::1\]$|::1$|\[?::ffff:127\.)/) next
				# only a socket can be traefik itself; a published port on it is DNAT
				if ($1 == "ss" && (host == own || "[" host "]" == own)) next
				lo = hi = substr($2, i + 1)
				if (lo ~ /-/) { split(lo, r, "-"); lo = r[1]; hi = r[2] }
				for (k = 1; k <= n; k++) if (p[k] + 0 >= lo + 0 && p[k] + 0 <= hi + 0) { print $2; next }
			}' | sort -u
	)
	[[ -z "$exposed" ]] || die "error: listening outside loopback, move to 127.0.0.1 first: ${exposed//$'\n'/ }"
}

# --check runs only the check above; make_compose.py --compose runs it after
# the rest of the stack is up, before it starts traefik.
if [ "${1:-}" = "--check" ]; then
	check_exposed
	exit 0
fi

# --config-only writes both configs and exits; docker compose runs traefik
# from them (make_compose.py --traefik).
if [ "${1:-}" = "--config-only" ]; then
	mkdir -p "$STATIC_DIR/confs" "$STATIC_DIR/certs" "$CONFS_DIR"
	write_static_conf "$STATIC_DIR/traefik.yml.new"
	write_dynamic_conf "$CONFS_DIR/traefik-conf.yml.new"
	mv "$STATIC_DIR/traefik.yml.new" "$STATIC_DIR/traefik.yml"
	mv "$CONFS_DIR/traefik-conf.yml.new" "$CONFS_DIR/traefik-conf.yml"
	exit 0
fi

: "${CERT_DIR:?is required}"
ip -o addr show scope global | awk -v ip="$PRIVATE_IP" '{sub(/\/.*/, "", $4)} $4 == ip {found = 1} END {exit !found}' ||
	die "error: PRIVATE_IP must be a global address on this host, as \`ip addr\` prints it"
[[ "$CERT_DIR" == /* && "$CERT_DIR" != *:* ]] || die "error: CERT_DIR must be an absolute path without ':'"

# The key is usually root-only; the readiness probe reads it with sudo. Without
# a terminal and without passwordless sudo (a service), the probe uses
# traefik's ping endpoint instead.
NEED_SUDO=0
for f in server.crt server.key rootCA.crt; do
	[[ -r "$CERT_DIR/$f" ]] || NEED_SUDO=1
done
PING_PROBE=0
if ((NEED_SUDO)) && [[ ! -t 0 ]] && ! sudo -n true 2>/dev/null; then
	PING_PROBE=1
fi
as_root() { if ((NEED_SUDO && !PING_PROBE)); then sudo "$@"; else "$@"; fi; }
as_root test -f "$CERT_DIR/server.crt" -a -f "$CERT_DIR/server.key" -a -f "$CERT_DIR/rootCA.crt" ||
	die "error: CERT_DIR must hold server.crt server.key rootCA.crt"
# CERT_DIR is mounted whole, so a symlink out of it does not resolve in the
# container
CERT_REAL=$(as_root readlink -f "$CERT_DIR")
for f in server.crt server.key rootCA.crt; do
	[[ "$(as_root readlink -f "$CERT_DIR/$f")" == "$CERT_REAL/"* ]] ||
		die "error: CERT_DIR/$f links out of CERT_DIR; copy the file into it"
done

check_exposed

export TAG="${TAG:-$TRAEFIK_VERSION}"
IMG="traefik:${TAG}"
# Whatever can fail runs before the old proxy is removed. The config is
# rendered to .new files and renamed into place only after that, so a failed
# write leaves the running proxy and the config it watches untouched.
if ! docker image inspect "$IMG" >/dev/null 2>&1; then
	./fetch_traefik_image.sh || die "failed: could not pull $IMG from any registry"
fi
# confs/ and certs/ are the mount points of the nested mounts; docker cannot
# create them inside the read-only static mount.
mkdir -p "$STATIC_DIR/confs" "$STATIC_DIR/certs" "$CONFS_DIR"

# json-file, docker's default driver, never rotates; the access log would
# grow until the disk is full.
driver=$(docker info --format '{{.LoggingDriver}}')
LOG_OPTS=(--log-opt mode=non-blocking)
if [[ "$driver" == json-file ]]; then
	LOG_OPTS+=(--log-opt max-size=50m --log-opt max-file=3)
fi

write_static_conf "$STATIC_DIR/traefik.yml.new"

write_dynamic_conf "$CONFS_DIR/traefik-conf.yml.new"

docker rm --force traefik || true
mv "$STATIC_DIR/traefik.yml.new" "$STATIC_DIR/traefik.yml"
mv "$CONFS_DIR/traefik-conf.yml.new" "$CONFS_DIR/traefik-conf.yml"

# DAC_READ_SEARCH is the one capability kept, so traefik can read a key owned
# by another user without being able to write it; with host networking the
# default set would also allow NET_RAW.
docker run -d --name traefik \
	--network="host" \
	--restart unless-stopped \
	--cap-drop ALL --cap-add DAC_READ_SEARCH \
	--security-opt no-new-privileges \
	"${LOG_OPTS[@]}" \
	-v "$STATIC_DIR:/etc/traefik:ro,z" \
	-v "$CONFS_DIR:/etc/traefik/confs:ro,z" \
	-v "${CERT_DIR}:/etc/traefik/certs:ro" \
	"$IMG"

# A bare `docker run -d` returns as soon as the container is created, before
# traefik has opened its listeners and loaded the file-provider routers. During
# that window requests are refused (000) or answered with 404 (no router yet).
# Wait until traefik actually routes a request. The probe asks for / because
# Prometheus answers it with a redirect under any route prefix, so a 404 can only
# come from traefik. Any other status (302/502/503/...) means traefik is ready,
# even if the target service is still down.
probe() {
	if ((PING_PROBE)); then
		curl --noproxy '*' --output /dev/null --connect-timeout 5 --max-time 10 "$@" "http://localhost:8080/ping"
		return
	fi
	as_root curl --noproxy '*' --globoff \
		--cacert "${CERT_DIR}/rootCA.crt" \
		--cert "${CERT_DIR}/server.crt" --key "${CERT_DIR}/server.key" \
		--output /dev/null --connect-timeout 5 --max-time 10 \
		"$@" "https://${ADDR}:9090/"
}

wait_for_traefik_ready() {
	local deadline=$((SECONDS + 60))
	local code=""
	while ((SECONDS < deadline)); do
		code=$(probe --silent --write-out '%{http_code}' 2>/dev/null || true)
		case "$code" in
		404) ;; # routers not loaded yet; keep waiting
		[1-5][0-9][0-9]) return 0 ;;
		esac
		sleep 2
	done
	docker logs --tail 20 traefik >&2 || true
	probe --silent --show-error >&2 || true
	die "error: traefik did not become ready in time (last status: ${code:-none})"
}

wait_for_traefik_ready
