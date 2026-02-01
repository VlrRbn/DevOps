#!/usr/bin/env bash
# Description: Snapshot installed packages to packages.list and packages_table.txt.
# Usage: pkg-snapshot.sh
# Output: packages.list (for restore) and packages_table.txt (human-readable).
set -e
dpkg --get-selections > packages.list
dpkg -l > packages_table.txt
echo "Saved: packages.list (for restore) and packages_table.txt (human-readable)."
