#!/usr/bin/env bash

CURRENT_VERSION="master"
if [ -f CURRENT_VERSION.sh ]; then
	CURRENT_VERSION=$(cat CURRENT_VERSION.sh)
fi

. versions.sh
VERSION_FOR_DEFAULTS=$CURRENT_VERSION
BRANCH_VERSION=$(echo $CURRENT_VERSION | cut -d'.' -f1,2)
if [ -z ${DEFAULT_VERSION[$CURRENT_VERSION]} ]; then
	VERSION_FOR_DEFAULTS=$BRANCH_VERSION
fi
MANAGER_VERSION=${MANAGER_DEFAULT_VERSION[$VERSION_FOR_DEFAULTS]}
VECTOR_VERSION=${VECTOR_DEFAULT_VERSION[$VERSION_FOR_DEFAULTS]}
echo "making vector $VECTOR_VERSION $VERSION_FOR_DEFAULTS"
if [ "$1" = "-e" ]; then
	DEFAULT_VERSION=${DEFAULT_ENTERPRISE_VERSION[$VERSION_FOR_DEFAULTS]}
fi

. dashboards.sh

FORMAT_COMAND=""
FORCEUPDATE=""
SPECIFIC_SOLUTION=""
PRODUCTS=()
if [ -f env.sh ]; then
	. env.sh
fi

for arg; do
    shift
        case $arg in
        --support-dashboard)
            SUPPORT_DASHBOARD="1"
            ;;
        --clear)
            CLEAR_DASHBOARD="1"
            ;;
        --vector-store)
            VECTOR_STORE="1"
            ;;
        *)
            set -- "$@" "$arg"
            ;;
        esac
done
usage="$(basename "$0") [-h] [-v comma separated versions ]  [-D] [-j additional dashboard to load to Grafana, multiple params are supported] [-M scylla-manager version ] [-t] [-F force update] [-S start with a system specific dashboard set] -- Generates the grafana dashboards and their load files"
BASE_DASHBOARD_DIR="grafana/provisioning/dashboards"
while getopts ':htDv:j:M:S:B:P:s:R:F' option; do
	case "$option" in
	h)
		echo "$usage"
		exit
		;;
	t)
		TEST_ONLY=1
		;;
	v)
		VERSIONS=$OPTARG
		FORMAT_COMAND="$FORMAT_COMAND -v $OPTARG"
		;;
	M)
		MANAGER_VERSION=$OPTARG
		FORMAT_COMAND="$FORMAT_COMAND -M $OPTARG"
		;;
	F)
		FORCEUPDATE="1"
		;;
	P)
		PRODUCTS+=(-P)
		PRODUCTS+=($OPTARG)
		;;
	S)
		SPECIFIC_SOLUTION="$OPTARG"
		;;
	s)
		STACK="$OPTARG"
		BASE_DASHBOARD_DIR="grafana/stack/$OPTARG/provisioning/dashboards"
		;;
	D)
		VERSIONS=${SUPPORTED_VERSIONS[$BRANCH_VERSION]}
		FORMAT_COMAND="$FORMAT_COMAND -v $VERSIONS"
		MANAGER_VERSION=${MANAGER_SUPPORTED_VERSIONS[$BRANCH_VERSION]}
		;;
	R)
		DASHBOARD_REFRESH=$OPTARG
		;;
	B)
		BASE_DASHBOARD_DIR=$OPTARG
		;;
	j)
		GRAFANA_DASHBOARD_ARRAY+=("$OPTARG")
		FORMAT_COMAND="$FORMAT_COMAND -j $OPTARG"
		;;
	esac
done
if [[ -z "$TEST_ONLY" ]]; then
	mkdir -p grafana/build
fi

if [[ -z "$DASHBOARD_REFRESH" ]]; then
	DASHBOARD_REFRESH="5m"
fi

if [ "$DASHBOARD_REFRESH" = "0" ]; then
	DASHBOARD_REFRESH=""
fi
mkdir -p $BASE_DASHBOARD_DIR
rm -f $BASE_DASHBOARD_DIR/load.*.yaml

function set_loader {
    if [ "$4" = "" ]; then
        NAME=$1
    else
        NAME=$4
    fi
	sed "s/NAME/$NAME/" grafana/load.yaml | sed "s/FOLDER/$2/" | sed "s/VERSION/$3/" >"$BASE_DASHBOARD_DIR/load.$NAME.yaml"
}

IFS=','
for v in $VERSIONS; do

	if [ $v = "latest" ]; then
		if [ -z "$BRANCH_VERSION" ] || [ "$BRANCH_VERSION" = "master" ]; then
			echo "Default versions (-v latest) is not supported on the master branch, use specific version instead"
			exit 1
		fi
		v=${DEFAULT_VERSION[$BRANCH_VERSION]}
		echo "The use of -v latest is deprecated. Use a specific version instead."
	fi
	if [[ -z "$SPECIFIC_SOLUTION" ]]; then
		VERDIR_NAME="ver_$v"
	else
		VERDIR_NAME=$SPECIFIC_SOLUTION"_$v"
	fi

	VERDIR="grafana/build/$VERDIR_NAME"
	SUPPORTVERDIR="grafana/build/support/$VERDIR_NAME"
	if [[ -z "$TEST_ONLY" ]]; then
		mkdir -p $VERDIR
		if [ "$CLEAR_DASHBOARD" = "1" ]; then
		    rm -f $VERDIR/*.json
		fi
		if [ "$SUPPORT_DASHBOARD" = "1" ]; then
		  mkdir -p $SUPPORTVERDIR
		  if [ "$CLEAR_DASHBOARD" = "1" ]; then
            rm -f $SUPPORTVERDIR/*.json
          fi
		fi
	fi

	if [[ $VERSIONS = *","* ]]; then
		set_loader $v "$v" "$VERDIR_NAME"
	else
		set_loader $v "" "$VERDIR_NAME"
		if [ "$SUPPORT_DASHBOARD" = "1" ]; then
		  set_loader $v "support" "support\/$VERDIR_NAME" "$v.support"
		fi
	fi

	for f in "${DASHBOARDS[@]}"; do
		if [ -e grafana/$f.template.json ]; then
			if [ ! -f "$VERDIR/$f.$v.json" ] || [ "$VERDIR/$f.$v.json" -ot "grafana/$f.template.json" ] || [ ! -z "$FORCEUPDATE" ]; then
				if [[ -z "$TEST_ONLY" ]]; then
					echo "updating dashboard grafana/$f.$v.template.json"
					if [ -z "$SUPPORT_DASHBOARD" ] || [[  $f != "scylla-advanced"* ]]; then
					   ./make_dashboards.py ${PRODUCTS[@]} -af $VERDIR -t grafana/types.json -d grafana/$f.template.json -R "__MONITOR_VERSION__=$CURRENT_VERSION" -R "__SCYLLA_VERSION_DOT__=$v" -R "__MONITOR_BRANCH_VERSION=$BRANCH_VERSION" -R "__REFRESH_INTERVAL__=$DASHBOARD_REFRESH" --replace-file docs/source/reference/metrics.yaml -V $v
					else
					    ./make_dashboards.py ${PRODUCTS[@]} -af $SUPPORTVERDIR -t grafana/types.json -d grafana/$f.template.json -R "__MONITOR_VERSION__=$CURRENT_VERSION" -R "__SCYLLA_VERSION_DOT__=$v" -R "__MONITOR_BRANCH_VERSION=$BRANCH_VERSION" -R "__REFRESH_INTERVAL__=$DASHBOARD_REFRESH" --replace-file docs/source/reference/metrics.yaml -V $v
 				    fi
				fi
			fi
		else
			if [ -f grafana/$f.$v.json ]; then
				cp grafana/$f.$v.json $VERDIR
			fi
		fi
	done
done

IFS=','
for oring_v in $MANAGER_VERSION; do
	if [ -e grafana/scylla-manager.template.json ]; then
	    v=$(echo $oring_v | cut -d'.' -f1)
		VERDIR="grafana/build/manager_$v"
		mkdir -p $VERDIR
		set_loader "manager_$v" "" "manager_$v"
		if [ ! -f "$VERDIR/scylla-manager.$v.json" ] || [ "$VERDIR/scylla-manager.$v.json" -ot "grafana/scylla-manager.template.json" ] || [ "$VERDIR/scylla-manager.$v.json" -ot "grafana/types.json" ] || [ ! -z "$FORCEUPDATE" ]; then
			if [[ -z "$TEST_ONLY" ]]; then
				echo "updating grafana/scylla-manager.$v.template.json"
				./make_dashboards.py ${PRODUCTS[@]} -af $VERDIR -t grafana/types.json -d grafana/scylla-manager.template.json -R "__MONITOR_VERSION__=$CURRENT_VERSION" -R "__SCYLLA_VERSION_DOT__=$v" -R "__MONITOR_BRANCH_VERSION=$BRANCH_VERSION" -R "__REFRESH_INTERVAL__=$DASHBOARD_REFRESH" --replace-file docs/source/reference/metrics.yaml -V $v
			else
				echo "notice: grafana/scylla-manager.template.json was updated, run ./generate-dashboards.sh $FORMAT_COMAND"
			fi
		fi
	fi
done

if [ "$VECTOR_STORE" != "" ]; then
    if [ -e grafana/scylla-vector-store.template.json ]; then
        oring_v=$VECTOR_VERSION
        v=$(echo $oring_v | cut -d'.' -f1)
        VERDIR="grafana/build/vector_$v"
        mkdir -p $VERDIR
        set_loader "vector_$v" "" "vector_$v"
        if [ ! -f "$VERDIR/scylla-vector-store.$v.json" ] || [ "$VERDIR/scylla-vector-store.$v.json" -ot "grafana/scylla-vector-store.template.json" ] || [ "$VERDIR/scylla-vector-store.$v.json" -ot "grafana/types.json" ] || [ ! -z "$FORCEUPDATE" ]; then
            if [[ -z "$TEST_ONLY" ]]; then
                echo "updating grafana/scylla-vector-store.$v.template.json"
                ./make_dashboards.py ${PRODUCTS[@]} -af $VERDIR -t grafana/types.json -d grafana/scylla-vector-store.template.json -R "__MONITOR_VERSION__=$CURRENT_VERSION" -R "__SCYLLA_VERSION_DOT__=$v" -R "__MONITOR_BRANCH_VERSION=$BRANCH_VERSION" -R "__REFRESH_INTERVAL__=$DASHBOARD_REFRESH" --replace-file docs/source/reference/metrics.yaml -V $v
            else
                echo "notice: grafana/scylla-vector-store.template.json was updated, run ./generate-dashboards.sh $FORMAT_COMAND"
            fi
        fi
    fi
fi
for val in "${GRAFANA_DASHBOARD_ARRAY[@]}"; do
	VERDIR="grafana/build/default"
	set_loader "default" "" "default"
	mkdir -p $VERDIR
	if [[ $val == *".template.json" ]]; then
		val1=${val::-14}
		val1=${val1:8}
		if [ ! -f $VERDIR/$val1.json ] || [ $VERDIR/$val1.json -ot $val ] || [ ! -z "$FORCEUPDATE" ]; then
			if [[ -z "$TEST_ONLY" ]]; then
				echo "updating $val"
				./make_dashboards.py ${PRODUCTS[@]} -af $VERDIR -t grafana/types.json -d $val -R "__MONITOR_VERSION__=$CURRENT_VERSION" -R "__MONITOR_BRANCH_VERSION=$BRANCH_VERSION" --replace-file docs/source/reference/metrics.yaml
			fi
		fi
	else
		cp $val $VERDIR
	fi
done
