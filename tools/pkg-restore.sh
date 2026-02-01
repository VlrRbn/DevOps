#!/usr/bin/env bash
# Description: Restore package selections from packages.list and apply them.
# Usage: pkg-restore.sh
# Notes: Uses dpkg selections and apt-get dselect-upgrade.
set -e
[ -f packages.list ] || { echo "packages.list not found"; exit 1; }
sudo apt update
sudo dpkg --set-selections < packages.list
sudo apt-get -y dselect-upgrade
