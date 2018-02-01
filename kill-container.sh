#!/usr/bin/env bash

usage="$(basename "$0") [-h] [ -p container port ] [-n optional name] [-b base name] -- kills existing Docker instances at given ports"

while getopts ':hb:p:n:' option; do
  case "$option" in
    h) echo "$usage"
       exit
       ;;
    p) PORT=$OPTARG
       ;;
    n) NAME=$OPTARG
       ;;
    b) BASE_NAME=$OPTARG
       ;;
    :) printf "missing argument for -%s\n" "$OPTARG" >&2
       echo "$usage" >&2
       exit 1
       ;;
   \?) printf "illegal option: -%s\n" "$OPTARG" >&2
       echo "$usage" >&2
       exit 1
       ;;
  esac
done
if [ -z $NAME ]; then
	if [ -z $PORT ]; then
	    NAME=$BASE_NAME
	else
	    NAME=$BASE_NAME-$PORT
	fi
fi

if [ "$(docker ps -q -f name=$NAME)" ]; then
    docker kill $NAME
fi

if [[ "$(docker ps -aq --filter name=$NAME 2> /dev/null)" != "" ]]; then
    docker rm -v $NAME
fi
