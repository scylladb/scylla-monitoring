#!/usr/bin/env bash
#
# Delete Scylla Monitor cloud images (AWS AMIs + their snapshots, GCP images)
# by image name. Dry run by default; pass --delete to actually remove them.
#
# Usage:
#   ./delete_cloud_images.sh --name <image-name> [--cloud aws|gcp|all] [--delete]
#
# The name is the packer `monitor_image_name`, e.g.
#   scylladb-monitor-4-16-0-rc0-2026-06-28t11-42-58z
# A trailing '*' is allowed to match several builds, e.g.
#   scylladb-monitor-4-16-0-rc*
#
# AWS regions and the GCP project are read from scylla-monitor-template.json,
# so the script always covers the same regions the build copies AMIs to.
# Only AMIs owned by the current AWS account are considered.

set -euo pipefail

cd "$(dirname "$0")"
TEMPLATE=scylla-monitor-template.json

NAME=""
CLOUD="all"
MODE="dry-run"

usage() { sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --name)   NAME="$2"; shift 2 ;;
    --cloud)  CLOUD="$2"; shift 2 ;;
    --delete) MODE="delete"; shift ;;
    --dry-run) MODE="dry-run"; shift ;;
    -h|--help) usage ;;
    *) echo "unknown argument: $1" >&2; usage 1 ;;
  esac
done

[ -n "$NAME" ] || { echo "--name is required" >&2; usage 1; }
case "$CLOUD" in aws|gcp|all) ;; *) echo "--cloud must be aws, gcp or all" >&2; exit 1 ;; esac
case "$NAME" in
  scylladb-monitor-*) ;;
  *) echo "refusing: name must start with 'scylladb-monitor-' (got '$NAME')" >&2; exit 1 ;;
esac

echo "mode:  $MODE"
echo "name:  $NAME"
echo "cloud: $CLOUD"
echo

MATCHES="$(mktemp)"
trap 'rm -f "$MATCHES"' EXIT

delete_aws() {
  local regions
  regions="$(jq -r '.variables.aws_region, .variables.aws_ami_regions' "$TEMPLATE" | tr ',' '\n' | sort -u)"
  echo "### AWS (account $(aws sts get-caller-identity --query Account --output text))"
  for r in $regions; do
    aws ec2 describe-images --region "$r" --owners self \
      --filters "Name=name,Values=$NAME" \
      --query 'Images[].[ImageId,Name,BlockDeviceMappings[].Ebs.SnapshotId|join(`,`,@)]' \
      --output text |
    while read -r ami name snaps; do
      [ -n "$ami" ] || continue
      echo "$r  $ami  $name  snapshots=$snaps" | tee -a "$MATCHES"
      if [ "$MODE" = "delete" ]; then
        aws ec2 deregister-image --region "$r" --image-id "$ami"
        for s in ${snaps//,/ }; do
          aws ec2 delete-snapshot --region "$r" --snapshot-id "$s"
        done
        echo "$r  $ami  deleted"
      fi
    done
  done
  echo
}

delete_gcp() {
  local project regex
  project="$(jq -r '.variables.gcp_project_id' "$TEMPLATE")"
  regex="^$(printf '%s' "$NAME" | sed 's/[.]/\\./g; s/\*/.*/g')$"
  echo "### GCP (project $project)"
  gcloud compute images list --project "$project" --no-standard-images \
    --filter="name~$regex" --format="value(name)" |
  while read -r img; do
    [ -n "$img" ] || continue
    echo "$project  $img" | tee -a "$MATCHES"
    if [ "$MODE" = "delete" ]; then
      gcloud compute images delete --project "$project" --quiet "$img"
      echo "$project  $img  deleted"
    fi
  done
  echo
}

[ "$CLOUD" = "gcp" ] || delete_aws
[ "$CLOUD" = "aws" ] || delete_gcp

COUNT=$(wc -l < "$MATCHES")
if [ "$COUNT" -eq 0 ]; then
  echo "No images matched '$NAME'."
elif [ "$MODE" = "dry-run" ]; then
  echo "Dry run only - $COUNT image(s) matched, nothing was deleted. Re-run with --delete to remove them."
else
  echo "Deleted $COUNT image(s)."
fi
