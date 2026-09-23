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
#
# Clients must present a certificate signed by rootCA.crt. The readiness probe
# presents server.crt, so that certificate must also allow client auth.
#
# Traefik listens on PRIVATE_IP ports 3000 (Grafana), 9090 (Prometheus), 9093
# (Alertmanager), 9100 (node_exporter) and 10911 (sidecar), and forwards each to
# 127.0.0.1 on the same port, so those services must listen on 127.0.0.1 only
# (start-all.sh -A 127.0.0.1, node_exporter --web.listen-address=127.0.0.1:9100).
# Its ping endpoint is on localhost:8080. Generated config goes to traefik/build.
# Any existing container named traefik is replaced.

cd "$(dirname "$0")" || exit 1
# shellcheck source=versions.sh
. ./versions.sh
set -euo pipefail

die() { echo "$@" >&2; exit 1; }

: "${PRIVATE_IP:?is required}" "${CERT_DIR:?is required}"
[[ "$PRIVATE_IP" =~ ^[0-9a-fA-F.:]+$ ]] || die "error: PRIVATE_IP must be an IP address"
[[ "$CERT_DIR" == /* && "$CERT_DIR" != *:* ]] || die "error: CERT_DIR must be an absolute path without ':'"

ADDR="$PRIVATE_IP"
if [[ "$ADDR" == *:* ]]; then ADDR="[$ADDR]"; fi

# The key is usually root-only; use sudo only when it is needed to read it.
NEED_SUDO=0
for f in server.crt server.key rootCA.crt; do
	[[ -r "$CERT_DIR/$f" ]] || NEED_SUDO=1
done
as_root() { if ((NEED_SUDO)); then sudo "$@"; else "$@"; fi; }
as_root test -f "$CERT_DIR/server.crt" -a -f "$CERT_DIR/server.key" -a -f "$CERT_DIR/rootCA.crt" ||
	die "error: CERT_DIR must hold server.crt server.key rootCA.crt"

busy=$(ss -Hltn | awk '$4 ~ /^(0\.0\.0\.0|\*|\[::\]):(3000|9090|9093|9100|10911)$/ {print $4}')
[[ -z "$busy" ]] || die "error: bound on all addresses, move to 127.0.0.1 first: ${busy//$'\n'/ }"

export TAG="${TAG:-$TRAEFIK_VERSION}"
IMG="traefik:${TAG}"
CONF_DIR="$PWD/traefik/build"
mkdir -p "$CONF_DIR"

cat > "$CONF_DIR/traefik.yml" <<EOF
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
  ping:
    address: "localhost:8080"
providers:
  file:
    directory: "/etc/traefik/confs"

# Uncomment to access the traefik dashboard at :8080
#api:
#  insecure: true

# enable healthcheck endpoint
ping:
  entryPoint: "ping"
EOF

cat > "$CONF_DIR/traefik-conf.yml" <<EOF
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
tls:
  options:
    default:
      minVersion: VersionTLS12
      clientAuth:
        caFiles:
          - /etc/traefik/rootCA.crt
        clientAuthType: RequireAndVerifyClientCert
  stores:
    default:
      defaultCertificate:
        certFile: /etc/traefik/server.crt
        keyFile: /etc/traefik/server.key
EOF

if ! docker image inspect "$IMG" >/dev/null 2>&1; then
	./fetch_traefik_image.sh || die "failed: could not pull $IMG from any registry"
fi

# json-file, docker's default driver, never rotates; the access log would
# grow until the disk is full.
LOG_OPTS=(--log-opt mode=non-blocking)
if [[ "$(docker info --format '{{.LoggingDriver}}')" == json-file ]]; then
	LOG_OPTS+=(--log-opt max-size=50m --log-opt max-file=3)
fi

docker rm --force traefik || true

# DAC_OVERRIDE is the one capability kept, so traefik can read a key owned by
# another user; with host networking the default set would also allow NET_RAW.
docker run -d --name traefik \
	--network="host" \
	--restart unless-stopped \
	--cap-drop ALL --cap-add DAC_OVERRIDE \
	--security-opt no-new-privileges \
	"${LOG_OPTS[@]}" \
	-v "$CONF_DIR/traefik.yml:/etc/traefik/traefik.yml:ro" \
	-v "$CONF_DIR/traefik-conf.yml:/etc/traefik/confs/traefik-conf.yml:ro" \
	-v "${CERT_DIR}/server.crt:/etc/traefik/server.crt:ro" \
	-v "${CERT_DIR}/server.key:/etc/traefik/server.key:ro" \
	-v "${CERT_DIR}/rootCA.crt:/etc/traefik/rootCA.crt:ro" \
	"$IMG"

# A bare `docker run -d` returns as soon as the container is created, before
# traefik has opened its listeners and loaded the file-provider routers. During
# that window requests are refused (000) or answered with 404 (no router yet).
# Wait until traefik actually routes a request. We classify by HTTP status code:
# any routed response (200/502/503/...) means traefik is ready, even if the
# target service is still down.
probe() {
	as_root curl --noproxy '*' --globoff \
		--cacert "${CERT_DIR}/rootCA.crt" \
		--cert "${CERT_DIR}/server.crt" --key "${CERT_DIR}/server.key" \
		--output /dev/null --connect-timeout 5 --max-time 10 \
		"$@" "https://${ADDR}:9090/-/healthy"
}

wait_for_traefik_ready() {
	local deadline=$((SECONDS + 60))
	local code=""
	while ((SECONDS < deadline)); do
		code=$(probe --silent --write-out '%{http_code}' 2>/dev/null || true)
		case "$code" in
		404) ;; # routers not loaded yet; keep waiting
		[1-5][0-9][0-9]) return 0 ;; # any routed response means traefik is ready
		esac
		# anything else (000, or empty when sudo/curl did not run): keep waiting
		sleep 2
	done
	docker logs --tail 20 traefik >&2 || true
	probe --silent --show-error >&2 || true
	die "error: traefik did not become ready in time (last status: ${code:-none})"
}

wait_for_traefik_ready
