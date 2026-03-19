#!/usr/bin/env bash
# Description: Quick boot-health checks for run state, failed units, and mount metadata.
# Usage: boot-health-check.sh [--strict]
set -Eeuo pipefail

usage() {
  cat <<'USAGE'
Usage:
  boot-health-check.sh [--strict]

Examples:
  ./lessons/13-boot-recovery-troubleshooting/scripts/boot-health-check.sh
  ./lessons/13-boot-recovery-troubleshooting/scripts/boot-health-check.sh --strict
USAGE
}

STRICT=0

# Parse supported flags.
for arg in "$@"; do
  case "$arg" in
    -h|--help)
      usage
      exit 0
      ;;
    --strict)
      STRICT=1
      ;;
    *)
      echo "ERROR: unknown argument: $arg" >&2
      usage
      exit 2
      ;;
  esac
done

# Validate required commands before checks.
for cmd in systemctl findmnt df awk; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: missing command: $cmd" >&2; exit 1; }
done

warn=0
# Collect high-level boot health indicators.
run_state="$(systemctl is-system-running 2>/dev/null || echo unknown)"
failed_count="$(systemctl list-units --failed --no-legend --plain 2>/dev/null | awk 'NF{c++} END{print c+0}')"

findmnt_rc=0
findmnt_msg="ok"
if ! findmnt_msg="$(findmnt --verify 2>&1)"; then
  findmnt_rc=$?
fi

root_use_pct="$(df --output=pcent / | tail -n1 | tr -dc '0-9')"
root_use_pct="${root_use_pct:-0}"

# Print concise check summary first.
echo "[CHECK] system state: $run_state"
echo "[CHECK] failed units: $failed_count"
echo "[CHECK] findmnt verify rc: $findmnt_rc"
echo "[CHECK] rootfs use: ${root_use_pct}%"

if [[ "$run_state" == "degraded" || "$run_state" == "maintenance" || "$run_state" == "offline" ]]; then
  echo "[WARN] system state is not healthy: $run_state"
  warn=1
fi

if (( failed_count > 0 )); then
  echo "[WARN] failed units detected"
  systemctl list-units --failed --no-pager --plain || true
  warn=1
fi

if (( findmnt_rc != 0 )); then
  echo "[WARN] findmnt --verify reported problems"
  printf '%s\n' "$findmnt_msg"
  warn=1
fi

if (( root_use_pct >= 90 )); then
  echo "[WARN] root filesystem usage is high (${root_use_pct}%)"
  warn=1
fi

# In strict mode any warning should fail CI/automation pipelines.
if (( STRICT && warn )); then
  echo "[FAIL] strict mode found issues" >&2
  exit 1
fi

echo "[OK] boot health check completed"
