#!/bin/sh -e

ORIGIN="https://github.com/scylladb/scylla-monitoring.git"
BUILD="_build/dirhtml"

# Make a git repo for the built pages
rm -rf _build/dirhtml/.git
(cd $BUILD && git init && git checkout -b gh-pages)

# Set up Git and GitHub Pages for the built pages repo
cp .git/config _build/dirhtml/.git
cp CNAME _build/dirhtml/

# Commit and push
(cd $BUILD && git add . && git commit -a -m "scripted deploy, will be overwritten")
(cd $BUILD && git push -f $ORIGIN gh-pages)
