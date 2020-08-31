#!/usr/bin/env bash

if [  $# -eq 0 ]; then
   echo "usage: make-release.sh version"
   exit 0
fi

git checkout -b release-$1
yarn build
git add -f dist
git commit -m "Release v$1"
git push origin release-$1
zip scylla-grafana-datasource-$1.src.zip . -r -x "node_modules/*" -x ".git/*"
