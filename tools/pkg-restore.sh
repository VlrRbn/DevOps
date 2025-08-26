#!/usr/bin/env bash
set -e
[ -f packages.list ] || { echo "packages.list not found"; exit 1; }
sudo apt update
sudo dpkg --set-selections < packages.list
sudo apt-get -y dselect-upgrade
