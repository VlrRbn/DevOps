#!/usr/bin/env bash
set -e
dpkg --get-selections > packages.list
dpkg -l > packages_table.txt
echo "Saved: packages.list (for restore) and packages_table.txt (human-readable)."
