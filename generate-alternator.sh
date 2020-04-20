#!/usr/bin/env bash
usage="$(basename "$0") [-h] [-v version]"
VERSIONS="master"
while getopts ':hv:' option; do
  case "$option" in
    h) echo "$usage"
       exit
       ;;
    v) VERSIONS=$OPTARG
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


DASHBOARDS="scylla-io scylla-cpu scylla-os scylla-errors alternator" ./generate-dashboards.sh -v $VERSIONS -S alternator
