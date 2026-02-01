#!/usr/bin/env bash
# Description: Run a safe apt update and simulate an upgrade without installing.
# Usage: apt-dry-upgrade.sh
# Notes: Uses sudo for apt update; apt-get -s upgrade performs a dry-run.
set -e
sudo apt update
sudo apt-get -s upgrade
