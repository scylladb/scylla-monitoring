#!/usr/bin/env bash

. versions.sh
. network-lib.sh
if [ -f env.sh ]; then
	. env.sh
fi

ALLOY_CONFIG=$PWD/loki/alloy/config.alloy
DOCKER_PARAM=""
BIND_ADDRESS=""
usage="$(basename "$0") [-h] [-l] [--loki-address ip:port] [--alloy-port port] [--alloy-syslog-port port] [-A bind-to-ip-address] [-D encapsulate docker param] -- starts Grafana Alloy, sending syslog to Loki

  --loki-address ip:port    - Where to push the logs, env: ALLOY_LOKI_ADDRESS, default: the loki container.
  --alloy-port port         - Alloy's http port, env: ALLOY_PORT, default: 12345.
  --alloy-syslog-port port  - The port Alloy listens for syslog on, env: ALLOY_SYSLOG_PORT, default: 1514."
LIMITS=""
VOLUMES=""
PARAMS=""
for arg; do
	shift
	if [ -z "$LIMIT" ]; then
		case $arg in
		--limit)
			LIMIT="1"
			;;
		--quick-startup)
			QUICK_STARTUP=1
			;;
		--volume)
			LIMIT="1"
			VOLUME="1"
			;;
		--param)
			LIMIT="1"
			PARAM="1"
			;;
		--loki-address)
			LIMIT="1"
			PARAM="loki-address"
			;;
		--alloy-port)
			LIMIT="1"
			PARAM="alloy-port"
			;;
		--alloy-syslog-port)
			LIMIT="1"
			PARAM="alloy-syslog-port"
			;;
		*)
			set -- "$@" "$arg"
			;;
		esac
	else
		DOCR=$(echo $arg | cut -d',' -f1)
		VALUE=$(echo $arg | cut -d',' -f2- | sed 's/#/ /g')
		NOSPACE=$(echo $arg | sed 's/ /#/g')
		if [ "$PARAM" = "loki-address" ]; then
			ALLOY_LOKI_ADDRESS=$arg
			unset PARAM
		elif [ "$PARAM" = "alloy-port" ]; then
			ALLOY_PORT=$arg
			unset PARAM
		elif [ "$PARAM" = "alloy-syslog-port" ]; then
			ALLOY_SYSLOG_PORT=$arg
			unset PARAM
		elif [ "$PARAM" = "1" ]; then
			if [ -z "${DOCKER_PARAMS[$DOCR]}" ]; then
				DOCKER_PARAMS[$DOCR]=""
			fi
			DOCKER_PARAMS[$DOCR]="${DOCKER_PARAMS[$DOCR]} $VALUE"
			PARAMS="$PARAMS --param $NOSPACE"
			unset PARAM
		else
			if [ -z "${DOCKER_LIMITS[$DOCR]}" ]; then
				DOCKER_LIMITS[$DOCR]=""
			fi
			if [ "$VOLUME" = "1" ]; then
				SRC=$(echo $VALUE | cut -d':' -f1)
				DST=$(echo $VALUE | cut -d':' -f2-)
				SRC=$(readlink -m $SRC)
				DOCKER_LIMITS[$DOCR]="${DOCKER_LIMITS[$DOCR]} -v $SRC:$DST"
				VOLUMES="$VOLUMES --volume $NOSPACE"
				unset VOLUME
			else
				DOCKER_LIMITS[$DOCR]="${DOCKER_LIMITS[$DOCR]} $VALUE"
				LIMITS="$LIMITS --limit $NOSPACE"
			fi
		fi
		unset LIMIT
	fi
done
if [ "$DOCKER_PARAM" != "" ]; then
	DOCKER_PARAM_FROM_FILE="1"
fi

while getopts ':hlD:A:' option; do
	case "$option" in
	h)
		echo "$usage"
		exit
		;;
	l)
		if [[ ! $DOCKER_PARAM =~ (^|[[:space:]])--(net|network)(=|[[:space:]])host($|[[:space:]]) ]]; then
			DOCKER_PARAM="$DOCKER_PARAM --net=host"
		fi
		;;
	D)
		if [ "$DOCKER_PARAM_FROM_FILE" = "1" ]; then
			DOCKER_PARAM=""
			DOCKER_PARAM_FROM_FILE=""
		fi
		DOCKER_PARAM="$DOCKER_PARAM $OPTARG"
		;;
	A)
		BIND_ADDRESS="$OPTARG:"
		;;
	:)
		printf "missing argument for -%s\n" "$OPTARG" >&2
		echo "$usage" >&2
		exit 1
		;;
	\?)
		printf "illegal option: -%s\n" "$OPTARG" >&2
		echo "$usage" >&2
		exit 1
		;;
	esac
done

if [ -z "$ALLOY_LOKI_ADDRESS" ]; then
	# Without --loki-address, look for the loki container start-loki.sh starts by default.
	if stack_network >/dev/null; then
		ALLOY_LOKI_ADDRESS="loki:3100"
	elif [ "$(network_param)" = "host" ]; then
		# Both containers share the host's network, Loki has no address of its own.
		ALLOY_LOKI_ADDRESS="127.0.0.1:3100"
	else
		ALLOY_LOKI_ADDRESS="$(first_container_address loki):3100"
	fi
fi
if [ "$ALLOY_LOKI_ADDRESS" = ":3100" ]; then
	echo "Error: could not find Loki, use --loki-address to set its address"
	exit 1
fi

if [ -z $ALLOY_PORT ]; then
	ALLOY_PORT=12345
	ALLOY_NAME=alloy
else
	ALLOY_NAME=alloy-$ALLOY_PORT
fi
if [ -z $ALLOY_SYSLOG_PORT ]; then
	ALLOY_SYSLOG_PORT=1514
fi

docker container inspect $ALLOY_NAME >/dev/null 2>&1
if [ $? -eq 0 ]; then
	printf "\nSome of the monitoring docker instances ($ALLOY_NAME) exist. Make sure all containers are killed and removed. You can use kill-all.sh for that\n"
	exit 1
fi

# Alloy listens on the same ports inside the container as outside, so the ports
# hold with host networking too, where there is no port mapping.
if [[ ! $DOCKER_PARAM =~ (^|[[:space:]])--(net|network)(=|[[:space:]])host($|[[:space:]]) ]]; then
	PORT_MAPPING="-p $BIND_ADDRESS$ALLOY_PORT:$ALLOY_PORT -p $BIND_ADDRESS$ALLOY_SYSLOG_PORT:$ALLOY_SYSLOG_PORT"
fi

sed -e "s/LOKI_IP/$ALLOY_LOKI_ADDRESS/" -e "s/0.0.0.0:1514/0.0.0.0:$ALLOY_SYSLOG_PORT/" loki/alloy/config.template.alloy >$ALLOY_CONFIG

docker run ${DOCKER_LIMITS["alloy"]} -d $DOCKER_PARAM -i $PORT_MAPPING \
	-v $ALLOY_CONFIG:/etc/alloy/config.alloy:z \
	--name $ALLOY_NAME docker.io/grafana/alloy:$ALLOY_VERSION \
	run --server.http.listen-addr=0.0.0.0:$ALLOY_PORT --storage.path=/var/lib/alloy/data /etc/alloy/config.alloy ${DOCKER_PARAMS["alloy"]}

if [ $? -ne 0 ]; then
	echo "Error: Alloy container failed to start"
	echo "For more information use: docker logs $ALLOY_NAME"
	exit 1
fi

# Wait till Alloy is available
TRIES=0
RETRIES=25
if [ ! "$QUICK_STARTUP" = "1" ]; then
	until $(curl --output /dev/null -f --silent http://localhost:$ALLOY_PORT/-/ready) || [ $TRIES -eq $RETRIES ]; do
		((TRIES = TRIES + 1))
		sleep 1
	done
fi

if [ ! "$(docker ps -q -f name=$ALLOY_NAME)" ]; then
	echo "Error: Alloy container failed to start"
	echo "For more information use: docker logs $ALLOY_NAME"
	exit 1
fi
