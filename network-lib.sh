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
