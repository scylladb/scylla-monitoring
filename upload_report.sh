#!/usr/bin/bash

function usage {
  __usage="Usage: $(basename $0) [OPTIONS]

Options:
  -h print this help and exit
  -v Verbose mode
  -u set the uuid from command line
  -D docker name if not set assume aprom
  -k keep the directory after upload
  -d take files directly from a directory - for standalone 
  -t the tmp directory to use, default is /tmp

The script will copy Prometheus local metrics and will upload them.
Metrics does not contain internal data.
By default the script will use /tmp partition and will delete the directory when completed
"
  echo "$__usage"
}

VERBOSE=""
DOCKER="aprom"

while getopts ':hvku:d:D:t:' option; do
  case "$option" in
    h) usage
       exit
       ;;
    D) DOCKER=$OPTARG
       ;;
    d) DIR=$OPTARG
       ;;
    u) UPLOADID=$OPTARG
       ;;
    t) TMPDIR=$OPTARG
       ;;
    k) KEEP=1
       ;;
    v) VERBOSE="-v"
       ;;
    
    \?) printf "illegal option: -%s\n" "$OPTARG" >&2
       usage >&2
       exit 1
       ;;
  esac
done

if [ -z "$UPLOADID" ]; then
    UPLOADID=$(uuidgen)
fi
if [ -z "$TMPDIR" ]; then
    TMPDIR=$(mktemp -d -t prom-data-XXXXXXXXXX)
else
    mkdir -p $TMPDIR
    TMPDIR="$TMPDIR/$UPLOADID"
    mkdir $DEST_DIR || { echo 'make sure the directory does not exists' $DEST_DIR  ; exit 1; }
fi

NEED_SIZE=`docker exec aprom du -s /prometheus|awk '{print $1}'`
SIZE=`df -P -k $TMPDIR |grep -v Filesystem |awk '{print $4}'`

# Add 10M for the needed size
NEED_SIZE=$(( NEED_SIZE + 10000))
if [ $NEED_SIZE -gt $SIZE ]; then
    echo "Not enough diskspace, " $NEED_SIZE " is needed" $SIZE "is available"
    exit 1
fi
if [ -z "$DIR" ]; then
    docker cp -a $DOCKER:/prometheus  - |gzip -9 > $TMPDIR/prometheus_data.tar.gz
#    tar $VERBOSE -zcf $TMPDIR/prometheus_data.tar.gz -C $DEST_DIR --remove-files .
else
    tar $VERBOSE -zcf $TMPDIR/prometheus_data.tar.gz $DIR
fi
curl -X PUT http://upload.scylladb.com/$UPLOADID/prometheus_data.tar.gz -T $TMPDIR/prometheus_data.tar.gz

echo "Files were uploaded with UUID " $UPLOADID "include it in your ticket/issue"

if [ -z "$KEEP" ];  then
    rm -rf $TMPDIR
else
    echo "uploaded data can be found at $TMPDIR"
fi