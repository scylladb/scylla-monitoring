# Helpers shared by the start scripts for working out how the containers of the
# monitoring stack address each other. Sourced, not executed.

# Prints the network named by --net/--network in $DOCKER_PARAM, empty when there
# is none. Both the --net=name and the "--net name" spellings are recognised.
# Reads $DOCKER_PARAM, so call it once the -D parameters are parsed.
network_param() {
	echo "$DOCKER_PARAM" | awk '{for (i = 1; i <= NF; i++) { if ($i ~ /^--(net|network)=/) { sub(/^--(net|network)=/, "", $i); n = $i } else if ($i ~ /^--(net|network)$/ && i < NF) { n = $(i + 1) } }} END {print n}'
}

# Prints the Docker network the containers are attached to, and returns non-zero
# when that network does not resolve container names. Only a user-defined network
# has an embedded DNS that does; host, bridge, none and container networking do
# not, and neither does having no --net at all.
stack_network() {
	local net
	net=$(network_param)
	case "$net" in
	"" | host | bridge | none | container:*)
		return 1
		;;
	esac
	echo "$net"
}

# Prints the address a container holds on the network the stack was told to use,
# falling back to its address on any network. Empty when it has none.
first_container_address() {
	local name=$1
	local net
	local ip

	# Ask for that network by name, because a container attached to more than one
	# has an address on each and only this one is any use to its peers. Templates
	# walk a map in sorted key order, so picking the first would otherwise mean
	# picking whichever network sorts first.
	net=$(network_param)
	case "$net" in
	"" | host | none | container:*) ;;
	*)
		ip=$(docker inspect --format "{{with index .NetworkSettings.Networks \"$net\"}}{{.IPAddress}}{{end}}" "$name" 2>/dev/null)
		;;
	esac
	if [ -z "$ip" ] || [ "$ip" = "invalid IP" ]; then
		# One address per line, so that a container attached to more than one
		# network does not come back as several addresses concatenated into one
		# invalid string. Docker reports "invalid IP" for a network the container
		# has no address on.
		ip=$(docker inspect --format '{{range .NetworkSettings.Networks}}{{println .IPAddress}}{{end}}' "$name" 2>/dev/null |
			grep -v '^invalid IP$' | grep -m1 '[^[:space:]]')
	fi
	echo "$ip"
}

# The network the stack creates when -D names none, so that the containers
# resolve each other by name.
# Usage: default_network [stack id]
default_network() {
	echo "monitor-net$1"
}

# Resolve the address of a Docker container.
# Usage: container_address <container_name> <container_port> [host_port]
# Prints <ip>:<container_port>, the address the container is reachable at from
# inside the Docker network. Falls back to BIND_ADDRESS or the host IP when the
# container has no address of its own, and then uses host_port, because that is
# the port the container is published on. host_port defaults to container_port.
container_address() {
	local name=$1
	local port=$2
	local host_port=${3:-$2}
	local ip
	ip=$(first_container_address "$name")
	if [ -z "$ip" ]; then
		if [ ! -z "$BIND_ADDRESS" ]; then
			ip=$(echo $BIND_ADDRESS | sed 's/:$//')
		elif [[ $(uname) == "Linux" ]]; then
			ip=$(hostname -I | awk '{print $1}')
		elif [[ $(uname) == "Darwin" ]]; then
			ip=$(ifconfig en0 | awk '/inet / {print $2}')
		fi
		port=$host_port
	fi
	echo "$ip:$port"
}

# Resolve the address of a monitoring container, as seen by the other containers
# of the stack.
# Usage: service_address <container_name> <container_port> [host_port]
# On a user-defined network Docker's embedded DNS resolves container names. A name
# stays correct when Docker gives the container a different address, which it does
# whenever the containers are recreated or the host reboots, so prefer it there.
# This covers the network the script creates and one the caller passed in -D
# alike. Falls back to container_address when the network resolves no names, as
# with host networking, which has no container address either.
service_address() {
	local name=$1
	local port=$2
	local host_port=${3:-$2}

	if stack_network >/dev/null; then
		echo "$name:$port"
		return
	fi
	container_address "$name" "$port" "$host_port"
}

# The address the other containers reach Alertmanager at.
# Usage: alertmanager_address <port given to start-alertmanager.sh -p, or empty> <host port>
# start-alertmanager.sh names the container after its -p: aalert-<port>, or
# aalert without one.
alertmanager_address() {
	local port_arg=$1
	local host_port=$2
	local name=aalert

	if [ -n "$port_arg" ]; then
		name=aalert-$port_arg
		host_port=$port_arg
	fi
	service_address "$name" 9093 "$host_port"
}

# The name of the Grafana container, the way start-grafana.sh names it: a
# GRAFANA_NAME from env.sh wins over the port, and otherwise the name follows a
# port having been given at all rather than its value, so -g 3000 names the
# container agraf-3000.
# Usage: grafana_container_name <port given to start-grafana.sh -g, or empty>
grafana_container_name() {
	if [ -n "$GRAFANA_NAME" ]; then
		echo "$GRAFANA_NAME"
	elif [ -z "$1" ]; then
		echo agraf
	else
		echo "agraf-$1"
	fi
}
