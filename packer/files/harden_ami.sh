#!/usr/bin/bash
# CIS-level hardening is applied separately by apply_cis_rules.
set -eu

sudo apt-get purge -y unattended-upgrades update-notifier-common apport fwupd-signed modemmanager motd-news-config postfix snapd || true
sudo apt-get autoremove -y --purge || true

sudo systemctl mask apt-daily.timer apt-daily-upgrade.timer motd-news.timer unattended-upgrades.service || true
